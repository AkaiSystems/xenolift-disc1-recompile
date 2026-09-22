#!/bin/bash
# c474_extract.sh - READ-ONLY CENSUS, NO RUN, NO BUILD,
# NO PATCH. The c473 receipts: the pre-movie poll chain
# is decoded in-tree (R295/R296) - fn_800769A4
# (MoviePollSkipInput) waits for X (bit 0x40, cells
# 0x800773AC/0x800773B4, gate 0x80077028==0) then sets
# 0x80077014=5=movie start. The R296 virtual player
# gates on g_movie_live (player=0 all park - NEVER
# FIRED); the R474/R1163 machinery gates on the
# 0x452DAAEE sentinel (cell=0x03FF7F14 garbage - all
# silent). RECEIPTS: (1) POLLCENSUS: the preserved
# c470 log - did SkipInput/skip-movie/RCB dispatch,
# did the virtual player or R373 one-shot fire, did
# the sentinel ever appear; (2) MOVIESTATE: the
# current runtime.c g_movie_live/g_press_state
# writers + gates; (3) R373REGION: the menu-era
# player shape; (4) BTNREFS: 0x773AC/0x773B4/
# 0x80077028 refs. Fail-closed, tee'd to
# /tmp/c474_receipts.txt.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C474-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c474_receipts.txt) 2>&1
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
echo "===POLLCENSUS474=== did the poll family dispatch / players fire / sentinel appear (the preserved c470 log)"
for TAG in "800769A4" "80076AE0" "8003569C" "padin" "skipgate" "sgarm" "sgdecline" "mpad" "452DAAEE" "0x80077014" "0x80077028" "773AC"; do
  C=$(grep -c -e "$TAG" "$LOG" | tr -d " ")
  echo "$TAG: $C"
done
echo "--- first/last skip-poll receipts:"
grep -n -e "800769A4" "$LOG" | head -3
grep -n -e "800769A4" "$LOG" | tail -3
echo "--- first/last padin receipts:"
grep -n -e "padin" "$LOG" | head -4
grep -n -e "padin" "$LOG" | tail -4
echo "--- skipgate/mpad receipts (head 6):"
grep -n -e "skipgate" -e "mpad" "$LOG" | head -6
echo "===MOVIESTATE474=== g_movie_live writers + g_press_state writers (current tree)"
grep -n -e "g_movie_live =" "$SRC" | head -10
grep -n -e "g_movie_live=" "$SRC" | head -10
echo "--- g_press_state writes:"
grep -n -e "g_press_state = " "$SRC" | head -12
echo "===R373REGION474=== the menu-era virtual player shape (context)"
LN=$(grep -n -e "R373 MENU-ERA VIRTUAL PLAYER" "$SRC" | head -1 | cut -d: -f1)
echo "R373 region at line $LN"
if [ -n "$LN" ]; then sed -n "${LN},$((LN+40))p" "$SRC" | head -42; fi
echo "===BTNREFS474=== button cells + gate refs"
grep -n -e "0x800773AC" "$SRC" | head -8
grep -n -e "0x800773B4" "$SRC" | head -8
grep -n -e "0x80077028" "$SRC" | head -8
echo "===C474DONE=== the poll census + movie-state gates are in - the c475 fix follows from these only"
