#!/bin/bash
# c509_extract.sh - READ-ONLY DATA-READY CENSUS, NO RUN, NO
# BUILD, NO PATCH. The c508 healthy-vs-broken comparison
# named the delivery mechanism: the healthy chain is
# wait-loop event -> collector slot=4 -> dispatch h4
# 0x8002B084 (the FILE-CB) -> DATA HANDLER ->
# LegacyCdSectorFetch (caller 800413BC) -> the GUEST writes
# the DMA registers -> cd-dma fires -> the sector lands ->
# ring advances. The broken window stops ONE step earlier:
# healthy shows the DATA-READY BIT WRITE (0x80056788:
# 00000002 -> 00000102 at fn 0x80041B24 sw_line=128995)
# which arms the collector's slot-4 event; the broken
# window ran the SAME SITE (the twin 56789 write at
# sw_line=128995 occurred) but the 56788 write NEVER
# happened - so slot=4 never queued, the FILE-CB never
# dispatched, no DMA, the FIFO sector sat unconsumed,
# FDF8 stayed 14360. CLEARED SUSPECTS: the null sector
# callback (cbreg a0=0 appears in EVERY era including
# healthy - delivery uses the collector slots, not the
# PSX sector callback) and data=0/2060 (appears in the
# WORKING 239317-era too). THE QUESTION: what condition
# inside the guest's own fn 0x80041B24 (at the sw 128995
# site) decides the 56788 data-ready bit, and why did it
# evaluate FALSE for the file#18 request? THIS CENSUS
# receipts: (1) the emitted code at that exact site
# (disc1.c around line 128995, the condition + the
# 56788/56789 writes); (2) the collector slot=4 history
# (what arms it); (3) the WORKING 239317-era window right
# after the [frc] poll (how delivery proceeded there);
# (4) the runtime's fifo/status register model (the frc
# camera's data= source + the 1F801803 handler).
# Fail-closed, tee'd to /tmp/c509_receipts.txt.
# Pure-ASCII output.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C509-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c509_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="13aab535963b12c3ff0515d0c2892e8d7625327afa09a3569ae1f2d7b3e1c5d4"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the c504 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the c504 tree with the landed interpreter)"
LOG="run.log"
if [ ! -s "$LOG" ]; then LOG="run.log.d"; fi
echo "LOG=$LOG ($(wc -l < "$LOG" | tr -d " ") lines)"
D="disc1.c"
if [ ! -f "$D" ]; then echo "GATE-FAILED: disc1.c missing"; exit 0; fi
echo "===SITE509=== the emitted code at the data-ready site (disc1.c line 128995 +/- context)"
sed -n "128955,129060p" "$D"
echo "===SLOT509=== the collector slot=4 history (what arms the data-ready event)"
grep -n -e "slot=4" "$LOG" | head -16
grep -n -e "\[slot\]" "$LOG" | grep -F -e "a0=0x00000004" | head -8
echo "===WORK509=== the WORKING 239317-era window after the frc poll (delivery proceeding)"
FRC=$(grep -n -e "\[frc\].*239317" "$LOG" | head -1 | cut -d: -f1)
echo "the 239317-era frc poll at line $FRC; the window that follows:"
awk -v A="$FRC" 'NR>=A && NR<=A+80 { print NR": "$0 }' "$LOG" | head -90
echo "===MODEL509=== the runtime's fifo/status model (the frc data= source + 1F801803)"
grep -n -e "poll803" "$SRC" | head -4
grep -n -e "1F801803" "$SRC" | head -12
grep -n -e "data_loaded" "$SRC" | head -6
echo "--- the fifo byte-count model:"
grep -n -e "fifo" "$SRC" | grep -e "2060" | head -8
echo "===C509DONE=== the data-ready condition is receipted - the c510 fix follows from these receipts only - digest is pure ASCII"
