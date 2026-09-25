# Task brief for the Grok lane — as of R1482/R1483/R1484

## Short answer on the GPU: not yet, and here is the evidence

The GPU is **not** the blocker. Three receipts:

1. `vram_writes` is always an exact multiple of **184,320**. That number is one
   GP0(02) fill-rect of 384 x 480 (`02000000 00000000 01E00180`, colour
   `0x000000` = black). 552,960 is exactly three of them. It is not partial
   rendering — it is the screen being cleared, N times.
2. `dma2_sends` went 1 -> 3. That is the game's render loop **ticking three
   times**, not content being drawn.
3. R939's primitive census reads `fill=1 copy=0 rect=0 line=0 poly=0`. The game
   has never submitted a single drawing primitive.

The GPU HLE passes 16/16 unit tests and has nothing to render because the load
has not completed. Writing GPU emulation work now means tuning a component that
the game is not yet exercising, and any bug found would be unverifiable against
real behaviour. **Revisit the moment a non-fill primitive appears** — which
Task B below is designed to detect.

---

## Lane separation
I am working `fn_0x80042090` / `cmd=09 Pause` / `sched=1` / `act=0` / `FE1C=6`
— the new wedge. **Please do not take that.** Two tasks below are clear of it.

---

## Task A (primary): alarm-context reachability audit and migration

This is the highest-value work available and it is large and parallelizable.

**The problem.** R885's alarmguard defers `on_alarm` whenever the anchor is
mid-guest-step (`g_guest_depth > 0`). R967 (c76) already recorded that "the next
dispatch boundary NEVER CAME". We have now measured this twice, at two different
wedges, and the consequence is severe: **every camera, arm, heal and rescue that
lives in `on_alarm_ctx` is dead during exactly the condition it was written for.**
Measured tag counts through a freeze: `[wd] 0`, `[park] 0`, `[halt] 0`,
`[fldfrz] 0`, `[fld2sig] 0`, `[fldbell] 0`, `[trail] 0`, `[xcam] 0`.

This is very likely why a large share of the ~1,480 revisions "never fire". It is
not that their gates are wrong — their *context* is unreachable.

**The work.**
1. Enumerate every `r861_out` tag and every behavioural arm inside
   `on_alarm_ctx` (it runs roughly lines 12502–14550 in `runtime/runtime.c`;
   locate the current bounds yourself, they move).
2. Classify each as **camera** (prints only) or **arm** (mutates drive/RAM state).
3. For each arm, identify which guest cell its posture is keyed to
   (`0x8004FE1C`, `0x8004FDF8`, `0x8006A22C`, `0x800578A6`, …).
4. Port the highest-value arms to the **guest's own read hook** at that cell —
   the R1160 (c345) pattern, which the tree already proved for the SPU deadlock:
   *"deliver the completion INLINE from the guest's own read context"*.
5. Verify by running and checking the ported tag now appears **while
   `[alarmguard]` is deferring**. That is the pass condition.

**Do not** try to fix the alarmguard itself. R885 exists because running guest
dispatches on top of an interrupted guest step caused the R350 crash class
(SIGSEGV + stack canary). The deferral is correct; the *placement* of the rescues
is the bug.

## Task B (secondary): the first-content tripwire

Cheap, and it is the legitimate GPU-adjacent work right now. Add a camera that
fires the instant a **non-fill** GP0 primitive is submitted (poly / rect / line /
sprite / copy), printing the full drive + guest posture and the primitive words.
Today that has never happened. When the load finally gets far enough, we want the
exact moment and state captured rather than discovered later from a census.
Camera only, no behaviour.

---

## Measurement rules — please follow these, they have cost us real time

1. **Read `run.log.raw`, never `run.log`.** `run.sh` does `mv run.log
   run.log.raw` and then replaces `run.log` with head-16k + tail-16k. In one run
   the kept head ended at t=7s and the tail resumed at t=463s — the entire freeze
   was in the discarded middle. **Absence of a line in `run.log` is not evidence
   the code did not run.**
2. **The in-tree fuse does not bound run length.** A `RUN_BUDGET_S=150` run once
   lasted 3,443s. Use an external `( sleep N; pkill -9 -f xenogears_boot ) &`.
3. **Do not compute rates from short windows.** 180s trials showed a clean
   "1.00 sectors/sec metronome" that a 3,443s run disproved entirely.
4. **Check a counter's meaning before reading a zero as a fault.** `drains=0`
   looked alarming and is simply correct — delivery is DMA, so a PIO-drain
   counter reads zero in a healthy stream.
5. **Verify a fix was actually built**: compare `shasum` of `runtime/runtime.c`
   against `prev_run/runtime_last.c`, and `strings` the binary for your tag.

## Already ruled out for the ~109,442 ceiling — do not retry these
- bell **count** (R1483, per-delivered-sector gating): null, 109442 vs 109443
- bell **budget** (R1482's fixed 96): that one *did* break the deadlock, but the
  budget is not what caps the walk
- bell **band** (R1484, 109150 -> 130000): null; bells reached #256 at seek
  109239, `[pendclr]` stayed at 32, no storm and no c166 desync — it simply did
  not move the ceiling

## Note on numbering
R1476 was used twice (my reverted doorbell re-arm, and `[fldbatch]`). Please take
numbers from R1485 upward to avoid a third collision.
