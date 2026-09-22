#!/bin/bash
# c278_writertrace_dossier.sh - READ-ONLY: the stale-cell writers,
# the pre-fault window, the sound-heap head, and the fault census.
# THE c277 VERDICT: after consuming f15 (GetTN answered, TOC
# completion routed to the state machine, state-queue cells
# churned), THE FIRST FAULT: computed-garbage 0x00200000 at
# pc=8004B694 (r4=00200000 r5=80400813), BadVAddr=0x00200000,
# EPC=0x80032EB4 (the LZSS wrapper) - the unpack was called with
# SOURCE 0x00200000 = THE HEAP FREE-SENTINEL FLAGS VALUE consumed
# as a pointer (struct-class confusion); the fntrail 80041B3C
# 8004B54C 8004B55C 8004B694 is the SAME SOUND-HEAP DISPATCHER
# FAMILY as the c217b dossier (g_SoundHeapHead 0x80059410 null).
# faultctx names the stale cells holding the target: 0x8004FB6C,
# 0x801FBFFC, 0x801FFF1C - "writer trace next".
# THIS DOSSIER receipts (read-only, on witness log 9193a7cd):
# (1) every log receipt touching the stale cells (writers);
# (2) the pre-fault window 29719-30068 tag census + the receipts
#     that armed the dispatch (state-queue churn, io write);
# (3) the sound-heap family receipts (0x80059410, sndheap,
#     sndreboot, 8004B55C, 8004B694 camera coverage);
# (4) the full fault census (is this the ONLY fault class now?).
# No patch, no compile, no run.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C278-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
LOG=$(ls -t witness_c276_*/run.log.witness 2>/dev/null | head -1)
EXPECT="9193a7cd47b9595f8317072207550cab70292e9cd2bfd08f8d20e9219e122e21"
if [ -z "$LOG" ] || [ ! -s "$LOG" ]; then echo "C278-FAILED: preserved witness log missing"; exit 1; fi
SS=$(shasum -a 256 "$LOG" | cut -d" " -f1)
echo "LOG_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: witness log sha mismatch - refusing a foreign log"; exit 0; fi
echo "BASELINE_VERIFIED (the c276 consumption witness run)"
ENDL=$(wc -l < "$LOG" | tr -d " ")
echo "log_lines=$ENDL"
win() { S=$1; [ "$S" -lt 1 ] && S=1; E=$2; [ "$E" -gt "$ENDL" ] && E=$ENDL; awk -v s="$S" -v e="$E" 'NR>=s&&NR<=e{printf "%d:%s\n",NR,$0}NR>e{exit}' "$LOG"; }

echo "===CELLS278=== every receipt touching the stale cells (the writers)"
for C in 8004FB6C 801FBFFC 801FFF1C; do
  echo "--- cell $C:"
  grep -n "$C" "$LOG" | head -6
done
echo "--- all 00200000 receipts:"
grep -n "00200000" "$LOG" | head -10

echo "===PREFAULT278=== the window between the TOC answer and the fault"
echo "--- tag census (29719-30068):"
win 29719 30068 | grep -o "\[[a-z0-9]*\]" | sort | uniq -c | sort -rn | head -18
echo "--- the non-churn receipts (excluding task/chg/bandhist/asciiart):"
win 29719 30068 | grep -v "\[task\]\|\[chg\]\|\[bandhist\]\|\[asciiart\]\|\[bp\] *$\|\[rcb\]\|\[evt\]\|\[spxw\]" | head -22

echo "===SNDHEAP278=== the sound-heap family receipts"
echo "--- 80059410 receipts:"
grep -n "80059410\|59410" "$LOG" | head -8
echo "--- sndheap/sndreboot receipts:"
grep -n "sndheap\|sndreboot\|soundheap\|SoundHeap" "$LOG" | head -10
echo "--- the dispatcher fns in cameras:"
grep -n "8004B55C\|8004B694\|8004B54C" "$LOG" | head -12

echo "===FAULTCENSUS278=== the full fault census (one class or many?)"
echo "fault_receipts=$(grep -c "\[fault\]" "$LOG")"
grep -n "computed-garbage\|NULL-trap\|BadVAddr" "$LOG" | head -12
echo "--- the recoveries:"
grep -n "recovery " "$LOG" | head -8

echo "===C278DONE=== writer-trace dossier complete - the c279 fix design comes from these receipts"
