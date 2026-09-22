# Xenolift Recompile Superagent Handoff

Updated: 2026-09-22 (DIRECTOR docs sync — FE1C widen already in pinned SHA)

## Objective
Continue the Xenogears Disc 1 Xenolift recompile at maximum safe cadence. The recompile is the only goal. Do not spend cycles on bridge mechanics unless transport is blocking a recompile cycle.

## Repo map (GitHub)
- Active branch: **`xenolift-clean`** — allowlisted live tree (`source/`, `ext/`, `docs/`).
- Archive branch: **`xenolift-source`** — frozen messy dump. Never rewrite or delete. Tag: `archive/xenolift-source-messy-import-2026-09-22`.
- `main` — early docs-only commits; do not treat as the live tree.
- Mac disc `.bin` and secrets stay on the Mac only.

Owner map: edit/run in `source/`; read-only refs in `ext/`; history/handoffs in `docs/`. Folder `source/` ≠ branch `xenolift-source`.

## Owner requirements
- One cycle at a time: directive, immediate pickup, final digest, analysis, next directive.
- Never stack directives.
- No behavioral fix without a receipted mechanism.
- Every behavioral directive is labeled `FIX` and explains the causal mechanism.
- Every run targets `120` seconds through `xenolift_budget.txt` and `RUN_BUDGET_S=120`.
- Use programmatic identifier counts and block-unique selectors. Never hand-write post-count expectations.
- Verify exact directive JSON by round trip, decode the block, run `bash -n`, and confirm no trailing double quote.
- Use the V1.1 foreground API-key handshake bridge only. No daemon, LaunchAgent, watchdog, background restart, or stacked worker.
- Report in three plain sentences followed by receipts.
- Never claim the program is running without a confirmed pickup and runtime evidence.

## Current verified source state
- Last completed directive: `c1252`
- Last labeled FIX in that cycle: `R1470B`
- Pinned `source/runtime/runtime.c` SHA-256: `a6d3279bf56d3d8aab13c35aa08515286fe6dd4db6f79421b6ddbd074940a4ce`
- Behavioral baseline for c1252 was SHA `096f27debdcdfb5ff92dc4f82e20a705d7dfe0c205d7758899bbbf970d00e36e` (already contained FE1C `6||0`). Comment-only R1467A header sync on 2026-09-22 bumped the file SHA to `a6d3279bf56d3d8aab13c35aa08515286fe6dd4db6f79421b6ddbd074940a4ce` with **no executable change**.
- c1252 boot run: `RUN rc=0`, `SECONDS=181`, game process exit status `137` at the fuse.
- c1252 reached field seek `120634` and rendering reached `747520` VRAM writes.
- Defib6 completed at seeks `108861` and `108995`.

### R1467A FE1C gate — already in this SHA
DIRECTOR census (2026-09-22) on `xenolift-clean`: inside block
`R1467A (c1172): THE PAUSED-STAMPED ARMED-READ START.` … before
`R1464C (c1163): THE PAUSE-SCHEDULED ARMSTART` (~L3279–L3313), the live gate is already:

```c
&& (xenolift_mem_read32(0x8004FE1Cu) == 6u || xenolift_mem_read32(0x8004FE1Cu) == 0u)
```

Fire log text already includes `FE1C-in-0-6`.

**Do not re-apply** a “widen FE1C to 6||0” FIX. Tokens `c1253` / `c1253b` were rejected for stale bridge (`last_completed=c1251b`) and never ran — but the uploaded tree at this SHA already embeds the widen (pre-upload / undocumented relative to those tokens). A naive “require exactly one `== 6u` then replace” selector is **unsafe** on current text (matches the left arm of the OR and can double-OR).

## Current receipted blocker (runtime, not missing OR)
At seek `120634` (c1252 terminal):
- `FE04 == seek == 120634`
- `FDF8 == 2048`
- `cmd == 09`
- `cd_read_active == 0`
- `cd_data_loaded == 0`
- `cd_pending == 0`
- `cd_scheduled == 0`
- `arm1 == 0`
- `FE1C == 0` (allowed by current R1467A gate)
- staged FIFO posture: `data=2060/0`

R1298B emitted armstart declines at ~83s and ~113s.

If Mac still sticks here on **this** SHA, investigate **binary ≠ pinned SHA**, **2M-confirm thrash**, or **another vehicle** — not “FE1C still equals 6 only.”

## Next action (verify, not phantom FIX)
Mac 120s verify against the pinned SHA (Hiroshi matrix; Akitoshi success bar):

1. Bridge: stop all `bridge-v1-api.py`; start one foreground bridge; require `HANDSHAKE BASELINE: last_completed=c1252`.
2. Build from `source/` (or Mac tree matching this SHA). Log source SHA + binary identity.
3. Run 120s. Grade:
   - **PASS:** `[pausestart]` R1467A near seek 120634 + seek advances + field continues; no new HALT; armstart/defib6/VRAM not worse than c1252 when probed. FE1C is observational only.
   - **INCONCLUSIVE:** budget/receipt/SHA gaps.
   - **REGRESS:** new HALT; lost pausestart/field; seek worse; thrash-dominant stuck.
4. Stuck with no pausestart → `binary≠SHA` or `confirm_thrash`. **`reapply_OR_forbidden=YES`.**

Do **not** claim continuous-Disc1 / endgame from one verify cycle.

## Transport recovery
```bash
pkill -TERM -f '[b]ridge-v1-api.py' 2>/dev/null || true
sleep 1
cd ~/Downloads/xenolift   # or cloned source/ sibling with bridge script
exec /usr/bin/python3 bridge-v1-api.py
# Prefer: cd <repo>/source && exec /usr/bin/python3 bridge-v1-api.py
```

Rejected tokens (no source change, no launch): `c1253`, `c1253b` — `parent_token_mismatch`, stale `last_completed=c1251b`.

## Transfer limitation
Bridge is tied to Superagent / conversation IDs. Clones need a regenerated bridge and a fresh token via hidden Terminal prompt. Never commit tokens.
