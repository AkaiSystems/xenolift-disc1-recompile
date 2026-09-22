#!/bin/bash
# c501_extract.sh - READ-ONLY PROBE, NO RUN, NO BUILD, NO
# PATCH, NO ARTIFACT MODIFICATION. The c500 locator named
# the landscape: runtime.c has NO dispatch definition (only
# calls/comments; the g_guest_depth-filtered print showed 6
# lines), and runtime/*.c beyond runtime.c have no
# xenolift_dispatch either. THE DEFINITION IS SOMEWHERE
# ELSE: either a runtime.c one-liner on a line the
# g_guest_depth filter wrongly skipped, or a header
# definition (xenolift_runtime.h declares it; if it also
# DEFINES it inline, every TU gets its own copy and the
# guard's linkage must be extern). THIS PROBE prints the
# TRUE SHAPE unfiltered: (1) every xenolift_dispatch line
# in runtime.c (UNFILTERED); (2) tree-wide across .c/.h
# excluding the emitted disc1.c and build dirs; (3) the
# header's dispatch region + the DISPATCH macro contract;
# (4) hle/ if it references it. Fail-closed, tee'd to
# /tmp/c501_receipts.txt. Pure-ASCII output.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C501-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c501_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="4342a7391696a99bdc7745ca697c9ec29ddcd3bf384ef5a2813d79644addcc9f"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the c497 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the c497 tree with the working guard)"
echo "===COUNT501=== every xenolift_dispatch line in runtime.c, UNFILTERED"
C=$(grep -c -e "xenolift_dispatch" "$SRC" | tr -d " ")
echo "unfiltered count: $C"
grep -n -e "xenolift_dispatch" "$SRC" | head -40
echo "===TREE501=== tree-wide search (.c/.h, excluding the emitted disc1.c and build dirs)"
grep -rn --include="*.c" --include="*.h" -e "xenolift_dispatch" . 2>/dev/null | grep -v -e "disc1.c:" | grep -v -e "target/" | head -40
echo "===HEADER501=== the header's dispatch region + the DISPATCH macro contract"
HDR="runtime/xenolift_runtime.h"
if [ -f "$HDR" ]; then
  grep -n -e "xenolift_dispatch" "$HDR"
  for L in $(grep -n -e "xenolift_dispatch" "$HDR" | cut -d: -f1); do
    echo "--- context around header line $L:"
    sed -n "$(( L > 12 ? L - 12 : 1 )),$((L+14))p" "$HDR"
  done
  echo "--- the DISPATCH macro:"
  grep -n -e "define DISPATCH" "$HDR"
  L=$(grep -n -e "define DISPATCH" "$HDR" | head -1 | cut -d: -f1)
  if [ -n "$L" ]; then sed -n "$((L-2)),$((L+6))p" "$HDR"; fi
else
  echo "header not found at $HDR - listing runtime/:"
  ls -la runtime/ | head -12
fi
echo "===HLE501=== hle/ references"
if [ -d hle ]; then grep -rn -e "xenolift_dispatch" hle/ 2>/dev/null | head -10; else echo "no hle/ dir"; fi
echo "===C501DONE=== the true definition shape is receipted - the c502 splice follows from these receipts only - digest is pure ASCII"
