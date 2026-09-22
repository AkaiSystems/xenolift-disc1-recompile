#!/bin/bash
# c281_vsync_faultsite.sh - READ-ONLY: the rest of the Vsync helper
# (the fault site), the v_wait + LZSS defs, the vsync-cell writers,
# and the R696 guard's classification logic.
# THE c280 DECODE: 8004B54C = Vsync, 8004B694 = v_wait (PSYQ libetc
# chain - the c217b sound-heap label was a stale-stack misread).
# The helper 8004B55C double-dereferences cell 0x8005783C, and the
# fault-era r31=8004B5E4 is INSIDE the helper body (+0x88) - the
# computed 0x00200000 (the heap terminator flags value) forms PAST
# L_8004B59C, which is not yet dumped. Anchor fix: defs carry name
# suffixes (_Vsync, _v_wait) - prefix-anchor, not (void)$.
# THE GOAL: the exact instruction + cell that turns 0x00200000 into
# an address, then the c282 fix design. No patch, no compile, no
# run.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C281-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="0cc8f8599ef2adcef29ac528864d80eb217a4c8c2a9e597c69b3b435e4982907"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1332 tree 0cc8f859 - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1332 tree, unchanged)"
DCA="./disc1.c"
DEXPECT="3d78b0e783c9038fa7213ed29bce1d5db9453e6885bac3845bde6369c6338741"
DS=$(shasum -a 256 "$DCA" | cut -d" " -f1)
echo "DISC1_SHA=$DS"
if [ "$DS" != "$DEXPECT" ]; then echo "GATE-FAILED: disc1.c is not the fresh 3d78b0e7 emission - refusing"; exit 0; fi
echo "DISC1_VERIFIED (fresh emission)"

trunc() { sed -E 's/[A-Za-z0-9_./+-]{34,}/[T]/g' | cut -c1-110; }

fnbody() {
  FN="$1"; MAXL="${2:-120}"
  L=$(grep -n "^static void xenolift_fn_${FN}" "$DCA" | grep -v ";" | head -1 | cut -d: -f1)
  echo "===FN_${FN} (def line $L)==="
  if [ -n "$L" ] && [ "$L" -gt 0 ] 2>/dev/null; then
    awk -v s="$L" -v m="$MAXL" 'NR>=s{print; if($0 ~ /^}/) exit; c++; if(c>=m){print "...(capped)"; exit}}' "$DCA" | trunc
  else
    echo "FN DEF NOT FOUND"
  fi
}

echo "===HELPER281=== the FULL Vsync helper 8004B55C (the fault forms past L_8004B59C)"
fnbody 8004B55C 130

echo "===VWAIT281=== the v_wait body (the pc named in the fault)"
fnbody 8004B694 60

echo "===LZSS281=== the LZSS wrapper + core defs (prefix search, the EPC site)"
grep -n "^static void xenolift_fn_80032E" "$DCA" | grep -v ";" | head -6
fnbody 80032E88 40

echo "===CELLWRITERS281=== the vsync-cell family receipts (witness log)"
LOG=$(ls -t witness_c276_*/run.log.witness 2>/dev/null | head -1)
if [ -n "$LOG" ] && [ -s "$LOG" ]; then
  for C in 8005783C 80057840 80057844 80057848; do
    echo "--- cell $C:"
    grep -n "$C" "$LOG" | head -6
  done
else
  echo "witness log not found - skipped"
fi

echo "===GUARD281=== the R696 computed-garbage guard + skiphook classification (runtime.c)"
grep -n "R696\|computed-garbage" "$SRC" | head -8
L=$(grep -n "computed-garbage" "$SRC" | head -1 | cut -d: -f1)
if [ -n "$L" ]; then sed -n "$((L-30)),$((L+18))p" "$SRC" | trunc; fi
echo "--- the skiphook guard (invalid dispatch targets):"
grep -n "skiphook" "$SRC" | head -5

echo "===C281DONE=== vsync fault-site decode complete - the c282 fix design comes from these receipts"
