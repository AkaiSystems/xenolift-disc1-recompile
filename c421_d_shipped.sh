#!/bin/bash
# c421_gatecontracts2.sh - READ-ONLY CENSUS. NO run, NO
# patch. The c420 half-failed: grep patterns with
# leading dashes are parsed as grep OPTIONS regardless
# of shell quoting (lesson saved). The receipts that
# landed: [siopad] = ZERO for the whole log (the game
# never read the emulated SIO pad register; the pad
# path is the RAM buffer 0x800625FC); movsite = 8
# entries all at one boot second, count cut by my own
# head cap. THIS PASS re-runs the decodes with -e-
# anchored patterns: (1) LegacyCdCommandSync (0x80041B3C)
# - the branch structure, esp. the path that never
# reaches the game's own A22C=0 store (L_80041B84-BA4);
# (2) LegacyCdDataWait's read contract (the waiter
# called from r31=80041420); (3) the movie-loader poll
# family (8003569C ReadControllerButtons / 8004CCA8 /
# 80040690) - what each polls; (4) the FULL movsite
# census (count + last entry line); (5) the btn camera's
# print policy + the final-era pad-buffer read story;
# (6) 8003569C's callers in disc1.c. NO behavior change
# - receipts only. R1378 follows from these receipts
# only.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C421-FAILED: xenolift dir missing"; exit 1; }
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
if [ ! -f "$D" ]; then echo "disc1.c MISSING"; exit 0; fi
echo "===CDSYNC421=== LegacyCdCommandSync (0x80041B3C): the branch to the A22C=0 store"
F=$(grep -n -e "0x80041B3C (function)" "$D" | head -1 | cut -d: -f1)
echo "fn header at line: $F"
if [ -n "$F" ]; then
  awk -v s="$F" -v e="$((F+150))" 'NR>=s && NR<=e { print NR": "$0 }' "$D" | head -152
fi
echo "===DATAWAIT421=== LegacyCdDataWait's contract (r31=80041420 region + name search)"
grep -n -e "LegacyCdDataWait" "$D" | head -6
F2=$(grep -n -e "LegacyCdDataWait" "$D" | head -1 | cut -d: -f1)
if [ -n "$F2" ]; then
  awk -v s="$F2" -v e="$((F2+80))" 'NR>=s && NR<=e { print NR": "$0 }' "$D" | head -82
fi
echo "--- the caller chunk at 0x80041420:"
F3=$(grep -n -e "0x80041420" "$D" | head -1 | cut -d: -f1)
echo "first 80041420 ref at line: $F3"
if [ -n "$F3" ]; then
  awk -v s="$F3" -v e="$((F3+60))" 'NR>=s && NR<=e { print NR": "$0 }' "$D" | head -62
fi
echo "===MOVIEPOLL421=== the movie-loader poll family"
for FN in 8003569C 8004CCA8 80040690; do
  F4=$(grep -n -e "0x$FN (function)" "$D" | head -1 | cut -d: -f1)
  echo "--- $FN at line $F4"
  if [ -n "$F4" ]; then
    awk -v s="$F4" -v e="$((F4+70))" 'NR>=s && NR<=e { print NR": "$0 }' "$D" | head -72
  fi
done
echo "===MOVSITEFULL421=== the FULL movsite census (count + last entries)"
echo "total movsite lines: $(grep -c -e "movsite" "$LOG")"
grep -n -e "movsite" "$LOG" | tail -4
echo "===BTNPOL421=== the btn camera's print policy + the final-era pad story"
B=$(grep -n -e "btn census\|btncen\|btn\]" "$SRC" | head -3)
echo "$B"
B1=$(echo "$B" | head -1 | cut -d: -f1)
if [ -n "$B1" ]; then
  awk -v s="$((B1-8))" -v e="$((B1+14))" 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
fi
echo "--- final-era pad receipts (any tag, after 31000):"
grep -n -e "btn" "$LOG" | awk -F: '$1 > 31000' | head -6
echo "--- 8003569C callers in disc1.c:"
grep -n -e "fn_8003569C" "$D" | head -6
echo "===C421DONE=== the gate contracts are decoded - R1378 follows from these receipts only"
