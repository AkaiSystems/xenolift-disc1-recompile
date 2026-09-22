#!/bin/bash
# c478_extract.sh - READ-ONLY CENSUS, NO RUN, NO BUILD,
# NO PATCH. The c477 decode: the park = THE LOADING
# SCREEN (the archive family reads FE14+F0C, prints the
# file, calls ArchiveGetFilePath), stuck at F0C=0x0e
# waiting for the file#14 INSTALL. The coordinator-zero
# disease is documented in-tree (R1141: start's BSS
# clear re-zeroes the module window; hardware's loader
# re-expands after) and xenolift_field_expand_all
# exists. HYPOTHESIS: the file#14 data is shelved
# (801dd680) but the UNPACK (260862 bytes) never ran
# this epoch. RECEIPTS: (1) UNPACK478: did the unpack
# run this epoch (log greps lzss/lzhle/260862/R1366/
# expand/fldfin); (2) EXPAND478: the R1141 continuation
# + expand_all (tree 1470-1570); (3) GPWRITER478: the
# gp-relative writer greps for F0C/FAEC in disc1.c;
# (4) MOUNTBODY478: the 92C0/92BC state-machine bodies.
# Fail-closed, tee'd to /tmp/c478_receipts.txt.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C478-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c478_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="d86f3deb57aed5b0921ab3a82867dea3a1e1d9960028e360bed8d9bdc90d45f8"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the R1387 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the R1387 tree)"
LOG="run.log"
if [ ! -s "$LOG" ]; then LOG="run.log.d"; fi
if [ ! -s "$LOG" ]; then echo "GATE-FAILED: no preserved run log"; exit 0; fi
echo "LOG=$LOG ($(wc -l < "$LOG" | tr -d " ") lines)"
D="disc1.c"
if [ ! -f "$D" ]; then echo "GATE-FAILED: disc1.c not found"; exit 0; fi
echo "===UNPACK478=== did the file#14 unpack run this epoch (the preserved c470 log)"
for TAG in "260862" "260,862" "LZHLE" "lzhle" "lzss-f" "lzss-x" "whole-member" "R1366" "field_expand" "expand_all" "fldfin" "fldreloc" "fvp"; do
  C=$(grep -c -e "$TAG" "$LOG" | tr -d " ")
  echo "$TAG: $C"
done
echo "--- the unpack/decode receipts (head 10):"
grep -n -e "260862" -e "LZHLE" -e "lzhle" -e "whole-member" "$LOG" | head -10
echo "--- the fvp + fldfin receipts (head 6):"
grep -n -e "\[fvp\]" -e "fldfin" "$LOG" | head -6
echo "--- the expand receipts (head 6):"
grep -n -e "field_expand" -e "expand_all" -e "fldreloc" "$LOG" | head -6
echo "===EXPAND478=== the R1141 continuation + the expand machinery (tree 1470-1570)"
sed -n "1470,1570p" "$SRC"
echo "===GPWRITER478=== the gp-relative F0C/FAEC accessors in the emitted source"
for OFF in "0x0D9C)" "0x0E7C)"; do
  C=$(grep -c -e "$OFF" "$D" | tr -d " ")
  echo "--- $OFF refs: $C"
  grep -n -e "$OFF" "$D" | head -8
done
for OFF in "0x0D9C)"; do
  RL=$(grep -n -e "$OFF" "$D" | head -1 | cut -d: -f1)
  if [ -n "$RL" ]; then echo "--- $OFF first ref in context (line $RL):"; sed -n "$((RL>14 ? RL-14 : 1)),$((RL+24))p" "$D" | head -40; fi
done
echo "===MOUNTBODY478=== the mount state-machine bodies (92C0/92BC contexts)"
RL=$(grep -n -e "0x92C0)" "$D" | head -1 | cut -d: -f1)
if [ -n "$RL" ]; then echo "--- first 0x92C0 ref in context (line $RL):"; sed -n "$((RL>14 ? RL-14 : 1)),$((RL+24))p" "$D" | head -40; fi
RL=$(grep -n -e "0x92BC)" "$D" | sed -n "2p" | cut -d: -f1)
if [ -n "$RL" ]; then echo "--- second 0x92BC ref in context (line $RL):"; sed -n "$((RL>14 ? RL-14 : 1)),$((RL+24))p" "$D" | head -40; fi
echo "===C478DONE=== the unpack census + expand machinery + writers are in - the c479 fix follows from these only"
