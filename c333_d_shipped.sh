#!/bin/bash
# c333_collectorprobe.sh - READ-ONLY probe (NO patch, NO run):
# the collector loop, getintr, and the pendclr site table.
# THE c332 CONVICTION: the pair is the GPU/MDEC IRQ handler
# (HW register pointers), NOT the CD handler. The true kernel
# CD INT processing candidate = the tick's collector loop
# (getintr 800415B4 + slot handlers), forge-blocked at L18405.
# THIS CYCLE: (1) sha gate; (2) the collector loop code at
# L18405 (+-30 lines, fresh runtime.c); (3) 800415B4's emitted
# body from disc1.c; (4) the R1167 pendclr site table;
# (5) the full enq/deq/cbreg census from the c332 witness.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C333-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="2de3899174d063071efad05918f54ae2bbdbd64ebb9392628a9b95b340b2e0f8"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1354 tree 2de38991 - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1354 tree)"
echo "===COLLECTOR333=== the collector loop at L18405 (fresh runtime.c)"
G=$(grep -n 'L18405' "$SRC" | head -1 | cut -d: -f1)
echo "L18405_LINE=$G"
if [ -n "$G" ]; then awk -v s="$((G-30))" -v e="$((G+30))" 'NR>=s && NR<=e {print NR": "$0}' "$SRC"; fi
echo "===COLLECTORCTX=== the enclosing block comment (R1293/R316 collector notes)"
grep -n "R1293\|collector loop\|R471 drain" "$SRC" | head -12
echo "===GETINTR333=== the 800415B4 emitted body (disc1.c)"
D="disc1.c"
[ -s "$D" ] || D="runtime/disc1.c"
if [ -s "$D" ]; then
  G2=$(grep -n "0x800415B4 (function)" "$D" | head -1 | cut -d: -f1)
  echo "GETINTR_DEF_LINE=$G2"
  if [ -n "$G2" ]; then awk -v s="$((G2-2))" -v e="$((G2+40))" 'NR>=s && NR<=e {print NR": "$0}' "$D"; fi
else
  echo "NO disc1.c"
fi
echo "===SITETAB333=== the R1167 pendclr site table (which game sites clear pendings)"
G3=$(grep -n "R1167" "$SRC" | head -1 | cut -d: -f1)
echo "R1167_FIRST_LINE=$G3"
grep -n "R1167" "$SRC" | head -10
G4=$(grep -n "site=" "$SRC" | head -3)
echo "$G4"
echo "===PENDCLR333=== the pendclr receipts in the c332 witness (which sites fired)"
W=$(ls -1d witness_c332_* 2>/dev/null | tail -1)
echo "WITNESS_DIR=$W"
LOG="$W/run.log"; [ -s "$LOG" ] || LOG="$W/run.log.d"
grep -n "pendclr" "$LOG" | head -16
echo "===ENQ333=== the full enq/deq/cbreg census (all priorities)"
grep -n "\[enq\]\|\[deq\]\|\[cbreg\]\|SysEnqIntRP\|SetCdSectorCallback" "$LOG" | head -16
echo "===C333DONE=== probe complete - the collector loop's mechanics name the fix"
