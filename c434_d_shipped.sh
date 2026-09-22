#!/bin/bash
# c434_servearm.sh - READ-ONLY CENSUS. NO run, NO patch.
# The c433 differential: the boot-2 system-ring walk
# (LBAs 0-9, manufactured serves, dstw0=0, game cells
# advancing) DIED MID-STEP AT LBA 9 - FDF8 re-armed,
# site-5 INT1 armed+acked ONCE (vs 5 acks per LBA
# 7/8), no DATA HANDLER dispatch, no FE04 advance.
# TWO SUSPECTS with exact coincidences: (a) FDE4 hit
# 0xF=15 at exactly LBA 9 (walks LBA+6) - a 16-entry
# or 0xF gate; (b) total site-5 fires ~46 - a 48
# budget. THIS PASS: (1) the FDE4 cell's readers in
# the source (any 0xF/16 cap); (2) the site-5 stamp
# call sites + their gates/budgets; (3) the zrf/cdf
# serve machinery gates; (4) the FDE4 full walk in the
# log; (5) pump-alive receipts at the park (the
# recursive-pump ruleout); (6) the probe cadence at
# the park. Receipts only - the repair follows from
# these only.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C434-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="6c916b3fc08cc29c92247a12aaea6cd4f294e9c395164490e737ab690b782737"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1378 tree - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1378 tree)"
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
echo "===FDE4SRC434=== the FDE4 cell's readers in the source"
grep -n -e "0x8004FDE4" "$SRC" | head -14
echo "--- context of the first 2 refs (+18 each):"
for LN in $(grep -n -e "0x8004FDE4" "$SRC" | head -2 | cut -d: -f1); do
  echo "--- ref at line $LN:"
  awk -v s="$LN" -v e=$((LN+18)) 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
done
echo "===STAMP5SRC434=== the site-5 stamp call sites + gates"
grep -n -e "cd_pending_stamp(1u, 5u)" "$SRC" | head -6
echo "--- context of first site-5 arm (+30):"
LN=$(grep -n -e "cd_pending_stamp(1u, 5u)" "$SRC" | head -1 | cut -d: -f1)
if [ -n "$LN" ]; then
  awk -v s=$((LN-24)) -v e=$((LN+8)) 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
fi
echo "===FDE4LOG434=== the FDE4 full walk in the log"
grep -n -e "FDE4" "$LOG" | head -26
echo "===ZRF434=== the zrf/cdf serve machinery"
grep -c -e "zrf" "$SRC"
grep -n -e "zrf" "$SRC" | head -18
echo "--- zrf log receipts walk-era:"
grep -n -e "zrf" "$LOG" | awk -F: '$1 > 31000' | head -8
echo "--- cdf log receipts walk-era:"
grep -n -e "cdf" "$LOG" | awk -F: '$1 > 31000' | head -8
echo "===PUMPALIVE434=== the recursive-pump ruleout at the park"
grep -n -e "hkick" "$LOG" | tail -4
grep -n -e "alarmguard" "$LOG" | tail -4
echo "--- probe cadence at the park:"
grep -n -e "bp] probe" "$LOG" | awk -F: '$1 > 31900' | head -6
echo "===C434DONE=== the serve arm's gate is receipted - the repair follows from these receipts only"
