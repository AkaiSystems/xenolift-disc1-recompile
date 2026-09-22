#!/bin/bash
# c481_extract.sh - READ-ONLY CENSUS, NO RUN, NO BUILD,
# NO PATCH. The c480 verdict: the movie phase (state 6)
# mounted, positioned the drive at 109166 with the
# movie dest res=801EF300, but its module load NEVER
# ARMED A READ (FE04=0, FDF8=0, FE1C=6), then the game
# DELIBERATELY requested state 0 - the designed
# fallback to the menu. RECEIPTS: (1) STATE6481: did
# the MOVIE entry (0x800737EC/MODULE 6) dispatch in
# the state-6 era; (2) FILE25W481: the loader steps
# (R754); (3) ARM481: the R1364/R1365 queued-arm gate
# in the tree; (4) LOADER481: the fn 80019BD0 body;
# (5) BAND481: the movie-band ftab identity
# (109158/109166). Fail-closed, tee'd to
# /tmp/c481_receipts.txt.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C481-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c481_receipts.txt) 2>&1
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
D="disc1.c"
if [ ! -f "$D" ]; then echo "GATE-FAILED: disc1.c not found"; exit 0; fi
echo "===STATE6481=== the movie-entry dispatch story in the state-6 window (29600-30150)"
for TAG in "MODULE 6" "800737EC" "80019BD0" "109158" "109166"; do
  C=$(awk 'NR>=29600 && NR<=30150' "$LOG" | grep -c -e "$TAG" | tr -d " ")
  echo "$TAG in window: $C"
done
echo "--- the 800737EC lines (head 6):"
awk 'NR>=29600 && NR<=30150' "$LOG" | grep -n -e "800737EC" | head -6
echo "--- the 109166 lines (head 6):"
awk 'NR>=29600 && NR<=30150' "$LOG" | grep -n -e "109166" | head -6
echo "--- the MODULE 6 lines (all eras, head 8):"
grep -n -e "MODULE 6" "$LOG" | head -8
echo "===FILE25W481=== the loader steps (R754, all eras)"
grep -n -e "file25w" "$LOG" | head -10
echo "===ARM481=== the R1364/R1365 queued-arm in the current tree"
grep -n -e "R1364" "$SRC" | head -8
grep -n -e "R1365" "$SRC" | head -8
RL=$(grep -n -e "R1364" "$SRC" | head -1 | cut -d: -f1)
if [ -n "$RL" ]; then echo "--- first R1364 site in context (line $RL):"; sed -n "$((RL>25 ? RL-25 : 1)),$((RL+35))p" "$SRC" | head -62; fi
echo "===LOADER481=== the fn 80019BD0 body (the state-6 loader)"
LN=$(grep -n -e "0x80019BD0 (function)" "$D" | head -1 | cut -d: -f1)
echo "marker at line $LN"
if [ -n "$LN" ]; then sed -n "${LN},$((LN+45))p" "$D" | head -47; fi
echo "===BAND481=== the movie-band ftab receipts (all eras)"
grep -n -e "file#=18" "$LOG" | head -6
grep -n -e "LBA=109158" -e "seek=109158" "$LOG" | head -6
echo "===C481DONE=== the movie-entry dispatch + arm gate + loader body are in - the c482 fix follows from these only"
