# TRAILBLAZER FINDINGS: FIRST-FIELD-RENDER VERIFICATION CHECKLIST & PRE-SHIP PROBE DESIGNS
**Role:** Field-World & Initialization Specialist (TRAILBLAZER)  
**Target Milestone:** First Field Render upon Mount Acceptance (Module 2 / File 14 / `0x0E`)  
**Deliverable Level:** L3 — Recommended Verification Plan & Watch-Probe Designs  
**Target File Path:** `xenolift/hle/agents/trailblazer-findings.md`

---

## 1. EXECUTIVE SUMMARY & CONTEXT

The Xenolift static recompiler is on the threshold of entering the **Field Phase** (State 1).
* **RAM State:** Module 2 (Field, File 14 / `0x0E`) is loaded at landing base `0x801D9724` (135KB compressed, 125,304 bytes, stage-2 decompressed at `0x801D3000`).
* **Kernel Menu:** Native kernel menu rendered, virtual player selection submitted for Field.
* **Pending Gate:** Mount acceptance pending file-completion signal.
* **Expected Transition:** Upon mount acceptance, `fn_80019ACC` (RunResidentGameLoop) checks phase index cell `0x8006FAEC` (`idx = 1`) and game mode cell `0x800592C0` (`cur = 1`), invoking phase callback `table[1] = 0x80077E88` (`RunFieldCoordinator`).

This document provides:
1. **The Single-Cycle First-Field-Render Checklist:** A 10-item numbered verification protocol with concrete pass/fail thresholds for the manager to verdict in ONE bridge cycle.
2. **Field Era Danger Zones & Safeguards:** Analysis of operational risks (era-gated probe blindness, log budget exhaustion, MMIO guest dispatch traps, DMA direct memcpy bypass, MIPS sign-extension pitfalls, and crash-kit requirements) derived from `LESSONS.md` and `ORACLE_PSX_CD.md`.
3. **Pre-Shipped Watch-Probe Designs:** Four ready-to-ship runtime diagnostic probes (cell + digest section + era budget) to ensure the field era is observed with full visibility.

---

## 2. FIRST-FIELD-RENDER CHECKLIST (SINGLE-CYCLE VERDICT PLAN)

When the mount accepts, the manager can evaluate these 10 numbered items in order during a single digest inspection:

| # | Milestone & Target | Watch Location / Receipt | Expected Value / Behavior | What It Proves | Verdict Criteria |
|---|---|---|---|---|---|
| **1** | **Phase Callback Dispatch** | Digest `=PHASE=` / `=FLDCB=`<br>RAM `0x8006FAEC`<br>RAM `0x800592C0` | `0x8006FAEC == 1`<br>`0x800592C0 == 1`<br>`[fldcb]` logs entry to `0x80077E88` | Game loop (`fn_80019ACC`) exited Title/Menu and dispatched Field Coordinator `table[1]`. | **PASS:** `[fldcb]` entry logged, `idx=1`.<br>**FAIL:** `idx!=1` or stuck in `0x8001A344`. |
| **2** | **LZSS Payload Decompress** | Function `0x8007008C`<br>(`DecompressFieldPayload`) | Decompresses 125,304 bytes from `0x801D9724` to `0x801D3000` | Stage-2 LZSS scene archive unpacked into operational field buffer. | **PASS:** `[fldinit] LZSS complete, dst=801D3000`.<br>**FAIL:** Decompress returns error or hangs. |
| **3** | **9-Section Scene Unpack** | Function `0x80070CC8`<br>(`InstallFieldScene`) | Parses header, VM scripts, dialogue, 3D meshes, collision, camera bounds, TIMs, SEDS/WDS, actor formations | Map section tables and scene views populated in RAM without pointer overflow. | **PASS:** `[fldinit] Scene installed, 9 sections parsed`.<br>**FAIL:** Null header or bad offset crash. |
| **4** | **Heap Allocation & Party Skins** | Function `0x80077C88`<br>Tracking cell `0x80077D2C` | Pins 3 x `0x14000` byte (`245.7KB` total) RAM buffers for party character skin datasets | Heap manager (`fn_80031BDC`) has sufficient unfragmented RAM for field actors. | **PASS:** 3 skin buffers allocated (`!= NULL`).<br>**FAIL:** Heap allocation returns NULL. |
| **5** | **VRAM Image & CLUT Uploads** | Functions `0x80070488` / `0x80070F4C`<br>GP0 `0xA0` (`DataToVRAM`) | Blits field TIM textures and CLUT palettes to assigned VRAM pages | VRAM populated with map/actor textures; CLUTs ready for GPU primitive assembly. | **PASS:** GP0 `0xA0` command count > 0.<br>**FAIL:** Zero GP0 texture blits. |
| **6** | **Actor & Camera Reset** | Functions `0x80080A74` / `0x8007254C` | Resets actor slots, sets initial character transform, seeds default camera eye/target pose | Initial field spawn point and camera transformation matrices established. | **PASS:** Camera target entity bound & matrices non-zero.<br>**FAIL:** Camera target NULL or NaN transform. |
| **7** | **Map Entry Script Execution** | Function `0x800A22AC`<br>(`FieldRunEntryActorScript`) | Executes entry script mode (0/1/2/3) via primary VM `0x800A1EC8` | Environment flags, scene triggers, and initial lighting bytecode initialized. | **PASS:** Script PC advances without trap opcode.<br>**FAIL:** Script scheduler hits illegal opcode. |
| **8** | **BGM & SPU Sound Bank Load** | Functions `0x8008F7B8` / `0x800854D0` | Transfers SEDS/WDS audio samples to SPU RAM and arms BGM stream chunk reader | SPU voice allocation and background music sequence engine operational. | **PASS:** SPU RAM upload logged, stream active.<br>**FAIL:** SPU audio DMA timeout or lockup. |
| **9** | **Entry Fade-In Unmask** | Function `0x80071CB4`<br>(`AdvanceAndRenderFade`) | Color delta steps from 0x00 (black) to 0x80 (full brightness presentation) | Visual display unmasked, exposing active 3D map geometry and sprites. | **PASS:** Fade counter reaches target brightness 0x80.<br>**FAIL:** Fade counter stays at 0 (black screen). |
| **10** | **Steady-State Frame Loop & GPU Proof** | Functions `0x80077DAC` / `0x8007554C`<br>Digest `=GPU=` & image outputs | `prims-log-lines > 0`<br>`vram.png` > 5KB (non-uniform)<br>`screen.png` > 2.5KB | GPU active, double-buffering exchanging frames, 3D map & sprites rendering. | **PASS:** `prims > 0`, `screen.png` size > 2500 bytes.<br>**FAIL:** `prims == 0` or `screen.png` < 500 bytes (black). |

---

## 3. KNOWN FIELD ERA DANGER ZONES & SAFEGUARDS

Analysis of lessons learned (`LESSONS.md`) and PSX CD specifications (`ORACLE_PSX_CD.md`) reveals six primary failure modes for the field era transition:

### Danger Zone 1: Era-Gated Probes Going Blind (Lesson L4)
* **Risk:** Probes gated on `g_movie_live` or fixed boolean flags fail to fire when transitioning to Field mode (`g_movie_live` stays set or doesn't track state change).
* **Safeguard:** Gate probes on **State Signatures** and explicit cell reads (e.g. `xenolift_mem_read32(0x8006FAECu) == 1u`), never on stale era booleans.

### Danger Zone 2: Probe Budget Exhaustion Mid-Era (Lessons L1, L15, L20, L36)
* **Risk:** A probe logging on every frame or per-access exhausts its line budget (e.g. 24 lines) during early boot or title loop, going completely blind before the field phase begins. Uncapped loggers also trigger log storms (20MB+) that kill the watchdog or stall the digest greps (Lesson L19).
* **Safeguard:**
  1. Every probe MUST use a **Hard Lifetime Cap** + **Sparse Stride** (e.g., initial 24 prints, then 1 print every 1000 frames).
  2. Each probe gets its own **Dedicated Head/Tail-Kept Digest Section** in `run.sh` to prevent later-era log spam from evicting early-era evidence (Lesson L24).

### Danger Zone 3: MMIO Guest Dispatch Traps & Oracle FIFO Deadlocks (Lessons L2, L3, L16)
* **Risk:**
  1. Dispatching guest code (`xenolift_dispatch`) directly from MMIO read/write handlers causes re-entrant deadlock loops (Lesson L2).
  2. CD-ROM completion handlers that wait indefinitely for the response FIFO to empty lock up when the guest leaves responses unconsumed (Oracle Trap #1).
* **Safeguard:**
  1. Retirement/mount assists perform **Cell-Writes Only** (`FE1C = 1`, counters++), allowing the safe `fd-tick` collector to handle delivery.
  2. Pend CD INT2 events using **Absolute Deadlines** rather than response-FIFO empty gates.

### Danger Zone 4: Memory Stomps & Direct DMA Memcpy Bypass (Lessons L37, L40)
* **Risk:**
  1. Direct `memcpy` calls in CD DMA handlers bypass CPU memory hooks (`xenolift_mem_write32`), making CPU store watchers completely blind to DMA memory corruption (Lesson L37).
  2. Multi-sector CD fills can overshoot staging boundaries into adjacent heap descriptors.
* **Safeguard:** Implement a DMA-Intersection Guard at `cd_read` / staging `memcpy` that checks destination bounds against critical field structure boundaries.

### Danger Zone 5: MIPS Immediate Sign-Extension Address Pitfalls (Lesson L34)
* **Risk:**
  1. In MIPS assembly, offsets `>= 0x8000` sign-extend negative. For example, `SW r16, 0x9394(r1)` with `r1 = 0x80060000` computes address `0x80059394`, NOT `0x80069394`.
  2. Misfired address watchers cost cycles looking at "phantom" addresses.
* **Safeguard:** Compute all cell watch addresses with explicit signed 16-bit extension (`(int32_t)(int16_t)offset`) before wiring probes.

### Danger Zone 6: Self-Guarded Crash-Kit Requirements (Lessons L18, L38)
* **Risk:** If the field engine faults or wedges during initialization, a crash printer inside a signal handler can deadlock the process, producing an empty digest with zero evidence.
* **Safeguard:**
  1. Ship a **Self-Guarded Crash Kit** with a stage-counter latch (`g_in_park`) and 8-second backstop alarm (`_exit(77)`).
  2. Print `host_pc`, fault address, MIPS registers `r2` through `r31`, caller `r31`, and kernel BSS state (`FE1C`, `FDF8`, `FE04`, `8006FAEC`).

---

## 4. PRE-SHIPPED WATCH-PROBE DESIGNS (READY FOR RUNTIME.C & RUN.SH)

To ensure full observability the exact instant the mount accepts, the following four probes are designed to be pre-shipped.

### Probe 1: `=FLDCB=` Phase Callback & Transition Monitor
* **Watched Cells:** `0x8006FAEC` (Phase Index), `0x800592C0` (Committed Game State), Function `0x80077E88` (`RunFieldCoordinator`).
* **Runtime Code Snippet (`runtime.c`):**
```c
/* Probe 1: FLDCB - Field Phase Entry & Dispatch Tracker */
if (a == 0x80077E88u) {
    static uint32_t fldcb_count = 0;
    uint32_t idx  = xenolift_mem_read32(0x8006FAECu);
    uint32_t mode = xenolift_mem_read32(0x800592C0u);
    uint32_t land = xenolift_mem_read32(0x801D9724u);
    if (fldcb_count < 30u || (fldcb_count % 1000u) == 0u) {
        fprintf(stderr, "[fldcb] #%u FIELD-PHASE entry a0=%08X a1=%08X idx=%u mode=%u land=%08X caller=%08X\n",
                fldcb_count, r[4], r[5], idx, mode, land, r[31]);
    }
    fldcb_count++;
}
```
* **Digest Section (`run.sh`):**
```bash
echo "=FLDCB="
grep "\[fldcb\]" run.log | head -n 35
```
* **Era Budget:** 30 initial prints + 1 per 1000 frames (Hard Cap: max 100 lines per run).

---

### Probe 2: `=FLDINIT=` Scene Unpack & Resource Allocation Monitor
* **Watched Targets:** `0x8007008C` (Decompress), `0x80070CC8` (Install Scene), `0x80077C88` (Skin Alloc), `0x80070488` (VRAM Upload).
* **Runtime Code Snippet (`runtime.c`):**
```c
/* Probe 2: FLDINIT - Field One-Time Scene & Resource Init */
if (a == 0x8007008Cu || a == 0x80070CC8u || a == 0x80077C88u || a == 0x80070488u) {
    static uint32_t fldinit_count = 0;
    if (fldinit_count < 40u) {
        const char *fn_name = (a == 0x8007008Cu) ? "DecompressPayload" :
                              (a == 0x80070CC8u) ? "InstallFieldScene" :
                              (a == 0x80077C88u) ? "AllocateSkinBuffers" : "BeginGraphicsUpload";
        fprintf(stderr, "[fldinit] #%u %s target=%08X a0=%08X a1=%08X a2=%08X caller=%08X\n",
                fldinit_count, fn_name, a, r[4], r[5], r[6], r[31]);
        fldinit_count++;
    }
}
```
* **Digest Section (`run.sh`):**
```bash
echo "=FLDINIT="
grep "\[fldinit\]" run.log | head -n 40
```
* **Era Budget:** 40 lines total (One-shot scene initialization window).

---

### Probe 3: `=FLDGPU=` Field Geometry & Visual Render Activity
* **Watched Metrics:** GP0 primitive counts (FT4 textured quads, 3D polygon meshes), VRAM entropy, screen capture size.
* **Runtime Code Snippet (`runtime.c`):**
```c
/* Probe 3: FLDGPU - Field Rendering & Frame Output Monitor */
if (a == 0x8007554Cu) { /* FieldPresentationPassA */
    static uint32_t fldgpu_count = 0;
    if (fldgpu_count < 25u || (fldgpu_count % 300u) == 0u) {
        fprintf(stderr, "[fldgpu] #%u FieldPresentationPassA frame=%u disp_y=%u prims=%u defers=%u\n",
                fldgpu_count, fldgpu_count, gpu_disp_y, gpu_prims_count, gpu_defers_count);
    }
    fldgpu_count++;
}
```
* **Digest Section (`run.sh`):**
```bash
echo "=FLDGPU="
grep "\[fldgpu\]" run.log | head -n 30
echo "=GPU="
grep "\[gpu\]" run.log | tail -n 20
```
* **Era Budget:** 25 initial prints + 1 per 300 frames (Hard Cap: max 50 lines per run).

---

### Probe 4: `=FLDSCRIPT=` Field VM Interpreter & Yield Heartbeat
* **Watched Targets:** `0x800A2030` (`FieldRunActorScriptScheduler`), `0x800A1EC8` (`DispatchPrimaryFieldVm`), `0x8009DD34` (`YieldScriptVmTimer`).
* **Runtime Code Snippet (`runtime.c`):**
```c
/* Probe 4: FLDSCRIPT - VM Interpreter & Actor Script Scheduler */
if (a == 0x800A2030u) {
    static uint32_t fldvm_count = 0;
    if (fldvm_count < 20u || (fldvm_count % 500u) == 0u) {
        fprintf(stderr, "[fldscript] #%u ActorScriptScheduler tick, active_actors=%u caller=%08X\n",
                fldvm_count, xenolift_mem_read32(0x80079200u), r[31]);
    }
    fldvm_count++;
}
```
* **Digest Section (`run.sh`):**
```bash
echo "=FLDSCRIPT="
grep "\[fldscript\]" run.log | head -n 25
```
* **Era Budget:** 20 initial prints + 1 per 500 frames.

---

## 5. MANAGER VERDICT PROTOCOL (SINGLE-CYCLE ACTION)

When the mount accepts and the test run completes, inspect the digest output and execute the following decision flow:

```
                  +-----------------------------------+
                  | Mount Accepts & Field Run Completes |
                  +-----------------------------------+
                                    |
                                    v
                  +-----------------------------------+
                  | Check =FLDCB= Phase Entry Receipt |
                  +-----------------------------------+
                                    |
                    +---------------+---------------+
                    |                               |
              [ [fldcb] Logged ]              [ No [fldcb] ]
                    |                               |
                    v                               v
    +-------------------------------+   +-----------------------+
    | Check =FLDGPU= & Screen Dump  |   | FAIL: Phase Dispatch  |
    +-------------------------------+   | Stuck or Mount Rejected|
                    |                   +-----------------------+
        +-----------+-----------+
        |                       |
  [ Prims > 0 & ]         [ Prims == 0 or ]
  [ screen.png  ]         [ screen.png    ]
  [  > 2500 B   ]         [   < 500 B     ]
        |                       |
        v                       v
+---------------+       +-----------------------+
| VERDICT: PASS |       | PARTIAL / FAIL:       |
| Field Render  |       | Black Screen / Render |
| Proven!       |       | Pipeline Stalled      |
+---------------+       +-----------------------+
```

### Final Verdict Definitions:
* **FULL PASS:** `=FLDCB=` shows `idx=1` entry into `0x80077E88`, `=FLDINIT=` completes scene unpack, `=FLDGPU=` records primitives > 0, `screen.png` size > 2500 bytes, `vram.png` size > 5000 bytes.
* **PARTIAL PASS:** Phase callback `0x80077E88` entered and VM scripts running (`=FLDSCRIPT=` active), but visual presentation is black (`screen.png` < 500 bytes or zero primitives).
* **FAIL:** Phase index `0x8006FAEC` stays 0 or SystemError spike (`fn_80019ACC(0x83)`) fires.

---
**Report submitted by TRAILBLAZER.**  
*Ready to deploy pre-shipped probes into `runtime.c` and `run.sh` upon approval.*
