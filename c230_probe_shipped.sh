#!/bin/bash
# c230_loop_exit_probe.sh - READ-ONLY: no patch, no compile, no run.
# The c229 raw windows NAMED the re-entry trigger: the c335-class guest
# LZSS runaway AFTER a successful unpack. Receipts: the menu module
# installs (coordinator 80077E88 written with real bytes, module window
# written by the guest loop at fn 80032EB4), then the guest loop IGNORES
# the r15 exit-target heal, reads past the 2MB guest RAM end (1,048,576
# suppressed ops, frontier 0x802FFFFF, aborts=0), R1151 converts to
# crash-kit recovery, and the recovery boot re-entry WIPES the installed
# module - the cycle repeats. The HLE decode is correct; the redundant
# guest loop never exits. This probe extracts the guest loop's own code
# (fn 80032EB4 region in the Mac's CURRENT emitted C - authoritative;
# sandbox copies are stale) plus the runtime's heal/HLE/lzrwatch/R926
# sites, so c231 patches the REAL exit condition.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C230-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
R="runtime/runtime.c"
EXPECT="c821d139f2c30c9aa470ca274656956928f42d0f9989530fdf4aa1db6ac769f4"
if [ ! -s "$R" ]; then echo "C230-FAILED: runtime/runtime.c missing"; exit 1; fi
SS=$(shasum -a 256 "$R" | cut -d" " -f1)
echo "TREE_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the c226 R1318 tree c821d139 - nothing extracted"; exit 0; fi
echo "BASELINE_VERIFIED"

echo "===EMITC230=== locate the emitted guest C (the authoritative current file)"
find . -name "*.c" -not -path "./.git/*" -not -path "./target/*" -exec ls -la {} \; 2>/dev/null | sort -k5 -rn | head -12
echo "--- files containing 80032EB4:"
grep -rln "80032EB4" --include="*.c" . 2>/dev/null | head -5

F=""
for CAND in $(grep -rln "80032EB4" --include="*.c" . 2>/dev/null | head -5); do
  SZ=$(wc -c < "$CAND"); if [ "$SZ" -gt 200000 ]; then F="$CAND"; break; fi; done
echo "EMIT_FILE=$F"
if [ -n "$F" ]; then
  echo "===LOOP230=== the guest unpack wrapper fn 80032EB4 in the emitted C"
  grep -n "80032EB4" "$F" | head -12
  N=$(grep -n "L_80032EB4\|fn_80032EB4" "$F" | head -1 | cut -d: -f1)
  echo "first-marker-line=$N"
  if [ -n "$N" ]; then
    S=$((N-10)); [ "$S" -lt 1 ] && S=1
    awk -v s="$S" -v e=$((N+90)) 'NR>=s&&NR<=e{printf "%d:%s\n",NR,$0}NR>e{exit}' "$F"
  fi
  echo "--- the loop core (the callee the wrapper jumps into, look for the copy loop):"
  grep -n "80029670\|80032E88\|80032E8C" "$F" | head -6
  N2=$(grep -n "L_80032E88\|fn_80032E88" "$F" | head -1 | cut -d: -f1)
  if [ -n "$N2" ]; then
    S2=$((N2-6)); [ "$S2" -lt 1 ] && S2=1
    awk -v s="$S2" -v e=$((N2+70)) 'NR>=s&&NR<=e{printf "%d:%s\n",NR,$0}NR>e{exit}' "$F"
  fi
fi

echo "===HEALSITE230=== the runtime lzss-heal site (why the exit-target heal did not take)"
grep -n "lzss-heal" "$R" | head -4
NH=$(grep -n "lzss-heal" "$R" | head -1 | cut -d: -f1)
if [ -n "$NH" ]; then
  S=$((NH-30)); [ "$S" -lt 1 ] && S=1
  awk -v s="$S" -v e=$((NH+15)) 'NR>=s&&NR<=e{printf "%d:%s\n",NR,$0}NR>e{exit}' "$R"
fi

echo "===HLESITE230=== the HLE decode + one-shot zero-read site"
NG=$(grep -n "one-shot zero-read" "$R" | head -1 | cut -d: -f1)
echo "hle-print-line=$NG"
if [ -n "$NG" ]; then
  S=$((NG-60)); [ "$S" -lt 1 ] && S=1
  awk -v s="$S" -v e=$((NG+20)) 'NR>=s&&NR<=e{printf "%d:%s\n",NR,$0}NR>e{exit}' "$R"
fi

echo "===LZRW230=== the R1151 lzrwatch conversion site"
NL=$(grep -n "lzrwatch" "$R" | head -1 | cut -d: -f1)
echo "lzrwatch-line=$NL"
if [ -n "$NL" ]; then
  S=$((NL-25)); [ "$S" -lt 1 ] && S=1
  awk -v s="$S" -v e=$((NL+12)) 'NR>=s&&NR<=e{printf "%d:%s\n",NR,$0}NR>e{exit}' "$R"
fi

echo "===R926230=== the R926 abort guard site"
grep -n "R926" "$R" | head -6

echo "===GUARD230=== the lzss-guard-r suppression site (what it feeds the loop on overrun)"
NGU=$(grep -n "lzss-guard-r" "$R" | head -1 | cut -d: -f1)
echo "guard-line=$NGU"
if [ -n "$NGU" ]; then
  S=$((NGU-20)); [ "$S" -lt 1 ] && S=1
  awk -v s="$S" -v e=$((NGU+14)) 'NR>=s&&NR<=e{printf "%d:%s\n",NR,$0}NR>e{exit}' "$R"
fi
echo "===C230DONE=== loop-exit probe complete - the c231 fix patches the REAL exit condition from these receipts"
