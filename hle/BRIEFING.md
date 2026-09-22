# xenolift HLE briefing — shared context for all HLE sub-agents (2026-09-11)

## Mission
xenolift = a pure-Rust static recompiler for Xenogears USA Disc 1
(SLUS-00664, 1,228 functions decoded, binary-in / C-source-out). The
recompiled kernel runs inside a headless C HLE harness (runtime/) that
models PS1 hardware. END GOAL (owner's decision): extract and rebuild
the game as portable code for Unreal/Unity — the HLE runtime is the
validation harness and reverse-engineering documentation, not a
shippable emulator. Your module must therefore be (a) spec-faithful,
(b) readable as documentation, (c) cleanly separable from kernel code.

## Project layout (absolute paths)
- /app/conversations/6aa26c825d5b4135ae6b48b5/   <- workspace root
- xenolift/            Rust recompiler (src/*.rs), do not modify
- xenolift/runtime/runtime.c   the HLE harness (~2.7k lines, C17) —
                       READ IT, do not modify it. You deliver modules.
- xenolift/runtime/xenolift_runtime.h  RAM sizes: 2MB @ 0x80000000,
                       IO window 0x1F801000-0x1F802000
- disc1.c              emitted recompiled kernel (1228 fns)
- SLUS_006.64          the real PS-EXE header+image in workspace root
- xenolift/hle/        YOUR WORKSPACE. One subdir per field:
                       gpu/ gte/ spu/ mdec/ qa/
- The 718MB disc .bin exists ONLY on the owner's Mac. Sandbox reads
  of disc sectors return zeros. Design tests that do not need the disc.

## Current runtime state (R127)
- MMIO: special reads/writes routed via the runtime's register
  district handlers (see cd_read / io_special_write in runtime.c).
- CD-ROM: deep model, ~75% (sector FIFO, ch3 DMA, INT1/2/3/5, Pause
  second-response). Reference: research_cd_spec.md in workspace root.
- GPU: blit capture ONLY. Globals: gpu_vram[1024*512] (uint16,
  15bpp), gpu_gp0(v) (GP0 port 0x1F801810 writes), gpu_gp1(v)
  (GP1 port 0x1F801814), gpu_stat, gpu_disp_x/y/w/h (display area
  from GP1 0x05/0x08), gpu_dump_capture()/gpu_snapshot() (dumps
  vram.bin + live vram_live.bin at 4fps), PNG render via vramtopng.py.
- GTE: COP2 is stubbed (runtime README: "COP stubs") — zero real math.
- SPU: only the kernel-side sound HEAP exists (0x80065B10-0x8006BE00,
  first-fit allocator, limit cell 0x800695E4). No SPU audio at all.
- Pads: digital pad handshake works (cell pair 0x800625FC).
- MDEC, memory card: nothing.

## Conventions (MANDATORY)
- Pure C17, standard library only, no threads, no external deps,
  deterministic, no global mutable state that breaks re-entry.
- All logging: fprintf(stderr, "[<tag>] ...") — pick a tag like
  [gte], [spudev], [mdec], [memcard].
- Every module: hle_<field>.c + hle_<field>.h with a documented API,
  plus test_<field>.c that compiles and runs STANDALONE:
      cc -w test_<field>.c hle_<field>.c -o t_<field> && ./t_<field>
  Tests must print PASS/FAIL per case and exit nonzero on failure.
- Honesty: never fake success. If a spec detail is uncertain, mark it
  /* UNSPEC */ in code and list it in your report. Cite sources
  (psx-spx section names, emulator file paths) in header comments.

## Primary spec references (research these; use web search + page reads)
- psx-spx (Martin Korth, "Playstation SPCCON spec"): the canonical
  doc for GPU, GTE, SPU, MDEC, SIO/memory card. Search "psx-ssp GPU"
  "psx-spx GTE" etc. or read via psx.arthus.net.
- DuckStation and Beetle PSX GitHub sources (GPL — read for behavior
  reference ONLY; write original code, do not copy GPL code into this
  permissively-licensed project).
- research_cd_spec.md (workspace root): our CD dossier, example of
  the documentation style we want.

## Deliverables per field agent
1. hle/hle_<field>.c + hle_<field>.h   (full module)
2. hle/test_<field>.c                   (standalone unit tests)
3. hle/<field>/INTEGRATION_<FIELD>.md   (exact hook points into
   runtime.c: register addresses, which function to call from where,
   state cells, digest log lines to add)
4. Your returned report: what's implemented, what's UNSPEC, test
   results (pass/fail counts), key spec facts with sources.

## Integration/QA agent (separate role)
Audit runtime.c (do NOT modify): produce hle/qa/RUNTIME_HOOKS.md —
every MMIO range, function-entry watcher (a== patterns), model state
variable, and exit path — plus hle/qa/MERGE_PLAN.md describing how
each field module plugs in with minimal collision. Build a
hle/qa/harness.c conformance skeleton linking all modules.

## LATEST KERNEL FINDINGS (R128–R130; see also R131–R136 in PROJECT_LOG.md)
The kernel boot was stuck in a restart loop: 3 archive files read fine,
the 4th (module file 18, LBA 109158, size 14360) enqueued every cycle
but never started. Fully decoded as of R130:

- ARCHIVE FS (0x80028xxx): 7-byte FAT entries [3B LBA][4B SIGNED
  size] at base *(0x8004FDF0); 16-bit dir table at *(0x8004FDF4);
  fn_80028470 SelectArchiveDirectoryEntry sets active offset cell
  0x8004FE14; lookup = FAT[(file# + off - 1) * 7]; NEGATIVE size =
  directory marker. fn_800295D8 = sync archive read, fn_80029690 =
  StartArchiveRead (request struct @0x80059EF8, file# at +0x14,
  node at +0x18).
- CD SLOT QUEUE: fn_8004111C(type, node) enqueues into slot tables
  @0x80056420; for type 2 (archive read) it writes h2's address into
  the slot-handler cell 0x800564A8 = "next slot event dispatches h2
  to start the read". h2 = fn_8002A68C = the request STEPPER: FE1C
  cell (0x8004FE1C) is a per-request phase counter (0=Setloc,
  1=ReadN, 2=drain), advanced by slot-2 events from the native cmd
  chain. Slot types seen: 0xE=fd layer, 2=archive read, 6/9=driver
  internal. The kernel runs idle h2 passes safely (proven).
- THE WALL + FIX (R130, live in runtime.c): for the LAST queued
  request the previous read completes, the drive idles, and NO slot
  event ever wakes h2 -> boot handler (ret 0x80019BD8) restarts
  (~0.18s) and wipes the queue. Fix = queued-request KICK at fd-tick:
  at idle (pending/sched/arm1 all 0) with an unserved request LBA in
  cell 0x8004FE04 (!= cd_seek_lba): discard stale FIFO leftover +
  dispatch h2 (a0=byte@0x80056788, a1=0x8005A210) exactly like the
  kernel's wait loop. Requests are SEQUENTIAL (fn_800295D8 is
  synchronous) -> no mid-stream kick risk.
- KEY CELLS (all kernel BSS, low 2MB): 0x8004FE04 = requested LBA;
  0x8004FDF8 = bytes remaining of active read; 0x8004FE1C = phase
  counter (repurposed per subsystem — NOT a plain status flag);
  0x8004FE10 = status; 0x8005A488 = queued-read counter;
  0x800564A8 = slot-2 handler cell; 0x80056788 = slot byte;
  0x80056550/0x80056570 = collector scan tables (fn_800415B4).
- CD callbacks 0x8003A68C (CdSync via fn_80040FB4) and 0x8003B084
  (CdReady via fn_80040FCC) are registered by fn_80029690 and NEVER
  fire in the harness — do not build anything that depends on them.
- DISASSEMBLER (use this, do not hand-decode): from xenolift/,
  `python3 disasm.py <hexaddr-no-0x>` (little-endian MIPS, reads
  SLUS_006.64; file offset = va - 0x80010000 + 0x800). annotations.csv
  has 1,228 symbol names.
- CURRENT STATUS: R130 awaiting first Mac run. Expected on success:
  fd-kick lines in [cd] log, Setloc to LBA 109158, reads-done
  counter jumping past 2049, module 18 install, boot past phase 6.
  QA deliverables hle/qa/SLOT_MAP.md and HANDLER_MAP.md in progress
  by analysis agents.

---

# PROFESSOR'S CURRICULUM (R136, 06:58 — REQUIRED READING BEFORE ANY WORK)

You launch with no memory. This file is your textbook. The case studies
below are REAL bugs from this program — every one of them either poisoned
a build or nearly did. Read them as graded papers: what was submitted,
what was wrong, and the rule you now follow.

## Case study 1: "compile-verified" was not verified (GTE, R134)
SUBMITTED: "module is compile-verified." GRADED: the test suite FAILED —
RTPS produced SZ3=65535 (saturated), SX2/SY2/IR0 wrong, FLAG overflow bits
set. Root cause (found by the fix agent): the depth shift was
`mac3 >> ((1 - sf) * 12)`; with sf=1 (RTPS default) that is a shift of 0,
so the depth never divided by 4096, saturated, and every downstream value
cascaded wrong. A SECOND bug: the 64-entry disassembler name table was
missing one entry at 0x1A, shifting every later name down one index and
leaving index 63 NULL.
RULES:
- "Verified" = the test binary RAN TO EXIT 0 with all asserts passing,
  and you paste the tail of its output in your report. Compiled ≠ passes.
- Build lookup tables by writing all 64 entries for all 64 indices —
  then unit-test the FIRST and LAST entry. Off-by-ones live at the edges.
- When a formula has a mode flag, test BOTH branches. `(1 - sf) * 12`
  looks symmetric until sf=1 makes it zero.

## Case study 2: the test harness lied about the module (SPU, R134)
SUBMITTED: SPU module "segfaults." FIRST SUSPICION: module bug.
REALITY (ASan): the TEST declared `int16_t pcm[100*2]` and then called
`hle_spu_generate(500, pcm)` — 1000 shorts into a 200-short buffer.
The module was CORRECT; the test harness had the bug. After fixing the
harness: 6/6 pass.
RULES:
- When a test crashes, run it under ASan (`-fsanitize=address`) before
  blaming the module. Name the crashing frame with evidence.
- A segfault in a test suite is ALWAYS a finding — never ship "module
  fine, test crashes" without the ASan trace that proves which side.

## Case study 3: undeclared dependency + tangled deliverable (MDEC, R134)
SUBMITTED: MDEC "compile-verified" — but its test would not link alone:
`test_mdec.c` called `hle_memcard_reset()` (another agent's module) and
needed `-lm` for `cos()`/`floor()`. The two agents had cross-linked
their tests. After unlinking + adding -lm: 27/27 pass.
RULES:
- Your test must build with ONLY your module: `cc test_X.c hle_X.c`.
  If you need another module or a system library, that dependency goes
  in your report IN WRITING — silent dependencies break the build.

## Case study 4: the hardware-faithful state machine ate the next
command (GPU test, R135)
SUBMITTED: "CLUT textured rect fails — module bug." REALITY: the TEST
uploaded a CLUT declaring 16 halfwords but sent only 14. The GPU state
machine — CORRECTLY, exactly like hardware — treated the next command's
first word as the remaining blit data. The whole texture upload after it
was silently swallowed as NOPs. One missing word poisoned the test.
RULES:
- Hardware-faithful state machines consume EXACTLY what the header
  declares. Test payloads must be spec-exact; when the machine eats your
  next command, YOUR payload is short — count your words.

## Case study 5: the byte-vs-word decode (GPU module, R135 — REAL bug)
SUBMITTED: rects 0x68-0x7F never drew. GRADED: `size_code = (cmd >> 27)
& 3` where cmd is the 8-bit opcode byte — (byte>>27) is ALWAYS ZERO, so
every rect was treated as variable-size and the 1x1/8x8/16x16 variants
silently waited for a size word that never came. They NEVER executed.
Fixed: `(w0 >> 27) & 3` — bits 27-28 of the FULL 32-bit word.
RULES:
- Decode command bitfields from the FULL word. Bit N of the opcode byte
  = bit N+24 of the instruction word. `(cmd >> 27)` on a byte is dead
  code that LOOKS right — the most dangerous kind.
- "It never fires" bugs are usually a decode producing a constant.
  Check: does the decode expression depend on the data at all?

## STANDING DATA — the runtime you must not poison
These are PROVEN, boot-critical behaviors. Breaking any of them
regresses a boot that took 130+ builds to get here:
1. runtime.c is the professor's file. Agents NEVER edit it. You deliver
   module + header + test; the professor verifies, fixes, and integrates.
   Integration is ADDITIVE: hooks return 0 so the register-district store
   still happens, and reads of proven registers keep their proven values.
2. All I/O write widths (32/16/8) funnel through io_special_write() —
   one hook point covers everything. Reads funnel through
   io_special_read(). The raw register district gives write-readback.
3. NEVER change: SPUCNT 0x1F801DAA bit 7 (the ch4 sound-bank arrival
   handshake), SPUSTAT reads, GPUSTAT reads, the SIO pad handshake
   (0x800625FC pair, 64-step settle), and the CD INT/slot machinery.
4. ch4 DMA is the SPU upload loader: MADR advances by bytes, completion
   sets SPUCNT bit 7. Real chunk bytes now feed hle_spu's RAM.
5. MDEC reads at 0x1F801820/0x1F801824 are served by hle_mdec.
6. GTE (R136): COP2 moves + LWC2/SWC2 + CO-form math ALL route through
   hle_gte; math commands EXECUTE (the halt-class is retired).
7. The GPU capture path (gpu_gp0) drives the live framebuffer viewer —
   hle_gpu is dual-fed ALONGSIDE it; do not replace the capture.

## DELIVERY PROTOCOL (how to earn a passing grade)
1. Read this file top to bottom, then your module + its test.
2. Work pure C17, no new system deps without declaring them.
3. Verify: `cc -w -std=c17 -o /tmp/t test_X.c hle_X.c && /tmp/t` →
   exit 0, all asserts pass. ASan if anything crashes.
4. Report: root cause of what you changed, the exact verify command,
   and the tail of its output. If you weakened a test, justify it
   against the real hardware spec or it is rejected.
5. The professor re-verifies everything you claim. That is not distrust
   — it is the same code review every PS1 kernel engineer got in 1997.

## R136 Mac results + R137 (07:04 update — your modules ARE live)
- The Mac PROVED all modules engaged: the kernel fed the SPU module
  152,576 bytes of REAL sound-bank data via ch4 DMA (five feeds), GTE
  CTC2 moves route through hle_gte, MDEC reads served. Integration
  works end-to-end. This is what a shipped module looks like.
- New park: r31=0x80041BB0 = INSIDE the pump fn_80041B3C — the FOURTH
  collector-caller context (wait-loop, fd, legacy, pump). R137 made the
  collector tick CONTEXT-INDEPENDENT; the whack-a-mole is retired.
- The kernel staged its first DEEP-DISC read: FE04=LBA 239317
  (game-data territory, far past the 108893-109158 boot files), FDF8=
  9048. [newread] now flags every out-of-boot-range read.

## R140 lesson (professor's own bug — case study #6)
- Extending a C array's initializer WITHOUT updating the declaration's
  size compiles silently (-w discards excess initializers) and the loop
  reads past the array -> SEGFAULT. RULE: when resizing an array,
  change DECLARATION + initializer count + loop bound in one patch,
  and never trust "it compiled" — run it. (hc_addr[20] -> [22].)

## LATEST KERNEL FINDINGS (R142, 07:29 — recomp intel)
- Modules load at 0x8006FAF0 (NOT 0x80070000): files 13-18 = Battling/Field/
  WorldMap/Battle/Menu/Movie (disc1-overlay-inventory.md). Capture window now
  0x8006F000-0x8008FFFF. See RECOMP_INTEL.md for sound driver architecture
  (WDS banks = the ch4 sound bank; 16-byte preset records; SoundSpuIRQHandler
  0x8003BFA0) and decomp-backed symbol names for the work-list loop and
  CD callbacks. Do NOT trust old 131072B overlay_region.bin captures.

## LATEST INTEL (R149, 2026-09-11)
- hle/qa/MODULE_PREMAP.md — modules 1-5 (files 13-17) pre-mapped: FAT verified, phase callbacks live-matched, annotation families (Field 11, Battle 3, Menu 12 helpers). KEY: Menu overlay payload loads at 0x801C5000 — OUTSIDE the 0x8006F000-0x8008FFFF capture window; a second capture window is needed when the Menu phase dispatches.
- hle/qa/STR_PIPELINE.md — the 18-step FMV playback checklist + 3 riskiest runtime gaps: async MDEC slice DMA with per-slice callbacks (hle_mdec is currently synchronous), Mode2 Form2 2340B raw-sector 2x streaming, XA-ADPCM audio demux routed to SPU CD volume (0x1F801DB0/DB2).
- Kernel reached REAL GPU RENDERING (R147): PsyQ SubmitGpuPrimitive 0x80044B70 -> GP0 word-pusher fn_8004659C, callback table at 0x80056888 (static EXE data).
- RULE (violated twice this session, now absolute): the runtime startup banner must NEVER contain bracketed log tokens like [phasecb] — section greps re-match the banner and poison digests.

## LATEST KERNEL FINDINGS (R152-era, 2026-09-11 17:10) — GAME-MODE STATE MACHINE
READ hle/qa/GAMEMODE_INTEL.md FIRST when working boot/state/module questions:
- The game dispatches module entries through a WORKING game table @0x8002808C
  (idx cell 0x80028088, unpack-dest cell 0x80028084) — NOT the ROM table
  0x8001808C our old hooks watched. Current-state pair = 0x800692C0/0x800692BC
  (the 0x800592xx cells are INERT).
- Prime restart-loop suspect: the working table is never initialized at runtime.
- fn_800324B8(0x31/0x30) = heap content-category bookkeeping, NOT install/teardown.
- External goldmine: yaz0r/Noah (complete decomp — kernel + movie/STR in C++,
  local copies hle/qa/external/noah_*.cpp); TCRF bootmode lore; annotations.csv.


## LATEST (R154, 17:10) — WORKING-TABLE INSTALL
Cycle-5 live proof: commit writes ROM idx 0x80018088; dispatcher reads the
NEVER-INITIALIZED working cells 0x80028088/0x8002808C (raw code) -> wild
descriptor -> abort to restart step before the entry dispatch. R154 runtime
patch: table install at boot init + idx mirror at dispatcher entry +
unpack-dest per state (0x8006FAF0 / menu 0x801C5000). FE04 LBA-cell watcher
added (clobber to 109142 suspected in the read stall). READ hle/qa/GAMEMODE_INTEL.md.

## R224 — THE FALLTHROUGH-JR-RA CLASS (root cause of the 45-cycle restart loop)
The Rust emitter mistranslates a function whose TAIL instruction is `jr ra` (return to
the live return register) as a "fallthrough into the next function in memory". For
fn_80019548 (RestoreResidentExecutionRegisters) the next function in memory was
fn_80019578 (boot main) — so EVERY dispatcher pass, the restore hard-restarted boot
instead of returning to the post-restore chain. Symptom fingerprint: probes fire at
the call site, the "next" instruction after the call never dispatches, and boot main
re-enters with r31 pointing at that next instruction.
FIX PATTERN: guard the emitted fallthrough with `if (r[31] == <legit-target>)` and
`return;` otherwise; rides run.sh idempotently after emit (R224 guard, anchor fn_80019548).
AUDIT ITEM for any future emitter work: scan every emitted function for tail `jr ra`
followed by a direct call to the next-in-memory function — same class may lurk elsewhere.

## R224–R227 — THE TWO-WINDOW CAPTURE-COMPILE ARCHITECTURE + MOVIE PLAYER LIVE
The 45-cycle boot loop = the emitter's FALLTHROUGH-JR-RA class (tail `jr ra` misread
as a call into the next-in-memory function). R224 guard: emitted restore honors live
r[31] (only the cold-boot stub case continues); rides run.sh idempotently post-emit.
THE PIPELINE FOR SELF-LOADING CODE (the project's core pattern now):
  1. module/stage executes → reads a NEW code payload from disc into a fresh region
  2. calls into it mid-stream → runtime HALT at the unresolved target (by design)
  3. halt-path completes the pending read FROM THE DISC IMAGE, dumps the window
     (window 1: 0x8006F000+135168B -> overlay_region.bin; window 2: 0x801D3000
     +135168B -> stage2_region.bin)
  4. emitter (Rust) maps the capture into the image (size-gated) + seeds the target
  5. next build: the call lands in recompiled code
Cycle-12 result: stage-2 RESOLVED — the movie module ran MovieLaunchScriptedMovie
-> MovieRunPlayback -> MoviePollSkipInput (caller chain 0x80073B8C/0x80076478/0x800767C0)
= THE GAME IS STARTING ITS OPENING FMV. Then a raw segfault with zero output because
the old SIGSEGV handler used non-signal-safe calls (crash-in-crash). R227 = async-
signal-safe crash capture: cur_fn tracked live at every function entry, si_addr,
key registers, last-32-function call trail from the trace ring, SIGSEGV+SIGBUS.
Next frontier: name and fix the crashing function in the movie-player chain; then
the FMV pipeline (STR_PIPELINE.md, 18-step checklist) is the direct road to the
title screen. GOTCHA: crash handlers must be async-signal-safe — raw write(2) only.

## R225-R227 — THE TWO-WINDOW CAPTURE-COMPILE ARCHITECTURE (boot wall BROKEN)
Sprint arc: R224 (fallthrough-jr-ra fix) killed the 45-cycle restart loop → MovieEntry
executed → the module self-loads an 88,604B second stage into 0x801D3000 and calls it
mid-stream → R225: at the expected halt, complete the pending read from the disc image
and capture the window → R226: the Rust emitter maps stage2_region.bin at 0x801D3000
(image extended to 0x801F4000, 0x801D3538 seeded) → cycle 12: THE FMV PLAYER IS LIVE
(MovieLaunchScriptedMovie → MovieRunPlayback → MoviePollSkipInput). CURRENT FRONTIER:
raw segfault right at the movie-player boundary; R227 = async-signal-safe crash
reporter (single atomic critical line: sig/addr/cur_fn/r31/sp/r4-r6, then the 32-fn call
trail from the trace ring, then native backtrace) + =CRASH= digest section. KNOWN RISK:
the stage-2 window overlaps the kernel's scratch area (0x801F1xxx/0x801F3xxx decompress
dests) — captured scratch could seed phantom functions; if the crash trail lands in a
garbage function, suspect phantom-seed discovery over scratch data.


## LATEST FINDINGS (R220-R230)

### 1. BOOT CHAIN & MOVIE MODULE ENTRY
- **Boot Loop Broken**: Stale-request retirement plus PSXSPX-faithful CD DMA behavior (CHCR busy bit 24 auto-clears, done-write `0x00000000`) broke the 45-cycle install loop.
- **State Machine & Module Mounting**: State machine mounted state 6 (Movie module), member 7 read completed, and movie module file 18 (LBA 109158, 14,360B) was read + unpacked to RAM at `0x8006FAF0`.
- **First Blits & Handshake**: GPU drew first real blits and digital pad handshake completed.
- **Boot Wall Broken**: Module 6 entry REACHED (boot wall broken).
- **FMV Execution**: `MovieLaunchScriptedMovie` -> `MovieRunPlayback` -> `MoviePollSkipInput` x10 executed.

### 2. MOVIEPOLLSKIPINPUT CRASH ANALYSIS & DIAGNOSTICS
- **Crash Location**: Inside `MoviePollSkipInput` at `0x800769A4`.
- **Wild Pointer Dereference**: Target address varied across runs (`0xB7E7EFF8` then `0xB81B5FF8`), confirming data-dependent garbage dereference, NOT stack recursion.
- **Stack Pointer & Data Base**: Stack pointer `sp` was pinned at `0x807FC910` (`0x80800000 - 0x36F0`), which is outside valid 2MB RAM (deterministic across runs = deliberate stack setup with a bad constant). Module data base register `r5` = `0x80077194`.
- **Crash-Report Diagnostic History**:
  - *R226*: Unsafe handler died with crash.
  - *R227*: Async-safe handler installed, printed nothing (stack exhausted).
  - *R228*: `sigaltstack` + `SA_ONSTACK` FIRED, naming `MoviePollSkipInput`.
  - *R230*: Added memory dumps: 32 words MIPS at `cur_fn` + 8 words at `r5` + stack window, all `[crash]`-tagged so the digest keeps them.

### 3. GPU RECT & POLYGON DECODER FIX (R229/R230)
- **Decoder Bit Swap Fix**: `hle_gpu` had textured and semi-transparent bits SWAPPED in rectangle AND polygon decoders, raw texture hardcoded ON, and dead byte-shift tests.
- **PSXSPX-Verified Layout**:
  - Bit 0: Raw texture (disable blending/shading)
  - Bit 1: Semi-transparent (blending enabled)
  - Bit 2: Textured
  - Bit 3: Quad / polygon primitive
  - Bit 4: Gouraud shading
  - Word bits 27-28: Rect size code
- **Verification**: Fixed across 4 decoder sites; verified word counts for 24 rect + 20 polygon primitive types.
- **Symptom Resolved**: Fixed DMA stream desynchronization at the first textured primitive (which previously caused an empty screen and looping redraw packets).

### 4. PROCESS RULES FOR FUTURE AGENTS
- **(a) -Werror Compliance**: ALL ship builds compile with `-Werror=implicit-function-declaration`. The sandbox compiler silently forgave implicit declarations (like implicit `printf`), but Mac Clang strictly refused them, wasting one full bridge cycle (cycle 16).
- **(b) No Sandbox Leniency**: Never rely on sandbox leniency; declare everything you use explicitly.
- **(c) Disc & Capture Realities**: The sandbox has a 303KB stub disc and empty captures — real module bytes exist only on the Mac. Byte-level decode must come from digest dumps.
- **(d) Clean Runtime Banner**: Never put digest grep tokens (like `[phasecb]`, `[crash]`, etc.) inside the runtime startup banner, as section greps re-match the banner and poison digests.
- **(e) Single Verified Package**: Deliver one package per turn; verify zip contents (banner + all fixes) before issuing the directive.

### 5. MOVIE-ERA STATE (R325-R333, cycle 74-81) — READ BEFORE ANY MOVIE/CD TASK
- **Boot wall long dead**; title handoff works (virtual X-press); intro countdown (77014 5->1) completes NATIVELY; frames 1-4 of the movie are decoded AND presented (GPU wait -> retrace -> double-buffer flip -> InstallDisplayEnvironment all run). The movie module = the disc-diagnostic suite (ReadStressTestScreen family); "movie data" = its stress-test sector patterns (03FF03FF/00010009...).
- **THE frame-5 gate**: the next-batch data request. Batch 1 (LBA 108599-108604, FDF8 10780->0) delivered PERFECTLY via the game's own LegacyCdSectorFetch chain -> ring 0x801E6000-0x801E8800 + 12B headers -> 0x80059EF8. The next request parks at state 7 (FE1C=7, FE20=4, last_cmd=0x01, resp_n=3, seek 108605, data_n=0). NOTE: real disc sector 108605 = SYSTEM.CNF text, NOT stress data — the request target itself may be mis-derived.
- **Two assists live**: rdcomp (stalled read completion) and seek7 (state-7 wedge cells) — both fire once per stall, writes land, but the kernel's follow-through doesn't complete the batch. R333 added seek7x escalation (FE04+1, INT1 redelivered) — R332 shipped it with the armed flag written BACKWARDS (=0); fixed in R333.
- **THE GHOST STORY (3 cycles) RESOLVED AS INSTRUMENTATION**: state-6/7/11 handler "bodies never write their cells" was concluded from probes + watchers, but (a) XTRACE probes are the fns' FIRST statement (body provably STARTS), and (b) the hc watcher cells had a 24-line log budget exhausted during BOOT — movie-era writes were never filmed. R333 gives movie-era cells (FE1C/FE20/0x8006A488/94/98/A4A8/B4) a 240-line budget and 1-in-2000 sampling on the state-6/7 probes. Decisive read: FE1C 7->6 in the R333 digest tail = bodies work, wall is kernel follow-through; absent = vanish between XTRACE and first store (only a handful of instructions).
- **Watcher resize lesson (4 strikes)**: hc_addr[] grew to 61 entries but loop stayed k<57 = 4 watchers silently dead. RESIZE decl+init+loop+caps TOGETHER, always.
- **Slice-loop decode (R331 modsrc)**: at last countdown tick -> fn_801D4318 (stage-2 slice decoder) -> 7701C==0 -> WaitForGpuDrawing -> WaitForVerticalRetrace -> RelocateVramRectangle -> InstallDisplayEnvironment -> fn_800768A4. The present path is HEALTHY.
- **Trampoline/guard history**: the R320 recursion guard false-tripped (depth measured from a static var = 4.4GB "depth"); fixed in R324 with a real stack local + range bound. The R323 churn trampoline only bounces >8MB deep — ruled out as body-killer.

### 6. ORACLE VERIFIED (OpokXeno/xenogears-recomp annotations, 2026-09-12)
Downloaded to hle/: RECOMP_ANNOTATIONS.csv (resident EXE, 1219 fns), RECOMP_MOVIE_OVERLAY.csv, RECOMP_MOVIE_STRLIB.csv, RECOMP_OVERLAY_INVENTORY.md. KEY NAMES for our frontier:
- 0x8002A68C = ProcessArchiveDriveStatus; 0x8002AC24 = ArchiveQueuedReadReadyCallback (consumes ready sectors, seeks gaps, retries); 0x8002B084 = ArchiveCurrentFileReadyCallback (advance->finalize path the zrf assist arms).
- 0x80040FB4 = HandleCdSyncCompletion; 0x80040FCC = HandleCdReadyCompletion; 0x8004111C = IssueDiscCommandImmediate; 0x800413EC = SetCdSectorCallback; 0x80041534 = ConvertDiscLocationToSector; 0x800415B4 = ReadCdInterruptState (all PsyQ libcd).
- 0x8001996C = CommitGameStateTransition (1=Field, 6=Movie); 0x80019ACC = RunResidentGameLoop; 0x8001BB50 = StartNewGame (waits for all archive transfers).
- STAGE-2 MODULE (0x801D3000) = movie-str-lib-overlay (file 0x18/0x01). Movie overlay (file 18/0x801EFC94) = 0x01/0x12, entry 0x800737EC = MovieModuleEntry ("scripted playback OR 14-item debug menu").
- 0x800768D8 = MovieDecodeSliceCallback; 0x800769A4 = MoviePollSkipInput; 0x800763BC = MovieLaunchScriptedMovie; 0x80076488 = MovieRunPlayback.
- **THE GAME HAS ITS OWN STALL-RECOVERY PATH**: 0x801D3F7C MovieStrUpdatePlayback — "after a prolonged stall it supplies the following-sector recovery location... otherwise restarting from the original start"; 0x801D5A94 MovieStrGetBackLocation — "writes the sector AFTER the saved frame-start location and returns its frame number"; capture saved by 0x801D5A04 MovieStrCdDataReadyCallback; capture enabled only when mode bit 0x20 set in 0x801D586C MovieStrStartCdRead2. OUR seek7x FE04+1 escalation MIRRORS THE GAME'S OWN documented recovery (following-sector) — R335 state-6 zrf service = the queued ReadS first-sector delivery that MovieStrCdInterrupt (0x801D5D54) assembles. VERIFIED.
- STR ring pipeline: StartCdRead2 (Setmode+ReadS+callbacks) -> CdInterrupt assembles sectors into ring (rejects when contiguous frame won't fit) -> DataReadyCallback marks frame-start + saves location -> UpdatePlayback advances / recovers; StopPlayback 0x801D4318.

### 6. VERIFICATION ORACLES (verified live 2026-09-12, Jos-directed)
- **OpokXeno/xenogears-recomp** (github, 47 stars): static recomp of the SAME game/EXE on PSXRecomp (MIPS->C->x64, no emulator binary). STATUS: boots, title, INTRO FMV, opening gameplay playable (alpha). Validates our whole architecture. Its working CD controller + full PSX hw layer live in the psxrecomp submodule — the reference for what a CORRECT disc model does for this exact game.
- **yaz0r/Noah** (github): COMPLETE Xenogears decompilation, all executing code decompiled/reimplemented (US SLUS_006.64). THE game-behavior oracle: read the actual driver code (the fn_8002A68C family, 0x80041CA0 router, movie loop 0x8007670C/7DC) as real source instead of recompiled idioms.
- **ladysilverberg/xenogears-decomp**: matching decompilation, same target. Secondary reference.
- Use for: state-machine semantics (state 6=data-wait etc.), batch chain, MDEC slice protocol, CD command ladders. Flow per standing rule: decode from disasm -> cross-check Noah/recomp -> then trust the fix.
- **R336 process note**: single park authority = the 195s budget watchdog. All early-phase halt detectors must not terminate runs while assists are still winding up.

## MISTAKE LEDGER (READ BEFORE WRITING RUNTIME CODE)
- **LESSONS.md** (package root) = durable ledger of every mistake class + PRE-FLIGHT CHECK for ships. Read it first; do not repeat entries L1-L12. Key hard rules: no guest dispatch from MMIO-read context; every probe ships as a triple (code + digest section + budget); detectors cover all observed variants; -Werror=implicit-function-declaration on every build.

## LATEST KERNEL FINDINGS (2026-09-13 12:00, R528) — READ FIRST
- KERNEL MENU + CONFIRM happened (R502). Game is in the DISK DIRECTORY SCAN era: Setloc BCD 00:02:00 -> LBA 0, then 00:02:01 -> LBA 1 (the game is reading its file-table/directory sectors at the disc lead-in).
- THE ACK-DELIVERY FAMILY (R521-R527, all fired + verified in c96): the game's CD state machine polls for a 3-byte ack [02 01 01] for Setloc (cmd 02, state FE1C=10), ReadS (cmd 09, FE1C=0), and GetStat (cmd 01, n=1 [02] or [22], FE1C=0). PRIMING THE FIFO IS NOT ENOUGH — the game only reads its mailbox when cd_pending!=0 (the "doorbell"): handler-pair conversion then pops the bytes (rspop path). All three doorbells are in runtime.c: search [dirack], [dirack2], [dirack3].
- CURRENT FRONTIER (R528): LBA-1 sector sits in the FIFO (data_n=2060, loaded=1) unconsumed; the game polls GetStat at FE1C flapping 0<->6. The zrf0 force-deliver wedge (search "[zrf0] R511") was widened to accept fe1c==0 so the flapping always arms->fires -> INT1 delivered -> the game's own callback fn_8002B084 pulls the sector into the ring dest (rs+18 = 0x801FCF24, batch FE08 ring 0x801FB724->...->0x801FCF24).
- KEY CELLS: FE1C=CD state (arc table @0x800188F4), FE20=substate, FDE4=batch/step counter (watched it walk 0x11->0x14), FDF8=remaining-bytes countdown, FE04=file request id, FE08=ring dest head, read struct @0x80059EF8 (+10=ready callback 0x8002B084), cbheal re-arms 0x80059F08.
- NEXT WALLS (predicted): after LBA-1 consumption the directory scan continues (LBA 2,3,...); then the game re-reads its file table and loads field files -> field init -> first render. Then real pad input for walking (day-3 goal).
- VERIFY against psx-spx (CD response/INT semantics) and OpokXeno sources before trusting any new gate.

## FIELD MANUAL — Practical Binary Analysis (Andriesse, No Starch 2018) [Jos directive 13:08]

Book studied by the lead agent; these six disciplines apply to EVERY task you take:

1. **ANATOMY FIRST** — never theorize about a structure. Build a small parser
   tool and read the real bytes. If you are reasoning about read-struct
   0x80059EF8, the queue node at 0x80059F10, or any struct: dump it first.
2. **BUILD YOUR OWN TOOLS** — purpose-built small scripts beat generic
   squinting. If the digest lacks a view you need, say so in your findings.
3. **STATIC + DYNAMIC PAIRING** — decode from the decompiled source AND
   observe at runtime. Where the two disagree, that gap IS the bug. Cite both.
4. **INSTRUMENT WITHOUT MODIFYING** — prefer observation over patching. When
   you propose a cell write, prove first that the game's own code reads it.
5. **TAINT TRACKING** — when delivered data is wrong, trace its full path
   source -> destination and name the exact instruction where it diverges.
6. **DERIVE THE CONTRACT** — for any wait/wedge, enumerate ALL conditions the
   code checks and satisfy the complete set, not one guess at a time. The
   cycle-102-107 GetStat wedge class happened from guessing one byte at a
   time; the answer was to derive the full contract.

## OPERATING POSTURE — jdBasic-style persistence (Jos directive 13:12)
The lab adopts github.com/AtomiJD/jdBasic's "rewrite the game while it is
still running" philosophy: (a) frontier save-state/restore so runs resume AT
the field-mount wall instead of rebooting every cycle; (b) a live control
file the runtime polls each tick (write cells / prime answers / toggle drive
flags against the running game — derive contracts by live experiment, then
bake winners into runtime.c). Never propose another 4-minute-cycle guess when
a live experiment can answer it in seconds.

## PROJECT CONSTITUTION — the three goals (Jos 13:25)
1. PRIMARY: Xenogears Disc 1 fully playable by Sep 18 (7-day recompile sprint).
2. Xenolift becomes a PRODUCT: real-time old-code → modern-code translator.
   Drag-and-drop, fully deciphered in 5-10 minutes. Not archaeology — commodity.
3. A REAL-TIME GAME ENGINE built from our accumulated knowledge. Invent NEW
   mechanisms; don't just trust existing ones. We improve and invent.
When you build something game-AGNOSTIC (a probe pattern, a panel, a decode
method, a lesson), note it: that is product capital for goal 2/3, not just a
fix for goal 1.

## LATEST KERNEL FINDINGS (c155 refresh — READ FIRST)
- KERNEL MENU reached (R502): game rendered its own menu, virtual player pressed CONFIRM on Field, game's own mount machinery launched (file 14, LBA 108933, 125,304 bytes).
- f14inst (R583/R584): ENTIRE file-14 module installed to landing 0x801D9724 from the disc + end-of-read cells (FDF8=0, FDFC=0). Driver completed its wrap chain for the first time (13->08->01 at seek 108996).
- REMAINING WALL: the file layer still never signals file-14 complete — F0C (request slot) stays 14, cur(92C0) stays FFFFFFFF. FDF8=0 is NOT the completion contract. Boot-era files 2-6 complete NATIVELY — their fingerprints are the reference standard.
- R585/R586: full read-struct watch (0x80059EF8 +0..+0x34) + emit self-heal (payload verify + re-emit). RSW watch data lands c155.
- MDEC/LZSS divergence (REEL's wall): live decompressor output ZEROED vs reference at first byte, both streams — oldest open wall, day-4 risk.
- LESSONS.md = pre-flight ledger: audit every new probe against it before shipping.
