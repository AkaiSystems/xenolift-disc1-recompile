#!/bin/bash
# c486_extract.sh - READ-ONLY CENSUS, NO RUN, NO BUILD,
# NO PATCH. The c485 decode: the movie module's code
# EXECUTED past its entry (real init: cell stores, GPU
# rect setup via helper 800439E0, a table walk at
# 8009A2E0, GPU packets to a garbage dest 0x8249D520),
# then jumped to 0x8009A2F8 - an EMITTED label the
# DISPATCHER failed to resolve (the overlay-identity
# class: module load success does not prove indirect
# calls select the right translation). RECEIPTS:
# (1) CONTAIN486: the function containing
# L_8009A2E0/L_8009A2F8 + the label context; (2)
# RESOLVE486: the dispatcher's native-resolution core
# (how a jump address maps to a native fn); (3) VT486:
# the vtcell vtable read story; (4) WDEST486: the
# garbage-dest provenance; (5) PREFB486: the raw
# pre-fallback sequence (29975-30007). Fail-closed,
# tee'd to /tmp/c486_receipts.txt.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C486-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c486_receipts.txt) 2>&1
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
echo "===CONTAIN486=== the function containing L_8009A2E0 / L_8009A2F8"
LN=$(grep -n -e "L_8009A2E0:;" "$D" | head -1 | cut -d: -f1)
echo "L_8009A2E0 at line $LN"
if [ -n "$LN" ]; then
  awk -v N="$LN" 'NR<=N && /---------- 0x/ {last=NR": "$0} NR==N {print "CONTAINING FN MARKER: "last; exit}' "$D"
  echo "--- the label context (lines $((LN>30 ? LN-30 : 1))..$((LN+60))):"
  sed -n "$((LN>30 ? LN-30 : 1)),$((LN+60))p" "$D" | head -92
fi
echo "===RESOLVE486=== the dispatcher native-resolution core (how a jump address maps to a native fn)"
sed -n "23740,23800p" "$SRC" | head -62
echo "--- the resolution lookup mechanism (the fn map):"
grep -n -e "xenolift_fn_for_addr" -e "fn_for_addr" -e "addr_to_fn" -e "native_for" "$SRC" | head -8
echo "===VT486=== the vtcell vtable read story (all eras)"
grep -c -e "vtcell" "$LOG" | tr -d " " | sed "s/^/vtcell count: /"
grep -n -e "vtcell" "$LOG" | head -12
echo "===WDEST486=== the garbage-dest provenance (0x8249D520)"
grep -c -e "8249D5" "$LOG" | tr -d " " | sed "s/^/8249D5 writes: /"
grep -n -e "8249D5" "$LOG" | head -8
echo "--- any receipt naming the dest's computation:"
grep -n -e "8249D4" -e "8249D520" "$LOG" | head -8
echo "===PREFB486=== the raw pre-fallback sequence (log 29970-30008)"
awk 'NR>=29970 && NR<=30008 { print NR": "$0 }' "$LOG"
echo "===C486DONE=== the containing fn + resolution core + pre-fallback sequence are in - the fix design follows from these only"
