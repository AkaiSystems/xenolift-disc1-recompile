#!/bin/bash
# c344_f15probe.sh - READ-ONLY probe of the EXISTING c343
# witness. NO patch, NO rerun. The R1358 fix is reproducible;
# the game reached the f15 era (request stamped, FE04=108995
# FDF8=92180) but READ ISSUED file#15 never fired; the kernel
# sits at last_cmd=09, pend=1, sched=1, resp_n=1, FE1C=0.
# THIS CYCLE: (1) the 785 lines between cmdtl #12 (30129) and
# the stamp (30914); (2) the pause-INT2 machinery; (3) the
# stepper context; (4) the sched=1 identity; (5) the 801Cxxxx
# family census; (6) the A22C=2 writer.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C344-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="37a3790a5e6d5e2daebddc6cb9dc67d6bc264bcdff459198f487b30803d5b92a"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1358 tree - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1358 tree)"
WD="witness_c343_20260917_130210"
LOG="$WD/run.log"
[ -s "$LOG" ] || LOG="$WD/run.log.d"
if [ ! -s "$LOG" ]; then echo "PROBE-FAILED: witness log missing - nothing to probe"; exit 0; fi
echo "PROBE_TARGET=$LOG"
echo "===BETWEEN344=== the kernel actions between cmdtl #12 (30129) and the f15 stamp (30914)"
awk 'NR>=30129 && NR<=30914' "$LOG" | grep -v "wait-loop tick" | awk 'NR%8==1' | head -80
echo "===PAUSE2_344=== the pause-INT2 machinery sites in runtime.c"
grep -n "R124\|INT2" "$SRC" | grep -i "pause\|INT2\|second response" | head -20
echo "--- pause-INT2 log receipts after 30129 ---"
awk 'NR>=30129' "$LOG" | grep -n "INT2\|pause\|Pause\|PAUSE" | grep -v "watchdog\|R1314\|R1315" | head -12
echo "===STEPPER344=== the request-stepper receipts in the f15 era"
awk 'NR>=30129' "$LOG" | grep -n "ftab\|mtrans\|mntacc\|READ ISSUED\|schdd\|reqcell\|file#" | head -20
echo "===SCHED344=== the sched=1 identity (scheduled response class)"
awk 'NR>=30129' "$LOG" | grep -n "cdstate\|park\]\|rspop\|pendclr\|penddossier" | head -16
echo "--- sched arm sites for cmd 09 in runtime.c ---"
grep -n "cd_scheduled = 1" "$SRC" | head -10
echo "===MVFAM344=== the 801Cxxxx family census (dispatcher vs spin)"
awk 'NR>=30914' "$LOG" | grep -o "loop-id fn=[0-9A-F]*" | sort | uniq -c | sort -rn | head -14
awk 'NR>=30914' "$LOG" | grep -c "mvloop"
echo "===A22C344=== the A22C=2 writer evidence"
awk 'NR>=30129' "$LOG" | grep -n "A22C\|8006A22C" | head -10
echo "--- A22C write sites in runtime.c ---"
grep -n "8006A22C" "$SRC" | head -12
echo "===PAD344=== the pad/press state in the f15 era"
awk 'NR>=30129' "$LOG" | grep -n "pad\|btn\|press" | head -8
echo "===C344DONE=== probe complete - the f15-era missing transition is named by these receipts"
