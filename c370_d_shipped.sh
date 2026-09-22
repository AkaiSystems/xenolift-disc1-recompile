#!/bin/bash
# c370_hlegate.sh - READ-ONLY extraction. NO patch, NO run.
# The c369 receipts: the file-14 read COMPLETED natively
# (62 sectors, FDF8=0, head advance, game moved to f15) but
# the unpack faulted on REAL bytes: dest==payload-start
# (8-byte member header stripped) so the guest decoder read
# word0=FFFF9C30 (the payload's first word) as the expanded
# size -> backward computed exit -> walked off 2MB RAM ->
# firstfault door. The member header file[0:4]=0003FAFE=
# 260,862 = the expanded size c235 receipted the HLE native
# decoder (line 14431) unpacking successfully; c233 receipted
# it now SKIPPING. THIS PASS: (1) the line-14431 HLE gate and
# its skip conditions; (2) the defib6/header-strip site;
# (3) the disc bytes at LBA 108933 (header sanity).
set -u
cd "$HOME/Downloads/xenolift" || { echo "C370-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="8d14ab4f2385a0004c28bd5a07bc762c5b9407b6da8a817d96554d5e91f226b0"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1365 tree - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1365 tree)"
echo "===HLEGATE370=== the HLE native decoder gate at line 14431 (+-60 lines)"
awk 'NR>=14371 && NR<=14491 { print NR": "$0 }' "$SRC"
echo "===SKIPRC370=== what the gate checks - the skip-receipt print sites"
grep -n "skipped" "$SRC" | head -10
echo "===HDRSTRIP370=== the header-strip / 8-byte sites (defib6 carry + reshtail)"
grep -n "R1296\|reshtail" "$SRC" | head -6
LR=$(grep -n "reshtail" "$SRC" | head -1 | cut -d: -f1)
if [ -n "$LR" ]; then
  S=$((LR-30)); [ $S -lt 1 ] && S=1
  E=$((LR+10))
  awk -v s="$S" -v e="$E" 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
fi
echo "===CARRY370=== the defib6 carry PROMOTE site (R489)"
LC=$(grep -n "carry PROMOTE" "$SRC" | head -1 | cut -d: -f1)
echo "CARRY_LINE=$LC"
if [ -n "$LC" ]; then
  S=$((LC-50)); [ $S -lt 1 ] && S=1
  E=$((LC+20))
  awk -v s="$S" -v e="$E" 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
fi
echo "===DISC370=== the model disc bytes at LBA 108933 (header sanity: does the member header live there?)"
grep -n "disc_read_lba" "$SRC" | head -4
echo "===UNPACKW370=== the [unpackw] camera site (a0/a1 semantics)"
LU=$(grep -n "unpackw" "$SRC" | head -1 | cut -d: -f1)
echo "UNPACKW_LINE=$LU"
if [ -n "$LU" ]; then
  S=$((LU-20)); [ $S -lt 1 ] && S=1
  E=$((LU+14))
  awk -v s="$S" -v e="$E" 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
fi
echo "===LZSST370=== the lzss-t tracer site (word0/computed_exit semantics)"
LT=$(grep -n "computed_exit" "$SRC" | head -1 | cut -d: -f1)
echo "LZSST_LINE=$LT"
if [ -n "$LT" ]; then
  S=$((LT-40)); [ $S -lt 1 ] && S=1
  E=$((LT+14))
  awk -v s="$S" -v e="$E" 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
fi
echo "===WITNESS370=== the HLE-skip receipts in the c368 witness"
WD="witness_c368_20260917_144156"
LOG="$WD/run.log"
[ -s "$LOG" ] || LOG="$WD/run.log.d"
if [ -s "$LOG" ]; then
  grep -n "HLE\|hle-decode\|native decoder\|skip" "$LOG" | grep -i "lzss\|unpack\|file-14\|14431\|HLE" | head -8
  echo "--- the unpack/lzss-t receipts around 9839-9849 ---"
  awk 'NR>=9835 && NR<=9852 { print NR": "$0 }' "$LOG"
fi
echo "===C370DONE=== the HLE-gate story is extracted"
