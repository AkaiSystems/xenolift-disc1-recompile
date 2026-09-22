/*
 * xenolift SPU (Sound Processing Unit) HLE Module Implementation
 * Path: xenolift/hle/hle_spu.c
 *
 * Spec reference: psx-spx (Martin Korth, PlayStation Sound Processing Unit)
 * - Pure C17, deterministic, standard library only.
 * - SPU RAM model (512KB), 16-byte ADPCM decoder, 24 voice channels,
 *   ADSR envelope generator, stereo mixer, register port interface, WAV dumper.
 */

#include "hle_spu.h"
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


/* Global SPU state instance */
hle_spu_state_t g_spu;

/* ADPCM Filter Coefficients Table (5-tap per psx-spx) */
static const int K0[5] = { 0, 60, 115,  98, 122 };
static const int K1[5] = { 0,  0, -52, -55, -60 };

/* ADSR Attack Step Table (+7, +6, +5, +4) */
static const int ADSR_ATTACK_STEP[4] = { 7, 6, 5, 4 };

/* Standalone ADPCM Block Decoder */
void hle_spu_decode_adpcm_block(const uint8_t block[16], int16_t pcm_out[28],
                                int16_t *old_s1, int16_t *old_s2,
                                uint8_t *out_flags)
{
    uint8_t header = block[0];
    uint8_t flags  = block[1];

    if (out_flags) {
        *out_flags = flags;
    }

    int shift = header & 0x0F;
    int filter = (header >> 4) & 0x07;

    /* Per psx-spx: reserve shift values 13..15 act same as shift=9 */
    if (shift > 12) {
        shift = 9;
    }
    if (filter > 4) {
        filter = 4;
    }

    int k0_coeff = K0[filter];
    int k1_coeff = K1[filter];

    int16_t s1 = old_s1 ? *old_s1 : 0;
    int16_t s2 = old_s2 ? *old_s2 : 0;

    int pcm_idx = 0;
    for (int i = 0; i < 14; i++) {
        uint8_t byte = block[2 + i];

        /* Low nibble = 1st sample, High nibble = 2nd sample */
        int nibbles[2];
        nibbles[0] = byte & 0x0F;
        nibbles[1] = (byte >> 4) & 0x0F;

        for (int n = 0; n < 2; n++) {
            int nib = nibbles[n];
            /* Sign extend 4-bit to signed 32-bit */
            int32_t s4 = (nib & 8) ? (nib - 16) : nib;

            int32_t raw = s4 << (12 - shift);
            int32_t predict = ((int32_t)s1 * k0_coeff + (int32_t)s2 * k1_coeff + 32) >> 6;
            int32_t sample = raw + predict;

            /* Clamp to signed 16-bit PCM [-32768, 32767] */
            if (sample > 32767) {
                sample = 32767;
            } else if (sample < -32768) {
                sample = -32768;
            }

            s2 = s1;
            s1 = (int16_t)sample;

            pcm_out[pcm_idx++] = (int16_t)sample;
        }
    }

    if (old_s1) *old_s1 = s1;
    if (old_s2) *old_s2 = s2;
}

/* ADSR Envelope Generator Tick (executed once per 44.1kHz sample per voice) */
static void spu_voice_adsr_tick(hle_spu_voice_t *v)
{
    if (v->adsr_phase == SPU_ADSR_OFF) {
        v->adsr_level = 0;
        return;
    }

    switch (v->adsr_phase) {
    case SPU_ADSR_ATTACK: {
        int a_mode = (v->adsr_low >> 15) & 1; /* 0 = Linear, 1 = Exponential */
        int a_shift = (v->adsr_low >> 10) & 0x1F;
        int a_step_idx = (v->adsr_low >> 8) & 0x03;
        int step_val = ADSR_ATTACK_STEP[a_step_idx];

        uint32_t cycles = 1u << ((a_shift > 11) ? (a_shift - 11) : 0);
        if (a_mode == 1 && v->adsr_level > 0x6000) {
            cycles *= 4;
        }

        v->adsr_cycle_counter++;
        if (v->adsr_cycle_counter >= cycles) {
            v->adsr_cycle_counter = 0;
            int32_t step = step_val << ((a_shift < 11) ? (11 - a_shift) : 0);
            int32_t next = (int32_t)v->adsr_level + step;
            if (next >= 0x7FFF) {
                v->adsr_level = 0x7FFF;
                v->adsr_phase = SPU_ADSR_DECAY;
            } else {
                v->adsr_level = (int16_t)next;
            }
        }
        break;
    }

    case SPU_ADSR_DECAY: {
        int d_shift = (v->adsr_low >> 4) & 0x0F;
        int target = ((v->adsr_low & 0x0F) + 1) * 0x0800;
        if (target > 0x7FFF) target = 0x7FFF;

        uint32_t cycles = 1u << ((d_shift > 11) ? (d_shift - 11) : 0);

        v->adsr_cycle_counter++;
        if (v->adsr_cycle_counter >= cycles) {
            v->adsr_cycle_counter = 0;
            int32_t step = -8 << ((d_shift < 11) ? (11 - d_shift) : 0);
            step = (step * (int32_t)v->adsr_level) >> 15;
            if (step >= 0) step = -1;

            int32_t next = (int32_t)v->adsr_level + step;
            if (next <= target) {
                v->adsr_level = (int16_t)target;
                v->adsr_phase = SPU_ADSR_SUSTAIN;
            } else {
                v->adsr_level = (int16_t)next;
            }
        }
        break;
    }

    case SPU_ADSR_SUSTAIN: {
        int s_mode = (v->adsr_high >> 15) & 1;
        int s_dir  = (v->adsr_high >> 14) & 1; /* 0 = Increase, 1 = Decrease */
        int s_shift = (v->adsr_high >> 8) & 0x1F;
        int s_step_idx = (v->adsr_high >> 6) & 0x03;

        int step_val = (s_dir == 0) ? (7 - s_step_idx) : (-8 + s_step_idx);
        int target = (s_dir == 0) ? 0x7FFF : 0;

        uint32_t cycles = 1u << ((s_shift > 11) ? (s_shift - 11) : 0);
        if (s_mode == 1 && s_dir == 0 && v->adsr_level > 0x6000) {
            cycles *= 4;
        }

        v->adsr_cycle_counter++;
        if (v->adsr_cycle_counter >= cycles) {
            v->adsr_cycle_counter = 0;
            int32_t step = step_val << ((s_shift < 11) ? (11 - s_shift) : 0);
            if (s_mode == 1 && s_dir == 1) {
                step = (step * (int32_t)v->adsr_level) >> 15;
                if (step >= 0) step = -1;
            }

            int32_t next = (int32_t)v->adsr_level + step;
            if (s_dir == 0) { /* Increase */
                if (next >= target) {
                    v->adsr_level = (int16_t)target;
                } else {
                    v->adsr_level = (int16_t)next;
                }
            } else { /* Decrease */
                if (next <= target) {
                    v->adsr_level = 0;
                } else {
                    v->adsr_level = (int16_t)next;
                }
            }
        }
        break;
    }

    case SPU_ADSR_RELEASE: {
        int r_mode = (v->adsr_high >> 5) & 1;
        int r_shift = v->adsr_high & 0x1F;

        uint32_t cycles = 1u << ((r_shift > 11) ? (r_shift - 11) : 0);

        v->adsr_cycle_counter++;
        if (v->adsr_cycle_counter >= cycles) {
            v->adsr_cycle_counter = 0;
            int32_t step = -8 << ((r_shift < 11) ? (11 - r_shift) : 0);
            if (r_mode == 1) { /* Exponential Release */
                step = (step * (int32_t)v->adsr_level) >> 15;
                if (step >= 0) step = -1;
            }

            int32_t next = (int32_t)v->adsr_level + step;
            if (next <= 0) {
                v->adsr_level = 0;
                v->adsr_phase = SPU_ADSR_OFF;
                v->is_on = 0;
            } else {
                v->adsr_level = (int16_t)next;
            }
        }
        break;
    }

    default:
        break;
    }
}

/* Key On voice helper */
static void spu_voice_key_on(int idx)
{
    if (idx < 0 || idx >= SPU_VOICE_COUNT) return;
    hle_spu_voice_t *v = &g_spu.voices[idx];

    v->current_addr = v->start_addr % SPU_RAM_SIZE;
    v->old_s1 = 0;
    v->old_s2 = 0;
    v->pitch_counter = 0;
    v->sample_idx = 28; /* Triggers new block decode on first sample step */
    v->adsr_phase = SPU_ADSR_ATTACK;
    v->adsr_level = 0;
    v->adsr_cycle_counter = 0;
    v->is_on = 1;
    v->loop_end_hit = 0;

    g_spu.endx_flags &= ~(1u << idx);
}

/* Key Off voice helper */
static void spu_voice_key_off(int idx)
{
    if (idx < 0 || idx >= SPU_VOICE_COUNT) return;
    hle_spu_voice_t *v = &g_spu.voices[idx];

    if (v->is_on) {
        v->adsr_phase = SPU_ADSR_RELEASE;
        v->adsr_cycle_counter = 0;
    }
}

/* SPU Reset API */
void hle_spu_reset(void)
{
    memset(&g_spu, 0, sizeof(g_spu));

    for (int i = 0; i < SPU_VOICE_COUNT; i++) {
        g_spu.voices[i].id = i;
        g_spu.voices[i].pitch = 0x1000; /* 44100 Hz default */
        g_spu.voices[i].start_addr = 0x0000;
        g_spu.voices[i].repeat_addr = 0x0000;
        g_spu.voices[i].current_addr = 0x0000;
    }

    g_spu.mvol_l = 0x7FFF;
    g_spu.mvol_r = 0x7FFF;
    g_spu.spucnt = 0x8000; /* Unmuted / Reset released */
    g_spu.spudac = 0x0004;

    /* Write default silent ADPCM loop block at 0x0000 and 0x0400 */
    /* Header: shift=0, filter=0, flags=0x07 (Loop Start 4 | Loop Repeat 2 | Loop End 1) */
    uint8_t dummy_block[16] = { 0x00, 0x07, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
    memcpy(&g_spu.ram[0x0000], dummy_block, 16);
    memcpy(&g_spu.ram[0x0400], dummy_block, 16);

    hle_out("[spudev] SPU reset complete: 512KB SPU RAM initialized, 24 voices ready.\n");
}

/* Write to SPU MMIO port window */
void hle_spu_port_write(uint32_t addr, uint16_t v)
{
    uint32_t p = addr & 0x1FFFFFFF;
    if (p >= 0x1F801C00 && p <= 0x1F801E00) {
        p &= 0x3FF; /* Normalize relative offset in 0x1C00..0x1E00 window */
    }

    /* Voice Registers Window: 0x000 - 0x017F (Voice 0..23) */
    if (p < 0x0180) {
        int v_idx = p / 0x10;
        int reg   = p % 0x10;
        if (v_idx >= 0 && v_idx < SPU_VOICE_COUNT) {
            hle_spu_voice_t *voice = &g_spu.voices[v_idx];
            switch (reg) {
            case 0x00: voice->vol_l = v; break;
            case 0x02: voice->vol_r = v; break;
            case 0x04: voice->pitch = v; break;
            case 0x06: voice->start_addr = (uint32_t)v * 8; break; /* Word to byte addr */
            case 0x08: voice->adsr_low = v; break;
            case 0x0A: voice->adsr_high = v; break;
            case 0x0C: voice->adsr_level = (int16_t)v; break;
            case 0x0E: voice->repeat_addr = (uint32_t)v * 8; break;
            default: break;
            }
        }
        return;
    }

    /* Global Registers Window: 0x0180 - 0x01BF */
    switch (p) {
    case 0x0180: g_spu.mvol_l = v; break;
    case 0x0182: g_spu.mvol_r = v; break;
    case 0x0184: g_spu.svol_l = v; break;
    case 0x0186: g_spu.svol_r = v; break;

    case 0x0188: /* Key On Low (0..15) */
        g_spu.key_on_flags = (g_spu.key_on_flags & 0xFFFF0000u) | v;
        for (int i = 0; i < 16; i++) {
            if (v & (1u << i)) spu_voice_key_on(i);
        }
        break;
    case 0x018A: /* Key On High (16..23) */
        g_spu.key_on_flags = (g_spu.key_on_flags & 0x0000FFFFu) | ((uint32_t)v << 16);
        for (int i = 0; i < 8; i++) {
            if (v & (1u << i)) spu_voice_key_on(16 + i);
        }
        break;

    case 0x018C: /* Key Off Low (0..15) */
        g_spu.key_off_flags = (g_spu.key_off_flags & 0xFFFF0000u) | v;
        for (int i = 0; i < 16; i++) {
            if (v & (1u << i)) spu_voice_key_off(i);
        }
        break;
    case 0x018E: /* Key Off High (16..23) */
        g_spu.key_off_flags = (g_spu.key_off_flags & 0x0000FFFFu) | ((uint32_t)v << 16);
        for (int i = 0; i < 8; i++) {
            if (v & (1u << i)) spu_voice_key_off(16 + i);
        }
        break;

    case 0x0190: g_spu.pmon_flags = (g_spu.pmon_flags & 0xFFFF0000u) | v; break;
    case 0x0192: g_spu.pmon_flags = (g_spu.pmon_flags & 0x0000FFFFu) | ((uint32_t)v << 16); break;

    case 0x0194: g_spu.non_flags = (g_spu.non_flags & 0xFFFF0000u) | v; break;
    case 0x0196: g_spu.non_flags = (g_spu.non_flags & 0x0000FFFFu) | ((uint32_t)v << 16); break;

    case 0x0198: g_spu.eon_flags = (g_spu.eon_flags & 0xFFFF0000u) | v; break;
    case 0x019A: g_spu.eon_flags = (g_spu.eon_flags & 0x0000FFFFu) | ((uint32_t)v << 16); break;

    case 0x019C: g_spu.endx_flags &= ~((uint32_t)v); break; /* Write clears flags */
    case 0x019E: g_spu.endx_flags &= ~((uint32_t)v << 16); break;

    case 0x01A4: g_spu.irq_addr = (uint32_t)v * 8; break;
    case 0x01A6: g_spu.transfer_addr = (uint32_t)v * 8; break;

    case 0x01A8: /* SPUDATA (Fifo manual write) */
        g_spu.ram[g_spu.transfer_addr % SPU_RAM_SIZE] = v & 0xFF;
        g_spu.ram[(g_spu.transfer_addr + 1) % SPU_RAM_SIZE] = (v >> 8) & 0xFF;
        g_spu.transfer_addr = (g_spu.transfer_addr + 2) % SPU_RAM_SIZE;
        break;

    case 0x01AA:
        g_spu.spucnt = v;
        g_spu.spustat = (g_spu.spustat & ~0x003F) | (v & 0x003F);
        break;

    case 0x01AC: g_spu.spudac = v; break;

    case 0x01B0: g_spu.cd_vol_l = v; break;
    case 0x01B2: g_spu.cd_vol_r = v; break;
    case 0x01B4: g_spu.ext_vol_l = v; break;
    case 0x01B6: g_spu.ext_vol_r = v; break;

    default:
        break;
    }
}

/* Read from SPU MMIO port window */
uint16_t hle_spu_port_read(uint32_t addr)
{
    uint32_t p = addr & 0x1FFFFFFF;
    if (p >= 0x1F801C00 && p <= 0x1F801E00) {
        p &= 0x3FF;
    }

    if (p < 0x0180) {
        int v_idx = p / 0x10;
        int reg   = p % 0x10;
        if (v_idx >= 0 && v_idx < SPU_VOICE_COUNT) {
            hle_spu_voice_t *voice = &g_spu.voices[v_idx];
            switch (reg) {
            case 0x00: return voice->vol_l;
            case 0x02: return voice->vol_r;
            case 0x04: return voice->pitch;
            case 0x06: return (uint16_t)(voice->start_addr / 8);
            case 0x08: return voice->adsr_low;
            case 0x0A: return voice->adsr_high;
            case 0x0C: return (uint16_t)voice->adsr_level;
            case 0x0E: return (uint16_t)(voice->repeat_addr / 8);
            default: return 0;
            }
        }
        return 0;
    }

    switch (p) {
    case 0x0180: return g_spu.mvol_l;
    case 0x0182: return g_spu.mvol_r;
    case 0x0184: return g_spu.svol_l;
    case 0x0186: return g_spu.svol_r;
    case 0x019C: return (uint16_t)(g_spu.endx_flags & 0xFFFFu);
    case 0x019E: return (uint16_t)((g_spu.endx_flags >> 16) & 0xFFu);
    case 0x01A4: return (uint16_t)(g_spu.irq_addr / 8);
    case 0x01A6: return (uint16_t)(g_spu.transfer_addr / 8);
    case 0x01AA: return g_spu.spucnt;
    case 0x01AC: return g_spu.spudac;
    case 0x01AE: return g_spu.spustat;
    case 0x01B0: return g_spu.cd_vol_l;
    case 0x01B2: return g_spu.cd_vol_r;
    case 0x01B4: return g_spu.ext_vol_l;
    case 0x01B6: return g_spu.ext_vol_r;
    default:
        break;
    }

    /* Internal voice current volume readback window 0x0200 - 0x025F */
    if (p >= 0x0200 && p < 0x0260) {
        int v_idx = (p - 0x0200) / 4;
        int channel = (p - 0x0200) % 4;
        if (v_idx >= 0 && v_idx < SPU_VOICE_COUNT) {
            hle_spu_voice_t *voice = &g_spu.voices[v_idx];
            int32_t env = voice->adsr_level;
            if (channel == 0) {
                return (uint16_t)((env * (int16_t)voice->vol_l) >> 15);
            } else if (channel == 2) {
                return (uint16_t)((env * (int16_t)voice->vol_r) >> 15);
            }
        }
    }

    return 0;
}

/* SPU DMA Transfer Write Function */
void hle_spu_dma_write(uint32_t spu_addr, const uint8_t *data, uint32_t len)
{
    if (!data || len == 0) return;

    for (uint32_t i = 0; i < len; i++) {
        uint32_t dst = (spu_addr + i) % SPU_RAM_SIZE;
        g_spu.ram[dst] = data[i];
    }

    g_spu.transfer_addr = (spu_addr + len) % SPU_RAM_SIZE;
}

/* Core Audio Generation and Stereo Mixing Engine */
void hle_spu_generate(uint32_t nframes, int16_t *out)
{
    for (uint32_t f = 0; f < nframes; f++) {
        int32_t mix_l = 0;
        int32_t mix_r = 0;

        for (int i = 0; i < SPU_VOICE_COUNT; i++) {
            hle_spu_voice_t *v = &g_spu.voices[i];

            if (!v->is_on || v->adsr_phase == SPU_ADSR_OFF) {
                continue;
            }

            /* Step ADSR envelope once per sample frame */
            spu_voice_adsr_tick(v);

            if (v->adsr_level == 0 && v->adsr_phase == SPU_ADSR_RELEASE) {
                v->is_on = 0;
                v->adsr_phase = SPU_ADSR_OFF;
                continue;
            }

            /* Pitch accumulator step (0x1000 = 1.0 sample step) */
            uint32_t step = (v->pitch == 0) ? 0x1000 : v->pitch;
            v->pitch_counter += step;

            while (v->pitch_counter >= 0x1000) {
                v->pitch_counter -= 0x1000;
                v->sample_idx++;

                if (v->sample_idx >= 28) {
                    /* Read header flags of completed ADPCM block */
                    uint32_t curr = v->current_addr % SPU_RAM_SIZE;
                    uint8_t flags = g_spu.ram[(curr + 1) % SPU_RAM_SIZE];

                    /* Loop Start flag (bit 2) */
                    if (flags & 0x04) {
                        v->repeat_addr = curr;
                    }

                    /* Loop End flag (bit 0) */
                    if (flags & 0x01) {
                        v->loop_end_hit = 1;
                        g_spu.endx_flags |= (1u << i);
                        v->current_addr = v->repeat_addr % SPU_RAM_SIZE;

                        /* Bit 1 = Loop Repeat. If clear: End + Mute */
                        if (!(flags & 0x02)) {
                            v->adsr_phase = SPU_ADSR_RELEASE;
                            v->adsr_level = 0;
                        }
                    } else {
                        v->current_addr = (curr + 16) % SPU_RAM_SIZE;
                    }

                    /* Copy 16 bytes safely handling 512KB wrap-around */
                    uint8_t block_buf[16];
                    for (int k = 0; k < 16; k++) {
                        block_buf[k] = g_spu.ram[(v->current_addr + k) % SPU_RAM_SIZE];
                    }

                    /* Decode newly reached 16-byte ADPCM block */
                    hle_spu_decode_adpcm_block(block_buf, v->pcm_block,
                                                &v->old_s1, &v->old_s2, NULL);
                    v->sample_idx = 0;
                }
            }

            /* Fetch PCM sample from active decoded block */
            int16_t sample_pcm = v->pcm_block[v->sample_idx % 28];

            /* Optional Linear Interpolation flag check */
            if (g_spu.interpolate_mode && v->sample_idx < 27) {
                int16_t next_pcm = v->pcm_block[v->sample_idx + 1];
                int32_t frac = v->pitch_counter; /* 0..0xFFF */
                sample_pcm = (int16_t)(sample_pcm + (((next_pcm - sample_pcm) * frac) >> 12));
            }

            /* Apply ADSR Envelope volume (0..0x7FFF) */
            int32_t env_pcm = ((int32_t)sample_pcm * (int32_t)v->adsr_level) >> 15;

            /* Apply per-voice Left/Right Volumes */
            int32_t vl = (env_pcm * (int16_t)v->vol_l) >> 15;
            int32_t vr = (env_pcm * (int16_t)v->vol_r) >> 15;

            mix_l += vl;
            mix_r += vr;
        }

        /* Apply Master Volume L/R */
        int32_t final_l = (mix_l * (int16_t)g_spu.mvol_l) >> 15;
        int32_t final_r = (mix_r * (int16_t)g_spu.mvol_r) >> 15;

        /* Clip to signed 16-bit PCM range */
        if (final_l > 32767) final_l = 32767;
        else if (final_l < -32768) final_l = -32768;

        if (final_r > 32767) final_r = 32767;
        else if (final_r < -32768) final_r = -32768;

        if (out) {
            out[f * 2 + 0] = (int16_t)final_l;
            out[f * 2 + 1] = (int16_t)final_r;
        }
    }
}

/* WAV File Dump Helper (16-bit Stereo PCM 44100Hz with standard 44-byte RIFF header) */
int hle_spu_wav_dump(const char *path)
{
    if (!path) return -1;

    FILE *f = fopen(path, "wb");
    if (!f) {
        hle_out("[spudev] Failed to open WAV dump file: %s\n", path);
        return -1;
    }

    uint32_t nframes = 44100; /* 1 second of audio */
    uint32_t data_size = nframes * 2 * sizeof(int16_t);
    uint32_t riff_size = 36 + data_size;

    /* 44-byte RIFF WAV Header */
    uint8_t header[44];
    memcpy(&header[0], "RIFF", 4);
    header[4] = (uint8_t)(riff_size & 0xFF);
    header[5] = (uint8_t)((riff_size >> 8) & 0xFF);
    header[6] = (uint8_t)((riff_size >> 16) & 0xFF);
    header[7] = (uint8_t)((riff_size >> 24) & 0xFF);

    memcpy(&header[8], "WAVEfmt ", 8);
    header[16] = 16; header[17] = 0; header[18] = 0; header[19] = 0; /* Subchunk1Size = 16 */
    header[20] = 1;  header[21] = 0;                                  /* AudioFormat = 1 (PCM) */
    header[22] = 2;  header[23] = 0;                                  /* NumChannels = 2 */

    uint32_t sample_rate = 44100;
    header[24] = (uint8_t)(sample_rate & 0xFF);
    header[25] = (uint8_t)((sample_rate >> 8) & 0xFF);
    header[26] = (uint8_t)((sample_rate >> 16) & 0xFF);
    header[27] = (uint8_t)((sample_rate >> 24) & 0xFF);

    uint32_t byte_rate = 44100 * 4;
    header[28] = (uint8_t)(byte_rate & 0xFF);
    header[29] = (uint8_t)((byte_rate >> 8) & 0xFF);
    header[30] = (uint8_t)((byte_rate >> 16) & 0xFF);
    header[31] = (uint8_t)((byte_rate >> 24) & 0xFF);

    header[32] = 4;  header[33] = 0;                                  /* BlockAlign = 4 */
    header[34] = 16; header[35] = 0;                                  /* BitsPerSample = 16 */

    memcpy(&header[36], "data", 4);
    header[40] = (uint8_t)(data_size & 0xFF);
    header[41] = (uint8_t)((data_size >> 8) & 0xFF);
    header[42] = (uint8_t)((data_size >> 16) & 0xFF);
    header[43] = (uint8_t)((data_size >> 24) & 0xFF);

    fwrite(header, 1, 44, f);

    int16_t *pcm_buf = (int16_t *)malloc(data_size);
    if (!pcm_buf) {
        fclose(f);
        return -1;
    }

    hle_spu_generate(nframes, pcm_buf);
    fwrite(pcm_buf, 1, data_size, f);

    free(pcm_buf);
    fclose(f);

    hle_out("[spudev] WAV dump written to %s (%u bytes)\n", path, 44 + data_size);
    return 0;
}
