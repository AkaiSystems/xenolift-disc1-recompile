#!/bin/bash
# c511_extract.sh - READ-ONLY SLOT-4 ARMING CENSUS, NO RUN,
# NO BUILD, NO PATCH. The c510 receipts: (1) fn_80041B24 is
# an EPILOGUE TAIL (frame restore + return) - the hook's
# 'at fn 0x80041B24' is the last-DISPATCHED function, the
# known attribution trap; the real writer is a
# directly-called leaf. (2) The runtime ALREADY HAS the
# R408 field data-ready arm assist - but the R409 era-size
# gate was added after it mis-fired during HEALTHY reads
# (seeks 239317/109158) and the c510 receipt CUTS OFF
# mid-sentence exactly at the current gate condition.
# (3) 0x80056788 is the slot-bits word the runtime posts
# when a sector arrives (line 1012 comment); the healthy
# 02->102 and the broken 88000000->88000001 may be the
# same overlapping byte store - so the missing piece may
# be the collector's slot-4 EVENT ENQUEUE, not the bit.
# THIS CENSUS receipts: (1) the FULL R408/R409 gate
# (runtime.c 3855-4000); (2) the sector-post block at
# 990-1130 (the 56788 writer); (3) the collector cells
# (0x800564A4/A8/AC/B0) and fn_8004111C in the emitted
# code; (4) the healthy window's [slot] enqueue receipts;
# (5) the collector slot=4 full history. Fail-closed, tee'd
# to /tmp/c511_receipts.txt. Pure-ASCII output.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C511-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c511_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="13aab535963b12c3ff0515d0c2892e8d7625327afa09a3569ae1f2d7b3e1c5d4"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the c504 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the c504 tree with the landed interpreter)"
LOG="run.log"
if [ ! -s "$LOG" ]; then LOG="run.log.d"; fi
D="disc1.c"
for F in "$LOG" "$D"; do
  if [ ! -s "$F" ]; then echo "GATE-FAILED: $F missing/empty"; exit 0; fi
done
echo "===R409GATE511=== the FULL R408/R409 field data-ready gate (runtime.c 3855-4000)"
sed -n "3855,4000p" "$SRC"
echo "===POST511=== the sector-post block (runtime.c 990-1130, the 56788 writer)"
sed -n "990,1130p" "$SRC"
echo "===COLL511=== the collector cells in the emitted code (0x800564A4/A8/AC/B0)"
grep -n -F -e "0x800564A4u" "$D" | head -8
grep -n -F -e "0x800564AC" "$D" | head -8
echo "--- fn_8004111C's body (the ENQUEUE camera's function):"
F1=$(grep -n -e "0x8004111C (function)" "$D" | head -1 | cut -d: -f1)
if [ -n "$F1" ]; then sed -n "$((F1)),$((F1+70))p" "$D"; else echo "(function header not found; trying the label)"; grep -n -e "fn_8004111C" "$D" | head -6; fi
echo "===SLOTW511=== the healthy window's [slot] enqueue receipts (lines 4150-4210)"
awk 'NR>=4150 && NR<=4210 { print NR": "$0 }' "$LOG" | grep -e "\[slot\]" -e "slot=4" -e "564A4" -e "564A8" -e "564AC" | head -20
echo "--- the collector slot=4 full history (both runs):"
grep -n -e "collector slot=4" "$LOG" | head -20
echo "===C511DONE=== the slot-4 arming chain is receipted end-to-end - the c512 fix follows from these receipts only - digest is pure ASCII"
