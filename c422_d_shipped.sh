#!/bin/bash
# c422_datasync.sh - READ-ONLY CENSUS. NO run, NO
# patch. The c421 decode REINTERPRETED A22C: it is
# CD_sync's internal TIMEOUT COUNTER (cleared at entry,
# incremented per pace miss, timeout 0x3C0000), NOT a
# data-arrived flag - A22C=4 is EXONERATED as the movie
# blocker, and the R879/R896/R1205 post family used
# wrong cell semantics. The collector (80041BA8->
# 80041C00) is the kernel EVENT DISPATCHER: it reads
# slot bits 0x80056788/89 and dispatches via the table
# at 0x80056550; final-era slot bits=0 so nothing
# dispatches. The full CD_sync entry (which clears A22C)
# never runs final-era. THIS PASS decodes the remaining
# contracts: (1) CD_datasync (0x8004293C) - the actual
# data-wait: which cells it polls, what releases it;
# (2) the WRITERS of slot bits 0x80056788/89 in
# disc1.c - the game's event-post sites (ISR family);
# (3) the dispatcher continuation: the rest of 80041C00
# (the slot dispatch + handler call) + the timeout path
# 80041C64; (4) the waiter fn header (the fn enclosing
# L_80041420). NO behavior change - receipts only.
# R1378 follows from these receipts only.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C422-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="6759e34359fdf33df2e78cfaf2c144194da718412f3d42cb022b12e87470a8bb"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1377 tree - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1377 tree)"
D="disc1.c"
if [ ! -f "$D" ]; then echo "disc1.c MISSING"; exit 0; fi
echo "===CDDATASYNC422=== CD_datasync (0x8004293C): the actual data-wait contract"
F=$(grep -n -e "0x8004293C (function)" "$D" | head -1 | cut -d: -f1)
echo "fn header at line: $F"
if [ -n "$F" ]; then
  awk -v s="$F" -v e="$((F+130))" 'NR>=s && NR<=e { print NR": "$0 }' "$D" | head -132
fi
echo "===SLOTWRITERS422=== the writers of slot bits 0x80056788/89 (the event-post sites)"
grep -n -e "0x6788" "$D" | grep -e "SB(" -e "SW(" | head -12
for LN in $(grep -n -e "0x6788" "$D" | grep -e "SB(" -e "SW(" | head -3 | cut -d: -f1); do
  echo "--- writer context at line $LN (-14/+6):"
  awk -v s=$((LN-14)) -v e=$((LN+6)) 'NR>=s && NR<=e { print NR": "$0 }' "$D"
done
echo "===DISPATCH422=== the dispatcher continuation (80041C00 rest + timeout 80041C64)"
F2=$(grep -n -e "0x80041C64 (function)" "$D" | head -1 | cut -d: -f1)
echo "80041C64 at line: $F2"
if [ -n "$F2" ]; then
  awk -v s="$F2" -v e="$((F2+60))" 'NR>=s && NR<=e { print NR": "$0 }' "$D" | head -62
fi
echo "--- the rest of 80041C00 (after the slot-byte reads, lines 129393-129460):"
awk -v s=129393 -v e=129460 'NR>=s && NR<=e { print NR": "$0 }' "$D"
echo "===WAITER422=== the waiter fn header (the fn enclosing L_80041420)"
F3=$(awk 'NR<128070 && /^static void xenolift_fn_/ { l=NR": "$0 } END { print l }' "$D")
echo "enclosing fn: $F3"
F4=$(echo "$F3" | cut -d: -f1)
if [ -n "$F4" ]; then
  awk -v s="$F4" -v e="$((F4+45))" 'NR>=s && NR<=e { print NR": "$0 }' "$D" | head -47
fi
echo "===C422DONE=== the data-wait and event-post contracts are decoded - R1378 follows from these receipts only"
