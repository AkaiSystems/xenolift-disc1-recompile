#!/bin/bash
# c515_extract.sh - READ-ONLY R2-PROVENANCE CENSUS, NO RUN,
# NO BUILD, NO PATCH. The c514 receipts: (1) ZERO arm fires
# anywhere (no drdoor/R96/fld-int1/fld2-int1/mvdoor) - the
# runtime arm family is dead code in this run; healthy
# delivery was the GUEST's own chain end-to-end; (2) every
# healthy slot=4 was followed by the R206 fallback (h4 cell
# + read-struct empty -> known-native 0x8002B084); (3) the
# file#18 window: slot=2 only, never slot=4, though the
# byte store at 10621 produced the healthy s3 shape - a
# SECOND input to the getintr never arrived; (4) candidate:
# A22C (the CD-data-arrived flag) - healthy DATA HANDLER
# shows A22C=00000004, broken window shows A22C=00000000
# throughout; the A22C writers live in the
# LegacyCdCommandSync chunk (L_80041B84-BA4) - the SAME
# chunk that shows POISON entries in the broken window
# (r2=00000000 vs healthy r2=80018EB0, a valid kernel-data
# pointer). THE QUESTION: what feeds r2 into the chunk -
# the pointer entering NULL in the file#18 era, breaking
# the chain that sets A22C. THIS CENSUS receipts: (1) the
# emitted code around L_80041B70-L_80041BA8 (who loads r2);
# (2) the chunk's A22C-writer body (L_80041B84-BA4); (3)
# every A22C receipt past line 10400 (did it EVER set in
# the broken era?); (4) the full [cdcsync] r2 history both
# eras. Fail-closed, tee'd to /tmp/c515_receipts.txt.
# Pure-ASCII output.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C515-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c515_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="13aab535963b12c3ff0515d0c2892e8d7625327afa09a3569ae1f2d7b3e1c5d4"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the c504 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the c504 tree with the landed interpreter)"
LOG="run.log"
if [ ! -s "$LOG" ]; then LOG="run.log.d"; fi
D="disc1.c"
for F in "$LOG" "$D"; do
  if [ ! -s "$F" ]; then echo "GATE-FAILED: $F missing/empty"; exit 0; fi
done
echo "===R2PROV515=== the emitted path into the chunk (who loads r2): L_80041B70 region"
grep -n -e "L_80041B70" "$D" | head -6
B70=$(grep -n -e "L_80041B70:" "$D" | head -1 | cut -d: -f1)
if [ -n "$B70" ]; then echo "--- the region at line $B70 (the path feeding the chunk):"; sed -n "$((B70-30)),$((B70+40))p" "$D"; fi
echo "--- the chunk entry (0x80041BA8) head:"
BA8=$(grep -n -e "L_80041BA8:" "$D" | head -1 | cut -d: -f1)
if [ -n "$BA8" ]; then sed -n "$((BA8-6)),$((BA8+20))p" "$D"; fi
echo "===CHUNK515=== the A22C-writer body (L_80041B84-BA4)"
B84=$(grep -n -e "L_80041B84:" "$D" | head -1 | cut -d: -f1)
if [ -n "$B84" ]; then sed -n "$((B84-10)),$((B84+34))p" "$D"; else echo "(L_80041B84 not found; grepping the A22C offset)"; grep -n -e "0xA22C" "$D" | head -8; fi
echo "===A22C515=== every A22C receipt past line 10400 (did it EVER set in the broken era?)"
awk 'NR>10400 && /A22C/ { print NR": "$0 }' "$LOG" | head -28
echo "--- healthy contrast (A22C= set values in the healthy 239317 era):"
awk 'NR>=8060 && NR<=8120 && /A22C=/ { print NR": "$0 }' "$LOG" | head -8
echo "===CDC515=== the full [cdcsync] r2 history (both eras, poison vs valid)"
grep -n -e "\[cdcsync\]" "$LOG" | head -36
echo "===C515DONE=== the r2 provenance + A22C writer path are receipted - the c516 fix follows from these receipts only - digest is pure ASCII"
