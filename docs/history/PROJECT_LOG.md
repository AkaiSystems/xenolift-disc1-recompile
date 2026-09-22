# xenolift project log

Static recompiler (binary in, C source out) for Xenogears USA Disc 1
(SLUS-00664). 1,228 functions decoded via a 3-pass pipeline (decode →
discovery → emit). Runtime = headless PS1 HLE harness validating the
recompiled kernel boot before the extraction/port stage.

## 2026-09-11 build history (session 2)

- **R94** — emitter delay-slot bug: 183 branches with a chunk-start slot
  silently dropped the slot instruction; inline-plain-slot fix. Kernel now
  writes its own sound-heap limit (0x800695E4) and passes the reverb wall.
- **R100-R107** — CD-ROM data path: ch3 DMA serves the real sector FIFO
  (12-byte BCD header + 2048 data), kernel-native handler fn_8002B084
  streams real disc bytes to the staging region; first REAL file
  decompression (6594/29048/6209 bytes) off the disc.
- **R119-R120** — overlay capture-compile: the runtime-installed module
  (files 13-18) dumped from RAM and emitted natively at 0x80070000
  (128KB, 23,939 nonzero words). Phase callbacks land in recompiled code.
- **R112-R113** — instant FE1C release: the file layer's read-complete
  poll no longer waits 4096 polls for the fallback nudge.
- **R124** — spec-exact Pause: the CD Pause command's SECOND response
  (INT2, status Read-cleared) was never delivered; the fd layer could
  never pop its request queue. Research source: research_cd_spec.md
  (psx-spx). Status bits corrected: bit5=Read, bit6=Seek, bit4=ShellOpen.
- **R125** — GPU frame capture: GP0 writes were silently dropped; now
  0xA0 DataToVRAM blits populate a 1024x512x16bpp VRAM model, display
  area tracked via GP1 0x05/0x08, watchdog dumps vram.bin +
  vramtopng.py renders screen.png. (PS1 VRAM is not CPU-addressable —
  blit capture is the only way to see anything.)
- **R126 (current)** — live framebuffer: gpu_snapshot() writes
  vram_live.bin at ~4fps (atomic tmp+rename); xenoview.py renders it
  live in a Terminal window (ANSI 24-bit color, 2 pixels per cell);
  run.sh auto-opens the viewer via osascript before the game runs.
  Contains R124 (Pause INT2) + R125 (capture). Mac run 05:40: viewer
  and capture WORK (62 blits, 256x240 display, 37 snapshots), Pause INT2
  fires — but file 18 still never reads; boot restarts ~1000x/watchdog.

- **R149 (current)** — SUB-AGENT DELIVERABLES EXECUTED (Jos: "verify
  and execute on all sub agents work"). BOTH 7-day-sprint prep agents
  delivered: (1) MODULE_PREMAP.md (19.5KB) — files 13-17 FAT verified
  EXACT vs live =FTAB= (Battling 108893/80284, Field 108933/125304,
  WorldMap 108995/92180, Battle 109041/166564, Menu 109123/70944);
  ALL phase-cb claims match the live =PHASE= table; annotation
  families: Field 11 resident helpers, Battle 3, Menu 12, Battling 0,
  WorldMap 0 (overlay-internal symbols absent from CSV);
  **KEY FINDING: Menu overlay payload loads at 0x801C5000 — OUTSIDE
  the 0x8006F000-0x8008FFFF capture window** (needs a second window
  when [menu] fires); boot prediction: Module 6 diag -> CommitGameState
  Transition(1) -> Field state 1 -> RunFieldCoordinator 0x80077E88.
  (2) STR_PIPELINE.md (15.2KB) — 18-step FMV checklist + 3 riskiest
  gaps: async MDEC slice DMA w/ per-slice callbacks (our hle_mdec is
  synchronous), Mode2 Form2 2340B raw-sector demux at 2x, XA-ADPCM
  audio demux to SPU CD volume (0x1F801DB0/DB2); player chain:
  MovieLaunchScriptedMovie 0x800763BC -> MovieRunPlayback 0x80076488
  -> MDEC cmd 2/3 tables -> DMA ch0 in / ch1 out ->
  MovieDecodeSliceCallback 0x800768D8 -> frame upload; skip input
  MoviePollSkipInput 0x800769A4.
  R149 EXECUTION: [phasecb] entry hooks on all 5 module callbacks +
  the 4 movie-player fns (first 8 + every 500th, caller logged);
  [cd] Setmode 0x0E decode+log (2x/XA/raw flags = the STR-transition
  marker in =CD=); =PHASECB= digest. Banner-token lesson violated and
  re-fixed TWICE more ([phasecb] literal) — the rule is now: banner
  NEVER contains bracketed log tokens. Sandbox 17/33 identical.
- **R148** — RENDER LIVENESS. R147 Mac: the Seek INT2 fix
  CASCADED — the stress read at LBA 239317-323321 COMPLETED via native
  h4 slot dispatches ("wait-loop: dispatch h4 0x8002B084 (a0=1)",
  FE1C 5->0, file layer released), Pause INT2 armed and delivered,
  read struct now holds file#=3 (multi-file servicing), and the kernel
  entered REAL GPU RENDERING: park r31=0x80044BB8 = inside
  fn_80044B70 SubmitGpuPrimitive___PsyQ_libgpu (emitter-named from the
  symbol CSV!) -> GPU callback table at 0x80056888 (static EXE data,
  read straight from the SLUS image; 0x800568C8 holds the table PTR,
  [5] = 0x8004659C "cwb" = the GP0 word-pusher; [15] = 0x80046DB4) ->
  cwb pushes r5 words from r4 to GP0 through cell 0x800569A0 with a
  GP1(0x04) DMA-off toggle; the kernel submitted a textured-quad
  stream (r3=0x3C000000 = textured quad opcode) from the display-list
  buffer 0x801F1C68-0x801F34B4 (~1555 words), double-buffered packet
  chains per =DISP2= (fn_80044894 -> s2=0x801F1C68/94). THE KILL:
  watchdog = 15s alarm deferring only on PARK ticks (CD driver
  machinery) — a pure GPU stretch produces ZERO park ticks, so the
  watchdog shot the kernel MID-RENDER. 15s of host time in the pusher
  = an enormous/ongoing stream (boot render or steady-state display
  loop — possibly the kernel's own diagnostic/error screen loop).
  R148: [gpuprim] submission log (first 24 + every 500th, prim addr +
  tag + len + caller), g_gpu_words counter (cwb entry), RENDER-ALIVE
  watchdog defers (GPU words advanced -> defer, budget 40 = ~10 min
  max render stretch, "[halt] render alive" lines), [park] gpu
  counters, =GPU= digest extended. Banner token lesson applied
  (no [gpuprim] literal in banner). Sandbox 17/33 identical.
- **R147** — SEEK INT2. R146 MAC DIGEST = LANDMARK:
  (1) "overlay module: 135168 bytes mapped at 0x8006F000 (24296
  nonzero words)" = MOVIE MODULE NATIVE RECOMPILED CODE (cycle-2
  bootstrap completed); (2) FILE-18 READ COMPLETE — =DMA= shows all
  sectors 109159-109165 streamed to the 0x801F0494-0x801F3494
  install region (verdict-dest 0x801F34B4 adjacent), FDF8 -> 0;
  (3) kernel then SEEDED Seek(0x07) to LBA 109166 = FIRST-PAST-THE-
  MODULE territory (read struct still holds file#=18, +18=0x00331724
  unknown cell) and PARKED in the fd processor (r31=0x80041C78,
  r16=0xE fd slot, r17=0x80059F18 queue node, r11/r15 = movie-module
  tail 0x80076F3B/43, r14=0x8006FAF0 module base) waiting for the
  Seek's INT2 — the model delivered the INT3 ack but never armed
  the completion INT2 = the SAME missing-second-response class R123
  found for Pause. FIX: cmd 0x07 added to the R124 two-response set
  (Pause 0x09, Init 0x0A, now Seek 0x07) — after INT3 ack, arm INT2
  with stat 0x02 (motor, Read cleared), "[cd] Seek complete" log.
  ALSO CONFIRMED ON MAC: =GATE= handlers live (InitPAD/StartPAD
  x10 cycles, SetCustomExit @0x800578DC once, ChangeClearRCnt rc=3
  once); digest compact works (one banner, =PARK= dump names the
  park state); =TASK= shows 0x80040A8C/0x8004C970/0x8004D028 new
  tasks; phase idx=6 cb=0x800737EC staged but not dispatched (the
  install chain parks at the Seek first). Sandbox 17/33 identical.
- **R146** — DIGEST COMPACT (Jos: "the build report is
  too big"). ROOT CAUSE: the runtime startup banner had grown into an
  8,182-char build-history essay whose text contained the literal
  grep tokens of the digest sections ([movie], [newread], NEW
  CONTEXT, [spu-dma], [park], [bxcep]...) — so ONE digest reprinted
  the ENTIRE banner FOUR TIMES (=BUILD=, =MOVIE=, =NEWREAD=, =CTX=,
  =SPUDMA=, =PARK=). FIXES: (1) banner compacted to a one-line
  build ID + pointer to PROJECT_LOG.md (the full history R94-R145
  ships in the package — nothing lost); (2) run.sh now pre-filters
  run.log into run.log.d (grep -v "runtime build") and every digest
  section + every =TICK= counter reads run.log.d; the banner appears
  exactly once, in =BUILD= (head -1); (3) noisy sections trimmed
  (OVL2 20->8, ARC 20->8, CELL 40->24, FL 28->16, CD tail 40->28,
  SLOT 24->16). Sandbox: digest end-to-end verified via the digest
  block alone (17KB sandbox digest, 1 banner copy), 17/33 run
  identical. Estimated Mac digest: ~60% smaller than the R143 report.
- **R145** — BIOS THUNK AUDIT IMPLEMENTATION (Jos ask:
  execute the audit's recommended calls). Top-5 at-risk thunks
  implemented in xenolift_bios_gate: (1) ChangeClearRCnt C0:0x0A —
  flag stored per RC, PREVIOUS returned (BIOS semantics); SANDBOX
  LIVE: kernel calls rc=3 flag=0 (RC3 = BIOS delay counter, NOT RC2 —
  the Movie VSync suspect narrows); MMIO RC modes deliberately NOT
  poked (display/VSync proven, R144 park digest decides). (2) InitPAD
  B0:0x12 — SANDBOX LIVE: buf1=0x800625FC len1=34 buf2=0x8006261E
  len2=34 = EXACTLY the audit's predicted pair (decode confirmed);
  buffers NOT rewritten (do-not-poison: the settled pad handshake
  feeds them). (3) StartPAD B0:0x13 — LIVE, returns 1. (4)
  SetCustomExitFromException B0:0x19 — LIVE: kernel registers its
  exception-recovery hook @0x800578DC (new named symbol). (5)
  ReturnFromException B0:0x17 — silent (correct: HLE never raises CPU
  exceptions); loud [bxcep] marker if it ever fires. =GATE= digest.
  Sandbox 17/33 identical, zero regression.
- **R144** — PARK DECODE + ROOT-COUNTER TRACE. R143 MAC
  DIGEST ANALYSIS: (1) fn_80019ACC NOT spiking — 1 call/cycle = the
  NORMAL rhythm (Jos hypothesis #1 disproven: not a validation-fail
  cascade); (2) =MOVIE=/=MOD6= EMPTY — Module 6 NEVER entered; the
  wall is EARLIER than the Movie verification path; (3) THE PARK:
  watchdog in pump fn_80041B3C (r31=0x80041BB0) with NOTHING ARMED
  (pending=0 arm1=0) after a 23744B read @LBA 108861 completed +
  Pause INT2 + slot-1 event — the queued file-18 h2 request never
  dispatches (needs a slot-2 event whose SOURCE the runtime does not
  emit); slot-table entries 3 & 6 armed since early boot, NEVER
  dispatched; (4) cycle 1 of the overlay bootstrap worked as
  designed — the emitter REJECTED the stale 131072B capture; the run
  captured the FRESH 135KB window @0x8006F000 (next run = cycle 2 =
  module native at the correct base, first time including the
  0x8006FAF0-0x80070000 base region); (5) =ADPCM= GOLD: 12,839 valid
  blocks / 113 contiguous streams in the real sound bank (shift/filt
  headers + loop flags) + null-mute loop @0x1000 confirmed; (6)
  =SPUDMA= ch4 sources = the DECOMPRESSED ARCHIVE region 0x8006FD98-
  0x800AA6C8 (module base + 0x2A8) — the wds banks flow disc->RAM
  (decompressed)->ch4->SPU. BIOS_THUNK_AUDIT.md (agent finisher,
  12.9KB): 12/37 handled, 5 at-risk, 20 latent; #1 at-risk =
  ChangeClearRCnt C0:0x0A @0x8004B730 UNHANDLED (root-counter
  auto-clear — prime suspect for a nothing-armed park); exception
  subsystem (ReturnFromException/SetCustomExit) + InitPAD/StartPAD
  also unhandled. R144 adds: [park] state dump at the watchdog
  (slot table/slot-bits/handler cell 0x800564A8/queue nodes 0x80059F10-
  18/read struct 0x80059EF8/CD model state), [pump] context state
  lines (budget 24, slot-bits + t3/t6 + cells), [rcnt] ChangeClearRCnt
  arg logger, =PARK= digest. Sandbox 17/33 identical. GOTCHA
  (recurring class): variable names — cd_arm1 does not exist, the
  real name is cd_arm_int1_pending; scope errors caught by sandbox
  cc before shipping (the whole point of the sandbox).
- **R143** — MODULE 6 DIAGNOSTIC INSTRUMENTATION (Jos
  directive 07:41: gp/sp at entry, fn_80019ACC spike, drive-state
  drift, entry-offset validation). MODULE 6 IDENTIFIED (agent,
  qa/OVERLAY_SYMBOLS.md): Module 6 = MOVIE OVERLAY (movie.bin,
  file 18, 29,779B decompressed @0x8006FAF0-0x80076F43, entry
  0x800737EC = MovieModuleEntry) — a CD-ROM DIAGNOSTIC SUITE:
  MovieRunCdReadStressTestScreen 0x800704E8, MovieUpdateCdRead-
  StressTest 0x80070DCC, MovieAdvanceCdReadVerification 0x800712C4
  ("verifies async readback data and records mismatches"!), Movie-
  QueueRandomSectorRead 0x80071BA0 (explains the R136 NEW-TERRITORY
  read @LBA 239317 = a random-sector STRESS READ), MovieStartCdRead-
  TestOperation 0x80071C34, MovieAdvanceCdStressVSyncClock 0x80072428,
  MovieRunDiscChangeTest 0x80072480, MovieReinitializeCdAfterDisc-
  Change 0x8007293C. RESTART-LOOP SUSPECT: the Movie module's readback
  verification failing against our CD model -> abort -> boot main
  restart. R143 instruments: [mod6] REGS (gp/sp/ra + kernel-gp
  sanity check — overlays link kernel data via $gp; wrong gp = every
  module data access reads garbage), [mod6] DRIVE-STATE struct
  snapshot at entry (ptr5677C/slotbits56788/FE04/FDF8/FE1C — Jos
  drive-state-drift hypothesis), [movie] named hooks on all 8
  diagnostic fns (digest shows WHICH diagnostics run + order),
  [bootmain] per-cycle fn_80019ACC error-dispatcher SPIKE counter.
  =MOVIE= digest section. Entry-offset validation CLOSED by the
  agent: 0x800737EC = exact MovieModuleEntry in movie-overlay CSV.
  Sandbox 17/33 identical. SOUND_DRIVER_INTEL.md (agent, 26.9KB:
  WDS/SEDS/SMDS formats, SPU reg map, hle_spu gap audit) +
  OVERLAY_SYMBOLS.md (13.2KB, 51 movie symbols + window map) landed.
- **R142** — XENOGEARS-RECOMP INTEL APPLIED (Jos ask 07:29
  "study the repo, get info that helps the build"). Studied repo:
  game.toml (entry_pc 0x80019524, text 0x4A000 -> image end 0x8005A000,
  whole-image discovery, mod_function_entry_funcs 0x8004B54C, disc
  1x-never-instant, bios_hle, overlay capture-compile), seeds (667
  fns + verified decomp-backed promotions: WorkListUpdate 0x8001C9F8,
  cb_data 0x800431C0, HeapCalloc 0x80032B64, SoundSpuIRQHandler
  0x8003BFA0), bios-thunk inventory (SysEnqIntRP 0x80040ACC = our
  R92 IRQ-chain class), audio driver docs (WDS loading 0x80037FD8 =
  our ch4 pipeline: alloc SPU region -> async ADPCM upload -> header/
  preset records into driver RAM = our 0x840 staging block; 16-byte
  preset records = our 128B descriptor feeds), overlay inventory
  (files 13-18 = Battling/Field/WorldMap/Battle/Menu/Movie; file 18
  Movie sector 109158 14360B = EXACTLY our R132 read; battle-effects
  @0x801FC000 = our R116 windows; wds audio banks dir 0x01 files 2-5
  = our sound bank). CRITICAL FIX: modules load at 0x8006FAF0 — our
  capture window started 0x5B10 bytes TOO HIGH; R142 window =
  0x8006F000-0x8008FFFF (135KB), emitter maps at 0x8006F000, size
  gate rejects stale 131072B captures (misalignment hazard). All
  intel in RECOMP_INTEL.md; BRIEFING updated for agents. Sandbox
  17/33 identical.
- **R141** — ADPCM SAMPLE-HEADER SCAN AUTO-ANALYSIS (Jos ask
  07:27 "look at the remaining ADPCM sample headers"). Sandbox
  spu_ram.bin analysis: the fed region (2048B @0x0) = ZEROS — honest
  plumbing proof (the staging block at 0x80067210 was still empty
  when the sandbox halts at the frontier; the REAL bank only lands
  on the Mac where the CD pipeline fills staging). GOLD: 4 nonzero
  words @0x1000 = 07 07 07... x16 = the driver's NULL-SAMPLE MUTE
  LOOP (shift 7, filter 0, all 3 loop flags, zero samples) — the
  classic Sony sound-driver silent loop written via the SPU data
  port, faithfully captured by the module = expected memory-map
  detail CONFIRMED. R141 ships spu_adpcm_scan.py (pure stdlib):
  16-byte block validity (filter<=4, flag bits 3-7 clear, shift<=12),
  contiguous stream detection, loop-flag stats, null-sample check —
  self-tested on synthetic stream (8-block, shift 4 filt 2,
  loop-start/end detected). run.sh =ADPCM= section: next Mac digest
  auto-scans the REAL 152KB bank. Sandbox: 17/33 identical.
- **R140** — DRIVE-STATE TOUCHER MAP (Jos ask 07:23
  "search all references to 0x8005677C"). The fd driver's global
  struct block at 0x800567xx: 0x8005677C = PTR CELL initialized to
  0x1F801803 (CD data register address) by fn_80019524 boot init —
  the collector fn_800415B4 polls THROUGH it (&7 mask, read-twice-
  compare until stable, 8-byte response frame when request&0x20, R131
  disasm); 0x80056780 = RAM_SIZE cell; 0x80056788 = SLOT-BITS byte
  (r18 in every fd park; R130 kick reads it) — live writers: fn_80042088
  + fn_80041B24 set 2, fn_8004B54C clears 0; 0x800567A4-B4 = DMA cell
  pointers (runtime writes register addresses at boot). PHANTOM FOUND:
  the emitter mis-discovered the 0x80056700+ data pocket as CODE
  (disc1.c: fns fn_80056788/8C + L_80056700+ label chains + DISPATCH
  case entries) — data words decode as BGTZ $gp branches; INERT so far
  (no observed dispatch), flagged latent hazard. R140 adds both cells
  to the on-change watchers (22 cells) -> next digest names every
  drive-state WRITER live. Gotcha lesson: array resize must touch
  decl+init+loop together (first patch segfaulted: [20] decl ate
  [22] initializers silently). Sandbox: 17/33 identical, watch live.
- **R139** — CH4 STAGING CROSS-CHECK CLOSED (Jos ask
  07:11 "check the ch4 handler against the kernel-side staging
  blocks"). The sandbox [spu-dma] line proved it: ch4 source MADR =
  0x80067210 = EXACTLY the AllocateSoundHeapBlock evt=2 result from
  the =CLEAR= digest (block 0x80067210 size 0x840) — the kernel
  stages the sound bank in that sound-heap block and streams it via
  ch4. BCR 0x00200010 = 32 blocks x 16 words x 4 = 2048B/chunk,
  MADR +0x800/chunk — handler arithmetic MATCHES the staging layout.
  AUDIT FIXES (hardware fidelity): (1) BA=0 now means 0x10000 blocks
  per psx-spx DMA spec (was 1 — unobserved case, spec-wrong);
  (2) byte cap 0x10000 -> 0x200000 (RAM-size cap) — the old cap sat
  EXACTLY at the Mac's 65536B feed and could silently CLIP a larger
  chunk + desync the MADR advance the kernel reads back; the module
  wraps at 512KB internally (= SPU RAM wraparound). Plus =SPUDMA=
  digest section so the Mac's MADR/BCR lines (first 40 chunks,
  already in run.log, never surfaced) complete the staging cross-check
  with REAL values. Sandbox: chunk path unchanged (BA=32, 2048B),
  17/33 ticks/convs identical.
- **R138** — SPU MEMORY-MAP VERIFICATION (Jos ask 07:08
  "verify the 152,576 bytes against the expected memory map").
  VERIFIED: (1) arithmetic — the five digest feeds tile 0x0-0x25400
  CONTIGUOUSLY once the log filter's two HIDDEN 128B feeds are
  restored (filter hides chunks when total%0x8000 >= bytes; chain
  closes exactly: 0xF700+0x80=0xF780, 0x1F780+0x80=0x1F800), all
  feeds 128B-aligned, coverage 29.1% of 512KB, no wrap; (2) module
  placement — replayed the full 7-feed chain into hle_spu: 14/14
  boundary probes pass, transfer_addr=0x25400 exact, sequential
  contiguity confirmed (my own test harness had 2 probe bugs —
  probed 0x8FF expecting feed-2's tag; feed 2 ends 0x87F. Module
  innocent.); (3) 65536B feed = exactly the 0x10000 ch4 cap — the
  kernel's own chunk size, no clipping evidence. NEXT-LEVEL CHECK
  (shipped): R138 adds the definitive verifier — full SPU RAM
  snapshot at BOTH halt paths (spu_ram.bin, 512KB, via
  gpu_dump_capture's call sites) + [hle-spu] map line (dma total +
  last write pos; spu_wr_pos hoisted to file scope) + =SPURAM=
  digest — when the Mac run lands, I scan the dump for ADPCM sample
  headers/bank structure to confirm the sound bank matches the
  expected VAB layout. Sandbox: snapshot fires (524288B file,
  2048B fed), ticks/convs 17/33 identical.
- **R137** — CONTEXT-INDEPENDENT COLLECTOR GATE. R136 Mac
  digest = DEEPEST BEHAVIORAL RUN: SPU module took 152,576 bytes of
  REAL ch4 sound-bank DMA (5 feeds, kernel's actual audio uploads),
  GTE CTC2 moves live, reads-done 1774, Pause-INT2 chained, and the
  kernel STAGED its first deep-disc read (FE04=LBA 239317, FDF8=9048,
  FDFC=1 — game-data territory far past the 108893-109158 boot
  files). New park: r31=0x80041BB0 = INSIDE the pump fn_80041B3C =
  the FOURTH collector-caller context the tick gate missed (wait-loop
  0x80028704, fd 0x80041CA0, legacy 0x80042398, pump-internal).
  FIX: collector gate now context-INDEPENDENT — ANY collector call
  with pending!=0&&arm1==0 converts via the proven handler pair (busy
  guard + budgets unchanged); NEW CONTEXT lines name unseen callers
  (sandbox: 3 flagged, incl. 0x80042398). Plus [newread] watcher
  (every fn_80029690 READ ISSUED outside boot range 108804-109165)
  + =GTE=/=NEWREAD=/=CTX= digest sections. Sandbox: frontier intact,
  17 ticks / 33 convs (identical), GTE moves confirmed.
- **R136** — GTE EXECUTES + PROFESSOR CURRICULUM (Jos
  directive 06:58 "like a professor grading a paper — teach the sub
  agents, not only when they make a mistake but the data they should
  know so they do not poison the runtime or build"). GTE fix agent
  DELIVERED: root-caused the RTPS sf-inversion (mac3 >> ((1-sf)*12)
  = shift 0 when sf=1 → depth never divided → SZ3 saturated 65535 →
  wrong SX2/SY2/IR0/bogus FLAG) + a 64-entry disasm name-table
  off-by-one (missing 0x1A entry). Professor re-verified: 8/8 exit 0.
  INTEGRATED: COP2 moves (MFC2/CFC2/MTC2/CTC2) + LWC2/SWC2 + CO-form
  math ALL route through hle_gte; the GTE MATH halt-class is RETIRED —
  commands execute. Kernel CTC2 moves confirmed feeding the module in
  sandbox; ticks/convs identical (17/33) = zero regression. ALL FIVE
  HLE MODULES NOW LIVE (SPU/MDEC/memcard/GPU/GTE). CURRICULUM: 5 case
  studies with root causes + graded rules + standing do-not-poison
  data + delivery protocol appended to hle/BRIEFING.md (233 lines) —
  every future agent launches into a textbook, not a blank slate.
- **R135** — GPU HLE FINISHED (Jos directive 06:54
  "finish the GPU rebuild task based on the leftover data"). The
  GPU rebuild agent left hle_gpu.c (23KB) + hle_gpu.h + test_gpu.c
  on disk. VERIFY-FIX-INTEGRATE: 14/16 tests passed as delivered;
  the 2 CLUT textured-rect failures = TWO bugs: (1) TEST bug — the
  CLUT upload declared 16 halfwords but sent 14 (7 words), the
  state machine (correctly, hardware-faithful) ate the next
  command's header as blit data and the texture upload was NOP'd
  (one-word fix); (2) MODULE bug — size_code decoded from the
  command BYTE ((cmd>>27)&3 = always 0) instead of the WORD
  (w0>>27)&3, so EVERY rect 0x60-0x7F was treated as variable-size
  and the 1x1/8x8/16x16 opcodes (0x68-0x7F) silently waited for a
  size word that never came = rect commands never executed. Fixed
  both sites → 16/16 PASS. INTEGRATED (dual-feed, zero-regression):
  every GP0 (0x1F801810) / GP1 (0x1F801814) write now ALSO feeds
  hle_gpu's full interpreter (rects, quads, lines, copy, texpage,
  drawing area, CLUT sampling) while the proven R125 capture path
  keeps driving the live viewer/snapshots; gpu_init() at boot;
  [hle] gpu-writes counter at the watchdog dump. Sandbox: builds
  clean, frontier intact, ticks/convs identical to R133/134 (17/33).
- **R134** — HLE MODULE INTEGRATION (Jos directive
  06:49 "Integrate sub agents work"). VERIFICATION FIRST caught the
  sub-agents overclaiming "compile-verified": GTE test FAILED (real
  RTPS math bug: SX2 160 vs 210, SY2 120 vs 145, SZ3 saturating
  65535 vs 512, IR0 8 vs 1024, FLAG wrongly set), SPU test
  SEGFAULTED (ASan: TEST-HARNESS bug — pcm[100*2] buffer but
  generate(500); fixed the harness, then 6/6 SPU tests PASS),
  MDEC test tangled with memcard module + missing -lm (fixed: MDEC
  + memcard 27/27 PASS). INTEGRATED (additive, zero-regression):
  hle_spu + hle_mdec + hle_memcard compile into the runtime; SPU
  register writes 0x1F801C00-DAF feed hle_spu_port_write (SPU reads
  + SPUCNT/SPUSTAT keep the existing proven behavior); ch4 sound-
  bank DMA now copies REAL bytes into the module's SPU RAM (was
  consume-only); MDEC 0x1F801820/824 reads served by hle_mdec;
  memcard reset at boot (SIO routing DEFERRED — the working pad
  handshake is untouched until the title/menu phase); =HLE= digest.
  Sandbox: SPU module ENGAGES (kernel writes 0x1F801D80+ reverb
  regs, 1 DMA feed of real bytes), ticks/convs IDENTICAL to R133
  (17/33), frontier intact. GTE HELD OUT — fix agent relaunched
  with the exact failing values.
- **R133** — R132 Mac = DEEPEST RUN: FIRST COMPLETE
  file-18 read (14360B = 7 sectors LBA 109158-109165, FDF8 14360->0,
  "read complete: FE1C 5->0 releasing the file layer"), kernel
  advanced into NEW tasks (0x80040A8C, 0x8004C970, 0x8004D028) and
  holds OVERLAY addresses (r11/r15 = 0x80076F3B/43) = module data
  being touched. The narrowed re-prime collapsed the treadmill:
  100000 -> 38687 (survived the run). Pause INT2 + GetStat cycle
  complete; =MOD6= clean (grep fix verified — no false positive).
  NEW WALL (third instance of the tick-context class): park at
  r31=0x80042398 = the LEGACY CD service loop 0x80042390 —
  structurally IDENTICAL to the fd processor (jal 0x800415B4
  ReadCdInterruptState at 0x80042394, slot-bits dispatch of h4 via
  cell 0x800564AC / h2 via 0x800564A8) — with an armed-but-
  undelivered INT3 (pending=3, resp_n=1, drive idle, last_cmd
  GetStat, FDF8/FE1C/FDFC all 0). The gate only ticked callers
  0x80028704 (wait-loop) + 0x80041CA0 (fd); the legacy loop's
  collector calls never converted its armed INT -> collector
  returned 0 -> eternal re-entry. R133: tick gate extended to
  r31=0x80042398 (tick log now prints r31 generically). Sandbox:
  13 fd-context + 4 legacy-context ticks, conversions fire in the
  new context, frontier intact, re-primes 98.
- **R132** — R131 Mac =TICK= exposed the RESPONSE-FIFO
  TREADMILL: reprimes-used 100000 EXHAUSTED. The R123 re-prime
  condition included cd_read_active, so during streams EVERY status
  poll refilled the response FIFO with a fake byte — the kernel
  consumed them in a poll treadmill for ~10 min (40 watchdog
  defers, park-tick-alive), the stream stalled mid-read (sector
  108800 loaded, FIFO never drained, fd collector spin), budget
  died, spin froze, watchdog fired. Kernel disasm confirms: fd
  processor 0x80041C98 dispatches fn_800415B4 ReadCdInterruptState
  (PsyQ libcd) whose internal loop polls the drive-state byte
  (ptr cell 0x8005677C, &7, read-twice-compare) until stable, then
  copies an 8-byte response frame when request&0x20. The kernel's
  response architecture is FRAME-based (per-command sequences),
  ours is byte-based — but per psx-spx the frames the kernel uses
  (GetStat/Setloc/ReadN INT3 first = [stat]; INT1 data-ready =
  [stat] ✓ already armed) are 1-byte, so the fix is NOT frames:
  R132 = re-prime only at DRIVE-IDLE (!read_active — during
  streams the native INT1 machinery owns the loop), Init (0x0A)
  INT2 second response (psx-spx: Init = INT3(stat)+INT2(stat),
  same shape as the R124 Pause fix — the kernel ISSUES Init),
  watchdog defers 40 -> 150 (~37 min) so long module streams
  complete, =MOD6= grep tightened (R131 banner contained the
  literal [mod6] tag = digest false positive — Module 6 was NOT
  reached). Sandbox: re-primes 1078 -> 98, kicks 2, frontier OK.
- **R131** — R130 Mac = BREAKTHROUGH + new stall. The kick
  cascaded: the kernel left the old 3-file cycle and streamed a ~116KB
  read (FDF8=116208, sectors 108804+, FDF8 tail 99824) INTO THE
  OVERLAY REGION (dests 0x800883F0-0x8008BBF0, +0x800/sector) — the
  Module-6 population path exactly as the HANDLER_MAP decode
  (hle/qa/HANDLER_MAP.md) describes: boot handler reads
  install_required_flag (12(s1), cell 0x80018088, module descriptors
  @0x8001808C), enqueues file 18 async (NO wait loop, 0-cycle
  tolerance), then jalrs into Module 6 entry 0x800737EC (ra=0x80019C0C)
  expecting the CD to have populated the overlay; unpopulated → instant
  return → ~5.5Hz restart loop. R130 stalled MID-STREAM at sector
  108812/49-to-go: conv_budget=400 AND reprimed_budget=400 both
  EXHAUSTED (final fd-tick: pending=1 arm1=0 resp_n=0, no conversion
  or re-prime line; kernel parked in fd collector, FIFO fully
  drained, next sector never loaded). R131 = BUDGET LIBERATION: conv/
  re-prime/kick budgets 400 → 100000 (machinery proven over 1000+
  cycles; sandbox alone used 1078 reprimes — the old cap was
  throttling even sandbox runs). =TICK= now prints convs-used/
  reprimes-used/kicks-used. New =MOD6= digest + [mod6] watcher on
  0x800737EC (HANDLER_MAP success criterion: execution REMAINS in
  Module 6, fn_80019ACC drops from 5.5Hz to 1 call).
- **R130** — R129 Mac =SLOT= data cracked the mechanism:
  the file-18 archive enqueue RUNS (caller 0x80029AD4 = fn_80029690's
  tail), h2 = the request STEPPER (each read advances via h2 phases,
  FE1C cell = sub-request phase 0/1/2, driven by slot-2 events from
  the native command chain), and fn_8004111C writes h2's address into
  the slot-handler cell 0x800564A8 on enqueue — meaning "next slot
  event dispatches h2 to start the queued request". For file 18 the
  previous read completes, the drive idles, and NO event ever wakes
  h2 — the request starves until the boot handler restarts. The CD
  callbacks 0x8003A68C/0x8003B084 registered by fn_80029690 never
  fire either (no [slot] callback lines). R130 = QUEUED-REQUEST KICK:
  at fd-tick, when an unserved FE04 request LBA exists at drive idle
  (pending/scheduled/arm1 all 0), discard the stale FIFO leftover and
  dispatch h2 exactly as the wait loop does. h2 is safe to dispatch
  spuriously (the kernel itself runs idle h2 passes, =SLOT= proof).
  Sandbox: 5 kicks fire, no regression, 0x80200000 frontier intact.
  Two decode sub-agents re-launched to verify h2's exact start
  semantics + the boot-handler restart condition against the
  disassembly while the Mac run executes.
- **R129** — boot wall narrowed to the slot queue. R128 Mac data:
  file 18 RESOLVES (LBA 109158, size 14360, FAT @0x80010004 in the EXE,
  dir table @0x80018004, offset 23 set correctly by 4 Select calls/cycle).
  fn_80029690 (StartArchiveRead) runs, registers CD callbacks
  0x8003A68C/0x8003B084, bumps counter 0x8005A488, ENQUEUES via
  fn_8004111C(2, node@0x80059F18) into the CD driver slot tables
  @0x80056420 — then returns. The read is never dequeued: no Setloc to
  109158, ArchiveStartQueuedReads (fn_80029AFC) never entered (its only
  EXE callers are skin loaders 0x8001AD4C/0x8001B000/0x8001B158/
  0x8001BC28, pointer-dispatched by the overlay). FE1C redecoded: it is
  the ACTIVE FILE# cell, not a status flag. R129 probes: [slot]
  watchers on the enqueue, the h2 starter (fn_8002A68C), both CD
  callbacks; cell watches on FE1C/FE10/0x8005A488/0x800564A8. Two
  analysis sub-agents decoding the slot machinery + boot-handler
  restart condition in parallel.
  SANDBOX LESSON: array-expansion bug (hc_addr[16] decl vs 21
  initializers, -w hid the warning, loop k<20 read OOB -> segfault).
- **R128** — archive FAT decode complete. The 0x80028xxx range
  = the kernel's archive filesystem (symbol names recovered): FAT with
  7-byte entries [3B LBA][4B signed size] at *(0x8004FDF0); a 16-bit
  DIRECTORY table at *(0x8004FDF4); SelectArchiveDirectoryEntry(a0,a1)
  reads dir_table[a0+a1], stores entry-1 as the ACTIVE ARCHIVE OFFSET
  (cell 0x8004FE14, zeroed on negative); every file lookup indexes
  FAT[(file# + offset - 1)*7]. NEGATIVE sizes = directory markers
  (declare following-record counts). MeasureArchivePayload returns the
  raw signed size; ReadArchiveMemberIntoBuffer bails -3 on <= 0 without
  issuing any CD command — matching the flat reads-done perfectly.
  WALL THEORY: module install requests logical file 18 with a stale or
  missing directory selection -> wrong FAT entry (or a directory
  marker) -> -3 -> boot restart. R128 probes: [arc] watchers on
  SelectArchiveDirectoryEntry + ArchiveStartQueuedReads, cell watches on
  FAT base / dir-table ptr / archive offset / host-route gate
  (0x8004FE48 nonzero = debug host route, bypasses FAT), and a one-shot
  FAT neighborhood dump (entries 12-21) at the first file-18 request.
- **R127** — file-table gate trace (shipped, superseded by R128 same
  session). Decoded fn_800295D8:
  size lookup (fn_80028738) -> -3 bail if size<=0 -> sync wait ->
  LBA lookup (fn_800289D0 -> 0x8004FE04) -> size (fn_800288EC ->
  0x8004FDF8) -> read (fn_80029690). File table = 7-byte entries at
  *(0x8004FDF0): bytes[0..2]=LBA 24-bit LE, bytes[3..6]=size; index =
  file# + *(0x8004FE14) - 1. The 2660-byte staged file at 0x800AFC98 is
  the table itself (380 entries). [ftab] logs entry 18 raw + each gate.

## Architecture knowledge recovered so far

- Sound heap: 0x80065B10-0x8006BE00, first-fit, limit written by the
  kernel itself post-R94. AllocateSoundHeapBlock=0x80038F18.
- CD request struct: 0x8005A218 chain, IRQ handler pair
  0x800409E4/0x80040A4C, collector fn_800415B4, INT processor
  0x80041C60.
- Boot state cell 0x80059340 holds dispatched state fn addresses;
  installer loop states 80032E94 (decompress) ↔ 800197EC/8001B9AC.
- CD INTs: INT1=DataReady, INT2=Complete (Pause/Seek), INT3=ack,
  INT5=error. GetStat/GetLocL/GetLocP/Setmode = 0x01/0x10/0x11/0x0E.

## End goal

Extract and rebuild the game as portable code for Unreal/Unity —
the recompiled C and HLE runtime are the validation harness and the
reverse-engineering documentation, not the final product.

## BRIDGE v5 REFACTOR COMPLETE (2026-09-11, Jos: "finish refactoring the bridge to v5")
- v5 upgrades over v3/v4: `test` self-test mode (one command = full
  diagnosis w/ exact HTTP codes + fixes); directive extractor hardened
  vs response shapes (raw text + recursive JSON walk + brute unescape —
  v3/v4 regex fails on JSON-escaped newlines = the silent-killer class);
  GET-poll fallback; 80k digest cap; per-cycle digest archive; 5xx retry
  x5; XENOLIFT_API_BASE env override (mock testing); python-zipfile
  extract fallback when unzip is absent; download timeout 120s.
- SANDBOX E2E VERIFIED against a mock inbox (local HTTP server): full
  cycle PASS — announce POST -> directive parsed -> package download +
  extract -> block executed -> banner archived -> digest POSTED (content
  confirmed in mock log) -> clean park. Failure path also verified
  (mock down: 15 retries over 80s, clear FATAL, exit 1).
- Delivered: public download (curl to ~/Downloads) + rides the xenolift
  zip. Launch: caffeinate -i ~/Downloads/xenolift-bridge5.sh 45

## R150 (2026-09-11, cycle-1 digest verdict)
R149 Mac cycle 1 (16:07) VERDICT: (1) the R148 GPU stream is a RESUBMIT
LOOP of one 4-word packet (tag 0x040AA6B0, buffer 0x801FFF98, caller
0x80019E78) submitted 11253x = the boot error-screen redraw, NOT
steady-state rendering. (2) The phase commit for the Movie module fires
every cycle (fn_80019ACC idx=6, cb registered, install 0x31 verdict ok)
but the phase global cell 0x800592C0 stays -1, the teardown 0x30
follows immediately, and the module entry 0x800737EC NEVER dispatches
(phasecb/mod6/movie sections all empty). (3) The final park is the fd
leaf-spin (r31=0x80041CA0, polling ISTAT r3=0x1F801070 + CD reg
r4=0x1F801803) holding pending INT1 (data_n=2060, LBA 108886, arm1=0)
invisible to the kernel — our CD interrupts live at the BIOS-event
layer and never assert I_STAT bit 3.
R150 FIXES: (a) ISTAT leaf-spin rescue — after 16 polls with cd_pending,
assert I_STAT bit 3 (hardware truth: the bit asserts while the CD
controller holds an interrupt; kernel ACKs by writing 1s);
(b) on-change watchers on the phase global 0x800592C0 + flag 0x800592BC
(watchers 22 -> 24 — hc_addr decl resize caught by -fsyntax-only, the
R140 decl+init+loop lesson class); (c) teardown caller + install-state
trace (idx cell 0x80018088, desc[6]/desc[0] callbacks at 0x30);
(d) gpuprim command-byte decode.
Sandbox note: platform bash retries created a mixed-state runtime.c —
recovered by restoring the R149 runtime.c from the shipped zip and
re-applying patches idempotently (zip = recovery point; always diff
against it).
