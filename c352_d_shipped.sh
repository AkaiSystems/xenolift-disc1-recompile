#!/bin/bash
# c352_witnessmine.sh - READ-ONLY mining of the preserved c351
# witness. NO patch, NO run. The c351 receipts: the R1360 clear
# converted the infinite wedge into a FINITE COURSE (two boots,
# clean exit-0 each), but READ ISSUED file#15 never fires and
# main returns instead of entering the menu loop. THIS CYCLE:
# name WHY main returns and why the f15 pop never happens -
# the exit-0 context, the resident-loop latch/state census, the
# f15 request lifecycle, and the mount accessor chain.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C352-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="14bd5f5d96d4b0f33beb05be6ed8d490d71735912b5b8f3949d6bc57682061ea"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1360 tree - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1360 tree)"
WD="witness_c351_20260917_134012"
LOG="$WD/run.log"
[ -s "$LOG" ] || LOG="$WD/run.log.d"
if [ ! -s "$LOG" ]; then echo "WITNESS-MISSING: the c351 witness is not on disk - nothing to mine"; exit 0; fi
echo "WITNESS=$WD LOG=$LOG SIZE=$(wc -l < "$LOG" | tr -d ' ') lines"
echo "===EXITCTX352=== the context before each clean main-return (the last receipts)"
for E in $(grep -n "rungasp.*exit status=0" "$LOG" | cut -d: -f1); do
  echo "--- exit context at line $E (the 30 lines before) ---"
  S=$((E-30)); [ $S -lt 1 ] && S=1
  awk -v s="$S" -v e="$((E-1))" 'NR>=s && NR<=e' "$LOG"
done
echo "===STATECENSUS352=== the resident-loop state census (latch, g_CurGameState, statetbl)"
grep -n "latchhw\|rlgl\|statetbl\|CurGameState\|STATE-1\|state-1" "$LOG" | tail -14
grep -n "latch(92BC)" "$LOG" | tail -6
echo "===F15LIFE352=== the f15 request lifecycle (why the pop never happens)"
grep -n "file#=15\|file#15\|F0C=15\|108995" "$LOG" | head -16
echo "--- the fd queue node receipts (59F10) late-run ---"
grep -n "59F10" "$LOG" | tail -8
echo "--- the fd processor / queue posture receipts late-run ---"
grep -n "rsdump\|park\|fd processor" "$LOG" | tail -10
echo "===MOUNTCHAIN352=== the mount accessor chain (mntacc/mtrans/coordinator)"
grep -n "mntacc\|mtrans\|coordinator\|gdisp" "$LOG" | tail -12
echo "===RETURNPATH352=== the main-return chain (who returns, from where)"
grep -n "main-return\|main return\|bootmain\|real_main\|restart" "$LOG" | tail -12
echo "===ABORT352=== the abort census (130/131 chains)"
grep -c "abort" "$LOG"
grep -n "abort-1[03][01]\|Abort 1[03][01]\|abort(1[03][01]" "$LOG" | head -6
echo "===TAILSTATE352=== the last 25 receipts of the run"
tail -25 "$LOG"
echo "===C352DONE=== the witness is mined - the main-return story is receipted"
