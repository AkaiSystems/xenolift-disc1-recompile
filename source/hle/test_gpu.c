/*
 * test_gpu.c - Standalone test suite for hle_gpu module
 * xenolift project - tests GP0/GP1 commands, VRAM blits, CLUT rects, quads, blending
 */

#include "hle_gpu.h"
#include <stdio.h>
#include <stdlib.h>
#include <assert.h>

static int g_tests_passed = 0;
static int g_tests_failed = 0;

#define TEST_ASSERT(cond, msg) \
    do { \
        if (cond) { \
            g_tests_passed++; \
        } else { \
            g_tests_failed++; \
            fprintf(stderr, "FAIL: %s (line %d): %s\n", __func__, __LINE__, msg); \
        } \
    } while (0)

static void test_init_and_fill(void)
{
    gpu_init();

    uint16_t x, y, w, h;
    gpu_display_area(&x, &y, &w, &h);
    TEST_ASSERT(x == 0 && y == 0 && w == 320 && h == 240, "Default display area 320x240 @ (0,0)");

    /* GP0 0x02: Fill Rect X=32, Y=32, W=16, H=16 with Pure Red (RGB 255,0,0) */
    gpu_gp0_write(0x020000FFu); /* Word 0: 0x02, R=255, G=0, B=0 */
    gpu_gp0_write((32u << 16) | 32u); /* Word 1: Y=32, X=32 */
    gpu_gp0_write((16u << 16) | 16u); /* Word 2: H=16, W=16 */

    /* Red 15bpp BGR555: R=31 -> 0x001F */
    TEST_ASSERT(gpu_vram_peek(32, 32) == 0x001F, "Fill rect pixel at (32,32) is Red 0x001F");
    TEST_ASSERT(gpu_vram_peek(47, 47) == 0x001F, "Fill rect pixel at (47,47) is Red 0x001F");
    TEST_ASSERT(gpu_vram_peek(0, 0) == 0x0000, "VRAM outside fill rect remains 0x0000");
}

static void test_cpu_to_vram_and_clut_rect(void)
{
    gpu_init();

    /* Set Drawing Area top-left (0,0) and bottom-right (1023,511) */
    gpu_gp0_write(0xE3000000u); /* E3: (0,0) */
    gpu_gp0_write(0xE407FCFFu); /* E4: (1023,511) */
    gpu_gp0_write(0xE5000000u); /* E5: Offset (0,0) */

    /* 1. Upload 4bpp CLUT palette (16 halfwords = 8 words) to VRAM at (0, 256) via GP0 0xA0 */
    gpu_gp0_write(0xA0000000u);           /* Header 0: CPU-to-VRAM */
    gpu_gp0_write((256u << 16) | 0u);     /* Header 1: Y=256, X=0 */
    gpu_gp0_write((1u << 16) | 16u);      /* Header 2: H=1, W=16 */
    /* 8 words (2 pixels per word): entry 0=0x0000 (trans), 1=0x03E0 (green), 2=0x7C00 (blue) */
    gpu_gp0_write(0x03E00000u);           /* Entry 0: 0x0000, Entry 1: 0x03E0 */
    gpu_gp0_write(0x00007C00u);           /* Entry 2: 0x7C00, Entry 3: 0x0000 */
    gpu_gp0_write(0x00000000u);
    gpu_gp0_write(0x00000000u);
    gpu_gp0_write(0x00000000u);
    gpu_gp0_write(0x00000000u);
    gpu_gp0_write(0x00000000u);
    gpu_gp0_write(0x00000000u);

    TEST_ASSERT(gpu_vram_peek(0, 256) == 0x0000, "CLUT entry 0 is transparent");
    TEST_ASSERT(gpu_vram_peek(1, 256) == 0x03E0, "CLUT entry 1 is Green 0x03E0");
    TEST_ASSERT(gpu_vram_peek(2, 256) == 0x7C00, "CLUT entry 2 is Blue 0x7C00");

    /* 2. Upload 4bpp texture image 8x8 pixels = 2x8 VRAM words = 16 halfwords = 8 words at (0, 260) */
    gpu_gp0_write(0xA0000000u);
    gpu_gp0_write((260u << 16) | 0u);     /* Y=260, X=0 */
    gpu_gp0_write((8u << 16) | 2u);       /* H=8, W=2 halfwords = 8 4bpp pixels per row */
    /* Row 0: all palette 1 (0x1111 0x1111 -> 4 nibbles of 1 per halfword) */
    gpu_gp0_write(0x11111111u);
    /* Row 1: all palette 2 (0x2222 0x2222) */
    gpu_gp0_write(0x22222222u);
    /* Rows 2-7: 0 */
    for (int i = 0; i < 6; i++) gpu_gp0_write(0x00000000u);

    /* Texpage: 4bpp (TP=0), PageX=0, PageY=1 (Y=256) -> bits: PageY=1 (bit 4=1), TP=0 -> 0x0010 */
    gpu_gp0_write(0xE1000010u);

    /* 3. Draw 8x8 CLUT textured rect at (40, 40) via GP0 0x72 (8x8 textured rect, raw texture) */
    /* CLUT attribute for X=0, Y=256: (256 << 6) | (0 / 16) = 0x4000. Texture row 0 is at V=4 relative to PageY=256 */
    gpu_gp0_write(0x75000000u);           /* Word 0: 0x72, raw textured rect */
    gpu_gp0_write((40u << 16) | 40u);     /* Word 1: Y=40, X=40 */
    gpu_gp0_write((0x4000u << 16) | (4u << 8) | 0u);  /* Word 2: CLUT=0x4000, V=4, U=0 */

    TEST_ASSERT(gpu_vram_peek(40, 40) == 0x03E0, "Textured rect row 0 is Green (CLUT 1)");
    TEST_ASSERT(gpu_vram_peek(40, 41) == 0x7C00, "Textured rect row 1 is Blue (CLUT 2)");
}

static void test_quad_stream_and_blending(void)
{
    gpu_init();

    /* 1. Fill background rect (100,100) size 32x32 with Blue (RGB 0,0,255 -> 0x7C00) */
    gpu_gp0_write(0x02FF0000u);           /* Word 0: Fill Blue */
    gpu_gp0_write((100u << 16) | 100u);
    gpu_gp0_write((32u << 16) | 32u);

    TEST_ASSERT(gpu_vram_peek(110, 110) == 0x7C00, "Background is Blue 0x7C00");

    /* 2. Set Texpage to ABR Mode 0 (0.5 Back + 0.5 Front) -> bits 5-6 = 00 */
    gpu_gp0_write(0xE1000000u);

    /* 3. Draw semi-transparent flat untextured quad (0x2C) with Red (RGB 255,0,0 -> 0x001F) */
    gpu_gp0_write(0x2A0000FFu);           /* Word 0: 0x2C (quad, semi-trans), Red */
    gpu_gp0_write((100u << 16) | 100u);   /* V0: (100, 100) */
    gpu_gp0_write((100u << 16) | 131u);   /* V1: (131, 100) */
    gpu_gp0_write((131u << 16) | 100u);   /* V2: (100, 131) */
    gpu_gp0_write((131u << 16) | 131u);   /* V3: (131, 131) */

    /* Blended value: 0.5 * Blue(0x7C00) + 0.5 * Red(0x001F) = B=15, G=0, R=15 -> 0x3C0F */
    uint16_t blended_px = gpu_vram_peek(110, 110);
    TEST_ASSERT(blended_px == 0x3C0F, "Semi-transparent quad blended Blue + Red to 0x3C0F");
}

static void test_gp1_and_snapshot(void)
{
    gpu_init();

    /* Put a distinctive pixel in VRAM */
    gpu_vram_poke(10, 20, 0x1234);

    /* GP1 0x05: Display Area Start X=64, Y=32 */
    gpu_gp1_write(0x05008040u);           /* (32 << 10) | 64 = 0x8040 */
    /* GP1 0x08: Display Mode 512x480 */
    gpu_gp1_write(0x08000024u);           /* hres=512 (code 2 -> bit 5), vres=480 (bit 2) */

    uint16_t dx, dy, dw, dh;
    gpu_display_area(&dx, &dy, &dw, &dh);
    TEST_ASSERT(dx == 64 && dy == 32, "GP1(0x05) sets display origin (64, 32)");
    TEST_ASSERT(dw == 512 && dh == 480, "GP1(0x08) sets display mode 512x480");

    /* Test VRAM Snapshot */
    static uint16_t snap_buf[GPU_VRAM_SIZE];
    gpu_vram_snapshot(snap_buf, GPU_VRAM_SIZE);
    TEST_ASSERT(snap_buf[20 * GPU_VRAM_WIDTH + 10] == 0x1234, "Snapshot copies VRAM content accurately");
}

static void test_vram_to_vram_copy(void)
{
    gpu_init();

    /* Put pattern at (20, 20) */
    gpu_vram_poke(20, 20, 0x5555);
    gpu_vram_poke(21, 20, 0xAAAA);

    /* GP0 0x80: Copy VRAM from (20,20) to (100,100) size 16x16 */
    gpu_gp0_write(0x80000000u);
    gpu_gp0_write((20u << 16) | 20u);     /* Src (20, 20) */
    gpu_gp0_write((100u << 16) | 100u);   /* Dst (100, 100) */
    gpu_gp0_write((16u << 16) | 16u);     /* Size 16x16 */

    TEST_ASSERT(gpu_vram_peek(100, 100) == 0x5555, "VRAM copy transferred pixel 0");
    TEST_ASSERT(gpu_vram_peek(101, 100) == 0xAAAA, "VRAM copy transferred pixel 1");
}

int main(void)
{
    printf("=== Running xenolift hle_gpu Unit Tests ===\n");

    test_init_and_fill();
    test_cpu_to_vram_and_clut_rect();
    test_quad_stream_and_blending();
    test_gp1_and_snapshot();
    test_vram_to_vram_copy();

    printf("Results: %d passed, %d failed\n", g_tests_passed, g_tests_failed);

    return (g_tests_failed == 0) ? 0 : 1;
}
