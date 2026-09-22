#!/bin/bash
# c450_r1381anchors.sh - READ-ONLY CENSUS of the R1381
# anchors (tree 2c660613 verified). NO run, NO patch,
# NO build. The c449 correction: defib6's R473 fire #1
# was FILE#14's legitimate whole-member carry
# completion (62 sectors, 126976 bytes, fdf8 drained);
# the TRUE frontier: the field coordinator positioned
# the READ-AHEAD RING for file#15 (FE08=8007F2F8,
# FDF8=0) and the driver expects READ-AHEAD STREAMING;
# the handshake completed; the module renders on an
# empty archive. R1381 = the R583 f14inst pattern for
# file#15 (stream 92180 bytes from LBA 108995 into the
# ring + done bookkeeping; R496 file-table arm
# precedent). THIS PASS prints the anchors: (1) the
# R489 carry-PROMOTE gate (the size-adoption logic);
# (2) the defib6 entry posture; (3) the FULL f14inst
# block (the fix template); (4) the R539/R540 f15-park
# handler; (5) the log-side park postures + ring
# receipts. Receipts only - R1381's patch follows
# from these only.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C450-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="2c660613e608e9f878833ece08dcb579a4f431b11c7c4e411323db2c5633f6f2"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1380 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the R1380 tree)"
echo "===R489PROMOTE450=== the carry-PROMOTE gate (size adoption)"
grep -n -e "R489" "$SRC" | head -6
L=$(grep -n -e "carry PROMOTE" "$SRC" | head -1 | cut -d: -f1)
echo "--- region around the PROMOTE print (line $L, -70..+15):"
awk -v s=$((L-70)) -v e=$((L+15)) 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
echo "===DEFIB6ENTRY450=== the defib6 entry posture (15120..15195)"
awk 'NR>=15120 && NR<=15195 { print NR": "$0 }' "$SRC"
echo "===F14INST450=== the full f14inst block (the fix template)"
grep -n -e "f14inst" "$SRC" | head -4
L2=$(grep -n -e "FILE-14 INSTALLER" "$SRC" | head -1 | cut -d: -f1)
if [ -z "$L2" ]; then L2=$(grep -n -e "f14inst" "$SRC" | head -1 | cut -d: -f1); fi
echo "--- f14inst region (line $L2, +80):"
awk -v s="$L2" -v e=$((L2+80)) 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
echo "===F15REGION450=== the R539/R540 f15-park handler (15614..15675)"
awk 'NR>=15614 && NR<=15675 { print NR": "$0 }' "$SRC"
echo "===PARKPOSTURE450=== the log-side park postures + ring receipts"
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
grep -n -e "F0C=15" "$LOG" | tail -4
grep -n -e "8007F2F8" "$LOG" | tail -6
grep -n -e "cbmod2" "$LOG" | tail -4
echo "===C450DONE=== the R1381 anchors are receipted - the patch follows from these only"
