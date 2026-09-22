#!/bin/bash
# c228_module_consume.sh - READ-ONLY: no patch, no compile, no run.
# The c227 receipts: the state-1 mount completes (92BC=801DD680), the
# member-14 read ISSUES and the field-band machinery SERVES it (fetchcam
# FDF8 countdown in the 108970+ band), abort-130=0, unpack-fix=0 - but
# the boot re-enters 8 times without ever entering state 1 (cur census:
# FFFFFFFF/6/0 only) and the digest's tail-capped sections CUT the
# era-1/2 door + unpack receipts, so the module-consumption question is
# OPEN, not answered. This extraction settles it: (1) does ANY unpack/
# lzss receipt consume src=801DD680 in ANY era; (2) the era-2 read
# window in full (countdown + completions + the FDF8 59C->FFFFFD9C->0
# underflow at fn 8002A394); (3) the door receipts at the member-14
# moments; (4) the dispatch receipts before each boot re-entry - the
# verdict that sends the game back to boot instead of into state 1.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C228-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
LOG="run.log"
EXPECT="fef3377465773175d5da73910926f0902cd7fde8ce421271874d98f406f43685"
if [ ! -s "$LOG" ]; then echo "C228-FAILED: run.log missing"; exit 1; fi
SS=$(shasum -a 256 "$LOG" | cut -d" " -f1)
echo "LOG_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: run.log is not the c227 post-run log - refusing a foreign log"; exit 0; fi
echo "BASELINE_VERIFIED (the c227 post-run log)"
P="runlog_preserve_c228_$(date +%Y%m%d_%H%M%S)"
if ! (mkdir -p "$P" && cp -p "$LOG" "$P/run.log"); then echo "C228-FAILED: preserve failed"; exit 1; fi
echo "PRESERVED: $P/run.log sha=$SS size=$(wc -c < "$P/run.log" | tr -d " ")"

win() { S=$1; [ "$S" -lt 1 ] && S=1; awk -v s="$S" -v e="$2" 'NR>=s&&NR<=e{printf "%d:%s\n",NR,$0}NR>e{exit}' "$LOG"; }
rng() { awk -v s="$1" -v e="$2" 'NR>=s&&NR<=e{printf "%d:%s\n",NR,$0}NR>e{exit}' "$LOG" | grep "$3" | head -"$4"; }

echo "===DD680228=== every receipt naming the module block 801DD680"
echo "all_mentions=$(grep -c "801DD680" "$LOG")"
echo "unpack-class (a0= or r4=): $(grep -c "a0=801DD680\|r4=801DD680" "$LOG")"
grep -n "801DD680" "$LOG" | head -40

echo "===ERA2READ228=== the era-2 member-14 read window (16120-19540): countdown + completions"
rng 16120 19540 "fetchcam\|fldfin\|f18done\|cdreq\|pendclr\|sgarm\|sectserve\|fldsec" 40

echo "===ERA2REQ228=== the era-2 [req] writes (the FDF8 lifecycle incl. the underflow)"
rng 16120 19540 "\[req\]" 30

echo "===DOORSEA1_228=== the door receipts at era-1's member-14 read (11490-14900)"
rng 11490 14900 "fld2sig\|fld2arm\|fldsec\|fetchcam" 30

echo "===REENTRY228=== the dispatch receipts before each boot re-entry"
echo "--- era-1 end (14600-14940):"
rng 14600 14940 "fn_80019ACC\|rlgl\|idxw\|latchhw\|\[phase\]\|verdict\|bootmain" 30
echo "--- era-2 end (19250-19560):"
rng 19250 19560 "fn_80019ACC\|rlgl\|idxw\|latchhw\|\[phase\]\|verdict\|bootmain" 30

echo "===FDE4228=== the member-index counter trail"
grep -n "FDE4" "$LOG" | head -20

echo "===CURW228=== the cur-cell (0x800592C0) writer trail"
grep -n "mount-cell 0x800592C0" "$LOG" | head -30
echo "--- any true cur=1 receipts:"
grep -n "cur=0x00000001\|cur(92C0)=00000001\|g_CurGameState.*=00000001" "$LOG" | head -8

echo "===UNPKALL228=== every lzss/unpack entry in eras 1-2 (the consumption census)"
rng 11500 19500 "lzsscam\|unpackw\|lzss-t\|lzss-hle" 24

echo "===C228DONE=== module-consumption extraction complete - the c229 fix is decided by these receipts"
