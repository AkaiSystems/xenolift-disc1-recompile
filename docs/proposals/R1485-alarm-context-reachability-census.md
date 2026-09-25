# R1485 — Alarm-context reachability census

**Lane:** Nasir / Programming · Grok executor  
**Tree pin:** `xenolift-clean` @ `43e44569964e4777fe2e278f6a4469533a7986d1`  
**Scope:** docs + census ONLY — no behavioural land, no R885 touch, no migration this turn  
**Numbering:** R1485+ (do not reuse R1476 / R1483 / R1484)

## Why this census exists

R885's alarmguard correctly defers `on_alarm_ctx` whenever `g_guest_depth > 0`
(prevents R350 SIGSEGV/canary from dispatching guest work on an interrupted
guest step). Measured through freezes, the rescue/camera tree that lives
*below* that guard prints zero:

`[wd] [park] [halt] [fldfrz] [fld2sig] [fldbell] [trail] [xcam]`

The bug is **placement** (work parked in alarm context), not the deferral.
Durable shape already in tree: **R1160 / c345** — deliver INLINE from the
guest's own read/MMIO hook of the polled cell.

This has now been seen at **two** wedges (structural, not one-off):

| | Before R1482 | After R1482 (current) |
|---|---|---|
| Guest spin | `fn 0x8004252C` CD_flush | `fn 0x8004247C` (epilogue of `fn_0x80042090`) |
| depth | 2 | 1 |
| cmd | 06 ReadN | 09 Pause |
| Drive | act=1 loaded=1 pend=1 sched=0 FE1C=00 | act=0 loaded=0 pend=0 sched=1 FE1C=06 |
| Cells | A22C/FE04 static | A22C + FE04 still advancing |

**Lane separation (HARD):** `fn_0x80042090` / Pause / sched-never-converts is
Claude's lane. This census documents alarm-context deadness as shared
structure; it does **not** propose a FIX for that function.

**R1483 / R1484:** NULL and REVERTED. Do not retry bell count / budget / band
for the ~109442 ceiling (`docs/digests/R1483-R1484-null-and-the-wedge-moved.md`).

## `on_alarm_ctx` anatomy (source of truth)

File: `source/runtime/runtime.c`  
Function: `on_alarm_ctx` **L12611–L14680** (~2070 lines)

```
L12611  on_alarm_ctx enter
L12616  R1199 interrupted-PC capture          — always (pre-guard)
L12643  frz_watch thread spawn (R890/R825)    — always (pre-guard)
L12669  [halt] FORCED if g_force_halt         — pre-guard, rare
L12684  [wd] + gpu_screen_receipts + [r96cam] — gated g_guest_depth==0 (R969)
L12750  *** R885 alarmguard ***
          if (g_guest_depth > 0) {
            [alarmguard] (cap 6)
            [wedge] R967/R1193/R1195/... (cap 8)
            alarm(2); return;                 — DRAIN NEVER RUNS
          }
L12840  everything else (rescues, cameras, park dump)
L14680  end
```

**Reachability rule used below**

- `reachable-at-depth>0? = NO` — registration only runs after the R885 return,
  or is explicitly depth==0 gated before the return.
- `YES` — also (or only) on a guest MMIO/read hook that runs mid-step.
- `PARTIAL` — thin outside twin exists but alarm-context copy is still the
  primary / richer printer or arm.
- `UNKNOWN` — unclear host; marked with why.

Pass condition for any future port (not this turn): ported tag appears in
`run.log.raw` **while** `[alarmguard]` is deferring.

## R1160 / c345 target shape (do not reinvent)

| Site | Location | What it proves |
|---|---|---|
| R1160 SPU done | `runtime.c` **L9134–L9171** (`[spudone2]`) | On guest read of polled cell `0x8005957C`, complete INLINE (≥66ms busy). No alarm, no guest dispatch. R350-safe. |
| R1160 alias | **L6571** | 32-bit read of flags word runs same inline path. |
| Sibling doors | A22C site ~L6921+ (`[zrfB]` R1280), status `case 0x1F801800` ~L3228+, `cd_read_impl` ~L3182+ | Same idea: serve/heal at the poll the spin actually executes. |

Port recipe: identify the guest cell the arm keys to → put twin on that
cell's read/MMIO hook → keep R885 untouched → one FIX at a time →
DIRECTOR go required before land.

## Measurement rules (locked)

1. Grade **`run.log.raw`**, never truncated `run.log`.
2. In-tree fuse does **not** bound run length — use external `pkill` budget.
3. No rates from short windows.
4. Check counter meaning before reading zero as fault (`drains=0` can be healthy).
5. Verify camera in built binary via source SHA + `strings` for the tag.

## HOLDs (restate)

- No FE1C OR `(6\|\|0)` / `reapply_OR_forbidden=YES`
- No stillness / armstart stacking
- No opcode-0x16
- No fldbatch revive
- No R1477 re-land
- One FIX at a time
- **No R885 widen/bypass/remove**
- **No dual-land** into Claude's `fn_0x80042090` Pause lane
- No bell count/budget/band retries for ~109442 (R1483/R1484 null)
- No behavioural port from this census without DIRECTOR go

---

## Enumeration table

Legend: **C** = camera (print / sample only) · **A** = behavioural arm (mutates drive/RAM) · **I** = infrastructure

| name / tag | C/A | reachable @ depth>0? | migrate-to? | notes |
|---|---|---|---|---|
| R1199 intr PC capture | I | YES (always) | stay | Pre-guard stores only; already spin-safe |
| frz_watch spawn R890/R825 | I | YES (once) | stay | Pre-guard; watcher thread itself is not the rescue tree |
| `[halt]` R320 forced | C | PARTIAL | stay | Pre-guard but only if `g_force_halt`; measured 0 is expected without force |
| `[wd]` R969 | C | **NO** | guest-path twin *if* wall-clock needed mid-spin | Explicitly depth==0 gated (async-signal-safety). Measured 0 under spin is by design |
| `[r96cam]` STUCK (alarm) | C | **NO** (alarm copy) | N/A camera-only stay *or* keep relying on guest twin | Alarm sample is inside depth==0 block. **Guest twin already exists** in `cd_read_impl` (`[r96cam]` FIRE/CLEAR/DRAIN ~L4950/L5100/L5149) — YES at depth>0 via that path |
| `[alarmguard]` R885 | C | **YES** | stay | The deferral receipt itself; do not remove |
| `[wedge]` R967/R1193/R1195/R1197/R1199 | C | **YES** | stay | Bounded mid-spin camera (cap 8); already the depth>0 visibility channel |
| `[schbnd]` R1402 | C | **NO** | stay | Boundary poll-release receipt; only meaningful at depth==0 |
| `[boundaryrel]` R918/R923 | A+C | **NO** | stay | Runs `cd_sched_poll_release()` at clean seam — correctly depth==0 |
| `[park]` R1213 backstop + park dump | A+C | **NO** | stay | `_exit(77)` / latch clear / full park printers all post-guard. Helper `xenolift_park_tick` (~L8963) is a different [park] printer |
| `[bwalk]` R801 boot-file stamp | A | **NO** | drop candidate *or* port only if boot-stall returns | Stamps FE04/FDF8 from FAT; boot-era |
| `[mpad]` R800 idle-menu fallback | A | **NO** | drop candidate unless menu-idle returns | Injects confirm; outside prints exist elsewhere |
| `[boot2b]` R709 | C | **NO** | stay | Epoch heartbeat camera |
| `[cd]` R621/R622/R630–R639… | C/A mix | **NO** | triage per sub-arm | Starvation cameras + mountlatch/exitgate/dragback stamps (R632–R639 etc.) |
| `[trail]` R642 | C | **NO** | guest-path twin (optional) | Measured 0; comment in-tree already notes alarm-driven deferral during spins |
| `[ackcam]` R561 | C | **NO** | stay | Ack-starve heartbeat |
| `[rsdump]` R588 | C | **NO** | stay | Register dump camera |
| `[mountw]` R566 | C | **NO** | stay | Mount watcher |
| `[mtrans]` R648–R671… | A+C | **NO** | stay / drop-candidate audit | Menu→field transition stamps + f15 install; many outside prints — do not conflate with Pause lane |
| `[f14inst]` R584/R605 | C/A | **NO** | stay | File-14 installer observe / re-arm |
| `[f14node]` R599 | C | **NO** | stay | Disarmed observe-only |
| `[deskdial]` R701 | A | **NO** | drop candidate | Sampler dial mutates req cell |
| `[mntacc]` R584 | C | **NO** | stay | Mount acceptance camera |
| `[f14pump]` R559 | A+C | **NO** | port to R1160-shape *if* DIRECTOR go | FE1C/FE08 pump eval + possible serve |
| `[f15pump]` R577/R579/R580 | A+C | **NO** | port to R1160-shape *if* DIRECTOR go | File-15 stream pump |
| `[f15trace]` R579 | C | **NO** | stay | Trace |
| `[f14land]` R560 | C | **NO** | stay | Dest-head camera |
| `[cfgcam]` R1236 | C | **NO** | stay | Config-read posture |
| `[parkclose]` R1186 | A | **NO** | port to guest CD idle hook *if* needed mid-spin | Stale FIFO discard + close stalled read |
| `[c2door]` R1191 | A | **NO** | port to R1160-shape *if* DIRECTOR go | Cell-anchored delivery |
| `[fldfrz]` | C | **NO** | **guest-path twin** (high-value camera) | Measured 0; freeze posture dump — ideal pattern-proof camera port |
| `[xcam]` R1480 | C | **NO** | **guest-path twin** (high-value camera) | Measured 0; last-N DMA/fldsec ring + stall dump. Ring push already exists on delivery path (~L6272); **stall dump** is alarm-only |
| `[dirack]` R525 | A | **NO** | port to guest status/ack hook *if* DIRECTOR go | Doorbell arm (rspop path) |
| `[dirack2]` R526 | A | **NO** | port to guest Pause/GetStat hook *if* go | ReadS-ack doorbell (cmd=09) — **near Claude Pause lane; do not dual-land** |
| `[fld2sig]` (alarm UNCOND + ARM-C) | A+C | **PARTIAL** | guest-path twin already partial (~L25870 fd-tick / variant-B) | Alarm copy dead at depth>0; outside `[fld2sig]` printers + variant-B arm exist on pump/fd-tick path — verify which spin reaches them before new port |
| `[fldbell3]` R544 | A | **NO** | port to R1160-shape *if* go | Answer prime + INT1 |
| `[dirack4]` R532 | A | **NO** | port *if* go | Field-era Setloc-ack doorbell |
| `[fldbell]` R503b | A | **PARTIAL** | prefer existing guest twin | Alarm R503b dead mid-spin. **Guest twin already in `cd_read_impl` ~L4285 (R503)** — reachable at depth>0. Do not invent a third copy without DIRECTOR go |
| `[fe34fix]` R549 | A | **NO** | guest twin exists outside (~L22024+) — audit before port | Batch count FE34 prime |
| `[fldbell4]` R545 | A | **NO** | port *if* go | Posture bell + close stalled read |
| `[schdw]` R1291 | C | **NO** | stay | Clear-site tracer (should live at clear sites; check if already twinned) |
| `[cbheal]` R506 | A | **NO** | port *if* go | Ready-callback re-arm `0x80059F08` |
| `[dirack3]` R527 | A | **NO** | port *if* go | GetStat doorbell |
| `[fldpump]` | C | **NO** | guest-path twin optional | Timeline camera |
| `[devt]` R83 | C | **NO** | stay | Device table dump (park-time) |
| `[cdstate]` | C | **NO** | stay | Drive state dump (park-time) |
| `[hle]` | C | **NO** | stay | HLE counters (park-time) |
| `[xenolift]` park banner | C | **NO** | stay | Park narrative |
| `[fl]` free-list walk | C | **NO** | stay | Park-time heap walk; `_exit`/`exit(0)` ends park |

`#ifdef` arms inside `on_alarm_ctx`: only platform ucontext PC extract (`__APPLE__`/`__arm64__`/`__x86_64__`) and one `__APPLE__` wedge backtrace block — no behavioural `#ifdef` rescues.

### Measured-zero set (explicit)

| tag | alarm reachable @ depth>0? | already has guest twin? |
|---|---|---|
| `[wd]` | NO (depth==0 gate) | NO |
| `[park]` | NO | weak (`park_tick` only) |
| `[halt]` | NO in practice | NO |
| `[fldfrz]` | NO | NO |
| `[fld2sig]` | NO (alarm copy) | PARTIAL (fd-tick ~L25870) |
| `[fldbell]` | NO (alarm copy) | **YES** (`cd_read_impl` R503) |
| `[trail]` | NO | NO |
| `[xcam]` | NO (stall dump) | PARTIAL (ring push on delivery; stall dump alarm-only) |

---

## Migration order recommendation (ONE at a time — not a land)

1. **This turn (R1485):** census only (this doc). No runtime change.
2. **Recommended first (BIMODAL / Task A ELEVATED — docs proposal):**  
   **`[c2door]` R1191 guest-read port** — see
   `docs/proposals/R1487-c2door-guest-read-port.md`. Behavioural arm, dead at
   depth>0, hook = `cd_read_impl` `case 0x1F801800` (~L3228). **No land until
   DIRECTOR explicit GO / greenlight.**
3. **Prior default (camera-only, superseded as first by Task A):**  
   **camera-only `[xcam]` STALL dump twin** (or `[fldfrz]`) on status
   `0x1F801800` and/or A22C `0x8006A22C` — still valid as a later pattern-proof
   camera if DIRECTOR prefers camera-before-behavioural.
4. **Do not** pick `[dirack2]` / Pause-ack doorbells as first port — overlaps
   Claude's Pause / `fn_0x80042AA8` lane.
5. **Do not** pile behavioural doorbells; one FIX at a time after Mac receipts.
6. **Do not** touch R885.
7. Census alone does not authorize a land — R1487 is the named first
   behavioural candidate; DIRECTOR GO required before any runtime change.

## Task B pointer

Optional secondary: `docs/proposals/R1486-first-content-gp0-tripwire.md`
(camera/tripwire stub only — not implemented).

