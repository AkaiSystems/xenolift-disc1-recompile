#!/bin/bash
# c361_fdtick.sh - READ-ONLY: (a) census the c358 witness for
# the fd-tick conversion receipts (does the conversion block
# run in the 800286CC park era?), the R1341 sibling-discard
# receipts (did it eat the primed pending after the serve?),
# and the R1345 stalecd-near change-prints (pend oscillation
# after 9527); (b) extract the conversion block's ENCLOSING
# function from runtime.c (lines ~21900-22060 + the function
# header above) to learn which tick hosts it. NO patch, NO run.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C361-FAILED: xenolift dir missing"; exit 1; }
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
echo "WITNESS_LINECOUNT=$(wc -l < "$LOG" | tr -d ' ') lines"
echo "===FDTICK361=== the conversion receipts (whole-run census + timestamps)"
grep -c "fd-tick" "$LOG"
grep -n "fd-tick" "$LOG" | head -12
grep -n "fd-tick" "$LOG" | tail -4
echo "===R1341DISC361=== the sibling discard receipts (did it eat the primed pending?)"
grep -c "stalecd] R1341" "$LOG"
grep -n "stalecd] R1341" "$LOG" | head -12
echo "===NEAR361=== the R1345 change-prints after the serve (pend oscillation, 9527+)"
grep -n "stalecd-near" "$LOG" | awk -F: '$1>=9527' | head -10
grep -n "stalecd-near" "$LOG" | awk -F: '$1>=9527' | wc -l
echo "===STALECDALL361=== every stalecd receipt after the serve (9527+) - which discards fired?"
grep -n "stalecd" "$LOG" | awk -F: '$1>=9527' | head -14
echo "===WOPFLAGPERSIST361=== the op flag story - any clears after the serve?"
grep -n "op flag" "$LOG" | awk -F: '$1>=9527' | head -8
echo "===CONVFUNC361=== the conversion block's enclosing function (lines 21870-22058)"
awk 'NR>=21870 && NR<=22058 { print NR": "$0 }' "$SRC"
echo "===C361DONE=== the fd-tick story is receipted"
