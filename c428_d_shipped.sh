#!/bin/bash
# c428_intflag.sh - READ-ONLY CENSUS. NO run, NO patch.
# The c427 receipts show the register model is
# index-aware and case 0x1F801803 bank 1 = THE INT FLAG
# REGISTER (psx-spx, line 3787) - but its BODY is
# unseen, and that body is the decisive question: does
# the bank-1 INT-flag read expose cd_pending (& 7,
# what the kernel's getintr polls every frame) or does
# it return 0/constant? Same for the write handler's
# case 0x1F801803 (line 2295 - getintr's tail writes 7
# there as the hardware ACK). THIS PASS: (1) the
# INT-flag read body (lines 3787-3870); (2) the write
# handler cases (lines 2264-2400, all four registers);
# (3) the special blocks at 7495 and 7817 (the
# a==1F801800/802/803 ack-pair family); (4) the
# runtime's own mirror writes at 16200/16249 context;
# (5) the combo/bank read logic at 2987-3010. NO
# behavior change - receipts only. R1378 follows from
# these receipts only.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C428-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="6759e34359fdf33df2e78cfaf2c144194da718412f3d42cb022b12e87470a8bb"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1377 tree - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1377 tree)"
echo "===INTFLAGRD428=== the bank-1 INT flag register read body (3787-3870)"
awk -v s=3787 -v e=3870 'NR>=s && NR<=e { print NR": "$0 }' "$SRC" | head -84
echo "===REGWRITE428=== the write handler cases (2264-2400)"
awk -v s=2264 -v e=2400 'NR>=s && NR<=e { print NR": "$0 }' "$SRC" | head -137
echo "===SPECIALBLOCKS428=== the 7495 and 7817 blocks (7485-7530 + 7807-7840)"
awk -v s=7485 -v e=7530 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
echo "---"
awk -v s=7807 -v e=7840 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
echo "===MIRRORW428=== the runtime's mirror writes (16185-16260)"
awk -v s=16185 -v e=16260 'NR>=s && NR<=e { print NR": "$0 }' "$SRC" | head -76
echo "===COMBO428=== the combo/bank read logic (2987-3015)"
awk -v s=2987 -v e=3015 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
echo "===C428DONE=== the INT-flag read + ack-write bodies are decoded - R1378 follows from these receipts only"
