#!/bin/bash
# c462_census.sh - READ-ONLY CENSUS, NO RUN, NO BUILD,
# NO PATCH (the c461 snapshot is preserved; the live
# run.log IS the c461 run). TARGETS: (1) the 3
# lowercase mdec receipts; (2) the wedgespin anatomy at
# 0x8007B540 (fn 0x800465EC, 138M hits); (3) the A22C
# (0x8004A22C) WRITER sites in runtime.c - the R896
# boot sync-delivery family bumped it; our f15 delivery
# did not; (4) the FULL LegacyCdDataWait exit-note
# source (the R878 note is pipe-cut in the digest);
# (5) the post-arm activity between the fire and the
# pause; (6) fn 0x800465EC + cell 0x8007B540 context in
# the source. Receipts only, fail-closed, tee'd to
# /tmp/c462_receipts.txt.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C462-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c462_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="06e7abc1114ec13b231b5a58621c90732c0c2ed62a27e4502bebe96197e6870b"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the R1384 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the R1384 tree)"
LOG="run.log"
ls -la "$LOG"
echo "===MDEC462=== the 3 lowercase mdec receipts (full lines)"
grep -n -e "mdec" "$LOG" | head -8
echo "===WEDGE462=== the wedgespin anatomy (distinct sites + functions)"
grep -c -e "wedgespin" "$LOG"
grep -e "wedgespin" "$LOG" | grep -o -e "a=0x[0-9A-F]*" | sort | uniq -c | sort -rn | head -8
grep -e "wedgespin" "$LOG" | grep -o -e "cur_fn 0x[0-9A-F]*" | sort | uniq -c | head -8
grep -e "wedgespin" "$LOG" | head -2
grep -e "wedgespin" "$LOG" | tail -2
echo "===A22C-WRITER462=== the A22C (0x8004A22C) writer sites in runtime.c"
grep -n -e "0x8004A22C" "$SRC" | head -20
echo "--- context around each writer site (2 lines before/after):"
for LN in $(grep -n -e "0x8004A22C" "$SRC" | cut -d: -f1 | head -12); do
  echo "--- site at line $LN:"
  S=$((LN>3 ? LN-2 : 1)); E=$((LN+2)); sed -n "${S},${E}p" "$SRC"
done
echo "===LEGWAIT462=== the LegacyCdDataWait exit-note source (the R878 note is pipe-cut; print the full comment)"
grep -n -e "LegacyCdDataWait" "$SRC" | head -10
echo "--- the R878 camera print source (full note text):"
LN=$(grep -n -e "R878 CD-STATE" "$SRC" | head -1 | cut -d: -f1)
echo "at line $LN"
if [ -n "$LN" ]; then S=$((LN>7 ? LN-6 : 1)); E=$((LN+6)); sed -n "${S},${E}p" "$SRC"; fi
echo "===POSTARM462=== the activity between the fire and the pause (era dump, noisy cameras excluded)"
ARM_LINE=$(grep -n -e "f15arm" "$LOG" | head -1 | cut -d: -f1)
echo "arm at line $ARM_LINE"
if [ -n "$ARM_LINE" ]; then
  tail -n +$((ARM_LINE+1)) "$LOG" | grep -v -e "mvloop" -e "wedgespin" -e "f15stream" | head -40
fi
echo "===FN462=== fn 0x800465EC + cell 0x8007B540 in the source"
grep -n -e "800465EC" "$SRC" | head -6
grep -n -e "8007B540" "$SRC" | head -6
echo "===FUSE462=== the final era receipts (last 8 non-mvloop lines)"
grep -v -e "mvloop" -e "wedgespin" "$LOG" | tail -8
echo "===C462DONE=== the census receipts are in - the A22C-writer + wait-note decode drives the c463 fix"
