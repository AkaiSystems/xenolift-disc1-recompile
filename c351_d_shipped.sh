#!/bin/bash
# c351_longrun.sh - READ-ONLY longer run (150s) of the UNCHANGED
# R1360 tree (14bd5f5d). The c350 receipts: the era-gated
# Pause-ends-reading clear unblocked the post-pause fd flow -
# the next request is a READ ARM at LBA 239317 (FDF8=9048,
# deep territory unvisited since c186), then Setloc 108958 +
# file#14. The 120s window ended mid-course. THIS CYCLE: give
# the flow the extra 30s and census the deep-read lifecycle.
# NO patch, NO behavior change.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C351-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="14bd5f5d96d4b0f33beb05be6ed8d490d71735912b5b8f3949d6bc57682061ea"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1360 tree 14bd5f5d - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1360 tree)"
clang -fsyntax-only -std=gnu99 "$SRC" 2>/dev/null; PRC=$?
echo "PARSE_RC=$PRC"
if [ "$PRC" != "0" ]; then echo "PARSE-FAILED - refusing to run"; exit 0; fi
echo "PARSE-OK"
TS=$(date +%Y%m%d_%H%M%S)
echo "===RUN351=== the unchanged R1360 build, 150s budget, first-fault stop"
XENOLIFT_FIRSTFAULT_STOP=1 RUN_BUDGET_S=150 bash run.sh > /tmp/run_full_c351.txt 2>&1; RRC=$?
echo "RUN_RC=$RRC"
WDIR="witness_c351_$TS"; mkdir -p "$WDIR"
for f in run.log run.log.d; do [ -f "$f" ] && cp -p "$f" "$WDIR/$f"; done
cp -p /tmp/run_full_c351.txt "$WDIR/run_full.txt"
echo "WITNESS=$WDIR"
LOG="run.log"; [ -s "$LOG" ] || LOG="run.log.d"
echo "===R1360RECEIPTS351=== the era-gated clear receipts"
grep -n "R1360" "$LOG" | head -8
echo "===CMDTL351=== the full command ladder"
grep -n "cmdtl" "$LOG"
echo "===DEEPREAD351=== the 239317 deep-read lifecycle"
grep -n "239317\|239318\|239324" "$LOG" | head -12
grep -n "FDF8=9048" "$LOG" | head -6
grep -n "sector LBA 239" "$LOG" | head -10
grep -c "sector LBA" "$LOG"
echo "===F15ANDCO351=== f15 + the file ladder + state-1"
grep -n "file#15\|file#=15" "$LOG" | head -6
grep -n "f15 request stamped" "$LOG" | tail -3
grep -n "READ ISSUED" "$LOG" | tail -8
grep -n "mtrans\|STATE-1 ENTRY" "$LOG" | tail -8
echo "===FE1C351=== the FE1C walk (late)"
grep -n "\[chg\] FE1C" "$LOG" | tail -12
echo "===FAULT351=== fault census"
grep -c "computed-garbage" "$LOG"
FF=$(grep -n "computed-garbage address" "$LOG" | head -1 | cut -d: -f1)
echo "FIRST_FAULT_LINE=$FF"
if [ -n "$FF" ]; then awk -v s="$((FF-6))" -v e="$((FF+6))" 'NR>=s && NR<=e' "$LOG"; fi
echo "===VIS351=== exits + gpu census"
grep -n "rungasp" "$LOG" | tail -3
grep -n "gpufin\|gp0_words" "$LOG" | tail -3
grep -n "nonblank" "$LOG" | tail -4
echo "===TAIL351=== the last 12 lines (where the flow stands at cutoff)"
tail -12 "$LOG"
echo "===C351DONE=== the 150s census is receipted"
