/*
 * xenolift SPU Standalone Test Suite
 * Path: xenolift/hle/test_spu.c
 *
 * Compiles and runs standalone:
 *   cc -w test_spu.c hle_spu.c -o t_spu && ./t_spu
 */

#include "hle_spu.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int g_fails = 0;

#define TEST_ASSERT(cond, msg) \
    do { \
        if (!(cond)) { \
            fprintf(stderr, "  [FAIL] %s (line %d): %s\n", __func__, __LINE__, msg); \
            g_fails++; \
        } else { \
            fprintf(stderr, "  [PASS] %s: %s\n", __func__, msg); \
        } \
    } while(0)

/* Test 1: Hand-crafted ADPCM Block Decoding */
static void test_adpcm_decoding(void)
{
    fprintf(stderr, "=== Test 1: ADPCM Decoding (Filter 0 and Filter 4) ===\n");

    /*
     * Hand-crafted Block 1 (Filter 0, Shift 9):
     * Byte 0: 0x09 (Filter = 0, Shift = 9).
     * Byte 1: 0x00 (Flags = 0).
     * Byte 2: 0xF2 -> Nibble 0 = 0x2 (+2), Nibble 1 = 0xF (-1).
     * Byte 3: 0x38 -> Nibble 2 = 0x8 (-8), Nibble 3 = 0x3 (+3).
     * Bytes 4..15: 0x00.
     *
     * Derivation:
     * Shift = 9 => raw = s4 << (12 - 9) = s4 << 3. Filter 0 => predict = 0.
     * Sample 0 (Nibble 0x2 = +2): raw = 2 << 3 = 16. Predict = 0. Sample 0 = 16.
     * Sample 1 (Nibble 0xF = -1): raw = -1 << 3 = -8. Predict = 0. Sample 1 = -8.
     * Sample 2 (Nibble 0x8 = -8): raw = -8 << 3 = -64. Predict = 0. Sample 2 = -64.
     * Sample 3 (Nibble 0x3 = +3): raw = 3 << 3 = 24. Predict = 0. Sample 3 = 24.
     * Samples 4..27: 0 nibbles -> Sample = 0.
     * After all 28 samples, history s1 = 0, s2 = 0.
     */
    uint8_t block0[16] = {
        0x09, 0x00, 0xF2, 0x38, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    };

    int16_t pcm_out[28];
    int16_t s1 = 0, s2 = 0;
    uint8_t flags = 0xFF;

    hle_spu_decode_adpcm_block(block0, pcm_out, &s1, &s2, &flags);

    TEST_ASSERT(flags == 0x00, "Header flags extracted correctly (0x00)");
    TEST_ASSERT(pcm_out[0] == 16, "Filter 0 Sample 0 exact match (+16)");
    TEST_ASSERT(pcm_out[1] == -8, "Filter 0 Sample 1 exact match (-8)");
    TEST_ASSERT(pcm_out[2] == -64, "Filter 0 Sample 2 exact match (-64)");
    TEST_ASSERT(pcm_out[3] == 24, "Filter 0 Sample 3 exact match (+24)");
    TEST_ASSERT(s1 == 0 && s2 == 0, "Filter 0 final history after 28 samples exact match (0, 0)");

    /*
     * Hand-crafted Block 2 (Filter 4, Shift 8):
     * Filter 4: K0 = 122, K1 = -60. Predict = (s1 * 122 + s2 * (-60) + 32) >> 6.
     * Initial history: s1 = 200, s2 = 100.
     * Byte 0: 0x48 (Filter = 4, Shift = 8). raw = s4 << (12 - 8) = s4 << 4.
     * Byte 1: 0x00.
     * Byte 2: 0x13 -> Nibble 0 = 0x3 (+3), Nibble 1 = 0x1 (+1).
     *
     * Derivation:
     * Sample 0 (Nibble 0x3 = +3):
     *   raw = 3 << 4 = 48.
     *   predict = (200 * 122 + 100 * (-60) + 32) >> 6 = (24400 - 6000 + 32) >> 6 = 18432 >> 6 = 288.
     *   sample 0 = 48 + 288 = 336.
     * Sample 1 (Nibble 0x1 = +1):
     *   raw = 1 << 4 = 16.
     *   predict = (336 * 122 + 200 * (-60) + 32) >> 6 = (40992 - 12000 + 32) >> 6 = 29024 >> 6 = 453.
     *   sample 1 = 16 + 453 = 469.
     */
    uint8_t block4[16] = {
        0x48, 0x00, 0x13, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    };

    s1 = 200; s2 = 100;
    hle_spu_decode_adpcm_block(block4, pcm_out, &s1, &s2, &flags);

    TEST_ASSERT(pcm_out[0] == 336, "Filter 4 Sample 0 exact match (+336)");
    TEST_ASSERT(pcm_out[1] == 469, "Filter 4 Sample 1 exact match (+469)");
    TEST_ASSERT(s1 != 0 || s2 != 0, "Filter 4 filter history updated after 28 samples");
}

/* Test 2: Loop Flags Handling */
static void test_loop_flags(void)
{
    fprintf(stderr, "\n=== Test 2: Loop Flags (Loop Start / Loop End & Repeat) ===\n");

    hle_spu_reset();

    /* Place Block 1 at SPU RAM 0x1000 (Loop Start flag 0x04) */
    uint8_t blk_start[16] = { 0x09, 0x04, 0x22, 0x22, 0x00, 0x00, 0x00, 0x00,
                              0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
    /* Place Block 2 at SPU RAM 0x1010 (Loop End & Repeat flags 0x03) */
    uint8_t blk_end[16]   = { 0x09, 0x03, 0x33, 0x33, 0x00, 0x00, 0x00, 0x00,
                              0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };

    hle_spu_dma_write(0x1000, blk_start, 16);
    hle_spu_dma_write(0x1010, blk_end, 16);

    /* Setup voice 0 to start at 0x1000 */
    hle_spu_port_write(0x1F801C06, 0x1000 / 8); /* start_addr */
    hle_spu_port_write(0x1F801C04, 0x1000);     /* pitch 44100 Hz */
    hle_spu_port_write(0x1F801C00, 0x7FFF);     /* vol_l */
    hle_spu_port_write(0x1F801C02, 0x7FFF);     /* vol_r */

    /* Key On voice 0 */
    hle_spu_port_write(0x1F801D88, 0x0001);

    TEST_ASSERT(g_spu.voices[0].current_addr == 0x1000, "Voice 0 key-on sets current_addr to 0x1000");

    /* Generate 28 samples -> voice finishes block 1 (start block) */
    int16_t out_pcm[28 * 2];
    hle_spu_generate(28, out_pcm);

    TEST_ASSERT(g_spu.voices[0].repeat_addr == 0x1000, "Loop Start flag updated repeat_addr to 0x1000");

    /* Generate 28 more samples -> voice finishes block 2 (end block) and loops */
    hle_spu_generate(28, out_pcm);

    TEST_ASSERT(g_spu.voices[0].loop_end_hit == 1, "Loop End flag set loop_end_hit");
    TEST_ASSERT((g_spu.endx_flags & 0x01) != 0, "ENDX register bit 0 set on loop end");
    TEST_ASSERT(g_spu.voices[0].current_addr == 0x1000, "Voice current_addr looped back to 0x1000");
}

/* Test 3: Voice Envelope & ADSR Rate */
static void test_adsr_envelope(void)
{
    fprintf(stderr, "\n=== Test 3: Voice ADSR Envelope State Machine ===\n");

    hle_spu_reset();

    /* Setup voice 0 with Attack Shift = 11 (cycles = 1), Attack Step = 0 (+7 per tick)
     * ADSR low: bit 15 = 0 (Linear), bits 14-10 = 11 (0x0B), bits 9-8 = 0 (+7 step)
     * adsr_low = (11 << 10) = 0x2C00
     */
    hle_spu_port_write(0x1F801C08, 0x2C00); /* adsr_low */
    hle_spu_port_write(0x1F801C0A, 0x0000); /* adsr_high */
    hle_spu_port_write(0x1F801C04, 0x1000); /* pitch = 44100 Hz */

    /* Key On voice 0 */
    hle_spu_port_write(0x1F801D88, 0x0001);

    TEST_ASSERT(g_spu.voices[0].adsr_phase == SPU_ADSR_ATTACK, "Voice 0 enters ATTACK phase on Key On");
    TEST_ASSERT(g_spu.voices[0].adsr_level == 0, "Initial ADSR level is 0");

    /* Run 100 sample ticks */
    int16_t dummy_pcm[100 * 2];
    hle_spu_generate(100, dummy_pcm);

    /* 100 ticks * +7 step = 700 expected level */
    TEST_ASSERT(g_spu.voices[0].adsr_level == 700, "ADSR level rises linearly (+7 per tick * 100 ticks = 700)");

    /* Run enough frames to reach max attack (0x7FFF = 32767) */
    hle_spu_generate(5000, NULL);

    TEST_ASSERT(g_spu.voices[0].adsr_level > 700, "ADSR level continued rising into Decay/Sustain");
}

/* Test 4: WAV Dump Helper & File Integrity */
static void test_wav_dump(void)
{
    fprintf(stderr, "\n=== Test 4: WAV Dump Helper (1 second stereo PCM 44100Hz) ===\n");

    hle_spu_reset();

    /* Put looping audio sample in SPU RAM at 0x1000 */
    /* Header: shift=0, filter=0, flags=0x07 (Loop Start | Loop Repeat | Loop End) */
    uint8_t blk_sound[16] = { 0x00, 0x07, 0x77, 0x77, 0x77, 0x77, 0x77, 0x77,
                              0x77, 0x77, 0x77, 0x77, 0x77, 0x77, 0x77, 0x77 };
    hle_spu_dma_write(0x1000, blk_sound, 16);

    hle_spu_port_write(0x1F801C06, 0x1000 / 8); /* start_addr */
    hle_spu_port_write(0x1F801C04, 0x1000);     /* pitch */
    hle_spu_port_write(0x1F801C00, 0x7FFF);     /* vol_l */
    hle_spu_port_write(0x1F801C02, 0x7FFF);     /* vol_r */

    /* Attack shift = 0 (fastest) */
    hle_spu_port_write(0x1F801C08, 0x0000);
    hle_spu_port_write(0x1F801D88, 0x0001); /* Key On */

    /* Pre-set ADSR level to full for immediate loud output */
    g_spu.voices[0].adsr_level = 0x7FFF;

    const char *wav_path = "t_spu_test.wav";
    int ret = hle_spu_wav_dump(wav_path);

    TEST_ASSERT(ret == 0, "hle_spu_wav_dump returned success (0)");

    FILE *f = fopen(wav_path, "rb");
    TEST_ASSERT(f != NULL, "WAV file successfully created");

    if (f) {
        fseek(f, 0, SEEK_END);
        long sz = ftell(f);
        fclose(f);

        /* 44 byte header + 44100 frames * 2 channels * 2 bytes = 176444 bytes */
        TEST_ASSERT(sz == 176444, "WAV file size is exactly 176,444 bytes (44B header + 1 sec PCM)");

        /* Re-open and check RIFF header & non-zero sample data */
        f = fopen(wav_path, "rb");
        uint8_t hdr[44];
        fread(hdr, 1, 44, f);
        TEST_ASSERT(memcmp(&hdr[0], "RIFF", 4) == 0, "WAV header RIFF magic valid");
        TEST_ASSERT(memcmp(&hdr[8], "WAVEfmt ", 8) == 0, "WAV header WAVEfmt magic valid");

        int16_t sample_buf[100];
        fread(sample_buf, sizeof(int16_t), 100, f);
        fclose(f);

        int has_nonzero = 0;
        for (int i = 0; i < 100; i++) {
            if (sample_buf[i] != 0) {
                has_nonzero = 1;
                break;
            }
        }
        TEST_ASSERT(has_nonzero == 1, "WAV payload contains non-zero generated audio samples");
    }
}

/* Test 5: Key Off Release Decay */
static void test_key_off_release(void)
{
    fprintf(stderr, "\n=== Test 5: Key Off & Release Envelope Decay ===\n");

    hle_spu_reset();

    /* Fast attack so envelope reaches max quickly */
    hle_spu_port_write(0x1F801C08, 0x0000); /* adsr_low */
    hle_spu_port_write(0x1F801C0A, 0x0000); /* adsr_high: fast release */
    hle_spu_port_write(0x1F801C04, 0x1000);

    /* Key On voice 0 */
    hle_spu_port_write(0x1F801D88, 0x0001);

    int16_t pcm[100 * 2];
    hle_spu_generate(100, pcm);

    TEST_ASSERT(g_spu.voices[0].is_on == 1, "Voice 0 is active before Key Off");
    int16_t level_before = g_spu.voices[0].adsr_level;
    TEST_ASSERT(level_before > 0, "ADSR level is non-zero before Key Off");

    /* Key Off voice 0 */
    hle_spu_port_write(0x1F801D8C, 0x0001);

    TEST_ASSERT(g_spu.voices[0].adsr_phase == SPU_ADSR_RELEASE, "Voice 0 transitions to RELEASE phase");

    /* Run 500 frames for release to decay to 0 */
    hle_spu_generate(100, pcm); /* R-fix: buffer is 100 frames — was 500 = stack overflow */

    TEST_ASSERT(g_spu.voices[0].adsr_level == 0, "ADSR level decayed to 0 after Key Off");
    TEST_ASSERT(g_spu.voices[0].is_on == 0, "Voice 0 turned off (is_on = 0)");
}

/* Test 6: Volume Register Scaling */
static void test_volume_scaling(void)
{
    fprintf(stderr, "\n=== Test 6: Volume Register Scaling ===\n");

    hle_spu_reset();

    /* Put looping audio sample in SPU RAM at 0x1000 */
    uint8_t blk_sound[16] = { 0x00, 0x07, 0x77, 0x77, 0x77, 0x77, 0x77, 0x77,
                              0x77, 0x77, 0x77, 0x77, 0x77, 0x77, 0x77, 0x77 };
    hle_spu_dma_write(0x1000, blk_sound, 16);

    hle_spu_port_write(0x1F801C06, 0x1000 / 8);
    hle_spu_port_write(0x1F801C04, 0x1000);
    hle_spu_port_write(0x1F801C08, 0x0000); /* Fast attack */

    /* Set voice volume to full 0x7FFF */
    hle_spu_port_write(0x1F801C00, 0x7FFF); /* Vol L */
    hle_spu_port_write(0x1F801C02, 0x7FFF); /* Vol R */
    hle_spu_port_write(0x1F801D88, 0x0001); /* Key On */
    g_spu.voices[0].adsr_level = 0x7FFF;

    int16_t out_full[100 * 2];
    hle_spu_generate(100, out_full);

    int16_t sample_full = out_full[10 * 2]; /* Sample at frame 10 */

    /* Reset and test half volume (0x3FFF) */
    hle_spu_reset();
    hle_spu_dma_write(0x1000, blk_sound, 16);
    hle_spu_port_write(0x1F801C06, 0x1000 / 8);
    hle_spu_port_write(0x1F801C04, 0x1000);
    hle_spu_port_write(0x1F801C08, 0x0000);

    hle_spu_port_write(0x1F801C00, 0x3FFF); /* Half Vol L */
    hle_spu_port_write(0x1F801C02, 0x3FFF); /* Half Vol R */
    hle_spu_port_write(0x1F801D88, 0x0001);
    g_spu.voices[0].adsr_level = 0x7FFF;

    int16_t out_half[100 * 2];
    hle_spu_generate(100, out_half);

    int16_t sample_half = out_half[10 * 2];

    TEST_ASSERT(sample_full != 0, "Full volume output is non-zero");
    TEST_ASSERT(abs(sample_half - (sample_full / 2)) <= 2, "Half volume output is approximately half of full volume");
}

int main(void)
{
    fprintf(stderr, "====================================================\n");
    fprintf(stderr, " xenolift SPU Unit Test Suite (hle_spu.c / hle_spu.h)\n");
    fprintf(stderr, "====================================================\n\n");

    test_adpcm_decoding();
    test_loop_flags();
    test_adsr_envelope();
    test_wav_dump();
    test_key_off_release();
    test_volume_scaling();

    fprintf(stderr, "\n====================================================\n");
    if (g_fails == 0) {
        fprintf(stderr, " RESULT: ALL SPU TESTS PASSED!\n");
        fprintf(stderr, "====================================================\n");
        return 0;
    } else {
        fprintf(stderr, " RESULT: %d TEST(S) FAILED!\n", g_fails);
        fprintf(stderr, "====================================================\n");
        return 1;
    }
}
