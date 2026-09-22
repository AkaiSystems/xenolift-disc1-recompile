#!/bin/bash
# c389_movieposture.sh - READ-ONLY CENSUS. NO run, NO patch.
# The c388 verdict: R1368 let the first complete uninterrupted
# native file#14 read drain (125304 bytes, FE04 108940-108995,
# FDF8 to 0), the R1005 staged path expanded the whole member
# (LZSS 260862 of 260862), the ladder hit #66, the GPU got
# 944,490 gp0 words + 8,060 drawing-list DMA sends, and the
# game reached THE PRE-MOVIE POLL. TWO RESIDUALS: (1) the
# game's unpack still fires mid-read at ~58% (prod=-1 ->
# Module-6 fail -> 3 boot cycles); (2) the movie-band ReadN
# (seek=239322, ladder #61) arms pend=3 sched=1 but FDF8=0 -
# NO LENGTH ARMED - so no sector can serve; the spin holds
# last_cmd=09 FE1C=6 A22C=3. THIS PASS: the movie-posture
# anatomy from the existing log.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C389-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="456a8dcd3e3987a3ff79b490133d5ff63c6f1f2961dfbd6d9b336d945da7e141"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1368 tree - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1368 tree)"
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
if [ ! -s "$LOG" ]; then echo "TREE-ROOT-LOG-MISSING"; exit 0; fi
echo "AUTHORITATIVE LOG = $LOG ($(wc -l < "$LOG" | tr -d ' ') lines)"
echo "===LADDERWIN389=== the movie-request window (the ladder #58-#66, lines 31150-31450)"
awk 'NR>=31150 && NR<=31450 { print NR": "$0 }' "$LOG" | grep -v "lzss-fence\|narrowblast\|bandhist" | head -60
echo "===MOVIELEN389=== the movie serve length story (seek 239322 + FDF8)"
grep -n "seek=239322\|0003A6DA\|0003a6da" "$LOG" | grep -v "mvloop\|waitbr\|parkcam\|fldfrz2" | head -24
echo "===MOVIEREQ389=== the movie request formation (Setloc/ReadN at 239322: who armed what)"
grep -n "Setloc BCD.*239\|READ ISSUED\|smq\|arc\]" "$LOG" | awk -F: '$1>=31000 && $1<=31450' | head -20
echo "===A22C389=== the A22C=3 hold (when did it become 3, who writes it)"
grep -n "A22C" "$LOG" | grep -v "mvloop\|waitbr\|parkcam" | head -16
echo "===MDEC389=== the MDEC receipts (what are the 944K words drawing?)"
grep -n "mdec\|MDEC" "$LOG" | head -14
echo "===GPU389=== the gp0/dma2 story (drawing lists receipted when?)"
grep -n "R694 live" "$LOG" | head -6
grep -n "dma2" "$LOG" | grep -v "R694" | head -8
echo "===EPOCH389=== the boot epoch timeline (3 cycles: the mid-read unpack chain)"
grep -n "bootentry\|bootmain\|fn_80019ACC" "$LOG" | head -14
echo "===MIDUNPACK389=== the mid-read unpack trigger (the window around 12750)"
awk 'NR>=12700 && NR<=12760 { print NR": "$0 }' "$LOG" | head -12
echo "===FLDX389=== the R1005 staged-expansion receipts (the oracle landing)"
grep -n "fldx2\|RETARGET" "$LOG" | head -10
echo "===SCR389=== the display/VRAM story (page 2: is anything drawn?)"
grep -n "R693 snap\|R695 regions\|R736 band census" "$LOG" | tail -8
echo "===C389DONE=== the movie-posture anatomy is receipted"
