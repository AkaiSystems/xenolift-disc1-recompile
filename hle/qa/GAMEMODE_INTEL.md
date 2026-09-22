---
title: "Game-Mode State Machine Intel"
summary: "Full static + external-source decode of the Xenogears game-state machine (commit/dispatch/mount), the two-table structure, the uninitialized working-table problem, and the Noah decomp confirmations."
---

# GAMEMODE_INTEL.md — the game-state machine, decoded (R152 era, 2026-09-11 17:10)

## The mechanism (raw-MIPS-verified)

CommitGameStateTransition fn_8001996C(state) — writes the REQUESTED state to the
GAME table idx cell 0x80028088 (lui r1,0x8002; sw r4,0x8088(r1)), then compares
against the CURRENT state cell 0x800692C0 and releases the pending module heap
block at 0x800692BC when changing states.

Resident game loop dispatch chain (inside RunResidentGameLoop 0x80019ACC, region
0x80019AFC-0x80019C10, raw-verified):
1. LW 0x80028088 -> current requested state
2. descriptor = 0x8002808C + state*16 (GAME table), saved in s7
3. MountGameStateModule(state) @0x80019B7C — early-exits if cur==req (cells
   0x800692C0/0x800692BC); else: module file# from table 0x8005EAA0+state*4,
   MeasureArchivePayload, AllocateHeapBlock(size,1) -> block stored 0x800692BC,
   ReadArchiveMemberIntoBuffer(file#, block), archive-select restore, returns block
4. WaitArchiveCdData
5. unpack dest = LW(0x80028084)  <- dest cell inside the same working region
6. UnpackCompressedBuffer(block, dest)
7. GPU wait, VSync, MoveHeapAllocation, ClearHeapRuntime, ClearControllerSnapshots
8. entry dispatch @0x80019BFC: r2 = LW(s7+0) = descriptor[0] = the module
   entryPoint -> jalr -> loop continues (0x80019C14 calls RunResidentGameLoop again)

## The two tables

- ROM table @0x8001808C ("boot table" — what ALL our hooks watched since R130):
  static disc data, verified byte-for-byte vs live dumps. 7 entries x 16 bytes
  (entryPoint, startOfZeroInit, endOfZeroInit, needOverlay), valid 0..6; the old
  "[7] cb=0x635C3A63 garbage" = reading PAST the 7-entry table (no entry 7).
- GAME table @0x8002808C (what the dispatcher actually reads): the WORKING copy.
  Disc image at that VA contains resident CODE (functions around
  ArchiveVisualizeHostIoRetry 0x8002804C) — at rest NOT table data. Disc-wide
  byte-pattern search: the 7-entry descriptor table exists EXACTLY ONCE in the
  image (VA 0x8001808C). No code in the recompiled kernel or overlay writes
  0x8002808C-0x8002810C or 0x80028084/0x80028088 in absolute/constant-offset
  form — the initializer is either runtime-dynamic (pointer-carried /
  decompressed payload) or a step our boot never reaches.

## What the state machine should do (external-source confirmed)

TCRF (tcrf.net/Xenogears): "A kernel boot menu exists in the final game and can be
reached by setting the bootmode to 0" — bootmode defaults NON-zero in retail ->
boot skips the menu and requests a state directly (our run: 6 = Movie).

Noah decomp (github.com/yaz0r/Noah — complete Xenogears reimplementation),
NoahLib/kernel/gameMode.cpp + kernelBootMenu.cpp (fetched -> hle/qa/external/):
- gameModes[7] = { kernelBootMenu, fieldEntryPoint, battleEntryPoint,
  worldmapEntryPoint, unimplementedGameMode, enterMenu, movieEntryPoint } —
  EXACTLY our 7 states; sBootMode {entryPoint, startOfZeroInit, endOfZeroInit,
  needOverlay} = our 16-byte descriptors; needOverlay=1 for field/battle/
  worldmap/battling/movie.
- kernelBootMenu() prints " XENOGEARS Kernel MENU", cursor selection calls
  setGameMode(selected+1), then bootGame(0) -> gameModes[mode].entryPoint().
- setGameMode = CommitGameStateTransition equivalent; clears cached overlay on change.
- Flow: boot(menu) -> select -> commit(N) -> mount overlay N -> entryPoint().

## RESOLVED LIVE (cycle 5, 17:01) — R154 patch shipped

CORRECTION of the earlier decode: CommitGameStateTransition writes the ROM/idx
cell 0x80018088 (live [phase]: 0 -> 6). The dispatcher (0x80019AFC) reads the
WORKING idx cell 0x80028088 and descriptors from 0x8002808C — both raw disc
code, NEVER initialized at runtime. Every cycle the dispatcher computed a wild
descriptor pointer (state 0xA7A00032 << 4 + 0x8002808C = out-of-RAM), ran the
GPU-prep steps, MoveHeap/ZeroMemory with garbage ranges, then called
MountGameStateModule(r4 = LW(0x80028088)) — and the chain aborted into the
restart step 0x80019BD0 (RestoreResidentExecutionRegisters -> boot main)
BEFORE the entry dispatch 0x80019BFC ever executed. [phasecb]/[mod6] empty
because the dispatch never ran. reads-done frozen at 2049 the whole time:
the module file-18 read is issued (LBA cell FE04=109158) but its sectors
NEVER stream; the park shows FE04 clobbered to 109142 (108886+256?) at halt.

R154 FIX (runtime, additive): (1) boot-init installs the working table —
7 descriptors copied ROM 0x8001808C -> 0x8002808C, idx mirrored from
0x80018088 ([gtab-init] banner line); (2) dispatcher-entry hook re-mirrors
the idx every resident-loop pass ([gdisp] idx mirror lines); (3) mount hook
sets the unpack-dest cell 0x80028084 = module load base per state
(0x8006FAF0; Menu state 5 = 0x801C5000) — cycle-5 live value was the disc
word 0xAFB100EC, nonsense; (4) watchers on 0x8004FE04 (LBA cell, the
clobber suspect) + 0x8004FE1C (file# cell) — 30 total.

EXPECTED NEXT DIGEST IF CORRECT: [gdisp] dispatcher state=6, ENTRY-DISPATCH
desc=0x800280EC cb=0x800737EC, [phasecb] MovieEntry 0x800737EC FIRES, [mod6]
logs, bootmain restarts STOP, and the Movie diagnostic begins its CD
readback stress test (reads-done should finally move past 2049; FE04
watcher shows who writes what).

## OLD OPEN QUESTION (kept for the record)

Our run: commit(6) every tick OK, mount chain runs fully OK (archive selects,
file-18 read issued+completed, AllocateHeapBlock, decompress verdict OK) — but
the module entry NEVER dispatches ([mod6]/[phasecb] empty). Prime suspect: the
working game table + dest cell (0x80028084-0x8002810C) are never initialized at
runtime, so (a) the unpack dest may point somewhere wrong (module lands
off-target — explains why native-capture was needed to see module bytes), and
(b) descriptor[6].cb reads code-garbage -> dispatch to a phantom -> no movie
entry -> boot restart.

R152 instruments (shipped 16:52, pkg 2aec5a405): watchers on 0x28084/0x28088/
0x692BC/0x692C0, [mount] trace with LIVE game-table dump, unpack-dest site
trace, [phase] reads the real cells (old 0x800592xx pair is inert).
- If live game table = code-garbage -> find/build the initializer (candidates:
  copy ROM table 0x8001808C->0x8002808C + set 0x80028084 = module load address;
  BUT first hunt the original initializer — likely a GameBootstrap branch we
  skip, or a decompressed payload landing there).
- If live table VALID -> abort is between unpack and dispatch (WaitArchiveCdData /
  heap steps) — the [mount] trace timestamps will show where the chain dies.

## Also corrected (important)

fn_800324B8 = SetHeapContentCategory (heap allocator) — the 0x31/0x30
"install/teardown bounce" tracked since R114 is normal heap bookkeeping around
the module decompress, NOT install semantics. R143-era "installer bounce"
interpretation is retired.

## External sources used (for agents)

- yaz0r/Noah — complete US Xenogears decompilation/reimplementation.
  NoahLib/kernel/* (gameMode, kernelBootMenu, gameState, decompress, events,
  filesystem, DTL, TIM, gte, graphics), NoahLib/movie/* (movie, strPlayer,
  mdecDecoder = the whole STR/FMV pipeline in readable C++). Local copies:
  hle/qa/external/noah_*.cpp. For ANY kernel/CD/GPU/SPU question, search this
  repo FIRST.
- ladysilverberg/xenogears-decomp — matching decomp of SLUS 006.64 (our exact
  disc), in progress; field module largely done, boot kernel not yet — watch it
  for future symbol harvests.
- TCRF Xenogears pages — debug room, unused text, kernel boot menu lore.
- annotations.csv (project root, from OpokXeno/xenogears-recomp) — 1,219 named
  functions; confirmed: CommitGameStateTransition, MountGameStateModule,
  RunResidentGameLoop, GameBootstrap, RestoreResidentExecutionRegisters,
  UnpackCompressedBuffer, WaitArchiveCdData, DumpMainRamToPc (0x80019C2C — the
  kernel can DUMP FIRST 2MB OF RAM to a dev PC; potential debugging aid).
