# Next Mac cycle: R1481 `[r96gate]` — CD_flush exit (behavioral)

Landed on `xenolift-clean`. **ONE behavioral FIX** this cycle (DIRECTOR authorized Nasir land).
`reapply_OR_forbidden=YES`. HOLD stillness/armstart / FE1C OR / opcode-0x16 / fldbatch revive / R1477 re-land.
Do **not** touch INT3→INT1 ack-pair or DMA next-sector arm.

Grep tags: `[r96gate]` · `[pendclr]` · `[alarmguard]` · `[wedge]`  
Proposal: `docs/proposals/R1481-r96-flush-exit-gate.md`  
Digest base: `docs/digests/ROOT-CAUSE-cdflush-alarmguard-deadlock.md`

## Pass / fail (grade **`run.log.raw` only**)

| Meter | FAIL | PASS |
|-------|------|------|
| `[pendclr]` sampled print count | ~15699 ≈ 1.03B clears | **orders of magnitude down** |
| `[alarmguard]` / `[wedge]` `cur_fn` | `8004252C` stuck | **absent** (or not 30s STUCK) |
| `[r96gate] SUPPRESS` | missing | present in former storm era |
| Regression vs `bcbfce8` | earlier stream death | not worse |

## Paste-ready Mac steps

```bash
cd /path/to/xenolift-disc1-recompile
git fetch origin && git checkout xenolift-clean && git pull --ff-only origin xenolift-clean
rg -n 'R1481 \[r96gate\]|r1481_sector_ready' source/runtime/runtime.c
# rebuild usual way; ≥1500s external killer preferred
# Grade RAW only:
rg '\[pendclr\]' run.log.raw | tee /tmp/pendclr.txt | wc -l
rg '\[r96gate\]' run.log.raw | tee /tmp/r96gate.txt | wc -l
rg '8004252C' run.log.raw | rg 'alarmguard|wedge' | tee /tmp/flush-wedge.txt
rg '\[wedge\].*8004252C|cur_fn=8004252C' run.log.raw | head -40
rg 'seek=' run.log.raw | tail -40
```

Push `docs/digests/r1481-r96gate-<stamp>.md` with pendclr counts, wedge/alarmguard on 4252C, suppress samples, max seek, PASS/FAIL/REVERT call.
