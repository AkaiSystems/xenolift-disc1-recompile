# State machine: the mode dispatcher is never reached, and the game reboots itself

Built on the prior team's `hle/qa/GAMEMODE_INTEL.md` (confirmed against the Noah
decomp and `annotations.csv`). R1500 `[chaincam]` counts entries to each step.

## The dispatcher, decoded linearly (0x80019AFC..0x80019BFC)
```
80019AFC  r17 = 0x8002808C + (*(0x80028088) << 4)      &descriptor[state]
          ResetGraph, DrawSyncCallback(0), SetControllerUpdateCallback(0),
          DrawSync(0), VSync(2)
80019B3C  HeapRelocate(descriptor.endOfZeroInit + 0x800)
80019B44  HeapResetUser
80019B4C  if (descriptor.needOverlay == 0) goto 80019BD0
80019B5C  ClearMemory(startOfZeroInit, endOfZeroInit)
80019B74  LoadGameStateOverlay(*(0x80028088))            = MountGameStateModule 0x800199CC
80019B80  ArchiveCdDataSync                              = WaitArchiveCdData 0x80028A60
80019B90  LZSSDecompress(block, *(0x80028084))          = UnpackCompressedBuffer
          DrawSync, VSync, Enter/ExitCriticalSection, FlushCache
80019BD0  RestoreResidentExecutionRegisters             JOIN POINT, not an abort
80019BDC  HeapRelocate(endOfZeroInit + 4)
80019BE4  HeapReset                                     = ClearHeapRuntime 0x80031A30
80019BEC  ControllerResetState
80019BF4  ChangeGameState(0)                             = CommitGameStateTransition
80019BFC  xenolift_dispatch(descriptor.entryPoint)      ENTRY DISPATCH
```
**Correction to GAMEMODE_INTEL.md's framing:** `0x80019BD0` is not an abort step.
`RestoreResidentExecutionRegisters` resets SP/S8/GP before entering a mode and is
reached on both the overlay and no-overlay paths.

## Finding 1 — the dispatcher is never entered in the current build
`[gdisp]` (hooked at `0x80019AFC`): **0 in all 6 R1500 trials.** `HeapRelocate` is
called twice on every dispatcher pass, yet the independent R1108 receipt shows it
entered once in one of six trials. `ChangeGameState`, the entry dispatch and
`MovieEntry` are all 0. The 23 `[gdisp]` lines seen earlier came from older
builds.

So the question is not "why does the movie-mode dispatch fail". The game does not
reach the resident mode dispatcher at all.

## Finding 2 — the game reboots itself
`RestoreResidentExecutionRegisters` has five callers; the active one is
`xenolift_fn_80019524_start`, the program entry. `[bootmain] boot main entered
(restart?) caller=0x80019578` counts: 2 in most runs, **37 in one**.

The runtime deliberately re-enters `start`: four sites set
`xenolift_churn_pend = 0x80019524`, each after restoring a pristine EXE image and
re-applying library patches, with the comment "window keeps exploring":
```
R772       guest abort()          -> restart
R769/R770  halt / exit            -> restart
R765       fault-walk exit        -> restart
R777       crash-kit poison HALT  -> restart
```
It was a resilience choice for unattended runs. The cost: a fatal guest error is
converted into a reboot, and each boot attempt re-hits it.

In these runs the four doors fire rarely (once each, in one trial). Most
re-entries come from the churn-anchor recovery path.

## Finding 3 — bad-address faults are data used as code (but rare)
`[fault] computed-garbage address` in 4 of 18 runs, 1-2 each:
`0x2D2D2D29` (ASCII "---)"), `0x0F000F4A`, `0x50006385`, `0x1FF3060F`. These are
data bytes used as jump targets, which is what misloaded data produces. They are
the minority case; `[busyrecover]` (9-36/run) counts every resume at the recovery
anchor, not only faults — I initially conflated the two.

## Corrections made while getting here
- `[phase]` (R661) reads `0x800592C0`/`0x8005FAEC`, the pair GAMEMODE_INTEL.md
  calls inert, not the real state cells `0x800692C0`/`0x80028088`. Its
  `cur=0 idx=0` says nothing about the game state.
- My R1500 `loop=0` counted `0x80019ACC`; restart re-entry lands mid-function at
  `0x80019AFC`. Wrong address, not a missing loop.

## Tooling for the next step
`XENOLIFT_FIRSTFAULT_STOP=1` halts at the first computed-garbage recovery with a
full dossier (regs/code/data/backtrace) before any reroute or image restore. It
only triggers on that path, so it covers the minority case above.

## Next
Trace `start` -> boot main -> ... -> `RunResidentGameLoop` to find where boot
diverges before the dispatcher.
