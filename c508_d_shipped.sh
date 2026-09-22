#!/bin/bash
# c508_extract.sh - READ-ONLY HEALTHY-VS-BROKEN DELIVERY
# COMPARISON, NO RUN, NO BUILD, NO PATCH. The c507 raw
# window verdict: the delivery engine RAN for the file#18
# request - the sector WAS loaded into the data FIFO twice
# (LBA 109158, 2048 bytes), INT1 armed/re-asserted/converted
# - but NO [cd-dma] ever fired, and the game's own consumer
# (the CD-sync chunk family r31=80041C78/80041CA0 polling
# 1F801803 idx=1) saw data=0/2060 - an EMPTY FIFO despite
# loaded=1 - and polled forever. In the SAME run, the
# file#3 read delivered every sector via cd-dma (header to
# 80059EF8 + data to the ring dest) with FDF8 counting
# down. TWO CANDIDATE CAUSES: (a) the sector callback was
# CLEARED (cbreg SetCdSectorCallback(a0=00000000) caller
# 80029A90 at the window) and never re-registered - the
# INT1 handler has no consumer to invoke, so no DMA; or
# (b) the FIFO-status register model reports 0 bytes when
# a sector is loaded (pos=0/2060 despite loaded=1), so the
# game's poll never sees data. THE DISCRIMINATOR: the
# healthy file#3 window - who fired the cd-dma there, and
# what the callback registration + poll signatures looked
# like. THIS CENSUS receipts: (1) the raw healthy window
# (ringw #13 through the first fldsec, ~150 lines,
# dynamically anchored); (2) every cbreg + cbtaint receipt
# in the log (the callback chain, all eras); (3) the full
# [frc] poll history (the register view across eras); (4)
# every fld2sig signature (the posture comparison);
# (5) the fldsec consumption history (both eras).
# Fail-closed, tee'd to /tmp/c508_receipts.txt.
# Pure-ASCII output.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C508-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c508_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="13aab535963b12c3ff0515d0c2892e8d7625327afa09a3569ae1f2d7b3e1c5d4"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the c504 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the c504 tree with the landed interpreter)"
LOG="run.log"
if [ ! -s "$LOG" ]; then LOG="run.log.d"; fi
echo "LOG=$LOG ($(wc -l < "$LOG" | tr -d " ") lines)"
H1=$(grep -n -F -e "ringw] #13" "$LOG" | head -1 | cut -d: -f1)
if [ -z "$H1" ]; then echo "GATE-FAILED: the healthy ringw #13 anchor not found - refusing"; exit 0; fi
echo "===HEALTHY508=== the raw healthy file#3 window (ringw #13 at line $H1, the delivery chain in order)"
awk -v A="$((H1-8))" 'NR>=A && NR<=A+150 { print NR": "$0 }' "$LOG" | head -160
echo "===CBREG508=== every sector-callback receipt (the registration chain, all eras)"
grep -n -e "cbreg" "$LOG" | head -16
grep -n -e "cbtaint" "$LOG" | head -16
echo "--- the callback-taint stub target (80040B9C) mentions:"
grep -n -F -e "80040B9C" "$LOG" | head -8
echo "===FRC508=== the full [frc] poll history (the register view, both eras)"
grep -n -e "\[frc\]" "$LOG" | head -24
echo "===FLD2508=== every fld2sig signature (the posture comparison)"
grep -n -e "fld2sig" "$LOG" | head -24
echo "===FLDSEC508=== the sector-consumption history (both eras)"
grep -n -e "fldsec" "$LOG" | head -24
echo "===C508DONE=== callback-null vs register-model is receipted - the c509 fix follows from these receipts only - digest is pure ASCII"
