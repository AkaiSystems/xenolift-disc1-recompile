# CAMERA proposal: R1480 `[xcam]` last-N sector deliveries before stream stop (ONE next step)

**Author lane:** Programming · Nasir (grade for DIRECTOR)
**Tree pin:** `xenolift-clean` @ `5bde502` (runtime sha256 `604f99a11b46f94259e0ebf2f3e9b6972efc10ffffb9759b78fae9a4950e6a24`)
**Digest:** `docs/digests/R1479-first-results-and-a-trap.md`
**reapply_OR_forbidden:** YES
**Verdict ask:** APPROVE camera-only — no behavior change this cycle

## Grade of R1479 first trial (context for this ask)

| Claim | Verdict |
|-------|---------|
| Gradeable on ≥1500s `[mscycle]` gap bar | **NO** (150s/300s killer) — full gap grade waits for proper long digest |
| FIRE=128 / CLEAR=128 → R96 re-arm real | **PASS (proven)** |
| DRAIN==0 → undrained FIFO / R96 loop harm | **FAIL / TRAP** — DMA delivers; PIO `802` camera stays 0 while healthy |
| FIRE+DRAIN0+CLEAR@pos0 → R96 behavioral FIX | **DOES NOT FIRE** — leave R96 alone |
| Shape | Healthy ~88 sec/s burst (~176 sectors / 2s) → hard stop ~108910 (same posture) |
| R1476 `[fldbatch]` =18 | Fires; outcome unchanged; rate-profile bar still **invalid**; **HOLD revive** |
| R1477 | Already **REVERTED**; do not re-land |

**Decision-rule revision (locked):** replace PIO-DRAIN with **DMA/fldsec delivery** evidence. `pos==0` after DMA is normal. Do not propose R96 gate change from R1479 tallies alone. A ≥1500s r96cam run may still refine FIRE-during-stop counts, but will **not** rehabilitate DRAIN==0 as loop proof.

## Why this camera (not another steady-state rate fix)

Failure mode is a **regime transition** at seek ≈108905–108910, not intrinsic slowness and not (on present evidence) R96 harm. Instrument the **last N deliveries before `[fldsec]` stops advancing**, so the delta “streaming 88/s → frozen” is visible in one dump.

## What (camera only)

**Ring buffer** of last **N=16** sector-complete events at the existing DMA/`[fldsec]` site (`source/runtime/runtime.c` ~L6217–6254, after successful DMA sector consume, before or with `cd_seek_lba++`).

Each slot records (print-ready ints only):
- wall `t`, `fldsec_n`, `LBA`/`cd_seek_lba`, `madr`, DMA `bytes`, `fifo pos/n`, `FDF8`, `FE1C`, `FE20`, `A22C`, `cmd`, `act`, `pend`, `sched`, `flag578A6`, `cur_fn` (if cheap), `r31` (if already sampled elsewhere — else omit)

**Arm stall dump** (reuse freeze / on_alarm / fldsec-stall watcher seam — prefer existing “fldsec unchanged” path ~L1344+):
- When `g_fldsec_total` unchanged for **≥3s** (or existing stall threshold) **and** `seek ∈ [108880, 109050]` (plateau band) **and** dump cap **<8**:
  - Print `[xcam] STALL #%u @t=… seek=… FDF8=… FE1C=… act=… pend=…` then dump ring oldest→newest as `[xcam] N-k: …` lines.
- Cap: 8 stall dumps / run; ring never allocates beyond static 16 slots.

**Optional one-line heartbeat** every successful field-band DMA sector (cap 32, or only when `seek ∈ [108880, 109050]`): `[xcam] DELIV #%u LBA=… t=… FDF8=…` — only if DIRECTOR wants denser near-edge trail; default = **ring+stall dump only** to spare log budget / 16k cap.

Log tags: `[xcam] STALL` · `[xcam] N-*` (ring lines) · optional `[xcam] DELIV`

## Gates

- Field plateau band for stall dump: `seek ∈ [108880, 109050]` (covers 108905–108910 transition; adjust if Mac sees stop edge move)
- Zero behavior: no touch of pend / force / 578A6 / FDF8 / FE1C / DMA path
- Caps as above; respect R751 first/last 16k — put stall dumps late enough that middle truncation cannot hide them (or mirror key lines to a side file if Mac already has that path)

## Decision rule after **one ≥1500s** external-killer trial

| Receipt shape | Decision |
|---------------|----------|
| Last N deliveries show healthy DMA dest/`FDF8` drain, then next posture flips (`act`/`pend`/`cmd`/`FE1C`/`fn`) with **no further `[fldsec]`** | Transition named → next cycle propose **one** behavioral fix on the proven flipped term only |
| Deliveries already sick (bad `madr`, FDF8 stuck, act=0) before the last N | Failure is **upstream of** the stop LBA — do not “accel” the plateau |
| No stall dump / fldsec keeps ticking past 109050 | Band wrong or stop moved — retarget band, no FIX |
| Stop only ends via R1283/R473 with empty ring | Camera miss — widen arm condition, still no FIX |

**Pass/fail for eventual fix (unchanged):** `[mscycle]` gaps on ≥1500s — **no gaps >100s**. Do not use ~1.00 LBA/s or 180s windows.

## NON-goals (HARD)

- No FE1C OR (`reapply_OR_forbidden=YES`)
- No new stillness / armstart
- No opcode-0x16
- No R96 behavior change
- Do **not** revive fldbatch / re-land R1477
- No throughput “K=” burst this cycle

## Ask

Approve **R1480 `[xcam]` camera only**. Land, Mac rebuild, **≥1500s** external killer. Parallel: any leftover R1478/`[hbcam]` lines are observational only. After that digest: Nasir grades → at most **one** behavioral next step from the transition dump.
