# Next Mac cycle: R1476 `[fldbatch]` multi-sector poll burst

Landed on `xenolift-clean`. Behavioral FIX B on R1461S v8 fire body only.
Gates unchanged. `reapply_OR_forbidden=YES`. No FE1C OR, no stillness/armstart,
no alarm(2) rewrite.

Grep tags: `[fldbatch]` · `[fstrfd] R1461S v8+R1476`
Proposal: `docs/proposals/R1476-fldbatch.md`
Digest base: `docs/digests/ROOT-CAUSE-1-sector-per-second.md`

## First-trial risk (read before you run)

R1461S still requires the **65536-eval stuck confirm** before each fire. That
means the burst only runs after the posture has been held for a long stretch —
early under-fire / sparse `[fldbatch]` lines in a short window are expected, not
proof the site is cold. Prefer a **≥180s** trial (ideally **600s**) so enough
stuck-fires accumulate to move the rate profile. Do not judge PASS/FAIL from the
first few seconds alone.

## Paste-ready Mac steps

```bash
cd /path/to/xenolift-disc1-recompile   # your Mac clone
git fetch origin
git checkout xenolift-clean
git pull --ff-only origin xenolift-clean
# confirm tip includes R1476 fldbatch
rg -n 'R1476 \[fldbatch\]|k_fldbatch' source/runtime/runtime.c

# rebuild the usual way (same recipe as prior Mac cycles)
# then ONE rate-profile trial ≥180s (prefer 600s). Match ROOT-CAUSE timestamps.

# After the run — rate profile (same stamps as digest):
#   t≈2s, 8s, 10s, 31s, 61s, 91s, 121s, 181s  (and later if 600s)
# Extract seek/LBA progress vs wall the usual way; compute LBA/s.

rg '\[fldbatch\]' run.log | tee /tmp/fldbatch.txt
rg '\[fstrfd\] R1461S v8\+R1476' run.log || true
rg 'seek=' run.log | tail -40   # or your usual max-seek extractor
```

## Digest to push

Write `docs/digests/r1476-fldbatch-<shortsha-or-stamp>.md` and push to
`origin/xenolift-clean`. Include at minimum:

1. **Rate profile** at ROOT-CAUSE timestamps (t=2/8/10/31/61/91/121/181+).
   - still ~1.00 after t=10s → **FAIL**
   - sustained ≫1 → throughput **PASS candidate**
2. **`[fldbatch]` counts:** total lines; how often `i` reached 8/8 vs early
   progress-break / FDF8<64 break; sample before→after FDF8 deltas.
3. **Max seek** (field bar: past **120634**?).
4. Confirm gates untouched: no new FE1C OR, no new armstart, alarm(2) unchanged.
5. Note 65536 under-fire if fires were sparse in the first minute.

One cycle. No FE1C OR. No new armstart. Throughput FIX B only.
