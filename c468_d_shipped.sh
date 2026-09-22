#!/bin/bash
# c468_extract.sh - READ-ONLY EXTRACTION, NO RUN, NO
# BUILD, NO PATCH. The c467 verdict: the announcement
# STILL never posted - the watcher's HOST SITE goes
# cold after the arm (the R1381 block lives in the
# f15-wait loop; the arm's bell unblocks that very
# loop; f15near printed only #1 then silence, while
# other camera families stayed hot). RECEIPTS:
# (1) HOST468: the R1381 block's host site + its
# post-arm print census; (2) REQHOOK468: the [req]
# FDF8 write-hook shape - the re-home target for the
# announcement (fire at the drain's own FDF8->0
# write); (3) MVHOST468: the mvloop camera's host as
# an alternate; (4) SPINFAMILY468: the emitted disc1.c
# bodies of the spin family - the park loop's ACTUAL
# exit condition. Fail-closed, tee'd to
# /tmp/c468_receipts.txt.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C468-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c468_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="01b37d7c7252f8a29650cf8f0a27875a0ef1ea15dc62870a55417a77b194daa6"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the R1386 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the R1386 tree)"
LOG="run.log"
region() {
  LN=$1; WIDE=$2; TAG=$3
  echo "--- $TAG (line $LN, +- $WIDE):"
  S=$((LN>WIDE+1 ? LN-WIDE : 1)); E=$((LN+WIDE))
  sed -n "${S},${E}p" "$SRC"
}
echo "===HOST468=== the R1381 block host site"
LN=$(grep -n -e "R1381 (c451 receipts)" "$SRC" | head -1 | cut -d: -f1)
echo "R1381 block marker at line $LN"
if [ -n "$LN" ]; then region "$LN" 45 "the R1381 block + its host context"; fi
echo "--- the block-adjacent markers (which cameras live in the same host):"
grep -n -e "f15near" -e "f15arm" -e "R1382" "$SRC" | head -12
echo "--- the post-arm print census (did ANY block camera print after the arm?):"
AL=$(grep -n -e "f15arm. R1384" "$LOG" | head -1 | cut -d: -f1)
echo "arm at log line $AL"
if [ -n "$AL" ]; then
  echo "f15near total in log: $(grep -c -e "f15near" "$LOG" | tr -d " ")"
  echo "--- block prints after the arm (expect none - the host went cold):"
  tail -n +$((AL+1)) "$LOG" | grep -n -e "f15near" -e "f15arm" -e "f15post" | head -4
fi
echo "===REQHOOK468=== the [req] FDF8 write-hook shape (the re-home target)"
LN=$(grep -n -e "req. FDF8" "$SRC" | head -1 | cut -d: -f1)
echo "[req] print at line $LN"
if [ -n "$LN" ]; then region "$LN" 35 "the FDF8 write-hook camera + its host"; fi
echo "===MVHOST468=== the mvloop camera host (alternate)"
LN=$(grep -n -e "mvloop. pre-movie" "$SRC" | head -1 | cut -d: -f1)
echo "mvloop print at line $LN"
if [ -n "$LN" ]; then region "$LN" 20 "the mvloop camera host context"; fi
echo "===SPINFAMILY468=== the emitted disc1.c spin-family bodies (the park loop exit decode)"
D=$(find . -maxdepth 4 -name "disc1.c" -not -path "./worktrees/*" 2>/dev/null | head -3)
echo "disc1.c candidates: $D"
for F in $D; do
  echo "--- file: $F ($(wc -l < "$F" | tr -d " ") lines)"
  for FN in "800465EC" "800366F0" "800370DC"; do
    HL=$(grep -n -e "$FN" "$F" | head -2)
    echo "--- $FN hits: $HL"
    FL=$(echo "$HL" | head -1 | cut -d: -f1)
    if [ -n "$FL" ]; then
      FS=$((FL>1 ? FL-1 : 1)); FE=$((FL+50))
      sed -n "${FS},${FE}p" "$F" | head -52
    fi
  done
done
echo "===C468DONE=== the host + write-hook + spin-family receipts are in - the c469 re-home follows from these only"
