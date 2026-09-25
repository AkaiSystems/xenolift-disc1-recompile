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
