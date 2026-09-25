# R1487 NEXT — `[c2door]` guest-read twin landed (Mac grade)

**Land tip parent:** proposal `f0ff65b` (`docs/proposals/R1487-c2door-guest-read-port.md`).  
**Arm:** `[c2door]` R1191 cell-anchored file delivery — FIRST behavioural port out of `on_alarm_ctx` onto guest status read (R1160/c345).  
**Lane:** Nasir / Programming · Grok executor. One arm only.

## What landed

| Item | Value |
|---|---|
| Hook | `cd_read_impl` `case 0x1F801800:` — immediately after `[spinpost]` R1248, before R1451 |
| Twin tag | `[c2door] R1487 guest-read twin:` (grep `[c2door]` still hits both) |
| Alarm copy | **KEPT** untouched (`[c2door] R1191 cell-anchored delivery`, `c191_ticks >= 5`) |
| Stuck fence | Consecutive status polls holding same FE04/FDF8 posture |
| **N** | **131072** |
| Why N | Receipted R1451 frozen-poll fence on this same `case 0x1F801800` (`r1449_polls > 131072`); proposal asked R1451 shape, not alarm ticks. Exact ftab FE04+FDF8 match is stabler than cmd/sched flutter, so the lighter 128K fence (vs 2M delivery-start siblings) is appropriate |
| R885 / r96gate / R1486 / R1482 | Untouched |
| Claude Pause / dirack2 / `fn_0x80042AA8` | Not in this commit |

Cell predicates + delivery + R896/R897 completion stamps: same intent as alarm R1191 (`c191_tab[]` file band 108754–109158).

## PASS / REVERT (Hiroshi — Mac; do not invent results)

**PASS:**

1. `[c2door]` co-temporal with `[alarmguard]` deferring in `run.log.raw`  
   (`rg '\[c2door\]' run.log.raw` near `rg '\[alarmguard\]'` while depth>0 spin).
2. Binary escape (not rate):  
   `grep -cE 'LBA 2[0-9]{5} consumed'` — distribution under serialize **n≥5**, interleave, **~90s** budgets.
3. Report `[wd]`+`[halt]` as **leading only** (correlation-aware; do not overclaim mechanism).

**REVERT if:**

- Escape binary worse vs control distribution
- Print storm / logcap drowning
- R350-class crash (SIGSEGV/canary from guest work on interrupted step)
- Any other rescue/camera sneaks into the same land (this land is twin-only)

## Mac grade recipe

```
# build as usual, run ~90s serialize n>=5 interleaved vs control tip
rg '\[c2door\]' run.log.raw
rg '\[alarmguard\]' run.log.raw   # expect deferring while twin can still fire
grep -cE 'LBA 2[0-9]{5} consumed' run.log.raw
rg -c '\[wd\]|\[halt\]' run.log.raw   # leading only

# source gates
rg -n 'R1487 guest-read twin|N=131072' source/runtime/runtime.c
rg -n '\[c2door\] R1191 cell-anchored' source/runtime/runtime.c   # alarm still present
rg -n 'R885|alarmguard' source/runtime/runtime.c | head   # untouched by this land
```

Push grade note under `docs/digests/r1487-c2door-guest-<stamp>.md` with PASS/REVERT and the escape counts. Next candidate only after DIRECTOR next-GO.
