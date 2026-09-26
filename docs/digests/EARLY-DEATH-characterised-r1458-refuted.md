# Early field-band death: characterised, two hypotheses tested on 48 trials, no fix yet

Status note, not a fix. Recording what is ruled out so nobody re-derives it.

## Recovery check: R1495 revert is clean
Recovery batch (R1493 state) 1/6. R1493 across all four batches now **9/24 = 38%**
vs prior 2/24, Fisher one-tailed p = 0.018 (budget-4 batches alone: 6/18). Holds.

## The "terminal FE04=108894" I started from was a sampled-camera artifact
The last `[waitbr]` line is a budgeted camera, not the terminal state. The real
walk is healthy past it: `FE04` +1 at `0x80040FCC`, `FDF8 800->0` (consumed) at
`0x80040FCC`, `FDF8 0->800` (next armed) at `0x8004196C`, one clean cycle per
sector through 108927. Same trap class as `[fldsec]` and `drains=0`: **a budgeted
camera's last line is not the terminal state.**

## What the early deaths actually look like
Three independent trials stop at the same place:
```
trial 3:  06->09 seek=108935 FDF8=2048 | 09->09 108936 | 09->02 108936
trial 5:  09->02 seek=108934 FDF8=2048 | 06->09 108935 | 09->02 108935
trial 6:  06->09 seek=108935 FDF8=2048 | 09->09 108936 | 09->02 108936
```
Normal chunked reading (Setloc -> ReadN -> Pause every ~4 sectors) from 108900,
entering the file the tree's own table lists as `{108933, 125304}`, and stopping
2-3 sectors in. R412's comment already records "two re-arm passes 108933-108939"
at exactly this boundary.

The escaping run takes a different path at 108901/108907:
`09->01->0A->0C->07->0E->0D->02` = Pause -> Getstat -> **Init** -> Demute ->
MotorOn -> Setmode -> Setfilter -> Setloc. A full drive re-initialisation.

## Hypothesis 1 — r1458 causes the deaths. REFUTED.
On the first 6 trials it looked decisive: r1458 (`DISCARD` + `RE-ARM`: FE04 stamp,
act, same-poll `cd_data_load`, pend, force INT1) fired in 3 of 4 deaths and 0 of 2
survivors, and it is exactly the forced-bell class the c166 lesson warns about.

All 48 trials on disk, 8 batches:
```
                    escaped  no-escape  rate
r1458 fired            1         7      12%
r1458 did not fire     9        31      22%
Fisher p = 0.46
```
31 of 38 deaths happened with r1458 silent. **It is not the driver. Do not
disable or port r1458 on the strength of the 6-trial correlation.** This is the
second time today a 6-run correlation has failed on a larger sample (the first was
alarm-context liveness).

## Hypothesis 2 — the drive-reinit path. NECESSARY, NOT SUFFICIENT.
```
                          escaped   rate
Init (cmd ->0A) seen      10 / 36   28%
Init never seen            0 / 12    0%     Fisher p = 0.039
```
Every one of the 10 escapes went through Init; all 12 runs that never reached it
died. But 26 runs reached Init and still died.

`Setloc back to 108754` occurs in **48/48** trials, so it does not discriminate.

## Where that leaves the ~62% that do not escape
```
never reach Init        12/48 = 25%   always die (0/12)
reach Init, still die   26/48 = 54%
escape                  10/48 = 21%
```
Two separate problems, not one. The never-Init subgroup is the cleaner target: it
fails deterministically, so a fix there is directly measurable.
