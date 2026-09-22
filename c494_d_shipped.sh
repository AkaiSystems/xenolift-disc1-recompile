#!/bin/bash
# c494_extract.sh - READ-ONLY CENSUS, NO RUN, NO BUILD,
# NO PATCH. The c493 result: the R1392 camera compiled
# and ran but printed ZERO receipts including no arm -
# the check call sits after `xenolift_cur_fn = sv_fn;`
# (line 5127) which is NOT on the module-window dispatch
# path ([mod6] receipts prove 0x800737EC dispatched).
# PLACEMENT-CLASS MISS. THIS CENSUS finds the TRUE
# dispatch site: (1) SITES494: every xenolift_cur_fn
# write site with context; (2) MACRO494: the DISPATCH
# macro definition + the dispatcher function it expands
# to; (3) MOD6494: the [mod6]/[ovlcb]/R680 camera sites -
# all receipted ON the overlay dispatch path - with
# their enclosing function heads; (4) CORRELATE494:
# which write site the cameras sit in. Fail-closed, tee'd
# to /tmp/c494_receipts.txt. Pure-ASCII output.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C494-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c494_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="40f0659d5039304fcb339df327a09327deecbc7c082e2ab8055d64e7bd43955e"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the c493 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the c493 tree carrying R1392)"
echo "===SITES494=== every xenolift_cur_fn write site with context"
grep -n "xenolift_cur_fn = " "$SRC" | grep -v "==" | cut -d: -f1 > /tmp/c494_setters.txt
echo "setter count: $(wc -l < /tmp/c494_setters.txt | tr -d ' ')"
while read -r L; do
  echo "--- line $L:"
  sed -n "$(( L > 2 ? L - 2 : 1 )),$((L+2))p" "$SRC"
done < /tmp/c494_setters.txt
echo "===ALLREF494=== every xenolift_cur_fn reference (reads + writes)"
grep -n "xenolift_cur_fn" "$SRC" | head -30
echo "===MACRO494=== the DISPATCH macro + the dispatcher it expands to"
grep -rn -e "define DISPATCH" runtime/ src/ 2>/dev/null | head -4
M=$(grep -rn -e "define DISPATCH" runtime/ 2>/dev/null | head -1 | cut -d: -f2)
if [ -n "$M" ]; then echo "--- the macro at $M:"; fi
for F in runtime/xenolift_runtime.h runtime/runtime.h; do
  if [ -f "$F" ]; then grep -n -e "DISPATCH" "$F" | head -8; fi
done
echo "--- dispatcher-function candidates:"
grep -n -e "xenolift_dispatch" runtime/*.h "$SRC" 2>/dev/null | head -8
echo "===MOD6494=== the receipted overlay-dispatch camera sites"
echo "--- the [mod6] site:"
L6=$(grep -n -e "MODULE 6 ENTRY" "$SRC" | head -1 | cut -d: -f1)
echo "line $L6"
if [ -n "$L6" ]; then sed -n "$(( L6 > 8 ? L6 - 8 : 1 )),$((L6+4))p" "$SRC"; fi
echo "--- the [ovlcb] site:"
LO=$(grep -n -e "overlay fn 0x" "$SRC" | head -1 | cut -d: -f1)
echo "line $LO"
if [ -n "$LO" ]; then sed -n "$(( LO > 8 ? LO - 8 : 1 )),$((LO+4))p" "$SRC"; fi
echo "--- the R680 wildctx site:"
LW=$(grep -n -e "unresolved jump" "$SRC" | head -1 | cut -d: -f1)
echo "line $LW"
if [ -n "$LW" ]; then sed -n "$(( LW > 8 ? LW - 8 : 1 )),$((LW+4))p" "$SRC"; fi
echo "===ENCLOS494=== the enclosing function heads for those sites"
for L in "$L6" "$LO" "$LW"; do
  if [ -n "$L" ]; then
    H=$(awk -v A="$L" 'NR<=A && /^static|^void|^int|^unsigned|^uint/ { last = NR": "$0 } END { print last }' "$SRC")
    echo "site line $L <- enclosing: $H"
  fi
done
echo "===LOG494=== this run's dispatch receipts (correlation anchors)"
LOG="run.log"
if [ ! -s "$LOG" ]; then LOG="run.log.d"; fi
grep -n -e "MODULE 6 ENTRY" "$LOG" | head -4
grep -n -e "overlay fn 0x800737EC" "$LOG" | head -4
grep -n -e "wildctx" "$LOG" | head -4
echo "===C494DONE=== the true dispatch site is named by the correlation - digest is pure ASCII"
