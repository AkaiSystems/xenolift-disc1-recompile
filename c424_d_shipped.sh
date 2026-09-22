#!/bin/bash
# c424_getintr.sh - READ-ONLY CENSUS. NO run, NO
# patch. The c423 decode named the gate: the kernel
# sync continuation reads the INTERRUPT CLASS
# LBU([0x80056770]) & 3, passes it to getintr
# (0x800415B4), and checks getintr's return (r16 != 0,
# then r16 & 4 - the R891 bit2/bit1 dance). getintr is
# the interrupt->event converter; the poster 80041920
# (slot byte 2/5 + 7-byte response record to
# 0x8006A210) never runs if getintr returns 0 forever.
# THIS PASS decodes the final contracts: (1) getintr's
# FULL BODY - what it reads, when it returns nonzero,
# whether it calls/arms the poster; (2) CheckCallback
# (0x8004B894); (3) the WRITERS of the class cell -
# 0x80056770's pointer value + who stores the class
# byte (the ISR side: search disc1.c for stores near
# 0x1F801800-3 reads and 0x6770/6774 stores); (4) the
# continuation past the bit2 check (the handler call);
# (5) 80042A54 (bare-address grep - it is a split
# chunk, not a function). NO behavior change - receipts
# only. R1378 follows from these receipts only.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C424-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="6759e34359fdf33df2e78cfaf2c144194da718412f3d42cb022b12e87470a8bb"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1377 tree - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1377 tree)"
D="disc1.c"
if [ ! -f "$D" ]; then echo "disc1.c MISSING"; exit 0; fi
echo "===GETINTR424=== getintr (0x800415B4): the full body"
F=$(grep -n -e "0x800415B4 (function)" "$D" | head -1 | cut -d: -f1)
echo "getintr at line: $F"
if [ -n "$F" ]; then
  awk -v s="$F" -v e="$((F+140))" 'NR>=s && NR<=e { print NR": "$0 }' "$D" | head -142
fi
echo "===CLASSCELL424=== the class cell: 0x80056770's pointer value + the class writers"
echo "--- all 0x6770 references in disc1.c:"
grep -n -e "0x6770" "$D" | head -12
echo "--- all 0x6774 references (the likely class byte target):"
grep -n -e "0x6774" "$D" | head -12
for LN in $(grep -n -e "0x6774" "$D" | grep -e "SB(" -e "SW(" | head -3 | cut -d: -f1); do
  echo "--- class-writer context at line $LN (-25/+5):"
  awk -v s=$((LN-25)) -v e=$((LN+5)) 'NR>=s && NR<=e { print NR": "$0 }' "$D"
done
echo "===CHECKCALLBACK424=== CheckCallback (0x8004B894)"
F2=$(grep -n -e "0x8004B894 (function)" "$D" | head -1 | cut -d: -f1)
echo "CheckCallback at line: $F2"
if [ -n "$F2" ]; then
  awk -v s="$F2" -v e="$((F2+50))" 'NR>=s && NR<=e { print NR": "$0 }' "$D"
fi
echo "===BIT2CONT424=== the continuation past the bit2 check (from line 129500, +60)"
awk -v s=129500 -v e=129560 'NR>=s && NR<=e { print NR": "$0 }' "$D"
echo "===TIMEOUT424=== 80042A54 (bare-address grep: split chunk)"
grep -n -e "80042A54" "$D" | head -6
F3=$(grep -n -e "80042A54" "$D" | head -1 | cut -d: -f1)
if [ -n "$F3" ]; then
  awk -v s="$F3" -v e="$((F3+40))" 'NR>=s && NR<=e { print NR": "$0 }' "$D" | head -42
fi
echo "===C424DONE=== the getintr contract + the class-writer side are decoded - R1378 follows from these receipts only"
