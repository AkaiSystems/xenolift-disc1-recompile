#!/bin/bash
# c472_extract.sh - READ-ONLY DECODE, NO RUN, NO BUILD,
# NO PATCH. The c471 receipts: 0x800465EC exonerated
# (DMA-pointer init, no loop), the 0x8007B540 table
# hypothesis RETIRED (zero static refs anywhere), the
# loop family = the font pipeline (text page). NEW
# LEAD: the R894 SLICE-GATE cells - 0x80077014
# (cntdn=03FF7F14 FROZEN across the park) and
# 0x80076F04 (cnt), read by 0x800317E0. RECEIPTS:
# (1) SLICE472: D_80077014/D_80076F04 refs in the
# emitted disc1.c - the game's own slice-gate code
# (who reads/writes/decrements); (2) RTDIR472: the
# runtime/ directory census - which file hosts the
# [req]/[wedgespin] cameras and any 0x80077014 refs;
# (3) BODY472: the 0x800317E0 body (the slice-gate
# reader) + the 0x800459DC body. Fail-closed, tee'd
# to /tmp/c472_receipts.txt.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C472-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c472_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="d86f3deb57aed5b0921ab3a82867dea3a1e1d9960028e360bed8d9bdc90d45f8"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the R1387 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the R1387 tree)"
D="disc1.c"
if [ ! -f "$D" ]; then echo "GATE-FAILED: disc1.c not found"; exit 0; fi
echo "===SLICE472=== the slice-gate cells in the emitted source (the game's own code)"
echo "--- D_80077014 refs:"
grep -n -e "D_80077014" "$D" | head -12
echo "--- D_80076F04 refs:"
grep -n -e "D_80076F04" "$D" | head -12
for CELL in "D_80077014" "D_80076F04"; do
  RL=$(grep -n -e "$CELL" "$D" | head -1 | cut -d: -f1)
  if [ -n "$RL" ]; then
    echo "--- $CELL first ref in context (line $RL):"
    sed -n "$((RL>10 ? RL-10 : 1)),$((RL+18))p" "$D" | head -30
  fi
done
echo "===RTDIR472=== the runtime/ directory census (which files exist + who hosts the wedge/req cameras)"
ls runtime/*.c 2>/dev/null | head -20
echo "--- files containing the wedgespin tag:"
grep -rln "wedgespin" runtime/ | head -6
echo "--- files containing the req-tag print:"
grep -rln "req. FDF8" runtime/ | head -6
echo "--- any runtime/ file referencing the slice-gate cells:"
grep -rn "0x80077014" runtime/ | head -8
echo "===BODY472=== the slice-gate reader + the last loop-id"
for FN in "0x800317E0" "0x800459DC"; do
  echo "--- $FN body:"
  LN=$(grep -n -e "$FN (function)" "$D" | head -1 | cut -d: -f1)
  if [ -z "$LN" ]; then echo "marker not found for $FN"; continue; fi
  echo "(marker at line $LN)"
  sed -n "${LN},$((LN+60))p" "$D" | head -62
done
echo "===C472DONE=== the slice-gate + runtime-dir receipts are in - the c473 fix follows from these only"
