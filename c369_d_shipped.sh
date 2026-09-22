#!/bin/bash
# c369_windump.sh - READ-ONLY window dump of the R1365
# witness. NO patch, NO run. The c368 receipts: the file#14
# first sector served (LBA 108933, 9597/19858 both boots -
# first ever in that range), but only ONE sector of 61, no
# DATA HANDLER copy into 801DD680 (the unpack still reads
# word0=FFFF9C30 on the empty buffer), and the game moved to
# the f15 request before the unpack faulted (exit 99).
# THIS PASS: the ~270 lines between the #6 ReadN issue and
# the unpack fault (boot 1, ~9573-9839), sampled - to receipt
# WHO served the 108933 sector, whether an INT1 armed after
# it, whether any DATA HANDLER entered for 801DD680, and what
# moved the game to 108995.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C369-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="8d14ab4f2385a0004c28bd5a07bc762c5b9407b6da8a817d96554d5e91f226b0"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1365 tree - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1365 tree)"
WD="witness_c368_20260917_144156"
LOG="$WD/run.log"
[ -s "$LOG" ] || LOG="$WD/run.log.d"
if [ ! -s "$LOG" ]; then echo "WITNESS-MISSING: the c368 witness is not on disk"; exit 0; fi
echo "WITNESS_LINECOUNT=$(wc -l < "$LOG" | tr -d ' ') lines"
echo "===WINDOW369=== boot 1 lines 9560-9850, every 6th line (the era from the ReadN issue to the unpack fault)"
awk 'NR>=9560 && NR<=9850 && (NR-9560)%6==0 { print NR": "$0 }' "$LOG"
echo "===SERVENB369=== the exact neighbors of the 108933 serve (9597 +-8)"
awk 'NR>=9589 && NR<=9605 { print NR": "$0 }' "$LOG"
echo "===HANDLER369=== every DATA HANDLER entry in boot 1 (whose dst?)"
grep -n "DATA HANDLER" "$LOG" | awk -F: '$1<=10260' | head -8
echo "===INT1ARM369=== INT1 arm receipts in the window (9560-9850)"
grep -n "INT1" "$LOG" | awk -F: '$1>=9560 && $1<=9850' | head -10
echo "===A22C369=== the A22C story in the window"
grep -n "A22C" "$LOG" | awk -F: '$1>=9560 && $1<=9850' | head -6
echo "===MOVEON369=== what moved the game to 108995: the receipts between the 108933 serve and the #7 GetStat (9597-9740), every 10th"
awk 'NR>=9597 && NR<=9740 && (NR-9597)%10==0 { print NR": "$0 }' "$LOG"
echo "===F15DST369=== the f15-era DATA HANDLER dst receipts (comparison: the working class)"
grep -n "DATA HANDLER" "$LOG" | awk -F: '$1>=9740 && $1<=10260' | head -4
echo "===FLD2SIG369=== the fld2sig UNCOND receipts in the window (the watcher state)"
grep -n "fld2sig" "$LOG" | awk -F: '$1>=9560 && $1<=9850' | head -6
echo "===C369DONE=== the stream-continuation story is receipted"
