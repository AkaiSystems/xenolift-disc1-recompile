# Next Mac cycle: R1479 `[r96cam]` INT1 re-arm / FIFO drain / 578A6 correlation

Landed on `xenolift-clean`. **Camera-only** (zero behavioral). Approved after RETRACTION of R1476 metronome thesis. `reapply_OR_forbidden=YES`. HOLD stillness/armstart. Do **not** revive fldbatch / R1476 doorbell. Do **not** kill R1477 this cycle (wait for R1478 `[hbcam]` receipts).

Grep tag: `[r96cam]`  
Proposal: `docs/proposals/R1479-r96-int1-rearm-camera.md`  
Digest base: `docs/digests/RETRACTION-the-rate-was-a-window-artifact.md`

## Decision rule (read before you run)

After **one ≥1500s** external-killer trial:

| Receipt shape | Decision |
|---------------|----------|
| FIRE floods during multi-minute stop; **DRAIN==0**; CLEAR zeroes 578A6 while **pos stays 0** | **R96 loop is real** → next cycle propose a *minimal* R96 gate change (camera-proven term only). Not this cycle. |
| FIRE rare / absent during stop; DRAIN still 0 | R96 is **not** the stop mechanism → do not touch R96; open a different hypothesis next. |
| DRAIN advances but FDF8/seek still freeze | Drain happens; failure is elsewhere — do not blame R96 re-arm. |

Pass/fail bar for the *eventual* fix (not this camera alone): `[mscycle]` gap distribution has **no gaps >100s** on a ≥1500s run. This camera's success is naming whether R96↔578A6 correlates with undrained FIFO.

## Paste-ready Mac steps

```bash
cd /path/to/xenolift-disc1-recompile   # your Mac clone
git fetch origin
git checkout xenolift-clean
git pull --ff-only origin xenolift-clean
# confirm tip includes R1479 r96cam
rg -n 'R1479 \[r96cam\]|\[r96cam\]' source/runtime/runtime.c

# rebuild the usual way (same recipe as prior Mac cycles)
# then ONE ≥1500s trial with EXTERNAL killer (sleep N; pkill -9).
# Do not trust in-tree fuse alone for this bar.

# After the run:
rg '\[r96cam\]' run.log | tee /tmp/r96cam.txt
rg '\[r96cam\] FIRE'  run.log | wc -l
rg '\[r96cam\] CLEAR' run.log | wc -l
rg '\[r96cam\] DRAIN' run.log | wc -l
rg '\[r96cam\] STUCK' run.log | tee /tmp/r96cam-stuck.txt
rg '\[mscycle\]' run.log | tee /tmp/mscycle.txt
# gap histogram: consecutive [mscycle] t= deltas; flag any gap >100s
rg '\[hbcam\] R1478' run.log || true   # note R1478 lines if present (keep/kill orthogonal)
rg 'seek=' run.log | tail -40          # or your usual max-seek extractor
```

## Digest to push

Write `docs/digests/r1479-r96cam-<shortsha-or-stamp>.md` and push to `origin/xenolift-clean`. Include at minimum:

1. **`[r96cam]` counts:** FIRE / CLEAR / DRAIN / STUCK totals (and whether FIRE flooded during a multi-minute stop).
2. **`[mscycle]` gap histogram:** list gaps; call out any **>100s** (967s/1185s class).
3. **max seek** reached.
4. **Decision-rule verdict:** which of the three receipt shapes matched (R96 loop real / not the mechanism / drain elsewhere).
5. **R1478 note:** any `[hbcam] R1478` lines (calls / past_hb / R1477term) — observational only; do not kill R1477 in the same push unless DIRECTOR already directed.
6. Cap check: FIRE/CLEAR/DRAIN ≤64 each; STUCK ≤8.

One cycle. No FE1C OR. No R96 behavior change. Camera receipts only.
