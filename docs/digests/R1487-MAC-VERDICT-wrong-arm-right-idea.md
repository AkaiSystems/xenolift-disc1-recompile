# R1487 Mac verdict: NULL — ported the right way, wrong arm. Plus a hot-path hazard.

6 serialized trials, 300s budget, nothing else on the machine, scored only after
all runs exited. Build: R1482 + r96gate + R1486 + R1487. All figures from
`run.log.raw`.

## Result

```
PASS 1 — does [c2door] fire in guest-read context?
  trial      1  2  3  4  5  6
  c2door R1487 (twin)   0  0  0  0  0  0
  c2door R1191 (alarm)  0  0  0  0  0  0
  alarmguard            6  6  6  3  5  5

PASS 2 — escape (corrected detector: movie-band read at/after last field read)
  ESCAPE RATE: 0 / 6     (baseline without R1487: also 0 / 6)
```

**NULL on both criteria — but read the nuance before concluding anything about
the migration.**

## The port is not what failed
The **alarm copy fired 0 times too**. So this is not "the guest-read placement
doesn't work". The arm's own gate never became true in any run. The R1160/c345
migration concept is **untested by this trial, not refuted.**

## Why it never fired: 4 of 6 gate terms are wrong for the current stall

R1487 gate:
```c
c1487_fe1c == 1  &&  c1487_f8 != 0  &&  cd_seek_lba == 0
  && cd_pending == 0 && !cd_read_active && !cd_scheduled
```

Actual stall posture, reproducible and identical in trials 2 and 4:
```
fn 0x800286CC   seek=108884   FE1C=00   FDF8=00000000
act=1  loaded=1  sched=0  pend=0
```

| gate term | needs | actual | |
|---|---|---|---|
| `FE1C` | 1 | **0** | FAIL |
| `FDF8` | != 0 | **0** | FAIL |
| `cd_seek_lba` | 0 | **108884** | FAIL |
| `!cd_read_active` | act=0 | **act=1** | FAIL |
| `cd_pending` | 0 | 0 | ok |
| `!cd_scheduled` | 0 | 0 | ok |

`[c2door]`/R1191 targets the **boot-era idle-at-seek-0 pending-file** posture.
That is not the failure we are hitting. Its table band (108754–109158) overlaps
the stall *LBAs*, which is presumably why it was chosen — but LBA overlap is not
posture overlap.

## Port one of these instead — the posture matches
`FDF8==0` with `act=1 loaded=1` and `FE1C==0` is the **completed-read** class:
the read finished and the guest does not proceed. The in-tree family already
built for exactly that is **R1452 / R1436A / R1460F v2 / R1459W** — and every one
of them lives in `on_alarm_ctx`, so every one is dead at depth>0. That family is
the highest-value migration target, and unlike `[c2door]` its gate matches a
posture we can reproduce on demand.

## Hazard to fix in any future port: hooked reads on the hottest path
R1487's gate calls `xenolift_mem_read32` **three times on every**
`case 0x1F801800` status poll. R1197's comment states the rule verbatim:

> *"NEVER `xenolift_mem_read32` here: hook reads would feed the read-hit
> counters, the A22C cadence/threshold, and the kick counters"*

The status register is polled billions of times per run — this is a far hotter
path than the FE1C hook where I hit the same problem. My R1490 did exactly this
and produced a phantom ~3x "regression" while firing **zero** times. Use
bounds-checked `memcpy` from `xenolift_mem` instead, as R1197 does.

I am **not** claiming R1487 caused a regression. Last-field-read times in this
batch (1,28,2,76,4,3 s) are earlier than baseline (36,179,7,171,7,35 s), but with
zero fires it cannot be causal, and run-to-run variance here is already known to
swamp effects this size. Reporting the numbers, not a verdict on them.

## A fifth distinct wedge function
`fn 0x800286CC`, new this batch. Running tally of wedge sites: `8004252C`
(CD_flush), `8004247C`, `8004B55C`/`80041C68`, `80042AA8` (CD_getsector),
`800286CC`. The alarmguard blackout is confirmed structural across five
independent guest spin sites.

## Credit
The port itself is well-built: alarm copy kept, twin tagged distinctly, stuck
fence taken from R1451's receipted posture-poll confirm on the same case rather
than invented, and the corrected escape detector adopted. The approach is right.
Retarget it at the completed-read family and fix the hooked reads.
