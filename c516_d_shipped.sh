#!/bin/bash
# c515_extract.sh - READ-ONLY ERA-ANCHORED SEQUENCE CENSUS, NO
# RUN, NO BUILD, NO PATCH. Jos's c514 verdict: c513 does NOT
# establish that the fallback delivered file#18, nor that the
# healthy and stalled event states were equivalent. FOUR
# DISTINCTIONS: (1) s2=0x100 does not satisfy slots & 4 - the
# overlapping s2/s3 word views may reflect ONE byte write;
# capture the collector's ACTUAL returned r[2] separately
# (the 'collector slot=' receipts ARE that return); (2) the
# fallback message shows handler SELECTION - delivery needs
# dispatch to 0x8002B084 + consumption of the intended
# sector + the request's progress paired with it; (3) zero
# [wgen] = no observed hits only; (4) do NOT remove the
# cd_pending==0 guard - determine which response OWNS the
# pending interrupt, whether the guest acknowledges it, and
# whether the next data event remains queued afterward. THE
# SEQUENCE TO TRACE (era-anchored, not line-threshold):
# event-word write -> collector return -> branch selected ->
# handler dispatch -> sector consumption. THE FIX DEPENDS ON
# WHERE IT FIRST BREAKS: event posting, collection, handler
# selection, or data consumption. ALSO: the c514 ARM514
# section was EMPTY - no arm (R96/R1378/R408/R453/R879) ever
# fired in this run; healthy delivery ran purely on the
# guest's own event chain. THIS CENSUS: (1) GAPS - the camera
# budgets stated explicitly, including which sequence stages
# have NO receipts in the file#18 window; (2) SEQ - the
# file#18 window's full interleaved sequence
# (content-anchored on 109158); (3) HEALTHY - the same
# filter for the 239317-era window as the comparison anchor;
# (4) PEND - the pending-interrupt owner/ack/queue trace;
# (5) HOOKPOL - the [hook] camera's print policy (settles
# whether the missing 56788-view is a camera artifact or a
# genuinely different store). Fail-closed, tee'd to
# /tmp/c515_receipts.txt. Pure-ASCII output.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C515-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c515_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="13aab535963b12c3ff0515d0c2892e8d7625327afa09a3569ae1f2d7b3e1c5d4"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the c504 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the c504 tree with the landed interpreter)"
LOG="run.log"
if [ ! -s "$LOG" ]; then LOG="run.log.d"; fi
if [ ! -s "$LOG" ]; then echo "GATE-FAILED: no log"; exit 0; fi
echo "LOG=$LOG ($(wc -l < "$LOG" | tr -d " ") lines)"
echo "===GAPS515=== the camera budgets, stated explicitly"
C1=$(grep -c -e "\[cdcol\]" "$LOG" || true)
echo "cdcol receipts in this log: $C1 (the R1361 camera caps at 16 prints - if 16, the budget EXHAUSTED and the slot-bits word values in the file#18 window CANNOT be recovered by filtering; the c513 receipts show the budget ran out before the file#18 era)"
echo "--- the last cdcol receipt (where the budget ended):"
grep -n -e "\[cdcol\]" "$LOG" | tail -2
echo "--- arm receipts anywhere (c514 verdict rechecked):"
grep -c -e "\[drdoor\]" "$LOG" || true
grep -c -e "forced data-ready" "$LOG" || true
grep -c -e "\[mvdoor\] R879" "$LOG" || true
echo "(0 = that arm never fired in this run - absent-arm evidence, not absence-of-mechanism)"
echo "===SEQ515=== the file#18 window interleaved sequence (content-anchored on 109158)"
A=$(awk 'NR>10400 && /109158/ { print NR; exit }' "$LOG")
echo "the file#18 window anchor: first 109158 past 10400 at line $A"
if [ -n "$A" ]; then
  S=$(( A > 30 ? A - 30 : 1 ))
  E=$(( A + 240 ))
  awk -v s="$S" -v e="$E" 'NR>=s && NR<=e && (/\[hook\] 0x8005678/ || /wait-loop event/ || /wait-loop tick/ || /dispatch h4/ || /dispatch h2/ || /\[cbcall\]/ || /cd-dma/ || /\[fetchcam\]/ || /finstamp.*4FDF8/ || /\[rspop\]/ || /\[pendclr\]/ || /\[cdcsync\]/ || /\[cmdtl\]/ || /\[chg\] cell/ || /\[frc\]/ || /data-ready/ || /acknowledged/ || /\[fldsec\]/ || /collector slot=/) { print NR": "$0 }' "$LOG" | head -90
fi
echo "===HEALTHY515=== the same sequence filter for the healthy 239317-era window (the comparison anchor)"
awk 'NR>=8045 && NR<=8135 && (/collector slot=/ || /dispatch h4/ || /\[cbcall\]/ || /cd-dma/ || /\[fetchcam\]/ || /finstamp.*4FDF8/ || /\[hook\] 0x8005678/ || /\[chg\] cell/ || /data-ready/ || /\[rspop\]/ || /wait-loop tick/ || /\[cdcsync\]/) { print NR": "$0 }' "$LOG" | head -60
echo "===PEND515=== the pending-interrupt owner/ack/queue trace in the file#18 window"
A2=$(awk 'NR>10400 && /109158/ { print NR; exit }' "$LOG")
if [ -n "$A2" ]; then
  S2=$(( A2 > 30 ? A2 - 30 : 1 ))
  E2=$(( A2 + 240 ))
  awk -v s="$S2" -v e="$E2" 'NR>=s && NR<=e && (/\[pendclr\]/ || /wait-loop tick/ || /acknowledged/ || /\[rspop\]/ || /\[cmdtl\]/ || /pending=/) { print NR": "$0 }' "$LOG" | head -50
fi
echo "--- the pending stamps' owner vocabulary (site/cmd/LBA of every pendclr in the window):"
awk 'NR>10400 && NR<10800 && /\[pendclr\]/ { print NR": "$0 }' "$LOG" | head -12
echo "===HOOKPOL515=== the [hook] camera's print policy (camera artifact vs different store)"
H1=$(grep -n -F -e "[hook] 0x%08X" "$SRC" | head -1 | cut -d: -f1)
if [ -z "$H1" ]; then H1=$(grep -n -e "\[hook\]" "$SRC" | head -1 | cut -d: -f1); fi
echo "the hook print at line $H1:"
if [ -n "$H1" ]; then sed -n "$((H1-30)),$((H1+12))p" "$SRC"; fi
echo "===C515DONE=== the era-anchored sequence is receipted end-to-end with gaps named - the c516 fix follows from where the sequence FIRST BREAKS - digest is pure ASCII"
