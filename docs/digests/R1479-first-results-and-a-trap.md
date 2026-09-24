# R1479 [r96cam] first results - and a trap in reading `drains=0`

Trial: merged tree (R1476 fldbatch + R1479 r96cam + R1477 reverted),
`RUN_BUDGET_S=150` with an external 300s killer. Exit 137, max seek **108927**,
`vram_writes=184320` (blank screen, unchanged).

## Tallies
```
r96cam FIRE  = 128     (R96 re-arms INT1)
r96cam CLEAR = 128     (response-consume zeroes 0x800578A6)
r96cam DRAIN =   0     (PIO drain of the CD data FIFO)
r96cam STUCK =   0     (its 30s staged-empty sampler never fired)
fldbatch     =  18     (the parallel R1476 DID fire this run)
```
Every FIRE/CLEAR sample reads `data=0/2060 loaded=1` from seek 108754 to 108874.

## READ THIS BEFORE CONCLUDING ANYTHING FROM `drains=0`

`drains=0` is **expected** and is **not** evidence of a defect. Sector delivery in
this era is by **DMA**, not by the guest PIO-reading `0x1F801802`:
```
[cd-dma] CHCR=11000000 2048/2048 bytes -> 0x800BA1E8 (LBA 108904, fifo 2060/2060, FDF8=2048)
[cd-dma] CHCR=11000000 2048/2048 bytes -> 0x800BA9E8 (LBA 108905, fifo 2060/2060, FDF8=2048)
```
Destinations are sane and advance by exactly 0x800. The FIFO read position stays 0
precisely *because* DMA moved the payload. A camera that counts PIO drains will
read zero in a perfectly healthy DMA stream.

I flagged R96's re-arm as a candidate mechanism in the previous digest and this
camera was built on that flag, so I want to be explicit: **this data does not
support it.** The re-arm is real (128 fires) but nothing here shows it causing
harm, and the one tally that looks alarming is an artifact of the delivery mode.
This is the third measurement trap in this session, after the 180s window and the
truncated log.

## What the run does show
Early streaming is **healthy and fast**: `[fldsec] #176 LBA 108904 consumed @t=2s`
- 176 sectors in the first 2 seconds (~88 sectors/sec), with correct DMA
destinations. The machine is not intrinsically slow.

Then it freezes in the same band, at the same posture as every other run this
session:
```
seek~108910  cmd=06  FE1C=0  FDF8=2048  pend=1  sched=0  act=1
cur_fn=800415B4 (getintr)   r31=80041CA0
```

So the shape is: **a healthy high-rate burst, then a hard stop.** Not a slow
machine. Something transitions the stream out of the working regime at roughly
seek 108905-108910, and that transition - not the steady-state rate - is the thing
to instrument next.

## Note on the parallel R1476 [fldbatch]
It fired 18 times in this run, so its 65536 stuck-confirm is reachable (its own
`R1476_NEXT.md` flagged under-fire as a first-trial risk; that risk did not
materialize). Outcome unchanged: same band, same freeze, blank screen. Its stated
pass/fail bar - "Hiroshi rate profile, still ~1.00 after t=10s = FAIL" - is
**not a valid bar**; see the retraction digest. The valid bar is the `[mscycle]`
gap distribution over a run of 1500s+: a fix works if the >100,000 ms gaps
disappear. Judged on that bar this run is inconclusive, because a 300s run cannot
resolve a >1000s gap.

## Suggested next instrumentation (not landed)
Camera the **transition**, not the steady state: capture full drive + guest
posture on the last N sector deliveries before `[fldsec]` stops advancing, so the
delta between "streaming at 88/s" and "frozen" is visible in one place. Budget the
run at 1500s+ with an external killer, because the in-tree fuse does not bound
run length (receipted: a 150s budget ran 3443s).
