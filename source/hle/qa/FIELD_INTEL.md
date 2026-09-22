# Field Module Intelligence & "First Field Playable" Requirements Analysis

**Target Project:** `xenolift` PS1 Static Recompilation Harness (SLUS-006.64 USA Disc 1)  
**Overlay Module:** Module 2 (`Field`, File 14 / `0x0E` in Disc Directory `0x01`, LBA `108933`, Compressed Size `125,304` Bytes)  
**Load & Capture Target:** Primary Load Base `0x8006FAF0`, Phase Callback `table[1]` (`0x80077E88` `RunFieldCoordinator`), Capture Window `0x8006F000–0x8008FFFF` (135KB)  
**Primary Source Manifests:** `annotations/overlays/field/field-overlay_annotations.csv` (1,005 functions), `annotations/overlays/field/field-runtime-diagnostics-overlay_annotations.csv` (29 functions), `MODULE_PREMAP.md`

---

## 1. Executive Summary & Field Architecture Overview

Module 2 (`Field`, disc file 14 / `0x0E`) is the core operational overlay of Xenogears. It manages 3D world navigation, camera control, entity simulation, VM script execution, dialogue text boxes, collision detection, SEDS/WDS sound bank handling, and background CD archive streaming.

### Key Module Properties
* **Disc Location:** Directory `0x01`, File 14 (`0x0E`), LBA `108933`, 62 sectors, compressed stored size `125,304` bytes.
* **RAM Destination:** Primary overlay RAM load base `0x8006FAF0` (135KB capture window `0x8006F000–0x8008FFFF`).
* **Phase Table Registration:** Registered at kernel phase table entry `table[1]` with callback target `0x80077E88` (`RunFieldCoordinator`).
* **Boot Path Trajectory:** Movie Diagnostic (Module 6) -> `CommitGameStateTransition(1)` -> Field State -> `RunFieldCoordinator` (`0x80077E88`).
* **7-Day Sprint Target:** Achieving steady-state execution in the **First Field Playable** state following opening movie playback.

---

## 2. Field Coordinator & Lifecycle Mapping (`0x80077E88`)

### 2.1 Entry Point & Lifecycle Initialization
When game state transitions to Field mode (State 1), the resident kernel phase table invokes `table[1]` (`0x80077E88` `RunFieldCoordinator`).

* `0x80077E88` **`RunFieldCoordinator`**: Top-level Field coordinator that installs the initial map, runs connectivity, pause, frame, transition, and modal work, and persists and tears down Field state for resident-module handoffs.
* `0x800705DC` **`FieldInitializeRuntimeDefaults`**: Resets field, actor, camera, rendering, input, encounter, and transition state, seeds default values, and initializes supporting subsystems.
* `0x80078D44` **`FieldTransitionExecute`**: Prepares VRAM and render state, loads and installs the requested map archive, initializes or restores its actors, starts selected music, applies the entry fade path, and restores normal Field presentation.
* `0x80070CC8` **`InstallFieldScene`**: Resets map runtime state, decompresses and installs the nine Field sections, derives script and resource views, allocates actors from header records, and initializes actor resources and scripts.

### 2.2 Main Coordinator Frame Loop
Inside `RunFieldCoordinator` (`0x80077E88`), the execution loop iterates continuously while the Field state remains active. Each cycle coordinates:
1. Per-frame timing, input polling, and OT reset via `0x80077DAC` (`FieldPerFrameReset`).
2. Entity movement, collision, and VM script ticks via `0x800739C0` (`FieldUpdateEntitiesAndCameraMatrices`), `0x8008110C` (`FieldRunActorSimulationPasses`), and `0x800A2030` (`FieldRunActorScriptScheduler`).
3. 3D map mesh, character sprite, shadow, and skybox rendering via `0x8007554C` (`FieldPresentationPassA`).
4. Dialogue text box rendering via `0x8008004C` (`FieldTextBoxRender`).
5. VSync retrace synchronization via `0x800781BC` (`WaitForVerticalRetrace`) and double-buffer context exchange via `0x800796FC` (`ExchangeFieldRenderContext`).
6. Background CD archive read synchronization via `0x8008A520` (`FieldWaitForArchiveReadCompletion`) and audio streaming via `0x800854D0` (`FieldMusicStreamPollChunk`).

### 2.3 Teardown, State Serialization & Transition Path
When leaving Field mode (to Battle, World Map, Menu, or Boot), the coordinator validates readiness and performs cleanup:
* `0x80078BC8` **`FieldMainExitGate`**: Returns zero only when the coordinator's transition, storage, music, resource-loading, and pending-presentation gates are all clear.
* `0x8007954C` **`FieldChangeGameMode`**: Commits the selected battle, World Map, return-preserving resident-module, or boot-mode handoff and updates associated persistent and reentry state.
* `0x800A3F4C` **`FieldSaveSerializedRuntimeState`**: Creates the transient Field reentry snapshot from globals, camera, mutable walkmesh state, per-entity SceneActorRecord and motion state, optional attachment payloads, and all 1024 script variables.
* `0x800700B0` **`ReleaseFieldResources`**: Releases Field overlay scene allocations and working buffers.
* `0x80077D2C` **`ReleasePartySkinBuffers`**: Frees the three fixed `0x14000`-byte party skin output buffers.

---

## 3. Field Per-Frame Loop Requirements Inventory

To sustain 30/60fps playback, the Field main loop requires six distinct subsystems to execute every frame:

### 3.1 Script / Interpreter Functions
* `0x800A2030` **`FieldRunActorScriptScheduler`**: Scans active actors, selects each highest-priority runnable script slot, initializes idle slots, executes instruction budgets, and saves program counters.
* `0x800A1EC8` **`DispatchPrimaryFieldVm`**: Executes the primary Field script VM opcodes via indirect table dispatch at `0x800A1F70`.
* `0x8008110C` **`FieldRunActorSimulationPasses`**: Runs actor scripts, snapshots positions, accumulates planar movement, resolves collision/gravity, and dispatches contact scripts.
* `0x8008399C` **`FieldActorDispatchContactScripts`**: Tests actor proximity, height, facing, interaction input, and collision bounds, then starts eligible contact or interaction scripts.
* `0x8009F5F4` **`FieldScriptUpdatePlayerCharacter`**: Processes player movement eligibility, idle detection, directional input, movement triggers, and facing.

### 3.2 Sprite / Actor Drawing & 3D Geometry
* `0x800748E8` **`RenderFieldModelSet`**: Renders the active 3D Field map geometry and model collection into the active Ordering Table.
* `0x800752C8` **`FieldRenderCharactersAndShadows`**: Prepares character rendering state, uploads sprite frames, runs sprite updates, renders actors, refreshes eligible animations, and emits character shadows.
* `0x80075B44` **`RenderFieldCharacterSprites`**: Canonical Field character-sprite producer generating double-buffered FT4 textured quads.
* `0x800764B4` **`FieldRenderActorShadows`**: Projects eligible actors' double-buffered shadow quads and depth-sorts their `FlatTexturedQuadrilateralPrimitive` packets into OT.
* `0x80075484` **`FieldRenderPanoramicBackground`**: Renders the enabled panoramic background sky/horizon from current camera eye and target positions.
* `0x8007554C` **`FieldPresentationPassA`**: Primary Field presentation pass ending in `SubmitOrderingTable` (`DrawOTag`).

### 3.3 Pad Polling & Input
* `0x800775C0` **`PrepareFieldInput`**: Polls hardware/HLE controller devices and updates active Field controller structures.
* `0x80077DAC` **`FieldPerFrameReset`**: Records frame timing, clears and swaps the ordering table, polls input, and emits optional render markers.
* `0x80096078` **`TestVmControllerInput`**: Evaluates current controller held/pressed input state against VM input masks.
* `0x800961A0` **`FieldScriptVMCheckCurrentInputMask`**: VM opcode handler branching conditionally when evaluated input mask intersects held pad state.

### 3.4 VSync / Display / Context Steps
* `0x8007781C` **`UpdateFieldFrameDelta`**: Calculates elapsed per-frame delta timing for smooth movement scaling.
* `0x80073FE0` **`SwapFieldOrderingTable`**: Clears and swaps the double-buffered Field Ordering Table.
* `0x800781BC` **`WaitForVerticalRetrace`**: Canonical Field `VSync` call site returning at `0x800781C4` to synchronize display rate.
* `0x800796FC` **`ExchangeFieldRenderContext`**: Swaps double-buffered GPU draw and display environments (`DISP1` / `DISP2`).
* `0x8007999C` **`FlushFieldRenderer`**: Synchronizes and flushes pending GPU primitive submissions.

### 3.5 CD Streaming & Archive IO
* `0x8008A520` **`FieldWaitForArchiveReadCompletion`**: Polls archive synchronization until idle, yielding one vertical blank after each unready poll.
* `0x8008A558` **`FieldArchiveReadSynchronize`**: Checks background CD sector DMA status for ongoing scene or character asset loads.
* `0x800777DC` **`FieldWaitForReadFinished`**: Requests read completion and blocks until the active field archive request becomes idle.

### 3.6 Sound Triggers & SPU Audio
* `0x80085678` **`FieldSoundSequenceDispatchDueEvents`**: Emits queued sound events whose timestamps have elapsed and advances the sequence cursor.
* `0x800854D0` **`FieldMusicStreamPollChunk`**: Consumes available streamed music chunks, invokes SPU processors, and releases the stream when loading finishes.
* `0x80078B5C` **`FieldUpdateMusicState`**: Advances pending music loading, consumes random values, and updates entity sound channel delays.
* `0x8008F7B8` **`FieldScriptProcessMusicRequest`**: VM opcode handler resolving, loading, and switching field background music tracks.

---

## 4. Field One-Time Initialization Path

When transitioning into a new Field map, the game executes a strict one-time sequence before rendering the first steady-state frame:

1. **CD Sector Streaming:** Loads compressed Field archive File 14 (`0x0E`) from Disc LBA `108933` (`125,304` bytes) into staging RAM `0x8006FAF0`.
2. **LZSS Payload Decompression:** `0x8007008C` (`DecompressFieldPayload`) decompresses the raw scene archive.
3. **9-Section Scene Installation:** `0x80070CC8` (`InstallFieldScene`) parses and extracts the 9 archive sections:
   * *Section 0:* Field Header (map metadata, actor definitions, camera presets)
   * *Section 1:* Script Bytecode (VM opcodes for map entities & environmental triggers)
   * *Section 2:* Text/Dialogue Strings & String Index
   * *Section 3:* 3D Map Geometry (mesh geometry, walkmesh bounds, collision triangles)
   * *Section 4:* Camera Bounds & Trigger Volume Definitions
   * *Section 5:* Sprite & Model Resource Mapping
   * *Section 6:* TIM Textures & CLUT Palettes
   * *Section 7:* Sound / SEDS / WDS Sound Bank Assignments
   * *Section 8:* Initial Actor Placement & Encounter Formations
4. **Memory Allocations & State Inits:**
   * `0x800705DC` (`FieldInitializeRuntimeDefaults`): Resets runtime globals, actor slots, and camera bounds.
   * `0x80077C88` (`AllocatePartySkinBuffers`): Allocates three fixed `0x14000`-byte (`81.9KB`) RAM buffers for party character skin datasets (`245.7KB` total).
   * `0x8007DECC` (`FieldTextBoxSystemInitialize`): Resets dialogue slots and builds primitive templates.
   * `0x80071FB0` (`PrepareFieldRenderContexts`): Allocates OT buffers and sets up GTE perspective parameters.
   * `0x80071EE8` (`InitializeFieldInputDevices`): Prepares controller structures.
5. **VRAM Graphics Transfers:**
   * `0x80070488` (`FieldBeginGraphicsUpload`) & `0x80070F4C` (`FieldLoadContinueUploadImages`): Iterate map TIM images and CLUT palettes, issuing GP0 `0xA0` (`DataToVRAM`) blits to populate VRAM.
   * `0x80070508` (`FieldFinalizeGraphicsUploadAndMask`): Waits for GPU/archive completion and applies transparency masks.
6. **Entity, Camera, Script & Sound Setup:**
   * `0x80080A74` (`FieldActorInitializeState`): Resets actor scripts, movement, collision, and walkmesh positions.
   * `0x8007254C` (`FieldResetCameraState`): Seeds default camera orbit, pitch, FOV, and target entity.
   * `0x800A22AC` (`FieldRunEntryActorScript`): Runs map entry script mode (0/1/2/3) to initialize environmental flags, lighting, and cutscene triggers.
   * `0x8008F7B8` (`FieldScriptProcessMusicRequest`): Loads SEDS/WDS sound banks to SPU RAM and triggers BGM stream.
   * `0x80078D44` (`FieldTransitionExecute`): Triggers entry fade-in via `0x80071CB4` (`AdvanceAndRenderFade`), unmasking active presentation.

---

## 5. First Field Playable Requirements Checklist (Firing Order)

To reach the first playable frame after the opening movie, the execution pipeline must successfully pass through these ten milestones in order:

- [ ] **Milestone 1 — Phase Callback Dispatch:** Game state manager invokes `table[1]` (`0x80077E88` `RunFieldCoordinator`).
- [ ] **Milestone 2 — Archive Decompression:** `0x8007008C` (`DecompressFieldPayload`) decompresses File 14 scene archive without corruption.
- [ ] **Milestone 3 — 9-Section Scene Unpack:** `0x80070CC8` (`InstallFieldScene`) populates header, VM bytecode, text strings, 3D meshes, and actor records.
- [ ] **Milestone 4 — Large Memory Allocation:** `0x80077C88` (`AllocatePartySkinBuffers`) successfully pins `245.7KB` of heap RAM for party character skins.
- [ ] **Milestone 5 — VRAM Image Uploads:** `0x80070488` / `0x80070F4C` issue GP0 `0xA0` blits, populating map textures and CLUTs in VRAM.
- [ ] **Milestone 6 — Actor & Camera Initialization:** `0x80080A74` and `0x8007254C` establish initial character positions and camera target pose.
- [ ] **Milestone 7 — Entry Script Execution:** `0x800A22AC` runs entry VM scripts to configure scene flags and lighting without hitting unhandled opcode traps.
- [ ] **Milestone 8 — BGM & SPU Sound Bank Load:** `0x8008F7B8` and `0x800854D0` transfer SEDS/WDS wave data to SPU RAM and begin BGM streaming.
- [ ] **Milestone 9 — Entry Fade-In Unmask:** `0x80071CB4` (`AdvanceAndRenderFade`) steps color deltas from black to normal presentation.
- [ ] **Milestone 10 — Steady-State Frame Loop:** `FieldPerFrameReset` (`0x80077DAC`), `FieldRunActorScriptScheduler` (`0x800A2030`), `FieldPresentationPassA` (`0x8007554C`), and `WaitForVerticalRetrace` (`0x800781BC`) cycle continuously.

---

## 6. Key Architectural Risks & New HLE Requirements

Transitioning from movie playback to the Field overlay introduces four major technical risk areas where the headless C runtime will likely require new HLE functionality:

### 1. Input & Pad Polling (HIGH RISK)
* **Risk:** `PrepareFieldInput` (`0x800775C0`) and script input checks (`TestVmControllerInput` `0x80096078`, `FieldScriptVMCheckCurrentInputMask` `0x800961A0`) poll hardware controller buffers. In a headless HLE environment, if pad polling returns uninitialized zeros or stuck state, VM scripts will lock up or fail to advance dialogue in `FieldTextBoxRender` (`0x8008004C`).
* **HLE Requirement:** Ensure BIOS `InitPAD` (`B0:0x12`) buffers (`0x800625FC` & `0x8006261E`) are continuously serviced with valid neutral/idle button state, and implement mock pad injection for automated interaction tests.

### 2. VM Script Interpreter & Yield Loops (HIGH RISK)
* **Risk:** The Field VM scheduler (`FieldRunActorScriptScheduler` `0x800A2030`) executes actor bytecode via `DispatchPrimaryFieldVm` (`0x800A1EC8`). If opcodes stall waiting for asynchronous events (e.g. video playback `FieldScriptWaitForVideoPlayback` `0x8008A244` or CD sound loads), or if timer yields (`YieldScriptVmTimer` `0x8009DD34`) fail to advance, actors will park indefinitely at `FieldScriptParkActorMovementUpdate` (`0x80095284`), locking map progression.
* **HLE Requirement:** Map all 100+ VM opcodes in `0x800A1F70` table, ensure timer yield counters increment properly per frame, and verify asynchronous condition checks return completed status when headless.

### 3. Background CD Sector Streaming (CRITICAL RISK)
* **Risk:** Field map initialization and runtime gameplay trigger dynamic CD archive loads for character skins (`FieldBeginPartyCharacterResourceLoad` `0x8008A7DC`), sound banks (`FieldScriptLoadWdsSoundBankSlot` `0x8008AACC`), and mecha overlays (`FieldMechaBeginResourceLoad` `0x80077884`). `FieldWaitForArchiveReadCompletion` (`0x8008A520`) loops polling `FieldArchiveReadSynchronize` (`0x8008A558`). If multi-file CD DMA requests (INT1 DataReady -> INT2 Complete) fail to fire or pop request queues cleanly, the Field loading loop will freeze permanently.
* **HLE Requirement:** Verify multi-file CD sector FIFO and DMA channel 3 handling in `runtime.c` under rapid multi-file request transitions.

### 4. Memory Allocations & VRAM Render Pipeline (MEDIUM RISK)
* **Risk:** `AllocatePartySkinBuffers` (`0x80077C88`) pins 245.7KB of RAM. If heap boundaries or alignment are violated, allocation returns NULL, crashing actor spawn. Furthermore, `RenderFieldModelSet` (`0x800748E8`) and `RenderFieldCharacterSprites` (`0x80075B44`) rely heavily on GTE geometry calculations (`RTPT`, `NCLIP`) and GP0 primitive submissions (`SubmitOrderingTable` `0x8007554C`). Incorrect GTE perspective values will cause geometry clipping or invalid screen projections.
* **HLE Requirement:** Maintain exact heap alignment in `runtime.c` and ensure HLE GTE matrix transforms match hardware specs for 3D map rendering.
