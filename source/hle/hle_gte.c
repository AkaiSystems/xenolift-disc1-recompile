/*
 * xenolift HLE - PS1 Geometry Transformation Engine (GTE) Coprocessor 2
 *
 * Spec reference: psx-spx "COP2 Geometry Transformation Engine (GTE)"
 * (Martin Korth, PSX SPCCON spec)
 */

#include "hle_gte.h"
#include "receipt_xprintf.h" /* R985 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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


/* UNR (Unsigned Newton-Raphson) Division Lookup Table (257 entries) */
static const uint8_t unr_table[257] = {
    0xFF, 0xFD, 0xFB, 0xF9, 0xF7, 0xF5, 0xF3, 0xF1, 0xEF, 0xEE, 0xEC, 0xEA, 0xE8, 0xE6, 0xE4, 0xE3,
    0xE1, 0xDF, 0xDD, 0xDC, 0xDA, 0xD8, 0xD6, 0xD5, 0xD3, 0xD1, 0xD0, 0xCE, 0xCD, 0xCB, 0xC9, 0xC8,
    0xC6, 0xC5, 0xC3, 0xC1, 0xC0, 0xBE, 0xBD, 0xBB, 0xBA, 0xB8, 0xB7, 0xB5, 0xB4, 0xB2, 0xB1, 0xB0,
    0xAE, 0xAD, 0xAB, 0xAA, 0xA9, 0xA7, 0xA6, 0xA4, 0xA3, 0xA2, 0xA0, 0x9F, 0x9E, 0x9C, 0x9B, 0x9A,
    0x99, 0x97, 0x96, 0x95, 0x94, 0x92, 0x91, 0x90, 0x8F, 0x8D, 0x8C, 0x8B, 0x8A, 0x89, 0x87, 0x86,
    0x85, 0x84, 0x83, 0x82, 0x81, 0x7F, 0x7E, 0x7D, 0x7C, 0x7B, 0x7A, 0x79, 0x78, 0x77, 0x75, 0x74,
    0x73, 0x72, 0x71, 0x70, 0x6F, 0x6E, 0x6D, 0x6C, 0x6B, 0x6A, 0x69, 0x68, 0x67, 0x66, 0x65, 0x64,
    0x63, 0x62, 0x61, 0x60, 0x5F, 0x5E, 0x5D, 0x5D, 0x5C, 0x5B, 0x5A, 0x59, 0x58, 0x57, 0x56, 0x55,
    0x54, 0x53, 0x53, 0x52, 0x51, 0x50, 0x4F, 0x4E, 0x4D, 0x4D, 0x4C, 0x4B, 0x4A, 0x49, 0x48, 0x48,
    0x47, 0x46, 0x45, 0x44, 0x43, 0x43, 0x42, 0x41, 0x40, 0x3F, 0x3F, 0x3E, 0x3D, 0x3C, 0x3C, 0x3B,
    0x3A, 0x39, 0x39, 0x38, 0x37, 0x36, 0x36, 0x35, 0x34, 0x33, 0x33, 0x32, 0x31, 0x31, 0x30, 0x2F,
    0x2E, 0x2E, 0x2D, 0x2C, 0x2C, 0x2B, 0x2A, 0x2A, 0x29, 0x28, 0x28, 0x27, 0x26, 0x26, 0x25, 0x24,
    0x24, 0x23, 0x22, 0x22, 0x21, 0x20, 0x20, 0x1F, 0x1E, 0x1E, 0x1D, 0x1D, 0x1C, 0x1B, 0x1B, 0x1A,
    0x19, 0x19, 0x18, 0x18, 0x17, 0x16, 0x16, 0x15, 0x15, 0x14, 0x14, 0x13, 0x12, 0x12, 0x11, 0x11,
    0x10, 0x0F, 0x0F, 0x0E, 0x0E, 0x0D, 0x0D, 0x0C, 0x0C, 0x0B, 0x0A, 0x0A, 0x09, 0x09, 0x08, 0x08,
    0x07, 0x07, 0x06, 0x06, 0x05, 0x05, 0x04, 0x04, 0x03, 0x03, 0x02, 0x02, 0x01, 0x01, 0x00, 0x00,
    0x00
};

/* Internal GTE Register File State */
typedef struct {
    /* Data Registers (cop2r0..31) */
    int16_t vx[3], vy[3], vz[3];  /* V0, V1, V2 */
    uint8_t rgbc[4];              /* R, G, B, CODE */
    uint16_t otz;                 /* OTZ */
    int16_t ir[4];                /* IR0, IR1, IR2, IR3 */
    int16_t sx[3], sy[3];         /* SXY0, SXY1, SXY2 */
    uint16_t sz[4];               /* SZ0, SZ1, SZ2, SZ3 */
    uint8_t rgb_fifo[3][4];       /* RGB0, RGB1, RGB2 */
    uint32_t res1;                /* RES1 */
    int64_t mac[4];               /* MAC0, MAC1, MAC2, MAC3 */
    uint32_t lzcs;                /* LZCS */

    /* Control Registers (cop2r32..63 / cnt0..31) */
    int16_t rt[3][3];             /* Rotation matrix RT11..RT33 */
    int32_t tr[3];                /* Translation vector TRX, TRY, TRZ */
    int16_t l[3][3];              /* Light matrix L11..L33 */
    int32_t bk[3];                /* Background color RBK, GBK, BBK */
    int16_t lcm[3][3];            /* Light color matrix LR1..LB3 */
    int32_t fc[3];                /* Far color RFC, GFC, BFC */
    int32_t ofx, ofy;             /* Screen offset OFX, OFY */
    uint16_t h;                   /* Projection distance H */
    int16_t dqa;                  /* Depth queuing A */
    int32_t dqb;                  /* Depth queuing B */
    int16_t zsf3, zsf4;           /* Z scale factors ZSF3, ZSF4 */
    uint32_t flag;                /* Error flags FLAG */
} gte_state_t;

static gte_state_t g_gte;

/* Reset GTE state */
void hle_gte_reset(void) {
    memset(&g_gte, 0, sizeof(g_gte));
}

/* Data Register Reads (cop2r0..31) */
uint32_t hle_gte_read_data(int reg) {
    reg &= 31;
    switch (reg) {
    case 0: return (uint32_t)(uint16_t)g_gte.vx[0] | ((uint32_t)(uint16_t)g_gte.vy[0] << 16);
    case 1: return (uint32_t)(int32_t)g_gte.vz[0];
    case 2: return (uint32_t)(uint16_t)g_gte.vx[1] | ((uint32_t)(uint16_t)g_gte.vy[1] << 16);
    case 3: return (uint32_t)(int32_t)g_gte.vz[1];
    case 4: return (uint32_t)(uint16_t)g_gte.vx[2] | ((uint32_t)(uint16_t)g_gte.vy[2] << 16);
    case 5: return (uint32_t)(int32_t)g_gte.vz[2];
    case 6: return (uint32_t)g_gte.rgbc[0] | ((uint32_t)g_gte.rgbc[1] << 8) |
                   ((uint32_t)g_gte.rgbc[2] << 16) | ((uint32_t)g_gte.rgbc[3] << 24);
    case 7: return (uint32_t)g_gte.otz;
    case 8: return (uint32_t)(int32_t)g_gte.ir[0];
    case 9: return (uint32_t)(int32_t)g_gte.ir[1];
    case 10: return (uint32_t)(int32_t)g_gte.ir[2];
    case 11: return (uint32_t)(int32_t)g_gte.ir[3];
    case 12: return (uint32_t)(uint16_t)g_gte.sx[0] | ((uint32_t)(uint16_t)g_gte.sy[0] << 16);
    case 13: return (uint32_t)(uint16_t)g_gte.sx[1] | ((uint32_t)(uint16_t)g_gte.sy[1] << 16);
    case 14: return (uint32_t)(uint16_t)g_gte.sx[2] | ((uint32_t)(uint16_t)g_gte.sy[2] << 16);
    case 15: return (uint32_t)(uint16_t)g_gte.sx[2] | ((uint32_t)(uint16_t)g_gte.sy[2] << 16); /* SXYP mirror */
    case 16: return (uint32_t)g_gte.sz[0];
    case 17: return (uint32_t)g_gte.sz[1];
    case 18: return (uint32_t)g_gte.sz[2];
    case 19: return (uint32_t)g_gte.sz[3];
    case 20: return (uint32_t)g_gte.rgb_fifo[0][0] | ((uint32_t)g_gte.rgb_fifo[0][1] << 8) |
                    ((uint32_t)g_gte.rgb_fifo[0][2] << 16) | ((uint32_t)g_gte.rgb_fifo[0][3] << 24);
    case 21: return (uint32_t)g_gte.rgb_fifo[1][0] | ((uint32_t)g_gte.rgb_fifo[1][1] << 8) |
                    ((uint32_t)g_gte.rgb_fifo[1][2] << 16) | ((uint32_t)g_gte.rgb_fifo[1][3] << 24);
    case 22: return (uint32_t)g_gte.rgb_fifo[2][0] | ((uint32_t)g_gte.rgb_fifo[2][1] << 8) |
                    ((uint32_t)g_gte.rgb_fifo[2][2] << 16) | ((uint32_t)g_gte.rgb_fifo[2][3] << 24);
    case 23: return g_gte.res1;
    case 24: return (uint32_t)(int32_t)g_gte.mac[0];
    case 25: return (uint32_t)(int32_t)g_gte.mac[1];
    case 26: return (uint32_t)(int32_t)g_gte.mac[2];
    case 27: return (uint32_t)(int32_t)g_gte.mac[3];
    case 28: return 0; /* IRGB read */
    case 29: { /* ORGB read */
        int r = g_gte.ir[1] / 128; if (r < 0) r = 0; if (r > 31) r = 31;
        int g = g_gte.ir[2] / 128; if (g < 0) g = 0; if (g > 31) g = 31;
        int b = g_gte.ir[3] / 128; if (b < 0) b = 0; if (b > 31) b = 31;
        return (uint32_t)(r | (g << 5) | (b << 10));
    }
    case 30: return g_gte.lzcs;
    case 31: { /* LZCR read */
        uint32_t v = g_gte.lzcs;
        if ((int32_t)v >= 0) {
            return v == 0 ? 32 : (uint32_t)__builtin_clz(v);
        } else {
            return v == 0xFFFFFFFFu ? 32 : (uint32_t)__builtin_clz(~v);
        }
    }
    default: return 0;
    }
}

/* Data Register Writes (cop2r0..31) */
void hle_gte_write_data(int reg, uint32_t v) {
    reg &= 31;
    switch (reg) {
    case 0: g_gte.vx[0] = (int16_t)(v & 0xFFFF); g_gte.vy[0] = (int16_t)(v >> 16); break;
    case 1: g_gte.vz[0] = (int16_t)(v & 0xFFFF); break;
    case 2: g_gte.vx[1] = (int16_t)(v & 0xFFFF); g_gte.vy[1] = (int16_t)(v >> 16); break;
    case 3: g_gte.vz[1] = (int16_t)(v & 0xFFFF); break;
    case 4: g_gte.vx[2] = (int16_t)(v & 0xFFFF); g_gte.vy[2] = (int16_t)(v >> 16); break;
    case 5: g_gte.vz[2] = (int16_t)(v & 0xFFFF); break;
    case 6:
        g_gte.rgbc[0] = v & 0xFF; g_gte.rgbc[1] = (v >> 8) & 0xFF;
        g_gte.rgbc[2] = (v >> 16) & 0xFF; g_gte.rgbc[3] = (v >> 24) & 0xFF;
        break;
    case 7: g_gte.otz = (uint16_t)(v & 0xFFFF); break;
    case 8: g_gte.ir[0] = (int16_t)(v & 0xFFFF); break;
    case 9: g_gte.ir[1] = (int16_t)(v & 0xFFFF); break;
    case 10: g_gte.ir[2] = (int16_t)(v & 0xFFFF); break;
    case 11: g_gte.ir[3] = (int16_t)(v & 0xFFFF); break;
    case 12: g_gte.sx[0] = (int16_t)(v & 0xFFFF); g_gte.sy[0] = (int16_t)(v >> 16); break;
    case 13: g_gte.sx[1] = (int16_t)(v & 0xFFFF); g_gte.sy[1] = (int16_t)(v >> 16); break;
    case 14: g_gte.sx[2] = (int16_t)(v & 0xFFFF); g_gte.sy[2] = (int16_t)(v >> 16); break;
    case 15: /* SXYP write: moves SXY2->SXY1, SXY1->SXY0, and writes SXY2 */
        g_gte.sx[0] = g_gte.sx[1]; g_gte.sy[0] = g_gte.sy[1];
        g_gte.sx[1] = g_gte.sx[2]; g_gte.sy[1] = g_gte.sy[2];
        g_gte.sx[2] = (int16_t)(v & 0xFFFF); g_gte.sy[2] = (int16_t)(v >> 16);
        break;
    case 16: g_gte.sz[0] = (uint16_t)(v & 0xFFFF); break;
    case 17: g_gte.sz[1] = (uint16_t)(v & 0xFFFF); break;
    case 18: g_gte.sz[2] = (uint16_t)(v & 0xFFFF); break;
    case 19: g_gte.sz[3] = (uint16_t)(v & 0xFFFF); break;
    case 20: g_gte.rgb_fifo[0][0] = v; g_gte.rgb_fifo[0][1] = v>>8; g_gte.rgb_fifo[0][2] = v>>16; g_gte.rgb_fifo[0][3] = v>>24; break;
    case 21: g_gte.rgb_fifo[1][0] = v; g_gte.rgb_fifo[1][1] = v>>8; g_gte.rgb_fifo[1][2] = v>>16; g_gte.rgb_fifo[1][3] = v>>24; break;
    case 22: g_gte.rgb_fifo[2][0] = v; g_gte.rgb_fifo[2][1] = v>>8; g_gte.rgb_fifo[2][2] = v>>16; g_gte.rgb_fifo[2][3] = v>>24; break;
    case 23: g_gte.res1 = v; break;
    case 24: g_gte.mac[0] = (int32_t)v; break;
    case 25: g_gte.mac[1] = (int32_t)v; break;
    case 26: g_gte.mac[2] = (int32_t)v; break;
    case 27: g_gte.mac[3] = (int32_t)v; break;
    case 28: /* IRGB write */
        g_gte.ir[1] = (int16_t)((v & 0x1F) * 0x80);
        g_gte.ir[2] = (int16_t)(((v >> 5) & 0x1F) * 0x80);
        g_gte.ir[3] = (int16_t)(((v >> 10) & 0x1F) * 0x80);
        break;
    case 29: break; /* ORGB is read-only */
    case 30: g_gte.lzcs = v; break;
    case 31: break; /* LZCR is read-only */
    }
}

/* Control Register Reads (cop2r32..63 / cnt0..31) */
uint32_t hle_gte_read_ctrl(int reg) {
    reg &= 31;
    switch (reg) {
    case 0: return (uint32_t)(uint16_t)g_gte.rt[0][0] | ((uint32_t)(uint16_t)g_gte.rt[0][1] << 16);
    case 1: return (uint32_t)(uint16_t)g_gte.rt[0][2] | ((uint32_t)(uint16_t)g_gte.rt[1][0] << 16);
    case 2: return (uint32_t)(uint16_t)g_gte.rt[1][1] | ((uint32_t)(uint16_t)g_gte.rt[1][2] << 16);
    case 3: return (uint32_t)(uint16_t)g_gte.rt[2][0] | ((uint32_t)(uint16_t)g_gte.rt[2][1] << 16);
    case 4: return (uint32_t)(int32_t)g_gte.rt[2][2];
    case 5: return (uint32_t)g_gte.tr[0];
    case 6: return (uint32_t)g_gte.tr[1];
    case 7: return (uint32_t)g_gte.tr[2];
    case 8: return (uint32_t)(uint16_t)g_gte.l[0][0] | ((uint32_t)(uint16_t)g_gte.l[0][1] << 16);
    case 9: return (uint32_t)(uint16_t)g_gte.l[0][2] | ((uint32_t)(uint16_t)g_gte.l[1][0] << 16);
    case 10: return (uint32_t)(uint16_t)g_gte.l[1][1] | ((uint32_t)(uint16_t)g_gte.l[1][2] << 16);
    case 11: return (uint32_t)(uint16_t)g_gte.l[2][0] | ((uint32_t)(uint16_t)g_gte.l[2][1] << 16);
    case 12: return (uint32_t)(int32_t)g_gte.l[2][2];
    case 13: return (uint32_t)g_gte.bk[0];
    case 14: return (uint32_t)g_gte.bk[1];
    case 15: return (uint32_t)g_gte.bk[2];
    case 16: return (uint32_t)(uint16_t)g_gte.lcm[0][0] | ((uint32_t)(uint16_t)g_gte.lcm[0][1] << 16);
    case 17: return (uint32_t)(uint16_t)g_gte.lcm[0][2] | ((uint32_t)(uint16_t)g_gte.lcm[1][0] << 16);
    case 18: return (uint32_t)(uint16_t)g_gte.lcm[1][1] | ((uint32_t)(uint16_t)g_gte.lcm[1][2] << 16);
    case 19: return (uint32_t)(uint16_t)g_gte.lcm[2][0] | ((uint32_t)(uint16_t)g_gte.lcm[2][1] << 16);
    case 20: return (uint32_t)(int32_t)g_gte.lcm[2][2];
    case 21: return (uint32_t)g_gte.fc[0];
    case 22: return (uint32_t)g_gte.fc[1];
    case 23: return (uint32_t)g_gte.fc[2];
    case 24: return (uint32_t)g_gte.ofx;
    case 25: return (uint32_t)g_gte.ofy;
    case 26: return (uint32_t)(int32_t)(int16_t)g_gte.h; /* PS1 hardware bug: H sign-expanded on CFC2 */
    case 27: return (uint32_t)(int32_t)g_gte.dqa;
    case 28: return (uint32_t)g_gte.dqb;
    case 29: return (uint32_t)(int32_t)g_gte.zsf3;
    case 30: return (uint32_t)(int32_t)g_gte.zsf4;
    case 31:
        return (g_gte.flag & 0x7FFFFFFF) | (((g_gte.flag & 0x7F87E000u) != 0) ? 0x80000000u : 0);
    default: return 0;
    }
}

/* Control Register Writes (cop2r32..63 / cnt0..31) */
void hle_gte_write_ctrl(int reg, uint32_t v) {
    reg &= 31;
    switch (reg) {
    case 0: g_gte.rt[0][0] = (int16_t)(v & 0xFFFF); g_gte.rt[0][1] = (int16_t)(v >> 16); break;
    case 1: g_gte.rt[0][2] = (int16_t)(v & 0xFFFF); g_gte.rt[1][0] = (int16_t)(v >> 16); break;
    case 2: g_gte.rt[1][1] = (int16_t)(v & 0xFFFF); g_gte.rt[1][2] = (int16_t)(v >> 16); break;
    case 3: g_gte.rt[2][0] = (int16_t)(v & 0xFFFF); g_gte.rt[2][1] = (int16_t)(v >> 16); break;
    case 4: g_gte.rt[2][2] = (int16_t)(v & 0xFFFF); break;
    case 5: g_gte.tr[0] = (int32_t)v; break;
    case 6: g_gte.tr[1] = (int32_t)v; break;
    case 7: g_gte.tr[2] = (int32_t)v; break;
    case 8: g_gte.l[0][0] = (int16_t)(v & 0xFFFF); g_gte.l[0][1] = (int16_t)(v >> 16); break;
    case 9: g_gte.l[0][2] = (int16_t)(v & 0xFFFF); g_gte.l[1][0] = (int16_t)(v >> 16); break;
    case 10: g_gte.l[1][1] = (int16_t)(v & 0xFFFF); g_gte.l[1][2] = (int16_t)(v >> 16); break;
    case 11: g_gte.l[2][0] = (int16_t)(v & 0xFFFF); g_gte.l[2][1] = (int16_t)(v >> 16); break;
    case 12: g_gte.l[2][2] = (int16_t)(v & 0xFFFF); break;
    case 13: g_gte.bk[0] = (int32_t)v; break;
    case 14: g_gte.bk[1] = (int32_t)v; break;
    case 15: g_gte.bk[2] = (int32_t)v; break;
    case 16: g_gte.lcm[0][0] = (int16_t)(v & 0xFFFF); g_gte.lcm[0][1] = (int16_t)(v >> 16); break;
    case 17: g_gte.lcm[0][2] = (int16_t)(v & 0xFFFF); g_gte.lcm[1][0] = (int16_t)(v >> 16); break;
    case 18: g_gte.lcm[1][1] = (int16_t)(v & 0xFFFF); g_gte.lcm[1][2] = (int16_t)(v >> 16); break;
    case 19: g_gte.lcm[2][0] = (int16_t)(v & 0xFFFF); g_gte.lcm[2][1] = (int16_t)(v >> 16); break;
    case 20: g_gte.lcm[2][2] = (int16_t)(v & 0xFFFF); break;
    case 21: g_gte.fc[0] = (int32_t)v; break;
    case 22: g_gte.fc[1] = (int32_t)v; break;
    case 23: g_gte.fc[2] = (int32_t)v; break;
    case 24: g_gte.ofx = (int32_t)v; break;
    case 25: g_gte.ofy = (int32_t)v; break;
    case 26: g_gte.h = (uint16_t)(v & 0xFFFF); break;
    case 27: g_gte.dqa = (int16_t)(v & 0xFFFF); break;
    case 28: g_gte.dqb = (int32_t)v; break;
    case 29: g_gte.zsf3 = (int16_t)(v & 0xFFFF); break;
    case 30: g_gte.zsf4 = (int16_t)(v & 0xFFFF); break;
    case 31: g_gte.flag = v & 0x7FFFFFFF; break; /* Bit 31 is read-only */
    }
}

/* Internal Overflow & Saturation Helpers */
static inline void check_mac_overflow_44(int64_t val, int idx) {
    if (val > 8796093022207LL) {
        g_gte.flag |= (1u << (30 - (idx - 1)));
    } else if (val < -8796093022208LL) {
        g_gte.flag |= (1u << (27 - (idx - 1)));
    }
}

static inline void check_mac0_overflow(int64_t val) {
    if (val > 2147483647LL) {
        g_gte.flag |= (1u << 16);
    } else if (val < -2147483648LL) {
        g_gte.flag |= (1u << 15);
    }
}

static inline int16_t clamp_ir(int64_t val, int lm, int idx) {
    int min_val = lm ? 0 : -32768;
    int max_val = 32767;
    if (val < min_val) {
        g_gte.flag |= (1u << (25 - idx));
        return (int16_t)min_val;
    }
    if (val > max_val) {
        g_gte.flag |= (1u << (25 - idx));
        return (int16_t)max_val;
    }
    return (int16_t)val;
}

static inline uint8_t clamp_color(int64_t val, int component) {
    if (val < 0) {
        g_gte.flag |= (1u << (21 - component));
        return 0;
    }
    if (val > 255) {
        g_gte.flag |= (1u << (21 - component));
        return 255;
    }
    return (uint8_t)val;
}

static inline void push_rgb(uint8_t r, uint8_t g, uint8_t b, uint8_t code) {
    g_gte.rgb_fifo[0][0] = g_gte.rgb_fifo[1][0];
    g_gte.rgb_fifo[0][1] = g_gte.rgb_fifo[1][1];
    g_gte.rgb_fifo[0][2] = g_gte.rgb_fifo[1][2];
    g_gte.rgb_fifo[0][3] = g_gte.rgb_fifo[1][3];

    g_gte.rgb_fifo[1][0] = g_gte.rgb_fifo[2][0];
    g_gte.rgb_fifo[1][1] = g_gte.rgb_fifo[2][1];
    g_gte.rgb_fifo[1][2] = g_gte.rgb_fifo[2][2];
    g_gte.rgb_fifo[1][3] = g_gte.rgb_fifo[2][3];

    g_gte.rgb_fifo[2][0] = r;
    g_gte.rgb_fifo[2][1] = g;
    g_gte.rgb_fifo[2][2] = b;
    g_gte.rgb_fifo[2][3] = code;
}

static inline void push_sxy(int16_t sx2, int16_t sy2) {
    g_gte.sx[0] = g_gte.sx[1]; g_gte.sy[0] = g_gte.sy[1];
    g_gte.sx[1] = g_gte.sx[2]; g_gte.sy[1] = g_gte.sy[2];
    g_gte.sx[2] = sx2;         g_gte.sy[2] = sy2;
}

static inline void push_sz(uint16_t sz3) {
    g_gte.sz[0] = g_gte.sz[1];
    g_gte.sz[1] = g_gte.sz[2];
    g_gte.sz[2] = g_gte.sz[3];
    g_gte.sz[3] = sz3;
}

/* UNR Division for RTPS / RTPT */
static inline uint32_t gte_divide(uint16_t h, uint16_t sz3) {
    if ((uint32_t)h < (uint32_t)sz3 * 2u) {
        int z = __builtin_clz((uint32_t)sz3) - 16;
        uint32_t n = (uint32_t)h << z;
        uint32_t d = (uint32_t)sz3 << z;
        uint32_t idx = (d - 0x7FC0u) >> 7;
        if (idx > 256) idx = 256;
        uint32_t u = (uint32_t)unr_table[idx] + 0x101u;
        d = (0x2000080u - d * u) >> 8;
        d = (0x0000080u + d * u) >> 8;
        n = (n * d + 0x8000u) >> 16;
        if (n > 0x1FFFFu) n = 0x1FFFFu;
        return n;
    } else {
        g_gte.flag |= (1u << 17);
        return 0x1FFFFu;
    }
}

/* Disassembler name table for 64 COP2 CO-functions */
static const char *const g_cmd_names[64] = {
    "NOP",   "RTPS",  "UNKN2", "UNKN3", "UNKN4", "UNKN5", "NCLIP", "UNKN7",
    "UNKN8", "UNKN9", "UNKNA", "UNKNB", "OP",    "UNKND", "UNKNE", "UNKNF",
    "DPCS",  "INTPL", "MVMVA", "NCDS",  "CDP",   "UNKN15","NCDT",  "UNKN17",
    "UNKN18","UNKN19","UNKN1A","NCCS",  "CC",    "UNKN1D","NCS",   "UNKN1F",
    "NCT",   "UNKN21","UNKN22","UNKN23","UNKN24","UNKN25","UNKN26","UNKN27",
    "SQR",   "DCPL",  "DPCT",  "UNKN2B","UNKN2C","AVSZ3", "AVSZ4", "UNKN2F",
    "RTPT",  "UNKN31","UNKN32","UNKN33","UNKN34","UNKN35","UNKN36","UNKN37",
    "UNKN38","UNKN39","UNKN3A","UNKN3B","UNKN3C","GPF",   "GPL",   "NCCT"
};

const char *hle_gte_disasm(uint32_t opcode) {
    uint32_t fn = opcode & 0x3Fu;
    return g_cmd_names[fn];
}

/* Execute Perspective Transformation for single vertex v_idx */
static void execute_rtps_vertex(int v_idx, int sf, int lm, int is_last) {
    int64_t mac1 = ((int64_t)g_gte.tr[0] << 12) +
                   (int64_t)g_gte.rt[0][0] * g_gte.vx[v_idx] +
                   (int64_t)g_gte.rt[0][1] * g_gte.vy[v_idx] +
                   (int64_t)g_gte.rt[0][2] * g_gte.vz[v_idx];
    int64_t mac2 = ((int64_t)g_gte.tr[1] << 12) +
                   (int64_t)g_gte.rt[1][0] * g_gte.vx[v_idx] +
                   (int64_t)g_gte.rt[1][1] * g_gte.vy[v_idx] +
                   (int64_t)g_gte.rt[1][2] * g_gte.vz[v_idx];
    int64_t mac3 = ((int64_t)g_gte.tr[2] << 12) +
                   (int64_t)g_gte.rt[2][0] * g_gte.vx[v_idx] +
                   (int64_t)g_gte.rt[2][1] * g_gte.vy[v_idx] +
                   (int64_t)g_gte.rt[2][2] * g_gte.vz[v_idx];

    check_mac_overflow_44(mac1, 1);
    check_mac_overflow_44(mac2, 2);
    check_mac_overflow_44(mac3, 3);

    g_gte.mac[1] = (int32_t)mac1;
    g_gte.mac[2] = (int32_t)mac2;
    g_gte.mac[3] = (int32_t)mac3;

    int64_t ir1_raw = mac1 >> (sf ? 12 : 0);
    int64_t ir2_raw = mac2 >> (sf ? 12 : 0);
    int64_t ir3_raw = mac3 >> (sf ? 12 : 0);

    g_gte.ir[1] = clamp_ir(ir1_raw, lm, 1);
    g_gte.ir[2] = clamp_ir(ir2_raw, lm, 2);

    /* IR3 clamping & FLAG.22 check for RTPS */
    if (ir3_raw < -32768 || ir3_raw > 32767) {
        g_gte.flag |= (1u << 22);
    }
    if (ir3_raw < -32768) g_gte.ir[3] = -32768;
    else if (ir3_raw > 32767) g_gte.ir[3] = 32767;
    else g_gte.ir[3] = (int16_t)ir3_raw;

    /* SZ3 calculation & FLAG.18 check */
    int64_t sz3_raw = mac3 >> (sf ? 12 : 0);
    uint16_t sz3_clamped;
    if (sz3_raw < 0) {
        sz3_clamped = 0;
        g_gte.flag |= (1u << 18);
    } else if (sz3_raw > 65535) {
        sz3_clamped = 65535;
        g_gte.flag |= (1u << 18);
    } else {
        sz3_clamped = (uint16_t)sz3_raw;
    }

    uint32_t n = gte_divide(g_gte.h, sz3_clamped);

    /* Screen X */
    int64_t mac0_x = (int64_t)n * g_gte.ir[1] + g_gte.ofx;
    check_mac0_overflow(mac0_x);
    g_gte.mac[0] = (int32_t)mac0_x;
    int64_t sx2_raw = mac0_x >> 16;
    int16_t sx2;
    if (sx2_raw < -1024) { sx2 = -1024; g_gte.flag |= (1u << 14); }
    else if (sx2_raw > 1023) { sx2 = 1023; g_gte.flag |= (1u << 14); }
    else sx2 = (int16_t)sx2_raw;

    /* Screen Y */
    int64_t mac0_y = (int64_t)n * g_gte.ir[2] + g_gte.ofy;
    check_mac0_overflow(mac0_y);
    g_gte.mac[0] = (int32_t)mac0_y;
    int64_t sy2_raw = mac0_y >> 16;
    int16_t sy2;
    if (sy2_raw < -1024) { sy2 = -1024; g_gte.flag |= (1u << 13); }
    else if (sy2_raw > 1023) { sy2 = 1023; g_gte.flag |= (1u << 13); }
    else sy2 = (int16_t)sy2_raw;

    /* Depth queuing IR0 (calculated ONLY for last vertex) */
    if (is_last) {
        int64_t mac0_dq = (int64_t)n * g_gte.dqa + g_gte.dqb;
        check_mac0_overflow(mac0_dq);
        g_gte.mac[0] = (int32_t)mac0_dq;
        int64_t ir0_raw = mac0_dq >> 12;
        if (ir0_raw < 0) { g_gte.ir[0] = 0; g_gte.flag |= (1u << 12); }
        else if (ir0_raw > 4096) { g_gte.ir[0] = 4096; g_gte.flag |= (1u << 12); }
        else g_gte.ir[0] = (int16_t)ir0_raw;
    }

    push_sxy(sx2, sy2);
    push_sz(sz3_clamped);
}

/* Execute COP2 Command */
void hle_gte_execute(uint32_t opcode) {
    uint32_t fn = opcode & 0x3Fu;
    int sf = 1;
    int mx = 0, v = 0, cv = 0, lm = 0;

    if (opcode > 0x3Fu) {
        sf = (opcode >> 19) & 1;
        mx = (opcode >> 17) & 3;
        v  = (opcode >> 15) & 3;
        cv = (opcode >> 13) & 3;
        lm = (opcode >> 10) & 1;
    } else {
        if (fn == 0x1C) lm = 1; /* CC default lm=1 */
    }

    /* Clear FLAG at start of command */
    g_gte.flag = 0;

    switch (fn) {
    case 0x01: /* RTPS */
        execute_rtps_vertex(0, sf, lm, 1);
        break;

    case 0x30: /* RTPT */
        execute_rtps_vertex(0, sf, lm, 0);
        execute_rtps_vertex(1, sf, lm, 0);
        execute_rtps_vertex(2, sf, lm, 1);
        break;

    case 0x06: { /* NCLIP */
        int64_t mac0 = (int64_t)g_gte.sx[0] * ((int64_t)g_gte.sy[1] - g_gte.sy[2]) +
                       (int64_t)g_gte.sx[1] * ((int64_t)g_gte.sy[2] - g_gte.sy[0]) +
                       (int64_t)g_gte.sx[2] * ((int64_t)g_gte.sy[0] - g_gte.sy[1]);
        check_mac0_overflow(mac0);
        g_gte.mac[0] = (int32_t)mac0;
        break;
    }

    case 0x2D: { /* AVSZ3 */
        int64_t mac0 = (int64_t)g_gte.zsf3 * ((uint32_t)g_gte.sz[1] + g_gte.sz[2] + g_gte.sz[3]);
        check_mac0_overflow(mac0);
        g_gte.mac[0] = (int32_t)mac0;
        int64_t otz_raw = mac0 >> 12;
        if (otz_raw < 0) { g_gte.otz = 0; g_gte.flag |= (1u << 18); }
        else if (otz_raw > 65535) { g_gte.otz = 65535; g_gte.flag |= (1u << 18); }
        else g_gte.otz = (uint16_t)otz_raw;
        break;
    }

    case 0x2E: { /* AVSZ4 */
        int64_t mac0 = (int64_t)g_gte.zsf4 * ((uint32_t)g_gte.sz[0] + g_gte.sz[1] + g_gte.sz[2] + g_gte.sz[3]);
        check_mac0_overflow(mac0);
        g_gte.mac[0] = (int32_t)mac0;
        int64_t otz_raw = mac0 >> 12;
        if (otz_raw < 0) { g_gte.otz = 0; g_gte.flag |= (1u << 18); }
        else if (otz_raw > 65535) { g_gte.otz = 65535; g_gte.flag |= (1u << 18); }
        else g_gte.otz = (uint16_t)otz_raw;
        break;
    }

    case 0x12: { /* MVMVA */
        const int16_t (*mat)[3];
        if (mx == 0) mat = (const int16_t (*)[3])g_gte.rt;
        else if (mx == 1) mat = (const int16_t (*)[3])g_gte.l;
        else if (mx == 2) mat = (const int16_t (*)[3])g_gte.lcm;
        else mat = (const int16_t (*)[3])g_gte.rt;

        int16_t vec[3];
        if (v == 0) { vec[0] = g_gte.vx[0]; vec[1] = g_gte.vy[0]; vec[2] = g_gte.vz[0]; }
        else if (v == 1) { vec[0] = g_gte.vx[1]; vec[1] = g_gte.vy[1]; vec[2] = g_gte.vz[1]; }
        else if (v == 2) { vec[0] = g_gte.vx[2]; vec[1] = g_gte.vy[2]; vec[2] = g_gte.vz[2]; }
        else { vec[0] = g_gte.ir[1]; vec[1] = g_gte.ir[2]; vec[2] = g_gte.ir[3]; }

        int32_t tr[3];
        if (cv == 0) { tr[0] = g_gte.tr[0]; tr[1] = g_gte.tr[1]; tr[2] = g_gte.tr[2]; }
        else if (cv == 1) { tr[0] = g_gte.bk[0]; tr[1] = g_gte.bk[1]; tr[2] = g_gte.bk[2]; }
        else if (cv == 2) { tr[0] = g_gte.fc[0]; tr[1] = g_gte.fc[1]; tr[2] = g_gte.fc[2]; }
        else { tr[0] = 0; tr[1] = 0; tr[2] = 0; }

        for (int i = 0; i < 3; i++) {
            int64_t mac_i = ((int64_t)tr[i] << 12) +
                            (int64_t)mat[i][0] * vec[0] +
                            (int64_t)mat[i][1] * vec[1] +
                            (int64_t)mat[i][2] * vec[2];
            check_mac_overflow_44(mac_i, i + 1);
            g_gte.mac[i + 1] = (int32_t)mac_i;
            int64_t shifted = mac_i >> (sf ? 12 : 0);
            g_gte.ir[i + 1] = clamp_ir(shifted, lm, i + 1);
        }
        break;
    }

    case 0x28: { /* SQR */
        for (int i = 0; i < 3; i++) {
            int64_t sq = ((int64_t)g_gte.ir[i + 1] * g_gte.ir[i + 1]) >> (sf ? 12 : 0);
            check_mac_overflow_44(sq, i + 1);
            g_gte.mac[i + 1] = (int32_t)sq;
            g_gte.ir[i + 1] = clamp_ir(sq, lm, i + 1);
        }
        break;
    }

    case 0x0C: { /* OP */
        int64_t op1 = ((int64_t)g_gte.ir[3] * g_gte.rt[1][1] - (int64_t)g_gte.ir[2] * g_gte.rt[2][2]) >> (sf ? 12 : 0);
        int64_t op2 = ((int64_t)g_gte.ir[1] * g_gte.rt[2][2] - (int64_t)g_gte.ir[3] * g_gte.rt[0][0]) >> (sf ? 12 : 0);
        int64_t op3 = ((int64_t)g_gte.ir[2] * g_gte.rt[0][0] - (int64_t)g_gte.ir[1] * g_gte.rt[1][1]) >> (sf ? 12 : 0);

        check_mac_overflow_44(op1, 1);
        check_mac_overflow_44(op2, 2);
        check_mac_overflow_44(op3, 3);

        g_gte.mac[1] = (int32_t)op1;
        g_gte.mac[2] = (int32_t)op2;
        g_gte.mac[3] = (int32_t)op3;

        g_gte.ir[1] = clamp_ir(op1, lm, 1);
        g_gte.ir[2] = clamp_ir(op2, lm, 2);
        g_gte.ir[3] = clamp_ir(op3, lm, 3);
        break;
    }

    case 0x1E: /* NCS */
    case 0x20: /* NCT */
    case 0x1B: /* NCCS */
    case 0x3F: /* NCCT */
    case 0x13: /* NCDS */
    case 0x16: { /* NCDT */
        int count = (fn == 0x20 || fn == 0x3F || fn == 0x16) ? 3 : 1;
        for (int k = 0; k < count; k++) {
            /* Step 1: LLM * Vk */
            int16_t vx = (k == 0) ? g_gte.vx[0] : ((k == 1) ? g_gte.vx[1] : g_gte.vx[2]);
            int16_t vy = (k == 0) ? g_gte.vy[0] : ((k == 1) ? g_gte.vy[1] : g_gte.vy[2]);
            int16_t vz = (k == 0) ? g_gte.vz[0] : ((k == 1) ? g_gte.vz[1] : g_gte.vz[2]);

            for (int i = 0; i < 3; i++) {
                int64_t mac_i = (int64_t)g_gte.l[i][0] * vx +
                                (int64_t)g_gte.l[i][1] * vy +
                                (int64_t)g_gte.l[i][2] * vz;
                check_mac_overflow_44(mac_i, i + 1);
                g_gte.mac[i + 1] = (int32_t)mac_i;
                g_gte.ir[i + 1] = clamp_ir(mac_i >> (sf ? 12 : 0), lm, i + 1);
            }

            /* Step 2: BK*0x1000 + LCM * IR */
            for (int i = 0; i < 3; i++) {
                int64_t mac_i = ((int64_t)g_gte.bk[i] << 12) +
                                (int64_t)g_gte.lcm[i][0] * g_gte.ir[1] +
                                (int64_t)g_gte.lcm[i][1] * g_gte.ir[2] +
                                (int64_t)g_gte.lcm[i][2] * g_gte.ir[3];
                check_mac_overflow_44(mac_i, i + 1);
                g_gte.mac[i + 1] = (int32_t)mac_i;
                g_gte.ir[i + 1] = clamp_ir(mac_i >> (sf ? 12 : 0), lm, i + 1);
            }

            /* Step 3: Color Multiply (for NCCS/NCCT/NCDS/NCDT) */
            if (fn == 0x1B || fn == 0x3F || fn == 0x13 || fn == 0x16) {
                for (int i = 0; i < 3; i++) {
                    int64_t mac_i = ((int64_t)g_gte.rgbc[i] * g_gte.ir[i + 1]) << 4;
                    check_mac_overflow_44(mac_i, i + 1);
                    g_gte.mac[i + 1] = (int32_t)mac_i;
                }
            }

            /* Step 4: Depth Cueing (for NCDS/NCDT) */
            if (fn == 0x13 || fn == 0x16) {
                for (int i = 0; i < 3; i++) {
                    int64_t diff = (((int64_t)g_gte.fc[i] << 12) - g_gte.mac[i + 1]) >> (sf ? 12 : 0);
                    int16_t sub_ir = clamp_ir(diff, 0, i + 1);
                    int64_t mac_i = ((int64_t)sub_ir * g_gte.ir[0]) + g_gte.mac[i + 1];
                    check_mac_overflow_44(mac_i, i + 1);
                    g_gte.mac[i + 1] = (int32_t)mac_i;
                    g_gte.ir[i + 1] = clamp_ir(mac_i >> (sf ? 12 : 0), lm, i + 1);
                }
            }

            uint8_t cr = clamp_color(g_gte.mac[1] >> 4, 0);
            uint8_t cg = clamp_color(g_gte.mac[2] >> 4, 1);
            uint8_t cb = clamp_color(g_gte.mac[3] >> 4, 2);
            push_rgb(cr, cg, cb, g_gte.rgbc[3]);
        }
        break;
    }

    case 0x1C: /* CC */
    case 0x14: { /* CDP */
        /* Step 1: BK*0x1000 + LCM * IR */
        for (int i = 0; i < 3; i++) {
            int64_t mac_i = ((int64_t)g_gte.bk[i] << 12) +
                            (int64_t)g_gte.lcm[i][0] * g_gte.ir[1] +
                            (int64_t)g_gte.lcm[i][1] * g_gte.ir[2] +
                            (int64_t)g_gte.lcm[i][2] * g_gte.ir[3];
            check_mac_overflow_44(mac_i, i + 1);
            g_gte.mac[i + 1] = (int32_t)mac_i;
            g_gte.ir[i + 1] = clamp_ir(mac_i >> (sf ? 12 : 0), lm, i + 1);
        }

        /* Step 2: Primary color multiply */
        for (int i = 0; i < 3; i++) {
            int64_t mac_i = ((int64_t)g_gte.rgbc[i] * g_gte.ir[i + 1]) << 4;
            check_mac_overflow_44(mac_i, i + 1);
            g_gte.mac[i + 1] = (int32_t)mac_i;
        }

        /* Step 3: Depth Cueing (for CDP only) */
        if (fn == 0x14) {
            for (int i = 0; i < 3; i++) {
                int64_t diff = (((int64_t)g_gte.fc[i] << 12) - g_gte.mac[i + 1]) >> (sf ? 12 : 0);
                int16_t sub_ir = clamp_ir(diff, 0, i + 1);
                int64_t mac_i = ((int64_t)sub_ir * g_gte.ir[0]) + g_gte.mac[i + 1];
                check_mac_overflow_44(mac_i, i + 1);
                g_gte.mac[i + 1] = (int32_t)mac_i;
                g_gte.ir[i + 1] = clamp_ir(mac_i >> (sf ? 12 : 0), lm, i + 1);
            }
        } else {
            for (int i = 0; i < 3; i++) {
                int64_t shifted = g_gte.mac[i + 1] >> (sf ? 12 : 0);
                g_gte.ir[i + 1] = clamp_ir(shifted, lm, i + 1);
            }
        }

        uint8_t cr = clamp_color(g_gte.mac[1] >> 4, 0);
        uint8_t cg = clamp_color(g_gte.mac[2] >> 4, 1);
        uint8_t cb = clamp_color(g_gte.mac[3] >> 4, 2);
        push_rgb(cr, cg, cb, g_gte.rgbc[3]);
        break;
    }

    case 0x10: /* DPCS */
    case 0x2A: /* DPCT */
    case 0x29: /* DCPL */
    case 0x11: { /* INTPL */
        int count = (fn == 0x2A) ? 3 : 1;
        for (int k = 0; k < count; k++) {
            uint8_t r_in, g_in, b_in;
            if (fn == 0x2A) {
                /* DPCT reads R,G,B from bottom of Color FIFO (RGB0) */
                r_in = g_gte.rgb_fifo[0][0];
                g_in = g_gte.rgb_fifo[0][1];
                b_in = g_gte.rgb_fifo[0][2];
            } else {
                r_in = g_gte.rgbc[0];
                g_in = g_gte.rgbc[1];
                b_in = g_gte.rgbc[2];
            }

            if (fn == 0x29) { /* DCPL: [R*IR1, G*IR2, B*IR3] << 4 */
                g_gte.mac[1] = ((int64_t)r_in * g_gte.ir[1]) << 4;
                g_gte.mac[2] = ((int64_t)g_in * g_gte.ir[2]) << 4;
                g_gte.mac[3] = ((int64_t)b_in * g_gte.ir[3]) << 4;
            } else if (fn == 0x11) { /* INTPL: [IR1, IR2, IR3] << 12 */
                g_gte.mac[1] = (int64_t)g_gte.ir[1] << 12;
                g_gte.mac[2] = (int64_t)g_gte.ir[2] << 12;
                g_gte.mac[3] = (int64_t)g_gte.ir[3] << 12;
            } else { /* DPCS / DPCT: [R, G, B] << 16 */
                g_gte.mac[1] = (int64_t)r_in << 16;
                g_gte.mac[2] = (int64_t)g_in << 16;
                g_gte.mac[3] = (int64_t)b_in << 16;
            }

            for (int i = 0; i < 3; i++) {
                int64_t diff = (((int64_t)g_gte.fc[i] << 12) - g_gte.mac[i + 1]) >> (sf ? 12 : 0);
                int16_t sub_ir = clamp_ir(diff, 0, i + 1);
                int64_t mac_i = ((int64_t)sub_ir * g_gte.ir[0]) + g_gte.mac[i + 1];
                check_mac_overflow_44(mac_i, i + 1);
                g_gte.mac[i + 1] = (int32_t)mac_i;
                g_gte.ir[i + 1] = clamp_ir(mac_i >> (sf ? 12 : 0), lm, i + 1);
            }

            uint8_t cr = clamp_color(g_gte.mac[1] >> 4, 0);
            uint8_t cg = clamp_color(g_gte.mac[2] >> 4, 1);
            uint8_t cb = clamp_color(g_gte.mac[3] >> 4, 2);
            push_rgb(cr, cg, cb, g_gte.rgbc[3]);
        }
        break;
    }

    case 0x3D: { /* GPF */
        for (int i = 0; i < 3; i++) {
            int64_t mac_i = ((int64_t)g_gte.ir[i + 1] * g_gte.ir[0]) >> (sf ? 12 : 0);
            check_mac_overflow_44(mac_i, i + 1);
            g_gte.mac[i + 1] = (int32_t)mac_i;
            g_gte.ir[i + 1] = clamp_ir(mac_i, lm, i + 1);
        }
        uint8_t cr = clamp_color(g_gte.mac[1] >> 4, 0);
        uint8_t cg = clamp_color(g_gte.mac[2] >> 4, 1);
        uint8_t cb = clamp_color(g_gte.mac[3] >> 4, 2);
        push_rgb(cr, cg, cb, g_gte.rgbc[3]);
        break;
    }

    case 0x3E: { /* GPL */
        for (int i = 0; i < 3; i++) {
            int64_t base = g_gte.mac[i + 1] << (sf ? 12 : 0);
            int64_t mac_i = (base + (int64_t)g_gte.ir[i + 1] * g_gte.ir[0]) >> (sf ? 12 : 0);
            check_mac_overflow_44(mac_i, i + 1);
            g_gte.mac[i + 1] = (int32_t)mac_i;
            g_gte.ir[i + 1] = clamp_ir(mac_i, lm, i + 1);
        }
        uint8_t cr = clamp_color(g_gte.mac[1] >> 4, 0);
        uint8_t cg = clamp_color(g_gte.mac[2] >> 4, 1);
        uint8_t cb = clamp_color(g_gte.mac[3] >> 4, 2);
        push_rgb(cr, cg, cb, g_gte.rgbc[3]);
        break;
    }

    default:
        /* Unmapped or reserved COP2 opcode: no-op, clear FLAG at start */
        break;
    }
}
