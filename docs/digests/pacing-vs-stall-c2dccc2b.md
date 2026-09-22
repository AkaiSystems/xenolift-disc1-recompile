# Digest: pacing-vs-stall verdict + R1472 verification

- host: Joshuas-MBP
- date: 2026-09-22
- branch: xenolift-clean @ 2dccc2b (R1472 confirmed present)
- runtime.c sha256 (verified match to expected): 7f31353a545c739cca3172a5e3c5c059d7c4f5b099eca5176ff77f07c0e4e4d7
- disc image: Xenogears (USA) (Disc 1).bin, SLUS_006.64 sha256 dc0b2dd786203d4cce5927c5a3fc85a18f39a3f7406078860076ebb0bbae7119 (verified against the authoritative copy)

## Run 1 — 900s budget pacing test (pre-R1472 tree, own cd_tick_busy fix applied)

- exit status: 137 (fuse SIGKILL, not a crash)
- Highest **organic** field seek reached: **108886** (i.e. no further than the 120s-budget trials already showed — more time did not produce more organic progress)
- At log line ~13559 (early in the 900s window, not near the end), execution discontinuously jumped **108886 -> 239317** (confirmed non-sequential — this is the CD-ROM diagnostic module's `MovieQueueRandomSectorRead` stress-test entry point per `PROJECT_LOG.md` R143, not field-loading progress)
- The remaining ~13 minutes of budget were spent cycling inside that diagnostic region (seek oscillating in the 239317-239329 band); it never returned to resume organic field-loading
- `run.log` itself is capped at a fixed 32001 lines regardless of run duration (confirmed identical line count across 120s and 900s runs) — exact wall-clock timestamp of the final logged line is not reliably known relative to t=900s

## Run 2 — 120s budget, exact commit 2dccc2b (R1472 present), fresh clone, verified SHAs

- exit status: 137 (fuse SIGKILL)
- Final logged state (`[fld2sig]`): `sched=1 seek=108905 pend=3 arm1=0 loaded=0 data=0/2060 cmd=09 FDF8=2048 FE04=0001a969 FDFC=0 FE1C=6 FE20=3 resp_n=3`
- Max seek reached: 108907
- `[pendclr]` at the end: `pending INT1 (site=6 cmd=06 LBA=108905) CLEARED @t=141s, 140s after armed, 1 pumps since set` — one interrupt sat armed 140s and was serviced by exactly 1 pump
- **`[pausestart] R1472` decline lines: 0**
- **`[pausestart] R1467A` fires: 0** (expected, confirmed)
- Notable: in the final several `[fld2sig]` samples, `cmd` and `FE1C` actually **do** cycle through the exact values R1467A/R1472 care about (`cmd=09` with `FE1C=6` appears at seek=108903, 108904, 108905) — but `seek`/`FDF8`/`cmd` keep changing every few log lines, which resets both gates' "tuple-change" frozen-poll counters (R1467A needs 2,000,000 consecutive stable polls; R1472 needs 65,536 qualifying evals) before either can reach threshold. Neither gate is being starved of the right *values* — it's being starved of *stability* long enough to count.

## Verdict

**STALL** (not pure PACING, not INCONCLUSIVE) — with a specific nuance worth flagging: there IS real incremental sector-by-sector advancement (not a byte-identical freeze), and cmd/FE1C DO pass through the R1467A-qualifying tuple periodically. But (a) the 900s trial proves more wall-clock time does not yield more organic distance — it diverts into the CD self-test module instead and never returns, and (b) even within the field-loading band itself, the state changes just fast enough, relative to the two gates' very high stability thresholds (2M polls / 65,536 evals), that neither gate ever confirms a "held" posture to act on. This is a genuine structural block, not something a longer budget resolves on its own.

## Recommendation (no FIX proposed this cycle, per instruction)

The next diagnostic step should target *why* cmd/FE1C never hold still at the qualifying tuple for long enough — i.e., what's driving the churn between cmd=09/FE1C=6 and other values every few log lines — rather than lowering either gate's stability threshold blindly. Nasir should grade from this before any R1464 fix is proposed.
