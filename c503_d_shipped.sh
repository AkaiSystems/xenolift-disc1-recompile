#!/bin/bash
# c503_extract.sh - READ-ONLY PROBE, NO RUN, NO BUILD, NO
# PATCH, NO ARTIFACT MODIFICATION. The c502 refusal
# receipted three facts: (1) the R321/R322 trampolines are
# DEAD historical artifacts - run.sh's R323 region: "disc1.c
# trampoline is REMOVED: restore pristine xenolift_dispatch";
# (2) the LIVE dispatcher is the PRISTINE one in disc1.c
# (the c501 tree-wide grep excluded it); (3) the GTE
# compute call = hle_gte_execute(word) at the COP2 region
# line 91 (the strict (w) extraction correctly refused it).
# ONE QUESTION decides the splice's DURABLE SITE: does
# run.sh's R323 patcher REWRITE disc1.c's dispatcher span
# at every build (guard goes into run.sh's pristine
# template, emit-durable), or is it a no-op today (disc1.c
# itself is the site)? THIS PROBE receipts: (1) run.sh's
# R323 region in full + whether it writes disc1.c each
# build; (2) disc1.c's dispatcher definition shape + span
# markers; (3) the OBJS/compile source list (which .c
# files are live in the build); (4) the tramp-marker check
# in disc1.c. Fail-closed, tee'd to /tmp/c503_receipts.txt.
# Pure-ASCII output.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C503-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c503_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="4342a7391696a99bdc7745ca697c9ec29ddcd3bf384ef5a2813d79644addcc9f"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the c497 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the c497 tree; both c502 files restored)"
echo "===R323503=== run.sh's R323 region in full (does it rewrite disc1.c each build?)"
sed -n "280,350p" run.sh
echo "===DISC503=== disc1.c's dispatcher definition + span markers"
grep -n -e "xenolift_dispatch" disc1.c | head -20
echo "--- the definition context:"
L=$(grep -n -e "^void xenolift_dispatch" disc1.c | head -1 | cut -d: -f1)
if [ -n "$L" ]; then
  echo "definition at line $L"
  sed -n "$((L-4)),$((L+24))p" disc1.c
else
  echo "no column-0 definition; searching wider:"
  grep -n -e "xenolift_dispatch(uint32_t" disc1.c | head -6
  for CL in $(grep -n -e "xenolift_dispatch(uint32_t" disc1.c | cut -d: -f1 | head -4); do
    echo "--- context at disc1.c line $CL:"
    sed -n "$((CL-2)),$((CL+14))p" disc1.c
  done
fi
echo "--- trampoline span markers in disc1.c (R321/R322 era):"
grep -n -e "xenolift_sm_" -e "SM-TRAMPOLINE" disc1.c | head -8
echo "===OBJS503=== the compile source list (which .c files are live)"
grep -n -e "OBJS=" run.sh | head -4
grep -n -e "^ *for .*\.c" run.sh | head -6
sed -n "1040,1060p" run.sh
echo "===EMIT503=== is disc1.c regenerated per build? (the emit gate)"
grep -n -e "xenolift " -e "cargo " run.sh | head -10
grep -n -e "\.run\.md5" run.sh | head -6
echo "--- disc1.c sha + size now:"
shasum -a 256 disc1.c | cut -d" " -f1
wc -l < disc1.c | tr -d " " | sed "s/^/disc1.c lines: /"
echo "===C503DONE=== the durable splice site is receipted - the c504 splice follows from these receipts only - digest is pure ASCII"
