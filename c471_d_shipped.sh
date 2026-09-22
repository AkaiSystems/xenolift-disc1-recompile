#!/bin/bash
# c471_extract.sh - READ-ONLY DECODE, NO RUN, NO BUILD,
# NO PATCH. The c470 verdict: R1387's announcement
# POSTED (A22C 2->3 from the mv-loop watcher at the
# drain close) - but the park loop still spins
# (player=0, 56M polls). The loop's exit is NOT the
# announcement family. THIS EXTRACTION pulls the
# EMITTED GUEST SOURCE (disc1.c, 1,021,272 lines) of
# the spin family - anchored on the FUNCTION MARKERS
# (not the decl block), per the c468 lesson - plus the
# D_8007B540 table refs (fn 0x800465EC polls it 171M
# times at the park). Fail-closed, tee'd to
# /tmp/c471_receipts.txt.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C471-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c471_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="d86f3deb57aed5b0921ab3a82867dea3a1e1d9960028e360bed8d9bdc90d45f8"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the R1387 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the R1387 tree)"
D="disc1.c"
if [ ! -f "$D" ]; then echo "GATE-FAILED: disc1.c not found at tree root"; exit 0; fi
echo "disc1.c: $(wc -l < "$D" | tr -d " ") lines"
echo "===BODY471=== the spin-family bodies (function-marker anchored)"
for FN in "0x800465EC" "0x800366F0" "0x800370DC" "0x80036C94"; do
  echo "--- $FN body:"
  LN=$(grep -n -e "$FN (function)" "$D" | head -1 | cut -d: -f1)
  if [ -z "$LN" ]; then echo "marker not found for $FN"; continue; fi
  echo "(marker at line $LN)"
  sed -n "${LN},$((LN+70))p" "$D" | head -72
done
echo "===TABLE471=== the 0x8007B540 family refs in the emitted source (the polled table)"
grep -n -e "D_8007B540" "$D" | head -12
echo "--- the first ref in context:"
RL=$(grep -n -e "D_8007B540" "$D" | head -1 | cut -d: -f1)
if [ -n "$RL" ]; then sed -n "$((RL>12 ? RL-12 : 1)),$((RL+22))p" "$D" | head -36; fi
echo "===RTWRITERS471=== runtime.c writers/readers of the 0x8007B540 family"
grep -n -e "0x8007B540" "$SRC" | head -10
echo "===SPINIDS471=== the other loop-ids (marker line numbers only)"
for FN in "0x800366F8" "0x80036760" "0x80036BE0" "0x8003FF84" "0x80040030" "0x80045C20" "0x800317E0" "0x800459DC"; do
  LN=$(grep -n -e "$FN (function)" "$D" | head -1 | cut -d: -f1)
  echo "$FN body at line $LN"
done
echo "===C471DONE=== the spin-family bodies + table refs are in - the c472 fix follows from these only"
