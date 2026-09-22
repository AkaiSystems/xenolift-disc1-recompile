# xenolift Menu Module Preparation & Capture Specification (MENU_PREP.md)

**Document Version:** 1.0 (2026-09-12)  
**Target Architecture:** MIPS R3000A / PS1 Static Recompiler (`xenolift`, SLUS-006.64 USA Disc 1)  
**Deliverable Path:** `xenolift/hle/MENU_PREP.md`  
**Primary References:** `xenolift/disc1.c`, `SLUS_006.64`, `xenolift/annotations.csv`, `xenolift/qa/OVERLAY_SYMBOLS.md`, `xenolift/hle/qa/MENU_WINDOW_SPEC.md`

---

## Executive Summary & Gap Analysis

In the `xenolift` static recompiler architecture, executable overlay modules on Disc 1 are dynamically loaded from disc archive files in Directory `0x01` upon game state transitions.

* **Primary Overlay Capture Window (`0x8006F000–0x8008FFFF`, 135 KB):** Covers Modules 1 (`Battling`), 2 (`Field`), 3 (`WorldMap`), and 6 (`Movie`) which load into RAM at `0x8006FAF0`.
* **Stage-2 Capture Window (`0x801D3000–0x801F4000`, 135 KB):** Covers secondary stage-2 battle/field allocation payloads.
* **THE KEY GAP:** Module 5 (**`Menu`**, Disc File 17 / `0x11`, Disc LBA `109123`) loads its primary executable payload at **`0x801C5000`** in Upper RAM, completely outside both existing capture windows (`0x8006F000–0x8008FFFF` and `0x801D3000–0x801F4000`).

This document provides the complete reverse-engineering decode, memory mapping, draw-call structure, kernel dependency inventory, and minimal HLE/emitter changes required to capture and recompile the Menu module when game state transitions to State 5 (`Menu`) after movie playback.

---

## 1. Menu Module Mapping: Entry Points, Draw Calls, and VRAM Usage

### 1.1 Entry Point Mapping

The Menu subsystem spans a resident kernel wrapper (`0x8001BDDC–0x8001C76C`) and the upper RAM overlay payload loaded at `0x801C5000`.

| Function VA | Symbol Name / Identifier | Subsystem / Role | Description & Mechanics |
| :--- | :--- | :--- | :--- |
| **`0x801C5000`** | **`MenuOverlayPayloadBase`** | **Upper RAM Module Base** | Base load address for Disc 1 File 17 (`0x11`, LBA `109123`, stored compressed size `70,944` bytes). |
| **`0x8001C634`** | **`RunResidentMenu`** | **Phase Callback (State 5)** | Main phase callback registered in Game State Descriptor Table `table[5]` (`0x800180DC`). Allocates `7,832` B heap block, initializes graphics/display buffers, sets view state, and enters dispatcher. |
| **`0x8001C1A8`** | **`DispatchMenuMode`** | **Kernel Wrapper Dispatcher** | Resident kernel menu coordinator. Loads secondary archive resources, manages sub-menu state transitions, and invokes frame-stepping. |
| **`0x801C62A8`** | `MenuMainTopLevelHandler` | Overlay Sub-Menu Target | Top-level Main Menu handler (Status / Item / Equip / Tech overview). Target of `xenolift_dispatch(0x801C62A8)`. |
| **`0x801CB0A8`** | `MenuGearEquipHandler` | Overlay Sub-Menu Target | Gear and Character Equipment sub-menu screen handler. Target of `xenolift_dispatch(0x801CB0A8)`. |
| **`0x801CBDBC`** | `MenuSkillDriveHandler` | Overlay Sub-Menu Target | Ether, Deathblow, and Drive Skill sub-menu handler. Target of `xenolift_dispatch(0x801CBDBC)`. |
| **`0x801CCD28`** | `MenuSaveMemoryCardHandler` | Overlay Sub-Menu Target | Save / Load and Memory Card access interface handler. Target of `xenolift_dispatch(0x801CCD28)`. |
| **`0x801CE024`** | `MenuConfigSystemHandler` | Overlay Sub-Menu Target | Game Settings, Sound (Mono/Stereo), and Window Color configuration handler. Target of `xenolift_dispatch(0x801CE024)`. |

### 1.2 Window and Draw-Call Structure

The menu draw-call pipeline is structured around double-buffered PsyQ display environments, active Ordering Tables (OTs), and primitive submission:

1. **Environment Initialization:**
   * `0x8001BDDC` (`InitializeMenuGraphicsEnvironment`): Configures base GPU modes, primitive clipping boundaries, and OT sizes.
   * `0x8001BE14` (`InitializeMenuDisplayBuffers`): Configures double display buffers (320x224 / 640x480 double-buffered) and links drawing contexts.
   * `0x8001BEEC` (`MenuInitializeViewState`): Resets menu rotation, translation, camera vectors, and sets $Z$-projection distances to `0x800`.
2. **Per-Frame Render Loop (`0x8001C074 MenuDebugPresentFrame`):**
   * **Input Polling:** `0x8001BF38` (`ProcessMenuButtons`) polls debounced pad state from cell `0x800625FC`.
   * **OT Clear & Primitive Build:** Clears current OT, runs active sub-menu primitive generators.
   * **Primitive Generation:** `0x800263E4` (`SetupMenuResourcePolyFT4`) constructs double-buffered Flat Textured Quadrilateral primitives (`FT4`) for UI windows, portraits, icons, and text.
   * **Display Environment Swap & Sync:** Calls `0x80044C44` (`InstallDrawingEnvironment`), `0x80044E9C` (`InstallDisplayEnvironment`), waits for VSync (`0x8004B54C`), and sets display mask `0x80044534` (`ApplyDisplayMask(1)`).

### 1.3 VRAM Usage & Layout

Menu graphics occupy specific VRAM regions for framebuffers, UI font sheets, status portraits, and CLUTs:

* **Framebuffers:** Double-buffered display environments allocated in VRAM at `(0,0)–(319,223)` (Buffer 0) and `(0,240)–(319,463)` (Buffer 1).
* **Secondary UI Archive Resource (Entry `0x6B9`):** Loaded by `DispatchMenuMode` (`0x8001C438`) into RAM buffer `0x801DC000` (size `49,152` bytes / `0xC000` bytes).
* **VRAM Texture Allocations:**
  * **CLUTs (Color Look-Up Tables):** 16-color (4-bit) and 256-color (8-bit) indexed CLUT palettes uploaded to VRAM palette area `(0,480)–(255,511)`.
  * **Font Sheets & UI Borders:** Font glyph pages, item category icons, window frame border tiles, and status portraits loaded into upper VRAM page coordinates `(640,0)–(1023,511)`.

---

## 2. Memory Window and Capture System Requirements

### 2.1 Memory Map & Overlap Analysis

The upper RAM allocation span for the Menu overlay is completely distinct from all lower RAM kernel and overlay buffers.

```
0x80000000 +-------------------------------------------------------+
           | PS1 Kernel BSS & System Data                          |
0x80010000 +-------------------------------------------------------+
           | Main Resident Kernel EXE (SLUS_006.64, 303,104 B)    |
0x8005A000 +-------------------------------------------------------+
           | Kernel Heap / Dynamic BSS                             |
0x8006F000 +-------------------------------------------------------+
           | Primary Overlay Capture Window (Modules 1-4, 6)       |
0x8008FFFF +-------------------------------------------------------+
           | ... 1.24 MB Unallocated RAM Gap ...                  |
0x801C5000 +=======================================================+
           | MENU OVERLAY CAPTURE WINDOW 2                         |
           | - Primary Code Payload (File 17):  0x801C5000-0x801D6520 |
           | - Secondary UI Data (Entry 0x6B9): 0x801DC000-0x801E8000 |
0x801E8000 +=======================================================+
           | ... Upper RAM / Stage-2 Allocator Area ...             |
0x80200000 +-------------------------------------------------------+
```

| Region Description | Start Address | End Address | Size (Bytes) | RAM Offset (`0x80000000`) | Overlap Risk |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **Resident Main EXE** | `0x80010000` | `0x8005A000` | `303,104` | `0x010000` | **None** |
| **Boot Heap Arena** | `0x8006FAF8` | Freelist limit | Dynamic | `0x06FAF8` | **None** |
| **Primary Overlay Window** | `0x8006F000` | `0x8008FFFF` | `138,240` (135 KB) | `0x06F000` | **None** |
| **Menu Primary Code Payload (File 17)** | `0x801C5000` | `0x801D6520` | `70,944` | `0x1C5000` | **Target** |
| **Menu Secondary UI Data (`0x6B9`)** | `0x801DC000` | `0x801E8000` | `49,152` | `0x1DC000` | **Target** |
| **Full Upper Menu Allocation Span** | **`0x801C5000`** | **`0x801E7FFF`** | **`143,360` (140 KB)** | **`0x1C5000`** | **Isolated** |

### 2.2 Capture System Window Specification

* **Window Parameter Identifier:** `MENU_UPPER_OVERLAY_WINDOW`
* **RAM Start Base Address:** **`0x801C5000`**
* **RAM End Address:** **`0x801E7FFF`**
* **Total Capture Window Size:** **`0x23000` bytes** (`143,360` bytes / 140 KB)
* **Alignment Requirement:** 16-byte aligned (`0x801C5000` is `0x10` and `0x1000` aligned)
* **Output Binary Filename:** `menu_overlay_region.bin`
* **PS1 RAM Offset:** `0x001C5000` (`0x801C5000 - 0x80000000`)

---

## 3. Kernel Dependencies and Game-State Table Inventory

### 3.1 Kernel Game Loop Dispatcher

* **Kernel Dispatcher Entry:** `0x80019ACC` (`RunResidentGameLoop` / `fn_80019ACC`).
* **Game State Control Cell:** `st` stored at `0x80059480` or passed via `0x8001996C` (`CommitGameStateTransition(unsigned state)`).
* **State Transition Values:**
  `0` = Kernel Menu, `1` = Field, `2` = Battle, `3` = WorldMap, `4` = Battling, `5` = **Menu**, `6` = Movie.

### 3.2 Game-State Descriptor Table (`gdesc`) Inventory

The resident kernel maintains a 7-entry Game-State Descriptor Table at base **`0x8001808C`**. Each entry is 16 bytes: `[cb: uint32] [ptr: uint32] [dest: uint32] [flag: uint32]`.

```
Descriptor Entry VA = 0x8001808C + (state_index * 16)
```

| State Index (`st`) | Game Mode | Descriptor Table VA | Phase Callback Target (`cb`) | Target Symbol / Function Name | Load Buffer / Dest | Capture Window |
| :---: | :--- | :---: | :---: | :--- | :---: | :---: |
| **`0`** | Kernel Menu | `0x8001808C` | `0x8001A4B4` | `RunKernelMenu` | Kernel RAM | Resident |
| **`1`** | Field | `0x8001809C` | `0x80077E88` | `RunFieldCoordinator` | `0x8006FAF0` | Window 1 |
| **`2`** | Battle | `0x800180AC` | `0x8001B6C4` | `RunBattleAndDispatchOutcome` | `0x8006FAF0` | Window 1 / Kernel |
| **`3`** | WorldMap | `0x800180BC` | `0x80070CFC` | `WorldMapOverlayEntryPoint` | `0x8006FAF0` | Window 1 |
| **`4`** | Battling | `0x800180CC` | `0x80088E90` | `BattlingMain` | `0x8006FAF0` | Window 1 |
| **`5`** | **Menu** | **`0x800180DC`** | **`0x8001C634`** | **`RunResidentMenu`** | **`0x801C5000`** | **Window 2 (Gap)** |
| **`6`** | Movie | `0x800180EC` | `0x800737EC` | `MovieModuleEntry` | `0x8006FAF0` | Window 1 |

### 3.3 Menu Subsystem Kernel Function Dependencies

The Menu overlay payload relies on resident kernel infrastructure across 5 functional areas:

| Kernel Area | Function Address | Function Symbol Name | Description / Role |
| :--- | :---: | :--- | :--- |
| **State Dispatch** | `0x80019ACC` | `RunResidentGameLoop` | Main game loop pump & state stepper. |
| | `0x8001996C` | `CommitGameStateTransition` | Commits state change (e.g. exit Menu -> Field `st=1`). |
| **Heap Allocator** | `0x80031BDC` | `AllocateHeapBlock` | Allocates dynamic menu work buffers. |
| | `0x800320E8` | `ReleaseHeapBlock` | Releases menu work buffers upon exit. |
| | `0x80032498` | `SwitchHeapOwner` | Assigns heap allocation tags to menu owner `0x02`. |
| **CD Filesystem** | `0x80028470` | `SelectArchiveDirectoryEntry` | Selects archive directory `0x10` / `0x04` for menu assets. |
| | `0x800288EC` | `RoundArchiveMemberSize` | Rounds archive member size to 4-byte boundary. |
| | `0x800295D8` | `ReadArchiveMemberIntoBuffer` | Reads compressed archive members (File 17 / Entry `0x6B9`). |
| | `0x80028A60` | `WaitArchiveCdData` | CD read wait loop & LZSS decompression stepper. |
| **Graphics & PsyQ**| `0x8003F8E8` | `ClearByteRegion` | Zeroes allocated work memory buffers. |
| | `0x8003700C` | `PrintFontString` | Draws variable-width font strings to menu OTs. |
| | `0x80044C44` | `InstallDrawingEnvironment` | Installs PsyQ GPU drawing environment. |
| | `0x80044E9C` | `InstallDisplayEnvironment` | Installs PsyQ GPU display environment. |
| | `0x80044534` | `ApplyDisplayMask` | Toggles GPU display mask output. |
| | `0x8004B54C` | `WaitForVerticalRetrace` | Synchronizes menu frame presentation to VSync. |

---

## 4. Recommended Minimal HLE Harness and Emitter Changes

To seamlessly handle game state dispatch to State 5 (`Menu`) after movie playback completes, minimal additive changes are required in the HLE harness (`runtime.c`) and the static recompiler emitter (`xenolift` Rust pipeline).

### 4.1 Minimal HLE Harness Changes (`xenolift/runtime/runtime.c`)

*(Note: Additive analysis only — runtime.c is not modified by research sub-agents).*

1. **Add Upper Window Capture Hook in `runtime.c`:**
   Add a watcher for State 5 phase callback entry `0x8001C634` or game state `st == 5`:
   ```c
   /* Upper Menu Overlay Capture Hook (Window 2: 0x801C5000 - 0x801E7FFF) */
   if (pc == 0x8001C634u || (st == 5u && !menu_captured)) {
       FILE *f = fopen("menu_overlay_region.bin", "wb");
       if (f) {
           fwrite(xenolift_mem + (0x801C5000u - 0x80000000u), 1, 0x23000u, f);
           fclose(f);
           menu_captured = 1;
           fprintf(stderr, "[ovl] menu overlay captured: 0x801C5000-0x801E7FFF (140KB) -> menu_overlay_region.bin\n");
       }
   }
   ```
2. **Phase Callback Registration:**
   Ensure `0x8001C634` is recognized as a valid phase callback target in the harness execution watcher table so `xenolift_dispatch(0x8001C634)` executes without tripping unmapped address traps.
3. **CD Archive Read Kick Validation:**
   Verify that LBA `109123` (35 sectors, Disc File 17) is served by the CD slot queue kick mechanism during state 5 transition.

### 4.2 Minimal Emitter Changes (`xenolift` Rust Recompiler `src/*.rs`)

1. **Map Captured Menu Binary File:**
   Update `src/main.rs` (or equivalent emitter module) to check for and load `menu_overlay_region.bin`:
   ```rust
   const MENU_OVERLAY_BASE: u32 = 0x801C5000;
   const MENU_OVERLAY_SIZE: usize = 0x23000; // 140 KB

   if let Ok(menu_bytes) = fs::read("menu_overlay_region.bin") {
       if menu_bytes.len() == MENU_OVERLAY_SIZE {
           // Map bytes into static RAM initialization table at offset 0x001C5000
           emit_memory_map_block(MENU_OVERLAY_BASE, &menu_bytes);
       }
   }
   ```
2. **Resolve Indirect Jump Targets in `disc1.c`:**
   Map indirect dispatch calls (`xenolift_dispatch(0x801C62A8)`, `0x801CB0A8`, `0x801CBDBC`, `0x801CCD28`, `0x801CE024`) to translated C functions generated from `menu_overlay_region.bin`.
3. **Memory Map Initialization:**
   Emit `static const uint8_t menu_overlay_region_init[0x23000]` in generated C output and memcpy it to `xenolift_mem + (0x801C5000u - 0x80000000u)` during harness setup.

---

## 5. Summary Checklist for Menu Overlay Integration

* [x] **Entry Point:** Base VA `0x801C5000`, phase callback `0x8001C634` (`RunResidentMenu`), dispatcher `0x8001C1A8` (`DispatchMenuMode`).
* [x] **Sub-Menu Target Addresses:** `0x801C62A8` (Main), `0x801CB0A8` (Gear), `0x801CBDBC` (Skill), `0x801CCD28` (Save), `0x801CE024` (Config).
* [x] **Draw-Call & VRAM:** Double-buffered 320x224/640x480 framebuffers, secondary UI resource `0x6B9` loaded at `0x801DC000`, CLUT palettes at `(0,480)`.
* [x] **Capture Window:** Start `0x801C5000`, End `0x801E7FFF`, Size `0x23000` bytes (140 KB), file `menu_overlay_region.bin`.
* [x] **Kernel Dependencies:** Dispatcher `fn_80019ACC`, state 5 `gdesc` descriptor at `0x800180DC`, 15 resident helper functions identified.
* [x] **HLE / Emitter Minimal Plan:** Add watchpoint at `0x8001C634` in `runtime.c`, map `menu_overlay_region.bin` at `0x801C5000` in recompiler emitter.
