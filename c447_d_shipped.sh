#!/bin/bash
# c447_tailera.sh - READ-ONLY TAIL-ERA CENSUS on the
# R1380 run.log (tree 2c660613 verified). NO run, NO
# patch, NO build. The c446 verdict: R1380 PASS - the
# treadmill is GONE (zero site-5 cmd=06 receipts), the
# serve machinery alive in late epochs (READ ISSUED +
# sector serves after 20000), file#15 (LBA 108995,
# blocked since c239) SERVED at 31790, the kernel menu
# rendered late, no crash, fuse-only death. NEW
# FRONTIER: the final era sits at cur_fn=800465EC with
# hw-mangle drops at 8007B52A (r31=8001A52C, val 0311,
# 'chain preserved') + deferred alarm drains. THIS
# PASS: (1) the file#14 re-request + file#15 serve
# contexts (raw windows); (2) the movie-era receipts
# (mdec/mvdoor/mvloop - did the movie sequence
# start?); (3) the mangleguard pattern (count + all
# distinct shapes); (4) the final-loop anatomy (the
# cur_fn census of the last era + the raw tail); (5)
# the R1376/R1380 verification receipts; (6) the
# walk/menu/mod6 receipts this run. Receipts only -
# the next fix follows from these only.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C447-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="2c660613e608e9f878833ece08dcb579a4f431b11c7c4e411323db2c5633f6f2"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1380 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the R1380 tree)"
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
echo "===F14CTX447=== the file#14 re-request context (raw window around 31409)"
awk 'NR>=31384 && NR<=31434 { print NR": "$0 }' "$LOG"
echo "===F15CTX447=== the file#15 (LBA 108995) serve context (raw window around 31790)"
awk 'NR>=31760 && NR<=31812 { print NR": "$0 }' "$LOG"
echo "===MV447=== the movie-era receipts (did the movie sequence start?)"
grep -n -e "mdec" "$LOG" | tail -6
grep -n -e "mvdoor" "$LOG" | tail -4
grep -n -e "mvloop" "$LOG" | tail -4
echo "===MANGLE447=== the mangleguard pattern (count + distinct shapes)"
grep -c -e "mangleguard" "$LOG"
grep -e "mangleguard" "$LOG" | sed 's/.*hw mangle/hw mangle/' | sort | uniq -c | sort -rn | head -6
echo "===FINALLOOP447=== the final-era loop anatomy"
echo "--- cur_fn census of the last 800 lines:"
awk 'NR>=31200' "$LOG" | grep -o "cur_fn=[0-9A-F]*" | sort | uniq -c | sort -rn | head -8
echo "--- the raw tail (last 45 lines):"
tail -45 "$LOG"
echo "===GUARD447=== the R1376/R1380 verification receipts"
grep -n -e "R1376" "$LOG" | head -10
C=$(grep -c -e "site=5 cmd=06 LBA=108933" "$LOG")
echo "treadmill receipts (expect 0): $C"
echo "===WALK447=== walk/menu/mod6 receipts this run"
grep -n -e "FE04 00000009->" "$LOG" | head -3
grep -n -e "MODULE 6 ENTRY" "$LOG" | head -3
grep -n -e "fvp" "$LOG" | tail -6
echo "===DEATH447=== death receipts"
grep -c -e "SIGSEGV\|BadVAddr\|TRUE DEATH" "$LOG"
grep -n -e "rungasp" "$LOG" | tail -2
echo "===C447DONE=== the tail-era anatomy is receipted - the next fix follows from these receipts only"
