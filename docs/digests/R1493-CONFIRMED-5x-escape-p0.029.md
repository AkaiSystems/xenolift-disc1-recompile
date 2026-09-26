# R1493 CONFIRMED: 5x escape rate, Fisher p = 0.029

First result this session with a real p-value. Two independent 6-trial batches,
serialized, 300s, nothing else on the machine, scored after each batch exited,
from `run.log.raw`, with the corrected escape detector (a movie-band read at or
after the last field-band read).

## The fix
`R1426A` (TOC-band FDF8 completion bookkeeping) made **act-agnostic**.

The TOC-band stall had the sector **already delivered** — LBA 5 loads into the
FIFO 9x and DMAs 4x to a sane sequential buffer (LBA 3->0x1800, 4->0x2000,
5->0x2800, each +2048) — but `FDF8` never left `0x800`, so the waiter's
`FDF8==0` exit term never computed. R1426A exists to post exactly that zero and
declined on a single term: `!cd_read_active`, while the posture is `act=1`.
`seek<150`, `FE04==seek`, `FDF8==2048`, `pend==0` all already held.

Dropping the act term is the **R1460F v2 precedent verbatim**: *"the SAME disease,
the act cell flutters between the two forks. v2 gates WITHOUT the act term."*

Safety is unchanged and was never the act term — the **serve-delta confirm** still
gates every fire: the zero is posted only when `g_sectors_loaded` has advanced (a
sector really landed) AND the game failed to decrement by the next evaluation. It
cannot invent a completion for a read that never delivered.

## Result
```
batch 1   trial 1  4 fires  ESCAPE            lastField 116s
          trial 2  4 fires  ESCAPE            lastField 109s
          trial 3  4 fires  no                lastField   6s
          trial 4  4 fires  no                lastField  10s
          trial 5  4 fires  ESCAPE            lastField 217s
          trial 6  4 fires  no                lastField  15s   -> 3/6

batch 2   trial 1  4 fires  no                lastField   8s
          trial 2  4 fires  ESCAPE 239318     lastField 126s
          trial 3  4 fires  no                lastField  15s
          trial 4  4 fires  ESCAPE 239317     lastField 117s
          trial 5  4 fires  no                lastField  10s
          trial 6  4 fires  no                lastField   3s   -> 2/6

R1493 COMBINED            5 / 12  = 42%
all prior configs pooled  2 / 24  =  8%
relative                  5.0x
Fisher exact              p = 0.0289 (one- and two-tailed)
vs strict 0/6 baseline    p = 0.0924 (n=6, underpowered)
```
Escapes are consistent: LBA 239317-239326, last field read 109-217s in all five.

## Progression, same protocol throughout
```
baseline (R1482 + r96gate)   0 / 6
+ R1487 [c2door] port        0 / 6
+ R1491 [fdfcclr]            1 / 6
+ R1493 (act-agnostic)       5 / 12
```

## What this is NOT
- **Not a solution.** It still fails 7 of 12 times. This removes one blocker on a
  path that has others.
- **Not matched-control proof.** The 2/24 prior pool mixes configurations
  (baseline, R1487, R1491, A/B arms). It is a reasonable "before" pool, not a
  matched control. Against the strict 0/6 same-protocol baseline the result is
  only suggestive (p=0.092) because that baseline is 6 runs.
- **No player-visible change.** `nonblank` is still 0%, no primitive has ever been
  submitted, so nothing renders. This is CD-path progress only.

## Immediate next step, stated as a prediction
R1493 exhausted its budget **4/4 in all 12 trials**, including all 7 non-escapes.
So firing is necessary-not-sufficient, and the budget is a candidate limiter.
Raising it 4 -> 32 is a clean single-variable test: if the budget is the limiter,
escape should rise above 5/12; if it does not move, the remaining barrier is
elsewhere and the budget is exonerated.

## Two corrections carried forward
1. My original PASS bar for R1493 ("TOC-band trials stop terminating at seek
   0-6") was **wrong and is withdrawn**. Escaping trials also terminate at seek
   2-3 because the drive seeks back to TOC at end of run; terminal seek does not
   indicate stranding. Escape is the valid bar.
2. R1426A sits at **L4770, outside `on_alarm_ctx`** — already reachable at
   depth>0, no port required. For the migration lane: verify an arm is actually
   stranded before porting it.
