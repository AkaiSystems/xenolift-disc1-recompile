#!/bin/bash
# c359_collectormine.sh - READ-ONLY mining of the c358 witness.
# NO patch, NO run. The R1363 fix landed: the watcher serve now
# fires (prime + op flag SET + conv refill, 9525-9527) but the
# collector never runs ([wgen]=0, [cdcol]=0) and the kernel
# never consumes. HYPOTHESIS: the flag-check fns (8004B894/
# 8004293C) that run the collector do not cycle in this era's
# movie-poll spin. THIS PASS: the op flag's persistence/clears,
# the flag-check fn entries, pendclr, getintr dispatches, and
# the movie-poll fn census after the serve.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C359-FAILED: xenolift dir missing"; exit 1; }
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
echo "===OPFLAG359=== the op flag cell 0x800578A6 - every mention"
grep -n "800578A6\|78A6" "$LOG" | head -12
echo "===FLAGCHECK359=== the flag-check fns (8004B894/8004293C) - entries in the run"
grep -n "8004B894\|8004293C\|B894\|4293C" "$LOG" | head -12
echo "===PENDCLR359=== the pendclr receipts after the serve (9500+)"
grep -n "pendclr" "$LOG" | awk -F: '$1>=9500' | head -12
echo "--- whole-run pendclr census ---"
grep -c "pendclr" "$LOG"
echo "===GETINTR359=== the getintr dispatch fn (800415B4) - dispatches"
grep -n "415B4\|getintr" "$LOG" | head -12
echo "===CONSUME359=== the consumption receipts (the c334-era classes)"
grep -n "response consumed\|interrupt acknowledged" "$LOG" | head -12
echo "===MOVIEWAIT359=== the movie-poll census after the serve"
grep -n "movie-poll alive" "$LOG" | head -4
grep -c "movie-poll alive" "$LOG"
echo "===CURFN359=== the cur_fn census in the park window (what runs after the serve?)"
grep -n "cur_fn" "$LOG" | awk -F: '$1>=9500 && $1<=11000' | head -14
echo "===FE1CLATE359=== the FE1C walk after the serve (9525+)"
grep -n "chg. FE1C" "$LOG" | awk -F: '$1>=9525' | head -10
echo "===WPUMP359=== the tick/pump receipts after the serve"
grep -n "wconv\|conv_refill" "$LOG" | head -6
echo "===C359DONE=== the collector-never-runs story is receipted"
