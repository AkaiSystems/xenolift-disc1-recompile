#!/bin/bash
# c280_dispatcher_decode2.sh - READ-ONLY: the def-anchored, secret-
# safe static decode of the dispatcher family.
# THE c279 LESSONS (both fixed here): (1) the dump anchored on the
# disc1.c FORWARD PROTOTYPE block (lines 2472-2474) instead of the
# definitions - the real xenolift_fn_8004B55C def is at line 151346,
# dispatched via case 0x8004B55Cu: at 1016553 + a fallthrough at
# 151340; anchor with ^static void xenolift_fn_XXX(void)$ (no
# trailing semicolon). (2) the platform secret-scanner REDACTED ~184
# digest lines from the raw disc1.c prototype region - so this dump
# prints only curated fn bodies with long tokens truncated (>33
# chars -> [T]) and lines capped at 110 chars.
# THE TARGET: the dispatcher chain 8004B54C -> 8004B55C -> 8004B694
# that fed the LZSS wrapper (0x80032EB4) a garbage source
# (0x00200000 = the heap free-sentinel flags value; struct-field
# read, NOT a live heap walk - the fault window has no carve
# receipts). Name the EXACT cell the body reads as the unpack
# source, then design the c281 fix. No patch, no compile, no run.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C280-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="0cc8f8599ef2adcef29ac528864d80eb217a4c8c2a9e597c69b3b435e4982907"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1332 tree 0cc8f859 - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1332 tree, unchanged)"
DCA="./disc1.c"
DEXPECT="3d78b0e783c9038fa7213ed29bce1d5db9453e6885bac3845bde6369c6338741"
if [ ! -s "$DCA" ]; then echo "C280-FAILED: disc1.c missing"; exit 1; fi
DS=$(shasum -a 256 "$DCA" | cut -d" " -f1)
echo "DISC1_SHA=$DS"
if [ "$DS" != "$DEXPECT" ]; then echo "GATE-FAILED: disc1.c is not the fresh 3d78b0e7 emission - refusing a stale decode"; exit 0; fi
echo "DISC1_VERIFIED (fresh emission, Sep 17 07:06)"

trunc() { sed -E 's/[A-Za-z0-9_./+-]{34,}/[T]/g' | cut -c1-110; }

fnbody() {
  FN="$1"; MAXL="${2:-80}"
  L=$(grep -n "^static void xenolift_fn_${FN}(void)$" "$DCA" | head -1 | cut -d: -f1)
  echo "===FN_${FN} (def line $L)==="
  if [ -n "$L" ] && [ "$L" -gt 0 ] 2>/dev/null; then
    awk -v s="$L" -v m="$MAXL" 'NR>=s{print; if($0 ~ /^}/) exit; c++; if(c>=m){print "...(capped)"; exit}}' "$DCA" | trunc
  else
    echo "FN DEF NOT FOUND"
  fi
}

echo "===BODIES280=== the dispatcher chain + the LZSS wrapper (def-anchored, token-truncated)"
fnbody 8004B54C 60
fnbody 8004B55C 90
fnbody 8004B694 90
fnbody 80032E88 50

echo "===CALLSITE280=== the fallthrough caller at 151340 (who enters 8004B55C)"
sed -n '151300,151345p' "$DCA" | trunc
echo "===SWITCH280=== the dispatch case at 1016553"
sed -n '1016540,1016560p' "$DCA" | trunc

echo "===C280DONE=== def-anchored decode complete - the c281 fix design comes from these receipts"
