#!/bin/bash
# c423_eventchain.sh - READ-ONLY CENSUS. NO run, NO
# patch. The c422 decode completed the chain's anatomy:
# ISR -> poster (fn 0x80041920 writes slot byte
# 0x80056788 = 2 or 5) -> kernel sync-chunk dispatcher
# -> table handler (tables 0x80056550/0x800564D0) ->
# waiter releases. Final-era slot bits=0 = THE POSTER
# NEVER RAN. Our runtime completes CD via the POLL path
# only; the R896 slotbits|6 heals were crude emulations
# of this chain. THIS PASS decodes the remaining
# contracts: (1) the CALLERS of the poster 80041920 +
# what r17 means (which events get posted by whom);
# (2) the event-TABLE writers (stores to 0x6550/0x64D0
# in disc1.c - the handler registrations); (3) the sync
# fn's return continuation (80041C68/80041D90 - what the
# waiter sees); (4) Vsync's return contract
# (0x8004B54C - confirm the frame-counter return);
# (5) the timeout path 80042A54 (CD_datasync's version).
# NO behavior change - receipts only. R1378 follows from
# these receipts only.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C423-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="6759e34359fdf33df2e78cfaf2c144194da718412f3d42cb022b12e87470a8bb"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1377 tree - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1377 tree)"
D="disc1.c"
if [ ! -f "$D" ]; then echo "disc1.c MISSING"; exit 0; fi
echo "===POSTERCALLERS423=== the callers of the poster 80041920 (who posts which event)"
grep -n -e "80041920" "$D" | head -10
for LN in $(grep -n -e "fn_80041920" "$D" | grep -v -e "static void" | head -3 | cut -d: -f1); do
  echo "--- caller context at line $LN (-25/+4):"
  awk -v s=$((LN-25)) -v e=$((LN+4)) 'NR>=s && NR<=e { print NR": "$0 }' "$D"
done
echo "--- the poster fn header + full body:"
FP=$(grep -n -e "0x80041920 (function)" "$D" | head -1 | cut -d: -f1)
echo "poster at line: $FP"
if [ -n "$FP" ]; then
  awk -v s="$FP" -v e="$((FP+55))" 'NR>=s && NR<=e { print NR": "$0 }' "$D"
fi
echo "===TABLEWRITERS423=== the event-table writers (stores to 0x6550 / 0x64D0)"
grep -n -e "0x6550" "$D" | grep -e "SW(" -e "SB(" | head -10
grep -n -e "0x64D0" "$D" | grep -e "SW(" -e "SB(" | head -8
for LN in $(grep -n -e "0x6550" "$D" | grep -e "SW(" | head -2 | cut -d: -f1); do
  echo "--- table-writer context at line $LN (-16/+6):"
  awk -v s=$((LN-16)) -v e=$((LN+6)) 'NR>=s && NR<=e { print NR": "$0 }' "$D"
done
echo "===RETCONT423=== the sync fn's return continuation (80041C68/80041D90)"
FC=$(grep -n -e "80041D90" "$D" | head -1 | cut -d: -f1)
echo "first 80041D90 ref at line: $FC"
if [ -n "$FC" ]; then
  awk -v s="$FC" -v e="$((FC+45))" 'NR>=s && NR<=e { print NR": "$0 }' "$D" | head -47
fi
echo "===VSYNC423=== Vsync's return contract (0x8004B54C)"
FV=$(grep -n -e "0x8004B54C (function)" "$D" | head -1 | cut -d: -f1)
echo "Vsync at line: $FV"
if [ -n "$FV" ]; then
  awk -v s="$FV" -v e="$((FV+55))" 'NR>=s && NR<=e { print NR": "$0 }' "$D"
fi
echo "===TIMEOUT423=== CD_datasync's timeout path (80042A54)"
FT=$(grep -n -e "0x80042A54 (function)" "$D" | head -1 | cut -d: -f1)
echo "timeout fn at line: $FT"
if [ -n "$FT" ]; then
  awk -v s="$FT" -v e="$((FT+40))" 'NR>=s && NR<=e { print NR": "$0 }' "$D"
fi
echo "===C423DONE=== the event-chain contracts are decoded - R1378 follows from these receipts only"
