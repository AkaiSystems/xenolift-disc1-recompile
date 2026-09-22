#!/bin/bash
# c507_extract.sh - READ-ONLY DELIVERY CENSUS, NO RUN, NO
# BUILD, NO PATCH. The c506 trace verdict: the buffer
# 0x801EF300 was chosen, armed, issued, and
# ring-switched-to (ringw #103 FE08: 801F9B20 ->
# 801EF300, READ ISSUED FDF8=14360) - and the bytes NEVER
# LANDED: not one [cd-dma] line names 801EF300 in either
# run; between READ ISSUED and lzss #4 only interrupt
# bookkeeping appears (pending INTs for LBA 109158
# CLEARED, no sector delivery); the unpack then consumed
# zeros. The heap-release wipe theory is CLEARED (the
# only wipes near the window target 80077458, after the
# unpack). THE QUESTION: did the delivery engine run at
# all for this request (sector loads / cd-dma anywhere in
# the window), or did it deliver into the PREVIOUS ring
# destination (801F9B20)? THIS CENSUS receipts: (1) the
# COMPLETE raw window from READ ISSUED to the lzss exit
# (line numbers dynamically derived from THIS log - every
# family, not a preselected list); (2) every cd-dma line
# in the log (destinations across eras); (3) the ringw
# switch history; (4) the stepper progression (FDF8
# countdown); (5) the sector-load receipts (bigread /
# 'loaded into data FIFO' / fldsec). Fail-closed, tee'd
# to /tmp/c507_receipts.txt. Pure-ASCII output.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C507-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c507_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="13aab535963b12c3ff0515d0c2892e8d7625327afa09a3569ae1f2d7b3e1c5d4"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the c504 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the c504 tree with the landed interpreter)"
LOG="run.log"
if [ ! -s "$LOG" ]; then LOG="run.log.d"; fi
echo "LOG=$LOG ($(wc -l < "$LOG" | tr -d " ") lines)"
RI=$(grep -n -e "READ ISSUED" "$LOG" | head -1 | cut -d: -f1)
LZ=$(grep -n -e "\[lzss\] #4" "$LOG" | head -1 | cut -d: -f1)
if [ -z "$RI" ] || [ -z "$LZ" ]; then echo "GATE-FAILED: READ ISSUED or lzss #4 not found - refusing (unexpected log shape)"; exit 0; fi
echo "READ ISSUED at line $RI; lzss #4 at line $LZ"
echo "===WIN507=== the COMPLETE raw window (every family, absolute line numbers)"
awk -v A="$RI" -v B="$LZ" 'NR>=A && NR<=B { print NR": "$0 }' "$LOG" | head -200
echo "===DEST507=== every cd-dma line in the log (destination history, both eras)"
grep -n -e "cd-dma" "$LOG" | head -30
echo "--- deliveries into the PREVIOUS ring destination (801F9B20):"
grep -n -F -e "801F9B20" "$LOG" | head -12
echo "===RINGW507=== the ring-switch history (all ringw receipts)"
grep -n -e "ringw" "$LOG" | head -16
echo "===STEP507=== the stepper receipts (the FDF8 countdown)"
grep -n -e "stepper" "$LOG" | head -20
echo "===SEC507=== the sector-load + consumption receipts"
grep -n -e "bigread" "$LOG" | head -12
grep -n -e "loaded into data FIFO" "$LOG" | head -12
grep -n -e "fldsec" "$LOG" | head -12
echo "===C507DONE=== the delivery engine's behavior for this request is receipted - the c508 fix follows from these receipts only - digest is pure ASCII"
