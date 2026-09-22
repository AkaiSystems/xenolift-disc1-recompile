#!/bin/bash
# c282_faultsite_complete.sh - READ-ONLY: the completing dump of the
# fault-site region with FIXED next-def windows (the c281 lesson:
# nested-block closing braces at column 0 killed the awk brace-exit,
# cutting both 8004B55C past L_8004B59C and v_wait past L_8004B6B4).
# THE c281 DECODE: the fault EPC is inside the LZSS decompress core
# (a SOURCE read; r4=0x00200000 = the heap terminator flags value
# used as the source pointer). The pc=8004B694 in the fault receipt
# is cur_fn attribution (last dispatched fn = v_wait), NOT the
# faulting instruction. The Vsync cell family is healthy
# (boot-written HW register pointers, the libetc queue cell v_wait
# itself writes, the vblank counter the game's poll loops
# increment). THE GOAL: dump the remaining fault-era code - the rest
# of the 8004B55C body (disc1.c 151371-151540), the FULL v_wait
# body, the LZSS core entry (the source-read instruction), and the
# 80041B3C dispatcher that leads into the Vsync chain - then
# design the c283 fix. No patch, no compile, no run.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C282-FAILED: xenolift dir missing"; exit 1; }
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

fnwindow() {
  FN="$1"; MAXL="${2:-120}"
  L=$(grep -n "^static void xenolift_fn_${FN}" "$DCA" | grep -v ";" | head -1 | cut -d: -f1)
  if [ -z "$L" ] || [ "$L" -lt 1 ] 2>/dev/null; then echo "===FN_${FN}: DEF NOT FOUND"; return; fi
  E=$(awk -v s="$L" 'NR>s && /^static void/{print NR; exit}' "$DCA")
  if [ -z "$E" ]; then E=$((L+MAXL+2)); fi
  echo "===FN_${FN} (def $L .. next def $E, ${MAXL}-capped)==="
  awk -v s="$L" -v e="$((E-1))" 'NR>=s && NR<=e' "$DCA" | head -"$MAXL" | trunc
}

echo "===HELPER282=== the rest of the 8004B55C body (fixed window, no brace-exit)"
fnwindow 8004B55C 200
echo "===VWAIT282=== the FULL v_wait body (fixed window)"
fnwindow 8004B694 90
echo "===LZSSCORE282=== the LZSS decompress core entry (the source-read site)"
fnwindow 80032EB4 70
echo "===DISP282=== the 80041B3C dispatcher (leads into the Vsync chain)"
fnwindow 80041B3C 70
echo "===C282DONE=== fault-site dump complete - the c283 fix design comes from these receipts"
