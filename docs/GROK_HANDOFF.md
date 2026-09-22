# Grok Handoff: Xenolift Repository Status

Original audit: 2026-09-22 05:47 America/Chicago (docs-only `main`).  
**Docs sync:** 2026-09-22 — DIRECTOR (post `xenolift-clean` org + R1467A census).

Repository: `AkaiSystems/xenolift-disc1-recompile` (private)

## 1. What GitHub contains now

| Branch | Role |
|--------|------|
| `xenolift-clean` | **Active** allowlisted live tree (`source/`, `ext/`, `docs/`) |
| `xenolift-source` | **ARCHIVE** messy full working-tree dump — never rewrite/delete. Tag: `archive/xenolift-source-messy-import-2026-09-22` |
| `main` | Early docs-only history; not the live tree |

Do **not** use the 05:47 audit claim that “only two files exist” or “`xenolift-source` does not exist.” That was true at audit time and is obsolete.

Layout on `xenolift-clean`:
- `source/` — Rust, `runtime/`, `hle/`, `run.sh`, bridge, tools, patches
- `ext/` — Noah + PSX oracle references (not the game you edit)
- `docs/` — handoffs and history

Secrets, API tokens, `.env`, and proprietary disc images must not be committed.

## 2. Mac vs GitHub

Disc image and live Mac scratch remain on the owner Mac (`~/Downloads/xenolift` and/or Desktop disc path). GitHub holds reviewable source on `xenolift-clean`. Prefer Mac cycles from a tree whose `runtime.c` matches the pinned SHA below.

## 3. Verified recompile baseline (`c1252`)

- Last completed directive: `c1252`
- Last labeled fix in that cycle: `R1470B`
- Pinned SHA-256 of `source/runtime/runtime.c`: `096f27debdcdfb5ff92dc4f82e20a705d7dfe0c205d7758899bbbf970d00e36e`
- Seek `120634`; VRAM writes `747520`; defib6 at `108861` / `108995`
- `RUN rc=0`, `SECONDS=181`, process exit `137` (fuse — not game completion)

## 4. Receipted terminal posture (`c1252`)

Seek `120634`: FE04==seek, FDF8==2048, cmd==09, act/loaded/pend/sched/arm1 all 0, **FE1C==0**, FIFO `data=2060/0`. R1298B armstart declines ~83s / ~113s.

## 5. R1467A FE1C — CORRECTION vs older handoff text

**Older text claimed:** R1467A requires `FE1C==6` only; next FIX is widen to `6||0`; fix has not landed because `c1253`/`c1253b` never executed.

**Current SHA-pinned source:** the R1467A block already contains  
`(FE1C == 6u || FE1C == 0u)` and `FE1C-in-0-6` fire labeling (~L3299 in block ~L3279–L3313).

Therefore:
- **NO-GO** on a PR or directive whose only job is “implement FE1C 6||0.”
- **GO** on Mac 120s **verify** of this SHA for `[pausestart] R1467A`, seek advance, field continue (Hiroshi matrix). FE1C is observational. `reapply_OR_forbidden=YES`.
- If stuck with no pausestart: investigate binary≠SHA or confirm thrash — not another OR.

Akitoshi success bar: subsystem wins only for this cycle; no continuous-Disc1 claim from one gate/verify.

## 6. Transport

Before any cycle: one foreground bridge; `HANDSHAKE last_completed=c1252`; no stacked workers.  
`c1253` / `c1253b` were rejected (`parent_token_mismatch`, stale `c1251b`) and changed nothing.

## 7. Operating rules (unchanged)

One directive at a time; no behavioral fix without receipted mechanism; programmatic selectors; `bash -n`; 120s budgets; three-sentence digest + receipts; never claim running without pickup evidence.

## 8. Definition of “docs sorted” (this sync)

- README owner map distinguishes `source/` folder vs `xenolift-source` archive branch.
- This file and `docs/xenolift_superagent_handoff.md` no longer instruct a phantom FE1C widen.
- Next human/agent action is Mac verify + optional comment sync inside `runtime.c` header — not re-landing `6||0`.
