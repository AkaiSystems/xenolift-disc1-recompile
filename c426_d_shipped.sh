#!/bin/bash
# c426_chainvals.sh - READ-ONLY CENSUS. NO run, NO
# patch. The c425 receipts found the ROOT: the libcd
# CLASS POINTER CELL 0x80056770 is preserved as ZERO
# (c310 cdkeep2 receipt), and getintr derefs it every
# kernel-loop iteration - NULL -> getintr exits empty
# forever -> the poster never runs -> slot bits stay 0
# -> every event-waiter (incl. the movie-start, which
# waits for the seek-complete EVENT after Setloc(02))
# hangs. THE EVENT CHAIN IS DEAD AT ITS ROOT.
# THIS PASS gathers the last receipts before R1378's
# design: (1) REGCENSUS - did the game REGISTER a
# ready/sync/data/read callback in this run? (the
# registration dispatches 80040FB4/80040FCC/800413EC/
# 8004373C in the log, all eras, line-numbered);
# (2) PTRVALS - every existing receipt of the pointer
# cells 0x80056770/6774/6778/677C and the callback
# slots 0x800564A8/0x800564AC (cdkeep2, R1205, mod6,
# walkread families) - their ACTUAL final-era values;
# (3) getintr's return-value construction (disc1.c
# lines 128520-128620); (4) the runtime's c306-era
# wrapper around 0x80056770 (runtime.c lines 6140-6200
# + 8320-8340) - what we already preserve/restore.
# NO behavior change - receipts only. R1378 follows
# from these receipts only.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C426-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="6759e34359fdf33df2e78cfaf2c144194da718412f3d42cb022b12e87470a8bb"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1377 tree - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1377 tree)"
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
D="disc1.c"
[ -f "$D" ] || { echo "disc1.c MISSING"; exit 0; }
echo "===REGCENSUS426=== did the game register CD callbacks this run?"
for FN in 80040FB4 80040FCC 800413EC 8004373C; do
  N=$(grep -c -e "$FN" "$LOG")
  echo "--- $FN: $N log lines"
  if [ "$N" -gt 0 ]; then grep -n -e "$FN" "$LOG" | head -5; fi
done
echo "--- loopid/curfn receipts naming the callback fns (final era):"
grep -n -e "80040FB4\|80040FCC\|800413EC\|8004373C" "$LOG" | awk -F: '$1 > 31000' | head -8
echo "===PTRVALS426=== every existing receipt of the pointer cells + callback slots"
for C in 56770 6774 6778 677C 64A8 64AC; do
  N=$(grep -c -e "$C" "$LOG")
  echo "--- 0x8005${C}: $N log lines"
  if [ "$N" -gt 0 ]; then grep -n -e "$C" "$LOG" | head -6; fi
done
echo "===GETINTRRET426=== getintr's return-value construction (disc1.c 128520-128620)"
awk -v s=128520 -v e=128620 'NR>=s && NR<=e { print NR": "$0 }' "$D" | head -102
echo "===RUNTIMECTX426=== the runtime's c306-era wrapper (6140-6200 + 8320-8340)"
awk -v s=6140 -v e=6200 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
echo "--- the comment region:"
awk -v s=8320 -v e=8340 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
echo "===C426DONE=== the registration + pointer-value receipts are in - R1378 follows from these receipts only"
