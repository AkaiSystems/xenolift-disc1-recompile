# Xenogears HLE — MDEC Async Slice DMA Architecture Specification & Upgrade Plan

**Document Version:** 1.0 (2026-09-12)  
**Target:** Xenogears USA Disc-1 (`SLUS-006.64`), Module 6 (`movie.bin`)  
**Scope:** MDEC Asynchronous Slice DMA, Kernel Interrupt Event Pipeline, and `hle_mdec` Subsystem Upgrade Specification  
**Status:** SPECIFICATION / ARCHITECTURE DESIGN (Gap #1 Closure)

---

## Executive Summary

In the Xenogears PS1 HLE runtime (`xenolift`), the current Motion Decoder implementation (`hle_mdec.c`) is **synchronous and monolithic**: a single call to `hle_mdec_dma0_in` decodes an entire input bitstream buffer in a blocking loop.

However, real PlayStation hardware and Xenogears' Module 6 (`movie.bin`) streaming player execute MDEC decoding via **asynchronous slice DMA** driven by per-slice callbacks (`MovieDecodeSliceCallback` / `MovieSliceCallback` at `0x800768D8`). In the real game engine, video frames are divided into horizontal slices (typically 16 or 20 macroblocks per sector payload), demuxed from Mode 2 Form 2 CD sectors, and streamed into MDEC FIFO (`0x1F801820`). As each slice completes, MDEC or DMA Channel 1 IRQs fire, invoking the player's slice callback to double-buffer frame state, upload RGB data to VRAM, and pace playback.

This document presents the complete reverse-engineered mapping of the Xenogears movie playback chain (derived from the Oracle sources `noah_movie.cpp` and `noah_strPlayer.cpp` in `hle/qa/external/`, `STR_PIPELINE.md`, and `OVERLAY_SYMBOLS.md`), documents the current gaps in `hle_mdec.c`, and specifies the asynchronous upgrade design and test plan to eliminate FMV playback stalls before the boot wall falls.

---

## 1. Disassembly & Mapping of the Movie Player Chain (Module 6 Overlay)

### 1.1 Overlay Identity & Execution Memory Map
* **Module Identity:** Archive Directory `0x01`, File 18 (`0x12`), LBA sector `109158`, size 14,360 bytes compressed (LZSS), uncompressed loaded size 29,779 bytes (`0x7453`).
* **Overlay Load Range:** `0x8006FAF0` – `0x80076F43`.
* **Module Entry Point:** `MovieModuleEntry` (`0x800737EC`).

### 1.2 Core Playback Control Chain Step-by-Step

#### 1. `MovieLaunchScriptedMovie` (`0x800763BC`)
* **Role:** High-level launcher for scripted FMV sequences (e.g. opening FMV).
* **Execution Flow:**
  1. Configures active archive directory (`0x18, 0` for picture-only or `0x18, 1` for picture + XA-ADPCM audio).
  2. Resolves movie file sector offset on disc using `getFileStartSector` and total sector count `fileSectors`.
  3. Prepares GPU display state: clears display area (`0x280` x `0x200`), calls `DrawSync(0)`, `VSync(0)`, and turns off display mask (`SetDispMask(0)`).
  4. Materializes and registers `MovieDecodeSliceCallback` (`0x800768D8`).
  5. Invokes `MovieRunPlayback` (`0x80076488`).

#### 2. `MovieRunPlayback` (`0x80076488`)
* **Role:** Resident movie streaming and decode loop orchestrator.
* **Execution Flow:**
  1. Initializes resident player state at `0x80076588`.
  2. Configures display dimensions (e.g. 320x240 or 256x224) at `0x800765F4`.
  3. Re-enables display mask (`SetDispMask(1)`).
  4. Enters streaming loop:
     * Demuxes next sector from CD ring buffer via `MovieFindStrFrameSector` (`0x80074BA4`).
     * Extracts compressed 2016-byte MDEC bitstream slice.
     * Feeds bitstream to MDEC Command FIFO (`0x1F801820`) via DMA Channel 0 (RAM $\rightarrow$ MDEC).
     * Triggers asynchronous slice decode.
     * Evaluates `MoviePollSkipInput` (`0x800769A4`).
     * Controls frame pacing (target: 15 FPS = 1 frame every 2 NTSC vsyncs = ~66.6ms).
  5. On loop exit or abort, calls `MovieShutdownResidentPlayer` (`0x80076834`), restores display settings, restores kernel game mode (`setGameMode(movieReturnMode)`), and reboots game state (`bootGame(0)`).

#### 3. `MovieDecodeSliceCallback` (`0x800768D8`)
* **Role:** Asynchronous completion callback for MDEC slice transfers.
* **Execution Flow:**
  1. Triggered upon DMA Channel 1 (MDEC $\rightarrow$ RAM) transfer completion of a decoded RGB slice.
  2. Receives decoded slice index and slice status parameters.
  3. Increments completed slice counter (`collectedSectors`).
  4. Evaluates frame completion condition (`collectedSectors == expectedSectors`):
     * Marks frame decoding finished for active frame number.
     * Swaps double-buffered RGB frame buffer pointers (`m_currentFrameRGB`).
     * Issues GPU LoadImage (`0xA0000000`) or DMA Channel 2 transfer to copy decoded frame RGB to VRAM.

#### 4. `MoviePollSkipInput` (`0x800769A4`)
* **Role:** Input polling and movie skip/abort controller.
* **Execution Flow:**
  1. Polled every VSync tick during movie playback loop.
  2. Reads pad input state for Cross (`0x0040`) or Start (`0x0800`) button presses.
  3. If skip button pressed and `fadeParam == 0`, sets `skipCountdown = 5`.
  4. Initiates SPU CD volume attenuation (XA audio fade-down: sets SPU CD Volume registers `0x1F801D80` / `0x1F801D82` to 0).
  5. When `skipCountdown` reaches 1, terminates `MovieRunPlayback` streaming loop.

---

## 2. Reconstructed Slice Pipeline Architecture

```
+-----------------------------------------------------------------------------------+
|                                CD-ROM DRIVE                                       |
| Mode 2 Form 2 Raw Sectors (2340/2352 Bytes) @ Double-Speed (300 sectors/sec)       |
+-----------------------------------------------------------------------------------+
                                          |
                                          v (CD DMA Channel 3)
+-----------------------------------------------------------------------------------+
|                             RAM CD RING BUFFER                                    |
| Subheader Byte 2 Check: Bit 2 (0x04) = Video | Bit 3 (0x08) = XA Audio              |
+-----------------------------------------------------------------------------------+
                  |                                           |
                  v (Video Sector)                            v (Audio Sector)
+-----------------------------------+        +--------------------------------------+
|     STR SECTOR DEMUXER            |        |           SPU XA-ADPCM               |
| Strip 32B Header (0x20..0x7FF)    |        | Write CD Vol 0x1F801D80 / 0x1F801D82 |
| Extract 2016B MDEC Bitstream      |        | Flush & Play XA Audio Buffer         |
+-----------------------------------+        +--------------------------------------+
                  |
                  v (DMA Channel 0: RAM -> MDEC)
+-----------------------------------------------------------------------------------+
|                             MDEC HARDWARE (0x1F801820)                            |
| Cmd 1: Decode Macroblocks (0x10000000 | params)                                   |
| Async Step: Decode 1 Slice (16-20 Macroblocks) -> 15bpp/24bpp RGB                 |
+-----------------------------------------------------------------------------------+
                  |
                  v (DMA Channel 1: MDEC -> RAM / MDEC IRQ Bit 5)
+-----------------------------------------------------------------------------------+
|                       MovieDecodeSliceCallback (0x800768D8)                        |
| Increment slice counter -> On frame complete: Swap double-buffers & GPU LoadImage  |
+-----------------------------------------------------------------------------------+
```

### 2.1 STR Sector Header Specification
Each Mode 2 Form 2 video sector contains a 32-byte header preceding 2016 bytes of compressed MDEC bitstream:

| Offset | Size | Field Name | Description & Value |
| :--- | :--- | :--- | :--- |
| `+0x00` | 2 Bytes | `magic` | Demux chunk type marker (`0x0160` or `0x0001`) |
| `+0x02` | 2 Bytes | `chunkType` | Stream chunk identifier (`0x8001`) |
| `+0x04` | 2 Bytes | `sectorNumber` | 0-based sector/slice index within current frame |
| `+0x06` | 2 Bytes | `numSectors` | Total sector chunks required for current frame (e.g. 15 or 20) |
| `+0x08` | 4 Bytes | `frameNumber` | Sequential frame index |
| `+0x0C` | 2 Bytes | `width` | Frame width in pixels (e.g. 320 or 256) |
| `+0x0E` | 2 Bytes | `height` | Frame height in pixels (e.g. 240 or 224) |
| `+0x10` | 2 Bytes | `macroblockCount` | Total macroblocks in frame (e.g. 300 for 320x240) |
| `+0x12` | 2 Bytes | `quantScale` | Frame quantization scale factor |
| `+0x14` | 2 Bytes | `version` | Stream format version |
| `+0x16` | 10 Bytes | `reserved` | Padding zeroes |
| `+0x20` | 2016 Bytes | `bitstream_data` | Compressed MDEC Huffman/RLE macroblock payload |

### 2.2 Sector-to-Slice Mapping & Frame Geometry
* **Macroblock Size:** $16 \times 16$ pixels (4 $Y$ $8\times 8$ blocks, 1 $C_r$ $8\times 8$ block, 1 $C_b$ $8\times 8$ block — 4:2:0 YCbCr sampling).
* **320x240 Resolution Frame:** 20 macroblocks wide $\times$ 15 macroblocks tall = **300 total macroblocks**.
* **Sector/Slice Correspondence:** 1 CD sector payload (2016 bytes) stores 1 slice of **20 macroblocks** (1 full horizontal row of $16\times 16$ macroblocks). Thus, a 320x240 frame consists of **15 sectors / 15 slices**.
* **256x224 Resolution Frame:** 16 macroblocks wide $\times$ 14 macroblocks tall = **256 total macroblocks** (16 sectors / 16 slices).

---

## 3. Audit of `hle_mdec.c` & List of Current Gaps

### 3.1 Implemented Capabilities in Current `hle_mdec.c`
* **Registers:** `0x1F801820` (Data/Command FIFO) and `0x1F801824` (Status/Control).
* **Commands:** Command 0 (NOP/Reset), Command 1 (Decode Macroblocks), Command 2 (Set Quant Tables), Command 3 (Set Scale Table).
* **Pipeline:** RLE Huffman decoding, inverse quantization using IQ matrices (`iq_y`, `iq_uv`), zigzag reordering (`ZIGZAG`/`ZAGZIG`), 8x8 integer IDCT, YCbCr $\rightarrow$ RGB color space conversion.
* **Depths:** 15bpp RGB (depth 3, bit 15 STP set) and 24bpp RGB (depth 2).
* **DMA Functions:** `hle_mdec_dma0_in` (RAM $\rightarrow$ MDEC) and `hle_mdec_dma1_out` (MDEC $\rightarrow$ RAM).

### 3.2 Exact List of Missing Capabilities for Asynchronous STR Playback
1. **Monolithic Blocking Execution:** `mdec_process_decode()` processes the entire input buffer in a single synchronous loop inside `hle_mdec_dma0_in()`. Real hardware decodes macroblocks incrementally and yields between slice boundaries.
2. **Lack of Slice Boundary & Progress Tracking:** `hle_mdec.c` has no concept of slice boundaries (e.g. 20 macroblocks per slice). It cannot pause execution at slice boundaries or maintain slice progress counters.
3. **No MDEC IRQ / Interrupt Signaling:** Bit 5 of `I_STAT` (`0x1F801070`) and DMA IRQ (bit 3 of `I_STAT`) are never signaled. `hle_mdec.c` has no hook to trigger kernel interrupt event dispatching.
4. **No STR Sector Demuxing / Header Stripping Support:** `hle_mdec.c` expects raw pre-demuxed MDEC RLE words. It cannot accept Mode 2 Form 2 CD sector payloads containing 32-byte STR headers.
5. **No Double-Buffer / GPU Blit Coordination:** `hle_mdec_dma1_out` copies into a single static RAM buffer without supporting double-buffered slice output management or GPU LoadImage (`0xA0000000`) / DMA2 triggers.
6. **Inaccurate Status Register Dynamics:** Status register flags (`busy` bit 29, `data_in_enable` bit 28, `data_out_enable` bit 27, FIFO empty bit 31, FIFO full bit 30) flip instantly during synchronous calls rather than reflecting dynamic hardware states across slice DMA cycles.

---

## 4. MDEC Register Semantics & System Interconnect

### 4.1 Register Bit Specifications

#### `0x1F801820` — MDEC Command / Data FIFO
* **Write:** When no command is active, low 16 bits = parameter word count, high 16 bits = command code (`0x10000000` = Cmd 1 Decode, `0x20000000` = Cmd 2 Set Quant, `0x30000000` = Cmd 3 Set Scale). Subsequent writes push 16-bit bitstream/parameter halfwords into `in_buf`.
* **Read:** Pops 32-bit decoded RGB pixel words from `out_fifo`.

#### `0x1F801824` — MDEC Status / Control Register
* **Read (Status Register):**
  * Bit 31: Data-Out FIFO Empty (`1` = Empty, `0` = Data Available)
  * Bit 30: Data-In FIFO Full (`1` = Full, `0` = Space Available)
  * Bit 29: Command Busy (`1` = Decoding / Active, `0` = Idle)
  * Bit 28: Data-In Request / DMA0 Enable (`1` = Ready for DMA0)
  * Bit 27: Data-Out Request / DMA1 Enable (`1` = Ready for DMA1)
  * Bits 26-25: Data Output Depth (`00` = 4b, `01` = 8b, `10` = 24b, `11` = 15b)
  * Bit 24: Signed Output Flag (`0` = Unsigned, `1` = Signed)
  * Bit 23: Bit 15 Set Flag (`1` = Set STP bit 15 in 15bpp RGB)
  * Bits 18-16: Current Macroblock Component (`0..3` = Y1..Y4, `4` = Cr, `5` = Cb)
  * Bits 15-0: Remaining 16-bit Parameter Words Minus 1
* **Write (Control Register):**
  * Bit 31: Reset MDEC Hardware State
  * Bit 30: Enable Data-In Request (DMA Channel 0)
  * Bit 29: Enable Data-Out Request (DMA Channel 1)

### 4.2 PS1 Interrupt Controller Integration (`I_STAT` & `I_MASK`)
* **`I_STAT` (`0x1F801070`) Interrupt Status Bits:**
  * Bit 0 (`0x0001`): VBlank IRQ
  * Bit 1 (`0x0002`): GPU IRQ
  * Bit 2 (`0x0004`): CD-ROM IRQ (INT1/2/3/5)
  * Bit 3 (`0x0008`): DMA IRQ (Channels 0–6 complete)
  * Bit 4 (`0x0010`): Timer 0/1/2 IRQ
  * **Bit 5 (`0x0020`): MDEC IRQ (Decode Complete / Slice Done)**
  * Bit 9 (`0x0200`): SPU IRQ

---

## 5. Asynchronous Upgrade Design Specification

### 5.1 Proposed Header Extensions (`hle_mdec.h`)

```c
/* Callback function prototype for slice completion */
typedef void (*hle_mdec_slice_cb_t)(uint32_t slice_idx, uint32_t total_slices, void *userdata);

/* Async Configuration & Control API */
void hle_mdec_set_slice_callback(hle_mdec_slice_cb_t cb, void *userdata);
void hle_mdec_set_slice_macroblocks(uint32_t mb_per_slice);

/* STR Sector Helper API */
bool hle_mdec_push_str_sector(const uint8_t *sector_raw_2336);

/* Asynchronous Stepping API */
uint32_t hle_mdec_step_async(uint32_t max_macroblocks);
bool hle_mdec_has_pending_slices(void);

/* Kernel IRQ Signal Query */
bool hle_mdec_check_and_clear_irq(void);
```

### 5.2 Extended Internal State Structure (`MdecState`)

```c
typedef struct {
    uint8_t *ram;               /* Pointer to 2MB main RAM */

    /* Command & Control State */
    uint32_t current_cmd;       /* Active command (0, 1, 2, 3) */
    uint32_t output_depth;      /* Output depth (0=4b, 1=8b, 2=24b, 3=15b) */
    bool output_signed;         /* Bit 24 */
    bool output_bit15;          /* Bit 23 */
    uint32_t remaining_words;   /* Parameter words remaining */

    bool data_in_enable;        /* Control bit 30 */
    bool data_out_enable;       /* Control bit 29 */
    bool busy;                  /* Status bit 29 */
    uint32_t current_block;     /* Status bits 18-16 */

    /* Quantization & Scale Tables */
    uint8_t iq_y[64];
    uint8_t iq_uv[64];
    int16_t scale_table[64];

    /* Input Stream FIFO */
    uint16_t in_buf[65536];
    size_t in_count;
    size_t in_read_pos;

    /* Output Word FIFO */
    uint32_t out_fifo[8192];
    size_t out_count;
    size_t out_read_pos;

    /* NEW ASYNC SLICE FIELDS */
    uint32_t mb_per_slice;          /* Macroblocks per slice (default: 20 or 16) */
    uint32_t current_slice_mbs;      /* Macroblocks decoded in active slice */
    uint32_t slice_index;           /* Active slice index */
    uint32_t total_frame_slices;    /* Total expected slices for frame */
    
    hle_mdec_slice_cb_t slice_cb;   /* Registered MovieDecodeSliceCallback */
    void *slice_cb_userdata;        /* Callback context pointer */

    bool irq_pending;               /* MDEC INT bit 5 pending flag */
    uint32_t active_frame_w;        /* STR frame width */
    uint32_t active_frame_h;        /* STR frame height */
} MdecState;
```

### 5.3 Asynchronous Execution & Callback Pipeline

1. **Bitstream Feed via DMA Channel 0 (`hle_mdec_dma0_in`)**:
   * Copies input RLE halfwords from RAM into `in_buf`.
   * Sets `busy = true`.
   * Updates status register bit 28 (`DMA0 In Req`).
   * Does **not** perform synchronous macroblock decoding; queues data for async stepping.

2. **Async Stepping (`hle_mdec_step_async`)**:
   * Decodes up to `max_macroblocks` per invocation (or until `mb_per_slice` is reached).
   * For each macroblock:
     * Executes `rl_decode_block` for Cr, Cb, Y1, Y2, Y3, Y4.
     * Computes IDCT and YCbCr $\rightarrow$ RGB conversion.
     * Pushes decoded RGB words into `out_fifo`.
     * Increments `current_slice_mbs`.
   * **Slice Completion Event:**
     * When `current_slice_mbs == mb_per_slice` or input bitstream pauses:
       * Sets `irq_pending = true` (raising MDEC IRQ bit 5 in `I_STAT`).
       * Sets status bit 27 (`DMA1 Out Req = true`).
       * Triggers DMA Channel 1 transfer (`hle_mdec_dma1_out`) to drain `out_fifo` to RAM/VRAM.
       * Invokes `slice_cb(slice_index, total_frame_slices, slice_cb_userdata)`.
       * Increments `slice_index`, resets `current_slice_mbs = 0`.
     * When all slices for frame complete:
       * Sets `busy = false`.

3. **Kernel Event Layer Integration (`runtime.c`)**:
   * Define `g_mdec_irq_force` in `runtime.c` (mirroring `g_cd_irq_force`).
   * In `runtime.c` MMIO write to `0x1F801070` (`I_STAT` ACK): writing bit 5 clears MDEC IRQ state.
   * In `runtime.c` wait/polling tick:
     ```c
     if (hle_mdec_check_and_clear_irq() || g_mdec_irq_force) {
         g_mdec_irq_force = 0;
         /* Set Bit 5 in hardware I_STAT */
         xenolift_i_stat |= (1u << 5);
         /* Dispatch kernel interrupt event chain at 0x80059410 */
         dispatch_kernel_events(5);
     }
     ```

---

## 6. Implementation Test Plan

### 6.1 Test 1: Single-Slice Asynchronous Step Test
* **Objective:** Verify that `hle_mdec_step_async` decodes exactly 1 slice of macroblocks, updates status flags, sets `irq_pending`, and invokes the registered slice callback.
* **Input:** Synthetic 1-slice MDEC bitstream (20 macroblocks, 2016 bytes).
* **Procedure:**
  1. Call `hle_mdec_reset()`.
  2. Register mock callback `test_slice_cb`.
  3. Send Command 1 (`0x10000000`).
  4. Feed bitstream via `hle_mdec_dma0_in`.
  5. Assert `hle_mdec_is_busy() == true`.
  6. Call `hle_mdec_step_async(20)`.
  7. Assert mock callback invoked with `slice_idx == 0`.
  8. Assert `hle_mdec_check_and_clear_irq() == true`.

### 6.2 Test 2: Multi-Slice Frame Reassembly & Golden Compare
* **Objective:** Verify multi-slice decoding for a full 320x240 frame (15 slices, 300 macroblocks) and compare output against synchronous golden RGB buffer.
* **Input:** Sample 320x240 MDEC frame bitstream.
* **Procedure:**
  1. Decode frame with synchronous `hle_mdec_dma0_in` $\rightarrow$ record `golden_rgb_15bpp`.
  2. Reset MDEC, set `mb_per_slice = 20`.
  3. Feed frame in 15 sequential DMA0 slice pushes.
  4. Step async player 15 times, verifying callback count == 15.
  5. Assert assembled async RGB output matches `golden_rgb_15bpp` byte-for-byte.

### 6.3 Test 3: Interrupt Event Pipeline (`I_STAT` Bit 5) Integration
* **Objective:** Verify that MDEC slice completion sets bit 5 in `I_STAT` and triggers kernel event handler dispatch.
* **Procedure:**
  1. Configure `runtime.c` harness mock with `xenolift_i_stat = 0`.
  2. Feed 1 MDEC slice and step async.
  3. Verify `xenolift_i_stat & (1u << 5)` becomes non-zero.
  4. Simulate kernel write `xenolift_i_stat &= ~(1u << 5)` and verify ACK clears IRQ flag.

### 6.4 Test 4: Diagnostic Movie Path Harness Test
* **Objective:** Run diagnostic test using `MovieLaunchDebugMovie` (`0x8007625C`) / `MovieRunCdSectorMonitor` (`0x80075534`).
* **Procedure:**
  1. Instantiate diagnostic movie harness.
  2. Stream test movie sectors into MDEC async player.
  3. Assert zero frame drops, correct double-buffer flipping, and 15 FPS pacing adherence.
