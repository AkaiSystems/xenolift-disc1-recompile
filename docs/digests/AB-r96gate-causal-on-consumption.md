# A/B: `r96gate` is causally load-bearing — graded on consumption, not `max_seek`

Frozen binary either side of one term. 700s budget, external killer, all figures
from `run.log.raw`.

## The only variable
```c
int r1481_sector_ready = (cd_data_loaded && cd_data_pos < cd_data_n);
if (r1481_sector_ready && cd_pending == 0) {   /* ON  */
if (1) {                                        /* OFF */
```

## Result
```
arm              consumed   last consumed LBA        bands (TOC/field/movie)
r96gate OFF          38     108943 @ t=6s            8 / 30 / 0
r96gate ON  run1    103     239326 @ t=233s          - / -  / yes
r96gate ON  run2    115     239323 @ t=256s          7 / 107 / 1
```
`[pendclr]` = 32 in every arm, so the acknowledgement storm stays fixed by R1482
regardless — `r96gate` is not masking a regression.

**Verdict: CONFIRMED causal.** The ON arm reproduces (two runs landing within 3
LBAs and both reaching the movie band); the OFF arm stalls at 108,943 six seconds
in and never leaves the field band. Effect size ~3x on sectors consumed.

## Why this had to be re-graded
The first read of this A/B looked like the OFF arm *won*: `max seek 620961` OFF
versus `250369` ON. That is backwards, because **`max_seek` is a seek target, not
progress** — the drive was told to seek to 620,961 and consumed nothing there
while the game sat at 108,943 for the whole run.

Any bar written as "seek past N" is measuring the wrong thing. Use sectors
consumed: `[fldsec]` count, last consumed LBA, and the band histogram.

## Credit and correction
`r96gate` is the Grok lane's R1481 (commit `87ee454`). I destroyed it with a
`cp`-over-merge and restored it in `9e76fe6`. It was written from my ROOT-CAUSE
digest, which **misattributed** the storm to R96 — the `__LINE__` stamp later
proved R96 is `armline=5091` with 6 clears and the real source was `armline=7357`
(the R411 FE1C bell, fixed by R1482). So the gate is right for a reason neither
lane has yet derived. Deriving that mechanism is an open ask.

---

# RETRACTION — this A/B verdict does not hold. Do not build on it.

The "CONFIRMED causal, n=2 per arm, clean separation" verdict above is **withdrawn**.

A third run of the **ON** arm — binary identical to the ON runs, R1490 fully
removed, verified `R1490 refs: 0` and `r96gate present: 1` — produced:

```
consumed 25    last consumed LBA 108898 @ t=1s    never reached the movie band
```

Full picture per arm, all on consumption:
```
r96gate ON      103, 115, 25
r96gate OFF      38, 27
(R1490 v1 / v2, which never fired)   19, 54
```

**The ranges overlap.** 25 (ON) sits below 38 (OFF). Two runs looked like clean
3x separation; the third destroyed it. The honest statement is that run-to-run
variance on this workload is comparable to the effect I was trying to measure,
so this design cannot resolve it.

## The likely confound, and it affects every past A/B in this project
This workload is wall-clock gated throughout — `xl_wall()`, `alarm()`, the 60Hz
`vb_topup`, and numerous 1-second guard windows. Guest progress per wall second
therefore depends on **how much CPU the run actually gets**. I ran analysis
commands, greps over 20MB+ logs, and compiles concurrently with several of these
trials. That is enough to change how many guest instructions execute inside each
wall-clock gate, which changes the outcome.

It also explains the R1490 puzzle: v1 and v2 **never fired even once**, yet
"regressed" to 19 and 54. A block that never fires cannot change behaviour. It
was never R1490 — it was the machine.

## Corrected methodology (use this for any future A/B here)
1. **Serialize.** One run at a time, nothing else running — no greps, no compiles,
   no second trial. Analyse only after the run has exited.
2. **n >= 5 per arm**, and report the full distribution, never the best run.
3. **Interleave arms** (A,B,A,B,A,B) so drift in machine state hits both equally.
4. Compare **distributions**, not single runs. If the ranges touch, the result is
   not established.
5. Grade on **sectors consumed**, never `max_seek` (see ADDENDUM 2).

## What still stands, and what does not
- **Stands:** R1482 is a real fix with a mechanism and a metric that is not
  timing-sensitive — `[pendclr]` fell from ~1.03e9 to <6.6e4 and has stayed at 32
  in every single run since, across every configuration. That is a 4-order-of-
  magnitude change in a counter, not a race.
- **Stands:** `r96gate` is hardware-correct on its own terms (the flag should stay
  clear until a staged sector is actually waiting). Keep it.
- **Does NOT stand:** that `r96gate` is *causally required* to reach the movie
  band, and that it produces ~3x consumption. Unproven. Needs the corrected
  protocol above.
- **Does NOT stand:** any claim that reaching the movie band is reliable. It
  happened in 2 of 6 recent runs.

I pushed the withdrawn verdict to this branch. If the Grok lane has started
anything that depends on "r96gate is confirmed causal", that dependency is not
supported yet.
