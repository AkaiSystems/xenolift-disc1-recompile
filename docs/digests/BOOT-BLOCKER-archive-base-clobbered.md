# Boot blocker traced to one read — and a clobbered archive base

Bisection from `start` down to a single failing read, each step its own run
(R1501-R1508 cameras, 150s serialized batches, `run.log.raw`).

## The chain
```
start (0x80019524)
 └ GameBootstrap (0x80019578)           ~40 init calls, all succeed
    └ StartNewGame (0x8001BB50)          every failing boot dies here
       └ InitializeNewGameState (0x8001B970)   entered every attempt, rarely returns
          └ ArchiveReadFileToBuffer(archive 16, file 3)   hangs inside
             steps: 1 DecodeSize  2 CdDataSync  3 DecodeSector
                    4 DecodeAlignedSize  5 ArchiveReadFile  6 CdIntToPos
```
Target file: archive idx 16 / file 3 — the 9,048-byte (0x2358) initial game-state
image that INGS memmoves to 0x8007D634.

Whenever that read returns, boot continues through the splash screen,
`ChangeGameState` and **`MainLoop`** — reached in several runs across batches
(t=87-138s). This is the first time `MainLoop` has been reached this session.

## Ruled out along the way (each by measurement)
- the archive CD wait inside `StartNewGame` — not reached in failing boots
- the archive CD wait inside `InitializeNewGameState` — not reached in 5/6
- `PCopen`, the PsyQ dev-PC file-server path — 0 calls in all runs
- a NULL directory pointer — see "wrong cell" below

## The mechanism
`ArchiveSetIndex` (annotated SelectArchiveDirectoryEntry) is:
```
table = *(0x8004FDF4)             ; 0x80050000 + (int16)0xFDF4, sign-extended
*(0x8004FE14) = LHU(table + idx*2) - 1   ; current archive base
```
Measured on the REAL cells (R1507):
- `0x8004FDF4 = 0x80018004` — valid.
- `ArchiveSetIndex(16)` reads entry `0x0B22`, so it sets `FE14 = 0x0B21` (2849).
- When the read resolves file 3, **`FE14 = 0x17` (23)**.

The base is overwritten between selecting archive 16 and reading from it, so
"file 3" resolves in the wrong archive. That explains why the same logical read
resolved to different disc LBAs across runs (250369, 108754).

## The intruder (R1508)
Every `ArchiveSetIndex` call made while the INGS read is in flight:
```
trial 1:  ra=0x800858A8  archive=4  guest depth=2   x8
trial 3:  ra=0x800858A8  archive=4  guest depth=2   x8
```
- Both runs were parked at step 2 (the inner `ArchiveCdDataSync`), so the
  intruder runs **during the CD wait**.
- Depth 2 = nested inside other guest code, i.e. a callback run while waiting.
- Trial 1 had a single boot attempt, so this is not a reboot artifact.
- `0x800858A8` is not set as a return address anywhere in the emitted C: the
  caller is overlay code executed by the overlay interpreter.

Trial 2's intruders (`ra=0x8001967C`, archive 1, depth 0) are `GameBootstrap`
after a reboot — my in-flight flag survives reboots. Artifact, excluded. Trial 2
also reads a different directory entry for archive 16 (`0x0A22` vs `0x0B22`),
recorded but not yet explained.

## Working hypothesis (NOT yet proven)
The emulated CD wait is far longer than real hardware's, so a periodic callback
in installed overlay code — plausibly a sound/stream loader, given archive 4 and
the boot's sound loads — runs many times inside it and does its own archive
selection, clobbering the shared base. On real hardware the window may be too
short for this to happen. Unverified; the caller's identity is the next step.

## Wrong-cell camera, third one today
The `[mvloop]` R894 ARCH-REQ camera reads `0x8005FDF4`/`0x8005FE14`; the game
uses `0x8004FDF4`/`0x8004FE14` (sign-extended immediates). Its "FDF4=0 in 1255
samples" is retracted. Same class as `[phase]` (0x800592C0 vs 0x800692C0).

---

# UPDATE: callback identified (R845) and fixed (R1509) — but it was a symptom

## The callback is R845, a runtime rescue arm — exact 1:1:1
R1508 intruder batch, two independent trials:
```
                                trial 1   trial 3
R845 POLL-PARK RE-FORCE fires       8         8
field-coordinator interp entries    8         8
ArchiveSetIndex(4) during the read  8         8
```
R845 ("backup plan, round two") force-dispatches the field coordinator 0x80077E88
when the pre-movie poll counter `mv_n` is high and t > 20s. Its own comment says
it was built for the era AFTER boot. Its only era guard is `!g_splash_live`, and
boot never reaches the splash, so that guard never engages. The coordinator calls
`ArchiveSetIndex(4)`, rewriting the archive base. (R844, the sibling that forces
the same door on reboots, fired 0 times — ruled out.)

## R1509: R845 may only re-force once boot has reached MainLoop
Gate added: `g_bc_n[16] > 0` (R1501 [bootcam] MainLoop entry count).

Result, 6 trials x 150s:
```
R845 fires                  0 in all 6          (was 8)
0x800858A8 intruders        0 in all 6          (was 8)   <- mechanism removed
remaining "intruders"       ra=0x8001967C archive 1 depth 0 = GameBootstrap
                            after a reboot; my in-flight flag survives reboots
MainLoop reached            2 / 6               (baseline ~23%, 9/39)
```

## Verdict: correct fix, wrong root cause
R1509 does what it should — R845 no longer interferes with boot. **It does not
unblock boot.** MainLoop is unchanged.

The reason is causality, which I had backwards. Boot reaches the failing read at
t~2-3s. R845 first fires at t~21s — about 18 seconds AFTER the read was already
stuck. R845 fires BECAUSE the read is stuck: the stuck CD wait is what drives
`mv_n` past R845's threshold. So the archive-base clobbering is DOWNSTREAM of the
hang, not its cause. The "FE14 = 0x17 at the read" capture was contaminated by
the same reboot-persistent flag.

## Kept anyway
R1509 is kept as a correctness fix (a later-era rescue must not rewrite archive
state during boot) and because removing that interference is required to see the
real failure cleanly. It is NOT claimed as progress.

## Also observed
Reboots rose to 10-16 per run in three trials (typically ~2). Without R845
forcing the coordinator, the stuck read now falls through to reboot recovery
instead. More attempts, same success rate.

## The real question is now narrower
Why does the read of archive 16 / file 3 hang in the first ~18s, before any
rescue arm touches it? R1505 placed it inside ArchiveReadFile's CD streaming,
after CdIntToPos. That is a genuine CD read that does not complete.
