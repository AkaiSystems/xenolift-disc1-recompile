# FIX proposal: R1476 `[fldbatch]` multi-sector poll burst on R1461S (ONE FIX B)

**Author lane:** Programming · Nasir (grade for DIRECTOR)
**Tree pin:** `xenolift-clean` @ tip including this commit
**Digest:** `docs/digests/ROOT-CAUSE-1-sector-per-second.md` (+ A22C addendum)
**reapply_OR_forbidden:** YES
**Verdict:** APPROVE B — reject A; reject stillness/armstart stacking

## Why

The plateau is a consumer metronome at ~**1.00 LBA/s**, not a stall (ROOT-CAUSE
digest). Guest `LegacyCdDataWait` exits via its internal ~1–2s timeout every
sector; R1461S already serves the stuck-fire posture but only **one sector per
fire**. Crossing 108900 → 120634 (~11,734 sectors) at 1 LBA/s takes ~3.3 hours.
Batching K sectors per stuck-fire raises throughput without touching FE1C OR,
alarm(2), or stillness/armstart.

## What

Placement: `source/runtime/runtime.c` — **R1461S v8** fire body at guest
`0x800286CC` (the existing stream-serve site). Gates **unchanged**:

- bands `[120000,121000]` + `[108700,109400]` (+ existing deep `[250000,251000]`)
- `FE04==seek`; `FDF8>=64` (and existing upper); `act!=0`
- `pend==0`; `arm1==0`; `sched==0`; `cmd∈{02,06,0D,01}`
- existing FE08 / 65536 stuck-confirm / budget 48

On fire, replace single `cd_data_load`+pend+INT1 with **K=8** burst:

```
for i in 0..K-1:
  if FDF8 < 64: break
  loaded = 0
  cd_data_load()
  pend = 1
  cd_force_deliver_int1("fldbatch")
  if FDF8 unchanged vs before this iteration: break  // R958 progress-break
```

Log each iteration: `[fldbatch] i/K seek FDF8 before->after FE04 FE08`.

## Pass / fail

Hiroshi rate profile (same stamps as ROOT-CAUSE digest):

| Signal | Verdict |
|--------|---------|
| After t=10s still ~**1.00** LBA/s | **FAIL** — burst did not lift consumer cadence |
| Sustained ≫1 LBA/s (toward early-burst ~126) | **throughput PASS candidate** |
| Field bar: seek past **120634** | field door progress |

## Revert criteria

- `[fldbatch]` fires with zero FDF8 progress (every iter `before==after`)
- Rate profile unchanged at ~1.00 after t=10s across a ≥180s trial
- Any FE1C / alarm / stillness regression (this FIX must not have touched those)

## NON-goals (HARD)

- No FE1C OR / widen (`reapply_OR_forbidden=YES`)
- No new stillness/armstart
- No alarm(2) period change
- No A22C-only rewrite this cycle
- No disc images committed; do not rewrite `xenolift-source`
