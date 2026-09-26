# R1488 — NEXT rescue: R1436A `[idle1436]` completed-read idle twin

**Lane:** Nasir / Programming · Grok executor  
**Tree pin:** `xenolift-clean` @ `0d33c10` (DIRECTOR tip: R1487 Mac NULL)  
**Scope:** docs proposal ONLY — **do NOT land behavioural code until DIRECTOR explicit next-GO**  
**Numbering:** R1488 (R1487 = `[c2door]` land + Mac NULL; R1488 free)  
**Parent verdict:** `docs/digests/R1487-MAC-VERDICT-wrong-arm-right-idea.md`  
**Format parent:** `docs/proposals/R1487-c2door-guest-read-port.md`

## Why this one (Mac NULL → retarget)

R1487 Mac (n=6, 300s): `[c2door]` twin **0/6**, alarm copy **0/6**, escape
**0/6** (corrected detector). `[alarmguard]` still fires. The port method is
**untested, not disproven** — the arm's gate never became true.

Mac stall posture (trials 2 and 4, identical):

```
fn 0x800286CC   seek=108884   FE1C=00   FDF8=00000000
act=1  loaded=1  sched=0  pend=0
```

That is the **completed-read busy-stuck** class (`FDF8==0` with `act=1
loaded=1`), not `[c2door]`'s boot-era idle-at-seek-0 pending-file posture.
Task A family named by DIRECTOR: **R1452 / R1436A / R1460F v2 / R1459W**.

### Rank (Mac posture match)

| # | Candidate | Mac gate fit | Action fit | Why rank |
|---|---|---|---|---|
| **1** | **R1436A `[idle1436]`** | `act=1` `pend=0` `FDF8=0` seek-band **HOLD**; `FE1C!=0` **FAILS** (Mac FE1C=0); `cmd==02` unchecked in Mac print | **idle-reset** = exactly busy→idle | Highest: disease + action match; only gate adapt is FE1C / cmd flutter |
| 2 | R1460F v2 `[fe1cfd]` | act-agnostic + `FDF8=0` `pend=0` `sched=0` seek-band **HOLD**; **`FE1C==1` FAILS** | idle-reset **+** FE1C clear | Close second; FE1C clear is no-op on Mac (already 0); FE1C==1 gate refuses the receipted stall |
| 3 | R1452 `[fe1cclr]` | needs `FE1C==1` **and** `act==0` — **both FAIL** | FE1C clear only | Wrong fork (idle+stale-FE1C, not busy-stuck) |
| 4 | R1459W `[fe1clear]` | needs all-dead `act==0` + `FE1C!=0` — **both FAIL** | FE1C clear only | Already on `0x800286CC` seam, but wrong disease fork |

**Chosen: R1436A.** Do **not** re-land an R1487/`[c2door]` twin. R1160/c345
migration concept remains open.

## Exact guest-read hook placement (proposal — no land)

| Item | Value |
|---|---|
| **Arm** | R1436A `[idle1436]` completed-read idle transition (in-tree alarm/composer copy stays until GO; twin added) |
| **Preferred hook** | Guest `fn 0x800286CC` fd-tick / dispatch seam (Mac spin site; sibling of existing R1459W / R1405 cameras at that PC) |
| **Alt hook** | `cd_read_impl` `case 0x1F801800` only if DIRECTOR prefers status-poll twin — **must** obey memcpy rule below |
| **Why not seek-0** | Mac gate autopsy: `cd_seek_lba==0` was one of four failing `[c2door]` terms; stall is seek=108884 |
| **Pattern** | R1160/c345: evaluate INLINE on the poll/dispatch the spin actually executes. No `on_alarm_ctx` dispatch. No R885 touch. |

### Gate terms (twin — Mac-aligned completed-read posture)

Read cells via **bounds-checked `memcpy` from `xenolift_mem`** (R1197 / Mac
hazard rule). **Do not** call `xenolift_mem_read32` on the `0x1F801800` hot
path for this twin.

Proposed predicates (in-tree R1436A symbols; Mac-adapted):

1. `xenolift_mem` `FDF8 == 0` (memcpy) — read completed  
2. `cd_read_active == 1` — busy-stuck (Mac key; distinguishes from R1452/R1459W)  
3. `cd_pending == 0` && `cd_scheduled == 0`  
4. `cd_seek_lba >= 100000 && cd_seek_lba < 300000` — includes receipted 108884  
5. **`FE1C` agnostic** (drop R1436A's `xenolift_mem_read32(FE1C) != 0`) — Mac has FE1C=0 and is still stuck; FE1C clear alone is not the lever  
6. **Drop hard `cd_last_cmd == 0x02`** at proposal time — R1460F flutter lesson; receipt cmd at land from Mac/`[kickterms]` or widen to receipted set  
7. Optional reinforce: `cd_data_loaded == 1` (Mac has it)  
8. Stuck confirm: **`r1436a_stuck >= 65536`** (R1436A shape); at `0x800286CC` use dispatch-count fence, not alarm ticks  
9. Budget: keep `r1436a_budget = 4` unless DIRECTOR widens  
10. Reset stuck counter on posture break (existing R1436A else-branch); twin should also tuple-reset on seek/FDF8 change

**Fire body (verbatim R1436A idle legs):**

- `cd_read_active = 0;`  
- `cd_data_loaded = 0;`  
- `cd_data_pos = 0;`  
- `cd_data_n = 0;`  

Do **not** require an FE1C write for PASS on the Mac posture (already 0).
Idempotent `FE1C=0` via memcpy is optional hygiene only.

### HOT-PATH / memcpy rule (hard)

R1487 called `xenolift_mem_read32` ×3 on every `case 0x1F801800` poll —
violates R1197 intent ("NEVER `xenolift_mem_read32` here…"). Mac notes the
same class as the R1490 phantom. **This twin:**

- Uses bounds-checked `memcpy` from `xenolift_mem` for FE1C/FDF8/FE04 (and any
  other guest cells), same shape as existing R1197-safe sites  
- Does **not** add another hooked-read arm on the status-1800 path  
- **Leave R1487 land as-is** (`babf48c`, N=131072, zero fires) — no-op/revert
  hygiene only if DIRECTOR asks; not part of this proposal's land

## Before / after reachability

| | Before (today) | After land (DIRECTOR GO only) |
|---|---|---|
| R1436A during `0x800286CC` depth>0 spin | Composer/1800 copy may be **cold** (R1457-class); gate also refuses Mac FE1C=0 | Twin evaluates on the receipted spin seam with Mac-true gates |
| Alarm / in-tree copy | Keep | Keep; first land = twin only |
| R885 | Untouched | Untouched |
| R1487 `[c2door]` | Zero fires; leave | Leave as-is |
| Pass proof | — | `[idle1436]` (or twin tag) fires **while** `[alarmguard]` is deferring |

## Pass / revert bars

**Pass (Mac, after GO + land):**

1. Ported tag appears while `[alarmguard]` is deferring
   (`grep` co-temporal with `[alarmguard]` in `run.log.raw`).
2. Escape, scored by timeline (**not** by a grep count): a **movie-band read
   at or after the last field-band read**. The former
   `grep -cE 'LBA 2[0-9]{5} consumed'` detector is **WRONG** (boot-era FMV
   probe ~t=2s false positive). Do not use it.
3. `[wd]` and `[halt]` are support meters only. **Liveness ≠ escape.**
4. Protocol: serialized, n≥5, interleave, ~90s budgets OK (stall decided ~35s).

**This port is NOT a deterministic-escape converter.** Task A still stands on
the alarmguard blackout / completed-read reachability alone (Retraction 2 /
BIMODAL). Success = twin fires under blackout with Mac-true posture; escape
rate is observed, not claimed as the mechanism proof from one land.

**Revert if:**

- Escape binary worse vs control distribution  
- New print storm / logcap drowning  
- R350-class crash (SIGSEGV/canary from guest work on interrupted step) —
  twin must stay INLINE, no guest dispatch from signal context  
- Behavioural sneak beyond this one arm  
- Reintroduces `xenolift_mem_read32` gate reads on the status-1800 hot path  

## What is NOT in scope

- **No land until DIRECTOR explicit next-GO** (proposal only this turn)  
- No second behavioural port until that GO; **R1486 still ARMED** / HOLDs unchanged  
- Do **not** re-land R1487 `[c2door]` twin  
- No R885 widen / bypass / remove / "fixes"  
- No `dirack2` / Pause / `fn_0x80042AA8` / `fn_0x80042090` dual-land (Claude)  
- No FE1C OR `(6\|\|0)` / stillness / opcode-0x16 / fldbatch revive / R1477  
- No bell retries (`[fldbell*]` / R1483–R1484 null band)  
- Numbers from R1485+ only  
- No sectors-as-rate metric; primary escape = corrected timeline definition  

## One-at-a-time rule

This is the **next** nominated behavioural port after R1487 Mac NULL retarget.
Do not stack `[cbheal]`, `[f14pump]`, `[parkclose]`, camera twins, or a second
completed-read sibling (R1452 / R1460F / R1459W) in the same land. Next
candidate only after Mac receipts + DIRECTOR next-GO.
