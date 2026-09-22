#!/bin/bash
# c473_extract.sh - READ-ONLY DECODE, NO RUN, NO BUILD,
# NO PATCH. The c472 receipts: the park text page is
# the TITLE/ATTRACT screen - the state chain is
# 0x80077028 -> sets 0x80077014 = 5 = movie start
# (the .bak1304 historical decode: the countdown
# oscillated 5->4->3->5, 'real hardware had a
# human'). The current cell is FROZEN at 0x03FF7F14
# (garbage) - the chain never ran. The game code
# accesses the cells via base<<16+offset, NOT D_
# symbols. RECEIPTS: (1) PAT473: the offset-pattern
# greps in disc1.c (the game's own state-chain code);
# (2) CUR473: current-runtime.c refs to the state
# cells (baks excluded); (3) HIST473: the .bak1304
# historical decode regions. Fail-closed, tee'd to
# /tmp/c473_receipts.txt.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C473-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c473_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="d86f3deb57aed5b0921ab3a82867dea3a1e1d9960028e360bed8d9bdc90d45f8"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the R1387 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the R1387 tree)"
D="disc1.c"
if [ ! -f "$D" ]; then echo "GATE-FAILED: disc1.c not found"; exit 0; fi
echo "===PAT473=== the offset-pattern greps (the game's own state-chain code)"
echo "--- all 0x8007-base loads (the family working in the 0x8007XXXX region):"
grep -c -e "0x8007u << 16" "$D"
echo "--- 0x7014) hits (offset of the state cell):"
grep -n -e "0x7014)" "$D" | head -14
echo "--- 0x7028) hits (the upstream gate cell):"
grep -n -e "0x7028)" "$D" | head -14
echo "--- 0x6F04) hits (the cnt sibling):"
grep -n -e "0x6F04)" "$D" | head -10
echo "--- context of the first 0x7014) hit:"
RL=$(grep -n -e "0x7014)" "$D" | head -1 | cut -d: -f1)
if [ -n "$RL" ]; then sed -n "$((RL>16 ? RL-16 : 1)),$((RL+26))p" "$D" | head -44; fi
echo "--- context of the first 0x7028) hit:"
RL=$(grep -n -e "0x7028)" "$D" | head -1 | cut -d: -f1)
if [ -n "$RL" ]; then sed -n "$((RL>16 ? RL-16 : 1)),$((RL+26))p" "$D" | head -44; fi
echo "===CUR473=== the current runtime.c state-cell refs (baks excluded)"
grep -n -e "0x80077014" "$SRC" | head -8
grep -n -e "0x80077028" "$SRC" | head -8
grep -n -e "0x80076F04" "$SRC" | head -8
echo "===HIST473=== the .bak1304 historical decode regions"
BAK="runtime/runtime.c.bak1304"
if [ -f "$BAK" ]; then
  echo "--- the countdown comments (6320-6380):"
  sed -n "6320,6380p" "$BAK"
  echo "--- the R474-era checks (14800-14940):"
  sed -n "14800,14940p" "$BAK" | head -120
  echo "--- the state-chain comment (18030-18085):"
  sed -n "18030,18085p" "$BAK"
else
  echo "bak1304 not found"
fi
echo "===C473DONE=== the state-chain code + historical decode are in - the c474 fix follows from these only"
