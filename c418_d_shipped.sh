#!/bin/bash
# c418_callerdecode.sh - READ-ONLY CENSUS. NO run, NO patch.
# The c417 verdict: FE48 = g_ArchiveDebugTable, the
# game's archive HOST/DEBUG ROUTE GATE (nonzero bypasses
# the FAT); the runtime never writes it and no receipted
# 0->1 write exists - the FE48=1 writer is unreceipted.
# A22C's increments are our R879-era movie-door posts
# (the game's own chain, slot bits 0x80056788 + flag
# 0x800578A6, never dispatches this era). No waitbr
# receipts in the final-spin era (print policy
# unverified). The caller's release contract is still
# UNNAMED - so THIS PASS decodes the CALLER DIRECTLY:
# (1) the decompiled source of the rotating loop-id fns
# (800366F8, 80036760, 80036BE0, 80036C94, 800370DC,
# 8003FC58, 800403FC, 80046DB4) + their common caller
# (r31=80036BE8, 80036C54) from disc1.c - what cells do
# they poll?; (2) the R870 loop-id camera's identification
# source; (3) the R1306 waitbr camera's print condition
# (interpret the final-era absence correctly); (4) the FE48
# value timeline across all cameras (asyctx/R874/hook/
# walkread) + the game's archive-debug-table init writer
# (grep disc1.c for g_ArchiveDebugTable stores); (5) the
# R879/R896 doorbell gating context (when do the three
# A22C increment sites fire); (6) the movie event chain
# (0x80056788 slot bits + 0x800578A6) in the final era.
# NO behavior change - receipts only. R1378 follows from
# these receipts only.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C418-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="6759e34359fdf33df2e78cfaf2c144194da718412f3d42cb022b12e87470a8bb"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1377 tree - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1377 tree)"
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
echo "===LOOPFN418=== the caller's own code: the rotating loop-id fns from disc1.c"
D="disc1.c"
[ -f "$D" ] || D=$(find . -name "disc1.c" -not -path "./target/*" 2>/dev/null | head -1)
echo "disc1.c = $D"
if [ -n "$D" ] && [ -f "$D" ]; then
  for FN in 800366F8 80036760 80036BE0 80036C94 800370DC 8003FC58 800403FC 80046DB4 80036BE8; do
    L=$(grep -n "fn_$FN\b\|$FN" "$D" | head -2)
    echo "--- $FN: ${L:-not-found-in-decomp}"
  done
  echo "--- first loop fn full body (the deepest decoded):"
  F=$(grep -n "80036BE8\|fn_80036BE8" "$D" | head -1 | cut -d: -f1)
  if [ -n "$F" ]; then
    awk -v s="$F" -v e="$((F+60))" 'NR>=s && NR<=e { print NR": "$0 }' "$D" | head -62
  fi
else
  echo "disc1.c NOT FOUND - listing candidate decomp files:"
  find . -maxdepth 2 -name "*.c" -not -path "./target/*" 2>/dev/null | head -10
fi
echo "===R870SITE418=== the R870 loop-id camera's identification source"
R=$(grep -n "R870" "$SRC" | head -2)
echo "$R"
R1=$(echo "$R" | head -1 | cut -d: -f1)
if [ -n "$R1" ]; then awk -v s="$((R1-8))" -v e="$((R1+25))" 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"; fi
echo "===WAITBRCOND418=== the R1306 waitbr camera's print condition"
W=$(grep -n "R1306" "$SRC" | head -2)
echo "$W"
W1=$(echo "$W" | head -1 | cut -d: -f1)
if [ -n "$W1" ]; then awk -v s="$((W1-10))" -v e="$((W1+20))" 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"; fi
echo "===FE48TL418=== the FE48 value timeline across all cameras"
grep -n "FE48" "$LOG" | grep -v "mvloop" | awk -F: '{ if ($0 ~ /FE48=0+/) print "ZERO: "$0; else if ($0 ~ /FE48=0*1[^0-9]|FE48=00000001/) print "ONE: "$0 }' | head -12
echo "--- asyctx FE48 samples (first 3 + last 3):"
grep -n "FE48" "$LOG" | grep "asyctx" | head -3
grep -n "FE48" "$LOG" | grep "asyctx" | tail -3
echo "===ARCHDBG418=== the game's archive-debug-table init writer (disc1.c stores)"
if [ -n "$D" ] && [ -f "$D" ]; then
  grep -n "g_ArchiveDebugTable" "$D" | head -8
fi
echo "===R879GATE418=== the A22C increment sites' gating (the R879 movie-door posts)"
for LN in 1074 1200 1808; do
  echo "--- site at line $LN (context -18/+3):"
  awk -v s=$((LN-18)) -v e=$((LN+3)) 'NR>=s && NR<=e { print NR": "$0 }' "$SRC" | head -22
done
echo "===MOVIECHAIN418=== the game's own event chain in the final era (slot bits 56788 + flag 578A6)"
grep -n "578A6" "$LOG" | awk -F: '$1 > 30000' | head -8
grep -n "56788" "$LOG" | awk -F: '$1 > 31000' | grep -v "cdcsync\|movsite" | head -8
echo "===C418DONE=== the caller is decoded from source - R1378 follows from these receipts only"
