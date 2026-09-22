#!/bin/bash
# c475_extract.sh - READ-ONLY DECODE, NO RUN, NO BUILD,
# NO PATCH. The c474 census: SkipInput never dispatched
# (the park is NOT the old movie-poll era), both virtual
# players never fired, the sentinel lived only in the
# old-era sgarm class, the frame counter is FROZEN in
# the current park. RECEIPTS: (1) RCB475: the 3
# ReadControllerButtons log hits + era context; (2)
# SENT475: all 15 sentinel lines; (3) MOVIEMAKER475:
# the g_movie_live writer gate region + the 'four
# working cells' comment; (4) R636475: does the park
# census exist; (5) BTNWATCH475: the button-watch
# region; (6) MPAD475: the sio-acc counter site.
# Fail-closed, tee'd to /tmp/c475_receipts.txt.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C475-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c475_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="d86f3deb57aed5b0921ab3a82867dea3a1e1d9960028e360bed8d9bdc90d45f8"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the R1387 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the R1387 tree)"
LOG="run.log"
if [ ! -s "$LOG" ]; then LOG="run.log.d"; fi
if [ ! -s "$LOG" ]; then echo "GATE-FAILED: no preserved run log"; exit 0; fi
echo "LOG=$LOG ($(wc -l < "$LOG" | tr -d " ") lines)"
echo "===RCB475=== the ReadControllerButtons log hits (era context)"
grep -n -e "8003569C" "$LOG" | head -6
echo "--- context around each hit:"
for LN in $(grep -n -e "8003569C" "$LOG" | head -3 | cut -d: -f1); do
  echo "--- (hit at line $LN):"
  sed -n "$((LN>3 ? LN-3 : 1)),$((LN+3))p" "$LOG" | head -8
done
echo "===SENT475=== all the sentinel lines"
grep -n -e "452DAAEE" "$LOG" | head -16
echo "===MOVIEMAKER475=== the g_movie_live writer gate + the four-working-cells comment (tree 19940-20030)"
sed -n "19940,20030p" "$SRC"
echo "===R636475=== does the park census exist (the R636/R640 region, tree 19037-19120)"
sed -n "19037,19120p" "$SRC"
echo "===BTNWATCH475=== the button-watch region (tree 19385-19435)"
sed -n "19385,19435p" "$SRC"
echo "===MPAD475=== the sio-acc counter site"
grep -n -e "sio-acc" "$SRC" | head -4
RL=$(grep -n -e "sio-acc" "$SRC" | head -1 | cut -d: -f1)
if [ -n "$RL" ]; then echo "--- (site at line $RL):"; sed -n "$((RL>14 ? RL-14 : 1)),$((RL+16))p" "$SRC" | head -32; fi
echo "===C475DONE=== the RCB eras + writer gates + watch regions are in - the c476 fix follows from these only"
