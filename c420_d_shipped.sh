#!/bin/bash
# c420_gatecontracts.sh - READ-ONLY CENSUS. NO run, NO
# patch. The c419 verdict: the final-era loop is the
# game's per-frame TEXT REDRAW (the font family is the
# game's vsprintf-into-font-buffer) - the game is ALIVE,
# drawing text, flipping buffers; the wall = the movie
# never STARTS. GOLD: LegacyCdCommandSync (0x80041B3C)
# is decoded as the family that writes the A22C cells
# (L_80041B84-BA4: SW A22C=0) - the game's OWN
# A22C-CLEARING STORE never executes in the final era
# (sync-chunk entries climb, A22C stays 4 = our four
# R896 boot posts, a latch). The c193 question is
# ANSWERED: file#18's data WAS consumed (FDF8 wrapped
# 0) -> the movie PLAY protocol wants something else.
# THIS PASS decodes the three decisive functions from
# disc1.c: (1) LegacyCdCommandSync (0x80041B3C) - the
# branch structure: which condition routes to the
# A22C=0 store at L_80041B84-BA4 vs the pace-chunk at
# 80041BA8; (2) LegacyCdDataWait (r31=80041420 family)
# - the cells it reads + its return contract; (3) the
# movie-loader poll family (8003569C/8004CCA8/80040690)
# - what each polls. Plus: (4) the [siopad] receipt
# census (all 24, with line numbers - when did the game
# LAST read the pad). NO behavior change - receipts
# only. R1378 follows from these receipts only.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C420-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="6759e34359fdf33df2e78cfaf2c144194da718412f3d42cb022b12e87470a8bb"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1377 tree - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1377 tree)"
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
D="disc1.c"
[ -f "$D" ] || { echo "disc1.c missing"; }
echo "===CDSYNC420=== LegacyCdCommandSync (0x80041B3C): the branch to the A22C=0 store"
if [ -f "$D" ]; then
  F=$(grep -n "---------- 0x80041B3C" "$D" | head -1 | cut -d: -f1)
  echo "fn header at line: $F"
  if [ -n "$F" ]; then
    awk -v s="$F" -v e="$((F+150))" 'NR>=s && NR<=e { print NR": "$0 }' "$D" | head -152
  fi
fi
echo "===DATAWAIT420=== LegacyCdDataWait (the r31=80041420 family): the read contract"
if [ -f "$D" ]; then
  for F in $(grep -n "---------- 0x80041420\|---------- 0x800414\|---------- 0x800286CC" "$D" | head -3 | cut -d: -f1); do
    echo "--- fn at line $F:"
    awk -v s="$F" -v e="$((F+90))" 'NR>=s && NR<=e { print NR": "$0 }' "$D" | head -92
  done
fi
echo "===MOVIEPOLL420=== the movie-loader poll family (8003569C/8004CCA8/80040690)"
if [ -f "$D" ]; then
  for FN in 8003569C 8004CCA8 80040690; do
    F=$(grep -n "---------- 0x$FN" "$D" | head -1 | cut -d: -f1)
    echo "--- $FN at line $F"
    if [ -n "$F" ]; then
      awk -v s="$F" -v e="$((F+70))" 'NR>=s && NR<=e { print NR": "$0 }' "$D" | head -72
    fi
  done
fi
echo "===SIOPAD420=== the pad-read receipt census (all 24 with line numbers)"
grep -n "siopad" "$LOG" | head -26
echo "===MOVSITE420=== the movsite receipts (entries + the gate-decline count)"
grep -n "movsite" "$LOG" | head -12
echo "===C420DONE=== the gate contracts are decoded - R1378 follows from these receipts only"
