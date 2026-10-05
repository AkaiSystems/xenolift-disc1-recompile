/* xenolift HLE MDEC module — Motion Decoder Implementation
 *
 * Spec references & Citations:
 * - psx-spx "Macroblock Decoder (MDEC) I/O Ports": http://problemkaputt.de/psxspx-mdec-i-o-ports.htm
 * - psx-spx "MDEC Commands": http://problemkaputt.de/psxspx-mdec-commands.htm
 * - psx-spx "MDEC Data Format": http://problemkaputt.de/psxspx-mdec-data-format.htm
 * - psx-spx "MDEC Decompression": http://problemkaputt.de/psxspx-mdec-decompression.htm
 */

#include "hle_mdec.h"
#include "receipt_xprintf.h" /* R985 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

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


#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

/* Default Quantization Table (standard JPEG/PS1 MDEC table) */
static const uint8_t DEFAULT_QUANT_TABLE[64] = {
    0x02, 0x10, 0x10, 0x13, 0x10, 0x13, 0x16, 0x16,
    0x16, 0x16, 0x16, 0x16, 0x1A, 0x18, 0x1A, 0x1B,
    0x1B, 0x1B, 0x1A, 0x1A, 0x1A, 0x1A, 0x1B, 0x1B,
    0x1B, 0x1D, 0x1D, 0x1D, 0x22, 0x22, 0x22, 0x1D,
    0x1D, 0x1D, 0x1B, 0x1B, 0x1D, 0x1D, 0x20, 0x20,
    0x22, 0x22, 0x25, 0x26, 0x25, 0x23, 0x23, 0x22,
    0x23, 0x26, 0x26, 0x28, 0x28, 0x28, 0x30, 0x30,
    0x2E, 0x2E, 0x38, 0x38, 0x3A, 0x45, 0x45, 0x53
};

/* Default Scale Table (standard 64 signed 16-bit constants with 14-bit fraction) */
static const int16_t DEFAULT_SCALE_TABLE[64] = {
    0x5A82, 0x5A82, 0x5A82, 0x5A82, 0x5A82, 0x5A82, 0x5A82, 0x5A82,
    0x7D8A, 0x6A6D, 0x471C, 0x18F8, (int16_t)0xE707, (int16_t)0xB8E3, (int16_t)0x9592, (int16_t)0x8275,
    0x7641, 0x30FB, (int16_t)0xCF04, (int16_t)0x89BE, (int16_t)0x89BE, (int16_t)0xCF04, 0x30FB, 0x7641,
    0x6A6D, (int16_t)0xE707, (int16_t)0x8275, (int16_t)0xB8E3, 0x471C, 0x7D8A, 0x18F8, (int16_t)0x9592,
    0x5A82, (int16_t)0xA57D, (int16_t)0xA57D, 0x5A82, 0x5A82, (int16_t)0xA57D, (int16_t)0xA57D, 0x5A82,
    0x471C, (int16_t)0x8275, 0x18F8, 0x6A6D, (int16_t)0x9592, (int16_t)0xE707, 0x7D8A, (int16_t)0xB8E3,
    0x30FB, (int16_t)0x89BE, 0x7641, (int16_t)0xCF04, (int16_t)0xCF04, 0x7641, (int16_t)0x89BE, 0x30FB,
    0x18F8, (int16_t)0xB8E3, 0x6A6D, (int16_t)0x8275, 0x7D8A, (int16_t)0x9592, 0x471C, (int16_t)0xE707
};

/* PS1 Zigzag permutation table */
static const uint8_t ZIGZAG[64] = {
     0,  1,  5,  6, 14, 15, 27, 28,
     2,  4,  7, 13, 16, 26, 29, 42,
     3,  8, 12, 17, 25, 30, 41, 43,
     9, 11, 18, 24, 31, 40, 44, 53,
    10, 19, 23, 32, 39, 45, 52, 54,
    20, 22, 33, 38, 46, 51, 55, 60,
    21, 34, 37, 47, 50, 56, 59, 61,
    35, 36, 48, 49, 57, 58, 62, 63
};

/* Zagzig table: ZAGZIG[ZIGZAG[i]] = i */
static uint8_t ZAGZIG[64];

/* R1571: cmd1 takes up to 0xFFFF parameter words (2 halfwords each); a whole 320x240 24bpp frame
 * is 57,600 output words and the HLE decodes a frame at once (DMA0 is synchronous) */
#define MDEC_IN_HALFS  (1u << 17)
#define MDEC_OUT_WORDS (1u << 17)

/* Internal MDEC State */
typedef struct {
    uint8_t *ram;               /* Pointer to 2MB main RAM */

    /* Command execution state */
    uint32_t current_cmd;       /* 0, 1, 2, 3 */
    uint32_t output_depth;      /* 0=4bit, 1=8bit, 2=24bit, 3=15bit */
    bool output_signed;         /* bit 24 */
    bool output_bit15;          /* bit 23 */
    uint32_t remaining_words;   /* parameter 32-bit words remaining (R1571) */
    uint32_t param_words;       /* R1571: parameter words received for the current command */

    /* Control & Status flags */
    bool data_in_enable;        /* Control bit 30: Enable DMA0 & status bit 28 */
    bool data_out_enable;       /* Control bit 29: Enable DMA1 & status bit 27 */
    bool busy;                  /* Status bit 29 */
    uint32_t current_block;     /* Status bits 18-16: 0..3=Y1..Y4, 4=Cr, 5=Cb */

    /* Quantization & Scale tables */
    uint8_t iq_y[64];           /* Luminance quant table */
    uint8_t iq_uv[64];          /* Color quant table */
    int16_t scale_table[64];    /* Scale table */

    /* Data Input Stream Buffer (16-bit halfwords) */
    uint16_t in_buf[MDEC_IN_HALFS];
    size_t in_count;
    size_t in_read_pos;

    /* Output FIFO (32-bit words) */
    uint32_t out_fifo[MDEC_OUT_WORDS];
    size_t out_count;
    size_t out_read_pos;
} MdecState;

static MdecState g_mdec;

/* Helper: Clamp value to signed 8-bit (-128..127) */
static inline int clamp_s8(int v) {
    if (v < -128) return -128;
    if (v > 127) return 127;
    return v;
}

/* Helper: Clamp value to unsigned 8-bit (0..255) */
static inline int clamp_u8(int v) {
    if (v < 0) return 0;
    if (v > 255) return 255;
    return v;
}

/* Helper: Clamp value to signed 11-bit (-1024..1023) */
static inline int clamp_s11(int v) {
    if (v < -1024) return -1024;
    if (v > 1023) return 1023;
    return v;
}

/* Helper: Sign extend 10-bit signed value */
static inline int signed_10bit(uint16_t v) {
    int val = v & 0x3FF;
    if (val & 0x200) val -= 0x400;
    return val;
}

/* Initialize ZAGZIG inverse lookup table */
static void init_zagzig(void) {
    static bool inited = false;
    if (inited) return;
    for (int i = 0; i < 64; i++) {
        ZAGZIG[ZIGZAG[i]] = (uint8_t)i;
    }
    inited = true;
}

void hle_mdec_set_ram(uint8_t *shared_ram) {
    g_mdec.ram = shared_ram;
}

void hle_mdec_reset(void) {
    init_zagzig();
    g_mdec.current_cmd = 0;
    g_mdec.output_depth = 3; /* default 15bpp */
    g_mdec.output_signed = false;
    g_mdec.output_bit15 = false;
    g_mdec.remaining_words = 0xFFFF;
    g_mdec.param_words = 0;
    g_mdec.data_in_enable = false;
    g_mdec.data_out_enable = false;
    g_mdec.busy = false;
    g_mdec.current_block = 0;

    memcpy(g_mdec.iq_y, DEFAULT_QUANT_TABLE, 64);
    memcpy(g_mdec.iq_uv, DEFAULT_QUANT_TABLE, 64);
    memcpy(g_mdec.scale_table, DEFAULT_SCALE_TABLE, sizeof(DEFAULT_SCALE_TABLE));

    g_mdec.in_count = 0;
    g_mdec.in_read_pos = 0;
    g_mdec.out_count = 0;
    g_mdec.out_read_pos = 0;

    hle_out("[mdec] reset complete\n");
}

uint32_t hle_mdec_get_status(void) {
    uint32_t stat = 0;

    /* Bit 31: Data-Out FIFO Empty (1=Empty, 0=Not empty) */
    if (g_mdec.out_read_pos >= g_mdec.out_count) {
        stat |= (1u << 31);
    }

    /* Bit 30: Data-In FIFO Full (0=No, 1=Full) */
    if (g_mdec.in_count + 1 >= MDEC_IN_HALFS) {
        stat |= (1u << 30);
    }

    /* Bit 29: Command Busy */
    if (g_mdec.busy) {
        stat |= (1u << 29);
    }

    /* Bit 28: Data-In Request (set when DMA0 enabled and ready) */
    if (g_mdec.data_in_enable) {
        stat |= (1u << 28);
    }

    /* Bit 27: Data-Out Request (set when DMA1 enabled and data available) */
    if (g_mdec.data_out_enable && (g_mdec.out_read_pos < g_mdec.out_count)) {
        stat |= (1u << 27);
    }

    /* Bits 26-25: Data Output Depth (0=4b, 1=8b, 2=24b, 3=15b) */
    stat |= ((g_mdec.output_depth & 3u) << 25);

    /* Bit 24: Signed Output */
    if (g_mdec.output_signed) {
        stat |= (1u << 24);
    }

    /* Bit 23: Bit 15 set */
    if (g_mdec.output_bit15) {
        stat |= (1u << 23);
    }

    /* Bits 18-16: Current Block */
    stat |= ((g_mdec.current_block & 7u) << 16);

    /* Bits 15-0: Parameter words remaining minus 1 */
    stat |= (g_mdec.remaining_words & 0xFFFFu);

    return stat;
}

bool hle_mdec_is_busy(void) {
    return g_mdec.busy;
}

/* R1571: decoder core rewritten to psx-spx "MDEC Decompression". The old core
 * (a) emitted nothing for 24bpp, the depth every movie uses, (b) emitted each 8x8 Y block on its
 * own instead of one 16x16 macroblock in row order, and (c) counted parameters in halfwords, so
 * every command ended halfway and the rest of its data was parsed as new commands.
 * IDCT: 0.25 * sum cu*cv*X*cos*cos, which is real_idct_core with the default scale table; done
 * separably (rows, then columns) from a cached cosine table. */
static double g_idct_c[8][8]; /* [x][u] = cu * cos((2x+1) u pi / 16) */

static void idct_init(void) {
    static bool inited = false;
    if (inited) return;
    for (int x = 0; x < 8; x++)
        for (int u = 0; u < 8; u++)
            g_idct_c[x][u] = (u == 0 ? (1.0 / sqrt(2.0)) : 1.0) * cos((2.0 * x + 1.0) * u * M_PI / 16.0);
    inited = true;
}

static void idct_8x8(const int32_t *in_block, int32_t *out_block) {
    double tmp[64];
    idct_init();
    for (int v = 0; v < 8; v++)
        for (int x = 0; x < 8; x++) {
            double s = 0.0;
            for (int u = 0; u < 8; u++) s += in_block[v * 8 + u] * g_idct_c[x][u];
            tmp[v * 8 + x] = 0.5 * s;
        }
    for (int x = 0; x < 8; x++)
        for (int y = 0; y < 8; y++) {
            double s = 0.0;
            for (int v = 0; v < 8; v++) s += tmp[v * 8 + x] * g_idct_c[y][v];
            out_block[y * 8 + x] = (int32_t)floor(0.5 * s + 0.5);
        }
}

/* RLE decode one 8x8 block (psx-spx rl_decode_block) */
static bool rl_decode_block(const uint8_t *qt, int32_t *out_block) {
    int32_t blk[64];
    memset(blk, 0, sizeof(blk));

    while (g_mdec.in_read_pos < g_mdec.in_count && g_mdec.in_buf[g_mdec.in_read_pos] == 0xFE00)
        g_mdec.in_read_pos++;
    if (g_mdec.in_read_pos >= g_mdec.in_count) return false;

    uint16_t n = g_mdec.in_buf[g_mdec.in_read_pos++];
    int q_scale = (n >> 10) & 0x3F;
    int k = 0;
    int val = signed_10bit(n) * qt[0];
    for (;;) {
        if (q_scale == 0) val = signed_10bit(n) * 2;
        val = clamp_s11(val);
        if (q_scale > 0) blk[ZAGZIG[k]] = val;
        else blk[k] = val;
        if (g_mdec.in_read_pos >= g_mdec.in_count) break;
        n = g_mdec.in_buf[g_mdec.in_read_pos++];
        k += ((n >> 10) & 0x3F) + 1;
        if (k > 63) break; /* 0xFE00 = end of block */
        val = (signed_10bit(n) * qt[k] * q_scale + 4) / 8;
    }

    idct_8x8(blk, out_block);
    return true;
}

static void mdec_emit_bytes(const uint8_t *b, size_t n) {
    for (size_t i = 0; i + 3 < n; i += 4) {
        if (g_mdec.out_count >= MDEC_OUT_WORDS) return;
        g_mdec.out_fifo[g_mdec.out_count++] = (uint32_t)b[i] | ((uint32_t)b[i + 1] << 8) |
                                              ((uint32_t)b[i + 2] << 16) | ((uint32_t)b[i + 3] << 24);
    }
}

static inline uint8_t mdec_u8(int v) { /* signed -128..127 -> output byte */
    v = clamp_s8(v);
    return (uint8_t)(g_mdec.output_signed ? (v & 0xFF) : ((v + 128) & 0xFF));
}

/* Process macroblocks in the input buffer */
static void mdec_process_decode(void) {
    while (g_mdec.in_read_pos < g_mdec.in_count) {
        size_t saved_pos = g_mdec.in_read_pos;

        if (g_mdec.output_depth <= 1) {
            /* monochrome: one 8x8 Y block -> 64 bytes (8bpp) or 32 bytes (4bpp) */
            int32_t Y[64];
            uint8_t px[64];
            g_mdec.current_block = 4;
            if (!rl_decode_block(g_mdec.iq_y, Y)) { g_mdec.in_read_pos = saved_pos; break; }
            for (int i = 0; i < 64; i++) px[i] = mdec_u8(Y[i]);
            if (g_mdec.output_depth == 1) {
                mdec_emit_bytes(px, 64);
            } else {
                uint8_t nib[32];
                for (int i = 0; i < 32; i++) nib[i] = (uint8_t)((px[2 * i] >> 4) | (px[2 * i + 1] & 0xF0));
                mdec_emit_bytes(nib, 32);
            }
            continue;
        }

        /* colour: Cr, Cb (8x8, low resolution), then Y1..Y4 -> one 16x16 macroblock */
        int32_t Cr[64], Cb[64], Y[64];
        uint8_t rgb[16 * 16 * 3];
        g_mdec.current_block = 4;
        if (!rl_decode_block(g_mdec.iq_uv, Cr)) { g_mdec.in_read_pos = saved_pos; break; }
        g_mdec.current_block = 5;
        if (!rl_decode_block(g_mdec.iq_uv, Cb)) { g_mdec.in_read_pos = saved_pos; break; }
        bool ok = true;
        for (int blk = 0; blk < 4 && ok; blk++) {
            g_mdec.current_block = (uint32_t)blk;
            if (!rl_decode_block(g_mdec.iq_y, Y)) { ok = false; break; }
            int xx = (blk & 1) * 8, yy = (blk >> 1) * 8;
            for (int y = 0; y < 8; y++)
                for (int x = 0; x < 8; x++) {
                    int ci = ((x + xx) >> 1) + ((y + yy) >> 1) * 8;
                    double cr = Cr[ci], cb = Cb[ci];
                    int yv = Y[y * 8 + x];
                    int r = yv + (int)(1.402 * cr);
                    int g = yv + (int)((-0.3437 * cb) + (-0.7143 * cr));
                    int b = yv + (int)(1.772 * cb);
                    uint8_t *o = &rgb[((y + yy) * 16 + (x + xx)) * 3];
                    o[0] = mdec_u8(r); o[1] = mdec_u8(g); o[2] = mdec_u8(b);
                }
        }
        if (!ok) { g_mdec.in_read_pos = saved_pos; break; }

        if (g_mdec.output_depth == 2) {
            mdec_emit_bytes(rgb, sizeof rgb); /* 24bpp: R,G,B bytes, 192 words */
        } else {
            uint8_t h[16 * 16 * 2]; /* 15bpp: 128 words */
            for (int i = 0; i < 256; i++) {
                uint16_t p = (uint16_t)((rgb[i * 3] >> 3) | ((rgb[i * 3 + 1] >> 3) << 5) | ((rgb[i * 3 + 2] >> 3) << 10));
                if (g_mdec.output_bit15) p |= 0x8000u;
                h[i * 2] = (uint8_t)p; h[i * 2 + 1] = (uint8_t)(p >> 8);
            }
            mdec_emit_bytes(h, sizeof h);
        }
    }
}

void hle_mdec_port_write(uint32_t addr, uint32_t v) {
    uint32_t reg = addr & 0x0Fu;

    if (reg == 0x00) {
        if (!g_mdec.busy) {
            /* New command word; status bits 26-23 mirror its bits 28-25 */
            g_mdec.current_cmd = (v >> 29) & 7u;
            g_mdec.output_depth = (v >> 27) & 3u;
            g_mdec.output_signed = (v & (1u << 26)) != 0;
            g_mdec.output_bit15 = (v & (1u << 25)) != 0;
            g_mdec.param_words = 0;
            g_mdec.in_count = 0;
            g_mdec.in_read_pos = 0;

            if (g_mdec.current_cmd == 1) {
                g_mdec.out_count = 0;
                g_mdec.out_read_pos = 0;
                g_mdec.remaining_words = v & 0xFFFFu;
                g_mdec.busy = g_mdec.remaining_words != 0;
                hle_out("[mdec] cmd1 decode started: depth=%u words=%u\n",
                        g_mdec.output_depth, g_mdec.remaining_words);
            } else if (g_mdec.current_cmd == 2) {
                bool color = (v & 1u) != 0;
                g_mdec.remaining_words = color ? 32u : 16u; /* 64 bytes luma (+ 64 bytes colour) */
                g_mdec.busy = true;
                hle_out("[mdec] cmd2 set_iqtab started: color=%d\n", color);
            } else if (g_mdec.current_cmd == 3) {
                g_mdec.remaining_words = 32u; /* 64 signed halfwords */
                g_mdec.busy = true;
                hle_out("[mdec] cmd3 set_scale started\n");
            } else {
                g_mdec.remaining_words = 0xFFFFu;
                g_mdec.busy = false;
            }
        } else {
            /* Parameter word for the active command */
            uint32_t idx = g_mdec.param_words++;
            if (g_mdec.current_cmd == 2) {
                uint32_t byte = idx * 4u;
                uint8_t *t = byte < 64u ? &g_mdec.iq_y[byte] : (byte < 128u ? &g_mdec.iq_uv[byte - 64u] : NULL);
                if (t) { t[0] = (uint8_t)v; t[1] = (uint8_t)(v >> 8); t[2] = (uint8_t)(v >> 16); t[3] = (uint8_t)(v >> 24); }
            } else if (g_mdec.current_cmd == 3) {
                uint32_t hw = idx * 2u;
                if (hw < 64u) {
                    g_mdec.scale_table[hw] = (int16_t)(v & 0xFFFF);
                    g_mdec.scale_table[hw + 1] = (int16_t)(v >> 16);
                }
            } else if (g_mdec.current_cmd == 1) {
                if (g_mdec.in_count + 1 < MDEC_IN_HALFS) {
                    g_mdec.in_buf[g_mdec.in_count++] = (uint16_t)(v & 0xFFFF);
                    g_mdec.in_buf[g_mdec.in_count++] = (uint16_t)(v >> 16);
                }
            }
            if (g_mdec.remaining_words > 0) g_mdec.remaining_words--;
            if (g_mdec.remaining_words == 0) {
                g_mdec.busy = false;
                g_mdec.remaining_words = 0xFFFF;
                if (g_mdec.current_cmd == 1) {
                    mdec_process_decode();
                    hle_out("[mdec] cmd1 decode complete: produced %u words\n", (unsigned)g_mdec.out_count);
                } else if (g_mdec.current_cmd == 2) {
                    hle_out("[mdec] cmd2 set_iqtab finished\n");
                } else if (g_mdec.current_cmd == 3) {
                    hle_out("[mdec] cmd3 set_scale finished\n");
                }
            }
        }
    } else if (reg == 0x04) {
        if (v & (1u << 31)) {
            hle_mdec_reset();
        } else {
            g_mdec.data_in_enable  = (v & (1u << 30)) != 0;
            g_mdec.data_out_enable = (v & (1u << 29)) != 0;
        }
    }
}

uint32_t hle_mdec_port_read(uint32_t addr) {
    uint32_t reg = addr & 0x0Fu;

    if (reg == 0x00) {
        if (g_mdec.out_read_pos < g_mdec.out_count) {
            uint32_t val = g_mdec.out_fifo[g_mdec.out_read_pos++];
            return val;
        }
        return 0;
    } else if (reg == 0x04) {
        return hle_mdec_get_status();
    }
    return 0;
}

void hle_mdec_dma0_in(uint32_t madr, uint32_t bcr) {
    if (!g_mdec.ram) return;

    uint32_t block_size = bcr & 0xFFFFu;
    uint32_t block_count = (bcr >> 16) & 0xFFFFu;
    if (block_size == 0) block_size = 0x10000u;
    if (block_count == 0) block_count = 1;

    uint32_t total_words = block_size * block_count;
    uint32_t phys_addr = madr & 0x1FFFFFu;

    hle_out("[mdec-dma0] in from RAM 0x%08X (%u words)\n", madr, total_words);

    for (uint32_t i = 0; i < total_words; i++) {
        uint32_t ram_offset = (phys_addr + i * 4) & 0x1FFFFFu;
        uint32_t word = 0;
        memcpy(&word, g_mdec.ram + ram_offset, 4);
        hle_mdec_port_write(0x1F801820, word);
    }
}

void hle_mdec_dma1_out(uint32_t madr, uint32_t bcr) {
    if (!g_mdec.ram) return;

    uint32_t block_size = bcr & 0xFFFFu;
    uint32_t block_count = (bcr >> 16) & 0xFFFFu;
    if (block_size == 0) block_size = 0x10000u;
    if (block_count == 0) block_count = 1;

    uint32_t total_words = block_size * block_count;
    uint32_t phys_addr = madr & 0x1FFFFFu;

    hle_out("[mdec-dma1] out to RAM 0x%08X (%u words)\n", madr, total_words);

    for (uint32_t i = 0; i < total_words; i++) {
        uint32_t word = hle_mdec_port_read(0x1F801820);
        uint32_t ram_offset = (phys_addr + i * 4) & 0x1FFFFFu;
        memcpy(g_mdec.ram + ram_offset, &word, 4);
    }
}
