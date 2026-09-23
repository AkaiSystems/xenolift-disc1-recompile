# Digest: R1473 first two trials (post-merge with cd_tick_busy fix)

## Setup
- Tree: origin/xenolift-clean @ 5a73a50 (R1473 + JOSH-DIAG cd_tick_busy fix merged, syntax-clean)
- 2 sequential trials, 120-180s budget, fresh SLUS/captures verified against known-good hashes

## Results
Both trials: **identical outcome.** Max seek = 108907, exit 137 (fuse), `[pausepend] R1473` fires = 0/8 both times.

## Why R1473 didn't fire
R1473 requires `seek`/`FDF8`/`sched` to hold **completely still for 2 continuous
wall-clock seconds** before arming. In both trials, seek kept slowly advancing
(never truly froze at one fixed value) right up to the point the fuse killed the
process - so the specific "genuinely stuck" posture R1473 targets never arose in
either trial. R1473 is not disproven by this; it just wasn't tested by these two
runs.

## What's actually happening at the 108907 ceiling
Not a hard freeze. The log shows real activity right there:
```
[cd] sector LBA 108907 loaded into data FIFO (header 24:14:07 + 2048 bytes)
[zlheal2] R1466B v4 fire 25/2048 @datasync (seek=108907 cmd=06 FDF8 0->2048 FE1C=0)
  - act=1 + staged + pend + INT1 - the never-armed read started
```
An existing rescue (R1466B) is actively firing and servicing this sector. Both
trials landed on the exact same seek value (108907) at the moment of the fuse -
suspicious consistency, consistent with a fixed real-time pace being cut off by
the budget rather than a logical dead-end at that specific LBA.

## Suggested next step
Run one longer-budget trial (600s+) specifically to see whether execution
continues advancing past 108907 given more wall-clock time, vs. this being a
genuine (if slow) recurring stall point independent of budget. Not landing this
myself as a FIX - camera/observation only, per standing instruction.
