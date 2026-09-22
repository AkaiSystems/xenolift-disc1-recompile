#!/bin/bash
# c306_fe48_prov.sh - READ-ONLY: the FE48 provenance, the mount-
# consume chain, the f15 enqueue census, and the schdd camera
# condition.
# THE c305 VERDICT: pause-INT2 disconfirmed (loads proceeded
# without it); the game CYCLES mount-state-1 and NEVER ENQUEUES
# f15 (no a0=0x0F ENQUEUE; F0C went 0E->0F but fn 8004111C
# never fired). FE48=0 during working polls, =1 at the tail -
# set by the runtime's R896-era sync-delivery heal, never
# cleared; the R874 DOOR camera watches FDFC/FE48/FE30.
# [schdd] silent all run (was abundant c206-c215).
# THIS PROBE: (1) every FE48 writer site in runtime.c with
# context; (2) the 0->1 moment + owning request; (3) the full
# mount lifecycle + any game-side consume; (4) the ENQUEUE
# census + the F0C writer; (5) the schdd camera print condition;
# (6) PollArchiveTransfer tail returns. No patch, no compile,
# no run.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C306-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="82853e3bc9c2b5be37c893f608f4f57b46123a2c9ff829c47a03e589a9b5dccd"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1338b tree 82853e3b - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1338b tree)"
W=$(ls -d witness_c302_* 2>/dev/null | head -1)
LOG="$W/run.log"
[ -s "$LOG" ] || LOG="run.log"
echo "WITNESS=$LOG"
if [ ! -s "$LOG" ]; then echo "C306-NO-WITNESS"; exit 0; fi

echo "===FE48CODE306=== every FE48 reference in runtime.c (writer sites with context)"
grep -n "FE48\|fe48" "$SRC" | head -16
for L in $(grep -n "0x8004FE48" "$SRC" | cut -d: -f1 | head -6); do
  echo "--- context around line $L:"
  sed -n "$((L-6)),$((L+8))p" "$SRC"
done

echo "===FE48LOG306=== the 0->1 moment + owning request in the witness"
grep -n "FE48" "$LOG" | grep -v "DOOR" | head -24
echo "--- R896 sync-delivery receipts:"
grep -n "R896\|sync delivery\|sync-delivery" "$LOG" | head -16

echo "===MOUNT306=== the full mount lifecycle + game-side consume"
grep -n "mtrans\]" "$LOG" | wc -l
grep -n "R650 mount-success\|R661 STATE-1 CB ENTER\|R650 gate sample\|R676 cur-restore" "$LOG" | head -20
echo "--- state-1 cb consume receipts (what the game does after mount):"
grep -n "cbtab\|cb enter\|CB ENTER\|mv_done" "$LOG" | head -16

echo "===F15ENQ306=== the ENQUEUE census + the F0C writer"
grep -n "ENQUEUE" "$LOG" | wc -l
grep -n "ENQUEUE" "$LOG" | tail -12
echo "--- F0C (0x80059F0C) writes:"
grep -n "80059F0C" "$LOG" | head -12

echo "===SCHDD306=== the schdd camera print condition"
grep -n "schdd" "$SRC" | head -12
L=$(grep -n "schdd" "$SRC" | head -1 | cut -d: -f1)
if [ -n "$L" ]; then echo "--- context around line $L:"; sed -n "$((L-10)),$((L+16))p" "$SRC"; fi
echo "--- any schdd/delivery-decision receipts:"
grep -n "schdd\|delivery decision" "$LOG" | head -8

echo "===ASYCTX306=== PollArchiveTransfer returns (tail era)"
grep -n "asyctx\] R917" "$LOG" | tail -8
echo "===C306DONE=== FE48 provenance complete - the fix design verdict comes from these receipts"
