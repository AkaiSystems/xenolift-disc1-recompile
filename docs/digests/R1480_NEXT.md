# Next Mac cycle: R1480 `[xcam]` stream-transition camera

Landed on `xenolift-clean`. **Camera-only** (zero behavioral). DIRECTOR APPROVES R1480 [xcam].
`reapply_OR_forbidden=YES`. HOLD stillness/armstart. Do **not** revive fldbatch / R1476 doorbell.
Do **not** re-land R1477. Do **not** propose an R96 behavioral FIX from DRAIN==0.

Grep tags: `[xcam] STALL` · `[xcam] N-`  
Proposal: `docs/proposals/R1480-stream-transition-camera.md`  
Digest base: `docs/digests/R1479-first-results-and-a-trap.md`

## Revised decision rule (locked — read before you run)

| Claim | Rule |
|-------|------|
| DRAIN==0 from R1479 `[r96cam]` | **DMA trap** — PIO drain stays 0 while healthy DMA delivers. **Does NOT authorize an R96 FIX.** |
| FIRE=128 / CLEAR=128 | R96 re-arm is real; still not proof of loop harm. |
| This camera's job | Name the **regime transition** at seek ≈108905–108910 via last-N=16 DMA/`[fldsec]` deliveries before `[fldsec]` freezes. |
| Eventual fix bar (unchanged) | `[mscycle]` gaps on a **≥1500s** run — **no gaps >100s**. Do not use ~1.00 LBA/s or 180s windows. |

After **one ≥1500s** external-killer trial with this camera:

| Receipt shape | Decision |
|---------------|----------|
| Last N deliveries healthy (sane `madr` / FDF8 drain), then posture flips (`act`/`pend`/`cmd`/`FE1C`/`fn`) with **no further `[fldsec]`** | Transition named → next cycle propose **one** behavioral fix on the proven flipped term only |
| Deliveries already sick (bad `madr`, FDF8 stuck, act=0) before the last N | Failure is **upstream of** the stop LBA — do not “accel” the plateau |
| No stall dump / fldsec keeps ticking past 109050 | Band wrong or stop moved — retarget band, no FIX |
| Stop only ends via R1283/R473 with empty ring | Camera miss — widen arm condition, still no FIX |

## Paste-ready Mac steps

```bash
cd /path/to/xenolift-disc1-recompile   # your Mac clone
git fetch origin
git checkout xenolift-clean
git pull --ff-only origin xenolift-clean
# confirm tip includes R1480 xcam
rg -n 'R1480 \[xcam\]|\[xcam\] STALL' source/runtime/runtime.c

# rebuild the usual way (same recipe as prior Mac cycles)
# then ONE ≥1500s trial with EXTERNAL killer (sleep N; pkill -9).
# Do not trust in-tree fuse alone for this bar.

# After the run:
rg '\[xcam\]' run.log | tee /tmp/xcam.txt
rg '\[xcam\] STALL' run.log | tee /tmp/xcam-stall.txt
rg '\[xcam\] N-' run.log | tee /tmp/xcam-ring.txt
rg '\[mscycle\]' run.log | tee /tmp/mscycle.txt
# gap histogram: consecutive [mscycle] t= deltas; flag any gap >100s
rg '\[fldsec\]' run.log | tail -40
rg 'seek=' run.log | tail -40          # or your usual max-seek extractor
rg '\[r96cam\]' run.log | wc -l || true  # observational only; DRAIN==0 is NOT R96 proof
rg '\[fldbatch\]' run.log | wc -l || true
```

## Digest to push

Write `docs/digests/r1480-xcam-<shortsha-or-stamp>.md` and push to `origin/xenolift-clean`. Include at minimum:

1. **Transition dump:** full `[xcam] STALL` header(s) + the `[xcam] N-*` ring (oldest→newest). Call out which term flipped between N-1 and freeze.
2. **`[mscycle]` gap histogram:** list gaps; call out any **>100s**. PASS bar for an eventual fix = **no gaps >100s** on this ≥1500s run (camera alone grades the transition, not the bar).
3. **max seek** reached; whether stop landed in band `[108880, 109050]`.
4. **Decision-rule verdict:** which of the four receipt shapes matched.
5. **Revised R1479 note:** explicitly state that DRAIN==0 does **not** authorize an R96 FIX.
6. Cap check: stall dumps ≤8; ring slots ≤16 static.

One cycle. No FE1C OR. No R96 behavior change. No R1477 re-land. No fldbatch revive. Camera receipts only.
