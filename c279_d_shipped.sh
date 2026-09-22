#!/bin/bash
# c279_dispatcher_decode.sh - READ-ONLY: the STATIC DECODE of the
# dispatcher family that feeds the LZSS wrapper a garbage source.
# THE c278 VERDICT: the death census is ONE class - 3 recoveries +
# true death (segvdie, 16/16, sig=11), ALL at EPC=0x80032EB4 (the
# LZSS wrapper) with computed sources 0x00200000/0x56002000: the
# unpack repeatedly called with a GARBAGE SOURCE. The stale cell
# 0x801FBFFC = the heap terminator flag cell; its value 0x00200000
# is the game's OWN write (rootw r31=80042154, R702 rectguard
# confirmed ARMED) = the free-sentinel flag; the dispatcher family
# 8004B54C -> 8004B55C -> 8004B694 consumed FLAGS-AS-POINTER. The
# sound-heap head 0x80059410 was cleared to 0 at 29900 (fn
# 8003569C) 78 lines before the fault, after being set to 80065B10.
# THE 8004B54C family dispatches with a0=0xFFFFFFFF (not-a-struct-
# ptr class) - and the c217b dossier named the same family for the
# null sound-heap head.
# THIS CYCLE: the STATIC DECODE from the Mac's FRESH emitted
# disc1.c (sandbox copies are stale): dump the fn bodies
# 8004B54C / 8004B55C / 8004B694 / 8004B5E4 (the dispatcher chain)
# + the LZSS wrapper 80032E88 (the source-read path) + the
# fault-window state of the 801FBFFC/801FBFF8 cells. THE GOAL:
# name the EXACT cell the walk reads as the unpack source, then
# design the c280 fix. No patch, no compile, no run.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C279-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="0cc8f8599ef2adcef29ac528864d80eb217a4c8c2a9e597c69b3b435e4982907"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1332 tree 0cc8f859 - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1332 tree, unchanged)"

echo "===LOCATE279=== the fresh emitted disc1.c"
DC=$(find . -maxdepth 3 -name "disc1.c" -size +1000k 2>/dev/null | head -3)
echo "candidates: $DC"
DCA=""
for f in $DC; do SZ=$(wc -c < "$f" | tr -d " "); echo "  $f size=$SZ mtime=$(stat -f %Sm "$f" 2>/dev/null || stat -c %y "$f" 2>/dev/null)"; done
DCA=$(for f in $DC; do echo "$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null) $f"; done | sort -rn | head -1 | cut -d" " -f2-)
echo "chosen (newest): $DCA"
if [ -z "$DCA" ] || [ ! -s "$DCA" ]; then echo "C279-FAILED: no emitted disc1.c found"; exit 1; fi
echo "DISC1_SHA=$(shasum -a 256 "$DCA" | cut -d" " -f1) size=$(wc -c < "$DCA" | tr -d " ")"

fnbody() {
  FN="$1"; MAXL="${2:-70}"
  L=$(grep -n "xenolift_fn_${FN}" "$DCA" | grep -v "sw_line\|cur_fn\|r31\|caller" | head -1 | cut -d: -f1)
  echo "===FN_${FN} (def line $L)==="
  if [ -n "$L" ]; then
    awk -v s="$L" -v m="$MAXL" 'NR>=s{print; if($0 ~ /^}/) {n++; if(n>=1) exit} c++; if(c>m) exit}' "$DCA"
  else
    echo "FN NOT FOUND in disc1.c"
  fi
}

echo "===CHAIN279=== the dispatcher chain fns"
fnbody 8004B54C 50
fnbody 8004B55C 60
fnbody 8004B694 60
fnbody 8004B5E4 40

echo "===LZSS279=== the LZSS wrapper (the source-read path)"
fnbody 80032E88 40

echo "===CALLERS279=== who calls the dispatcher chain (the fntrail decode)"
grep -n "xenolift_fn_8004B55C\|xenolift_fn_8004B694" "$DCA" | grep -v "sw_line" | head -8
echo "--- the fntrail fns that armed the dispatch:"
fnbody 80041B3C 40

echo "===CELLS279=== the terminator cells at fault time (witness log window 29850-30070)"
LOG=$(ls -t witness_c276_*/run.log.witness 2>/dev/null | head -1)
if [ -n "$LOG" ] && [ -s "$LOG" ]; then
  grep -n "801FBFFC\|801FBFF8\|801FC000" "$LOG" | awk -F: '$1 >= 29850 && $1 <= 30070' | head -12
  echo "--- the fault-era walk receipts (the walk that consumed the flag):"
  grep -n "walkread\|take\]\|carvecam" "$LOG" | awk -F: '$1 >= 29900 && $1 <= 30070' | head -14
else
  echo "witness log not found - cells section skipped"
fi

echo "===C279DONE=== dispatcher static decode complete - the c280 fix design comes from these receipts"
