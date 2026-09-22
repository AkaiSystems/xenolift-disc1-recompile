#!/bin/bash
# c476_extract.sh - READ-ONLY CENSUS, NO RUN, NO BUILD,
# NO PATCH. The c475 receipts: the park = a stable
# 97-fn NO-PHASE loop (font + ReadControllerButtons +
# SPU + event dispatchers; zero phase callbacks) - the
# Field coordinator 80077E88 NEVER DISPATCHES while
# the mount cells read LIVE again at the park. The
# c196-era decode named the blocker class: the
# resident-loop latch 0x80059330=0 and an invalid
# game-state cell block the state-1 init path.
# RECEIPTS: (1) PHASECB: did any phase ever enter this
# run; (2) CNTDN: the countdown transitions; (3)
# STATECELL: the resident-loop/state-machine receipts;
# (4) WALKER: the fldfrz2 evolution at the park; (5)
# MOUNT: the mount/teardown timeline; (6) TREE: the
# resident-loop cameras in the current tree.
# Fail-closed, tee'd to /tmp/c476_receipts.txt.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C476-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c476_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="d86f3deb57aed5b0921ab3a82867dea3a1e1d9960028e360bed8d9bdc90d45f8"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the R1387 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the R1387 tree)"
LOG="run.log"
if [ ! -s "$LOG" ]; then LOG="run.log.d"; fi
if [ ! -s "$LOG" ]; then echo "GATE-FAILED: no preserved run log"; exit 0; fi
echo "LOG=$LOG ($(wc -l < "$LOG" | tr -d " ") lines)"
echo "===PHASECB476=== did any phase ever enter (the R149 watcher receipts)"
grep -c -e "phasecb" "$LOG" | tr -d " " | sed "s/^/phasecb lines: /"
grep -n -e "phasecb" "$LOG" | head -10
echo "===CNTDN476=== the countdown transitions (the R325 camera)"
grep -c -e "cntdn" "$LOG" | tr -d " " | sed "s/^/cntdn lines: /"
grep -n -e "\[cntdn\]" "$LOG" | head -8
echo "===STATECELL476=== the resident-loop / state-machine receipts"
grep -n -e "59330" "$LOG" | head -10
grep -n -e "18088" "$LOG" | head -8
grep -n -e "statestamp" "$LOG" | head -6
grep -n -e "rlgl" "$LOG" | head -6
echo "===WALKER476=== the fldfrz2 evolution (tail)"
grep -c -e "fldfrz2" "$LOG" | tr -d " " | sed "s/^/fldfrz2 lines: /"
grep -n -e "fldfrz2" "$LOG" | tail -6
echo "===MOUNT476=== the mount/teardown timeline"
grep -n -e "mcw" "$LOG" | head -14
echo "===TREE476=== the resident-loop cameras in the current tree"
grep -n -e "rlgl" "$SRC" | head -6
grep -n -e "0x80059330" "$SRC" | head -12
grep -n -e "0x80018088" "$SRC" | head -8
grep -n -e "0x80077E88" "$SRC" | head -8
echo "===C476DONE=== the phase/state receipts are in - the c477 fix follows from these only"
