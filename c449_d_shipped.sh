#!/bin/bash
# c449_healgates.sh - READ-ONLY CENSUS of the heal
# gate regions (tree 2c660613 verified). NO run, NO
# patch, NO build. The c448 verdict: the file#15
# request (positioned at 108995, dest 8007F2F8, FDF8=0,
# never issued) was consumed by OUR OWN HEALS:
# defib6 R473 'stalled-load COMPLETED: 62 sectors
# stuffed into ring, FDF8=0' + R540 fldfin 'end-of-read
# + read-active CLEARED' - leaving 62 sectors in the
# runtime ring, dstw0=0 (never delivered), the game
# proceeding on an empty archive (font garbage
# 0x60B025xx). R1381 = gate both heals on FDF8>0 (the
# R1379 live-request family). THIS PASS prints the
# gate regions verbatim: (1) the defib6/R473 stalled-
# load fire + its enclosing condition; (2) the R540
# fldfin end-of-read clear + its condition; (3) the
# fld-rearm sector-bell site (the working file#14
# chain's fetch starter); (4) the R1365 field-spin
# scheduled-read arming gate; (5) the log-side defib6
# fire #1 context. Receipts only - the patch anchors
# follow from these only.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C449-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="2c660613e608e9f878833ece08dcb579a4f431b11c7c4e411323db2c5633f6f2"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1380 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the R1380 tree)"
echo "===DEFIB6449=== the R473 stalled-load heal: fire sites + enclosing region"
grep -n -e "R473" "$SRC" | head -8
L=$(grep -n -e "stalled-load COMPLETED" "$SRC" | head -1 | cut -d: -f1)
echo "--- region around the fire print (line $L, -46..+14):"
awk -v s=$((L-46)) -v e=$((L+14)) 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
echo "===FLDFIN449=== the R540 fldfin end-of-read clear: sites + region"
grep -n -e "R540" "$SRC" | head -8
L2=$(grep -n -e "end-of-read" "$SRC" | head -1 | cut -d: -f1)
echo "--- region around the end-of-read clear (line $L2, -40..+12):"
awk -v s=$((L2-40)) -v e=$((L2+12)) 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
echo "===FLDBELL449=== the sector-bell re-arm site (the working fetch starter)"
grep -n -e "fld-rearm" "$SRC" | head -4
L3=$(grep -n -e "fld-rearm" "$SRC" | head -1 | cut -d: -f1)
if [ -n "$L3" ]; then echo "--- region around the bell re-arm (line $L3, -30..+10):"; awk -v s=$((L3-30)) -v e=$((L3+10)) 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"; fi
echo "===R1365449=== the R1365 field-spin scheduled-read arming gate"
grep -n -e "R1365" "$SRC" | head -8
L4=$(grep -n -e "R1365" "$SRC" | tail -1 | cut -d: -f1)
if [ -n "$L4" ]; then echo "--- region (line $L4, -30..+8):"; awk -v s=$((L4-30)) -v e=$((L4+8)) 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"; fi
echo "===FIRECTX449=== the log-side defib6 fire #1 context"
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
awk 'NR>=31740 && NR<=31760 { print NR": "$0 }' "$LOG"
echo "===C449DONE=== the heal gate regions are receipted - R1381's anchors follow from these only"
