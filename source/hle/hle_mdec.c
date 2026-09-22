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

/* Internal MDEC State */
typedef struct {
    uint8_t *ram;               /* Pointer to 2MB main RAM */

    /* Command execution state */
    uint32_t current_cmd;       /* 0, 1, 2, 3 */
    uint32_t output_depth;      /* 0=4bit, 1=8bit, 2=24bit, 3=15bit */
    bool output_signed;         /* bit 24 */
    bool output_bit15;          /* bit 23 */
    uint32_t remaining_words;   /* parameter 16-bit words remaining */

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
    uint16_t in_buf[65536];
    size_t in_count;
    size_t in_read_pos;

    /* Output FIFO (32-bit words) */
    uint32_t out_fifo[8192];
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
    if (g_mdec.in_count >= 65536) {
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

/* 8x8 Integer IDCT implementation */
static void idct_8x8(const int32_t *in_block, int32_t *out_block) {
    for (int y = 0; y < 8; y++) {
        for (int x = 0; x < 8; x++) {
            double sum = 0.0;
            for (int u = 0; u < 8; u++) {
                for (int v = 0; v < 8; v++) {
                    double cu = (u == 0) ? (1.0 / sqrt(2.0)) : 1.0;
                    double cv = (v == 0) ? (1.0 / sqrt(2.0)) : 1.0;
                    double val = in_block[v * 8 + u];
                    double cos_u = cos((2.0 * x + 1.0) * u * M_PI / 16.0);
                    double cos_v = cos((2.0 * y + 1.0) * v * M_PI / 16.0);
                    sum += cu * cv * val * cos_u * cos_v;
                }
            }
            out_block[y * 8 + x] = (int32_t)floor(0.25 * sum + 0.5);
        }
    }
}

/* RLE decode one 8x8 block from input buffer */
static bool rl_decode_block(const uint8_t *qt, int32_t *out_block) {
    int32_t freq_block[64];
    memset(freq_block, 0, sizeof(freq_block));

    if (g_mdec.in_read_pos >= g_mdec.in_count) return false;

    /* Skip padding 0xFE00 at start */
    while (g_mdec.in_read_pos < g_mdec.in_count && g_mdec.in_buf[g_mdec.in_read_pos] == 0xFE00) {
        g_mdec.in_read_pos++;
    }

    if (g_mdec.in_read_pos >= g_mdec.in_count) return false;

    /* First entry: DC value + q_scale */
    uint16_t n = g_mdec.in_buf[g_mdec.in_read_pos++];
    uint32_t q_scale = (n >> 10) & 0x3F;
    int dc = signed_10bit(n & 0x3FF);

    int val;
    if (q_scale == 0) {
        val = dc * 2;
    } else {
        val = dc * qt[0];
    }
    val = clamp_s11(val);
    freq_block[ZAGZIG[0]] = val;

    /* Subsequent entries: AC values or EOB (0xFE00) */
    int k = 0;
    while (k < 63 && g_mdec.in_read_pos < g_mdec.in_count) {
        n = g_mdec.in_buf[g_mdec.in_read_pos++];
        if (n == 0xFE00) {
            break;
        }

        uint32_t len = (n >> 10) & 0x3F;
        int ac = signed_10bit(n & 0x3FF);
        k += (int)len + 1;
        if (k > 63) break;

        if (q_scale == 0) {
            val = ac * 2;
        } else {
            val = (ac * qt[k] * (int)q_scale + 4) / 8;
        }
        val = clamp_s11(val);
        freq_block[ZAGZIG[k]] = val;
    }

    idct_8x8(freq_block, out_block);
    return true;
}

/* Process macroblocks in input buffer */
static void mdec_process_decode(void) {
    while (g_mdec.in_read_pos < g_mdec.in_count) {
        int32_t Cr[64], Cb[64], Y1[64], Y2[64], Y3[64], Y4[64];
        size_t saved_pos = g_mdec.in_read_pos;

        g_mdec.current_block = 4; /* Cr */
        if (!rl_decode_block(g_mdec.iq_uv, Cr)) { g_mdec.in_read_pos = saved_pos; break; }

        g_mdec.current_block = 5; /* Cb */
        if (!rl_decode_block(g_mdec.iq_uv, Cb)) { g_mdec.in_read_pos = saved_pos; break; }

        g_mdec.current_block = 0; /* Y1 */
        if (!rl_decode_block(g_mdec.iq_y, Y1)) { g_mdec.in_read_pos = saved_pos; break; }

        g_mdec.current_block = 1; /* Y2 */
        if (!rl_decode_block(g_mdec.iq_y, Y2)) { g_mdec.in_read_pos = saved_pos; break; }

        g_mdec.current_block = 2; /* Y3 */
        if (!rl_decode_block(g_mdec.iq_y, Y3)) { g_mdec.in_read_pos = saved_pos; break; }

        g_mdec.current_block = 3; /* Y4 */
        if (!rl_decode_block(g_mdec.iq_y, Y4)) { g_mdec.in_read_pos = saved_pos; break; }

        int32_t *Y_blocks[4] = { Y1, Y2, Y3, Y4 };

        for (int blk = 0; blk < 4; blk++) {
            int32_t *Y = Y_blocks[blk];
            int xx_off = (blk == 1 || blk == 3) ? 8 : 0;
            int yy_off = (blk >= 2) ? 8 : 0;

            uint16_t block_pixels[64];

            for (int y = 0; y < 8; y++) {
                for (int x = 0; x < 8; x++) {
                    int cx = (x + xx_off) / 2;
                    int cy = (y + yy_off) / 2;

                    int cr_v = Cr[cy * 8 + cx];
                    int cb_v = Cb[cy * 8 + cx];
                    int y_v  = Y[y * 8 + x];

                    int r = y_v + (int)(1.402 * cr_v);
                    int g = y_v - (int)(0.3437 * cb_v) - (int)(0.7143 * cr_v);
                    int b = y_v + (int)(1.772 * cb_v);

                    r = clamp_s8(r);
                    g = clamp_s8(g);
                    b = clamp_s8(b);

                    if (!g_mdec.output_signed) {
                        r = clamp_u8(r + 128);
                        g = clamp_u8(g + 128);
                        b = clamp_u8(b + 128);
                    }

                    if (g_mdec.output_depth == 3) {
                        /* 15bpp mode */
                        uint16_t r5 = (uint16_t)((r >> 3) & 0x1F);
                        uint16_t g5 = (uint16_t)((g >> 3) & 0x1F);
                        uint16_t b5 = (uint16_t)((b >> 3) & 0x1F);
                        uint16_t bit15 = g_mdec.output_bit15 ? 0x8000u : 0u;
                        block_pixels[y * 8 + x] = bit15 | (b5 << 10) | (g5 << 5) | r5;
                    } else if (g_mdec.output_depth == 2) {
                        block_pixels[y * 8 + x] = 0;
                    }
                }
            }

            if (g_mdec.output_depth == 3) {
                /* 15bpp: 64 pixels = 32 uint32 words */
                for (int i = 0; i < 64; i += 2) {
                    uint32_t word = ((uint32_t)block_pixels[i + 1] << 16) | (uint32_t)block_pixels[i];
                    if (g_mdec.out_count < 8192) {
                        g_mdec.out_fifo[g_mdec.out_count++] = word;
                    }
                }
            }
        }
    }
}

void hle_mdec_port_write(uint32_t addr, uint32_t v) {
    uint32_t reg = addr & 0x0Fu;

    if (reg == 0x00) {
        if (!g_mdec.busy) {
            /* New command word */
            g_mdec.current_cmd = (v >> 29) & 7u;
            g_mdec.in_count = 0;
            g_mdec.in_read_pos = 0;
            g_mdec.out_count = 0;
            g_mdec.out_read_pos = 0;

            if (g_mdec.current_cmd == 1) {
                /* Cmd 1: Decode Macroblock(s) */
                g_mdec.output_depth = (v >> 27) & 3u;
                g_mdec.output_signed = (v & (1u << 26)) != 0;
                g_mdec.output_bit15 = (v & (1u << 25)) != 0;
                g_mdec.remaining_words = v & 0xFFFFu;
                g_mdec.busy = true;
                hle_out("[mdec] cmd1 decode started: depth=%u words=%u\n",
                        g_mdec.output_depth, g_mdec.remaining_words);
            } else if (g_mdec.current_cmd == 2) {
                /* Cmd 2: Set Quant Table(s) */
                bool color = (v & 1u) != 0;
                g_mdec.remaining_words = color ? 32u : 16u; /* 128 bytes (32 16b words) or 64 bytes (16 16b words) */
                g_mdec.busy = true;
                hle_out("[mdec] cmd2 set_iqtab started: color=%d\n", color);
            } else if (g_mdec.current_cmd == 3) {
                /* Cmd 3: Set Scale Table */
                g_mdec.remaining_words = 32u; /* 64 halfwords = 32 16b words */
                g_mdec.busy = true;
                hle_out("[mdec] cmd3 set_scale started\n");
            } else {
                g_mdec.remaining_words = v & 0xFFFFu;
                g_mdec.busy = false;
            }
        } else {
            /* Parameter word for current active command (32-bit write = 2 16-bit parameter units) */
            if (g_mdec.current_cmd == 2) {
                size_t bytes_recv = (g_mdec.in_count * 2);
                if (bytes_recv < 64) {
                    g_mdec.iq_y[bytes_recv + 0] = (uint8_t)(v & 0xFF);
                    g_mdec.iq_y[bytes_recv + 1] = (uint8_t)((v >> 8) & 0xFF);
                    g_mdec.iq_y[bytes_recv + 2] = (uint8_t)((v >> 16) & 0xFF);
                    g_mdec.iq_y[bytes_recv + 3] = (uint8_t)((v >> 24) & 0xFF);
                } else if (bytes_recv < 128) {
                    size_t uv_idx = bytes_recv - 64;
                    g_mdec.iq_uv[uv_idx + 0] = (uint8_t)(v & 0xFF);
                    g_mdec.iq_uv[uv_idx + 1] = (uint8_t)((v >> 8) & 0xFF);
                    g_mdec.iq_uv[uv_idx + 2] = (uint8_t)((v >> 16) & 0xFF);
                    g_mdec.iq_uv[uv_idx + 3] = (uint8_t)((v >> 24) & 0xFF);
                }
                g_mdec.in_count += 2;
                g_mdec.remaining_words = (g_mdec.remaining_words >= 2) ? (g_mdec.remaining_words - 2) : 0;
                if (g_mdec.remaining_words == 0) {
                    g_mdec.busy = false;
                    g_mdec.remaining_words = 0xFFFF;
                    hle_out("[mdec] cmd2 set_iqtab finished\n");
                }
            } else if (g_mdec.current_cmd == 3) {
                size_t hw_idx = g_mdec.in_count;
                if (hw_idx < 64) {
                    g_mdec.scale_table[hw_idx + 0] = (int16_t)(v & 0xFFFF);
                    g_mdec.scale_table[hw_idx + 1] = (int16_t)((v >> 16) & 0xFFFF);
                }
                g_mdec.in_count += 2;
                g_mdec.remaining_words = (g_mdec.remaining_words >= 2) ? (g_mdec.remaining_words - 2) : 0;
                if (g_mdec.remaining_words == 0) {
                    g_mdec.busy = false;
                    g_mdec.remaining_words = 0xFFFF;
                    hle_out("[mdec] cmd3 set_scale finished\n");
                }
            } else if (g_mdec.current_cmd == 1) {
                if (g_mdec.in_count + 1 < 65536) {
                    g_mdec.in_buf[g_mdec.in_count++] = (uint16_t)(v & 0xFFFF);
                    g_mdec.in_buf[g_mdec.in_count++] = (uint16_t)((v >> 16) & 0xFFFF);
                }
                g_mdec.remaining_words = (g_mdec.remaining_words >= 2) ? (g_mdec.remaining_words - 2) : 0;
                if (g_mdec.remaining_words == 0) {
                    g_mdec.busy = false;
                    g_mdec.remaining_words = 0xFFFF;
                    mdec_process_decode();
                    hle_out("[mdec] cmd1 decode complete: produced %zu words\n",
                            g_mdec.out_count);
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
