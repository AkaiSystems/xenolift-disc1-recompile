# The outcome is BIMODAL, and escape tracks alarm-context liveness

This reframes what we have been measuring and it makes Task A the highest-value
work in the tree. It also supersedes "distance travelled" as a metric.

## 1. It is not a continuum — it is escape or hard-stall

Per-run, the time of the LAST sector consumed (700s budget, ~665s of the run
therefore producing NOTHING):

```
run        last consumed LBA    at        outcome
ab_on      239323               t=256s    ESCAPED to the movie band
ab_off     108943               t=6s      hard-stall
ab_off2    108901               t=20s     hard-stall
base3      108898               t=1s      hard-stall
r1490      108895               t=2s      hard-stall
r1490b     108882               t=35s     hard-stall
```

Five of six runs consume their final sector inside 35 seconds and then do
absolutely nothing for the remaining ~665s. "Sectors consumed" therefore is not
measuring speed — it is measuring **whether the run died early**, and the spread
(19..115) is the spread between two discrete outcomes, not a rate.

## 2. The escaping run stayed alive and retried

`ab_on` band-entry timeline:
```
t=0s    field band
t=20s   TOC re-read, then field again
t=198s  TOC re-read, then field again
t=256s  MOVIE BAND
```
It re-reads the disc TOC twice and retries. The stalled runs do not retry — they
consume nothing at all after their stall point. So the difference is not "faster
vs slower"; it is **alive and retrying vs hard-wedged**.

## 3. Escape tracks alarm-context liveness

```
run        escaped   [wd]   [halt]   [park]   wedge-prints   consumed
ab_on      YES        30      31        0          7            115
ab_off     no         10      16       16          0             38
ab_off2    no          0       0        0          7             27
base3      no          0       0        0          0             25
r1490      no          0       0        0          0             19
r1490b     no          0       0        0          8             54
```

The one run that escaped has ~3x the alarm-context liveness of any other, and
**four of the five stalled runs show total blackout** (`[wd]`=0, `[halt]`=0).

`[wd]` and `[halt]` print only from inside `on_alarm_ctx`. They are non-zero
exactly when the guest reaches `g_guest_depth == 0` often enough for R885's
alarmguard to let the drain run. When it does, the whole rescue tree fires and
the game keeps retrying until a retry succeeds. When the guest hard-spins at
depth > 0, everything goes dark and the run is over.

`ab_off` (liveness 10/16/16, no escape) shows liveness is **necessary but not
sufficient** — so this is a correlation across 6 runs, not a proven mechanism.
Stated as such deliberately.

## 4. Why this makes Task A the priority

If escape depends on the rescue tree being reachable, then migrating rescues out
of `on_alarm_ctx` into guest-read context (the R1160/c345 pattern) does not just
recover some dead cameras — it converts a **2-in-6 lucky escape into a
deterministic one**. That is a far larger effect than any individual arm.

## 5. Better metrics, and much cheaper runs

- **Primary (binary): did it escape the field band?** `grep -cE 'LBA 2[0-9]{5} consumed'`
- **Leading indicator: `[wd]` + `[halt]` counts** — alarm-context liveness.
- Both are outcome/state measures, not rates, so neither is corrupted by the
  CPU-share confound that forced the A/B retraction.
- **Runs can be ~90s, not 700s.** Stall-or-not is decided inside ~35 seconds.
  That is roughly 8x cheaper, which finally makes n>=5 per arm practical under
  the serialized protocol.

## Caveat, stated plainly
Six runs, one escape. Everything above is a correlation with an obvious causal
story, not a demonstrated mechanism. The corrected protocol (serialized, n>=5,
interleaved arms, distributions not single runs) still applies — but it is now
affordable, because the runs got 8x shorter.

---

# RETRACTION 2 — liveness does NOT predict escape. Escape rate is 1/12.

The correlation claimed above is **withdrawn**. A serialized 6-trial protocol
(300s budget, nothing else running on the machine, scored only after all runs
finished) refutes it.

## Escape rate, correctly scored

An escape is a movie-band read occurring **at or after** the last field-band
read. My first detector — `grep -cE 'LBA 2[0-9]{5} consumed'` — was wrong: it
also matches the **boot-era FMV probe at t=2s**, which happens *before* the field
walk and is not progress. Trial 6 scored as an escape under that detector and is
a false positive.

```
run           result   lastField(t)  escape(t,LBA)     early-boot movie reads
ab_on         ESCAPE   256           (256, 239323)     0
trial_1..6    no       36/179/7/171/7/35   -           0,0,0,0,0,2
ab_off        no       6             -                 0
ab_off2       no       20            -                 0
base3         no       1             -                 0
r1490/b       no       2 / 35        -                 0

ESCAPE RATE: 1 / 12      (serialized protocol alone: 0 / 6)
```

## The liveness hypothesis is dead
```
trial 2   [wd]=77  [halt]=81   -> NO escape   (highest liveness measured)
trial 5   [wd]=79  [halt]=43   -> NO escape
trial 4   [wd]=17  [halt]=15   -> NO escape
ab_on     [wd]=30  [halt]=31   -> ESCAPE      (the only one)
```
The two highest-liveness runs did not escape, and trials 1/3/6 escaped-or-not
with zero liveness. Alarm-context liveness does **not** predict escape. The
6-run correlation that suggested it was an artifact of a small sample, and I
should not have written it up as "makes Task A the highest-value work" on that
basis.

## What this does and does not change

- **Task A is still worth doing.** The alarmguard blackout is real, measured at
  four distinct `cur_fn` values, and it does make large parts of the tree
  unreachable. That stands on its own evidence.
- **But the justification I gave for prioritising it is void.** "It converts a
  2-in-6 lucky escape into a deterministic one" is unsupported. Do not plan
  around that claim.
- **Reaching the movie band is a rare event: 1 in 12 runs, 0 in 6 under the
  clean protocol.** The single escape (`ab_on`) may be a fluke. An earlier run
  that appeared to escape cannot be re-scored — its raw log was not preserved —
  so it is not counted.
- **The current build does not reliably progress past the field band.** Any
  claim resting on "we now reach the movie band" should be treated as unproven.

## Method note
Three detectors in this project have now produced confidently wrong answers:
`max_seek` (a seek target, not progress), sectors-consumed (a rate corrupted by
CPU-share), and this escape regex (matched a boot-era probe). Each looked
reasonable. Define the detector against a known-good and a known-bad run before
trusting it.
