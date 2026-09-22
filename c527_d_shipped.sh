#!/bin/bash
# c527_census.sh - READ-ONLY EPOCH-BY-EPOCH HEAP CENSUS, NO
# RUN, NO BUILD, NO PATCH. THE c526 VERDICTS: (1) member 6
# read HEALTHY earlier in the same run (line 8906: dest=
# 800AFC98, same caller 800197B4) - the garbage dest=0x1
# at line 30436 is the THIRD epoch's failure of a call
# that worked in epoch one. (2) THE ALLOCATION WALK IS THE
# WRITER: [heap] alloc #14 size=2660 -> the walk traverses
# -> [heapend] R1174 END sentinel OBSERVED @801FBFF8 (the
# heap's very top) -> the dash-terminator treated as
# end-of-list -> [s5cam] alloc-return consumed v0=00000001
# -> [ovlread] file#=6 a1=0x00000001 - the allocator walked
# the whole heap, found NO free 2660 block, returned 1,
# and the loader consumed 1 as the destination. (3) THE
# RUNAWAY FOLLOWS: UnpackCompressedBuffer a0=80029670
# a1=00000001 r31=0000000A (dest=1, a code address as
# source) -> the wild writes trash the CD state. (4) THE
# HEAP CELLS ARE TAINT-CORRUPTED (77450=F4FC0232...) and
# the module allocations accumulate across the three
# fault-walk restarts - the R772 restore covers ONLY the
# exe image (0x80010000..0x8006F000), so the heap band
# above it is never reset between epochs. THE OPEN
# QUESTION before the fix: is the heap genuinely
# EXHAUSTED across restarts (no release, allocations
# accumulate) or CORRUPTED into early termination - and
# does the game's own ReleaseAllHeapBlocks ever run?
# THIS CENSUS: (1) ALL the [heap] alloc receipts + the
# walk receipts ([walk]/[walkterm]/[walkterm2]/[dashfix]/
# [heapend]) with line numbers - the epoch-by-epoch
# allocation picture; (2) all the [s5cam] alloc-return
# receipts (the v0 values per epoch); (3) the heap-cell
# writers (77450/77454/77458 receipts); (4) the FULL
# newmod dest progression (all epochs, head+tail); (5)
# the release family (ReleaseAllHeap / 80031B24 /
# ReleaseHeapBlock) - did the game's own release ever
# run; (6) the epoch boundaries (fwrestart lines) as the
# census ruler. Fail-closed, tee'd to
# /tmp/c527_receipts.txt. Pure-ASCII output.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C527-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c527_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="d1c3d3912462c72ac7a811d8ce177c18b56166a6aa4825049cc3b686330b6384"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the c524 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the c524 tree with the landed R1381 park-release request)"
LOG="run.log"
if [ ! -s "$LOG" ]; then echo "GATE-FAILED: no run.log"; exit 0; fi
echo "LOG=run.log ($(wc -l < "$LOG" | tr -d " ") lines)"
echo "===EPOCHS527=== the epoch ruler (the fwrestart boundaries)"
grep -n -e "fwrestart" "$LOG"
echo "===WALKALL=== the allocation + walk receipts, epoch by epoch"
echo "--- all the [heap] alloc receipts:"
grep -n -e "\[heap\]" "$LOG" | head -24
echo "--- all the [walk] hop receipts:"
grep -n -e "\[walk\] hop" "$LOG" | head -20
echo "--- the terminator family receipts:"
grep -n -e "walkterm" -e "dashfix" "$LOG" | head -16
echo "--- all the [heapend] END sentinel observations:"
grep -n -e "heapend" "$LOG" | head -12
echo "===S5CAM527=== all the alloc-return consumption receipts (the v0 values)"
grep -n -e "s5cam" "$LOG" | head -12
echo "===HEAPCELLS=== the heap-cell receipts (77450/77454/77458 - the writers)"
grep -n -e "77450" "$LOG" | head -16
echo "===NEWMODALL=== the FULL module-dest progression (all epochs)"
grep -n -e "\[newmod\]" "$LOG" | head -14
echo "--- the tail of it:"
grep -n -e "\[newmod\]" "$LOG" | tail -8
echo "===RELALL=== the release family (did the game's own release ever run)"
grep -n -e "ReleaseAllHeap" -e "80031B24" -e "ReleaseHeapBlock" "$LOG" | head -12
echo "--- the heap-teardown receipts near the restarts:"
grep -n -e "ReleaseAll" "$LOG" | head -8
echo "===C527DONE=== the heap question is receipted epoch by epoch - the c528 fix (the restart heap restore or the first-fault fix the receipts name) follows from these receipts only - digest is pure ASCII"
