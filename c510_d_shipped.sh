#!/bin/bash
# c510_extract.sh - READ-ONLY BRANCH CENSUS, NO RUN, NO
# BUILD, NO PATCH. The c509 receipts: the healthy
# 239317-era loop is fully receipted (INT1 consumed ->
# 56788: 02->102 -> slot=4 -> FILE-CB -> fetch -> cd-dma ->
# FDF8 countdown -> ring advance -> next sector), and the
# broken file#18 window runs the SAME chain to the SAME
# site (the 56789 twin write at sw 128995 fires) but SKIPS
# the 56788 bit-8 store - so slot=4 never arms. The c509
# sed window landed on fn_8004196C's tail (zero-byte stores
# through pointers from 0x80056770/0x8005677C, then the
# call) - fn_80041B24's OWN body starts just below line
# 129060 and holds the deciding branch. THE QUESTION: what
# does fn_80041B24 read (likely 1F801803 bank 1, the
# INT-flag register - 'Response Received' bits 0-2) to
# decide the 56788 data-ready bit, and why does it read
# FALSE in the file#18 era? THIS CENSUS receipts: (1)
# fn_80041B24's body (disc1.c 129060-129260); (2) every
# emitted store to 0x80056788 with surrounding lines; (3)
# the runtime's 1F801803 read handlers (both sites); (4)
# every runtime reference to 0x80056788. Fail-closed, tee'd
# to /tmp/c510_receipts.txt. Pure-ASCII output.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C510-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c510_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="13aab535963b12c3ff0515d0c2892e8d7625327afa09a3569ae1f2d7b3e1c5d4"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the c504 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the c504 tree with the landed interpreter)"
D="disc1.c"
if [ ! -f "$D" ]; then echo "GATE-FAILED: disc1.c missing"; exit 0; fi
if [ ! -f "$SRC" ]; then echo "GATE-FAILED: runtime.c missing"; exit 0; fi
echo "===FN510=== fn_80041B24's body (disc1.c 129060-129260)"
sed -n "129060,129260p" "$D"
echo "===W510=== every emitted store to 0x80056788 (with context)"
grep -n -F -e "80056788" "$D" | head -12
echo "--- context around the FIRST store site:"
W1=$(grep -n -F -e "80056788" "$D" | head -1 | cut -d: -f1)
if [ -n "$W1" ]; then sed -n "$((W1-16)),$((W1+10))p" "$D"; fi
echo "===HAND510=== the runtime's 1F801803 read handlers (both sites)"
sed -n "2330,2400p" "$SRC"
sed -n "3820,3880p" "$SRC"
echo "===RT510=== every runtime reference to 0x80056788"
grep -n -F -e "56788" "$SRC" | head -12
echo "===C510DONE=== the deciding branch + its input register are receipted - the c511 fix follows from these receipts only - digest is pure ASCII"
