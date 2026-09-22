# WAVE Findings & SPU Audio Plan — Xenolift HLE
**Agent:** WAVE (SPU/Audio Specialist)
**Date:** 2026-09-13
**Deliverable:** xenolift/hle/agents/WAVE-findings.md

## 1. Inventory of Current SPU HLE in runtime.c
Inspection of `xenolift/runtime/runtime.c` reveals the current SPU HLE implementation state:
- **Header & Binding:** `#include "../hle/hle_spu.h"` is included; `hle_spu_reset()` is called during reset (`xenolift_reset()`). Global state `hle_spu_state_t g_spu` lives in `hle_spu.c`.
- **Register Writes:** `io_special_write()` routes MMIO writes in range `0x1F801C00..0x1F801DAF` to `hle_spu_port_write(p, v)`. First 3 writes log with `[hle-spu] reg write`.
- **Register Reads (GAP):** `io_special_read()` has **NO** handler for `0x1F801C00..0x1F801DFF`. Reads fall through to raw RAM mirror byte reads (`xenolift_mem`). `hle_spu_port_read()` is never called.
- **SPU DMA (Channel 4):** `io_special_write()` handles `0x1F8010C8` (D4_CHCR). Copies DMA chunks from RAM (`0x1F8010C0` MADR) into `g_spu.ram[spu_wr_pos]`, invoking `hle_spu_dma_write()`. Sets SPUSTAT/SPUCNT bits (`0x1F801DA6 |= 0x30`, `0x1F801DAA |= 0x80`).
- **Mute Loop State:** `hle_spu_reset()` seeds 16-byte silent dummy ADPCM loops (`0x00, 0x07, 0x00...`) at SPU RAM offsets `0x0000` and `0x0400`. All 24 voices default to `start_addr = 0x0000`.
- **RAM Snapshotting:** `gpu_dump_capture()` writes full 512KB SPU RAM to `spu_ram.bin` at park/halt.
- **Audio Generation (GAP):** `hle_spu_generate()` exists in `hle_spu.c` (ADPCM decode, ADSR step, stereo mix) but is **NEVER** called anywhere in `runtime.c`. No host audio device or PCM stream is active.

## 2. Minimal Viable Audio Spec & Sound Driver Architecture
To make ADPCM audio audible on voice key-on, the runtime must interface with PS1 hardware conventions and the resident sound driver:

### 2.1 PS1 SPU Hardware Write Conventions
- **Voice Start Address:** `0x1F801C06 + 0x10 * v` (voices $v \in [0, 23]$). Register holds 16-bit word address ($\text{byte\_addr} / 8$).
- **Voice Pitch:** `0x1F801C04 + 0x10 * v` ($0x1000 = 44.1\text{ kHz}$ sample rate ratio 1.0).
- **Voice Volumes:** `0x1F801C00 + 0x10 * v` (Left) and `0x1F801C02 + 0x10 * v` (Right) ($0..0x7FFF$).
- **Voice ADSR:** `0x1F801C08 + 0x10 * v` (ADSR Low) and `0x1F801C0A + 0x10 * v` (ADSR High).
- **Key-On Registers:** `0x1F801D88` (voices 0..15) and `0x1F801D8A` (voices 16..23). Writing 1s latches voice start address, resets phase, and enters ADSR Attack phase (`spu_voice_key_on()`).
- **Key-Off Registers:** `0x1F801D8C` (voices 0..15) and `0x1F801D8E` (voices 16..23). Initiates ADSR Release phase (`spu_voice_key_off()`).
- **SPU Control/Status:** `0x1F801DAA` (SPUCNT, bit 15 = Master Unmute), `0x1F801DAE` (SPUSTAT).

### 2.2 Sound Engine Location in Emitted Code
- **Driver Architecture:** The Xenogears sound driver (`system/sound.c`) is **NOT** a dynamic overlay module; it resides permanently in the resident kernel image (`SLUS_006.64`) at VAs `0x80037C80`–`0x8003F500`.
- **Core Kernel Driver Routines:**
  - `InitializeSoundSystem` (`0x80037C80`): Allocates sound heap (`0x80065B10`–`0x8006BE00`), resets SPU registers, installs 240Hz timer callback.
  - `SoundSequencerCallback240Hz` (`0x8003C020`): 240Hz root timer callback (~4.167ms). Interprets sequence bytecode (SMDS/SEDS), steps modulators, and triggers driver register flushes.
  - `CommitPendingSpuVoiceWrites` (`0x8003E900`): Flushes dirty voice parameters (vol, pitch, start_addr, ADSR) to MMIO ports and writes Key-On masks (`0x1F801D88` / `0x1F801D8A`).
  - `CommitPendingSpuVoiceKeyOffs` (`0x8003EB5C`): Writes Key-Off masks (`0x1F801D8C` / `0x1F801D8E`).
- **Boot Buffer / Overlay Landings:**
  - `0x8006FAF8`: Boot Heap Freelist / Module 2 (Field) landing (61,680B).
  - `0x8007EBF0`: Boot Heap Frontier / Module 3 (WorldMap) landing (155,120B).
  - `0x800A49E8`: Control Block / Module 4 (Battle) landing (23,744B).
  - `0x800AA6B0`: Sound Bank staging buffer (21,984B) — field WDS/SEDS sound resources load here before SPU DMA ch4 upload.
  - `0x800AFC98`: Staging head / Module 6 (Movie) landing (2,660B).

## 3. Ranked Implementation Plan

### Phase A: Key-On Detection & Voice Sample Dump Probe (Pure Probe, Zero Risk)
- **Goal:** Intercept game Key-On writes (`0x1F801D88`/`0x1F801D8A`), capture active voice parameters, and dump the target ADPCM sample header + raw SPU RAM bytes to stderr.
- **Runtime Hook:** In `hle_spu_port_write()` (or `io_special_write()` for `0x1F801D88`/`0x1F801D8A`):
  - When Key-On bit $v$ is asserted, print voice $v$ `start_addr`, `pitch`, `vol_l/r`, `adsr_low/high`, and inspect first 16 bytes of ADPCM data at `g_spu.ram[start_addr]`.
- **Concrete Cells & Registers to Watch:**
  - Registers: `0x1F801D88`, `0x1F801D8A`, `0x1F801C06 + 0x10 * v`.
  - Kernel Cells: `0x80069514` (`g_SoundSpuIRQCount`), `0x80065B10` (Sound Heap Base), `0x800695E4` (Sound Heap Limit).
- **Digest Section & Logging:**
  - Add `=SPU-KEYON=` section to `run.sh` capturing `[spu-keyon]` log tag.
  - Budget cap: 240 lines max (prevents log storms per Lesson L15).

### Phase B: Host-Side ADPCM Decoder & Audio Output
- **Goal:** Drive `hle_spu_generate()` from the runtime loop to mix active voice ADPCM channels into host PCM audio and output to file/stream.
- **Runtime Integration Hook:**
  - Call `hle_spu_generate(nframes, pcm_buffer)` periodically (e.g. 60Hz or 240Hz frame tick in `runtime.c`).
  - Wire SPU IRQ support in `hle_spu_generate()`: compare voice `current_addr` against `g_spu.irq_addr` (`0x1F801DA4 * 8`), setting `SPUSTAT` bit 6 (`0x0040`) to service `SoundSpuIRQHandler` (`0x8003BFA0`).
  - At park/halt, invoke `hle_spu_wav_dump("audio_out.wav")` to save rendered audio.
- **Concrete Cells & Registers to Watch:**
  - Registers: `0x1F801DAE` (SPUSTAT), `0x1F801DAA` (SPUCNT), `0x1F801DA4` (IRQ Addr).
  - Kernel Cells: `0x8006950C` (`g_SoundSpuIrqCallbackFn`).
- **Digest Section & Logging:**
  - Add `=SPU-AUDIO=` section in `run.sh` logging frame count, active voices, non-zero sample amplitudes, and WAV output status (`[spu-audio]`).
