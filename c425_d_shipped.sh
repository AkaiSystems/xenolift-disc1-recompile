#!/bin/bash
# c425_isr.sh - READ-ONLY CENSUS. NO run, NO patch.
# The c424 decode completed getintr's contract: it
# ACKNOWLEDGES (writes 1 to the class byte
# [0x80056770]), reads the STATUS byte [0x8005677C]
# & 7 (0 -> exit-empty), copies the 8-byte record
# from [0x80056774] when class bit5 is set, and
# returns a code whose bit4/bit1 dispatch the CD
# SYNC/DATA callbacks (slots 0x800564AC/0x800564A8).
# The five-stage failure is localized: getintr exits
# empty forever iff the STATUS byte target is never
# written - on hardware the game's CD ISR writes it.
# THIS PASS: (1) RUNTIME-SIDE census of the whole
# cell family (6770/6774/6778/677C/6788/64A8/64AC/
# 64C9/64D0/6550) in runtime.c - every read/write
# we already make; (2) the pointer-cell INITIALIZERS
# in disc1.c (who sets 0x80056770/74/7C, with
# context); (3) ALL getintr call sites in disc1.c
# (the ISR family will be among them); (4) getintr's
# return-code tail (the bits the kernel dispatches
# on); (5) the callback-REGISTRATION fns
# (CdDataCallback 0x800413EC / CdSyncCallback
# 0x80040FB4 / CdReadyCallback 0x80040FCC /
# CdReadCallback 0x8004373C) - which slot each
# writes. NO behavior change - receipts only.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C425-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="6759e34359fdf33df2e78cfaf2c144194da718412f3d42cb022b12e87470a8bb"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1377 tree - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1377 tree)"
D="disc1.c"
[ -f "$D" ] || { echo "disc1.c MISSING"; exit 0; }
echo "===RUNTIME425=== the runtime-side reads/writes of the event cell family"
for C in 6770 6774 6778 677C 6788 64A8 64AC 64C9 64D0 6550; do
  N=$(grep -c -e "0x${C}" "$SRC")
  echo "--- cell 0x8005${C}: ${N} runtime refs"
  if [ "$N" -gt 0 ]; then grep -n -e "0x8005${C}" "$SRC" | head -6; fi
done
echo "===PTRINIT425=== the pointer-cell initializers in disc1.c"
for C in 6770 6774 677C; do
  echo "--- stores to 0x${C}:"
  grep -n -e "0x${C}" "$D" | grep -e "SW(" | head -4
done
for LN in $(grep -n -e "0x6770" "$D" | grep -e "SW(" | head -2 | cut -d: -f1); do
  echo "--- initializer context at line $LN (-12/+8):"
  awk -v s=$((LN-12)) -v e=$((LN+8)) 'NR>=s && NR<=e { print NR": "$0 }' "$D"
done
echo "===GETINTRCALLERS425=== ALL getintr call sites in disc1.c"
grep -n -e "fn_800415B4" "$D" | grep -v -e "static void" | head -12
for LN in $(grep -n -e "fn_800415B4" "$D" | grep -v -e "static void" | head -4 | cut -d: -f1); do
  echo "--- caller context at line $LN (-18/+4):"
  awk -v s=$((LN-18)) -v e=$((LN+4)) 'NR>=s && NR<=e { print NR": "$0 }' "$D"
done
echo "===GETINTRTAIL425=== getintr's return-code tail (lines 128442-128520)"
awk -v s=128442 -v e=128520 'NR>=s && NR<=e { print NR": "$0 }' "$D"
echo "===CBREG425=== the callback-registration fns"
for FN in 800413EC 80040FB4 80040FCC 8004373C; do
  F=$(grep -n -e "0x${FN} (function)" "$D" | head -1 | cut -d: -f1)
  echo "--- $FN at line $F"
  if [ -n "$F" ]; then
    awk -v s="$F" -v e="$((F+30))" 'NR>=s && NR<=e { print NR": "$0 }' "$D" | head -32
  fi
done
echo "===C425DONE=== the ISR-side + runtime-side contracts are decoded - R1378 follows from these receipts only"
