# Next Mac cycle: R1486 `[r1486]` first-content GP0 tripwire (camera)

Landed on `xenolift-clean` tip that includes `9e76fe6` (R1481 [r96gate] RESTORE).
**Camera only** — no behavioural change. HOLD R1485 ports / R885 / Pause lane /
[xcam]/[fldfrz].

## Grade steps

1. Build + run as usual; collect `run.log.raw`.
2. Look for the tag:
   ```
   rg '\[r1486\]' run.log.raw
   ```
   - **Expect silence** if the run still only issues black fills (current era:
     dma2≈3, three GP0(02) fills, nonblank 0%).
   - **Pass when content appears:** one line like
     `[r1486] FIRST non-fill GP0: cmd=.. class=poly|rect|line|copy|other ...`
3. Binary / source gate:
   ```
   strings <built-binary> | rg '\[r1486\]'
   rg -n 'R1486|\[r1486\]' source/hle/hle_gpu.c
   ```
4. Confirm r96gate still present (untouched by this land):
   ```
   rg -n 'R1481 \[r96gate\]|r1481_sector_ready' source/runtime/runtime.c
   ```
5. REVERT if the tag fires on a fill-only run, or if any GPU submit semantics changed.

Push a short grade note under `docs/digests/r1486-gp0first-<stamp>.md` with
PASS/SILENT/REVERT and the first non-fill line (if any).
