#!/bin/bash
# c514_extract.sh - READ-ONLY LATE-ERA COLLECTOR CENSUS, NO
# RUN, NO BUILD, NO PATCH. The c513 receipts: (1) the R206
# fallback (h4 cell + read-struct both empty -> known-native
# h4 0x8002B084) IS the healthy delivery engine's dispatch
# path; (2) the healthy slot-bits word during delivery =
# s2=0x100 s3=88000001 - and the broken window's byte
# store at 10621 produced the IDENTICAL s3; (3) the R1361
# camera's 16-print budget + my head caps HID the
# late-era/file#18-window collector history (cap artifacts,
# not absence); (4) my full-literal greps were BLIND to the
# emitter's split-immediate idiom (0x8006<<16 + 0xA22C) -
# the emitted A22C/56789 writers exist at L_80041B84-BA4.
# THE QUESTION: what did the collector return in the
# file#18 window (lines 10487-10656), did the R206 fallback
# fire there, did ANY arm (R96/R1378/R408/R453) ever fire
# anywhere, and what preceded the healthy 239317-era slot=4
# events? THIS CENSUS receipts from the EXISTING log with
# LATE-ERA line filters: (1) every slot=4 event past line
# 8000; (2) every h4-fallback receipt past line 9400; (3)
# the complete collector/tick behavior in the broken
# window; (4) every arm-fire receipt in the whole log.
# Fail-closed, tee'd to /tmp/c514_receipts.txt.
# Pure-ASCII output.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C514-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c514_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="13aab535963b12c3ff0515d0c2892e8d7625327afa09a3569ae1f2d7b3e1c5d4"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the c504 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the c504 tree with the landed interpreter)"
LOG="run.log"
if [ ! -s "$LOG" ]; then LOG="run.log.d"; fi
if [ ! -s "$LOG" ]; then echo "GATE-FAILED: no log"; exit 0; fi
echo "LOG=$LOG ($(wc -l < "$LOG" | tr -d " ") lines)"
echo "===SLOT4LATE514=== every slot=4 event past line 8000 (the healthy 239317 era vs the file#18 window)"
awk 'NR>8000 && /collector slot=4/ { print NR": "$0 }' "$LOG" | head -24
echo "===H4LATE514=== every h4-fallback receipt past line 9400 (both runs' later eras)"
awk 'NR>9400 && /h4 cell/ { print NR": "$0 }' "$LOG" | head -16
echo "===WIN514=== the complete collector/tick behavior in the broken window (10600-10710)"
awk 'NR>=10600 && NR<=10710 && (/wait-loop event/ || /wait-loop tick/ || /cdcol/ || /slot/ || /h4 cell/ || /rspop byte#1/ || /acknowledged/) { print NR": "$0 }' "$LOG" | head -40
echo "===ARM514=== every arm-fire receipt in the whole log (R96/R1378/R408/R453/R206-class)"
grep -n -e "\[drdoor\]" "$LOG" | head -12
grep -n -e "forced data-ready INT1" "$LOG" | head -8
grep -n -e "\[fld-int1\]" "$LOG" | head -8
grep -n -e "\[fld2-int1\]" "$LOG" | head -8
grep -n -e "\[mvdoor\]" "$LOG" | head -8
echo "--- the slot=2 vs slot=4 census in the file#18 window + after:"
awk '/collector slot=/ && NR>10400 { print NR": "$0 }' "$LOG" | head -24
echo "===C514DONE=== the late-era collector history is receipted uncapped - the c515 fix design follows from these receipts only - digest is pure ASCII"
