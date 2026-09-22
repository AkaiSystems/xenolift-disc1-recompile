#!/bin/bash
# c513_extract.sh - READ-ONLY SLOT-BITS HISTORY CENSUS, NO
# RUN, NO BUILD, NO PATCH. The c512 receipts: the
# wait-loop dispatches the GUEST's collector
# (fn_800415B4), reads slot bits from r[2] (slots&4 -> h4
# FILE-CB, with R206's read-struct fallback and R1183's
# forge-block break); in the broken window the collector
# RAN (slot=2 receipts) but the data-event bit never
# entered the word. EVERY data-ready arm in the runtime
# (R96, R1378, R408, R453) requires cd_pending==0 - the
# file#18 posture holds pend=3 ('near-universal' per
# R1357's own reverted-gate comment). The guest's event
# post goes through 0x80056788 bits + flag 0x800578A6.
# THE REMAINING QUESTION: the slot-bits word's actual
# values in both eras at collector-complete (the R1361
# camera already receipts them), the genuine-answer
# collector state, the R206 fallback history, and the
# identity of the emitted function that posts the
# 0x800578A6 event. THIS CENSUS receipts from the
# EXISTING logs and code only: (1) the [cdcol] R1361
# collector-complete inputs (both eras); (2) the [wgen]
# genuine-answer receipts; (3) the R206 fallback /
# read-struct receipts; (4) the 578A6 post-site in the
# emitted code + the A22C family writers.
# Fail-closed, tee'd to /tmp/c513_receipts.txt.
# Pure-ASCII output.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C513-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c513_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="13aab535963b12c3ff0515d0c2892e8d7625327afa09a3569ae1f2d7b3e1c5d4"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the c504 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the c504 tree with the landed interpreter)"
LOG="run.log"
if [ ! -s "$LOG" ]; then LOG="run.log.d"; fi
D="disc1.c"
for F in "$D" "$SRC"; do
  if [ ! -s "$F" ]; then echo "GATE-FAILED: $F missing/empty"; exit 0; fi
done
echo "===CDCOL513=== the R1361 collector-complete inputs (the slot-bits word, both eras)"
grep -n -e "\[cdcol\]" "$LOG" | head -32
echo "===WGEN513=== the genuine-answer collector state (both eras)"
grep -n -e "\[wgen\]" "$LOG" | head -16
echo "===R206513=== the slot-4 fallback / read-struct receipts"
grep -n -F -e "read-struct" "$LOG" | head -12
grep -n -e "h4 cell" "$LOG" | head -12
echo "===POST513=== the 578A6 event-flag post-site in the emitted code + runtime refs"
grep -n -F -e "578A6" "$D" | head -8
grep -n -F -e "578A6" "$SRC" | head -8
echo "--- context around the FIRST emitted 578A6 site (the post function):"
E1=$(grep -n -F -e "578A6" "$D" | head -1 | cut -d: -f1)
if [ -n "$E1" ]; then sed -n "$((E1-12)),$((E1+8))p" "$D"; fi
echo "===A22C513=== the A22C family writers in the emitted code (the sync-chunk cells)"
grep -n -F -e "0x8006A22Cu" "$D" | head -10
echo "--- the slot-bits word's guest writers (0x80056788/89 stores) re-checked:"
grep -n -F -e "0x80056789" "$D" | head -10
echo "===C513DONE=== the slot-bits history + post-site identity are receipted - the c514 fix follows from these receipts only - digest is pure ASCII"
