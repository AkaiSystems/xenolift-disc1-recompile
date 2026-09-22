#!/bin/bash
# c429_pollret.sh - READ-ONLY CENSUS. NO run, NO patch.
# The c428 receipts show the whole psx-spx ack protocol
# is already register-level real in our model (the
# 1803-idx1 write-7 ack clears cd_pending; the ReadN
# INT3->INT1 ack-pair arms data-ready; the INT2
# second-response family arms on the INT3 ack; the
# mirror table is seeded by R974/R976 at the pump and
# getintr doors). The R408 comment states the design
# intent: 'the poll then returns the flag'. TWO RECEIPTS
# DECIDE R1378: (1) what the 803-idx1 read actually
# RETURNS today (the case body continues past line
# 3870 - the R453 arm conditions + the return); (2)
# whether the game's REGISTERED callbacks (80040DA0
# sync / 80040DC8 ready, installed at lines 1417-1423)
# were ever DISPATCHED in the log. THIS PASS: (1) the
# rest of the 803-idx1 case body (3870-3990); (2) the
# GetStat (cmd 01) response construction in cd_cmd;
# (3) run.log greps: the callback fn dispatches, the
# [regtabseed] receipts, the [frc]/[cd] fld-poll map,
# the spin-conv/ackcam final-era receipts; (4) the
# final-era GetStat response bytes (cmdtl receipts with
# resp values). NO behavior change - receipts only.
# R1378 follows from these receipts only.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C429-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="6759e34359fdf33df2e78cfaf2c144194da718412f3d42cb022b12e87470a8bb"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1377 tree - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1377 tree)"
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
echo "===POLLRD429=== the rest of the 803-idx1 case body (3870-3990)"
awk -v s=3870 -v e=3990 'NR>=s && NR<=e { print NR": "$0 }' "$SRC" | head -121
echo "===GETSTAT429=== the GetStat (cmd 01) response construction"
G=$(grep -n -e "case 0x01" "$SRC" | head -4)
echo "$G"
for LN in $(grep -n -e "case 0x01" "$SRC" | head -3 | cut -d: -f1); do
  echo "--- context at line $LN (-6/+22):"
  awk -v s=$((LN-6)) -v e=$((LN+22)) 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
done
echo "===CBDISP429=== were the game's callbacks ever dispatched?"
for FN in 80040DA0 80040DC8; do
  N=$(grep -c -e "$FN" "$LOG")
  echo "--- $FN: $N log lines"
  if [ "$N" -gt 0 ]; then grep -n -e "$FN" "$LOG" | head -8; fi
done
echo "===SEEDCENSUS429=== the regtabseed / frc / spin-conv receipts"
N=$(grep -c -e "regtabseed" "$LOG")
echo "--- regtabseed: $N lines"
if [ "$N" -gt 0 ]; then grep -n -e "regtabseed" "$LOG" | head -6; fi
N=$(grep -c -e "\[frc\]" "$LOG")
echo "--- frc: $N lines"
if [ "$N" -gt 0 ]; then grep -n -e "\[frc\]" "$LOG" | head -6; fi
N=$(grep -c -e "spin-conv" "$LOG")
echo "--- spin-conv: $N lines"
if [ "$N" -gt 0 ]; then grep -n -e "spin-conv" "$LOG" | head -5; fi
echo "===CMDTL429=== the final-era cmdtl receipts (the GetStat poll + response values)"
grep -n -e "cmdtl" "$LOG" | awk -F: '$1 > 31000' | head -12
echo "===C429DONE=== the poll-return + dispatch receipts are in - R1378 follows from these receipts only"
