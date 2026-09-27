# Mode-6 mount fault: a field-era CD heal copied boot TOC sectors across the heap

After R1517, every run reached MainLoop, but 5 of 6 then faulted at t≈3s when mode 6
mounted. Each fault triggered R777 halt → R772 restore → R765 restart. R1519 removes the
fault. With it gone, the game's own dispatcher goes **movie (state 6) → menu (state 0) →
field (state 1)** in 4 of 6 runs.

| 6 × 150s, serialized | cdtrace | R1517 | **R1519** |
|---|---|---|---|
| Reaches MainLoop | 3/6 | 6/6 | 6/6 |
| Fault restart at the t≈3s mode-6 mount | n/a | 5/6 | **0/6** |
| Reaches **field state 1** | 0/6 | 1/6 | **4/6** (at 4s, 30s, 30s, 32s) |
| R511/R515 fires | n/a | 117 | 4 |

One-sided Fisher exact tests:

| Comparison | p |
|---|---|
| No mount fault, R1519 6/6 vs R1517 1/6 | 0.0076 |
| Field reach vs all 18 prior trials (1/18: cdtrace, jtfix, R1517) | 0.0065 |
| Field reach vs R1517 alone (1/6) | 0.12, not significant at n=6 |

Dispatcher sequences (R670 entries):
- R1519: `30s:st6 32s:st0 32s:st1`, `4s:st6 30s:st0 30s:st1`, `3s:st6 4s:st0 4s:st1`, `26s:st6 30s:st0 30s:st1`, and two runs with `4s:st6` only.
- R1517: five runs show state 6 only; one reaches state 1.

## The chain

1. **The fault.**
   - `HeapRelocate` (0x80031B10), called by the dispatcher as it mounts mode 6, starts with `HeapFreeAllBlocks`.
   - That walk reaches block #8 (file #7's LZSS output, data 0x800B3CD4). Its header at **0x800B3CCC** holds `next = 0x00FB00FC`.
   - `HeapFree` faults on 0x00FB00F8.
   - This is the same in 4 of 4 R1517 fault runs.
2. **The writer (R1518).**
   - The write hooks never saw the value, so it was a raw copy.
   - The per-trace poll caught `801FBFF8 -> 00FB00FC` inside the CD interrupt chain (getintr case → archive file callback `8002B084`), with the CD destination FE08 = 0x800B3C98 and the drive at LBA 8/9.
   - `0x00FB00FC` is at **LBA 8, user offset 52**. So the LBA-8 sector landed at 0x800B3C98, and its bytes 52–55 overwrote the header.
3. **Why LBA 8 was copied into the heap.**
   - `GameBootstrap` makes zero-length requests in the TOC band (Setloc 00:02:00, FDF8 = 0), and the drive streams LBA 5, 6, 7, 8.
   - `[zrf0] R511/R515` fire on `seek < 150 && FDF8 == 0 && sector in FIFO`: R515 sets FDF8 to 2048 and force-delivers INT1.
   - The game's callback then copies each sector to FE08 and advances it. FE08 is stale: it still holds 0x800B2498, left by the previous file read.
   - LBA 5 → 0x800B2498, 6 → 0x800B2C98, 7 → 0x800B3498, 8 → 0x800B3C98, all across the live heap.
   - The R515 comment says it was designed for the **field** era ("the field batch COMPLETED … flipped to the directory/system sector"). Every fire in the R1517 runs before the first MainLoop was in boot, for example 16 of 16 in trial 3.

## Fix: R1519

The zrf0 block (R511 + R515) now requires the R1517 main-loop latch, which is its designed era. It can no longer turn boot's zero-length TOC-band requests into copies to a stale destination.

## What this is not

- **The escape metric no longer applies.** `score.py` escape ("a movie-band read after the last field-band read") gives R1519 0/6. That metric was written for the old trajectory: a stall in the field band, then a movie read. The natural order is now movie → field, so it scores 0 while progress is up.
- **Faults still happen late.** R1519 still has faults at t≈150–152s, at the end of the run, in trials 2, 4 and 5:
  - trial 5: a later `HeapRelocate` walk under `KernelMenuMain`;
  - trials 2 and 4: in the libcd poll `8004B55C/8004B694`.
  These are separate and not yet investigated.
- **Field state stalls.** After field state 1, reads stop at about 39s and nothing more is consumed through 150s. That is the next blocker.
- **Another heal overshoots.** `[zlheal2] R1466B` also re-arms FDF8 0→2048 during boot file reads. It copied LBA 108891 to 0x800B36B0, past file 6's buffer, and wrote `0F010C3C` onto the same header. In these runs that write is harmless, because `HeapAlloc` rewrites the header afterwards, but it belongs to the same class and should be scoped the same way.

## Camera: R1518

`[hdrtrip]` hooks writes to 0x800B3CCC; `[hdrwatch]` polls it every trace to catch raw copies. Both are receipt-only and capped.
