# The earlier failure: TWO distinct stall classes, and a warning against the obvious fix

Hunt for the failure that gates access to R1491's posture (R1491 fired in only
2 of 6 trials; four trials had their last sampled read at t=1-5s). Data: the
R1491 6-trial serialized protocol, `run.log.raw`.

## There are at least TWO early failures, not one

Terminal seek per trial:
```
trial 1  seek=108785   field band    exit 0    (clean main-return, 14962 lines)
trial 2  seek=109164   field band    exit 137  (the escape, 51227 lines)
trial 3  seek=108899   field band    exit 137
trial 4  seek=6        TOC band      exit 137
trial 5  seek=5        TOC band      exit 137
trial 6  seek=0        TOC band      exit 137
```
**Half the trials never leave the TOC band at all.** That is a different failure
from the field-band stall every prior digest has been chasing, and it is equally
common. Trial 1 also exited **status 0** rather than being killed — a third
distinct ending.

Trial 5 terminal posture:
```
seek=5  FE04=00000005  FDF8=00000800  FE1C=00000006  FDFC=00000000
act=1 sched=0 pend=0 arm1=0 cmd=09  A22C=00000000
[waitbr] R1306 LegacyCdDataWait RETURN: ret=0 FDFC=0 FE1C=00000006
```
Here `FDFC` is clean and **`FE1C` is the single failing exit term** — the mirror
image of the R1491 posture, where FE1C was clean and FDFC was stuck. Two stalls,
two different failing terms, same waiter.

## The 4F/5F cell divergence is real and pervasive

`[f5cam]` R764A samples both copies of the state cell:
```
trial   0x8005FE1C (mirror)   0x8004FE1C (what the waiter reads)
1..6    00000000              00000006          all six diverged

965 of 1150 samples across all trials show 4F != 5F   (84%)
```
This is measured directly, not inferred from a missing log line.

## DO NOT port an R1459W-style "clear the stale FE1C" arm here

This is the important negative result. The obvious fix — the tree already has a
family for it (R1452 / R1459W / R1460F, all stranded in `on_alarm_ctx`) — is to
treat the 4F copy as stale and clear it. **The receipts say it is not stale.**

`[chg]` write census, trial 5:
```
0000->0006 @0x800415B4   x32     <-- the GUEST writes FE1C=6 itself
0006->0001 @0x80040FCC   x39
0005->0000 @0x8004196C   x44
0000->0005 @0x80040FB4   x29
```
`FE1C=6` is written by guest code at `fn 0x800415B4`. It is the guest's own state
machine value, not a runtime artifact. And at that moment `FDF8=0x800` is genuinely
owed, so 6 is *consistent* — the read really is outstanding. Clearing it would
lie to the guest about a read that has not completed.

So the 84% divergence is not "the runtime left a stale value"; the two cells are
simply not the same variable, and R1459W's premise ("the f5cam receipts prove the
cell STALE") does not hold at this posture. Anyone porting that family out of
alarm context should skip it for the TOC-band class.

## Two measurement corrections I owe

1. **`[fldsec]` is a SAMPLED camera, not a counter.** Its gate is
   `fldsec_n <= 4 || (fldsec_n % 8) == 0` — the first four, then every eighth. So
   every "sectors consumed" figure I have reported (including in the A/B and
   escape digests) is roughly an **8x undercount**. It is monotonic with real
   consumption, so ordinal comparisons between runs remain valid, but the absolute
   numbers are meaningless and should not be quoted as counts.
2. I briefly concluded "LBA 4 and 5 are loaded and DMA'd but never consumed"
   because no `LBA 4/5 consumed` line exists. That was the print cap, not a bug.
   Their DMA is in fact healthy and sequential (LBA 3->0x1800, 4->0x2000,
   5->0x2800, 6->0x3000, 7->0x3800, each +2048 to a valid low-RAM buffer).

## Where to aim next
The TOC-band class (seek 0-6, FE04 stamped, FDF8=2048 owed, act=1, FE1C=6,
FDFC=0) is as common as the field-band class and is *earlier*, so it gates access
to everything downstream. It needs the owed sector at that LBA to actually
complete and drain FDF8 — not an FE1C clear.
