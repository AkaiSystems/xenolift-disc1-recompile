#!/bin/bash
# c455_runonly.sh - RUN-ONLY VERDICT CYCLE on the R1382
# tree (77a9b4fc verified first). NO patch, NO build:
# the c454 cycle compiled this exact tree (BUILD OK,
# 21:23) - run.sh reuses the fresh binary. NO RUN in
# c454 (watchdog math), so this cycle is the verdict. The c454 receipts: R1382 (the arm-gate WIDEN) landed + compiled clean -
# the c453 receipts convicted the cmd/pend/sched terms
# (the ARRIVAL posture holds cmd=01/pend=1/sched=1) -
# now removed, freeze 5s. THIS PASS: RUN_BUDGET_S=150
# gives the park + the 5s freeze + R1298's 30s confirm
# room.
# NEVER-TWICE (c451): the receipt trail tees to
# /tmp/c455_receipts.txt AS IT RUNS so a watchdog kill
# can never erase progress evidence. PASS = [f15arm]
# fire + R1298 start + FDF8 92180 drains + FE08 walks +
# dstw0!=0 + forward execution. REVERT = fire with no
# consumption.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C453-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c455_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="77a9b4fc989d9e287ba1149a9f813a6e12b33fe9d3b68bb0a521c256b6442bed"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1382 tree 77a9b4fc - refusing to run"; exit 0; fi
echo "TREE_VERIFIED (the R1382 tree - the widened arm is in place)"
C0=$(grep -c -e "f15arm" "$SRC")
echo "f15arm marker: $C0 (expect 1)"
if [ "$C0" != "1" ]; then echo "GATE-FAILED: marker missing"; exit 0; fi
C1=$(grep -c -e "R1382 (c453)" "$SRC")
echo "R1382 marker: $C1 (expect 1)"
if [ "$C1" != "1" ]; then echo "GATE-FAILED: R1382 marker missing"; exit 0; fi
C2=$(grep -c -e "r1381_since >= 5" "$SRC")
echo "freeze-5s line: $C2 (expect 1)"
if [ "$C2" != "1" ]; then echo "GATE-FAILED: freeze line not the 5s form"; exit 0; fi
echo "===RUN455=== run-only (RUN_BUDGET_S=150, no build)"
RUN_BUDGET_S=150 ./run.sh run > /tmp/run_full_c455.txt 2>&1
echo "RUN_RC=$?"
LOG="run.log"
echo "===DIGEST455==="
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
echo "expected=77a9b4fc989d9e287ba1149a9f813a6e12b33fe9d3b68bb0a521c256b6442bed"
shasum -a 256 "$SRC" | cut -d" " -f1
echo "===PRESERVE455=== c118 protocol"
D=$(mktemp -d "$PWD/c455_snap.XXXXXX") || { echo "SNAPSHOT-DIR-FAILED"; exit 0; }
cp -p run.log "$D/run.log" && CP1=0 || CP1=1
cp -p /tmp/run_full_c455.txt "$D/run_full_c455.txt" && CP2=0 || CP2=1
cp -p /tmp/c455_receipts.txt "$D/c455_receipts.txt" && CP3=0 || CP3=1
echo "cp_rcs: $CP1 $CP2 $CP3"
ls -la "$D"
shasum -a 256 "$D/run.log" "$D/run_full_c455.txt"
tail -8 "$D/run_full_c455.txt"
echo "===C455DONE=== the 150s run receipted - PASS/REVERT from the digest receipts"
