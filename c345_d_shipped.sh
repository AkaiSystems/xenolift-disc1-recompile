#!/bin/bash
# c345_pause2probe.sh - READ-ONLY probe of the ACTUAL R1358 tree
# code. NO patch, NO rerun. The c344 receipts: the PAUSE's INT2
# second response never armed and cd_read_active stayed 1, so
# the fd layer never saw request-done and the stepper never
# issued the f15 read.
# THIS CYCLE: dump the R1314 PAUSE retire site, the R124 INT2
# arm gate terms, every cd_read_active=0 site, and the arm's
# trigger path - so the fix ships against real code.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C345-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="37a3790a5e6d5e2daebddc6cb9dc67d6bc264bcdff459198f487b30803d5b92a"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1358 tree - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1358 tree)"
echo "===R1314SITE=== the PAUSE retire site (context 1955-2010)"
sed -n '1955,2010p' "$SRC"
echo "===R124ARM=== the INT2 arm site (context 2320-2385)"
sed -n '2320,2385p' "$SRC"
echo "===READACT=== every cd_read_active clear site with context"
grep -n "cd_read_active = 0" "$SRC"
echo "--- context around each clear site ---"
for L in $(grep -n "cd_read_active = 0" "$SRC" | cut -d: -f1); do
  S=$((L-6)); E=$((L+4))
  echo "--- site at line $L ---"
  sed -n "${S},${E}p" "$SRC"
done
echo "===ARMTRIGGER=== how the INT2 arm is reached (the ack path)"
grep -n "cd_pending_stamp(2u, 2u)" "$SRC"
for L in $(grep -n "cd_pending_stamp(2u, 2u)" "$SRC" | cut -d: -f1); do
  S=$((L-16)); E=$((L+2))
  echo "--- arm at line $L (preceding gate) ---"
  sed -n "${S},${E}p" "$SRC"
done
echo "===SCHEDARM=== the sched arm site at 2232 (context 2200-2245)"
sed -n '2200,2245p' "$SRC"
echo "===RETIREFIRES=== the R1314/R1315 receipts in the whole c343 witness log"
WD="witness_c343_20260917_130210"
LOG="$WD/run.log"
[ -s "$LOG" ] || LOG="$WD/run.log.d"
if [ -s "$LOG" ]; then
  grep -n "R1314\|R1315\|Pause complete" "$LOG" | head -20
  echo "--- any INT2 arm receipts at all (whole log) ---"
  grep -c "Pause complete: INT2" "$LOG"
else
  echo "WITNESS-LOG-MISSING (log sections skipped)"
fi
echo "===C345DONE=== probe complete - the fix design now has the real code"
