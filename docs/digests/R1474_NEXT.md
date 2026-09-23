# Next Mac cycle: R1474 plateau cycling camera

Landed on `xenolift-clean`. Camera-only (zero behavioral). HOLD stillness/armstart. `reapply_OR_forbidden=YES`.

Grep tag: `[platcam]`  
Proposal: `docs/proposals/R1474-platcam.md`

## Paste-ready Mac steps

```bash
cd /path/to/xenolift-disc1-recompile   # your Mac clone
git fetch origin
git checkout xenolift-clean
git pull --ff-only origin xenolift-clean
# confirm tip includes R1474 platcam in source/runtime/runtime.c
rg -n 'R1474.*PLATEAU CYCLING CAMERA' source/runtime/runtime.c

# rebuild the usual way (same recipe as prior Mac cycles)
# then ONE 600s+ trial (fuse ≥600s). Do not shorten.

# After the run:
rg '\[platcam\]' run.log | tee /tmp/platcam.txt
rg '\[pausepend\] R1473' run.log || true
rg 'seek=' run.log | tail -20   # or your usual max-seek extractor
```

## Digest to push

Write `docs/digests/r1474-platcam-<shortsha-or-stamp>.md` and push to `origin/xenolift-clean`. Include at minimum:

1. **platcam counts:** total `[platcam]` lines; split `chg` vs `hb`; first/last `@t=` while seek in-band.
2. **max seek** (and whether it stayed in ~108886–108907 / camera band 108880–108920).
3. **R1473 fires:** expect still `0/8` (we did not change R1473).
4. **ctx growth:** last `hb` line `ca0=` / `bb0=` / `other=` / `evals=` — does pump vs fd-processor residency show up?
5. **Cold-seam check:** if seek entered band but `platcam=0` → composer seam cold; flag for dispatch-site camera (see proposal).
6. Cap check: ≤384 platcam lines.

One cycle. No FE1C OR. No new armstart. Camera receipts only.
