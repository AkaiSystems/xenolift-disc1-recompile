# Next Mac cycle: R1482 grade — HOLD before next FIX (≥1500s preferred)

Landed tip: **`988285f`** (`988285fd0608b7d09e2331e777f4987bbb318022`).  
runtime SHA-256: `20f9339daa33c7b3dfcf031185448636b4e9e648ee392d9f096735f21b22b80a`.  
Digest: `docs/digests/r1482-fe1c-bell-budget-mac180.md`.

**ONE instruction:** do **not** land a new behavioral FIX this cycle. Grade the 180s land on a **longer** Mac run; cameras that were dead under the ack storm may now speak.

`reapply_OR_forbidden=YES`. HOLD: FE1C OR / stillness/armstart / opcode-0x16 / fldbatch revive / R1477 re-land / one FIX at a time.

Grep tags: `[fld-rearm]` · `[pendclr]` · `[fldsec]` · `[xcam]` · `[alarmguard]` · `[wedge]` · `[mscycle]`

## Why HOLD (not R1483 yet)

180s already showed R1482’s own bars PASS and REVERT (stop-after-96) absent. New tip ~**109200** is past R411 band `<109150` and still short of door **~120634**. Reason for the new tip is **unknown** at 180s — prefer evidence over speculative FE1C/stillness change.

## Pass / fail for the long grade (`run.log.raw` only)

| Meter | Watch |
|-------|--------|
| max seek / last `[fldsec]` LBA | Continues past 109200? Hard plateau? Toward 120634? |
| `[fld-rearm]` bell N/96 | Exhausts at 96; stream after |
| `[pendclr]` / armline=7357 | Stay collapsed (regression = REVERT class) |
| `[xcam]` / alarm-context tags | Finally non-zero? Name transition |
| `[alarmguard]`/`[wedge]` `8004252C` | Must not return to storm-era stuck |
| nonblank / door | Still non-claims unless actually hit |

**Door PASS** still requires seek past **120634** + field continue — do not claim from partial progress.

## Paste-ready Mac steps

```bash
cd /path/to/xenolift-disc1-recompile
git fetch origin && git checkout xenolift-clean && git pull --ff-only origin xenolift-clean
git rev-parse HEAD   # expect 988285fd0608b7d09e2331e777f4987bbb318022
sha256sum source/runtime/runtime.c
# expect 20f9339daa33c7b3dfcf031185448636b4e9e648ee392d9f096735f21b22b80a
rg -n 'R1482|close the budgeted bell' source/runtime/runtime.c

# rebuild usual way; ≥1500s EXTERNAL killer preferred (sleep N; pkill -9)

# Grade RAW only:
rg '\[pendclr\]' run.log.raw | tee /tmp/pendclr.txt | wc -l
rg 'armline=7357' run.log.raw | wc -l
rg '\[fld-rearm\]' run.log.raw | tee /tmp/fld-rearm.txt | tail -20
rg '\[fldsec\]' run.log.raw | tee /tmp/fldsec.txt | tail -40
rg '\[xcam\]' run.log.raw | tee /tmp/xcam.txt | head -40
rg '8004252C' run.log.raw | rg 'alarmguard|wedge' | tee /tmp/flush-wedge.txt
rg 'seek=' run.log.raw | tail -40
# max seek extractor as usual; note wall time of last fldsec advance
```

Push an addendum digest only after the long run (meters + HOLD→camera/FIX decision). No speculative land from 180s alone.
