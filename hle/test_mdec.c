/* xenolift HLE MDEC & Memory Card / SIO Unit Tests
 *
 * Standalone compilation:
 * cc -w test_mdec.c hle_mdec.c hle_memcard.c -o t_mdec && ./t_mdec
 */

#include "hle_mdec.h"
#include "hle_memcard.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>

static int g_test_pass_count = 0;
static int g_test_fail_count = 0;

#define TEST_ASSERT(cond, msg) \
    do { \
        if (cond) { \
            fprintf(stderr, "  [PASS] %s\n", msg); \
            g_test_pass_count++; \
        } else { \
            fprintf(stderr, "  [FAIL] %s (line %d)\n", msg, __LINE__); \
            g_test_fail_count++; \
        } \
    } while (0)

static void test_mdec_decoding(void) {
    fprintf(stderr, "\n--- Running MDEC Decoding Test ---\n");
    hle_mdec_reset();

    /* Allocate 2MB dummy RAM for DMA tests */
    uint8_t *dummy_ram = (uint8_t *)calloc(1, 0x200000);
    assert(dummy_ram != NULL);
    hle_mdec_set_ram(dummy_ram);

    /* 1. Set Quant Table (Cmd 2, color=0 -> 64 bytes luminance quant table) */
    uint32_t cmd2 = (2u << 29); /* Cmd 2, color=0 */
    hle_mdec_port_write(0x1F801820, cmd2);
    TEST_ASSERT(hle_mdec_is_busy(), "MDEC busy after Cmd 2 write");

    /* Feed 16 words (64 bytes) of quant table = all 16 */
    for (int i = 0; i < 16; i++) {
        uint32_t qword = 0x10101010u; /* 16, 16, 16, 16 */
        hle_mdec_port_write(0x1F801820, qword);
    }
    TEST_ASSERT(!hle_mdec_is_busy(), "MDEC not busy after Cmd 2 parameters complete");

    /* 2. Decode 1 Macroblock (15bpp mode, unsigned output)
     * Cmd 1: (1 << 29) | (3 << 27) | (1 << 25) | 12 halfwords
     */
    uint32_t cmd1 = (1u << 29) | (3u << 27) | (1u << 25) | 12u;
    hle_mdec_port_write(0x1F801820, cmd1);
    TEST_ASSERT(hle_mdec_is_busy(), "MDEC busy after Cmd 1 decode write");

    /* Synthetic RLE stream for 6 blocks (Cr, Cb, Y1, Y2, Y3, Y4):
     * Each block has:
     * - First halfword: q_scale = 1 (bits 15-10 = 1 -> 0x0400), DC = 32 (bits 9-0 = 32 -> 0x0020) -> 0x0420
     * - Second halfword: EOB 0xFE00
     * One 32-bit word per block = (0xFE00 << 16) | 0x0420 = 0xFE000420
     * 6 32-bit writes = 12 halfwords.
     */
    for (int b = 0; b < 6; b++) {
        hle_mdec_port_write(0x1F801820, 0xFE000420u);
    }

    TEST_ASSERT(!hle_mdec_is_busy(), "MDEC completed decode after 6 parameter words");

    /* Read status */
    uint32_t stat = hle_mdec_port_read(0x1F801824);
    bool fifo_empty = (stat & (1u << 31)) != 0;
    TEST_ASSERT(!fifo_empty, "MDEC Output FIFO has decoded pixel data");

    /* Read decoded 15bpp pixel words (128 words expected = 256 pixels) */
    uint32_t first_pixel_word = hle_mdec_port_read(0x1F801820);
    TEST_ASSERT(first_pixel_word != 0, "Decoded 15bpp pixel word is non-zero RGB value");

    /* Verify 15bpp color fields (R, G, B components extracted) */
    uint16_t p0 = (uint16_t)(first_pixel_word & 0xFFFF);
    uint16_t r5 = p0 & 0x1F;
    uint16_t g5 = (p0 >> 5) & 0x1F;
    uint16_t b5 = (p0 >> 10) & 0x1F;

    fprintf(stderr, "  [mdec test] Sample 15bpp pixel: 0x%04X (R5=%u G5=%u B5=%u)\n", p0, r5, g5, b5);
    TEST_ASSERT(r5 > 0 && g5 > 0 && b5 > 0, "Decoded pixel has valid non-zero RGB components");

    free(dummy_ram);
}

static void test_memcard_sio_protocol(void) {
    fprintf(stderr, "\n--- Running Memory Card & SIO Protocol Test ---\n");
    hle_memcard_reset();

    /* 1. SIO Status transitions test (TXE & RXNE bits) */
    uint32_t stat = hle_sio_reg_read32(0x1F801044);
    TEST_ASSERT((stat & 2u) == 0, "Initial SIO status RXNE bit is 0 (FIFO Empty)");
    TEST_ASSERT((stat & 1u) != 0, "Initial SIO status TXE bit is 1 (TX Ready)");

    /* Send 0x81 (Memory Card Select) */
    hle_sio_port_write(0x1F801040, 0x81);
    stat = hle_sio_reg_read32(0x1F801044);
    TEST_ASSERT((stat & 2u) != 0, "SIO status RXNE bit is 1 after TX write");

    uint8_t dummy_rx = hle_sio_port_read(0x1F801040);
    TEST_ASSERT(dummy_rx == 0xFF, "Memory Card select returned 0xFF dummy response");

    stat = hle_sio_reg_read32(0x1F801044);
    TEST_ASSERT((stat & 2u) == 0, "SIO status RXNE bit cleared after RX read");

    /* 2. Write Sector 5 via SIO 'W' Command Protocol */
    /* Step 1: Cmd 'W' (0x57) */
    hle_sio_port_write(0x1F801040, 0x57);
    uint8_t flag = hle_sio_port_read(0x1F801040);
    TEST_ASSERT(flag == 0x08, "Write command returned FLAG byte 0x08");

    /* Step 2: Receive ID1 (0x5A) */
    hle_sio_port_write(0x1F801040, 0x00);
    TEST_ASSERT(hle_sio_port_read(0x1F801040) == 0x5A, "Received ID1 0x5A");

    /* Step 3: Receive ID2 (0x5D) */
    hle_sio_port_write(0x1F801040, 0x00);
    TEST_ASSERT(hle_sio_port_read(0x1F801040) == 0x5D, "Received ID2 0x5D");

    /* Step 4: Send Sector MSB (0x00) & LSB (0x05) */
    hle_sio_port_write(0x1F801040, 0x00); hle_sio_port_read(0x1F801040);
    hle_sio_port_write(0x1F801040, 0x05); hle_sio_port_read(0x1F801040);

    /* Step 5: Send 128 payload bytes */
    uint8_t payload[128];
    for (int i = 0; i < 128; i++) {
        payload[i] = (uint8_t)(i + 0x10);
        hle_sio_port_write(0x1F801040, payload[i]);
        hle_sio_port_read(0x1F801040);
    }

    /* Step 6: Send checksum byte */
    uint8_t expected_chk = hle_memcard_calc_sector_checksum(5, payload);
    hle_sio_port_write(0x1F801040, expected_chk);

    /* Step 7: Receive ACK1 (0x5C) & ACK2 (0x5D) */
    TEST_ASSERT(hle_sio_port_read(0x1F801040) == 0x5C, "Write ACK1 is 0x5C");
    hle_sio_port_write(0x1F801040, 0x00);
    TEST_ASSERT(hle_sio_port_read(0x1F801040) == 0x5D, "Write ACK2 is 0x5D");

    /* Step 8: Receive End Byte 'G' (0x47) */
    hle_sio_port_write(0x1F801040, 0x00);
    uint8_t end_byte = hle_sio_port_read(0x1F801040);
    TEST_ASSERT(end_byte == 0x47, "Write End Byte is 'G' (0x47 Good Match)");

    /* 3. Read Sector 5 back via SIO 'R' Command Protocol */
    hle_sio_port_write(0x1F801040, 0x81); hle_sio_port_read(0x1F801040); /* Select */
    hle_sio_port_write(0x1F801040, 0x52); hle_sio_port_read(0x1F801040); /* Cmd 'R' */
    hle_sio_port_write(0x1F801040, 0x00); TEST_ASSERT(hle_sio_port_read(0x1F801040) == 0x5A, "Read ID1 0x5A");
    hle_sio_port_write(0x1F801040, 0x00); TEST_ASSERT(hle_sio_port_read(0x1F801040) == 0x5D, "Read ID2 0x5D");

    /* Send Sector MSB (0x00) & LSB (0x05) */
    hle_sio_port_write(0x1F801040, 0x00); hle_sio_port_read(0x1F801040);
    hle_sio_port_write(0x1F801040, 0x05); TEST_ASSERT(hle_sio_port_read(0x1F801040) == 0x5C, "Read ACK1 0x5C");

    hle_sio_port_write(0x1F801040, 0x00); TEST_ASSERT(hle_sio_port_read(0x1F801040) == 0x5D, "Read ACK2 0x5D");
    hle_sio_port_write(0x1F801040, 0x00); TEST_ASSERT(hle_sio_port_read(0x1F801040) == 0x00, "Read confirmed MSB 0x00");
    hle_sio_port_write(0x1F801040, 0x00); TEST_ASSERT(hle_sio_port_read(0x1F801040) == 0x05, "Read confirmed LSB 0x05");

    /* Read 128 data bytes */
    uint8_t read_buf[128];
    for (int i = 0; i < 128; i++) {
        hle_sio_port_write(0x1F801040, 0x00);
        read_buf[i] = hle_sio_port_read(0x1F801040);
    }
    TEST_ASSERT(memcmp(read_buf, payload, 128) == 0, "Read sector 5 payload matches written data");

    /* Read Checksum */
    hle_sio_port_write(0x1F801040, 0x00);
    uint8_t read_chk = hle_sio_port_read(0x1F801040);
    TEST_ASSERT(read_chk == expected_chk, "Read sector checksum matches expected checksum");

    /* Read End Byte */
    hle_sio_port_write(0x1F801040, 0x00);
    TEST_ASSERT(hle_sio_port_read(0x1F801040) == 0x47, "Read End Byte is 'G' (0x47)");
}

int main(void) {
    fprintf(stderr, "========================================\n");
    fprintf(stderr, " xenolift MDEC + Memcard / SIO Test Suite\n");
    fprintf(stderr, "========================================\n");

    test_mdec_decoding();
    test_memcard_sio_protocol();

    fprintf(stderr, "\n========================================\n");
    fprintf(stderr, " Test Summary: PASS = %d, FAIL = %d\n", g_test_pass_count, g_test_fail_count);
    fprintf(stderr, "========================================\n");

    if (g_test_fail_count > 0) {
        return 1;
    }
    return 0;
}
