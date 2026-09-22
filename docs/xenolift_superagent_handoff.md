# Xenolift Recompile Superagent Handoff

## Objective
Continue the Xenogears Disc 1 Xenolift recompile at maximum safe cadence. The recompile is the only goal. Do not spend cycles on bridge mechanics unless transport is blocking a recompile cycle.

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
- Last landed FIX: `R1470B`
- Current `runtime/runtime.c` SHA-256: `096f27debdcdfb5ff92dc4f82e20a705d7dfe0c205d7758899bbbf970d00e36e`
- c1252 restored the receipted one-second defib6 guard after c1251's immediate trigger regressed the trajectory.
- c1252 boot run: `RUN rc=0`, `SECONDS=181`, game process exit status `137` at the fuse.
- c1252 reached field seek `120634` and rendering reached `747520` VRAM writes.
- Defib6 completed at seeks `108861` and `108995`.

## Current receipted blocker
At seek `120634`:
- `FE04 == seek == 120634`
- `FDF8 == 2048`
- `cmd == 09`
- `cd_read_active == 0`
- `cd_data_loaded == 0`
- `cd_pending == 0`
- `cd_scheduled == 0`
- `arm1 == 0`
- `FE1C == 0`
- staged FIFO posture: `data=2060/0`

R1298B emitted armstart declines at 83s and 113s. The source census identified R1467A as the paused-stamped armed-read vehicle. Its documented posture matches the terminal except its gate requires `FE1C == 6`; the terminal holds `FE1C == 0`.

## Next intended FIX
A new cycle should widen the FE1C term only inside the block uniquely bounded by:
- start marker: `R1467A (c1172): THE PAUSED-STAMPED ARMED-READ START.`
- following marker: `R1464C (c1163): THE PAUSE-SCHEDULED ARMSTART`

Inside that block, programmatically require exactly one occurrence of:
`xenolift_mem_read32(0x8004FE1Cu) == 6u`

Replace it with a gate admitting `6u || 0u`, using a cycle-unique marker. Derive all count expectations from the selected block and replacement strings, preserve fail-closed rollback, recompile, and run 120 seconds.

## Transport blocker at handoff
The foreground bridge that rejected `c1253` and `c1253b` remained stale at `last_completed=c1251b`, even though the `c1252` digest had landed. Both directives were rejected before execution. No R1471 source mutation occurred.

Before sending another directive:
1. Stop every `bridge-v1-api.py` process.
2. Start exactly one foreground bridge.
3. Require `HANDSHAKE BASELINE: last_completed=c1252`.
4. Only then send a fresh token parented to `c1252`.

Suggested local recovery command after pressing Ctrl-C:
```bash
pkill -TERM -f '[b]ridge-v1-api.py' 2>/dev/null || true
sleep 1
cd ~/Downloads/xenolift
exec /usr/bin/python3 bridge-v1-api.py
```

## Important transfer limitation
The existing bridge is hardcoded to the current Superagent ID and conversation ID. A cloned Superagent needs a regenerated foreground bridge configured with the clone's agent ID and its new conversation ID. Do not copy or expose the old Base44 access token in this handoff. Capture a new token securely through the hidden Terminal prompt.

## Last rejected tokens
- `c1253`: rejected, `parent_token_mismatch`, stale bridge reported `last_completed=c1251b`.
- `c1253b`: rejected, `parent_token_mismatch`, stale bridge reported `last_completed=c1251b`.

Neither token changed source or launched Xenolift.
