# R1483 / R1484 null results - and the wedge has MOVED

Both changes are **reverted**. Their value is what they rule out, plus one
genuinely new fact: R1482 did not just raise the ceiling, it **moved the failure
to a different guest function**.

All numbers below are from `run.log.raw`, never `run.log`.

## The three runs, same 1300s budget

| | R1482 (baseline) | R1483 | R1484 |
|---|---|---|---|
| max seek | 109443 | 109442 | 109442 |
| last sector | #872 @ t=493s | #648 @ t=479s | #848 @ t=475s |
| bells rung | 96 (cap) | ~96 | **#256** |
| `[pendclr]` | 32 | 32 | 32 |
| vram_writes | 552960 | 368640 | 368640 |
| dma2_sends | 3 | 2 | 2 |
| nonblank | 0% | 0% | 0% |

**R1483** (one bell per delivered sector, the psx-spx model R411's own comment
states) — null. **R1484** (band widen 109150 → 130000) — null.

R1484 is the more interesting negative. It worked *mechanically*: bells went from
~96 to #256, reaching seek 109239, and `[pendclr]` stayed pinned at 32, so the
widen neither stormed nor triggered the c166 desync the narrow band was protecting
against. It simply didn't move the ceiling.

**Ruled out as the ~109,442 ceiling: the bell count, the bell budget, and the bell
band.** Three separate hypotheses, all eliminated. Anyone tempted to retry a bell
tweak should read this table first.

## The new fact: R1482 moved the wedge

This is the part worth acting on. The guest is no longer stuck where it was.

```
BEFORE R1482                          AFTER R1482
fn 0x8004252C  = CD_flush             fn 0x8004247C  (epilogue of fn_0x80042090)
depth = 2                             depth = 1
cmd  = 06 (ReadN)                     cmd  = 09 (Pause)
FE1C = 00                             FE1C = 06
act=1 loaded=1 pend=1 sched=0         act=0 loaded=0 pend=0 sched=1
A22C static                           A22C ADVANCING (0x16F -> 0x17E)
FE04 static                           FE04 ADVANCING (0x1AA22 -> 0x1AA2C)
```

Different function, different command, different drive posture, and - unlike the
old wedge - **cells are still advancing while it is stuck**. This is a later,
distinct failure that the CD_flush deadlock was previously hiding. `fn_0x80042090`
has no symbol in the DB; it sits in the CD kernel family beside `CD_flush`.

## The structural lesson, now seen twice

The new wedge spins at `g_guest_depth = 1`, so R885's alarmguard defers `on_alarm`
again and the whole alarm-context rescue tree goes dark a second time:

```
[alarmguard] R885 on_alarm deferred - anchor mid-guest-step (depth=1 cur_fn=8004247C)
[wd] 0   [halt] 0   [fldfrz] 0   [xcam] 0
```

(In the R1482 baseline run these had recovered to `[wd]=2`, `[halt]=2`.)

So the alarmguard deadlock is **not a one-off tied to CD_flush**. It is a
recurring structural property: *any* guest spin at depth > 0 disables every
camera, arm, heal and rescue in `on_alarm_ctx`. Each time a spin is fixed, the
next spin re-creates it. Work placed in the alarm handler is only reachable when
the guest is already healthy - which is the opposite of when it is needed.

The durable fix is the R1160 (c345) pattern the tree already established: put
rescues in the guest's own read/write context, at the exact cell being polled,
never in alarm context.

## Where to aim next
At `fn_0x80042090` with `cmd=09` (Pause), `sched=1`, `act=0`, `FE1C=6`: a read is
*scheduled* but never started, while the drive sits idle and the guest spins. That
is a scheduled-read-never-converts shape, and this project has a large family of
arms for exactly that posture - all of which currently live in alarm context and
therefore cannot fire here.
