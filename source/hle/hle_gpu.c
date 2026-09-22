/*
 * hle_gpu.c - High-Level Emulation (HLE) module for PSX GPU
 * xenolift project - pure C17, cleanly separable GP0/GP1 command interpreter
 *
 * References:
 * - psx-spx (Martin Korth): GPU command table, texture pages, blending
 * - Nocash PSX Hardware Specification (GPU section)
 */

#include "receipt_xprintf.h" /* R985 */
#include <stdio.h> /* R230: Mac clang errors on implicit printf (cycle-16 dead cycle) */
#include "hle_gpu.h"
#include <string.h>
#include <stdlib.h>

/* R982 (b8-c92, WARDEN - HLE PRINT-DOOR SWEEP, kills the fprintf crash
 * class at its real source): c89/90/92 died identically - __stack_chk_fail
 * via __xvprintf <- vfprintf_l <- fprintf, PC attributed to real_main
 * (offset moved 2146139->2146123 as runtime.c edits shifted statics; the
 * call sites are THIS module's static fns placed after real_main with no
 * symbol - disassembly of rt.o proved runtime.c itself has ZERO fprintf/
 * printf calls). The HLE modules' raw fprintf(stderr)/hle_out() calls fire
 * on every recovery/reset (census receipts in every EXITTAIL) and a signal
 * landing mid-vfprintf smashes the canary - the class R977 killed at
 * r861_out's door, R981 killed at printf's door; these are the remaining
 * doors. Mechanical conversion: single-flight guarded printer (vsnprintf
 * into a local buffer + ONE raw write(2) - async-signal-safe, no FILE
 * machinery, nested calls drop like R977). Output moves to stderr for the
 * former hle_out() sites: cosmetic only, all receipts read stderr. */
#include <stdarg.h>
#include <unistd.h>
static void hle_out(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
static void hle_out(const char *fmt, ...)
{
    static int r982_in;
    char b[1024];
    va_list ap;
    int n;
    if (r982_in) return;
    r982_in = 1;
    va_start(ap, fmt);
    n = xl_format(b, (int)sizeof b, fmt, ap); /* R985: vprintf-free */
    va_end(ap);
    r982_in = 0;
    if (n > 0) {
        if (n > (int)sizeof b - 1) n = (int)sizeof b - 1;
        (void)!write(2, b, (size_t)n);
    }
}


/* Internal State */
uint16_t g_vram[GPU_VRAM_HEIGHT][GPU_VRAM_WIDTH]; /* R694: exposed - runtime screen sampler + live viewer alias this (single canvas) */
static uint32_t g_gpu_stat = 0x14802000u;
static uint32_t g_read_latch = 0;

static uint16_t g_disp_x = 0, g_disp_y = 0;
static uint16_t g_disp_w = 320, g_disp_h = 240;

static uint16_t g_draw_x1 = 0, g_draw_y1 = 0;
static uint16_t g_draw_x2 = 1023, g_draw_y2 = 511;
static int16_t  g_draw_offset_x = 0, g_draw_offset_y = 0;

static uint16_t g_texpage = 0;
static uint16_t g_clut = 0;
static uint32_t g_texwindow = 0;
static uint8_t  g_mask_set = 0;
static uint8_t  g_mask_check = 0;

/* GP0 Command Processing State */
typedef enum {
    GP0_STATE_IDLE = 0,
    GP0_STATE_A0_HEADER1,
    GP0_STATE_A0_HEADER2,
    GP0_STATE_A0_DATA,
    GP0_STATE_ACCUMULATE
} gp0_state_t;

static gp0_state_t g_gp0_state = GP0_STATE_IDLE;
static uint32_t g_blit_x = 0, g_blit_y = 0, g_blit_w = 0, g_blit_h = 0, g_blit_left = 0;

static uint32_t g_cmd_buf[16];
static int g_cmd_words_got = 0;
static int g_cmd_words_total = 0;

typedef struct {
    int16_t x, y;
    uint8_t u, v;
    uint8_t r, g, b;
} vertex_t;

/* Forward Declarations */
static void exec_fill(void);
static void exec_copy(void);
static void exec_rect(void);
static void exec_poly(void);
static void exec_line(void);
static void exec_env_cmd(uint32_t v);
static int get_cmd_word_count(uint32_t w0);
static void exec_cmd_buf(void);

/*
 * SPEC-ASSUMPTION: PSX semi-transparency modes 0-3 (ABR):
 * Mode 0: 0.5 * Back + 0.5 * Front
 * Mode 1: 1.0 * Back + 1.0 * Front (clamped to 31)
 * Mode 2: 1.0 * Back - 1.0 * Front (clamped to 0)
 * Mode 3: 1.0 * Back + 0.25 * Front (clamped to 31)
 * Mode 4: Opaque (Front)
 */
static inline uint16_t gpu_blend_pixel(uint16_t back, uint16_t front, int mode)
{
    int rb = back & 0x1F, gb = (back >> 5) & 0x1F, bb = (back >> 10) & 0x1F;
    int rf = front & 0x1F, gf = (front >> 5) & 0x1F, bf = (front >> 10) & 0x1F;
    int r = rf, g = gf, b = bf;

    switch (mode) {
    case 0:
        r = (rb + rf) >> 1;
        g = (gb + gf) >> 1;
        b = (bb + bf) >> 1;
        break;
    case 1:
        r = rb + rf; if (r > 31) r = 31;
        g = gb + gf; if (g > 31) g = 31;
        b = bb + bf; if (b > 31) b = 31;
        break;
    case 2:
        r = rb - rf; if (r < 0) r = 0;
        g = gb - gf; if (g < 0) g = 0;
        b = bb - bf; if (b < 0) b = 0;
        break;
    case 3:
        r = rb + (rf >> 2); if (r > 31) r = 31;
        g = gb + (gf >> 2); if (g > 31) g = 31;
        b = bb + (bf >> 2); if (b > 31) b = 31;
        break;
    default:
        break;
    }
    return (uint16_t)(r | (g << 5) | (b << 10) | (front & 0x8000));
}

/*
 * SPEC-ASSUMPTION: Texture window mask & offset logic follows nocash PSX-SPX spec.
 * Palette index 0 in 4bpp/8bpp textures is treated as transparent (skipped).
 */
static uint16_t sample_texture(int u, int v, uint16_t texpage, uint16_t clut, uint32_t texwindow)
{
    uint32_t tw_mask_x = (texwindow & 0x1Fu) * 8u;
    uint32_t tw_mask_y = ((texwindow >> 5) & 0x1Fu) * 8u;
    uint32_t tw_off_x  = ((texwindow >> 10) & 0x1Fu) * 8u;
    uint32_t tw_off_y  = ((texwindow >> 15) & 0x1Fu) * 8u;

    int u_eff = (u & ~(int)tw_mask_x) | ((int)tw_off_x & (int)tw_mask_x);
    int v_eff = (v & ~(int)tw_mask_y) | ((int)tw_off_y & (int)tw_mask_y);

    int page_x = (texpage & 0x0Fu) * 64;
    int page_y = ((texpage >> 4) & 1u) * 256;
    int tp_depth = (texpage >> 7) & 3u;

    int clut_x = (clut & 0x3Fu) * 16;
    int clut_y = (clut >> 6) & 0x1FFu;

    if (tp_depth == 0) {
        /* 4bpp CLUT */
        int tx = (page_x + u_eff / 4) & 0x3FF;
        int ty = (page_y + v_eff) & 0x1FF;
        uint16_t word = g_vram[ty][tx];
        int shift = (u_eff % 4) * 4;
        uint8_t index = (word >> shift) & 0x0Fu;
        if (index == 0) return 0;
        return g_vram[clut_y & 0x1FF][(clut_x + index) & 0x3FF];
    } else if (tp_depth == 1) {
        /* 8bpp CLUT */
        int tx = (page_x + u_eff / 2) & 0x3FF;
        int ty = (page_y + v_eff) & 0x1FF;
        uint16_t word = g_vram[ty][tx];
        uint8_t index = (u_eff % 2) ? (word >> 8) : (word & 0xFFu);
        if (index == 0) return 0;
        return g_vram[clut_y & 0x1FF][(clut_x + index) & 0x3FF];
    } else {
        /* 15bpp Direct BGR555 */
        int tx = (page_x + u_eff) & 0x3FF;
        int ty = (page_y + v_eff) & 0x1FF;
        uint16_t word = g_vram[ty][tx];
        if (word == 0) return 0;
        return word;
    }
}

/*
 * Triangle Barycentric Rasterizer
 * Handles flat/Gouraud shading, raw/modulated texturing, and semi-transparency.
 */
static void rasterize_triangle(vertex_t p0, vertex_t p1, vertex_t p2,
                               int is_textured, int is_gouraud, int is_semi_trans, int is_raw_tex,
                               int abr_mode, uint16_t clut, uint16_t texpage)
{
    int min_x = p0.x < p1.x ? (p0.x < p2.x ? p0.x : p2.x) : (p1.x < p2.x ? p1.x : p2.x);
    int max_x = p0.x > p1.x ? (p0.x > p2.x ? p0.x : p2.x) : (p1.x > p2.x ? p1.x : p2.x);
    int min_y = p0.y < p1.y ? (p0.y < p2.y ? p0.y : p2.y) : (p1.y < p2.y ? p1.y : p2.y);
    int max_y = p0.y > p1.y ? (p0.y > p2.y ? p0.y : p2.y) : (p1.y > p2.y ? p1.y : p2.y);

    if (min_x < g_draw_x1) min_x = g_draw_x1;
    if (max_x > g_draw_x2) max_x = g_draw_x2;
    if (min_y < g_draw_y1) min_y = g_draw_y1;
    if (max_y > g_draw_y2) max_y = g_draw_y2;

    if (min_x < 0) min_x = 0;
    if (max_x >= GPU_VRAM_WIDTH) max_x = GPU_VRAM_WIDTH - 1;
    if (min_y < 0) min_y = 0;
    if (max_y >= GPU_VRAM_HEIGHT) max_y = GPU_VRAM_HEIGHT - 1;

    if (min_x > max_x || min_y > max_y) return;

    float det = (float)((p1.y - p2.y)*(p0.x - p2.x) + (p2.x - p1.x)*(p0.y - p2.y));
    if (det >= -0.0001f && det <= 0.0001f) return;
    float inv_det = 1.0f / det;

    for (int y = min_y; y <= max_y; y++) {
        for (int x = min_x; x <= max_x; x++) {
            float w0 = ((p1.y - p2.y)*(x - p2.x) + (p2.x - p1.x)*(y - p2.y)) * inv_det;
            float w1 = ((p2.y - p0.y)*(x - p2.x) + (p0.x - p2.x)*(y - p2.y)) * inv_det;
            float w2 = 1.0f - w0 - w1;

            if (w0 < -0.001f || w1 < -0.001f || w2 < -0.001f) continue;

            uint8_t r, g, b;
            if (is_gouraud) {
                int ir = (int)(w0 * p0.r + w1 * p1.r + w2 * p2.r);
                int ig = (int)(w0 * p0.g + w1 * p1.g + w2 * p2.g);
                int ib = (int)(w0 * p0.b + w1 * p1.b + w2 * p2.b);
                r = (ir < 0) ? 0 : (ir > 255 ? 255 : ir);
                g = (ig < 0) ? 0 : (ig > 255 ? 255 : ig);
                b = (ib < 0) ? 0 : (ib > 255 ? 255 : ib);
            } else {
                r = p0.r; g = p0.g; b = p0.b;
            }

            uint16_t front_color;
            if (is_textured) {
                int u = (int)(w0 * p0.u + w1 * p1.u + w2 * p2.u);
                int v = (int)(w0 * p0.v + w1 * p1.v + w2 * p2.v);
                uint16_t tex_color = sample_texture(u, v, texpage, clut, g_texwindow);
                if (tex_color == 0) continue;

                if (is_raw_tex) {
                    front_color = tex_color & 0x7FFF;
                } else {
                    /* SPEC-ASSUMPTION: 8-bit polygon color modulates 5-bit texture color via division by 128 */
                    int tr = tex_color & 0x1F, tg = (tex_color >> 5) & 0x1F, tb = (tex_color >> 10) & 0x1F;
                    int fr = (tr * r) / 128; if (fr > 31) fr = 31;
                    int fg = (tg * g) / 128; if (fg > 31) fg = 31;
                    int fb = (tb * b) / 128; if (fb > 31) fb = 31;
                    front_color = (uint16_t)((fb << 10) | (fg << 5) | fr);
                }
            } else {
                front_color = (uint16_t)(((b >> 3) << 10) | ((g >> 3) << 5) | (r >> 3));
            }

            if (is_semi_trans) {
                g_vram[y][x] = gpu_blend_pixel(g_vram[y][x], front_color, abr_mode);
            } else {
                g_vram[y][x] = front_color;
            }
        }
    }
}

/* GP0 Command Implementations */
uint32_t g_cls_vram_writes; /* R940: exec-time paint counter */

static void exec_fill(void)
{
    uint32_t color24 = g_cmd_buf[0] & 0x00FFFFFFu;
    uint16_t r = color24 & 0xFFu;
    uint16_t g = (color24 >> 8) & 0xFFu;
    uint16_t b = (color24 >> 16) & 0xFFu;
    uint16_t c15 = (uint16_t)(((b >> 3) << 10) | ((g >> 3) << 5) | (r >> 3));

    uint32_t x = g_cmd_buf[1] & 0x3F0u;
    uint32_t y = (g_cmd_buf[1] >> 16) & 0x1FFu;
    uint32_t w = g_cmd_buf[2] & 0x3FFu;
    uint32_t h = (g_cmd_buf[2] >> 16) & 0x1FFu;

    if (!w) w = 1024u;
    if (!h) h = 512u;

    for (uint32_t dy = 0; dy < h; dy++) {
        uint32_t py = (y + dy) & 0x1FFu;
        for (uint32_t dx = 0; dx < w; dx++) {
            uint32_t px = (x + dx) & 0x3FFu;
            g_vram[py][px] = c15;
            g_cls_vram_writes++; /* R940 */
        }
    }
}

static void exec_copy(void)
{
    uint32_t sx = g_cmd_buf[1] & 0x3FFu;
    uint32_t sy = (g_cmd_buf[1] >> 16) & 0x1FFu;
    uint32_t dx = g_cmd_buf[2] & 0x3FFu;
    uint32_t dy = (g_cmd_buf[2] >> 16) & 0x1FFu;
    uint32_t w = g_cmd_buf[3] & 0x3FFu;
    uint32_t h = (g_cmd_buf[3] >> 16) & 0x1FFu;

    if (!w) w = 1024u;
    if (!h) h = 512u;

    for (uint32_t row = 0; row < h; row++) {
        uint32_t spy = (sy + row) & 0x1FFu;
        uint32_t dpy = (dy + row) & 0x1FFu;
        for (uint32_t col = 0; col < w; col++) {
            uint32_t spx = (sx + col) & 0x3FFu;
            uint32_t dpx = (dx + col) & 0x3FFu;
            g_vram[dpy][dpx] = g_vram[spy][spx];
        }
    }
}

static void exec_rect(void)
{
    uint32_t w0 = g_cmd_buf[0];
    uint32_t cmd = (w0 >> 24) & 0xFFu;
    /* R228: psx-spx-verified rect layout. Rects 0x60-0x7F: bit2 = textured,
     * bit1 = semi-transparent, bit0 = raw-texture. The old code had textured
     * and semi SWAPPED (borrowed the wrong bit layout) and raw hardcoded on
     * — 0x72 (mono 8x8 semi) parsed as TEXTURED (ate a phantom UV word),
     * 0x74 (textured 8x8 blend) parsed as UNTEXTURED: every rect misparsed
     * and the DMA packet stream desynced at the first textured rect. */
    int is_textured   = (cmd & 0x04u) != 0;
    int is_semi_trans = (cmd & 0x02u) != 0;
    int is_raw_tex    = (cmd & 0x01u) != 0;
    int size_code     = (w0 >> 27) & 3u; /* var=0 1x1=1 8x8=2 16x16=3 (from cmd bits 4-5) */

    uint8_t r = w0 & 0xFFu;
    uint8_t g = (w0 >> 8) & 0xFFu;
    uint8_t b = (w0 >> 16) & 0xFFu;

    int16_t rx = (int16_t)(g_cmd_buf[1] & 0xFFFFu);
    int16_t ry = (int16_t)(g_cmd_buf[1] >> 16);

    uint8_t u = 0, v = 0;
    uint16_t clut = g_clut;
    int idx = 2;

    if (is_textured) {
        uint32_t uv_word = g_cmd_buf[idx++];
        u = uv_word & 0xFFu;
        v = (uv_word >> 8) & 0xFFu;
        clut = (uv_word >> 16) & 0xFFFFu;
    }

    uint16_t w = 0, h = 0;
    if (size_code == 0) {
        uint32_t wh_word = g_cmd_buf[idx++];
        w = wh_word & 0xFFFFu;
        h = wh_word >> 16;
    } else if (size_code == 1) {
        w = 1; h = 1;
    } else if (size_code == 2) {
        w = 8; h = 8;
    } else if (size_code == 3) {
        w = 16; h = 16;
    }

    int x0 = rx + g_draw_offset_x;
    int y0 = ry + g_draw_offset_y;
    int abr_mode = (g_texpage >> 5) & 3;

    {   /* R228: bounded rect-dispatch log — surfaces in the =GPU= digest so
         * the Mac run proves the fixed path executes with correct lengths */
        static uint32_t rect_n;
        rect_n++;
        /* R368: hard cap - the title-era render loop submits 4.48M 8x8 rects
         * (cycle 124); every-500th sampling still printed ~9k lines */
        if (rect_n <= 40u)
            hle_out("[gpu] rect #%u cmd=0x%02X %s%s%s %dx%d @(%d,%d) w=%u h=%u\n",
                   rect_n, cmd,
                   is_textured ? "tex " : "mono ",
                   is_semi_trans ? "semi" : "opaque",
                   is_raw_tex ? " raw" : "",
                   size_code == 0 ? -1 : (size_code == 1 ? 1 : (size_code == 2 ? 8 : 16)),
                   size_code == 0 ? -1 : (size_code == 1 ? 1 : (size_code == 2 ? 8 : 16)),
                   x0, y0, w, h);
    }

    for (int dy = 0; dy < h; dy++) {
        int py = y0 + dy;
        if (py < g_draw_y1 || py > g_draw_y2 || py < 0 || py >= GPU_VRAM_HEIGHT) continue;
        for (int dx = 0; dx < w; dx++) {
            int px = x0 + dx;
            if (px < g_draw_x1 || px > g_draw_x2 || px < 0 || px >= GPU_VRAM_WIDTH) continue;

            uint16_t front_color;
            if (is_textured) {
                uint16_t tex_color = sample_texture(u + dx, v + dy, g_texpage, clut, g_texwindow);
                if (tex_color == 0) continue;

                if (is_raw_tex) {
                    front_color = tex_color & 0x7FFF;
                } else {
                    int tr = tex_color & 0x1F, tg = (tex_color >> 5) & 0x1F, tb = (tex_color >> 10) & 0x1F;
                    int fr = (tr * r) / 128; if (fr > 31) fr = 31;
                    int fg = (tg * g) / 128; if (fg > 31) fg = 31;
                    int fb = (tb * b) / 128; if (fb > 31) fb = 31;
                    front_color = (uint16_t)((fb << 10) | (fg << 5) | fr);
                }
            } else {
                front_color = (uint16_t)(((b >> 3) << 10) | ((g >> 3) << 5) | (r >> 3));
            }

            if (is_semi_trans) {
                g_vram[py][px] = gpu_blend_pixel(g_vram[py][px], front_color, abr_mode);
            } else {
                g_vram[py][px] = front_color;
            }
        }
    }
}

static void exec_poly(void)
{
    uint32_t w0 = g_cmd_buf[0];
    uint32_t cmd = (w0 >> 24) & 0xFFu;

    /* R228: psx-spx-verified polygon layout: bit4=gouraud bit3=quad
     * bit2=textured bit1=semi bit0=raw. Old code: textured/semi swapped,
     * raw = dead byte-shift test (always 1 = everything rendered raw). */
    int is_quad       = (cmd & 0x08u) != 0;
    int is_gouraud    = (cmd & 0x10u) != 0;
    int is_textured   = (cmd & 0x04u) != 0;
    int is_semi_trans = (cmd & 0x02u) != 0;
    int is_raw_tex    = (cmd & 0x01u) != 0;

    vertex_t verts[4];
    uint16_t clut = g_clut;
    uint16_t texpage = g_texpage;

    uint8_t r0 = w0 & 0xFFu, g0 = (w0 >> 8) & 0xFFu, b0 = (w0 >> 16) & 0xFFu;

    int idx = 1;
    int num_verts = is_quad ? 4 : 3;

    for (int i = 0; i < num_verts; i++) {
        if (i == 0) {
            verts[i].r = r0; verts[i].g = g0; verts[i].b = b0;
        } else if (is_gouraud) {
            uint32_t cw = g_cmd_buf[idx++];
            verts[i].r = cw & 0xFFu;
            verts[i].g = (cw >> 8) & 0xFFu;
            verts[i].b = (cw >> 16) & 0xFFu;
        } else {
            verts[i].r = r0; verts[i].g = g0; verts[i].b = b0;
        }

        uint32_t pos_w = g_cmd_buf[idx++];
        verts[i].x = (int16_t)(pos_w & 0xFFFFu) + g_draw_offset_x;
        verts[i].y = (int16_t)(pos_w >> 16) + g_draw_offset_y;

        if (is_textured) {
            uint32_t uv_w = g_cmd_buf[idx++];
            verts[i].u = uv_w & 0xFFu;
            verts[i].v = (uv_w >> 8) & 0xFFu;
            if (i == 0) clut = (uv_w >> 16) & 0xFFFFu;
            if (i == 1) texpage = (uv_w >> 16) & 0xFFFFu;
        } else {
            verts[i].u = 0; verts[i].v = 0;
        }
    }

    g_texpage = texpage;
    int abr_mode = (texpage >> 5) & 3;

    rasterize_triangle(verts[0], verts[1], verts[2],
                       is_textured, is_gouraud, is_semi_trans, is_raw_tex,
                       abr_mode, clut, texpage);

    if (is_quad) {
        /* SPEC-ASSUMPTION: Quad vertices (0,1,2,3) split into tri(0,1,2) and tri(1,2,3) */
        rasterize_triangle(verts[1], verts[2], verts[3],
                           is_textured, is_gouraud, is_semi_trans, is_raw_tex,
                           abr_mode, clut, texpage);
    }
}

static void exec_line(void)
{
    uint32_t w0 = g_cmd_buf[0];
    uint32_t cmd = (w0 >> 24) & 0xFFu;
    int is_semi_trans = (cmd & 0x02u) != 0; /* R228: psx-spx lines 0x40 opaque, 0x42 semi (bit1) */
    int abr_mode = (g_texpage >> 5) & 3;

    uint8_t r = w0 & 0xFFu, g = (w0 >> 8) & 0xFFu, b = (w0 >> 16) & 0xFFu;
    uint16_t color = (uint16_t)(((b >> 3) << 10) | ((g >> 3) << 5) | (r >> 3));

    int16_t x0 = (int16_t)(g_cmd_buf[1] & 0xFFFFu) + g_draw_offset_x;
    int16_t y0 = (int16_t)(g_cmd_buf[1] >> 16) + g_draw_offset_y;
    int16_t x1 = (int16_t)(g_cmd_buf[2] & 0xFFFFu) + g_draw_offset_x;
    int16_t y1 = (int16_t)(g_cmd_buf[2] >> 16) + g_draw_offset_y;

    int dx = abs(x1 - x0), sx = x0 < x1 ? 1 : -1;
    int dy = -abs(y1 - y0), sy = y0 < y1 ? 1 : -1;
    int err = dx + dy;

    for (;;) {
        if (x0 >= g_draw_x1 && x0 <= g_draw_x2 && y0 >= g_draw_y1 && y0 <= g_draw_y2) {
            if (x0 >= 0 && x0 < GPU_VRAM_WIDTH && y0 >= 0 && y0 < GPU_VRAM_HEIGHT) {
                if (is_semi_trans) {
                    g_vram[y0][x0] = gpu_blend_pixel(g_vram[y0][x0], color, abr_mode);
                } else {
                    g_vram[y0][x0] = color;
                }
            }
        }
        if (x0 == x1 && y0 == y1) break;
        int e2 = 2 * err;
        if (e2 >= dy) { err += dy; x0 += sx; }
        if (e2 <= dx) { err += dx; y0 += sy; }
    }
}

static void exec_env_cmd(uint32_t v)
{
    uint32_t cmd = (v >> 24) & 0xFFu;
    switch (cmd) {
    case 0xE1:
        g_texpage = v & 0xFFFFu;
        break;
    case 0xE2:
        g_texwindow = v & 0xFFFFFFu;
        break;
    case 0xE3:
        g_draw_x1 = v & 0x3FFu;
        g_draw_y1 = (v >> 10) & 0x1FFu;
        break;
    case 0xE4:
        g_draw_x2 = v & 0x3FFu;
        g_draw_y2 = (v >> 10) & 0x1FFu;
        break;
    case 0xE5:
        g_draw_offset_x = (int16_t)((v & 0x7FFu) << 5) >> 5;
        g_draw_offset_y = (int16_t)(((v >> 11) & 0x7FFu) << 5) >> 5;
        break;
    case 0xE6:
        g_mask_set = v & 1;
        g_mask_check = (v >> 1) & 1;
        break;
    default:
        break;
    }
}

static int get_cmd_word_count(uint32_t w0)
{
    uint32_t cmd = (w0 >> 24) & 0xFFu;

    if (cmd == 0x02) return 3;
    if (cmd == 0x80) return 4;
    if (cmd == 0xC0) return 3;

    if (cmd >= 0x20 && cmd <= 0x3F) {
        /* R228: bit2 = textured (was bit1 = semi's bit: textured polys
         * undercounted by 2-6 words = stream desync at the first one) */
        int is_quad     = (cmd & 0x08u) != 0;
        int is_gouraud  = (cmd & 0x10u) != 0;
        int is_textured = (cmd & 0x04u) != 0;
        int verts = is_quad ? 4 : 3;
        int per_vert = 1 + (is_textured ? 1 : 0) + (is_gouraud ? 1 : 0);
        return 1 + verts * per_vert - (is_gouraud ? 1 : 0);
    }

    if (cmd >= 0x40 && cmd <= 0x5F) {
        int is_gouraud = (cmd & 0x10u) || ((cmd >> 28) & 1u);
        return 3 + (is_gouraud ? 1 : 0);
    }

    if (cmd >= 0x60 && cmd <= 0x7F) {
        /* R228: psx-spx word counts: mono fixed=2, mono var=3, textured
         * fixed=3, textured var=4. Old is_textured test read the wrong bit. */
        int is_textured = (cmd & 0x04u) != 0;
        int size_code   = (w0 >> 27) & 3u;
        return 2 + (is_textured ? 1 : 0) + (size_code == 0 ? 1 : 0);
    }

    return 1;
}

/* R939 (b8-c45, camera - GPU COMMAND CLASS CENSUS): c45 proved GP0 words
 * arrive (144-174 words, dma2_sends 7-10) yet VRAM stays empty and blits=0
 * - the interpreter receives words but something never paints. This census
 * counts every executed command class AND every DROPPED unknown command
 * (the old else-branch discarded them silently), capturing the first few
 * cmd bytes + first poly vertices so the next digest names the exact stream.
 */
uint32_t g_cls_fill, g_cls_copy, g_cls_rect, g_cls_line, g_cls_poly, g_cls_unknown;
uint32_t g_cls_poly_cmd0, g_cls_poly_v0, g_cls_poly_v1, g_cls_poly_v2;
uint32_t g_cls_fill_w[3], g_cls_rect_w[4]; int g_cls_fill_n, g_cls_rect_n; uint32_t g_cls_rect_cmd;
uint32_t g_cls_dropped[4]; int g_cls_dropped_n;
uint32_t g_cls_words_exec; /* words consumed by executed cmds */
static void exec_cmd_buf(void)
{
    uint32_t cmd = (g_cmd_buf[0] >> 24) & 0xFFu;

    if (cmd == 0x02) {
        g_cls_fill++; g_cls_words_exec += (uint32_t)g_cmd_words_total;
        if (g_cls_fill == 1u) {
            for (int i = 0; i < 3 && i < g_cmd_words_total; i++)
                g_cls_fill_w[i] = g_cmd_buf[i];
            g_cls_fill_n = g_cmd_words_total;
        }
        exec_fill();
    } else if (cmd == 0x80) {
        g_cls_copy++; g_cls_words_exec += (uint32_t)g_cmd_words_total;
        exec_copy();
    } else if (cmd >= 0x20 && cmd <= 0x3F) {
        g_cls_poly++; g_cls_words_exec += (uint32_t)g_cmd_words_total;
        if (g_cls_poly == 1u) {
            g_cls_poly_cmd0 = cmd;
            g_cls_poly_v0 = g_cmd_words_total > 1u ? g_cmd_buf[1] : 0u;
            g_cls_poly_v1 = g_cmd_words_total > 2u ? g_cmd_buf[2] : 0u;
            g_cls_poly_v2 = g_cmd_words_total > 3u ? g_cmd_buf[3] : 0u;
        }
        exec_poly();
    } else if (cmd >= 0x40 && cmd <= 0x5F) {
        g_cls_line++; g_cls_words_exec += (uint32_t)g_cmd_words_total;
        exec_line();
    } else if (cmd >= 0x60 && cmd <= 0x7F) {
        g_cls_rect++; g_cls_words_exec += (uint32_t)g_cmd_words_total;
        if (g_cls_rect == 1u) {
            g_cls_rect_cmd = cmd;
            for (int i = 0; i < 4 && i < g_cmd_words_total; i++)
                g_cls_rect_w[i] = g_cmd_buf[i];
            g_cls_rect_n = g_cmd_words_total;
        }
        exec_rect();
    } else {
        g_cls_unknown++;
        if (g_cls_dropped_n < 4) g_cls_dropped[g_cls_dropped_n++] = cmd;
    }
}

void gpu_cls_report(void)
{
    hle_out("[gpucls] R939 cmd census: fill=%u copy=%u rect=%u line=%u poly=%u dropped=%u words_exec=%u | poly#1 cmd=%02X w1=%08X w2=%08X w3=%08X | dropped_cmds:",
            g_cls_fill, g_cls_copy, g_cls_rect, g_cls_line, g_cls_poly,
            g_cls_unknown, g_cls_words_exec, g_cls_poly_cmd0,
            g_cls_poly_v0, g_cls_poly_v1, g_cls_poly_v2);
    for (int i = 0; i < g_cls_dropped_n; i++)
        hle_out(" %02X", g_cls_dropped[i]);
    hle_out(" | fill#1:");
    for (int i = 0; i < g_cls_fill_n && i < 3; i++)
        hle_out(" %08X", g_cls_fill_w[i]);
    hle_out(" | rect#1 cmd=%02X:", g_cls_rect_cmd);
    for (int i = 0; i < g_cls_rect_n && i < 4; i++)
        hle_out(" %08X", g_cls_rect_w[i]);
    hle_out(" | vram_writes=%u\n", g_cls_vram_writes);
    fflush(stderr);
}

/* Public API Implementation */
void gpu_init(void)
{
    memset(g_vram, 0, sizeof(g_vram));
    g_gpu_stat = 0x14802000u;
    g_read_latch = 0;
    g_disp_x = 0; g_disp_y = 0;
    g_disp_w = 320; g_disp_h = 240;
    g_draw_x1 = 0; g_draw_y1 = 0;
    g_draw_x2 = 1023; g_draw_y2 = 511;
    g_draw_offset_x = 0; g_draw_offset_y = 0;
    g_texpage = 0; g_clut = 0; g_texwindow = 0;
    g_mask_set = 0; g_mask_check = 0;
    g_gp0_state = GP0_STATE_IDLE;
    g_blit_x = 0; g_blit_y = 0; g_blit_w = 0; g_blit_h = 0; g_blit_left = 0;
    g_cmd_words_got = 0; g_cmd_words_total = 0;
}

void gpu_gp0_write(uint32_t v)
{
    switch (g_gp0_state) {
    case GP0_STATE_A0_HEADER1:
        g_blit_x = v & 0x3FFu;
        g_blit_y = (v >> 16) & 0x1FFu;
        g_gp0_state = GP0_STATE_A0_HEADER2;
        return;
    case GP0_STATE_A0_HEADER2:
        g_blit_w = v & 0x3FFu;
        g_blit_h = (v >> 16) & 0x1FFu;
        if (!g_blit_w) g_blit_w = 1024u;
        if (!g_blit_h) g_blit_h = 512u;
        g_blit_left = g_blit_w * g_blit_h;
        g_gp0_state = g_blit_left ? GP0_STATE_A0_DATA : GP0_STATE_IDLE;
        return;
    case GP0_STATE_A0_DATA:
        for (int half = 0; half < 2 && g_blit_left > 0; half++, g_blit_left--) {
            uint16_t px = half ? (v >> 16) : (v & 0xFFFFu);
            uint32_t done = g_blit_w * g_blit_h - g_blit_left;
            uint32_t dx = (g_blit_x + done % g_blit_w) & 0x3FFu;
            uint32_t dy = (g_blit_y + done / g_blit_w) & 0x1FFu;
            g_vram[dy][dx] = px;
        }
        if (!g_blit_left) g_gp0_state = GP0_STATE_IDLE;
        return;
    default:
        break;
    }

    uint32_t cmd = (v >> 24) & 0xFFu;

    if (g_gp0_state == GP0_STATE_IDLE) {
        if (cmd == 0xA0u) {
            g_gp0_state = GP0_STATE_A0_HEADER1;
            return;
        }
        if (cmd == 0x00u || cmd == 0x01u || cmd == 0x1Fu) {
            return; /* NOP / Clear Cache / Interrupt */
        }
        if ((cmd & 0xE0u) == 0xE0u) {
            exec_env_cmd(v);
            return;
        }

        g_cmd_buf[0] = v;
        g_cmd_words_got = 1;
        g_cmd_words_total = get_cmd_word_count(v);

        if (g_cmd_words_got >= g_cmd_words_total) {
            exec_cmd_buf();
            g_cmd_words_got = 0;
            g_cmd_words_total = 0;
        } else {
            g_gp0_state = GP0_STATE_ACCUMULATE;
        }
    } else if (g_gp0_state == GP0_STATE_ACCUMULATE) {
        g_cmd_buf[g_cmd_words_got++] = v;
        if (g_cmd_words_got >= g_cmd_words_total) {
            exec_cmd_buf();
            g_cmd_words_got = 0;
            g_cmd_words_total = 0;
            g_gp0_state = GP0_STATE_IDLE;
        }
    }
}

void gpu_gp1_write(uint32_t v)
{
    uint32_t cmd = (v >> 24) & 0xFFu;
    uint32_t param = v & 0x00FFFFFFu;

    switch (cmd) {
    case 0x00:
        g_gpu_stat = 0x14802000u;
        g_gp0_state = GP0_STATE_IDLE;
        g_cmd_words_got = 0;
        g_cmd_words_total = 0;
        break;
    case 0x01:
        g_gp0_state = GP0_STATE_IDLE;
        g_cmd_words_got = 0;
        g_cmd_words_total = 0;
        break;
    case 0x02:
        g_gpu_stat &= ~(1u << 24);
        break;
    case 0x03:
        if (param & 1u) {
            g_gpu_stat |= (1u << 23);
        } else {
            g_gpu_stat &= ~(1u << 23);
        }
        break;
    case 0x04:
        g_gpu_stat = (g_gpu_stat & ~(3u << 29)) | ((param & 3u) << 29);
        if (param & 3u) {
            g_gpu_stat |= (1u << 25);
        } else {
            g_gpu_stat &= ~(1u << 25);
        }
        break;
    case 0x05:
        g_disp_x = param & 0x3FFu;
        g_disp_y = (param >> 10) & 0x1FFu;
        break;
    case 0x08: {
        static const uint16_t hres[4] = {256, 320, 512, 640};
        g_disp_w = hres[(param >> 4) & 3u];
        g_disp_h = (param & 0x04u) ? 480u : 240u;
        break;
    }
    default:
        if (cmd >= 0x10 && cmd <= 0x1F) {
            switch (param & 0x0Fu) {
            case 0x02: g_read_latch = g_texwindow; break;
            case 0x03: g_read_latch = (g_draw_y1 << 10) | g_draw_x1; break;
            case 0x04: g_read_latch = (g_draw_y2 << 10) | g_draw_x2; break;
            case 0x05: g_read_latch = ((g_draw_offset_y & 0x7FF) << 11) | (g_draw_offset_x & 0x7FF); break;
            case 0x07: g_read_latch = 2; break;
            default: break;
            }
        }
        break;
    }
}

void gpu_vram_snapshot(uint16_t *out_vram, size_t max_halfwords)
{
    if (!out_vram) return;
    size_t copy_size = max_halfwords < GPU_VRAM_SIZE ? max_halfwords : GPU_VRAM_SIZE;
    memcpy(out_vram, g_vram, copy_size * sizeof(uint16_t));
}

void gpu_display_area(uint16_t *x, uint16_t *y, uint16_t *w, uint16_t *h)
{
    if (x) *x = g_disp_x;
    if (y) *y = g_disp_y;
    if (w) *w = g_disp_w;
    if (h) *h = g_disp_h;
}

uint32_t gpu_get_status(void)
{
    return g_gpu_stat;
}

uint32_t gpu_get_read_latch(void)
{
    return g_read_latch;
}

uint16_t gpu_vram_peek(uint32_t x, uint32_t y)
{
    if (x < GPU_VRAM_WIDTH && y < GPU_VRAM_HEIGHT) {
        return g_vram[y][x];
    }
    return 0;
}

void gpu_vram_poke(uint32_t x, uint32_t y, uint16_t val)
{
    if (x < GPU_VRAM_WIDTH && y < GPU_VRAM_HEIGHT) {
        g_vram[y][x] = val;
    }
}
