#!/bin/bash
# c371_lztail.sh - READ-ONLY. NO patch, NO run. The c370
# extraction: the guest LZSS core is decoding REAL file-14
# data (bytes landing inside the 260,862-byte expanded
# range, the module covering the coordinator region), the
# HLE decode block exists but its gate DECLINED (zero lzss-hle
# receipts), and the c235-proven R1320 zero-header exit is not
# firing in this era. THIS PASS: (1) the witness tail 9850-
# 10260 - did the decode complete, what exit shape reached the
# installer, what exactly faulted into exit 99; (2) the HLE
# gate sites (lzss_hle_src_saved references); (3) the R1320
# zero-header site and its gate.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C371-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="8d14ab4f2385a0004c28bd5a07bc762c5b9407b6da8a817d96554d5e91f226b0"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1365 tree - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1365 tree)"
echo "===TAIL371=== witness boot-1 lines 9850-10260, every 8th (decode tail, exit shape, the fault)"
WD="witness_c368_20260917_144156"
LOG="$WD/run.log"
[ -s "$LOG" ] || LOG="$WD/run.log.d"
if [ ! -s "$LOG" ]; then echo "WITNESS-MISSING"; exit 0; fi
awk 'NR>=9850 && NR<=10260 && (NR-9850)%8==0 { print NR": "$0 }' "$LOG"
echo "===EXITSHAPE371=== the exit-shape + install-chain receipts (r15/r14/base, kit door, firstfault)"
grep -n "exit chunk\|r14=\|clean exit\|install chain\|InstallModule\|firstfault\|GUEST-FAULT\|fault#" "$LOG" | awk -F: '$1>=9840 && $1<=10260' | head -14
echo "===ARUNDOWN371=== the decoder runaway receipts (read frontier, fence hits)"
grep -n "lzss-runaway\|fencelife\|inpast\|frontier" "$LOG" | awk -F: '$1>=9840 && $1<=10260' | head -10
echo "===HLEGATE371=== the HLE gate: every lzss_hle_src_saved / lzss-hle site"
grep -n "lzss_hle_src_saved\|lzss-hle\|lzss_hle_armed\|lzss_hle" "$SRC" | head -14
echo "===HLEBLOCK371=== the HLE decode gate block (find the armer, +-44 lines)"
LA=$(grep -n "lzss_hle_src_saved = r\[4\]" "$SRC" | head -1 | cut -d: -f1)
echo "ARMER_LINE=$LA"
if [ -n "$LA" ]; then
  S=$((LA-44)); [ $S -lt 1 ] && S=1
  E=$((LA+8))
  awk -v s="$S" -v e="$E" 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
fi
echo "===R1320371=== the zero-header exit site and its gate"
grep -n "zero-header\|R1320" "$SRC" | head -8
LZ=$(grep -n "R1320" "$SRC" | head -1 | cut -d: -f1)
echo "R1320_LINE=$LZ"
if [ -n "$LL" ] || [ -n "$LZ" ]; then
  S=$((LZ-30)); [ $S -lt 1 ] && S=1
  E=$((LZ+24))
  awk -v s="$S" -v e="$E" 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
fi
echo "===C371DONE=== the LZ tail + gate story is extracted"
