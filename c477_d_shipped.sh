#!/bin/bash
# c477_extract.sh - READ-ONLY DECODE, NO RUN, NO BUILD,
# NO PATCH. The c476 verdict: NO phase ever entered
# ([phasecb] all boot-era SKIP-POLL; [rlgl] ZERO =
# RunResidentGameLoop never ran), and the MEMBER-14
# MODULE INSTALL IS FROZEN MID-WALK (fldfrz2 identical
# t=81..156s: FAEC=0, F0C=0x0e, q14=1), leaving the
# FIELD coordinator entry (80077E88) ZEROED ([cbmod])
# - no phase can ever dispatch. RECEIPTS: (1)
# WALKER477: the emitted install-walker code via
# offset greps (0x9F0C/0x9F10/0x9F14/0x9F18) - what
# advances F0C past member-14; (2) FAEC477: the walker
# latch readers/clearers (0x9FAEC); (3) MOUNT477: the
# mount state machine fns (0x92C0/0x92BC/0x92D0/
# 0x92C8); (4) COORD477: the runtime coordinator
# machinery (tree 1370-1470); (5) CENSUS477: the R636
# census host site. Fail-closed, tee'd to
# /tmp/c477_receipts.txt.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C477-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c477_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="d86f3deb57aed5b0921ab3a82867dea3a1e1d9960028e360bed8d9bdc90d45f8"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the R1387 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the R1387 tree)"
D="disc1.c"
if [ ! -f "$D" ]; then echo "GATE-FAILED: disc1.c not found"; exit 0; fi
echo "===WALKER477=== the install-walker cells in the emitted source"
for OFF in "0x9F0C)" "0x9F10)" "0x9F14)" "0x9F18)"; do
  C=$(grep -c -e "$OFF" "$D" | tr -d " ")
  echo "--- $OFF refs: $C"
  grep -n -e "$OFF" "$D" | head -6
done
for OFF in "0x9F0C)" "0x9F14)"; do
  RL=$(grep -n -e "$OFF" "$D" | head -1 | cut -d: -f1)
  if [ -n "$RL" ]; then
    echo "--- $OFF first ref in context (line $RL):"
    sed -n "$((RL>14 ? RL-14 : 1)),$((RL+24))p" "$D" | head -40
  fi
done
echo "===FAEC477=== the walker latch (0x9FAEC) readers/writers in the emitted source"
C=$(grep -c -e "0x9FAEC)" "$D" | tr -d " ")
echo "0x9FAEC refs: $C"
grep -n -e "0x9FAEC)" "$D" | head -8
RL=$(grep -n -e "0x9FAEC)" "$D" | head -1 | cut -d: -f1)
if [ -n "$RL" ]; then echo "--- first ref in context (line $RL):"; sed -n "$((RL>14 ? RL-14 : 1)),$((RL+24))p" "$D" | head -40; fi
echo "===MOUNT477=== the mount state-machine fns in the emitted source"
for OFF in "0x92C0)" "0x92BC)" "0x92D0)" "0x92C8)"; do
  C=$(grep -c -e "$OFF" "$D" | tr -d " ")
  echo "--- $OFF refs: $C"
  grep -n -e "$OFF" "$D" | head -5
done
echo "===COORD477=== the runtime coordinator machinery (tree 1370-1470)"
sed -n "1370,1470p" "$SRC"
echo "===CENSUS477=== the R636 census host site"
grep -n -e "census. R636" "$SRC" | head -3
RL=$(grep -n -e "census. R636" "$SRC" | head -1 | cut -d: -f1)
if [ -n "$RL" ]; then echo "--- census print site (line $RL, context):"; sed -n "$((RL>30 ? RL-30 : 1)),$((RL+10))p" "$SRC" | head -42; fi
echo "===C477DONE=== the install-walker code + coordinator machinery are in - the c478 fix follows from these only"
