#!/bin/bash
# c456_runonly.sh - RUN-ONLY VERDICT CYCLE at 190s on the R1382
# tree (06e7abc1 verified first). NO patch, NO build:
# the c454 cycle compiled this exact tree (BUILD OK,
# 21:23) - run.sh reuses the fresh binary. NO RUN in
# c454 (watchdog math), so this cycle is the verdict. The c454 receipts: R1382 (the arm-gate WIDEN) landed + compiled clean -
# the c453 receipts convicted the cmd/pend/sched terms
# (the ARRIVAL posture holds cmd=01/pend=1/sched=1) -
# now removed, freeze 5s. THIS PASS: RUN_BUDGET_S=190
# gives the park + the 5s freeze + R1298's 30s confirm
# room.
# NEVER-TWICE (c451): the receipt trail tees to
# /tmp/c461_receipts.txt AS IT RUNS so a watchdog kill
# can never erase progress evidence. PASS = [f15arm]
# fire + R1298 start + FDF8 92180 drains + FE08 walks +
# dstw0!=0 + forward execution. REVERT = fire with no
# consumption.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C453-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c461_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="06e7abc1114ec13b231b5a58621c90732c0c2ed62a27e4502bebe96197e6870b"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1384 tree 06e7abc1 - refusing to run"; exit 0; fi
echo "TREE_VERIFIED (the R1384 tree - the immediate arm+bell is in place)"
C0=$(grep -c -e "f15arm" "$SRC")
echo "f15arm marker: $C0 (expect 1)"
if [ "$C0" != "1" ]; then echo "GATE-FAILED: marker missing"; exit 0; fi
C1=$(grep -c -e "R1384 (c458 receipts)" "$SRC")
echo "R1384 marker: $C1 (expect 2)"
if [ "$C1" != "2" ]; then echo "GATE-FAILED: R1384 marker wrong count"; exit 0; fi
C2=$(grep -c -e "f15arm. R1384" "$SRC")
echo "f15arm-R1384 print: $C2 (expect 1)"
if [ "$C2" != "1" ]; then echo "GATE-FAILED: R1384 print missing"; exit 0; fi
C3=$(grep -c -e "cd_read_active = 1; cd_pending = 1; g_cd_irq_force = 1;" "$SRC")
echo "bell line: $C3 (expect 1)"
if [ "$C3" != "1" ]; then echo "GATE-FAILED: bell line missing"; exit 0; fi
echo "===RUN461=== run-only (RUN_BUDGET_S=190, no build)"
RUN_BUDGET_S=190 ./run.sh run > /tmp/run_full_c461.txt 2>&1
echo "RUN_RC=$?"
LOG="run.log"
echo "===DIGEST461=== the post-stream era census (the arm+stream PASSed c460 - this pass receipts what the game does AFTER the f15 read completes)"
echo "--- THE FIRE (the c460 milestone, repeated?):"
grep -n -e "f15arm" "$LOG" | tail -2
grep -n -e "f15stream" "$LOG" | tail -3
echo "--- THE STREAM TAIL (sectors + drain):"
grep -c -e "sector LBA 10899" "$LOG"
grep -c -e "sector LBA 1090" "$LOG"
grep -n -e "req] FDF8" "$LOG" | tail -4
echo "--- THE WAIT LOOP: mvloop tail (did the n-counter pass the arm era? does A22C/FE1C move?):"
ARM_LINE=$(grep -n -e "f15arm" "$LOG" | head -1 | cut -d: -f1)
echo "arm at line $ARM_LINE"
grep -n -e "mvloop" "$LOG" | tail -4
echo "--- mvloop receipts AFTER the arm (the loop exit evidence):"
if [ -n "$ARM_LINE" ]; then tail -n +$((ARM_LINE+1)) "$LOG" | grep -n -e "mvloop" | head -4; else echo "(no arm line - pacing variance, no fire this run)"; fi
echo "--- MDEC/movie activity (the movie player would be the next consumer):"
grep -c -e "mdec" "$LOG" | tr -d " "
grep -n -e "MDEC" "$LOG" | tail -4
echo "--- the game acks during the stream (pendclr tail):"
grep -n -e "pendclr" "$LOG" | tail -4
echo "--- forward execution after the arm (fvp/mod6/READ ISSUED/seek past 108999):"
if [ -n "$ARM_LINE" ]; then tail -n +$((ARM_LINE+1)) "$LOG" | grep -n -e "MODULE 6 ENTRY\|fvp\|READ ISSUED\|seek=108999\|seek=109000\|seek=10900" | head -8; else echo "(no arm this run)"; fi
echo "--- state cameras after the arm (A22C/FE1C/wedgespin/abort):"
if [ -n "$ARM_LINE" ]; then tail -n +$((ARM_LINE+1)) "$LOG" | grep -n -e "fldfrz2\|wedgespin\|abort\|state" | head -6; else echo "(no arm this run)"; fi
echo "--- death receipts:"
grep -n -e "rungasp" "$LOG" | tail -2
echo "--- tree sha:"
echo "expected=06e7abc1114ec13b231b5a58621c90732c0c2ed62a27e4502bebe96197e6870b"
shasum -a 256 "$SRC" | cut -d" " -f1
echo "===PRESERVE461=== c118 protocol"
D=$(mktemp -d "$PWD/c461_snap.XXXXXX") || { echo "SNAPSHOT-DIR-FAILED"; exit 0; }
cp -p run.log "$D/run.log" && CP1=0 || CP1=1
cp -p /tmp/run_full_c461.txt "$D/run_full_c461.txt" && CP2=0 || CP2=1
cp -p /tmp/c461_receipts.txt "$D/c461_receipts.txt" && CP3=0 || CP3=1
echo "cp_rcs: $CP1 $CP2 $CP3"
ls -la "$D"
shasum -a 256 "$D/run.log" "$D/run_full_c461.txt"
tail -8 "$D/run_full_c461.txt"
echo "===C461DONE=== the 150s run receipted - PASS/REVERT from the digest receipts"
