#!/bin/bash
# c536_census.sh - READ-ONLY CENSUS of the corrupted-call
# family in the movie-era setup, NO RUN, NO BUILD, NO PATCH.
# THE c535 DECODE: the c534 trajectory reached deeper
# territory than any prior run - epoch 4 installed
# member=18 (the MOVIE MODULE, gdisp=6, dest 801EF300),
# the R1394 interpreter COMPLETED module 6's entry at
# 800737EC, and the install chain went on to
# SelectArchiveDirectoryEntry(0x18) - the first-content
# load itself. THE FIRST FAULT (receipted, epoch 3 line
# 25453): the loader called UnpackCompressedBuffer with
# GARBAGE ARGS (dst=0x00000001 ctl=0x00000001, r31=0000000A
# = a corrupted link register, r17=0x19C4=6596 = the walk
# want, NOT a pointer) right after the member walk
# terminated at the DASH node; the src at 80029670 holds
# RAW MIPS CODE (8FBF0020 = lw ra,0x20(sp)), not LZSS data;
# the fallout = suppressed reads (0xFFFFF774) + dropped
# writes (0x00100001) - THE r31=0A FAMILY (64 receipts) IS
# THIS CLASS, not a regression. THE SAME FAMILY in the
# epoch-4 install chain: alloc #28 size=0xFFC00004
# (negative) from r31=0x8007389C (the interpreted module's
# own code) + a MoveHeapAllocation-class walk with a1=
# 0x80800000 (OUT OF GUEST RAM, top 0x80200000) a2=
# 0x00800000 (8MB) - the c80-era NULL-trap family at its
# true depth. DOWNSTREAM (plausibly): the file#2 read
# stalled MID-FILE (14 of 30 sectors, FDF8=33008 = 61680 -
# 14x2048 exactly, drive active, FIFO empty, sgarm
# declining) then RE-ARMED to the full 61680 and hung at
# sector 1 for 60+s (R967 STUCK, A22C never set). THIS
# CENSUS RECEIPTS: (1) the corrupted-unpack family (every
# unpack/lzss receipt with the args + the heal receipts +
# the first-context); (2) WHAT ENDED EPOCH 3 (the receipts
# between the corrupted unpack at 25453 and the restart at
# 25670 - the fault itself); (3) the epoch-4 garbage-alloc
# provenance (alloc #27/#28 + the walk/hand/carve/phase
# window + MoveHeapAllocation args); (4) the stall sequence
# (the sgdecline context, the 108769 receipts, the first
# R967 window, the epoch-4 fdw arms); (5) the movie-module
# install chain (member=18 + SelectArchiveDirectoryEntry +
# the interpreter-era timeline). Fail-closed, tee'd to
# /tmp/c536_receipts.txt. Pure-ASCII output.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C536-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c536_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="cc637bfb05891064a87390bd8918bf7a1742c45f458a2796bcece5cab02b1602"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the c534 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the c534 tree with the landed R1396 empty-door guard)"
LOG="run.log"
if [ ! -s "$LOG" ]; then echo "GATE-FAILED: no run.log"; exit 0; fi
echo "LOG=run.log ($(wc -l < "$LOG" | tr -d " ") lines)"
echo "===UNPK536=== the corrupted-unpack family (the args + the heals + the first context)"
grep -n -e "\[unpackw\]" "$LOG" | head -12
grep -c -e "\[unpackw\]" "$LOG" | tr -d " " | sed "s/^/unpackw receipts: /"
grep -n -e "\[lzss\] #" "$LOG" | head -8
grep -n -e "lzss-heal" "$LOG" | head -6
echo "--- the first corrupted-unpack context (the caller side, 25440-25456):"
sed -n "25440,25456p" "$LOG"
echo "===E3X536=== what ended epoch 3 (the receipts between the corrupted unpack 25453 and the restart 25670)"
awk "NR>25453 && NR<25675" "$LOG" | grep -n -e "fault" -e "abort" -e "exit" -e "restart" -e "receipt" -e "lzss" -e "unpack" -e "walk" -e "alloc" -e "trap" -e "stop" -e "SEGV" -e "guard" | head -20
echo "--- the last 12 lines before the epoch-3 restart (25658-25670):"
sed -n "25658,25670p" "$LOG"
echo "===ALLOC536=== the epoch-4 garbage-alloc provenance (the interpreted module's own calls)"
grep -n -e "\[heap\] alloc" "$LOG" | tail -8
echo "--- the walk/hand/carve/phase window (the MoveHeapAllocation-class args):"
grep -n -e "\[hand\]" "$LOG" | tail -6
grep -n -e "\[coal\]" "$LOG" | tail -4
grep -n -e "\[carvecam\]" "$LOG" | tail -4
grep -n -e "\[phase\]" "$LOG" | tail -4
echo "--- the alloc #28 context (the negative-size call from the module code):"
A28=$(grep -n -F -e "alloc #28 size=4293575748" "$LOG" | head -1 | cut -d: -f1)
if [ -n "$A28" ]; then
  _A0=$((A28-8)); [ "$_A0" -lt 1 ] && _A0=1
  sed -n "${_A0},$((A28+8))p" "$LOG"
fi
echo "===STALL536=== the stall sequence (mid-file stall -> re-arm -> sector-1 hang)"
echo "--- the sgdecline first-eval context (the 14-sectors-delivered stall):"
S1=$(grep -n -e "sgdecline" "$LOG" | head -1 | cut -d: -f1)
if [ -n "$S1" ]; then
  _S0=$((S1-12)); [ "$_S0" -lt 1 ] && _S0=1
  sed -n "${_S0},$((S1+6))p" "$LOG"
fi
echo "--- the seek=108769 receipts (the mid-file LBA):"
grep -n -e "108769" "$LOG" | head -8
echo "--- the first R967 STUCK context (the re-armed hang):"
R1=$(grep -n -e "R967 STUCK 10s" "$LOG" | head -1 | cut -d: -f1)
if [ -n "$R1" ]; then
  _R0=$((R1-12)); [ "$_R0" -lt 1 ] && _R0=1
  sed -n "${_R0},$((R1+4))p" "$LOG"
fi
echo "--- the epoch-4 fdw arms (the re-arm to the full 61680):"
awk 'NR>30000' "$LOG" | grep -n -e "FDF8 ARM" | head -4
echo "===MV536=== the movie-module install chain (member=18 + the interpreter era)"
grep -n -e "member=18" "$LOG"
grep -n -e "SelectArchiveDirectoryEntry" "$LOG" | head -4
echo "--- the interpreter-era timeline (30057-30110, the onward chain):"
sed -n "30057,30074p" "$LOG"
echo "===C536DONE=== the corrupted-call family + the epoch deaths + the stall order are receipted - the c537 fix follows from these receipts only - digest is pure ASCII"
