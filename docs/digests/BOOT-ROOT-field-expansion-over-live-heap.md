# Boot root cause: a runtime heal expands the field module over the live boot heap

The boot reboot loop was not in the game and not in the emitter. It came from our own
runtime. A field-era heal fired about 1 second into `GameBootstrap` and LZSS-expanded
260 KB of field code over the game's live heap. Everything after that was fallout.
R1517 blocks that heal until the game reaches its main loop.

| 6 × 150s, serialized | cdtrace (baseline) | jtfix (R1511) | **R1517** |
|---|---|---|---|
| Runs reaching MainLoop | 3/6 (at ~100s) | 2/6 | **6/6** (4 of them at t=4s) |
| Boot INGS read completes (`[cdtrace] END`) | 2/6 | 0/6 | **6/6** |
| R807 unresolved-jump reboots | 27 | 22 | **1** |
| Heap head broken (= 4) at the file-6 alloc | 16 of 33 boots | 16 of 27 | **0 of 11** |
| Boot entries (`[heapinit]`) | 40 | 41 | **14** |
| Full-handoff stamps / R1005 expansions | 28 / 16 | 25 / 16 | **0 / 0** |

One-sided Fisher exact tests against the pooled baselines (n=12):

| Metric | R1517 | Baseline | p |
|---|---|---|---|
| INGS read completes | 6/6 | 2/12 | 0.0015 |
| Trials with no R807 | 5/6 | 0/12 | 0.0007 |
| Reaches MainLoop | 6/6 | 5/12 | 0.025 |
| Heap healthy (per boot) | 11/11 | 28/60 | 6.6e-4 |

## The chain (each link has a receipt)

1. **R812/R814 full-handoff stamp fires inside GameBootstrap.**
   - It was designed for the *parked main-loop* era: kernel dispatcher idx=0/cur=0, "boot 3+".
   - Its posture check reads `0x8005FAEC`, `0x800592C0` and `0x80018088`. All three are 0 before the main loop exists, and `0x800592C0` is also the sign-extension wrong cell (the real one is `0x800692C0`).
   - So it fires at t≈1s during the boot file loads, whenever `mv_n % 524288 == 0`.
   - Receipt: `[statestamp] R814 FULL HANDOFF STAMPED #1`, then `[fldx] R790 expansion sequence entered (via full-handoff-stamp)` at t=1s. All 14 expansions in the diagnostic runs were via this route.
2. **The R1005 RETARGET arm expands file #14 into 0x8006FAF0.**
   - It is called from `xenolift_field_expand_all` and LZSS-expands 260,862 bytes to 0x8006FAF0.
   - During boot that address is the **live game heap**: `InitializeGameHeap(0x8006FAF0, 0x801FC000)`, with the head node, the sound bank in block #1, and file #3 in block #2.
   - R1516 put a physical-address write tripwire at write8/16/32 entry. All 10 value-4 writes to the heap head in 3 runs are `sw_active=0` (a runtime writer). They carry the host stack `xenolift_lzss_hle ← xenolift_field_expand_all ← xenolift_trace`.
3. **The heap is dead.**
   - `HeapAlloc` returns 1 for the file-7 buffer, and `LZSSHeapDecompress` is entered with `src=1`.
   - The runtime's LZSS heals (`[unpack-fix]`, `[reloc-fix]`) pass the value along.
4. **The game's own relocator rewrites low RAM.**
   - `SystemInitializeData(1)` → `ResolveArchiveEntryPointers(1)` (`0x8003342C`: `count=*a0; a0[1..count] += a0`) reads count 0x7178.
   - It then adds 1 to the unaligned u32 at 5, 9, 13, … up to 0x1C5E5. In little-endian that is **+0x100 on every aligned word from 0x80000005 to 0x8001C5E4**, which includes every rodata jump table.
   - R1513 diffed live RAM against the R722 boot image: one contiguous 50,656-byte run from 0x80010004 to 0x8001C5E3. The getintr table `8004196C 80041920 80041820 800419F0 80041A74` became `80041A6C 80041A20 80041920 80041AF0 80041B74`.
   - R1514 caught the rewrite at the return from 0x8003342C, with v1=0x0001C5E5.
5. **The shifted switch targets reboot the game.**
   - `getintr` (`lw v0, 0x80018E9C+i*4; jr v0`) and `fn_8002A694` (tables at 0x800188F4 and 0x8001892C) jump to mid-block PCs such as 80041A6C, 8002A994, 8002ABF0 and 8002AA9C. R1512 showed `v0 == target` in 14 of 14 receipts.
   - Those PCs have no dispatch case, so R807 reboots, and the pristine restore puts the tables back for the next lap. R1514 watched the flip happen on every boot.

The altered block occurs nowhere on the disc; the original getintr table is at sector 108624, inside `SLUS_006.64`. That is what ruled out a disc load and pointed to an in-process writer.

## Fix: R1517

- A per-boot latch `g_r1517_inloop` is set when `RunResidentGameLoop` (0x80019ACC) is entered and cleared on every boot entry (`start` 0x80019524, `GameBootstrap` 0x80019578).
- The R812 stamp and `xenolift_field_expand_all` (all three routes into it) require the latch.
- The heals keep the era they were designed for, inside the main loop. They can no longer fire inside GameBootstrap.
- The stamp never fired at all in the R1517 runs, so its in-loop behaviour is untested here.

## Retracted

- **R1511 is reverted.** Its premise, "0x80041A6C is a jump-table case the emitter never made dispatchable", was wrong. The target word does not exist in the EXE; the table in RAM was corrupted. R1511 made one symptom continue and changed nothing else: MainLoop reach went from 3/6 to 2/6.
- The same applies to the plan to "make jump-table targets dispatch entries in the emitter". Nothing is missing. The tables were right until our runtime rewrote them.

## Cameras shipped (receipt-only, capped)

| Camera | What it records |
|---|---|
| R1510 `[cdtrace]` | CD state, per change, during the boot INGS read |
| R1512 `[jtwho]` | Host stack plus guest registers at any main-EXE target missing from dispatch |
| R1513 `[jtdiff]` | Live 0x80010000–0x8001FFFF against the boot image at that moment (dumps to `/tmp/jtwatch/`) |
| R1514 `[jtwatch]` | Polls two rodata words each trace; on change, reports the last 8 chunks, registers and host stack |
| R1515 `[heapwatch]` | Every change of the heap head 0x8006FAF0 |
| R1516 `[heaptrip]` | Physical-address write tripwire on the heap head; `sw_active` separates guest stores from runtime writers |

## Still open (a different class, all after MainLoop)

- **A restart after MainLoop.** Most R1517 runs show a second boot, logged as `[bootmain] ... prior cycle: 1 fn_80019ACC error-dispatcher calls (SPIKE = Module-6 validation failing)`.
- **Two other rodata writers in 2 of 6 runs.**
  - Trial 6: 0x80010004 and 0x80018EAC are zeroed inside the CD handler chain (800409E4 → 80040A4C → getintr).
  - Trial 1: 0x80018EAC is zeroed, then set to 80808080, around an unaligned jump to 0x80045E0A (v0=5600200E) in 8004B8BC.
  - The R1514/R1516 cameras cover both and will name the writers.
- **Escape is not claimed.** `score.py` gives 4/6 against 3/6 and 2/6, but these were 150s boot runs, not the 300s escape protocol, and two of the "escapes" sit at t=2s.

## Unrelated finding

`duckstation/xenogears.bin` in the source folder is **not Xenogears**: its root holds `SLUS_005.53`, `ALUN_CD.EXE`, `ARAN_XA.XA` and a `TAKI` directory. `run.sh` correctly uses the Desktop copy (`SLUS_006.64` at LBA 108606), so runs are unaffected, but nothing should use the duckstation file as a reference.
