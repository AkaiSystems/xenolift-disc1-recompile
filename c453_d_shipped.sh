#!/bin/bash
# c453_runonly.sh - RUN-ONLY CYCLE on the landed R1381
# tree (8303add5 verified first). NO patch, NO build:
# the binary xenogears_boot_210756 was built from this
# exact tree at 21:07 (c452 receipts) - run.sh reuses
# it. The c452 verdict: R1381 landed but never fired -
# the f15 park posture never materialized in the 90s
# window (the game's epoch ended earlier: file#18 tail
# drained ~31376, file#14 RE-ISSUED at 31808, fuse at
# 31996) - receipted epoch pacing jitter, not a gate
# defect. THIS PASS: RUN_BUDGET_S=150 gives the park +
# the R1381 10s freeze + R1298's 30s confirm room.
# NEVER-TWICE (c451): the receipt trail tees to
# /tmp/c453_receipts.txt AS IT RUNS so a watchdog kill
# can never erase progress evidence. PASS = [f15arm]
# fire + R1298 start + FDF8 92180 drains + FE08 walks +
# dstw0!=0 + forward execution. REVERT = fire with no
# consumption.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C453-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c453_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="8303add53da667af6f70a63ea433c12a8c59377fc87ec57eb4b50d0a461a4b29"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1381 tree 8303add5 - refusing to run"; exit 0; fi
echo "TREE_VERIFIED (the R1381 tree - the arm is in place)"
C0=$(grep -c -e "f15arm" "$SRC")
echo "f15arm marker: $C0 (expect 1)"
if [ "$C0" != "1" ]; then echo "GATE-FAILED: marker missing"; exit 0; fi
echo "===RUN453=== run-only (RUN_BUDGET_S=150, no build)"
RUN_BUDGET_S=150 ./run.sh run > /tmp/run_full_c453.txt 2>&1
echo "RUN_RC=$?"
LOG="run.log"
echo "===DIGEST453==="
echo "--- THE ARM: [f15arm] receipts:"
grep -n -e "f15arm" "$LOG"
echo "--- THE START: R1298 receipts:"
grep -n -e "R1298" "$LOG" | head -6
echo "--- THE PARK: FE04 at the f15 LBA:"
grep -n -e "seek=108995" "$LOG" | tail -6
echo "--- THE STREAM: sectors at the file-15 band + FDF8 countdown:"
grep -n -e "sector LBA 10899" "$LOG" | tail -6
grep -n -e "req] FDF8" "$LOG" | tail -6
echo "--- ring walk + delivery:"
grep -n -e "FE08 8007F" "$LOG" | tail -4
grep -e "DATA HANDLER enter" "$LOG" | tail -3
echo "--- forward execution:"
grep -n -e "MODULE 6 ENTRY" "$LOG" | tail -2
grep -n -e "fvp" "$LOG" | tail -3
grep -n -e "READ ISSUED" "$LOG" | tail -3
echo "--- death receipts:"
grep -n -e "rungasp" "$LOG" | tail -2
echo "--- tree sha:"
echo "expected=8303add53da667af6f70a63ea433c12a8c59377fc87ec57eb4b50d0a461a4b29"
shasum -a 256 "$SRC" | cut -d" " -f1
echo "===PRESERVE453=== c118 protocol"
D=$(mktemp -d "$PWD/c453_snap.XXXXXX") || { echo "SNAPSHOT-DIR-FAILED"; exit 0; }
cp -p run.log "$D/run.log" && CP1=0 || CP1=1
cp -p /tmp/run_full_c453.txt "$D/run_full_c453.txt" && CP2=0 || CP2=1
cp -p /tmp/c453_receipts.txt "$D/c453_receipts.txt" && CP3=0 || CP3=1
echo "cp_rcs: $CP1 $CP2 $CP3"
ls -la "$D"
shasum -a 256 "$D/run.log" "$D/run_full_c453.txt"
tail -8 "$D/run_full_c453.txt"
echo "===C453DONE=== the 150s run receipted - PASS/REVERT from the digest receipts"
