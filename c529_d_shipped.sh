#!/bin/bash
# c529_census.sh - READ-ONLY CENSUS of the zrfF gate and
# the new LegacyCdSectorFetch wedge, NO RUN, NO BUILD, NO
# PATCH. THE c528 VERDICT: THE R1395 HEAP-BAND FIX PASSED
# ITS BAR - [heapclr] at both restarts, member-6 dest REAL
# in every epoch (800AFC98 x3), v0 never 1, the dash
# family absent, r31=0A ZERO, the member-6 sector cd-ma'd
# to the valid dst - the epoch-accumulation family is
# CLOSED. THE NEW TERMINAL WEDGE, receipted: the fetch
# (fn 80042AA8) stuck 80s at the fuse - FDF8=2048 armed at
# seek=0, FE04=0, cmd=02, act=0, pend=0, sched=0, A22C=0,
# polling 1F801800 408.9M times, the gate machinery
# RUNNING but declining (last-gate=B(0x35), gate-calls=
# 1444) - the c179 zrfF/R1282 class whose door gates on
# cmd=01: ONE command byte apart. THE SCREEN ADVANCED:
# vram_nonzero=16/8192, 2 fills, 57 rects, 2 blits.
# THIS CENSUS: (1) the zrfF/R1282 gate's EXACT current
# source terms (the command byte candidate); (2) the
# R1193 last-gate machinery; (3) the full wedge receipts +
# the first-stuck context; (4) the FDF8 0->2048 arm (WHO
# armed it and for WHICH request); (5) the seek-0 read
# history (did any LBA-0 sector land?); (6) the screen
# witnesses (what drew the first-band content).
# Fail-closed, tee'd to /tmp/c529_receipts.txt.
# Pure-ASCII output.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C529-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c529_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="db0e8c78788d5b2ab9045693cb95a21627e678c7da474581bfe2f3bdf028ad76"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the c528 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the c528 tree with the landed R1395 heap-band clear)"
LOG="run.log"
if [ ! -s "$LOG" ]; then echo "GATE-FAILED: no run.log"; exit 0; fi
echo "LOG=run.log ($(wc -l < "$LOG" | tr -d " ") lines)"
echo "===ZRFF529=== the zrfF/R1282 gate's exact current source terms"
grep -n -e "zrfF" "$SRC" | head -8
grep -n -e "R1282" "$SRC" | head -8
echo "--- the gate term lines (seek<150 / FDF8==2048 / cmd byte):"
grep -n -e "150u" "$SRC" | head -8
echo "--- the 150u context (the gate block):"
GL=$(grep -n -e "150u" "$SRC" | head -1 | cut -d: -f1)
if [ -n "$GL" ]; then
  _G0=$((GL-14)); [ "$_G0" -lt 1 ] && _G0=1
  sed -n "${_G0},$((GL+26))p" "$SRC"
fi
echo "===LASTGATE=== the R1193 last-gate machinery"
grep -n -e "R1193" "$SRC" | head -6
grep -n -e "last-gate" "$SRC" | head -6
echo "===WEDGE529=== the full wedge receipts + the first-stuck context"
grep -n -e "R967 STUCK" "$LOG" | head -8
grep -n -e "R1193" "$LOG" | head -6
echo "--- the first 80042AA8 receipt + its context:"
FW=$(grep -n -e "80042AA8" "$LOG" | head -1 | cut -d: -f1)
echo "first 80042AA8 at line $FW"
if [ -n "$FW" ]; then
  _S0=$((FW-12)); [ "$_S0" -lt 1 ] && _S0=1
  sed -n "${_S0},$((FW+12))p" "$LOG"
fi
echo "--- all the fldfrz2 watcher receipts:"
grep -n -e "fldfrz2" "$LOG" | head -4
echo "===ARM2048=== WHO armed FDF8 0->2048 (and for WHICH request)"
grep -n -e "fdw] R1299 FDF8 ARM-CONTEXT" "$LOG" | grep -e "00000800" | head -8
grep -n -e "ea=8004FDF8" "$LOG" | grep -e "2048" | head -8
echo "===SEEK0=== the seek-0 read history (did any LBA-0 sector land?)"
grep -n -e "LBA 0," "$LOG" | tail -6
grep -n -e "LBA 0 loaded" "$LOG" | tail -4
grep -n -e "fldsec" "$LOG" | head -4
echo "--- the Setloc chain to seek 0:"
grep -n -e "Setloc" "$LOG" | tail -6
echo "===SCREEN529=== the screen witnesses (what drew the first-band content)"
grep -n -e "gpucls" "$LOG" | tail -4
grep -n -e "\[gpu\] R694" "$LOG" | tail -3
grep -n -e "vram_nonzero" "$LOG" | head -6
echo "===C529DONE=== the zrfF gate terms + the wedge posture are receipted - the c530 fix (the command-byte widen or what the receipts name) follows from these receipts only - digest is pure ASCII"
