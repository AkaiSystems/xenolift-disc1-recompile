#!/bin/bash
# c400_r260.sh - READ-ONLY CENSUS. NO run, NO patch. The
# c399 verdict: the mount COMPLETED, file#18 streamed fully
# native (FDF8 14360 drained chunk-by-chunk), MDEC engaged
# (3 resets), and the game now polls pre-movie at FE1C=1
# with last_cmd=02 (Setloc 109166), sched=1, pend=0, FDF8=0,
# A22C=2 - the Setloc INT3 ARMED BUT UNDELIVERED at the
# movie-loop contexts (the c206/c208 class, movie variant).
# The tree already holds the cure PATTERN: R258 (the mvloop
# context-independent INT1 delivery every 256 passes) and
# R260 (the scheduled INT3 delivery). THIS PASS: (1) the
# full R258/R260 site (lines ~19940-20060: the complete
# comments + gate terms); (2) the schdd R1291 receipts at
# the end window (who declines the cmd-02 Setloc delivery);
# (3) the actchg/finstamp chain for the Setloc 109166; (4)
# the waitbr/fdw receipts at the final spin; (5) the
# cd_force_deliver_int1 / scheduled-delivery function
# bodies. The R1373 widen follows mechanically.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C400-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="6342434936dcbdbd45e922cc05a72f3ab159225b87cd0d78d2e7ddaf3751d0a6"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1372 tree - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1372 tree)"
echo "===R260SITE400=== the R258/R260 delivery site (lines 19940-20070)"
awk 'NR>=19940 && NR<=20070 { print NR": "$0 }' "$SRC" | grep -v "^\s*$" | head -85
echo "===FORCEDEL400=== the cd_force_deliver_int1 body + its callers"
LG=$(grep -n "cd_force_deliver_int1" "$SRC" | head -8)
echo "$LG"
LG1=$(grep -n "static.*cd_force_deliver_int1\|void cd_force_deliver_int1" "$SRC" | head -1 | cut -d: -f1)
if [ -n "$LG1" ]; then
  awk -v s="$LG1" -v e=$((LG1+45)) 'NR>=s && NR<=e { print NR": "$0 }' "$SRC" | grep -v "^\s*[0-9]*: \*" | head -40
fi
echo "===SCHDD400=== the schdd delivery decisions at the end window (run.log 31000+)"
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
if [ -s "$LOG" ]; then
  grep -n "schdd\]" "$LOG" | awk -F: '$1>=31000' | head -12
  echo "===ACTCHG400=== the actchg/finstamp chain for the Setloc 109166"
  grep -n "finstamp\|actchg" "$LOG" | awk -F: '$1>=31000' | head -14
  echo "===WAITBR400=== the LegacyCdDataWait returns at the final spin"
  grep -n "waitbr\]" "$LOG" | awk -F: '$1>=31500' | head -8
  echo "===FSENT400=== the R1365 field-spin entries at the end"
  grep -n "fsent\]" "$LOG" | awk -F: '$1>=31000' | head -6
else
  echo "LOG-MISSING"
fi
echo "===C400DONE=== the R260 delivery anatomy is receipted"
