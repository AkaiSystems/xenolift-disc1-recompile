# Grok Handoff: Xenolift Repository Audit and Completion Plan

Audit time: 2026-09-22 05:47 America/Chicago  
Repository: `AkaiSystems/xenolift-disc1-recompile`  
Visibility: private

## 1. What GitHub actually contains

The GitHub API was queried directly. The repository currently has only one branch, `main`, at commit `e962fa14212eea814f79e37040dd23e4a5a7aeb5`. It contains exactly two files totaling 4,370 bytes:

1. `README.md`
2. `docs/xenolift_superagent_handoff.md`

The default branch is `main`. The intended `xenolift-source` branch does not exist. Therefore the Xenolift source tree has **not** been uploaded, despite successful GitHub authentication and local `git init` on the Mac.

Do not claim the repository contains a buildable project yet. It contains documentation only.

## 2. What remains only on the Mac

The working tree is reported at:

`~/Downloads/xenolift`

The following essential items are not present in GitHub and must be pushed from that Mac before another agent can build, inspect, test, or continue the recompile:

- `source/runtime/runtime.c`
- the rest of the runtime sources and headers
- build system files and compiler scripts
- `run.sh` and boot/launch scripts
- bridge source such as `bridge-v1-api.py`
- Xenolift configuration and budget files
- test utilities and diagnostic scripts
- relevant logs and non-secret fixtures that are intentionally versioned

Secrets, API tokens, `.env` files, credentials, and proprietary disc images must not be committed. Large generated binaries and transient logs should be reviewed before inclusion.

## 3. Current verified recompile state

The latest verified source state comes from completed cycle `c1252`:

- Last completed directive: `c1252`
- Last landed fix: `R1470B`
- Expected SHA-256 of `source/runtime/runtime.c`: `096f27debdcdfb5ff92dc4f82e20a705d7dfe0c205d7758899bbbf970d00e36e`
- c1252 restored the receipted one-second defib6 guard after c1251's immediate trigger regressed the trajectory.
- c1252 reached field seek `120634`.
- Rendering reached `747520` VRAM writes.
- Defib6 completed at seeks `108861` and `108995`.
- Run receipt: `RUN rc=0`, `SECONDS=181`, game process exit status `137` at the fuse.

Do not treat exit status 137 as successful game completion. It is a fuse termination receipt.

## 4. Current receipted blocker

The terminal posture at seek `120634` is:

- `FE04 == seek == 120634`
- `FDF8 == 2048`
- command `09`
- `cd_read_active == 0`
- `cd_data_loaded == 0`
- `cd_pending == 0`
- `cd_scheduled == 0`
- `cd_arm_int1_pending == 0`
- `FE1C == 0`
- FIFO receipt `data=2060/0`

R1298B emitted armstart declines at approximately 83 and 113 seconds. The source census identified R1467A as the paused-stamped armed-read vehicle. Its documented posture matches this terminal state except that R1467A requires `FE1C == 6`, while the terminal holds `FE1C == 0`.

This is the receipted mechanism for the next behavioral change. Do not invent a different fix without new receipts.

## 5. Next intended FIX

After the source upload and transport repair, the next cycle should modify only the R1467A block. Bound it uniquely between:

- Start: `R1467A (c1172): THE PAUSED-STAMPED ARMED-READ START.`
- End: `R1464C (c1163): THE PAUSE-SCHEDULED ARMSTART`

Inside that exact block, programmatically require exactly one occurrence of:

```c
xenolift_mem_read32(0x8004FE1Cu) == 6u
```

Replace only that occurrence with a gate admitting FE1C state `6u` or `0u`. Use a cycle-unique marker, derive count expectations programmatically, preserve fail-closed rollback, recompile, set both budget controls to 120 seconds, run Xenogears, and capture the verdict battery.

This fix has not landed. Tokens `c1253` and `c1253b` were both rejected before execution, so no R1471 mutation occurred.

## 6. Transport state

The last foreground bridge was stale:

- Its handshake reported `last_completed=c1251b`.
- The actual latest completed cycle was `c1252`.
- It rejected `c1253` and `c1253b` with `parent_token_mismatch`.
- Neither rejection changed source or launched Xenolift.

Before another directive:

1. Terminate every old `bridge-v1-api.py` process.
2. Start exactly one foreground V1.1 API-key bridge.
3. Require the visible baseline `last_completed=c1252`.
4. Use a fresh directive token parented to `c1252`.
5. Require immediate pickup evidence within one polling interval.
6. Require the final digest before sending another directive.

A new Superagent cannot reuse the old bridge unchanged because the bridge is tied to the old agent and conversation IDs. Generate a fresh bridge for the new agent and enter its access token only through a hidden Terminal prompt. Never commit or paste that token into GitHub.

## 7. Repository completion plan

### Phase A: finish the source upload

From `~/Downloads/xenolift`, stage and commit the local source, then push it to `xenolift-source`. Verify through the GitHub API that the branch exists and contains `source/runtime/runtime.c`, `run.sh`, and the build files.

### Phase B: validate integrity

After upload:

1. Verify `source/runtime/runtime.c` hashes to `096f27debdcdfb5ff92dc4f82e20a705d7dfe0c205d7758899bbbf970d00e36e`.
2. Count repository files and inspect any GitHub tree truncation.
3. Verify no API tokens, credentials, `.env` files, or disc images were committed.
4. Verify no required source was silently omitted by `.gitignore`.
5. Confirm the local and remote commits match.

### Phase C: clean duplicate boot files safely

The Mac folder reportedly contains multiple boot files. Do not delete by filename or age. Inventory boot/launch/start/run candidates, hash them, and archive only exact duplicates after selecting the canonical entry point from source references and actual invocation receipts. Preserve archived files under a dated folder until the new agent builds and runs successfully.

### Phase D: make the repository usable

After verification, choose one clear repository layout:

- merge the source into `main` while preserving `docs/`, or
- make `xenolift-source` the default branch and copy the handoff documents into it.

Add a concise build section describing prerequisites, compile command, run command, 120-second budget controls, expected output paths, and the foreground bridge startup procedure without secrets.

### Phase E: resume the recompile

Only after the repository and bridge are verified:

1. Confirm baseline `c1252`.
2. Ship exactly one fresh FIX for the receipted R1467A FE1C mismatch.
3. Require immediate pickup.
4. Run with `xenolift_budget.txt=120` and `RUN_BUDGET_S=120`.
5. Analyze the final digest before any next cycle.

## 8. Non-negotiable operating rules

- One directive at a time.
- No stacking or duplicate execution.
- No behavioral fix without a receipted mechanism.
- Label every behavioral directive `FIX` and explain its mechanism.
- Use programmatic identifier counts and block-unique selectors.
- Never hand-write post-count expectations.
- Round-trip directive JSON and run `bash -n` on the decoded block.
- Reject trailing double quotes in directive blocks.
- Use only a visible foreground V1.1 handshake bridge.
- No daemon, LaunchAgent, watchdog, or automatic restart.
- Never claim a run started without pickup and live-process evidence.
- Report three plain sentences followed by receipts.

## 9. Definition of repository handoff complete

The handoff is not complete until all of these are true:

- A source-containing branch exists remotely.
- `source/runtime/runtime.c` is present and matches the c1252 SHA-256.
- Build and run scripts are present.
- Secrets and disc images are absent.
- Duplicate boot files are inventoried and safely archived rather than blindly deleted.
- The default branch points to a usable source tree.
- The new agent has a fresh foreground bridge with baseline `c1252`.
- A clean compile succeeds.
- The next 120-second FIX cycle produces both immediate pickup and a final digest.

Until then, GitHub is a documentation handoff, not a functioning Xenolift repository.
