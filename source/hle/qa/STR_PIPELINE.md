---
title: "Xenogears STR/FMV Playback Pipeline Architecture & Runtime Requirements"
summary: "Comprehensive technical analysis of PS1 STR video sector formats, Xenogears Module 6 movie playback execution loop, MDEC coverage gaps, CD XA-ADPCM audio streaming, and an 18-step ordered HLE runtime checklist for playable FMV."
---

# Xenogears STR/FMV Playback Pipeline Architecture & Runtime Requirements

**Document Version:** 1.0 (2026-09-11)  
**Target:** Xenogears USA Disc-1 (SLUS-006.64)  
**Focus:** FMV/STR Decoding & Module 6 (Movie Overlay) Integration  

---

## 1. PS1 STR Format Essentials & Demux Structure

### 1.1 CD Sector Structure & Payload Layout
* **Sector Encoding (FACTS from `research_cd_spec.md` & `RECOMP_INTEL.md` / INFERENCE from PS1 Spec):**
  * PS1 video streams use **Mode 2 Form 2** CD-ROM sectors (2336 payload bytes per sector, raw size 2340 bytes including 4-byte subheader).
  * Mode 2 Form 2 sectors drop EDC/ECC error correction to maximize data throughput for streaming video and audio.
  * **XA Subheader Submode Flags (Byte 2 of 4-byte subheader):**
    * Bit 2 (`0x04`): `Submode.Video` — Sector contains MDEC video bitstream payload.
    * Bit 3 (`0x08`): `Submode.Audio` — Sector contains XA-ADPCM audio payload.
    * Bit 5 (`0x20`): `Submode.RT` (Real-Time) — Streaming sector requiring synchronized delivery.
    * Bit 6 (`0x40`): `Submode.Form2` — 2324/2336-byte raw data payload.

### 1.2 STR Video Sector Header & Bitstream Payload (INFERENCE from PS1 Spec)
Within each 2336-byte Mode 2 Form 2 video sector, a 32-byte STR video header precedes 2016 (or 2020/2232) bytes of compressed MDEC bitstream data:

| Offset | Field Size | Name | Description |
|---|---|---|---|
| `+0x00` | 2 Bytes | `magic_type` | Demux chunk type marker (`0x0001` or `0x0160` / `0x8001`) |
| `+0x02` | 2 Bytes | `chunk_index` | 0-based index of this sector chunk within current video frame |
| `+0x04` | 2 Bytes | `chunk_count` | Total number of sector chunks required to reassemble current frame |
| `+0x06` | 2 Bytes | `frame_number` | Frame sequence index |
| `+0x08` | 4 Bytes | `chunk_payload_size` | Active payload byte count in this sector (typically 2016 or 2020 bytes) |
| `+0x0C` | 2 Bytes | `frame_width` | Native frame width in pixels (e.g., 320 or 256) |
| `+0x0E` | 2 Bytes | `frame_height` | Native frame height in pixels (e.g., 240 or 224) |
| `+0x10` | 2 Bytes | `macroblock_count` | Total macroblocks in frame (e.g., $20 \times 15 = 300$ for 320x240) |
| `+0x12` | 2 Bytes | `quant_scale` | Default quantization scale for frame |
| `+0x14` | 2 Bytes | `version` | Stream format version flag |
| `+0x16` | 10 Bytes | `reserved` | Zero padding to 32 bytes |
| `+0x20` | 2016 Bytes | `bitstream_data` | Packed MDEC Huffman/RLE macroblock bitstream slice |

### 1.3 Format Variants: `.STR` vs Custom Square `.IKI` (INFERENCE from Repo & PS1 Spec)
* Standard `.STR` files store frame chunk counts in header offset `+0x04` and append chunks sequentially.
* Square Enix title variants (such as `.IKI` / custom `.STR` variants used in Xenogears/FF) feature keyframe index tables and variable-length slice indexing for synchronized XA-ADPCM audio alignment.

### 1.4 Frame Layout & Macroblock Geometry (INFERENCE from PS1 Spec)
* **Macroblock Size:** $16 \times 16$ pixels (composed of four $8 \times 8$ $Y$ luminance blocks, one $8 \times 8$ $C_r$ block, and one $8 \times 8$ $C_b$ block — 4:2:0 YCbCr sampling).
* **Grid Layout for 320x240 Resolution:**
  * Width: 320 pixels / 16 = **20 macroblocks wide**.
  * Height: 240 pixels / 16 = **15 macroblocks tall**.
  * Total Macroblocks per Frame = **300 macroblocks** ($20 \times 15$).
  *(Note: 256x240 resolution uses 16 macroblocks wide x 15 tall = 240 macroblocks).*

### 1.5 Quantization & Scale Tables (FACTS from `hle_mdec.c` & PS1 Spec)
* **Quantization Tables ($I_Y$ and $I_{UV}$):** Two 64-byte matrices defining quantization divisors for 8x8 DCT AC coefficients. Uploaded to MDEC hardware via Command 2 (`0x20000000`).
* **Scale Table:** 64 signed 16-bit constants (14-bit fractional component) multiplying IDCT outputs. Uploaded to MDEC via Command 3 (`0x30000000`).

### 1.6 Output Color Representation & Palette (FACTS from `hle_mdec.c` & PS1 Spec)
* MDEC decodes compressed macroblocks directly into either **15bpp RGB** (5-5-5 format with bit 15 STP bit set) or **24bpp RGB** (8-8-8 format).
* No 16-color CLUT/palette is used during MDEC video decoding — full color RGB pixel vectors are transferred directly to VRAM or RAM via DMA Channel 1.

---

## 2. Xenogears-Specific Playback Chain (Module 6 & Kernel)

### 2.1 Boot Module Identity & Entry (FACTS from `OVERLAY_SYMBOLS.md`)
* **Module 6 (`movie.bin`):** Disc Archive Directory `0x01`, File 18 (`0x12`), LBA sector `109158`, uncompressed load address `0x8006FAF0`.
* **Module Entry Point:** `0x800737EC MovieModuleEntry`.
* **Execution Paths:**
  1. **Production Path:** `MovieModuleEntry` (`0x800737EC`) $\rightarrow$ `MovieLaunchScriptedMovie` (`0x800763BC`) $\rightarrow$ `MovieRunPlayback` (`0x80076488`).
  2. **Debug Diagnostic Path:** `MovieModuleEntry` branches to 14-item debug menu (`0x80074230`) providing standalone diagnostic screens:
     * `MovieRunCdReadStressTestScreen` (`0x800704E8`): Asynchronous CD read and verification monitor.
     * `MovieRunCdSectorMonitor` (`0x80075534`): Raw CD sector inspector.
     * `MovieRunFatBrowser` (`0x80075D8C`): Filesystem FAT entry reader.
     * `MovieLaunchDebugMovie` (`0x8007625C`): Manual movie playback test harness.

### 2.2 Core Playback Loop & Symbol Function Mapping (FACTS from `OVERLAY_SYMBOLS.md` + INFERENCE)

```
                       [MovieRunPlayback 0x80076488]
                                    │
    ┌───────────────────────────────┼───────────────────────────────┐
    ▼                               ▼                               ▼
[Sector Reader]            [Bitstream Feeder]           [Frame Scheduler & Slice CB]
MovieFindStrFrameSector    Extract 32B STR Header       MovieDecodeSliceCallback
(0x80074BA4)               Push BS to MDEC 0x1F801820   (0x800768D8)
      │                             │                               │
      ▼                             ▼                               ▼
Reads Mode 2 Form 2        DMA Ch0 (RAM -> MDEC)        Swaps frame buffers & updates
Sectors via CD Ring        DMA Ch1 (MDEC -> RAM)        slice progress state
```

* **Player Main Loop (`MovieRunPlayback` 0x80076488):** Orchestrates movie streaming. Initializes resident movie state (`0x80076588`), sets display parameters (`0x800765F4`), executes the streaming loop, and handles cleanup via `MovieShutdownResidentPlayer` (`0x80076834`).
* **Frame Scheduler & Skip Input (`MoviePollSkipInput` 0x800769A4):** Polls joypad input for movie skip requests, updates frame timer counters, and triggers audio fade-down on abort.
* **Sector Reader & Position Lookup (`MovieFindStrFrameSector` 0x80074BA4):** Resolves requested frame sequence numbers to physical CD LBA sector offsets. `MovieFindLastStrFrameNumber` (`0x8007519C`) queries total stream frames.
* **Slice Submission Callback (`MovieDecodeSliceCallback` 0x800768D8):** Registered at `0x80076668`. Fired upon completion of MDEC DMA slice transfers. Increments decoded slice counters, checks if all slices for the frame are finished, and triggers double-buffered frame state swapping.

### 2.3 CD Reading Mode & Speed Requirements (FACTS from `research_cd_spec.md` + INFERENCE)
* **CD Speed:** **Double-Speed (2x = 300 sectors/second)**. 1x speed (150 sectors/sec) provides insufficient throughput for interleaved video + audio streams (~600KB/s required for 2x vs ~300KB/s for 1x).
* **CD Mode Setting:** Command `Setmode` (`0x0E`) param `0x80` or `0xE0` (2x speed, XA-ADPCM filter enabled, 2340-byte raw sector read mode).
* **Streaming Command:** `ReadS` (`0x1B`) or `ReadN` (`0x06`) continuously streams 2340-byte raw sectors into RAM ring buffers via CD DMA Channel 3.

---

## 3. MDEC Module Coverage vs. STR Decode Flow

### 3.1 Implemented Features in `hle_mdec.c` (FACTS from `hle_mdec.c`)
* **Commands Handled:** Command 0 (Reset/NOP), Command 1 (Decode Macroblocks), Command 2 (Set Quant Tables), Command 3 (Set Scale Table).
* **MMIO Registers:** `0x1F801820` (Cmd/Param/Data) and `0x1F801824` (Status/Control).
* **Decompression Pipeline:** Full RLE Huffman decoding, inverse quantization, zigzag reordering, $8 \times 8$ floating-point IDCT, YCbCr-to-RGB color space conversion matrix.
* **Output Formats:** 15bpp (depth 3) and 24bpp (depth 2).
* **DMA Functions:** `hle_mdec_dma0_in` (RAM $\rightarrow$ MDEC) and `hle_mdec_dma1_out` (MDEC $\rightarrow$ RAM).

### 3.2 Key Gaps & Missing Capabilities in `hle_mdec.c` for Real-Time STR Frames (FACTS vs INFERENCE)
1. **Gap 1: Synchronous vs. Asynchronous Slice Decoding (INFERENCE):**
   * *Current State:* `hle_mdec.c` processes the entire input buffer synchronously in a single call inside `mdec_process_decode()`.
   * *STR Requirement:* STR decoding splits frames into slices (e.g., 16 or 20 macroblocks per slice). MDEC status register (`0x1F801824`) busy bits and DMA request bits must dynamically update after each slice so `MovieDecodeSliceCallback` (`0x800768D8`) can execute asynchronously on slice completion.
2. **Gap 2: Stream Bitstream Demuxing (FACTS from `hle_mdec.c` & PS1 Spec):**
   * *Current State:* `hle_mdec.c` expects pure, pre-demuxed MDEC RLE words.
   * *STR Requirement:* STR sector payloads contain 32-byte headers and chunk structures. The HLE runtime / demuxer must strip these headers, extract active payload words, and handle multi-sector reassembly before feeding DMA Channel 0.
3. **Gap 3: Direct VRAM Blitting & GPU Handshake (INFERENCE):**
   * *Current State:* `hle_mdec_dma1_out` writes decoded RGB pixels into a RAM buffer.
   * *STR Requirement:* Decoded 15bpp/24bpp RAM slice buffers must be pushed to VRAM via GPU DMA Channel 2 or GP0 load commands (`0xA0000000` / `ImageLoad`), followed by updating GPU display origin (`GP1(0x05)`).
4. **Gap 4: On-the-Fly Quantization Table Updates (FACTS from `hle_mdec.c`):**
   * *Current State:* Quantization tables are set during initialization or explicit `Set Quant Tables` commands.
   * *STR Requirement:* STR streams frequently issue Command 2 updates dynamically in sector stream headers. `hle_mdec.c` must support table updates mid-stream without resetting output FIFO state.

---

## 4. Audio During Movies (XA-ADPCM vs. Streamed SPU Audio)

### 4.1 Disc Layout & Audio Architecture (FACTS from `SOUND_DRIVER_INTEL.md` & `RECOMP_INTEL.md`)
* **Disc Total Size:** 718,738,272 bytes = 305,352 sectors.
* **FileSystem Region:** Sectors 0..109157 store archive files and core executables.
* **Movie Region:** LBA 109158 (`movie.bin`) onwards contains `.STR` stream files.
* **Sound Driver Storage (`system/sound.c`):** Main SPU RAM handles sequence music (SMDS), sound effects (SEDS), and sample wave banks (WDS) via `LoadAndRegisterWdsBank` (`0x80037FD8`).

### 4.2 Opening FMV Audio Mechanism: Interleaved XA-ADPCM (FACTS from Spec & Repo Intel)
* The opening movie audio does **NOT** use SPU WDS/SMDS sound banks.
* Instead, movie soundtrack audio consists of **interleaved XA-ADPCM audio sectors** placed directly within the `.STR` file on disc (Submode bit 3 `Submode.Audio` set).
* **Hardware Demuxing Path:**
  1. CD-ROM controller reads Mode 2 Form 2 sectors at 2x double speed (300 sectors/sec).
  2. The controller hardware automatically filters XA-ADPCM sectors out of the stream.
  3. The internal XA decoder converts ADPCM audio blocks directly to $37.8\text{ kHz}$ or $44.1\text{ kHz}$ stereo PCM audio.
  4. Decoded stereo PCM audio streams straight to the SPU CD-Audio input registers (`0x1F801DB0` / `0x1F801DB2` CD Volume Left/Right).
* **Conclusion:** Opening FMV audio is **hardware-streamed XA-ADPCM audio** interleaved with video sectors on disc.

---

## 5. Ordered Runtime Checklist (End-to-End Playable FMV)

The exact 18-step sequence our HLE runtime must support for the first FMV to play end-to-end:

1. `[kernel/movie]` Kernel loads Module 6 (`movie.bin`) from CD LBA 109158 into RAM at `0x8006FAF0` and jumps to `MovieModuleEntry` (`0x800737EC`).
2. `[kernel/movie]` `MovieModuleEntry` evaluates boot flags and invokes `MovieLaunchScriptedMovie` (`0x800763BC`) to initiate opening FMV playback.
3. `[cd]` Runtime receives CD `Setmode` (`0x0E`) command with mode `0x80` or `0xE0` to configure 2x double-speed, XA-ADPCM enable, and 2340-byte raw sector reading.
4. `[cd]` Runtime receives `Setloc` (`0x02`) command targeting the opening STR stream starting LBA sector on disc.
5. `[cd]` Runtime receives `ReadS` (`0x1B`) or `ReadN` (`0x06`) command to begin continuous 2x streaming (300 sectors/sec) of Mode 2 Form 2 raw sectors into the CD ring buffer.
6. `[cd]` Controller hardware demuxes XA-ADPCM audio sectors (submode bit 3) from the stream and routes decoded PCM samples directly to SPU CD audio input registers (`0x1F801DB0`/`0x1F801DB2`).
7. `[spu]` SPU applies main volume and CD input volume scaling (`0x1F801DB0`/`0x1F801DB2`) to mix streaming XA movie audio into the master output buffer.
8. `[kernel/movie]` `MovieRunPlayback` (`0x80076488`) reads 2340-byte video sectors from CD ring buffer, parses 32-byte STR sector headers, and reassembles macroblock slice bitstream chunks into RAM.
9. `[mdec]` Runtime handles MDEC Command 2 (`0x20000000` `Set Quant Tables`) via MMIO `0x1F801820` to update $I_Y$ and $I_{UV}$ quantization matrices for the video stream.
10. `[mdec]` Runtime handles MDEC Command 3 (`0x30000000` `Set Scale Table`) via MMIO `0x1F801820` to set the 64 IDCT scale constants.
11. `[dma]` DMA Channel 0 (`MDEC In`, `0x1F801080`) transfers reassembled MDEC slice bitstream words from RAM to MDEC command/data port (`0x1F801820`).
12. `[mdec]` MDEC engine processes Command 1 (`0x10000000` `Decode Macroblocks`), executing RLE decoding, inverse quantization, zigzag reordering, 8x8 IDCT, and YCbCr to 15bpp/24bpp RGB color space conversion.
13. `[dma]` DMA Channel 1 (`MDEC Out`, `0x1F801090`) transfers decoded 15bpp/24bpp RGB macroblock pixel buffer from MDEC FIFO (`0x1F801820`) to RAM frame slice buffers.
14. `[kernel/movie]` `MovieDecodeSliceCallback` (`0x800768D8`) fires upon DMA completion to track slice decode progress and signals full frame completion when all macroblock slices finish.
15. `[dma]` DMA Channel 2 (`GPU`, `0x1F8010A0`) or CPU GP0 load transfers decoded 320x240 RGB pixel frame buffer from RAM into GPU VRAM display area.
16. `[gpu]` GPU display origin (`GP1(0x05)`) and display range (`GP1(0x07)`/`GP1(0x08)`) are updated to present the newly uploaded VRAM frame buffer on screen.
17. `[kernel/movie]` `MoviePollSkipInput` (`0x800769A4`) polls joypad state each frame to handle user skip requests and initiate audio fade-out if triggered.
18. `[cd]` Upon movie end or skip, runtime receives CD `Pause` (`0x09`) command to halt 2x sector streaming and transition drive back to idle state.
