# RETRACTION + new evidence: the "1.00 sector/sec metronome" was a short-window artifact

**Status: two of my own prior conclusions are WRONG and are retracted here.**
No fix is claimed in this document. One fix (R1477) was landed, tested, and
fired zero times; it is reported below as a negative result.

---

## Retraction 1 — the rate profile in `ROOT-CAUSE-1-sector-per-second.md`

That digest concluded the field-band plateau is a **metronomic 1.00 sectors/second**
throughput bug, and computed from it that 108900 -> 120634 would take ~3.3 hours.
Every measurement behind it came from **180-second** trials.

A run that lasted **3443 seconds** (the in-tree fuse did not fire; see "Fuse" below)
shows that figure is an artifact of where the short window happened to land.

Measured over the long run, from the ms-resolution `[mscycle]` camera
(gap = time between consecutive changes of A22C / FDF8 / seek):

```
gap value   count     what it is
---------   -----     ----------
0-2 ms       174      intra-event bursts
18-22 ms      15      ~one 60Hz frame - healthy frame-paced delivery
996-1002ms    38      the "metronome" the 180s trials saw
4000 ms        1
967,317 ms     1      <-- 16.1 minute hard stop
1,184,579 ms   1      <-- 19.7 minute hard stop
```

The two long stops total **2,151,896 ms of a 2,211,998 ms run = 97.3% of the
entire observation**. Net progress across the whole run: seek **108861 -> 108964**,
i.e. **103 sectors in 2212 seconds = 0.047 sectors/second** - roughly **20x worse**
than the 1.00/s I reported, and a different failure mode entirely.

So the honest description is not "a slow metronome." It is: **short bursts of
near-frame-rate delivery, separated by multi-minute hard stops.** The 1.00/s
figure was real but local; generalizing it to the whole run was my error, and the
3.3-hour projection built on it is void.

### What actually ends a stop
Not the guest. The in-tree rescue does. At the end of the 19.7-minute stop:
```
[defib-decline] R1283: file-band FDF8 frozen 1184s (fdf8=2048 seek=108911) ...
[defib6] R473 stalled-load COMPLETED: 1 sectors stuffed into ring, FDF8=0, seek=108912 (fire #1)
```
The tree's own camera names the freeze duration (1184s) and the tree's own
defibrillator force-completes exactly one sector. Then the cycle repeats. The
"progress" being measured across these runs is substantially rescue-driven, not
guest-driven.

---

## Retraction 2 — "A22C is write-only / the guest does not poll it"

In reverting R1476 I wrote that A22C "is effectively a WRITE-ONLY COUNTER that the
runtime increments and the guest does not consume," and that this "invalidates the
premise behind ~9 existing runtime announce sites." **That broad claim is wrong.**

R1197's origin counter, which counts reads of 0x8006A22C by origin and was built
specifically so telemetry could not be mistaken for guest behavior, receipts:
```
[pollkick] R1196 kick #27000 serviced at A22C poll cur_fn=80041B24
  (r32 hits=270086220 wrap-aware | ORIGIN guest=2569842 host=0 | OUTCOME blocked=841842 svc-ent=27000 svc-ret=27000)
```
**guest=2,569,842** reads, host=0. The guest polls A22C millions of times.

What survives from the R1476 result is only the narrow, mechanical fact: R1476's
gate required `A22C == 0`, A22C increments monotonically and nothing in the tree
writes it back to zero, so that gate is never true and the fix could not fire.
That is a statement about R1476's gate, not about whether the guest reads the cell.
The ~9 existing announce sites are NOT invalidated. I retract that.

R1476 remains reverted (wrapped in `#if 0`, tree compiles clean, 0 errors).

---

## Negative result: R1477 (landed, built, zero fires)

`xenolift_vblank_heartbeat()` contains R448's frame-clock acceleration:
```c
if (cd_read_active && fe20 == 3u && fdf8 > 100000u)
    vb_thresh = 64u;          /* else 3000 polls per heartbeat round */
```
Log census of the field era: `FE20=3` holds (176 samples), `act=1` holds, and
**FDF8 only ever holds 0 or 2048** - because the runtime's own healers
(R1466B/R722D) stage one sector at a time. So `fdf8 > 100000` is the single
failing term and R448 has been dead code through the whole field era.

R1477 widened the gate to also accept the staged-single-sector form
(`0 < FDF8 <= 2048`, field band 100000..299999, same era terms, same proven
`vb_thresh = 64`).

**Result: zero fires.** Verified it was actually built - the `fldaccel` string is
present in the executed binary and the source sha256 matches the sha the build
archived to `prev_run/runtime_last.c`. The rate was unchanged.

So either the heartbeat is not on this era's rail at all, or another gate term
declines. Per the project's own REVERT rule the fix produced no consumption; it is
left in place only because an R1478 decline camera (the R1432B technique) now
prints every gate term live plus two call counters, to name the failing term
instead of guessing. If R1477 still fires zero with the camera data in hand it
should be removed.

---

## New evidence gathered during the long run (camera-only, no claims attached)

1. **The guest is not frozen during the multi-minute stops - it is hot-spinning.**
   `r32 hits` climbs 9,008,470 (kick #1) -> 604,607,318 (kick #71000). Over half a
   billion guest reads. Whatever the stop is, it is not the process being starved.

2. **The CD IRQ status register reads INT1 (data ready) persistently.**
   `[dev] read 0x1F801803 = 0x00000001` sampled 50 times, `n` running
   50,000 -> 13,050,000. The emitted waiter `fn_800415B4_getintr` reads
   `1F801803 & 7`, returns early if zero, else drains up to 8 response bytes.
   It is being told "data ready" continuously.

3. **The data FIFO is staged but never drained by the guest.** Freeze-dossier
   receipts: `act=1 loaded=1 pos=0/2060 sched=0 pend=1 cmd=06 FE1C=00`.
   2060 bytes staged, read position 0. The guest takes the interrupt and does not
   take the data.

4. **FE1C == 0 throughout the field crawl.** Every `[mscycle]` line in both the
   180s and the 3443s runs reads `FE1C=0`. The waiter's historically-failing exit
   term is already satisfied here, so this era is NOT the FE1C class that
   R1452/R1459W/R1460F and siblings were built for.

5. **The next sector is staged in the same millisecond the previous is consumed.**
   `#270 t=111995ms FDF8 2048->0 seek ->108990` / `#271 t=111995ms FDF8 0->2048`.
   The guest is never data-starved at any point.

6. **Candidate mechanism, NOT yet tested: R96 re-arms INT1 on every full response
   drain.** In the `0x1F801801` read path, once `cd_resp_pos == cd_resp_n`:
   ```c
   if ((cd_last_cmd == 0x06u || cd_last_cmd == 0x09u) && cd_read_active) {
       cd_pending = 1;
       r861_out("[cd] data-ready INT1 armed (ReadN INT3 consumed)\n");
       g_cd_irq_force = 1;
   }
   ```
   The log shows `[cd] response consumed` and `[cd] data-ready INT1 armed`
   alternating continuously through the freeze. The same path also writes
   `0x800578A6 = 0`, which is the exact cell the R722D/R1296B announce composite
   sets to 1 - so a response drain clears the announce flag those sites just set.
   Both observations are consistent with an INT1 re-arm loop, but neither is proof;
   this needs a fire/consume-correlated camera before anyone writes a fix for it.

7. **Still zero player-visible progress.** Same as every prior run:
   `vram_writes=184320`, `nonblank=0%`, `dma2_sends=1 (0 dma2 = the game never
   sent a drawing list)`, blank ASCII screen dump.

---

## Fuse note (affects every measurement in this project)

The run was launched with `RUN_BUDGET_S=150`/`180`. The in-tree fuse reports
`[fuse] run fuse cleared (R356: 210s hard kill - digest always generates)`, yet
the run lasted **3443 seconds** and exited 137. The 210s hard kill did not bound
it. Until that is understood, **run durations in this project cannot be assumed
from the budget variable**, and any rate computed from an assumed duration is
suspect - which is precisely how Retraction 1 happened. Long runs are now launched
with an external `sleep N; pkill -9` killer.

---

## What this changes for anyone working the field band

- Stop tuning stillness-gated armstarts against a "1 sector/sec creep." The thing
  to explain is a **multi-minute hard stop with data staged, INT1 asserted,
  FE1C=0, and the guest spinning hundreds of millions of reads**.
- The pass/fail bar from the prior digest ("does the rate still read 1.00/s")
  is **not a valid bar** - it only samples a burst window. The valid bar is the
  **[mscycle] gap distribution over a run of 1500s or more**: a fix works if the
  >100,000 ms gaps disappear.
