#!/bin/bash
# c386_midunpack.sh - READ-ONLY CENSUS. NO run, NO patch. The
# c385 verdict: R1366's target layout achieved NATIVELY
# (word0=0003FAFE, computed exit = the 260,862 expansion),
# but the unpack ran MID-READ (FDF8=59768 at the core entry -
# only ~52% of 125304 delivered) and the HLE decode rejected
# the partial input (prod=-1) -> core-loop runaway -> Module-6
# validation fail -> boot cycle x3. THIS PASS: the early-unpack
# anatomy - (1) what fired the install chain (r31=80019B98)
# while the read was in flight; (2) the FDF8 drain progression
# 11042->12773; (3) the dest churn (801DD680 -> 801E0E80 ->
# 801F0E80); (4) the lzss-hle prod=-1 precondition in
# runtime.c; (5) the second-pass restart trigger.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C386-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="52566422c865ec549026ce84b82e19a568b61b0cdd1e78984656a5b55cc437f2"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1367 tree - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1367 tree)"
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
if [ ! -s "$LOG" ]; then echo "TREE-ROOT-LOG-MISSING"; exit 0; fi
echo "AUTHORITATIVE LOG = $LOG ($(wc -l < "$LOG" | tr -d ' ') lines)"
echo "===INSTALLTRIG386=== the install-chain receipts in the window (what fired the unpack?)"
grep -n "80019B98\|install\|finstamp" "$LOG" | awk -F: '$1>=11042 && $1<=12775' | head -24
echo "===STEPPER386=== the queue walk in the window (F0C/F10 progression)"
grep -n "stepper\]" "$LOG" | awk -F: '$1>=11042 && $1<=12775' | head -16
echo "===FDF8DRAIN386=== the drain story in the window (125304 -> ?)"
grep -n "finstamp\|FDF8 ARM-CONTEXT\|\[req\] FDF8\|FDF8.*125304\|INSTALLRESET" "$LOG" | awk -F: '$1>=11042 && $1<=12775' | head -20
echo "===CBREADY386=== the file-ready callbacks in the window (the early-ready signal?)"
grep -n "cbcall\|FILE-CB\|HandleCdReady\|ArchiveCurrentFileReady" "$LOG" | awk -F: '$1>=11042 && $1<=12775' | head -12
echo "===SECCOUNT386=== the sector serves between the READ ISSUE and the unpack"
grep -n "loaded into data FIFO" "$LOG" | awk -F: '$1>=11042 && $1<=12773' | wc -l | tr -d ' '
grep -n "loaded into data FIFO" "$LOG" | awk -F: '$1>=11042 && $1<=12773' | tail -6
echo "===DESTCHURN386=== the FE08/dma dest story in the window"
grep -n "cd-dma\] CHCR.*bytes ->" "$LOG" | awk -F: '$1>=11042 && $1<=12773' | grep -v "80059EF8" | head -14
echo "===RESTART386=== the second-pass trigger (what preceded the re-Setloc at 11414?)"
awk 'NR>=11370 && NR<=11420 { print NR": "$0 }' "$LOG"
echo "===HLEFAIL386=== the lzss-hle decode-fail precondition (the runtime.c site)"
LG=$(grep -n "decode FAILED" "$SRC" | head -1 | cut -d: -f1)
echo "print at line $LG"
if [ -n "$LG" ]; then
  S=$((LG-45)); [ $S -lt 1 ] && S=1
  E=$((LG+15))
  awk -v s="$S" -v e="$E" 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
fi
echo "===LZEXIT386=== the core-loop exit receipts after the fallback (did it ever finish?)"
grep -n "lzss-x\] EXIT\|lzss-t\]" "$LOG" | head -8
echo "===C386DONE=== the early-unpack anatomy is receipted"
