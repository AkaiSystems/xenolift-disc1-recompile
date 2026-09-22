#!/bin/bash
# c364_serveextract.sh - READ-ONLY: extract the model's
# sector-serve machinery to design R1365. The c363 receipts:
# the file#14 ReadN at 108933 (FDF8=125304 nonzero class) never
# served a sector in the new 800286CC park (the unpack then
# ran on the empty buffer -> firstfault door), while the f15
# class (FDF8=0) works (variant-B arm -> sector -> DATA
# HANDLER). THIS PASS: (a) the 'sector LBA loaded' serve site
# and its gating conditions; (b) the variant-B/fld2-int1 arm
# code (the working f15 path); (c) the zrf door's context
# conditions (the old file-14 stream door, context-locked to
# the dead park). NO patch, NO run.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C364-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="b6874d751e5c7e653f4052ea352ad3cc526c9dd1d50d2e173163169aaf54e92d"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1364 tree - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1364 tree)"
echo "===SERVESITE364=== the 'sector LBA loaded' print sites - line numbers"
grep -n "loaded into data FIFO" "$SRC" | head -6
LG=$(grep -n "loaded into data FIFO" "$SRC" | head -1 | cut -d: -f1)
echo "FIRST_SERVE_LINE=$LG"
if [ -n "$LG" ]; then
  S=$((LG-70)); [ $S -lt 1 ] && S=1
  E=$((LG+14))
  awk -v s="$S" -v e="$E" 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
fi
echo "===ALLSERVE364=== every serve-site context (all print sites +-8)"
for L in $(grep -n "loaded into data FIFO" "$SRC" | cut -d: -f1); do
  echo "--- serve site at line $L ---"
  S=$((L-8)); [ $S -lt 1 ] && S=1
  E=$((L+4))
  awk -v s="$S" -v e="$E" 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
done
echo "===VARB364=== the variant-B / fld2-int1 arm code (the working f15 path)"
LB=$(grep -n "R457 VARIANT-B ARM" "$SRC" | head -1 | cut -d: -f1)
echo "VARB_LINE=$LB"
if [ -n "$LB" ]; then
  S=$LB; E=$((LB+30))
  awk -v s="$S" -v e="$E" 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
fi
echo "===ZRF364=== the zrf door context conditions (the old file-14 stream door)"
LZ=$(grep -n "zm_served" "$SRC" | head -1 | cut -d: -f1)
echo "ZM_LINE=$LZ"
if [ -n "$LZ" ]; then
  S=$((LZ-40)); [ $S -lt 1 ] && S=1
  E=$((LZ+40))
  awk -v s="$S" -v e="$E" 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
fi
echo "===RDARM364=== the read-stream state setters (cd_read_active writers)"
grep -n "cd_read_active = " "$SRC" | head -14
echo "===F15ARM364=== how the f15 serve got armed: the witness receipts around the working serve (lines 9728-9760)"
WD="witness_c362_20260917_142426"
LOG="$WD/run.log"
[ -s "$LOG" ] || LOG="$WD/run.log.d"
if [ -s "$LOG" ]; then
  awk -F: '$1>=9700 && $1<=9770' "$LOG" | grep "fld2\|fld2sig\|sector LBA\|DATA HANDLER\|actchg\|arm" | head -14
  echo "--- arm-related receipts whole-run ---"
  grep -c "fld2-int1\|variant-B" "$LOG"
  grep -n "fld2-int1\|variant-B" "$LOG" | head -6
fi
echo "===C364DONE=== the serve-machinery story is extracted"
