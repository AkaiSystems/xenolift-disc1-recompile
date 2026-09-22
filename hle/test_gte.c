/*
 * xenolift HLE - PS1 GTE Standalone Unit Tests
 */

#include "hle_gte.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int g_failed = 0;

#define ASSERT_EQ(actual, expected, name) \
    do { \
        if ((actual) != (expected)) { \
            fprintf(stderr, "FAIL: %s: got %ld, expected %ld\n", name, (long)(actual), (long)(expected)); \
            g_failed++; \
        } \
    } while (0)

#define ASSERT_TRUE(cond, name) \
    do { \
        if (!(cond)) { \
            fprintf(stderr, "FAIL: %s\n", name); \
            g_failed++; \
        } \
    } while (0)

/*
 * Hand Derivation of Identity RTPS Test:
 * ---------------------------------------
 * Setup:
 *   Identity Matrix RT:
 *     RT11=0x1000 (1.0), RT12=0, RT13=0
 *     RT21=0, RT22=0x1000 (1.0), RT23=0
 *     RT31=0, RT32=0, RT33=0x1000 (1.0)
 *   TR Vector: TRX=0, TRY=0, TRZ=0
 *   Screen Offsets: OFX = 160 << 16 = 10485760 (0x00A00000), OFY = 120 << 16 = 7864320 (0x00780000)
 *   Distance H: 256 (0x0100)
 *   Depth Cueing: DQA = 128 (0.5), DQB = 0
 *   Input Vertex V0: VX0 = 100, VY0 = 50, VZ0 = 512
 *
 * Calculations (sf=1):
 *   1. Transformed Vector:
 *      MAC1 = TRX*4096 + RT11*100 + RT12*50 + RT13*512 = 0 + 409600 = 409600
 *      IR1  = MAC1 >> 12 = 100
 *      MAC2 = TRY*4096 + RT21*100 + RT22*50 + RT23*512 = 0 + 204800 = 204800
 *      IR2  = MAC2 >> 12 = 50
 *      MAC3 = TRZ*4096 + RT31*100 + RT32*50 + RT33*512 = 0 + 2097152 = 2097152
 *      IR3  = MAC3 >> 12 = 512
 *      SZ3  = 512 (0x0200)
 *
 *   2. Perspective Division (UNR table with H=256, SZ3=512):
 *      Check H < SZ3 * 2 => 256 < 1024 => True
 *      z = clz_16(512) = 6
 *      n_in = 256 << 6 = 16384 (0x4000)
 *      d_in = 512 << 6 = 32768 (0x8000)
 *      tbl_idx = (32768 - 0x7FC0) >> 7 = 0
 *      u = unr_table[0] + 0x101 = 0xFF + 0x101 = 0x200 (512)
 *      d1 = (0x2000080 - 32768 * 512) >> 8 = 0x10000
 *      d2 = (0x0000080 + 65536 * 512) >> 8 = 0x20000
 *      n = (16384 * 131072 + 0x8000) >> 16 = 32768 (0x8000)
 *
 *   3. Screen Coordinates:
 *      MAC0_x = n * IR1 + OFX = 32768 * 100 + (160 << 16) = 13762560 -> SX2 = 13762560 >> 16 = 210
 *      MAC0_y = n * IR2 + OFY = 32768 * 50 + (120 << 16) = 9502720 -> SY2 = 9502720 >> 16 = 145
 *
 *   4. Depth Cueing:
 *      MAC0_dq = n * DQA + DQB = 32768 * 128 + 0 = 4194304 -> IR0 = 4194304 >> 12 = 1024
 *
 *   5. Error FLAG:
 *      FLAG = 0
 */
static void test_identity_rtps(void) {
    printf("[test] Running test_identity_rtps...\n");
    hle_gte_reset();

    /* Set Identity RT Matrix */
    hle_gte_write_ctrl(0, 0x00001000); /* RT11 = 0x1000, RT12 = 0 */
    hle_gte_write_ctrl(1, 0x00000000); /* RT13 = 0, RT21 = 0 */
    hle_gte_write_ctrl(2, 0x00001000); /* RT22 = 0x1000, RT23 = 0 */
    hle_gte_write_ctrl(3, 0x00000000); /* RT31 = 0, RT32 = 0 */
    hle_gte_write_ctrl(4, 0x00001000); /* RT33 = 0x1000 */

    /* Set TR = (0, 0, 0) */
    hle_gte_write_ctrl(5, 0);
    hle_gte_write_ctrl(6, 0);
    hle_gte_write_ctrl(7, 0);

    /* Set Offsets & Camera Params */
    hle_gte_write_ctrl(24, 160 << 16); /* OFX = 160.0 */
    hle_gte_write_ctrl(25, 120 << 16); /* OFY = 120.0 */
    hle_gte_write_ctrl(26, 256);        /* H = 256 */
    hle_gte_write_ctrl(27, 128);        /* DQA = 128 */
    hle_gte_write_ctrl(28, 0);          /* DQB = 0 */

    /* Input Vertex V0 = (100, 50, 512) */
    hle_gte_write_data(0, (100 & 0xFFFF) | ((50 & 0xFFFF) << 16)); /* VX0, VY0 */
    hle_gte_write_data(1, 512);                                   /* VZ0 */

    /* Execute RTPS (0x01080001 = RTPS with sf=1) */
    hle_gte_execute(0x01080001);

    /* Read Results */
    uint32_t sxy2 = hle_gte_read_data(14);
    int16_t sx2 = (int16_t)(sxy2 & 0xFFFF);
    int16_t sy2 = (int16_t)(sxy2 >> 16);
    uint32_t sz3 = hle_gte_read_data(19);
    int16_t ir0 = (int16_t)hle_gte_read_data(8);
    int16_t ir1 = (int16_t)hle_gte_read_data(9);
    int16_t ir2 = (int16_t)hle_gte_read_data(10);
    int16_t ir3 = (int16_t)hle_gte_read_data(11);
    uint32_t flag = hle_gte_read_ctrl(31);

    ASSERT_EQ(sx2, 210, "RTPS SX2");
    ASSERT_EQ(sy2, 145, "RTPS SY2");
    ASSERT_EQ(sz3, 512, "RTPS SZ3");
    ASSERT_EQ(ir0, 1024, "RTPS IR0");
    ASSERT_EQ(ir1, 100, "RTPS IR1");
    ASSERT_EQ(ir2, 50, "RTPS IR2");
    ASSERT_EQ(ir3, 512, "RTPS IR3");
    ASSERT_EQ(flag, 0, "RTPS FLAG");
}

static void test_mvmva_passthrough(void) {
    printf("[test] Running test_mvmva_passthrough...\n");
    hle_gte_reset();

    /* Identity RT */
    hle_gte_write_ctrl(0, 0x00001000);
    hle_gte_write_ctrl(1, 0x00000000);
    hle_gte_write_ctrl(2, 0x00001000);
    hle_gte_write_ctrl(3, 0x00000000);
    hle_gte_write_ctrl(4, 0x00001000);

    /* V0 = (123, -456, 789) */
    hle_gte_write_data(0, (123 & 0xFFFF) | (((uint32_t)(uint16_t)-456) << 16));
    hle_gte_write_data(1, 789);

    /* Execute MVMVA with mx=0 (RT), v=0 (V0), cv=3 (None), sf=1, lm=0 */
    /* Code = 0x01086012 */
    hle_gte_execute(0x01086012);

    int16_t ir1 = (int16_t)hle_gte_read_data(9);
    int16_t ir2 = (int16_t)hle_gte_read_data(10);
    int16_t ir3 = (int16_t)hle_gte_read_data(11);
    uint32_t flag = hle_gte_read_ctrl(31);

    ASSERT_EQ(ir1, 123, "MVMVA IR1");
    ASSERT_EQ(ir2, -456, "MVMVA IR2");
    ASSERT_EQ(ir3, 789, "MVMVA IR3");
    ASSERT_EQ(flag, 0, "MVMVA FLAG");
}

static void test_rotation_z_90(void) {
    printf("[test] Running test_rotation_z_90...\n");
    hle_gte_reset();

    /* RT 90 deg around Z:
     * RT11 = 0, RT12 = -0x1000 (0xF000)
     * RT13 = 0, RT21 = 0x1000
     * RT22 = 0, RT23 = 0
     * RT31 = 0, RT32 = 0
     * RT33 = 0x1000
     */
    hle_gte_write_ctrl(0, 0xF0000000u); /* RT11 = 0, RT12 = -0x1000 */
    hle_gte_write_ctrl(1, 0x10000000u); /* RT13 = 0, RT21 = 0x1000 */
    hle_gte_write_ctrl(2, 0x00000000u); /* RT22 = 0, RT23 = 0 */
    hle_gte_write_ctrl(3, 0x00000000u); /* RT31 = 0, RT32 = 0 */
    hle_gte_write_ctrl(4, 0x00001000u); /* RT33 = 0x1000 */

    /* V0 = (100, 200, 300) */
    hle_gte_write_data(0, (100 & 0xFFFF) | ((200 & 0xFFFF) << 16));
    hle_gte_write_data(1, 300);

    /* MVMVA sf=1, mx=0, v=0, cv=3, lm=0 */
    hle_gte_execute(0x01086012);

    int16_t ir1 = (int16_t)hle_gte_read_data(9);
    int16_t ir2 = (int16_t)hle_gte_read_data(10);
    int16_t ir3 = (int16_t)hle_gte_read_data(11);
    uint32_t flag = hle_gte_read_ctrl(31);

    ASSERT_EQ(ir1, -200, "Rotate Z 90 IR1");
    ASSERT_EQ(ir2, 100, "Rotate Z 90 IR2");
    ASSERT_EQ(ir3, 300, "Rotate Z 90 IR3");
    ASSERT_EQ(flag, 0, "Rotate Z 90 FLAG");
}

static void test_nclip(void) {
    printf("[test] Running test_nclip...\n");
    hle_gte_reset();

    /* CCW Triangle: SXY0=(0,0), SXY1=(10,0), SXY2=(0,10) */
    hle_gte_write_data(12, 0);
    hle_gte_write_data(13, 10 & 0xFFFF);
    hle_gte_write_data(14, (10 & 0xFFFF) << 16);

    hle_gte_execute(0x06); /* NCLIP */
    int32_t mac0_ccw = (int32_t)hle_gte_read_data(24);

    /* CW Triangle: SXY0=(0,0), SXY1=(0,10), SXY2=(10,0) */
    hle_gte_write_data(12, 0);
    hle_gte_write_data(13, (10 & 0xFFFF) << 16);
    hle_gte_write_data(14, 10 & 0xFFFF);

    hle_gte_execute(0x06); /* NCLIP */
    int32_t mac0_cw = (int32_t)hle_gte_read_data(24);

    ASSERT_TRUE(mac0_ccw > 0, "NCLIP CCW positive");
    ASSERT_TRUE(mac0_cw < 0, "NCLIP CW negative");
    ASSERT_EQ(mac0_ccw, -mac0_cw, "NCLIP opposite signs");
}

static void test_avsz3(void) {
    printf("[test] Running test_avsz3...\n");
    hle_gte_reset();

    /* SZ1 = 1000, SZ2 = 2000, SZ3 = 3000 */
    hle_gte_write_data(17, 1000);
    hle_gte_write_data(18, 2000);
    hle_gte_write_data(19, 3000);

    /* ZSF3 = 1365 (0x0555, ~1/3 in 1.3.12) */
    hle_gte_write_ctrl(29, 0x0555);

    hle_gte_execute(0x2D); /* AVSZ3 */

    uint32_t otz = hle_gte_read_data(7);
    ASSERT_EQ(otz, 1999, "AVSZ3 OTZ");
}

static void test_overflow_cases(void) {
    printf("[test] Running test_overflow_cases...\n");
    hle_gte_reset();

    /* Set huge V0 */
    hle_gte_write_data(0, 30000 | (30000 << 16));
    hle_gte_write_data(1, 30000);

    /* Set huge matrix elements */
    hle_gte_write_ctrl(0, 0x7FFF7FFF);
    hle_gte_write_ctrl(1, 0x7FFF7FFF);
    hle_gte_write_ctrl(2, 0x7FFF7FFF);
    hle_gte_write_ctrl(3, 0x7FFF7FFF);
    hle_gte_write_ctrl(4, 0x7FFF);

    /* Set huge TR */
    hle_gte_write_ctrl(5, 0x7FFFFFFF);
    hle_gte_write_ctrl(6, 0x7FFFFFFF);
    hle_gte_write_ctrl(7, 0x7FFFFFFF);

    /* Execute MVMVA with sf=0 */
    hle_gte_execute(0x00000012);

    uint32_t flag = hle_gte_read_ctrl(31);
    ASSERT_TRUE((flag & 0x70000000u) != 0, "44-bit positive overflow set in FLAG");
}

static void test_smoke_loop(void) {
    printf("[test] Running test_smoke_loop...\n");
    hle_gte_reset();

    /* Execute all 64 CO-functions */
    for (uint32_t fn = 0; fn < 64; fn++) {
        hle_gte_execute(fn);
        const char *name = hle_gte_disasm(fn);
        ASSERT_TRUE(name != NULL, "Disasm name not null");
    }

    /* Execute all 256 opcode byte combinations */
    for (uint32_t op = 0; op < 256; op++) {
        hle_gte_execute(op);
    }
}

int main(void) {
    printf("=== Xenolift GTE Submodule Unit Tests ===\n");
    test_identity_rtps();
    test_mvmva_passthrough();
    test_rotation_z_90();
    test_nclip();
    test_avsz3();
    test_overflow_cases();
    test_smoke_loop();

    if (g_failed == 0) {
        printf("ALL GTE TESTS PASSED!\n");
        return 0;
    } else {
        printf("GTE TESTS FAILED (%d failures)!\n", g_failed);
        return 1;
    }
}
