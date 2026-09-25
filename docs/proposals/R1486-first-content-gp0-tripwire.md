# R1486 — First-content GP0 tripwire (camera stub)

**Lane:** Nasir / Programming · Task B SECONDARY  
**Tree pin:** `xenolift-clean` @ `43e44569964e4777fe2e278f6a4469533a7986d1`  
**Status:** STUB ONLY — do not implement this turn  
**Depends on:** GPU work remains deferred until a non-fill primitive appears
(`docs/TASKS-grok-next.md`)

## Intent

Today the GPU HLE is healthy (16/16 unit tests) but the game has never
submitted a drawing primitive. R939 census: `fill=1 copy=0 rect=0 line=0 poly=0`.
`vram_writes` is always a multiple of 184320 = one GP0(02) 384×480 black
fill. `dma2_sends` ticking 1→3 is the render loop spinning, not content.

When load finally advances far enough, we want the **exact first non-fill
GP0** captured — drive + guest posture + primitive words — rather than
discovered later from a census.

## Proposed camera (not landed)

- **Site:** GP0 submit path (DrawPrim / HLE submit / `xenolift_drawprim_cam`
  neighbourhood — locate at implement time; do not guess from this stub).
- **Fire:** first time a GP0 primitive class is **not** fill-rect (02), i.e.
  poly / rect / line / sprite / copy / other non-fill.
- **Print:** full drive posture (seek/cmd/pend/sched/act/FE1C/FE04/FDF8/A22C)
  + guest `cur_fn`/`r31` + primitive words/tag/len. Cap ≤8 (preferably 1–2
  for the true first).
- **Behaviour:** **camera only** unless R1485 census (or later DIRECTOR note)
  proves a behavioural need — default remains camera-only.

## Pass / revert bars

| | Bar |
|---|---|
| **Pass** | Tag appears in `run.log.raw` on the first non-fill GP0; binary contains tag (`strings`); source SHA matches build; fill-only runs stay silent |
| **Revert** | False fires on fill-rect; log storm; any behavioural mutation sneaks in without DIRECTOR go |

## HOLDs

Same as R1485: no R885 touch, no FE1C OR, no dual-land into Pause lane,
one FIX at a time, no implement this turn.

## Relationship to GPU work

This tripwire is the **legitimate GPU-adjacent** work now. Full GPU
emulation tuning stays deferred until this camera (or equivalent) proves
the game is exercising non-fill content.
