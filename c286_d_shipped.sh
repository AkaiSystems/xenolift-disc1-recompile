#!/bin/bash
# c286_reverbchain_probe.sh - READ-ONLY: name the exact cell that
# feeds the garbage work-area base, and receipt the callback-queue +
# SPU DMA lifecycle around the fault.
# THE c285 VERDICT: the c284 first-fault host backtrace names the
# real chain - OUR PUMP (kick <- park_tick <- fn_80019F00 <-
# fn_80019AD8 <- HeapFree+808 <- 80032240 <- HeapRelocate <-
# 80019B00 <- KernelMenuMain) delivered a QUEUED SOUND CALLBACK:
# SpuSetReverbModeType -> SpuClearReverbWorkArea -> fn_8004CCB8 ->
# mem_read16(0x589F81A6), a read through garbage base r5=0x589F8000
# + 0x1A6 (r17=0x5BC4, r19=0x800564D0 a real sound-driver struct).
# The EPC=LZSS attribution was the guard routing context; the LZSS
# path is healthy. SoundInitialize RE-ENTERS at t=9s while the
# earlier-era callback is still queued - the lifetime/ownership
# suspect is the CALLBACK QUEUE + reverb work-area base, not the
# archive/LZSS.
# THIS PROBE: (a) fn 8004CCB8 - the r5-source instructions + the
# faulting read site; (b) SpuClearReverbWorkArea / SpuSetReverbMode
# Type heads (args + the queue path); (c) the kick-queue receipts
# around the fault (which callback, which era queued it); (d) the
# hle-spu DMA receipts (the last-pos 0x200000 overrun clue); (e)
# the SoundInitialize receipts (all eras). No patch, no compile,
# no run.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C286-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="ab668553a3e45945572b5c9d41f3e7fbe1726fa67e8796772c83c6a0ff9faf70"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1334 tree ab668553 - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1334 tree)"
LOG="witness_c284_20260917_084145/run.log"
LEXPECT="8ce98ba9d574adb1cfc4a787010c8aaa2caf92ca374cb6867dcca52d8006ca48"
LS=$(shasum -a 256 "$LOG" | cut -d" " -f1)
echo "WITNESS_SHA=$LS"
if [ "$LS" != "$LEXPECT" ]; then echo "GATE-FAILED: witness log sha mismatch - refusing"; exit 0; fi
echo "WITNESS_VERIFIED (the c284 camera run)"
ENDL=$(wc -l < "$LOG" | tr -d " ")
win() { S=$1; [ "$S" -lt 1 ] && S=1; E=$2; [ "$E" -gt "$ENDL" ] && E="$ENDL"; awk -v s="$S" -v e="$E" 'NR>=s&&NR<=e{printf "%d:%s\n",NR,$0}NR>e{exit}' "$LOG"; }
trunc() { sed -E 's/[A-Za-z0-9_./+-]{34,}/[T]/g' | cut -c1-110; }
DCA="./disc1.c"

fnwindow() {
  FN="$1"; MAXL="${2:-90}"
  L=$(grep -n "^static void xenolift_fn_${FN}" "$DCA" | grep -v ";" | head -1 | cut -d: -f1)
  if [ -z "$L" ] || [ "$L" -lt 1 ] 2>/dev/null; then echo "===FN_${FN}: DEF NOT FOUND"; return; fi
  E=$(awk -v s="$L" 'NR>s && /^static void/{print NR; exit}' "$DCA")
  [ -z "$E" ] && E=$((L+MAXL+2))
  echo "===FN_${FN} (def $L .. next def $E, ${MAXL}-capped)==="
  awk -v s="$L" -v e="$((E-1))" 'NR>=s && NR<=e' "$DCA" | head -"$MAXL" | trunc
}

echo "===FAULTREADER286=== fn 8004CCB8 - the r5-source + the faulting read site"
L=$(grep -n "^static void xenolift_fn_8004CCB8" "$DCA" | grep -v ";" | head -1 | cut -d: -f1)
echo "def at line $L"
if [ -n "$L" ]; then
  E=$(awk -v s="$L" 'NR>s && /^static void/{print NR; exit}' "$DCA")
  [ -z "$E" ] && E=$((L+900))
  echo "--- body size: $((E-L)) lines; the r5/LH(r5) sites:"
  awk -v s="$L" -v e="$E" 'NR>=s && NR<=e && (/r\[5\] = LW/ || /LH\(r\[5\]/ || /r\[17\] = /) {print NR": "$0}' "$DCA" | head -20 | trunc
  echo "--- the head (40 lines):"
  awk -v s="$L" 'NR>=s{print; c++; if(c>=40) exit}' "$DCA" | trunc
fi

echo "===REVERB286=== SpuClearReverbWorkArea + SpuSetReverbModeType heads"
fnwindow 8004E3C8 70
fnwindow 8004DD1C 70

echo "===KICK286=== the callback-queue receipts (which callback, which era)"
echo "--- kick/park receipts in the pre-fault window (29500-30183):"
win 29500 30183 | grep -i "kick\|park\|cbguard\|callback\|cbq" | head -20
echo "--- all kick receipts (head 12):"
grep -n -i "\[kick\]" "$LOG" | head -12
echo "--- the cblive/cbguard camera receipts (whole log):"
grep -n "cblive\|cbguard" "$LOG" | head -12

echo "===SPU286=== the hle-spu DMA receipts (the overrun clue)"
grep -n "hle-spu\]" "$LOG" | head -16
echo "--- spu transfer/dma receipts around the sound re-init (27500-28600):"
win 27500 28600 | grep -i "spu" | head -14

echo "===SNDINIT286=== SoundInitialize receipts (all eras)"
grep -n "sndinit\]" "$LOG" | head -14

echo "===C286DONE=== reverb-chain probe complete - the c287 fix design comes from these receipts"
