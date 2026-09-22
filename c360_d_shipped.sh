#!/bin/bash
# c360_pairpath.sh - READ-ONLY: (a) mine the c358 witness for
# what still runs in the 800286CC park (frame-boundary hkick,
# A22C=2 writer, [cd] wait-loop), (b) extract the genuine-
# answer pair machinery verbatim - the [wgen] R1351 dispatch
# site, [wpair], and the g_r1350_conv_refill conversion pass -
# to see what invokes the pair dispatch. NO patch, NO run.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C360-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="2a9235b6bf9480e309fd14ccfea09189ae7175b8360aef2fc032c29f8cb6e238"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1363 tree - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1363 tree)"
WD="witness_c358_20260917_141050"
LOG="$WD/run.log"
[ -s "$LOG" ] || LOG="$WD/run.log.d"
if [ ! -s "$LOG" ]; then echo "WITNESS-MISSING: the c358 witness is not on disk"; exit 0; fi
echo "WITNESS=$WD LOG=$LOG SIZE=$(wc -l < "$LOG" | tr -d ' ') lines"
echo "===HKICK360=== the frame-boundary tick census in the park (9510-12000 boot 1, 19700-22000 boot 2)"
awk -F: '$1>=9510 && $1<=12000' "$LOG" | grep -c "hkick"
awk -F: '$1>=19700 && $1<=22000' "$LOG" | grep -c "hkick"
grep -n "hkick" "$LOG" | awk -F: '$1>=9510' | head -6
echo "===A22C360=== who writes A22C=2 in the park"
grep -n "8005678C\|A22C.*-> 00000002\|chg.*A22C" "$LOG" | awk -F: '$1>=9510 && $1<=13000' | head -8
echo "===CDWAIT360=== the [cd] wait-loop receipts in the park"
grep -n "wait-loop tick" "$LOG" | awk -F: '$1>=9510' | head -6
grep -n "wait-loop tick" "$LOG" | awk -F: '$1>=9510' | wc -l
echo "===WAITBR360=== the LegacyCdDataWait returns in the park"
grep -n "waitbr" "$LOG" | awk -F: '$1>=9510' | head -4
echo "===TRAIL360=== the trail census (all parks receipted)"
grep -n "trail. R642" "$LOG" | head -10
echo "===WGENCODE360=== the [wgen] dispatch site - plus/minus 30 lines"
LG=$(grep -n "wgen. R1351 genuine-answer" "$SRC" | head -1 | cut -d: -f1)
echo "WGEN_LINE=$LG"
if [ -n "$LG" ]; then
  S=$((LG-30)); [ $S -lt 1 ] && S=1
  E=$((LG+30))
  awk -v s="$S" -v e="$E" 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
else
  echo "WGEN SITE NOT FOUND"
fi
echo "===WPAIRCODE360=== the [wpair] site - plus/minus 20 lines"
LP=$(grep -n "wpair" "$SRC" | head -1 | cut -d: -f1)
echo "WPAIR_LINE=$LP"
if [ -n "$LP" ]; then
  S=$((LP-20)); [ $S -lt 1 ] && S=1
  E=$((LP+20))
  awk -v s="$S" -v e="$E" 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
fi
echo "===CONVPASS360=== the g_r1350_conv_refill occurrences with context"
grep -n -B6 -A6 "g_r1350_conv_refill" "$SRC"
echo "===C360DONE=== the pair-dispatch invocation story is extracted"
