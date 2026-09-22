#!/bin/bash
# c483_extract.sh - READ-ONLY CENSUS, NO RUN, NO BUILD,
# NO PATCH. The c482 verdict: the movie module (file#18)
# loaded, unpacked, entry dispatched - then the loader
# sat at the PRE-MOVIE SPIN POSTURE (FE04=0, FDF8=0,
# FE1C=6, drive idle; file25w 29991), the class the
# R1369 arm + fd-retire release (12 receipted fires
# incl. FE1C 6->0) was built for in the c392 era. The
# game timed out and called ChangeGameState(0). RECEIPTS:
# (1) FDRET483: did the fd-retire/R1369 release fire in
# the state-6 era; (2) MOVIEBAND483: the 239322
# positioning story; (3) BOOTW483: the resident-loop
# passes in the window; (4) PHASEW483: the dispatch
# ladder in the window; (5) DECLINE483: any decline
# cameras in the window (a no-fire names the gate).
# Fail-closed, tee'd to /tmp/c483_receipts.txt.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C483-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c483_receipts.txt) 2>&1
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
echo "===FDRET483=== the fd-retire / R1369 release story"
for TAG in "fd-retire" "fdretire" "fdret" "R1369" "fsent"; do
  C=$(grep -c -e "$TAG" "$LOG" | tr -d " ")
  echo "$TAG (all eras): $C"
done
echo "--- fd-retire lines (all eras, head 8):"
grep -n -e "fd-retire" -e "fdretire" -e "fdret" "$LOG" | head -8
echo "--- R1369/fsent lines (all eras, head 6):"
grep -n -e "R1369" -e "fsent" "$LOG" | head -6
echo "--- in the state-6 window (29600-30150):"
awk 'NR>=29600 && NR<=30150' "$LOG" | grep -n -e "fd-retire" -e "fdretire" -e "fdret" -e "R1369" -e "fsent" | head -8
echo "===MOVIEBAND483=== the 239322 movie-band story"
echo "--- in window:"
awk 'NR>=29600 && NR<=30150' "$LOG" | grep -n -e "239322" -e "239324" | head -8
echo "--- all eras (head 6):"
grep -n -e "239322" "$LOG" | head -6
echo "===BOOTW483=== the resident-loop passes in the window"
awk 'NR>=29600 && NR<=30150' "$LOG" | grep -n -e "fn_80019ACC" | head -8
echo "--- [boot] lines all eras tail 4:"
grep -n -e "\[boot\] fn_80019ACC" "$LOG" | tail -4
echo "===PHASEW483=== the dispatch ladder in the window"
awk 'NR>=29600 && NR<=30150' "$LOG" | grep -n -e "\[phase\]" | head -10
echo "===DECLINE483=== decline cameras in the window (a no-fire names the gate)"
awk 'NR>=29600 && NR<=30150' "$LOG" | grep -n -e "decline" -e "zrf" -e "decline" | head -10
echo "===C483DONE=== the fd-retire + movie-band stories are in - the c484 fix follows from these only"
