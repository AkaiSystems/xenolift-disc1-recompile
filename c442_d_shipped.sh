#!/bin/bash
# c442_verdict.sh - READ-ONLY VERDICT HARVEST on the
# R1379 run (log preserved in c440_snap; tree c9e85ea1
# verified). NO run, NO patch, NO build. The c441
# census: the 90s run had NO guest crash (no segv at
# 80019524, no exit 99 - first crash-free run of the
# era), the kernel menu rendered, only 2 discards (both
# early-boot), and a NEW tail wedge at file#14 (LBA
# 108933) INT1 arms at t=2s. THIS PASS: (1) the 2
# discards' contexts - FDF8 at each moment (the guard
# must have allowed only FDF8==0 true-stale classes);
# (2) the walk-era presence (cmd=09 walk arms, FE04
# single-digit transitions) - did the LBA 0-9 walk run
# this trajectory?; (3) crash receipts census; (4) the
# file#14 wedge anatomy (the tail era raw window + the
# LBA-108933 serve/drain receipts + cmdtl tail);
# (5) the menu-era fvp sequence. Receipts only.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C442-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="c9e85ea1d9c6ebfd9145cc948dffd37826385f58bd947267ec37b0d39c34b5fb"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1379 tree c9e85ea1 - refusing (harvest must match the tree that made the log)"; exit 0; fi
echo "TREE_VERIFIED (the R1379 tree)"
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
echo "===GUARDCTX442=== the 2 discards' contexts (FDF8 at each moment)"
grep -n -e "spin-discard" "$LOG" | head -4
for LN in $(grep -n -e "spin-discard" "$LOG" | head -2 | cut -d: -f1); do
  echo "--- context around line $LN:"
  awk -v s=$((LN-8)) -v e=$((LN+4)) 'NR>=s && NR<=e { print NR": "$0 }' "$LOG"
done
echo "===WALK442=== the walk-era presence this trajectory"
echo "--- cmd=09 walk arms (LBA single digits):"
grep -n -e "cmd=09 LBA=[0-9])" "$LOG" | head -14
echo "--- FE04 single-digit transitions (the walk):"
grep -n -e "FE04 0000000" "$LOG" | head -14
echo "===CRASH442=== crash receipts census"
grep -c -e "segv\|SIGSEGV\|BadVAddr\|TRUE DEATH" "$LOG"
grep -n -e "segv\|SIGSEGV\|BadVAddr\|TRUE DEATH" "$LOG" | head -4
grep -c -e "exit status=99" "$LOG"
echo "===F14WEDGE442=== the file#14 tail wedge anatomy"
echo "--- the LBA-108933 receipts tail:"
grep -n -e "108933" "$LOG" | tail -10
echo "--- the raw tail window (last 40 lines):"
tail -40 "$LOG"
echo "--- cmdtl tail:"
grep -n -e "cmdtl" "$LOG" | tail -5
echo "===MENU442=== the menu-era fvp sequence + mount tail"
grep -n -e "fvp" "$LOG" | head -12
grep -n -e "mcw" "$LOG" | tail -5
echo "===C442DONE=== the R1379 verdict receipts are harvested - PASS/REVERT + the file#14 wedge diagnosis follow from these only"
