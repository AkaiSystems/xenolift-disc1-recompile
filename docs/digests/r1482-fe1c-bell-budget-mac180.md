# Digest: R1482 FE1C bell budget — deadlock broken (Mac 180s grade)

**Tip:** `988285fd0608b7d09e2331e777f4987bbb318022` (`988285f`)  
**runtime.c SHA-256:** `20f9339daa33c7b3dfcf031185448636b4e9e648ee392d9f096735f21b22b80a` — **PASS**  
**Parent:** `87ee454` (R1481 [r96gate] — superseded as the storm culprit)  
**Source of meters:** DIRECTOR Mac 180s `run.log.raw` (treat as measured; do not invent further)  
**Live FIX:** R1482 @ `988285f` supersedes awaiting-Mac on R1481 alone.  
**reapply_OR_forbidden:** YES  
**Baseline awareness:** pin behavioral awareness of `bcbfce8` / R1480 era; grade `run.log.raw` only.

---

## Causal correction (FE1C-read re-arm vs R96)

**Wrong first blame:** R96 (response-FIFO drain → unconditional INT1 re-arm).  
R96 print volume (~840) and armline stamp **5091 = 6 clears** cannot explain ~1.03e9 acknowledgements implied by the `[pendclr]` free-cap.

**Proven culprit (R1481 armline stamps, then R1482 land):**  
R411/R412/R415 FE1C-read INT1 re-arm at **armline ≈ 7357**.

- Gate: FE1C poll while `cd_pending==0` (exactly post-ack), mid-read FDF8, seek band `108900 ≤ seek < 109150`.
- R415 comment intended `r411_n` to bound the **number of bells** (24→96: “file 1 + file 2 end to end”).
- Bug: `if (r411_n++ < 96u)` wrapped **only** the `r861_out` receipt. The arm (`cd_pending=1` + `g_cd_irq_force=1`) sat **outside** and fired on **every** matching FE1C read.
- R1481 stamps: armline=7357 ≈ **1767/1799** clears (~98%); R96 armline=5091 = **6**.

**Why everything deadlocked:** guest `fn_0x8004252C` = `CD_flush` exits only when `1F801803&7==0`. Unbounded FE1C re-arm re-asserted INT1 as fast as ack cleared it. Spin at `g_guest_depth=2` → R885 alarmguard defers `on_alarm` forever (R967/c76: “next dispatch boundary NEVER CAME”). Alarm-context cameras/rescues (`[wd]` `[park]` `[halt]` `[fldfrz]` `[fld2sig]` `[fldbell]` `[trail]` `[xcam]`) read **ZERO** through the freeze — why R1480 produced nothing.

See also: `docs/digests/ROOT-CAUSE-cdflush-alarmguard-deadlock.md` (storm shape correct; **site** corrected from R96 → FE1C R411).

---

## What R1481 proved vs what it did not

| R1481 delivered | R1481 did **not** |
|-----------------|-------------------|
| Exhaustive `__LINE__` stamps on arm sites + `[pendclr]` armline print | Name the storm as R96 (that was a digest error) |
| One Mac run: armline=7357 dominates (~98%) | Solve the storm by gating R96 alone |
| Method: stamp → measure → fix the stamped site | Authorize stacking FE1C OR / stillness / next speculative arms |

R1482 **reverts** the R1481 `[r96gate]` behavioral gate at R96 (restores prior R96 arm) and applies the **correct** site fix: budget gates the FE1C bell. Stamp infrastructure remains useful.

---

## What R1482 changed (behavioral — already landed)

At the R411 FE1C mid-read re-arm (~L7357):

```c
static int r411_n;
if (r411_n++ < 96) {
    cd_pending = 1, g_pend_line = __LINE__;
    g_cd_irq_force = 1;
    r861_out("[fld-rearm] ... bell %d/96\n", ...);
} /* R1482: close the budgeted bell */
```

First 96 bells byte-identical to pre-fix; unbounded tail removed. Author’s stated R415 intent, nothing more.

---

## Measured before → after (Mac 180s, DIRECTOR meters)

| Meter | Before (storm era) | After R1482 @ 988285f |
|-------|--------------------|------------------------|
| `[pendclr]` prints | 1799 (~1.03e9 clears under free-cap) | **32** (free-cap only → counter never hit 65,536; **&lt;6.6e4** clears) |
| armline=7357 | 1767 | **0** |
| max seek | 108907 | **109200** (past old session ceiling) |
| `[fldsec]` | ~176 | **#824**, LBA **109191** @ ~194s |
| vram_writes | 184320 (frozen) | **552960** |
| dma2_sends | 1 | **3** (drawing lists moving) |
| bell budget | unbounded | **96/96**; stream **kept advancing** after |

### REVERT bar that did **not** trip

Stated REVERT: *“stream stops advancing after 96 bells.”*  
**Did not trip** — sectors continued to LBA 109191 after 96/96.

### Pass bars R1482 hit (its own contract)

- `[pendclr]` collapses by orders of magnitude — **PASS**
- armline=7357 stops dominating — **PASS**
- Stream continues past budget exhaustion — **PASS** (REVERT absent)

---

## Non-claims (locked)

- **nonblank still 0%** — no visible frame. Deadlock broken / render path **moving** — **not** rendering.
- **CD / field door unmet** — still short of seek **~120634**. Do **not** claim PASS on door.
- New tip ~**109200** is **not** yet a named next flipped term; 180s is too short to decide the next FIX.
- R411 band itself is `seek ∈ [108900, 109150)` — tip **109200** is already **past** that assisted band; do not casually widen the band without a long-run name for the stop.

---

## HOLDs (unchanged)

- no FE1C OR `(6\|\|0)`
- no stillness / armstart stacking
- no opcode-0x16
- no fldbatch revive
- no R1477 re-land
- **one FIX at a time**
- `reapply_OR_forbidden=YES`

---

## Ranked remaining gap to door (~120634)

Gap ≈ **120634 − 109200 ≈ 11.4k sectors**. Ranked diagnosis from code + digests + 180s meters:

1. **Ack-storm / CD_flush deadlock is broken** — meters collapse; post-96 stream and dma2/vram motion prove the tree is no longer wedged in `8004252C` ack thrash.
2. **New plateau tip ~109200 is unexplained at 180s** — sits just past R411 band upper `<109150`; could be band exit + slow native path, a new stall, or continued crawl invisible in a short window.
3. **Alarm-context cameras are unblocked in principle** — `[xcam]` / `[wd]` / friends can finally observe the post-storm regime; they could not during the freeze. Naming the next flipped term needs their receipts on a long run, not another speculative FE1C/stillness tweak.

---

## Mac next preference

**HOLD behavioral FIX.** Prefer **≥1500s** external-killer Mac grade on tip `988285f` before proposing the next land.

Grade `run.log.raw` only. Paste-ready steps: `docs/digests/R1482_NEXT.md`.

If the long run shows a hard plateau with a **named** flipped term (act/pend/cmd/FE1C/fn/madr/FDF8), then — and only then — propose **one** camera-only or one behavioral FIX that does not touch HOLDs. Until then: **HOLD**, not speculative FE1C band widen / stillness / OR.

---

## Nasir ONE next step for DIRECTOR

**HOLD** — need ≥1500s Mac grade on `988285f` before next FIX.

| Pass (long Mac, grade raw) | Revert / stop |
|----------------------------|---------------|
| Stream continues meaningfully past ~109200 toward door band, **or** a hard stop is named by live camera receipts (`[xcam]` / `[fldsec]` last-N / posture) with a single flipped term | Do **not** land a new behavioral FIX from 180s alone; do **not** widen FE1C band / OR / stillness without a named term |

**Door PASS still unmet** at seek 120634 + field continue. Nonblank 0% unchanged.
