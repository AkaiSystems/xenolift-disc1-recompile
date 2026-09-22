---
title: "xenolift Pre-Map Analysis of Overlay Modules 1–5"
summary: "Comprehensive pre-sprint pre-mapping of Xenogears USA Disc-1 overlay modules 1–5 (Battling, Field, WorldMap, Battle, Menu), detailing FAT disc LBAs, compressed sizes, annotations.csv symbol matches, phase table callbacks, RAM window locations, boot sequence predictions, and harness watchpoints."
---

# xenolift Pre-Map Analysis of Overlay Modules 1–5

**Document Version:** 1.0 (2026-09-11)  
**Target Project:** `xenolift` PS1 Static Recompilation Harness (SLUS-006.64 USA Disc 1)  
**Capture Window:** Primary Overlay Capture Window `0x8006F000–0x8008FFFF` (135KB) & Upper Menu Region (`0x801C5000`)

---

## 1. Overview & Overlay Module Master Table

Xenogears Disc 1 stores six executable overlay modules in Disc Directory `0x01` as files `13` through `18` (`0x0D`–`0x12`). Modules 1–4 and 6 share the primary overlay RAM load buffer at `0x8006FAF0`, overwriting each other dynamically upon game state transitions. Module 5 (Menu) loads into a separate dedicated RAM region at `0x801C5000`.

### Overlay Module Summary Matrix

| Module ID | Module Name | Disc File | Directory | Disc LBA | Stored Size (Bytes) | CD Sectors | Target Load Address | Phase Table Callback | Callback Target | Capture Window Status (`0x8006F000–0x8008FFFF`) |
| :---: | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :--- | :---: |
| **Module 1** | **Battling** | File 13 (`0x0D`) | `0x01` | `108893` | `80,284` | 40 | `0x8006FAF0` | `table[4]` | `0x80088E90` (`BattlingMain`) | **INSIDE** |
| **Module 2** | **Field** | File 14 (`0x0E`) | `0x01` | `108933` | `125,304` | 62 | `0x8006FAF0` | `table[1]` | `0x80077E88` (`RunFieldCoordinator`) | **INSIDE** |
| **Module 3** | **WorldMap** | File 15 (`0x0F`) | `0x01` | `108995` | `92,180` | 46 | `0x8006FAF0` | `table[3]` | `0x80070CFC` (`WorldMapOverlayEntryPoint`) | **INSIDE** |
| **Module 4** | **Battle** | File 16 (`0x10`) | `0x01` | `109041` | `166,564` | 82 | `0x8006FAF0` / `0x801FC000` | `table[2]` | `0x8001B6C4` (`RunBattleAndDispatchOutcome`) | **OUTSIDE** *(Kernel Wrapper)* |
| **Module 5** | **Menu** | File 17 (`0x11`) | `0x01` | `109123` | `70,944` | 35 | `0x801C5000` | `table[5]` | `0x8001C634` (`RunResidentMenu`) | **OUTSIDE** *(Kernel Wrapper / Upper RAM)* |
| **Module 6** | **Movie** | File 18 (`0x12`) | `0x01` | `109158` | `14,360` | 7 | `0x8006FAF0` | `table[6]` | `0x800737EC` (`MovieModuleEntry`) | **INSIDE** |

---

## 2. Pre-Map Analysis of Modules 1–5

### 2.1 Module 1: Battling Overlay (`file 13` / `0x0D`)

* **Disc Location & Compression:**
  * **Directory & File:** Directory `0x01`, File `13` (`0x0D`).
  * **Disc LBA:** `108893`
  * **Stored Compressed Size:** `80,284` bytes (LZSS compressed).
  * **Sector Count:** `80,284 / 2048 = 39.2` -> 40 sectors (spans LBAs `108893`–`108932`).
  * **Cross-Check vs `RECOMP_INTEL.md` & Discrepancies:** `RECOMP_INTEL.md` confirms File 13 (`0x0D`) = Battling mode, loading at `0x8006FAF0`. The sector calculation (`108893 + 40 = 108933`) perfectly matches the starting LBA of File 14 in the FAT table without gap or overlap.
* **`annotations.csv` Function Matches:**
  * **Hits in `annotations.csv`:** **ZERO** function hits matching `Battling*` in `annotations.csv`.
  * **Notes:** `annotations.csv` maps the 1,228 functions of the resident main executable image (`SLUS-006.64`, `0x80010000–0x8005A000`). State transition comments in `0x8001996C` (`CommitGameStateTransition`) and `0x8001A344` (`Kernel MENU`) reference game state `4` as `Battling`, but no function in the resident kernel image is named `Battling*`.
* **Phase Table Callback:**
  * **Callback Address:** `0x80088E90` (`BattlingMain`). Registered at kernel phase table entry `table[4]` (`0x800180CC`).
  * **Capture Window Location:** **INSIDE** `0x8006F000–0x8008FFFF` (`0x80088E90` < `0x8008FFFF`).
* **Expected Role & Context:**
  * Manages the 3D Gear Arena / Battling action-combat execution loop, HUD rendering, arena collision, and real-time controller inputs for state `4`.

---

### 2.2 Module 2: Field Overlay (`file 14` / `0x0E`)

* **Disc Location & Compression:**
  * **Directory & File:** Directory `0x01`, File `14` (`0x0E`).
  * **Disc LBA:** `108933`
  * **Stored Compressed Size:** `125,304` bytes (LZSS compressed).
  * **Sector Count:** `125,304 / 2048 = 61.18` -> 62 sectors (spans LBAs `108933`–`108994`).
  * **Cross-Check vs `RECOMP_INTEL.md` & Discrepancies:** `RECOMP_INTEL.md` confirms File 14 (`0x0E`) = Field mode, loading at `0x8006FAF0`. The sector calculation (`108933 + 62 = 108995`) aligns with the starting LBA of File 15.
* **`annotations.csv` Function Matches:**
  * The resident kernel provides 11 helper/interface functions matching `Field*` that service Module 2:
    * `0x8001B484`: `FieldLoadNewBundle` — Reuses a matching Field bundle or frees the previous buffer and starts loading archive entry `0xB8 + field_index`.
    * `0x8001B53C`: `FieldLoadRawBundle` — Allocates and pins a buffer, then asynchronously reads a raw Field bundle from archive entry `0xB8 + field_index`.
    * `0x8001B5A8`: `FieldUnloadWdsIfLoaded` — Unloads the currently loaded World Map WDS object and clears its loaded flag.
    * `0x8001B5E8`: `FieldFinalizePendingMusic` — Starts deferred music instance, releases it when required, and clears pending music state.
    * `0x8001B66C`: `FieldClearLoadedMusic` — Resolves deferred music/WDS cleanup, invalidates loaded music and wave IDs, and clears reset state.
    * `0x80025258`: `RenderFieldActorSprite` — Resident field actor sprite projection and ordering table submission dispatcher.
    * `0x8002675C`: `BuildFieldSpriteFt4Packets` — Builds double-buffered FT4 packets from expanded field sprite descriptors.
    * `0x8002709C`: `CreateFieldPanoramaPrimitiveSet` — Allocates and initializes the field panorama primitive set.
    * `0x800273C4`: `RenderFieldPanoramaSpan` — Projects a panorama span between two world points and emits wrapped texture strips.
    * `0x800278F8`: `RenderFieldPanoramaTextureStrips` — Splits a horizontally wrapping panorama texture into textured quad strips.
    * `0x8002E268`: `FieldModelFT4RawHandler` — Transforms, clips, and submits raw field-model FT4 packets.
* **Phase Table Callback:**
  * **Callback Address:** `0x80077E88` (`RunFieldCoordinator`). Registered at kernel phase table entry `table[1]` (`0x8001809C`).
  * **Capture Window Location:** **INSIDE** `0x8006F000–0x8008FFFF` (`0x80077E88` < `0x8008FFFF`).
* **Expected Role & Context:**
  * Top-level Field coordinator. Manages 3D field map rendering, entity scripting, collision detection, field dialog boxes, camera tracking, and field-to-battle/menu/world state transitions.

---

### 2.3 Module 3: WorldMap Overlay (`file 15` / `0x0F`)

* **Disc Location & Compression:**
  * **Directory & File:** Directory `0x01`, File `15` (`0x0F`).
  * **Disc LBA:** `108995`
  * **Stored Compressed Size:** `92,180` bytes (LZSS compressed).
  * **Sector Count:** `92,180 / 2048 = 45.01` -> 46 sectors (spans LBAs `108995`–`109040`).
  * **Cross-Check vs `RECOMP_INTEL.md` & Discrepancies:** `RECOMP_INTEL.md` confirms File 15 (`0x0F`) = WorldMap mode, loading at `0x8006FAF0`. The sector calculation (`108995 + 46 = 109041`) aligns with File 16 LBA.
* **`annotations.csv` Function Matches:**
  * **Hits in `annotations.csv`:** **ZERO** function hits matching `WorldMap*` or `World*` in `annotations.csv`.
  * **Notes:** While functions like `0x8001B5A8` (`FieldUnloadWdsIfLoaded`) mention World Map WDS audio and `0x800273C4` (`RenderFieldPanoramaSpan`) mentions world coordinate projection, no function symbol in `annotations.csv` begins with `WorldMap*` or `World*`.
* **Phase Table Callback:**
  * **Callback Address:** `0x80070CFC` (`WorldMapOverlayEntryPoint` / `FieldLoadContinueStageDefaults`). Registered at kernel phase table entry `table[3]` (`0x800180BC`).
  * **Capture Window Location:** **INSIDE** `0x8006F000–0x8008FFFF` (`0x80070CFC` < `0x8008FFFF`).
* **Expected Role & Context:**
  * Overworld map overlay module. Manages world terrain mesh streaming, vehicle navigation (on-foot, Gear, Yggdrasil), camera rotation/zoom, and random encounter triggering.

---

### 2.4 Module 4: Battle Overlay (`file 16` / `0x10`)

* **Disc Location & Compression:**
  * **Directory & File:** Directory `0x01`, File `16` (`0x10`).
  * **Disc LBA:** `109041`
  * **Stored Compressed Size:** `166,564` bytes (LZSS compressed).
  * **Sector Count:** `166,564 / 2048 = 81.33` -> 82 sectors (spans LBAs `109041`–`109122`).
  * **Cross-Check vs `RECOMP_INTEL.md` & Discrepancies:** `RECOMP_INTEL.md` confirms File 16 (`0x10`) = Battle mode, loading at `0x8006FAF0` (with battle-effect overlays loading into upper RAM `0x801FC000`). The sector calculation (`109041 + 82 = 109123`) aligns with File 17 LBA.
* **`annotations.csv` Function Matches:**
  * The resident kernel provides 3 core functions matching `Battle*` that wrapper and initialize Module 4:
    * `0x8001B6C4`: `RunBattleAndDispatchOutcome` — Initializes Battle graphics, runs BattleMain through Result teardown, dispatches successful outcomes to Movie, resident continuation, Field, or World Map, and resets resident state to title Field `0x1EA` on defeat.
    * `0x8001B844`: `BattleInitializeGraphicsEnvironments` — Resets graphics state, initializes geometry projection, and creates two 320x224 Battle display and drawing environments.
    * `0x8001B94C`: `BattleConfigureDrawEnvironment` — Enables background clearing and dithering and sets the Battle clear color to RGB(60,120,120).
* **Phase Table Callback:**
  * **Callback Address:** `0x8001B6C4` (`RunBattleAndDispatchOutcome`). Registered at kernel phase table entry `table[2]` (`0x800180AC`).
  * **Capture Window Location:** **OUTSIDE** `0x8006F000–0x8008FFFF`. (`0x8001B6C4` resides in the resident kernel image at `0x80010000–0x8005A000`).
  * **Note:** Module 4 binary code loads at `0x8006FAF0` (and `0x801FC000`), but its top-level phase table entry `table[2]` points to resident kernel function `0x8001B6C4`, which coordinates overlay execution and handles post-battle outcome branching.
* **Expected Role & Context:**
  * Core turn-based turn combat system (character/Gear combat, AP/Deathblow mechanics, Ether/Anima skills, battle UI, camera work, damage calculation, victory screen, and transition return dispatch).

---

### 2.5 Module 5: Menu Overlay (`file 17` / `0x11`)

* **Disc Location & Compression:**
  * **Directory & File:** Directory `0x01`, File `17` (`0x11`).
  * **Disc LBA:** `109123`
  * **Stored Compressed Size:** `70,944` bytes (LZSS compressed).
  * **Sector Count:** `70,944 / 2048 = 34.64` -> 35 sectors (spans LBAs `109123`–`109157`).
  * **Cross-Check vs `RECOMP_INTEL.md` & Discrepancies:** `RECOMP_INTEL.md` confirms File 17 (`0x11`) = Menu mode. **Critical Discrepancy:** While Modules 1–4 and 6 load into the standard overlay buffer at `0x8006FAF0`, Module 5 (Menu) loads into a separate dedicated upper RAM region at `0x801C5000`. The sector count (`109123 + 35 = 109158`) aligns with File 18 (Movie) starting LBA.
* **`annotations.csv` Function Matches:**
  * The resident kernel contains 12 functions matching `Menu*` that driver the resident menu system and interface with Module 5:
    * `0x8001A1E4`: `BuildKernelMenuCursor` — Kernel debug menu cursor construction.
    * `0x8001A250`: `LaunchKernelMenu` — Initializes kernel debug menu state and displays menu.
    * `0x8001A4B4`: `RunKernelMenu` — Kernel debug menu driver and option dispatcher.
    * `0x8001BDDC`: `InitializeMenuGraphicsEnvironment` — Menu system graphics environment setup.
    * `0x8001BE14`: `InitializeMenuDisplayBuffers` — Menu double-buffered ordering tables and primitive allocation.
    * `0x8001BEEC`: `MenuInitializeViewState` — Resets menu rotations, translations, camera state, and transition state while setting both Z distances to `0x800`.
    * `0x8001BF38`: `ProcessMenuButtons` — Processes pad input for menu navigation and adjustments.
    * `0x8001C074`: `MenuDebugPresentFrame` — Polls menu input, swaps render environments, clears active OT, runs enabled diagnostics, synchronizes drawing, and submits frame.
    * `0x8001C1A8`: `DispatchMenuMode` — Menu mode dispatcher.
    * `0x8001C634`: `RunResidentMenu` — Resident menu loop driver (phase table callback target).
    * `0x8001C76C`: `MenuExecutionConstants` — Maps menu operations to command identifiers, transition parameters, and packed coefficients.
    * `0x800263E4`: `SetupMenuResourcePolyFT4` — Builds double-buffered scaled FT4 primitives for menu-resource textures.
* **Phase Table Callback:**
  * **Callback Address:** `0x8001C634` (`RunResidentMenu`). Registered at kernel phase table entry `table[5]` (`0x800180DC`).
  * **Capture Window Location:** **OUTSIDE** `0x8006F000–0x8008FFFF`. (`0x8001C634` is in kernel RAM `0x80010000–0x8005A000`, while the overlay itself resides at upper RAM `0x801C5000`).
* **Expected Role & Context:**
  * Full in-game pause menu (Status, Equipment, Items, Deathblows, Gear Status/Tune-up, Party Selection, Save/Load, and System Configuration).

---

## 3. Boot Sequence & Phase Advancement Prediction

### 3.1 Post-Module 6 Load & State Transition Flow

1. **Cold Boot Diagnostic Phase (Module 6 / File 18):**
   * Kernel boot handler (`0x80019BFC / 0x80019C04`) reads archive file 18 (Movie, LBA `109158`, 14,360B compressed) into RAM at `0x8006FAF0` (29,779B decompressed).
   * Kernel jumps (`jalr`) directly to `0x800737EC` (`MovieModuleEntry`).
   * Module 6 executes hardware/CD diagnostics (`MovieRunCdReadStressTestScreen` `0x800704E8`), initializes STR movie playback parameters, or runs the 14-item developer debug menu.
2. **Phase Advance / Game State Transition:**
   * Upon diagnostic completion or game launch selection, state transition is requested via `CommitGameStateTransition(unsigned state)` (`0x8001996C`).
   * `CommitGameStateTransition` sets cell `0x80018088` (or target state cell `0x8004F2C0`), releases previous state memory via `ReleaseFlaggedHeapBlocks` (`0x8003218C`), invalidates stale module flags, and selects the new game state.
3. **Primary Gameplay Loop Cycle:**
   * **Default Post-Boot Target:** Transition to **Module 2 (Field, State 1)**.
   * Module 2 (file 14, LBA `108933`, 125,304B compressed) is decompressed and loaded at `0x8006FAF0`.
   * Phase coordinator transfers execution to `RunFieldCoordinator` (`0x80077E88`).
   * **Subsequent Dynamic Handoffs:**
     * **Field -> Menu (State 5):** Triggered by pause pad input. Loads Module 5 (file 17) to `0x801C5000`, phase callback `0x8001C634` (`RunResidentMenu`).
     * **Field -> Battle (State 2):** Triggered by encounter. Loads Module 4 (file 16) to `0x8006FAF0` / `0x801FC000`, phase callback `0x8001B6C4` (`RunBattleAndDispatchOutcome`).
     * **Battle -> Battling (State 4):** Triggered by arena or mini-game combat. Loads Module 1 (file 13) to `0x8006FAF0`, phase callback `0x80088E90` (`BattlingMain`).
     * **Field -> WorldMap (State 3):** Triggered by field map exit. Loads Module 3 (file 15) to `0x8006FAF0`, phase callback `0x80070CFC` (`WorldMapOverlayEntryPoint`).
     * **Battle Outcome Dispatch:** `0x8001B6C4` evaluates battle result and dispatches return transition back to Field (1), WorldMap (3), or Movie (6).

### 3.2 Kernel Requirements for First Field Module Entry (`0x80077E88`)

When `RunFieldCoordinator` (`0x80077E88`) is first entered, it requires the following kernel subsystems and BSS structures to be fully initialized:

1. **Kernel Globals & Variables:**
   * `InitKernelVariables` (`0x8001AADC`) must have executed, establishing party loading state, compass vectors, default rendering environments, and active field indices.
2. **Memory & Heap Management:**
   * Heap allocators `AllocateZeroedHeapBlock` (`0x80032B64`) and `ReleaseFlaggedHeapBlocks` (`0x8003218C`) must be operational to allocate field actor state blocks, dialog buffers, and collision data.
3. **Archive Filesystem & CD Slot Queue Stepper:**
   * `SelectArchiveDirectoryEntry` (`0x80028470`) and `FieldLoadNewBundle` (`0x8001B484`) / `FieldLoadRawBundle` (`0x8001B53C`) require the CD slot queue stepper `h2` (`0x8002A68C`) and queued-request kick mechanism (at cell `0x8004FE04`) to asynchronously stream Field bundle `0xB8 + field_index` from disc.
4. **Graphics & Primitive Submission Pipeline:**
   * Ordering tables and drawing/display environments must be initialized; field sprite renderers (`RenderFieldActorSprite` `0x80025258`, `BuildFieldSpriteFt4Packets` `0x8002675C`), panorama builders (`CreateFieldPanoramaPrimitiveSet` `0x8002709C`), and model handlers (`FieldModelFT4RawHandler` `0x8002E268`) must be ready for OT submission.
5. **Party Skin Streaming:**
   * `BeginPartyResourceReload` (`0x8001ACA4`) and `LoadStreamedPartySkins` (`0x8001B158`) must be able to load party member textures (archive members `0xA7`, `0xA8`, etc.) into VRAM.
6. **SPU Sound Driver & Audio Streams:**
   * SPU sound sequencer (`0x8003C6E8`), 240Hz counter callback (`0x8003C020`), SPU IRQ handler (`0x8003BFA0`), and field music handlers (`FieldFinalizePendingMusic` `0x8001B5E8`, `FieldClearLoadedMusic` `0x8001B66C`) must be functional to handle stream transfers and background music.

---

## 4. Harness Watchpoints

The HLE runtime team (`runtime/runtime.c`) should instrument the following exact virtual addresses, function-entry hooks, and state cells to track overlay loading, phase advancement, and module execution during harness runs:

| Watchpoint Address | Symbol Name / Hook Location | Module Context | Instrument Action & Runtime Purpose |
| :--- | :--- | :--- | :--- |
| **`0x8001996C`** | `CommitGameStateTransition` | Kernel Transition | **State Change Entry.** Log `a0` (requested state ID 0–6); track state cell updates at `0x80018088` and `0x8004F2C0`. |
| **`0x8004B54C`** | Module Entry Stepper | Kernel / Overlay | **Slot Bit Watcher.** Tracks clearing of slot-bits at cell `0x80056788` during module trampoline execution. |
| **`0x800737EC`** | `MovieModuleEntry` | Module 6 (Movie) | **Boot Diagnostic Entry.** Log execution start of initial boot/movie diagnostic module loaded at `0x8006FAF0`. |
| **`0x80077E88`** | `RunFieldCoordinator` | Module 2 (Field) | **Field Phase Coordinator.** Log entry into Field overlay loop; monitor field bundle loads (`0xB8 + index`). |
| **`0x80070CFC`** | `WorldMapOverlayEntryPoint` / Stage Defaults | Module 3 (WorldMap) / Field | **WorldMap Phase Entry.** Log entry into WorldMap overlay or Field stage continuation defaults at `+0x814`. |
| **`0x80088E90`** | `BattlingMain` | Module 1 (Battling) | **Battling Phase Entry.** Log entry into Gear Arena / Battling mode execution loop. |
| **`0x8001B6C4`** | `RunBattleAndDispatchOutcome` | Module 4 (Battle) | **Battle Coordinator.** Log battle startup, turn loop execution, and post-battle dispatch state. |
| **`0x8001C634`** | `RunResidentMenu` | Module 5 (Menu) | **Menu Coordinator.** Log resident menu activation and upper RAM overlay execution (`0x801C5000`). |
| **`0x80077C5C`** | Launch State Parameter Cell | Field / Overlay | **Launch Parameter Watcher.** Monitor parameter passed in `a0` to `fn_80031C58` during mode handoffs. |
| **`0x8004FE04`** | CD Queued Request LBA Cell | Kernel CD Driver | **CD Request Watcher.** Monitor target sector LBA during asynchronous archive overlay streams (`108893`–`109158`). |

---
