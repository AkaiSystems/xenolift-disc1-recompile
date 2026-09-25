# R1487 — FIRST rescue: `[c2door]` R1191 → guest-read port

**Lane:** Nasir / Programming · Grok executor  
**Tree pin:** `xenolift-clean` @ `84f32308c579b16fc371d06af9788a5ae079ebd3`  
**Scope:** docs proposal ONLY — **do NOT land behavioural code until DIRECTOR explicit GO / greenlight**  
**Numbering:** R1487 (R1485 = census, R1486 = GP0 tripwire; avoid R1476 collision)  
**Parent digest:** `docs/digests/BIMODAL-escape-tracks-alarm-context-liveness.md`  
**Census:** `docs/proposals/R1485-alarm-context-reachability-census.md`

## Why this one FIRST

Task A (ELEVATED) asks for the first **behavioural** rescue to migrate out of
`on_alarm_ctx` into guest-read (R1160/c345), addressing the alarmguard blackout
without claiming that the port predicts escape. Chosen arm:

**`[c2door]` R1191 — cell-anchored file delivery**

Rationale (≤3):

1. **Behavioural + dead at depth>0.** Mutates drive/RAM (disc_read_lba → dst,
   completion stamps, FE1C/FE04/FDF8 clear). Lives post-R885 in `on_alarm_ctx`
   (~L13851–L13909). Census row: reachable @ depth>0? **NO**.
2. **Drive/read progress during spin, not camera-only.** Arm comment itself
   names the failure class: request cells match a known ftab file, CD idle,
   guest spun on **`0x1F801800=0x24`** for billions of polls with no Setloc.
   Table LBAs (108754–109158) sit in the field-band stall zone from the BIMODAL
   digest (hard-stalls ~108882–108943). Delivering the stuck file is progress
   that can keep the retry loop alive — the escape-vs-stall class, not a rate.
3. **Hot guest-read site already proven.** Status `case 0x1F801800` in
   `cd_read_impl` already hosts `[spinpost]` R1248 (and siblings). No Pause /
   `fn_0x80042AA8` / `dirack2` dual-land — this is a general request-cell stuck
   delivery door, not Claude's Pause/GetStat FIX.

Retraction 2: liveness does **not** predict escape. `[wd]` and `[halt]` are
support meters only, not escape predictors. Task A priority-via-escape-rate is
**VOID**; Task A still stands on the alarmguard blackout alone. This port tests
rescue reachability under depth>0 spin; do **not** claim an escape-rate effect
or a proven mechanism from one land.

## Exact guest-read hook placement

| Item | Value |
|---|---|
| **Arm** | `[c2door]` R1191 (alarm copy stays until land GO; twin added) |
| **Polled MMIO** | `0x1F801800` (CD status) |
| **Hook function** | `cd_read_impl` (`source/runtime/runtime.c`) |
| **Hook site** | `switch (p) { case 0x1F801800:` — **~L3228** after tip `84f3230` (sibling of existing `[spinpost]` / R1451 / R1459* blocks) |
| **Cell predicates (unchanged intent)** | FE1C==1, FDF8!=0, FE04+FDF8 match `c191_tab[]`, `cd_seek_lba==0`, `!cd_pending`, `!cd_read_active`, `!cd_scheduled`, dst in RAM, one-fire-per-posture |
| **Stuck detector adaptation** | Alarm uses `c191_ticks >= 5` (alarm rounds). Guest-read twin must use a **poll-count** fence on consecutive status reads that hold the same FE04/FDF8 posture (same shape as R1451's frozen-poll confirm on this case) — not alarm ticks. Exact N at land time from receipted spin density; proposal does not invent a magic constant now. |
| **Pattern** | R1160/c345: serve INLINE on the poll the spin actually executes. No `on_alarm_ctx` dispatch. No R885 touch. |

Optional secondary anchor (NOT first land): `xenolift_mem_read32` watches already list
`0x8004FE04` / `0x8004FDF8` / `0x8004FE1C` (~L11179). Prefer **status 1800** first
because that is the receipted spin poll for this arm's class.

## Before / after reachability

| | Before (today) | After land (DIRECTOR GO only) |
|---|---|---|
| `[c2door]` at depth>0 | **NO** — post-R885 drain never runs under hard spin | **YES** — twin evaluates on guest status reads mid-step |
| Alarm copy | Primary / only | Keep or thin later; one FIX at a time — first land = twin only |
| R885 | Untouched | Untouched |
| Pass proof | — | `[c2door]` line in `run.log.raw` **while** `[alarmguard]` is deferring |

## Pass / revert bars

**Pass (Mac, after GO + land):**

1. Ported tag appears while `[alarmguard]` is deferring
   (`grep '[c2door]'` co-temporal with `[alarmguard]` in `run.log.raw`).
2. Escape, scored by timeline (not by a grep count): a **movie-band read at or
   after the last field-band read**. The former
   `grep -cE 'LBA 2[0-9]{5} consumed'` detector is **WRONG**: it matches the
   boot-era FMV probe at about t=2s and can produce a false positive. Do not
   use it.
3. `[wd]` and `[halt]` are support meters only. **Liveness ≠ escape**; they are
   not predictors and must not be used to claim an escape effect.
4. Protocol: serialized, n≥5, interleave, ~90s budgets OK (stall decided ~35s).

**Revert if:**

- Escape binary worse vs control distribution (more hard-stalls / fewer escapes)
- New print storm / logcap drowning
- R350-class crash (SIGSEGV/canary from guest work on interrupted step) —
  twin must stay INLINE on the read path, no guest dispatch from signal context
- Behavioural sneak beyond this one arm (any other rescue/camera land in same commit)

## What is NOT in scope

- **No land until DIRECTOR explicit GO / greenlight** (proposal only this turn)
- No R885 widen / bypass / remove
- No `dirack2` / Pause / `fn_0x80042AA8` / `fn_0x80042090` dual-land (Claude lane)
- No bell retries (`[fldbell*]` / R1483–R1484 null band)
- No FE1C OR `(6\|\|0)` / `reapply_OR_forbidden`
- No fldbatch revive, no R1477 re-land
- No reclaiming r96gate as confirmed causal (keep gate; variance retracted the A/B)
- No R885 "fixes", no pile of arms, no camera-only first when Task A asks behavioural
- No sectors-as-rate metric (SUPERSEDED); primary = the corrected timeline
  escape definition above
- HOLDs otherwise; R1486 awaits Mac; R1482 stands

## One-at-a-time rule

This is the **first** nominated behavioural port. Do not stack `[cbheal]`,
`[f14pump]`, `[parkclose]`, or camera twins in the same land. Next candidate
only after Mac receipts + DIRECTOR next-GO; no second behavioural port until
that next GO.
