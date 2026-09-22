/*
 * xenolift SPU (Sound Processing Unit) HLE Module Header
 * Path: xenolift/hle/hle_spu.h
 *
 * Spec reference: psx-spx (Martin Korth, PlayStation Sound Processing Unit)
 * - SPU Overview & Register Map: 0x1F801C00 - 0x1F801E00
 * - SPU ADPCM Samples & Decoding
 * - SPU Volume and ADSR Generator
 * - SPU Control and Status Registers
 */

#ifndef HLE_SPU_H
#define HLE_SPU_H

#include <stdint.h>
#include <stddef.h>
#include <stdio.h>

#ifdef __cplusplus
extern "C" {
#endif

#define SPU_RAM_SIZE (512 * 1024) /* 512 KB SPU RAM (256K 16-bit words) */
#define SPU_VOICE_COUNT 24

/*
 * Standard PSY-Q / Kernel SPU RAM Memory Layout Documented Reference:
 * -------------------------------------------------------------------
 * 0x0000 - 0x03FF (1024 B): Fixed Work Area / Capture Buffers
 *                           - 0x0000..0x03FF: CD Audio L/R & Voice 1/3 Capture buffers
 *                           - Default silent ADPCM dummy loop block at 0x0000 (16 B)
 * 0x0400 - 0x07FF (1024 B): Kernel Sound Allocator / Sound Bank Headers
 *                           - First-fit allocator bookkeeping & default loop block
 * 0x0800 - End of RAM     : Sound Sample Data (ADPCM VAG/VAB sound banks) &
 *                           Reverb Work Area (allocated from top of RAM down)
 */

/* ADSR State Machine Phases */
typedef enum {
    SPU_ADSR_OFF = 0,
    SPU_ADSR_ATTACK,
    SPU_ADSR_DECAY,
    SPU_ADSR_SUSTAIN,
    SPU_ADSR_RELEASE
} hle_spu_adsr_phase_t;

/* Reusable Voice Channel Structure (24 instantiated) */
typedef struct {
    int id;                      /* Voice channel index (0..23) */

    /* Registers */
    uint16_t vol_l;              /* Voice Volume Left (0x1F801C00 + N*10h) */
    uint16_t vol_r;              /* Voice Volume Right (0x1F801C02 + N*10h) */
    uint16_t pitch;              /* ADPCM Sample Rate / Pitch (0x1F801C04 + N*10h)
                                  * 0x1000 = 44100 Hz (1.0 ratio), 0x4000 = max (176.4 kHz) */
    uint32_t start_addr;         /* ADPCM Start Address in SPU RAM (byte address) */
    uint16_t adsr_low;           /* ADSR Lower 16 bits (0x1F801C08 + N*10h) */
    uint16_t adsr_high;          /* ADSR Upper 16 bits (0x1F801C0A + N*10h) */
    int16_t  adsr_level;         /* Current ADSR Volume Level (0..0x7FFF) */
    uint32_t repeat_addr;        /* ADPCM Repeat Address in SPU RAM (byte address) */
    uint32_t current_addr;       /* Current ADPCM Block Address in SPU RAM (byte address) */

    /* Rate Counter and Sampling State */
    uint32_t pitch_counter;      /* 16.12 fixed point phase accumulator */

    /* ADPCM Decoding State */
    int16_t  pcm_block[28];      /* Current decoded 28 PCM 16-bit samples */
    int      sample_idx;         /* Index within pcm_block (0..27) */
    int16_t  old_s1;             /* Filter history s[n-1] */
    int16_t  old_s2;             /* Filter history s[n-2] */

    /* ADSR State Machine */
    hle_spu_adsr_phase_t adsr_phase;
    uint32_t adsr_cycle_counter;

    /* Status flags */
    uint8_t  is_on;              /* Voice active / key-on flag */
    uint8_t  loop_end_hit;       /* ENDX bit set flag for this voice */
} hle_spu_voice_t;

/* Global SPU Hardware Model State */
typedef struct {
    uint8_t ram[SPU_RAM_SIZE];   /* 512KB SPU RAM */
    hle_spu_voice_t voices[SPU_VOICE_COUNT];

    /* Global Registers (0x1F801D80 - 0x1F801DBF window) */
    uint16_t mvol_l;             /* Main Volume Left (0x1F801D80) */
    uint16_t mvol_r;             /* Main Volume Right (0x1F801D82) */
    uint16_t svol_l;             /* Reverb Volume Left (0x1F801D84) */
    uint16_t svol_r;             /* Reverb Volume Right (0x1F801D86) */
    uint32_t key_on_flags;       /* Key On flags (0x1F801D88 / 0x1F801D8A) */
    uint32_t key_off_flags;      /* Key Off flags (0x1F801D8C / 0x1F801D8E) */
    uint32_t pmon_flags;         /* Pitch Modulation Enable (0x1F801D90 / 0x1F801D92) */
    uint32_t non_flags;          /* Noise Enable (0x1F801D94 / 0x1F801D96) */
    uint32_t eon_flags;          /* Reverb Enable (0x1F801D98 / 0x1F801D9A) */
    uint32_t endx_flags;         /* Voice End Flags (0x1F801D9C / 0x1F801D9E) */

    uint32_t irq_addr;           /* IRQ Byte Address (from 0x1F801DA4 * 8) */
    uint32_t transfer_addr;      /* Transfer Byte Address (from 0x1F801DA6 * 8) */
    uint16_t spucnt;             /* SPU Control Register (0x1F801DAA) */
    uint16_t spudac;             /* Sound RAM Data Transfer Control (0x1F801DAC) */
    uint16_t spustat;            /* SPU Status Register (0x1F801DAE) */

    uint16_t cd_vol_l;           /* CD Audio Volume Left (0x1F801DB0) */
    uint16_t cd_vol_r;           /* CD Audio Volume Right (0x1F801DB2) */
    uint16_t ext_vol_l;          /* External Audio Volume Left (0x1F801DB4) */
    uint16_t ext_vol_r;          /* External Audio Volume Right (0x1F801DB6) */

    /* Flag for optional resample mode: 0 = nearest-neighbor (default), 1 = linear interpolation */
    int interpolate_mode;
} hle_spu_state_t;

extern hle_spu_state_t g_spu;

/* Required Core API */
void hle_spu_reset(void);
void hle_spu_port_write(uint32_t addr, uint16_t v);
uint16_t hle_spu_port_read(uint32_t addr);
void hle_spu_dma_write(uint32_t spu_addr, const uint8_t *data, uint32_t len);
void hle_spu_generate(uint32_t nframes, int16_t *out);
int hle_spu_wav_dump(const char *path);

/* Standalone ADPCM block decoder helper (for unit testing and internal decoding) */
void hle_spu_decode_adpcm_block(const uint8_t block[16], int16_t pcm_out[28],
                                int16_t *old_s1, int16_t *old_s2,
                                uint8_t *out_flags);

#ifdef __cplusplus
}
#endif

#endif /* HLE_SPU_H */
