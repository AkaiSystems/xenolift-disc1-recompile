#!/bin/bash
# c353_witnesspass2.sh - READ-ONLY pass 2 on the preserved c351
# witness. NO patch, NO run. The c352 receipts: the game is IN
# state 1 (FIELD ERA START), the mount accessor holds cur=1
# req=1, but the file#14 re-read never serves - FDF8 frozen at
# 125304, 92D0=0, the queue node 59F10 holds the file#14
# request, the ladder stops at #5 (the kernel never issues the
# ReadN). SUSPECT: the node result cells hold the STAT filler
# 02020202 (the c277 GetTN/TOC stall). THIS PASS: the park
# window's scheduler decisions, the command-byte writes, the
# filler's writers, the GetTN story, and the mount progression.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C353-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="14bd5f5d96d4b0f33beb05be6ed8d490d71735912b5b8f3949d6bc57682061ea"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1360 tree - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1360 tree)"
WD="witness_c351_20260917_134012"
LOG="$WD/run.log"
[ -s "$LOG" ] || LOG="$WD/run.log.d"
if [ ! -s "$LOG" ]; then echo "WITNESS-MISSING: the c351 witness is not on disk - nothing to mine"; exit 0; fi
echo "WITNESS=$WD LOG=$LOG SIZE=$(wc -l < "$LOG" | tr -d ' ') lines"
echo "===SCHEDWIN353=== the scheduler decisions in the park window (24900+)"
grep -n "schdd\|sgdecline\|R1291" "$LOG" | awk -F: '$1>=24900' | head -20
echo "--- and the whole-run scheduler census ---"
grep -c "schdd" "$LOG"
grep -n "schdd" "$LOG" | tail -4
echo "===CMDBYTES353=== the command-byte writes in the park window (did the kernel write the 06?)"
grep -n "fetchw" "$LOG" | awk -F: '$1>=24900' | tail -20
echo "--- all 1F801801 writes (cmd register) whole-run tail ---"
grep -n "reg write 1F801801" "$LOG" | tail -8
echo "===COLLECTOR353=== the collector chain in the park window"
grep -n "wgen\|wconv\|wopflag\|wserve" "$LOG" | awk -F: '$1>=24900' | head -16
echo "===FILLER353=== the 02020202 story (who wrote the filler, when)"
grep -n "02020202" "$LOG" | head -20
echo "--- hook receipts on the node result cells 59F18/59F1C ---"
grep -n "80059F18\|80059F1C" "$LOG" | head -12
echo "===GETTN353=== the GetTN/TOC story"
grep -n "GetTN\|cmd 13\|\[toc\]" "$LOG" | head -12
echo "===MOUNTPROG353=== the mount progression (92D0/92C8) whole-run"
grep -n "92D0\|92C8" "$LOG" | head -16
echo "===REPRIME353=== the drive answers in the park window"
grep -n "reprime\|R263" "$LOG" | awk -F: '$1>=24900' | head -10
echo "===R1356353=== the fd-queue accessor receipts (the 4247C/413EC pair)"
grep -n "4247C\|413EC" "$LOG" | awk -F: '$1>=24900' | head -12
echo "===C353DONE=== witness pass 2 is receipted - the ReadN-never-issued story is complete"
