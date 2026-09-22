#!/bin/bash
# c443_treadmill.sh - READ-ONLY TREADMILL ANATOMY on the
# preserved R1379 run.log (tree c9e85ea1 verified). NO
# run, NO patch, NO build. The c442 verdict: R1379 PASS
# (both discards true-stale FDF8==0; the walk COMPLETED
# 0->9 and graduated to the file-table band at fn
# 0x800288EC; no guest crash in 90s). NEW BLOCKER: the
# file#14 ReadN (cmd=06 LBA=108933 size 125304 dst
# 801DD680) arm/clear treadmill - pendclr site=5
# clears=125-160+ all @t=2s, NO sector serve for 108933.
# Prior proof: cmd=07 seek=108972 DID get a real serve.
# Suspect: the ReadN posture (seek=108933, sched=1,
# act=0) sits outside the serve doors' arming scope.
# THIS PASS: (1) the treadmill START context (the
# receipts before the first site=5 cmd=06 clear); (2)
# the scheduler's delivery decisions (schdd tail);
# (3) the FDF8 arm-contexts (fdw tail); (4) the last
# REAL serves + cd_data_load; (5) the zrfm/R537
# lazy-advance receipts (the file-14 serve family);
# (6) the frozen-state cameras (mod6/parkcam/mvloop).
# Receipts only - the fix follows from these only.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C443-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="c9e85ea1d9c6ebfd9145cc948dffd37826385f58bd947267ec37b0d39c34b5fb"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1379 tree - refusing (harvest must match the tree that made the log)"; exit 0; fi
echo "TREE_VERIFIED (the R1379 tree)"
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
echo "===TREADMILL443=== the treadmill START (context before the first site=5 cmd=06 LBA=108933 clear)"
grep -n -e "site=5 cmd=06 LBA=108933" "$LOG" | head -3
LN=$(grep -n -e "site=5 cmd=06 LBA=108933" "$LOG" | head -1 | cut -d: -f1)
if [ -n "$LN" ]; then
  echo "--- raw window ($((LN-34))..$((LN+2))):"
  awk -v s=$((LN-34)) -v e=$((LN+2)) 'NR>=s && NR<=e { print NR": "$0 }' "$LOG"
fi
echo "===SCHDD443=== the scheduler's delivery decisions (tail)"
grep -n -e "schdd" "$LOG" | tail -10
echo "===FDW443=== the FDF8 arm-contexts (tail)"
grep -n -e "fdw" "$LOG" | tail -8
echo "===SERVE443=== the last REAL serves + data loads"
grep -n -e "sector LBA" "$LOG" | tail -6
grep -n -e "cd_data_load" "$LOG" | tail -4
echo "===ZRFM443=== the file-14 lazy-advance family receipts"
grep -n -e "zrfm\|R537\|lazy-advance" "$LOG" | tail -8
echo "===STATE443=== the frozen-state cameras (tail)"
grep -n -e "mod6" "$LOG" | tail -4
grep -n -e "parkcam" "$LOG" | tail -4
grep -n -e "mvloop" "$LOG" | tail -4
echo "===C443DONE=== the treadmill anatomy is receipted - the serve-door fix follows from these receipts only"
