#!/bin/bash
# c463_extract.sh - READ-ONLY EXTRACTION, NO RUN, NO
# BUILD, NO PATCH. TARGET: the R879 MOVIE-DOOR block
# verbatim - its exact gate + its exact cell writes -
# because the c462 census found it posts EXACTLY the
# shipment announcement LegacyCdDataWait needs (A22C
# bump + slotbits + flag578A6=1) and never fired for
# the f15 band. Receipts: (1) the R879 block (the
# receipt print at the MOVIE-DOOR line, +-45 lines);
# (2) ALL writers of 0x8006A22C / 0x8006A228 /
# 0x800578A6 / 0x8005FDFC (the true door cells);
# (3) the 14595 LegacyCdDataWait exit-decode region;
# (4) the R1098 decode at 5171 (CD_datasync twin
# comment); (5) the CheckCallback 0x8004B894 region;
# (6) mvdoor/R879 fire history in the c461 run.log.
# Fail-closed, tee'd to /tmp/c463_receipts.txt.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C463-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c463_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="06e7abc1114ec13b231b5a58621c90732c0c2ed62a27e4502bebe96197e6870b"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the R1384 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the R1384 tree)"
region() {
  LN=$1; WIDE=$2; TAG=$3
  echo "--- $TAG (line $LN, +- $WIDE):"
  S=$((LN>WIDE+1 ? LN-WIDE : 1)); E=$((LN+WIDE))
  sed -n "${S},${E}p" "$SRC"
}
echo "===R879-BLOCK=== the MOVIE-DOOR receipt print + its full block"
LN=$(grep -n -e "MOVIE-DOOR DATA EVENT POSTED" "$SRC" | head -1 | cut -d: -f1)
echo "print at line $LN"
if [ -n "$LN" ]; then region "$LN" 45 "the R879 block"; fi
echo "===ALL-R879-SITES=== every mvdoor/R879 marker in the tree"
grep -n -e "mvdoor" -e "R879" "$SRC" | head -20
echo "===WRITERS=== every site referencing the true door cells (0x8006A22C / 0x8006A228 / 0x800578A6 / 0x8005FDFC)"
for CELL in "0x8006A22C" "0x8006A228" "0x800578A6" "0x8005FDFC"; do
  echo "--- cell $CELL:"
  grep -n -e "$CELL" "$SRC" | head -12
done
echo "===WRITER-CONTEXT=== context of each WRITE (write32) site for these cells"
for CELL in "0x8006A22C" "0x800578A6"; do
  for LN in $(grep -n -e "write32.*$CELL" "$SRC" | cut -d: -f1 | head -6); do
    region "$LN" 6 "write site for $CELL"
  done
done
echo "===LEGWAIT-EXIT=== the 14595 exit-decode region"
region 14595 22 "the LegacyCdDataWait exit decode"
echo "===R1098=== the 5171 CD_datasync-twin comment"
region 5171 18 "the R1098 LegacyCdDataWait decode"
echo "===CHECKCB=== the CheckCallback 0x8004B894 region"
LN=$(grep -n -e "8004B894" "$SRC" | head -1 | cut -d: -f1)
echo "at line $LN"
if [ -n "$LN" ]; then region "$LN" 15 "the CheckCallback region"; fi
echo "===HISTORY=== the movie-door fire history in the c461 run.log + all mvdoor-era tags"
grep -c -e "MOVIE-DOOR" run.log | tr -d " "
grep -c -e "mvdoor" run.log | tr -d " "
grep -n -e "flag578A6" run.log | head -4
grep -n -e "slotbits" run.log | head -4
echo "===C463DONE=== the R879 block + writer receipts are in - the c464 f15 announcement fix writes EXACTLY these cells"
