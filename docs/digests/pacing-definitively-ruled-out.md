# Digest: pacing definitively ruled out - the 108886-108907 ceiling is structural

## Data across budget range 120s-900s (4 trials, same tree @ 1f4c307 = R1473 + cd_tick_busy fix)

| Budget | Max organic seek | R1473 fires |
|---|---|---|
| 120s | 108907 | 0/8 |
| 180s | 108907 | 0/8 |
| 600s | **108901** | 0/8 |
| 900s (pre-R1473 tree) | 108886 | n/a (camera not present yet) |

**More budget does not produce more organic progress.** A 7.5x increase in wall-clock
time (120s -> 900s) produced *zero* net additional field-loading distance - if
anything the 600s run landed marginally lower than the 120-180s runs, well within
noise. This rules out "just needs more time" as an explanation for the plateau.
Whatever holds the ceiling at ~108886-108907 is present from the start and does
not resolve itself given more cycles.

## R1473 still never fired, even with 900s of headroom

R1473 requires 2 continuous wall-clock seconds with `seek`/`FDF8`/`sched` all
unchanged. Across ALL trials to date (4 total, up to 900s), that never happened
once. This itself is informative: whatever is going on at the ceiling, the state
is *never* fully static for as long as 2 seconds - there's continuous small-scale
churn (per earlier digests: `cmd` and other fields cycling) even while the LBA
distance traveled stays flat. A time-based stability gate may not be the right
tool for a state that never actually goes still.

## Recommendation

The next productive instrumentation is probably NOT another stability-gated
armstart variant (R1467A/R1472/R1473 have each tried a different flavor of "wait
for stillness, then act" and none has fired yet across many trials). Worth
considering instead: directly instrument what's cycling during the plateau
(previously identified suspects: `cmd`, `FE1C`, the r31=0x80041CA0/0x80041BB0
pump contexts) to characterize the churn's actual period and cause, rather than
add a fourth stillness-detector with different thresholds. Camera-only finding,
no FIX proposed.
