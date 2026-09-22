#!/bin/bash
# c346_delsiteprobe.sh - READ-ONLY probe of the delivery sites.
# NO patch, NO rerun. The c345 receipts: the PAUSE's INT3 sits
# scheduled forever because the delivery trigger (fn 0x8004B894)
# never fires in the movie-module poll era; the R124 INT2 arm
# never acks; cmd 09 never clears cd_read_active.
# THIS CYCLE: the FDFC scheduled-cmd delivery site's gate
# terms, the 0x8004B894 hook, the schdd R1291 delivery gates,
# and the tail's [schdd]/FDFC receipts - so the fix lands in
# the right delivery site.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C346-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="37a3790a5e6d5e2daebddc6cb9dc67d6bc264bcdff459198f487b30803d5b92a"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1358 tree - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1358 tree)"
echo "===FDFCDEL=== the FDFC scheduled-cmd delivery sites (gate terms)"
grep -n "with scheduled cmd" "$SRC"
for L in $(grep -n "with scheduled cmd" "$SRC" | cut -d: -f1); do
  S=$((L-30)); E=$((L+12))
  echo "--- delivery site at line $L (gate context) ---"
  sed -n "${S},${E}p" "$SRC"
done
echo "===EVTFLAG=== the fn 0x8004B894 event-flag hook"
grep -n "8004B894" "$SRC" | head -8
for L in $(grep -n "0x8004B894" "$SRC" | head -3 | cut -d: -f1); do
  S=$((L-10)); E=$((L+30))
  echo "--- hook at line $L ---"
  sed -n "${S},${E}p" "$SRC"
done
echo "===SCHDD=== the R1291 delivery-decision gates"
grep -n "schdd\] delivery decision\|delivery decision BLOCKED" "$SRC" | head -6
for L in $(grep -n "delivery decision" "$SRC" | head -2 | cut -d: -f1); do
  S=$((L-40)); E=$((L+6))
  echo "--- decision site at line $L (the gate ladder above) ---"
  sed -n "${S},${E}p" "$SRC"
done
echo "===CMD09ISSUE=== the cmd 09 issue path (the SCHEDARM site context 2160-2235)"
sed -n '2160,2235p' "$SRC"
echo "===LOGTAIL=== the tail schdd/FDFC/delivery receipts from the c343 witness"
WD="witness_c343_20260917_130210"
LOG="$WD/run.log"
[ -s "$LOG" ] || LOG="$WD/run.log.d"
if [ -s "$LOG" ]; then
  echo "--- schdd receipts after line 30129 ---"
  awk 'NR>=30129' "$LOG" | grep -n "schdd" | head -10
  echo "--- FDFC=1 receipts after line 30129 ---"
  awk 'NR>=30129' "$LOG" | grep -n "FDFC" | head -8
  echo "--- delivered receipts after line 30129 ---"
  awk 'NR>=30129' "$LOG" | grep -n "delivered" | head -8
else
  echo "WITNESS-LOG-MISSING (log sections skipped)"
fi
echo "===C346DONE=== probe complete - the delivery-site gates are now receipted"
