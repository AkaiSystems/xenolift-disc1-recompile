# R1491: the guest-read migration is PROVEN to work. Escape effect is NOT.

Two separate claims, graded separately. One passes decisively, one does not.

Build: R1482 + r96gate + R1486 + R1487 + R1491. 6 serialized trials, 300s,
nothing else on the machine, scored after all runs exited, from `run.log.raw`.

## What R1491 is
The reproducible stall (identical in two prior trials) is
`fn 0x800286CC` (PollArchiveTransfer) with:
```
FE1C=00  FDF8=00000000  FE04=00000000  FDFC=00000001
act=1 loaded=1 sched=0 pend=0 cmd=02
```
The R1306 waiter exits on `ret==0 + FDFC==0 + FE1C==0`. Two of three already
hold; nothing is owed and nothing is stamped; **`FDFC` is the single failing exit
term** and the drive is idle so nothing will ever clear it.

**The address is the finding.** The wedge camera's FDFC is `0x8004FDFC` (checked
against its argument list), and R1195 wedgespin receipts show the guest polling
`0x8004FDFC` 63 times inside the wedge window. The tree has **five** clears of
`0x8005FDFC` but only **three** of `0x8004FDFC`, and two of those three sit in
`on_alarm_ctx` (L13432, L14902) — dead at depth>0. Both cells are real (42 refs
vs 17), so this is not a typo: the existing clears simply do not cover the cell
this waiter polls.

R1491 hooks the guest's own read of that cell, gates on the completed-idle
posture with a 131072-poll fence (R1451's receipted confirm, the same fence
R1487 used), budget 8, and all gate reads are raw `memcpy` per the R1197 rule.

## CLAIM 1 — the migration works. PASS, decisively.

Trial 2, `run.log.raw` line order:
```
26868  [fdfcclr] R1491 fire 1/8 ... 0x8004FDFC 1->0 at seek=108884 act=1 loaded=1
34153  [fdfcclr] fire 2/8
36638  [fdfcclr] fire 3/8
39271  [fdfcclr] fire 4/8
42907  [alarmguard] R885 on_alarm deferred - depth=1 cur_fn=80041BA8
42925  [fdfcclr] fire 5/8          <-- fires BETWEEN deferrals
43650  [alarmguard] R885 on_alarm deferred - depth=2 cur_fn=8002A694
45072  [fdfcclr] fire 6/8
49010  [fdfcclr] fire 7/8
49054  [fdfcclr] fire 8/8
50293  [alarmguard] ... depth=1 cur_fn=8004B55C
```
Alarm-context liveness in that same trial:
```
[wd]=0   [halt]=0   [fldfrz]=0   [xcam]=0   [park]=0
```
**A behavioural arm mutated guest state, repeatedly, during depth>0 spins, while
every single alarm-context arm was blacked out.** That is the R1160/c345 pattern
working, demonstrated rather than argued. R1487 could not show this because its
gate never opened (both its twin AND its alarm copy fired zero times).

Task A's method is therefore validated. The remaining alarm-context arms are
worth porting on this evidence.

## CLAIM 2 — does it improve escape? NOT ESTABLISHED.

```
trial   [fdfcclr]   escape                  lastField(t)
1       0           no                      2s
2       8           ESCAPE (106s, 239322)   105s
3       1           no                      13s
4       0           no                      2s
5       0           no                      1s
6       0           no                      2s

ESCAPE RATE: 1 / 6      (baseline without R1491: 0 / 6)
```
The only escaping trial is the one where R1491 spent its full budget, and the
one partial-fire trial (3) got the third-longest run. Suggestive.

**But 1/6 against a historical base rate of 1/12 is not a result.** n=6 with one
event cannot distinguish these. I am explicitly NOT claiming R1491 improves
escape. It needs many more trials, and the fires being concentrated in 1 of 6
trials means the arm itself only becomes reachable rarely.

## Honest caveat on the arm's reach
R1491 fired in only 2 of 6 trials. Most runs stall before the posture it targets
is reached (last field read at t=1-2s in four trials). So this arm fixes a stall
that most runs never get to — there is an earlier failure gating access to it.
Finding that earlier failure is likely worth more than tuning this one.
