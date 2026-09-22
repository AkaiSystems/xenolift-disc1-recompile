#!/bin/bash
# c480_extract.sh - READ-ONLY DECODE, NO RUN, NO BUILD,
# NO PATCH. The c479 verdict: the state machine RAN
# (cur 1 FIELD -> 6 MOVIE -> 0 MENU fallback), the park
# = the kernel menu re-rendering, but the RESIDENT
# LOOP (fn_80019ACC) never ran - the phase dispatch
# engine is cold. The coordinator was written healthy
# then garbage-overwritten by fn 0x80041534. RECEIPTS:
# (1) RESLOOP480: the 0x80031DA8 verdict branch + the
# containing function (who would call the resident
# loop); (2) FALLBACK480: the window 29619-30008 (what
# broke the movie state); (3) GARBAGE480: the 0x80041534
# body (the garbage writer); (4) COORDTAIL480: the
# park-era coordinator writes; (5) LATCH480: the park
# latch values. Fail-closed, tee'd to
# /tmp/c480_receipts.txt.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C480-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c480_receipts.txt) 2>&1
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
echo "===RESLOOP480=== the 0x80031DA8 verdict branch + containing function"
LN=$(grep -n -e "L_80031DA8:" "$D" | head -1 | cut -d: -f1)
echo "L_80031DA8 at disc1.c line $LN"
if [ -n "$LN" ]; then
  awk -v N="$LN" 'NR<=N && /---------- 0x/ {last=NR": "$0} NR==N {print "CONTAINING FN MARKER: "last; exit}' "$D"
  sed -n "$((LN>20 ? LN-20 : 1)),$((LN+30))p" "$D" | head -52
fi
echo "--- who references fn_80019ACC in the emitted source:"
grep -n -e "fn_80019ACC" "$D" | head -8
echo "===FALLBACK480=== the movie-state fallback window (log lines 29619-30008)"
for TAG in "mvloop" "ftab" "fldsec" "cntdn" "mcw" "chaincam" "wedge" "req" "lzss"; do
  C=$(awk 'NR>=29619 && NR<=30008' "$LOG" | grep -c -e "$TAG" | tr -d " ")
  echo "$TAG in window: $C"
done
echo "--- window first 18 lines:"
sed -n "29619,29636p" "$LOG" | head -18
echo "--- window last 18 lines:"
sed -n "29991,30008p" "$LOG" | head -18
echo "===GARBAGE480=== the fn 0x80041534 body (the garbage writer)"
LN=$(grep -n -e "0x80041534 (function)" "$D" | head -1 | cut -d: -f1)
echo "marker at line $LN"
if [ -n "$LN" ]; then sed -n "${LN},$((LN+48))p" "$D" | head -50; fi
echo "===COORDTAIL480=== the park-era coordinator writes (tail)"
grep -n -e "coordw" "$LOG" | tail -10
echo "===LATCH480=== the park-era latch receipts (tail)"
grep -n -e "latchhw" "$LOG" | tail -10
echo "===C480DONE=== the resident-loop caller + fallback window + garbage writer are in - the c481 fix follows from these only"
