#!/bin/bash
# c391_pauseanat.sh - READ-ONLY CENSUS. NO run, NO patch.
# The c390 anatomy: the epoch-3 PAUSE AT THE MOVIE POSTURE
# (#66, seek=239322, resp=0/0 pend=0 FE1C=6) never retires -
# no further ladder command, the pre-movie spin exits only on
# FE1C=0 and FE1C=6 never clears (the c219 cmd-09 lifecycle
# disease at a new posture). Epoch 1's pause completed
# cleanly (R1360 receipt at 8267). THIS PASS: the epoch-3
# Pause anatomy - the 31403-31480 window, any Pause INT2 at
# epoch 3, the epoch-1 pause comparison, the FE1C=6 writer,
# and the runtime's Pause response site (R1317) - the exact
# code for the R1369 fix.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C391-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="456a8dcd3e3987a3ff79b490133d5ff63c6f1f2961dfbd6d9b336d945da7e141"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1368 tree - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1368 tree)"
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
if [ ! -s "$LOG" ]; then echo "TREE-ROOT-LOG-MISSING"; exit 0; fi
echo "AUTHORITATIVE LOG = $LOG ($(wc -l < "$LOG" | tr -d ' ') lines)"
echo "===PAUSEWIN391=== the epoch-3 Pause window (lines 31400-31480)"
awk 'NR>=31400 && NR<=31480 { print NR": "$0 }' "$LOG" | grep -v "lzss-fence\|narrowblast\|bandhist" | head -48
echo "===PAUSEINT2C391=== every Pause response receipt in epoch 3 (31200-32001)"
grep -n "Pause complete\|cmd 0x09\|cmd 09" "$LOG" | awk -F: '$1>=31200' | head -12
echo "===PAUSEINT2ALL391=== every Pause response receipt whole-run"
grep -n "Pause complete" "$LOG" | head -10
echo "===E1PAUSE391=== the epoch-1 Pause window for comparison (lines 8255-8330)"
awk 'NR>=8255 && NR<=8330 { print NR": "$0 }' "$LOG" | grep -v "lzss-fence\|narrowblast\|bandhist" | head -36
echo "===FE1C6W391=== the FE1C->6 writers in epoch 3 (who set the stuck state)"
grep -n "chg\] FE1C" "$LOG" | awk -F: '$1>=31000' | head -12
grep -n "FE1C 000.->0006\|FE1C ..-> 0006" "$LOG" | awk -F: '$1>=31000' | head -8
echo "===FE1CCELL391=== the FE1C cell writers near the stuck window (hook receipts at 8004FE1C)"
grep -n "hook\] 0x8004FE1C" "$LOG" | awk -F: '$1>=31350' | head -10
echo "===VINT391=== the virtual INT3 receipts for cmd 09 (the pause ack path)"
grep -n "virtual INT3: cmd 0x09" "$LOG" | head -8
echo "===PAUSESITE391=== the runtime Pause response site (R1317 restoration)"
grep -n "Pause complete\|R1317" "$SRC" | head -14
echo "===R1360SITE391=== the R1360 module-era pause handler (its gate may exclude the movie posture)"
LG=$(grep -n "R1360 module-era Pause" "$SRC" | head -1 | cut -d: -f1)
echo "R1360 print at line $LG"
if [ -n "$LG" ]; then
  S=$((LG-45)); [ $S -lt 1 ] && S=1
  E=$((LG+15))
  awk -v s="$S" -v e="$E" 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
fi
echo "===C391DONE=== the epoch-3 Pause anatomy is receipted"
