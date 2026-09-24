# ROOT CAUSE: the plateau is a ~1.00 sector/second throughput bug, not a stall

## Headline
The field-band "plateau" that has blocked every trial is **not a stall and not a
stuck read**. Sector delivery is running at a metronomic **1.00 sectors/second**
because the guest's `LegacyCdDataWait` never receives its "data arrived"
notification and exits via its internal ~1-2s timeout on **every single sector**.

At 1 sector/sec, crossing 108900 -> 120634 (11,734 sectors) takes **~3.3 hours**.
That single number explains every observation this session.

## Measured rate profile (trial 4, 180s budget, R1472-R1475 present)
```
t=2s    126.00 LBA/s   <- healthy initial burst
t=8s      6.17 LBA/s
t=10s     1.00 LBA/s
t=31s     1.18 LBA/s
t=61s     0.97 LBA/s
t=91s     1.00 LBA/s
t=121s    1.00 LBA/s
t=181s    1.00 LBA/s
```
Locked to 1.00/s after the first ~10 seconds. A round, stable 1.00 is a
wall-clock artifact signature, not performance noise.

## Evidence chain
1. `[waitbr] R1306 LegacyCdDataWait RETURN: ret=0 ... A22C=00000000` - the waiter
   returns with the data-arrived flag at ZERO.
2. Log text names the mechanism directly: *"A22C=CD-data-arrived flag,
   LegacyCdDataWait times out on..."*
3. A22C value census across the run: **353 samples read 0**, only ~27 read
   nonzero (values 1..7, the monotonic `+1` from R722D's announce).
4. R1466B fires ~1 per sector (346 fires across 296 sectors) and each fire is at
   a distinct NEW seek - so R1466B's own "new seek fires instantly" fast path IS
   being taken. **The 1s same-LBA backup guard is NOT the throttle** (I initially
   suspected it; the fire/seek correlation ruled it out).
5. Therefore the ~1s per sector is spent inside the guest waiter, waiting out its
   timeout because the announce it needs isn't visible when it checks.

## Why this reframes everything
- Explains why 120s / 180s / 600s / 900s budgets all end in the same narrow band:
  every run gets ~1 sector/sec, so budget differences are marginal against the
  11,734 sectors needed.
- Explains why R1467A / R1472 / R1473 / R1475 never fire: they all wait for
  *stillness*, and nothing is ever still - the drive is metronomically creeping.
- Explains the earlier "pacing vs stall" ambiguity: it is pacing, but pathological
  pacing (~300x slower than a real 2x PS1, which streams ~300 sectors/sec).
- Means the entire "force-start the stuck read" family of rescues is aimed at the
  wrong failure mode. The read is not stuck; it is being notified too late.

## R722D already attempts this fix - and partially works
Inside R1466B's fire body:
```c
xenolift_mem_write32(0x8006A22Cu, xenolift_mem_read32(0x8006A22Cu) + 1u);
/* R722D: ... posting at the heal lets the waiter exit the moment data lands */
```
The occasional nonzero A22C values (1..7) are this working. But A22C reads 0 the
overwhelming majority of the time, so the announce is landing at the wrong moment
relative to when the waiter actually samples it (likely posted before the waiter
begins its wait, then cleared by the game, leaving the wait unannounced).

## Suggested fix direction (not yet landed)
Post the A22C data-arrived announce **at the moment data is staged into the FIFO
while a wait is outstanding**, rather than only at heal time - or re-post it while
a wait is pending and staged data exists. Target: restore the ~126 LBA/s rate
observed in the first seconds, which would cross the 11,734-sector gap in roughly
90 seconds instead of 3.3 hours.

Verification bar for any such fix: the rate profile above should stop reading
1.00/s. That is a direct, unambiguous pass/fail signal - no stillness heuristics
or receipt archaeology required.
