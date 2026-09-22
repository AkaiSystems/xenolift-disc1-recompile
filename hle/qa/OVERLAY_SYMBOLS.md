# xenolift Overlay Symbol Mapping & Boot Module Analysis
**Document Version:** 1.0 (2026-09-11)  
**Target:** Xenogears USA Disc-1 Boot Overlay Capture Window (`0x8006F000–0x8008FFFF`, 135KB)  
**Primary Reference Repo:** `github.com/OpokXeno/xenogears-recomp` (`annotations/overlays/`)

---

## 1. Executive Summary & Module Identity

### Identified Boot Overlay Module: **Module 6 — MOVIE Overlay (`movie-overlay`)**

* **Module Name:** Movie / STR Playback & Diagnostic Subsystem (`movie.bin`)
* **Disc Archive Location:** Disc Directory `0x01`, File `18` (`0x12`), LBA `109158`
* **Size Metrics:** Stored compressed size = `14,360` bytes (LZSS), Uncompressed loaded size = `29,779` bytes (`0x7453` bytes)
* **Load Address:** `0x8006FAF0` (RAM window `0x8006FAF0–0x80076F43`)
* **Module Entry Point VA:** `0x800737EC` (`MovieModuleEntry`)

### Identification Evidence:
1. **Entry Point Exact Match:** The kernel boot handler (`0x80019BFC / 0x80019C04`) loads archive file 18 into `0x8006FAF0` and `jalr`s directly into `0x800737EC`. In `annotations/overlays/movie/movie-overlay_annotations.csv`, `0x800737EC` is explicitly annotated as `MovieModuleEntry` ("runs scripted playback or the fourteen-item debug menu").
2. **Disc Directory Inventory Alignment:** Xenogears Disc 1 overlay manifest (`disc1-overlay-inventory.md` & `disc1-images.toml`) maps Disc Directory `0x01` files `13–18` to overlay modules `1–6`:
   * File 13 (`0x0D`): `Battling` (Module 1, loads at `0x8006FAF0`)
   * File 14 (`0x0E`): `Field` (Module 2, loads at `0x8006FAF0`)
   * File 15 (`0x0F`): `WorldMap` (Module 3, loads at `0x8006FAF0`)
   * File 16 (`0x10`): `Battle` (Module 4, loads at `0x8006FAF0`)
   * File 17 (`0x11`): `Menu` (Module 5, loads at `0x801C5000`)
   * File 18 (`0x12`): `Movie` (Module 6, loads at `0x8006FAF0`)
3. **Sector & Binary Fingerprint Match:** Our runtime execution logs (`R132` / `R142`) record archive file 18 reading sector `109158` with stored payload `14,360` bytes, matching `movie-image` in `disc1-images.toml` byte-for-byte.

---

## 2. Key Known Addresses & Symbol Cross-Reference

Our HLE runtime watches five specific addresses (`0x800737EC`, `0x80077E88`, `0x80070CFC`, `0x80088E90`, `0x80077C5C`). Below is the symbol identification for each address across Module 6 (Movie) and resident overlay modes:

| Virtual Address | Address Type / Role | Symbol Name (Module 6 / Resident Module) | Description & Functional Context |
| :--- | :--- | :--- | :--- |
| **`0x800737EC`** | **Module 6 Entry Point** | `MovieModuleEntry` *(Movie Overlay)* | **Module 6 Entry Point.** Executes initial boot sequence; branches to scripted movie playback or the 14-item debug menu. *(Cross-ref: `WorldMapRenderSky` in WorldMap overlay)*. |
| **`0x80077E88`** | **Phase Callback 1** | `RunFieldCoordinator` *(Field Overlay)* | Top-level Field coordinator that manages map installation, connectivity, pause, transitions, and resident-module handoffs. *(Extends past Movie overlay end at `0x80076F43`)*. |
| **`0x80070CFC`** | **Phase Callback 2** | `FieldLoadContinueStageDefaults` *(Field)* / `WorldMapOverlayEntryPoint` *(World)* | Field loading continuation (stages init constants, resets state, copies header, loads assets/actors) OR World Map entry point. *(In Movie overlay, falls inside `MovieRunCdReadStressTestScreen` at `+0x814`)*. |
| **`0x80088E90`** | **Phase Callback 3** | `BattlingMain` *(Battling Overlay)* | Runs the authenticated state-4 render and timing loop for Arena/Battling mode. *(Extends past Movie overlay end)*. |
| **`0x80077C5C`** | **Launch State Cell** | Overlay Launch State Watcher *(Kernel/HLE)* | Parameter cell (`a0 = 0x80077C5C`) passed to `fn_80031C58` during overlay mode transitions. *(In Field overlay, inside `FieldMechaFinalizeResourceLoad` at `+0x1A8`)*. |

---

## 3. Full Symbol Map for Capture Window (`0x8006F000–0x8008FFFF`)

### 3.1 Module 6 — Movie Overlay (`movie-overlay`) Symbol Table (Complete 51 Annotations)

The capture window `0x8006F000–0x8008FFFF` fully encompasses Module 6 (`0x8006FAF0–0x80076F43`).

| Address | Symbol Type | Symbol Name & Description |
| :--- | :--- | :--- |
| `0x800704E8` | Function Start | `MovieRunCdReadStressTestScreen` — Runs the interactive CD read and verification monitor. |
| `0x80070DCC` | Function Start | `MovieUpdateCdReadStressTest` — Polls and advances CD stress operations. |
| `0x800712C4` | Function Start | `MovieAdvanceCdReadVerification` — Verifies asynchronous readback data and records mismatches. |
| `0x80071BA0` | Function Start | `MovieQueueRandomSectorRead` — Allocates and queues a random-sector test read. |
| `0x80071C34` | Function Start | `MovieStartCdReadTestOperation` — Starts a selected CD stress operation. |
| `0x80072428` | Function Start | `MovieAdvanceCdStressVSyncClock` — Increments CD stress VSync clock and converts 60 ticks to 1 second. |
| `0x80072480` | Function Start | `MovieRunDiscChangeTest` — Runs the interactive disc-change diagnostic. |
| `0x8007293C` | Function Start | `MovieReinitializeCdAfterDiscChange` — Resets CD state after media replacement. |
| `0x800729A8` | Function Start | `MovieReadHostFile` — Reads a development host file into memory. |
| `0x80072A08` | Function Start | `MovieAdvanceDiscChangeValidation` — Validates PlayStation and Xenogears disc identity. |
| `0x80072D84` | Function Start | `MovieInitDarkAnimatedQuads` — Initializes dark double-buffered menu quads. |
| `0x80072F98` | Function Start | `MovieUpdateDarkAnimatedQuad` — Interpolates and submits one dark menu quad. |
| `0x80073328` | Function Start | `MovieInitBrightAnimatedQuads` — Initializes bright double-buffered menu quads. |
| `0x800734B8` | Function Start | `MovieUpdateBrightAnimatedQuad` — Interpolates and submits one bright menu quad. |
| `0x800737EC` | **Function Start** | **`MovieModuleEntry` — Module 6 main entry point; runs scripted playback or 14-item debug menu.** |
| `0x80073B00` | Instruction Site | Selects scripted playback or the Movie debug menu. |
| `0x80073B84` | Call Site | Scripted Movie path invokes `MovieLaunchScriptedMovie`. |
| `0x80073BD0` | Call Site | Initializes dark animated Movie menu quads. |
| `0x80073BEC` | Call Site | Initializes bright animated Movie menu quads. |
| `0x80073F6C` | Call Site | Resolves a selected STR start frame to a sector offset. |
| `0x8007407C` | Call Site | Determines the selected STR's final frame number. |
| `0x80074230` | Instruction Site | Dispatches the fourteen-way Movie debug menu. |
| `0x80074678` | Call Site | Launches debug-menu movie playback. |
| `0x800746B0` | Call Site | Launches the raw-sector monitor. |
| `0x800746DC` | Call Site | Launches the CD read stress test. |
| `0x80074708` | Call Site | Launches the FAT browser. |
| `0x80074734` | Call Site | Launches the disc-change test. |
| `0x800747AC` | Function Start | `MoviePollMenuInput` — Handles debounced menu navigation and adjustment. |
| `0x80074AF0` | Function Start | `MovieRandom` — Advances the deterministic Movie PRNG. |
| `0x80074B58` | Function Start | `MovieClearFramebuffer` — Clears the full 640x480 VRAM rectangle. |
| `0x80074BA4` | Function Start | `MovieFindStrFrameSector` — Finds the sector containing a requested STR frame. |
| `0x8007519C` | Function Start | `MovieFindLastStrFrameNumber` — Reads the final valid STR frame number. |
| `0x800753B8` | Function Start | `MovieLoadSoundEffectBanks` — Loads `main_se.wd`, `bat_se.wd`, `gear_se.wd` from host storage & transfers WDS. |
| `0x8007548C` | Function Start | `MovieLoadBattleAudio` — Loads and transfers `battle2.wd`, then loads `battle2.smd`. |
| `0x80075508` | Function Start | `MoviePlayBattleMusic` — Starts the loaded battle music sequence at full volume. |
| `0x80075534` | Function Start | `MovieRunCdSectorMonitor` — Displays and navigates raw sector contents. |
| `0x80075D4C` | Function Start | `MovieGetFatEntrySize` — Decodes a filesystem entry size. |
| `0x80075D8C` | Function Start | `MovieRunFatBrowser` — Displays filesystem entries and paths. |
| `0x8007625C` | Function Start | `MovieLaunchDebugMovie` — Configures and launches debug-menu playback. |
| `0x800763BC` | Function Start | `MovieLaunchScriptedMovie` — Configures and launches scripted playback. |
| `0x80076488` | Function Start | `MovieRunPlayback` — Runs the core resident STR playback loop. |
| `0x80076588` | Call Site | Initializes the resident STR subsystem. |
| `0x800765F4` | Call Site | Configures resident STR display and decode parameters. |
| `0x80076668` | Instruction Site | Materializes `MovieDecodeSliceCallback` for the resident player. |
| `0x80076698` | Call Site | Starts resident STR playback with selected options. |
| `0x80076834` | Call Site | Shuts down the resident STR player. |
| `0x800768D8` | Function Start | `MovieDecodeSliceCallback` — Tracks decode progress and swaps frame state. |
| `0x800769A4` | Function Start | `MoviePollSkipInput` — Handles playback skip and audio fade countdown. |
| `0x80076AF0` | Function Start | `MovieInitGteViewState` — Configures projection, screen center, color state, and matrices for Movie view transform. |
| `0x80076C68` | Function Start | `MovieApplyGteViewTransform` — Rebuilds view matrix and installs it as current GTE rotation/translation matrix. |
| `0x80076CA4` | Function Start | `MovieBuildGteViewTransform` — Derives camera angles, distance, and translation from eye/target globals and builds look-at matrix. |

---

## 4. Module 6 Functionality & Behavioral Analysis

Based on the symbol manifest around `0x800737EC` and throughout `movie.bin`, **Module 6 is the game's initial Boot, STR Movie Playback, and Developer Diagnostic Overlay**.

### Core Responsibilities:
1. **Boot / Intro Movie Dispatcher (`0x800737EC MovieModuleEntry`):**
   * Upon kernel handover from `0x80019C04`, `MovieModuleEntry` evaluates launch flags. In production boots, it launches scripted FMV movie streams (`MovieLaunchScriptedMovie` `0x800763BC` -> `MovieRunPlayback` `0x80076488`), streaming the opening movie / Square logo STR files from disc.
2. **MDEC Video & GTE Render Pipeline:**
   * Uses MDEC slice callbacks (`MovieDecodeSliceCallback` `0x800768D8`) to demux and decode streaming STR video frames into dual VRAM framebuffers (`MovieClearFramebuffer` `0x80074B58`).
   * Configures GTE rotation/translation matrices (`MovieInitGteViewState` `0x80076AF0`, `MovieApplyGteViewTransform` `0x80076C68`) for 3D overlay graphics and menu quad interpolation (`MovieUpdateDarkAnimatedQuad`, `MovieUpdateBrightAnimatedQuad`).
3. **Integrated Developer Diagnostics & Stress Suite (14-Way Debug Menu `0x80074230`):**
   * **CD Read Stress Test (`0x800704E8`):** Performs continuous async CD sector reads, VSync timing (`0x80072428`), and data verification (`0x800712C4`) to test optical drive stability.
   * **Disc Change Diagnostic (`0x80072480`):** Validates disc swap logic and PlayStation disc authentication headers (`0x80072A08`).
   * **Raw Sector Monitor (`0x80075534`):** Displays low-level disc sectors directly on screen.
   * **Archive FAT Browser (`0x80075D8C`):** Navigates directory tables and decodes FAT record sizes (`0x80075D4C`).
4. **Audio Driver & Sound Bank Staging:**
   * Directly interfaces with the sound driver by loading WDS sound effect banks (`main_se.wd`, `bat_se.wd`, `gear_se.wd` via `MovieLoadSoundEffectBanks` `0x800753B8`) and battle music streams (`battle2.wd`/`battle2.smd` via `MovieLoadBattleAudio` `0x8007548C` and `MoviePlayBattleMusic` `0x80075508`).

---

## 5. Execution Stability Analysis: 3 High-Signal Nearby Symbols

For HLE harness testing, execution-stability analysis, and hardware fidelity validation, the three most critical nearby symbols in Module 6 are:

1. **`MovieLoadSoundEffectBanks` (`0x800753B8`) & `MovieLoadBattleAudio` (`0x8007548C`):**
   * **Relevance to Stability:** Loads WDS sound sample banks from storage and stages them into main RAM before issuing ch4 SPU DMA transfers.
   * **Harness Impact:** Validates our SPU DMA staging block logic (`0x80067210`, 2048B chunks) and verifies that SPU RAM write pointers and preset records align across module handoffs without corrupting kernel sound-heap cells.

2. **`MovieDecodeSliceCallback` (`0x800768D8`):**
   * **Relevance to Stability:** Intermittent callback invoked during active MDEC video decoding to manage frame-slice completion, VRAM double-buffering, and framebuffer swaps.
   * **Harness Impact:** Primary test site for GPU blit synchronization (GP0 `0xA0` DataToVRAM) and MDEC/CD-ROM DMA interleaving. Ensures system state doesn't freeze or drop VSync interrupts during heavy streaming.

3. **`MovieRunCdReadStressTestScreen` (`0x800704E8`) & `MovieAdvanceCdReadVerification` (`0x800712C4`):**
   * **Relevance to Stability:** Exercises rapid, asynchronous CD-ROM sector queuing (`0x80071BA0`), sector FIFO draining, and readback verification.
   * **Harness Impact:** Directly tests our CD state machine fixes (Pause `INT2` responses, slot-2 request stepping, fd-kick logic at `0x8004FE04`). If CD DMA or FIFO timing deviates, this module will trip read verification errors or hang in a poll loop.
