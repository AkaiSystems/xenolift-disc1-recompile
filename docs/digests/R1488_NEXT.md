# R1488 NEXT — `[idle1436]` completed-read guest-read twin landed (Mac grade)

**Land tip parent:** proposal `ca8fcf6` (`docs/proposals/R1488-idle1436-guest-read-port.md`).  
**Arm:** R1436A `[idle1436]` completed-read busy→idle — guest-read twin on `fn 0x800286CC`.  
**Lane:** Nasir / Programming · Grok executor. **One arm only.** **HOLD next port.**

## What landed

| Item | Value |
|---|---|
| Hook | Guest `fn 0x800286CC` fd-tick / dispatch seam — immediately after R1459W `[fe1clear]`, before R764A `[f5cam]` |
| Twin tag | `[idle1436] R1488 guest-read twin:` (NOT an escape-converter) |
| Alarm / in-tree R1436A | **KEPT** untouched (`[idle1436] R1436A completed-read idle reset`, ~composer/status path) |
| Stuck fence | Dispatch-count at 286CC: `r1488_stuck >= 65536` |
| Budget | `r1488_budget = 4` (separate statics from in-tree R1436A) |
| Gate | `FDF8==0` (memcpy) + `act==1` + `pend==0` + `!sched` + seek `[100000,300000)` + **FE1C-agnostic** + **no hard `cmd==0x02`**; reset stuck on posture break / seek/FDF8 change |
| Fire | Idle-reset only: `cd_read_active=0; cd_data_loaded=0; cd_data_pos=0; cd_data_n=0`. Optional idempotent `FE1C=0` via **memcpy** hygiene |
| Guest cells | Bounds-checked `memcpy` from `xenolift_mem` only — **no** `xenolift_mem_read32` in this twin |
| Alt hook `0x1F801800` | **Not used** (preferred 286CC seam available) |
| R1487 `[c2door]` | **Untouched** (`babf48c` land left as-is) |
| R885 / Claude CD_getsector / second completed-read sibling | Untouched / not dual-landed |

## PASS / REVERT (Hiroshi — Mac; do not invent results)

Per `studio/docs/qa/Xenolift-R1488-idle1436-VERIFY-criteria.md` (QA locked).

**PASS:**

1. Twin tag co-temporal with `[alarmguard]` deferring in `run.log.raw`.
2. Escape by **corrected** timeline: movie-band read at/after last field-band read. **FORBIDDEN:** `grep -cE 'LBA 2[0-9]{5} consumed'` alone.
3. `[wd]` / `[halt]` support meters only — **liveness ≠ escape**. This port is **NOT** a deterministic-escape converter.

**REVERT if:**

- Escape distribution worse vs control (corrected detector)
- Print storm / logcap drowning
- R350-class crash
- `xenolift_mem_read32` gate reads on status-1800 hot path (this land must not add any)
- Any second behavioural arm in the land commit

## Mac grade recipe

```
rg '\[idle1436\] R1488 guest-read twin' run.log.raw
rg '\[alarmguard\]' run.log.raw
# escape = movie-band at/after last field-band; not the retired FMV grep
rg -n 'R1488 guest-read twin|r1488_stuck|0x800286CCu' source/runtime/runtime.c
rg -n 'R1487: \[c2door\] GUEST-READ TWIN' source/runtime/runtime.c   # still present, unchanged
# confirm twin uses memcpy, not mem_read32:
rg -n 'r1488_' source/runtime/runtime.c | rg 'mem_read32' || echo 'OK: no r1488 mem_read32'
```

**HOLD:** no second completed-read sibling (R1452 / R1460F / R1459W twin), no R885 touch, no FE1C-OR / stillness / opcode-0x16 / fldbatch / R1477. Next candidate only after Mac receipts + DIRECTOR next-GO.
