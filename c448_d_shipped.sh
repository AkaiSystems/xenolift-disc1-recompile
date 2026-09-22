#!/bin/bash
# c448_f15boundary.sh - READ-ONLY CENSUS of the
# file#15 boundary (tree 2c660613 verified). NO run,
# NO patch, NO build. The c447 receipts: the field
# mount executed end-to-end (CHANNEL F, alloc #37,
# file#14 served, menu rendered, MODULE 6 ENTRY 3x)
# but the game positions the drive at LBA 108995
# (dest 8007F2F8) with FDF8=0, the serve loads ONE
# undrained sector (loaded=1 data=0/2060), the game
# polls GetStat (02/01/01 acks then single-byte 02s,
# FE1C=0), and NO ReadN for file#15 ever issues -
# the field data never streams and the font family
# renders garbage (0x60B025xx, r31=80036708).
# THIS PASS: (1) the file#15 request story (ftab
# lookups/issuances for file#=15, the 108995 +
# 8007F2F8 receipts); (2) the GetStat poll anatomy
# (which status values served, the cmd-01 ladder,
# what follows each pop); (3) the FE1C=10 lifecycle
# (its writers/clearers at the tail); (4) the field
# module chain (80045xxx receipts); (5) the garbage
# origin (60B025xx + 80036708 receipts). Receipts
# only - R1381 follows from these only.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C448-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="2c660613e608e9f878833ece08dcb579a4f431b11c7c4e411323db2c5633f6f2"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1380 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the R1380 tree)"
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
echo "===F15REQ448=== the file#15 request story"
grep -c -e "file#=15" "$LOG"
grep -n -e "file#=15" "$LOG" | head -8
grep -n -e "108995" "$LOG" | head -10
grep -n -e "8007F2F8" "$LOG" | tail -8
echo "===GETSTAT448=== the GetStat poll anatomy"
grep -e "rspop] byte#1" "$LOG" | sed 's/.*byte#1 byte/byte/' | sed 's/ (pos.*//' | sort | uniq -c | sort -rn | head -8
echo "--- the cmd-01 ladder at the tail:"
grep -n -e "cmd 01" "$LOG" | tail -6
grep -n -e "cmd 06->01" "$LOG" | head -6
echo "--- what follows the pops (the tail around the last single-byte poll):"
grep -n -e "rspop] byte#1 val=0x02 (pos=1 n=1 last_cmd=0x01 FE1C=0)" "$LOG" | head -2 | tail -1
echo "===FE1C448=== the FE1C=10 lifecycle (writers/clearers)"
grep -n -e "chg] FE1C" "$LOG" | tail -10
grep -n -e "FE1C 000A->\|FE1C 10 ->\|FE1C 0000000A" "$LOG" | head -6
echo "===FIELDMOD448=== the field module chain (80045xxx receipts)"
grep -n -e "80045" "$LOG" | tail -8
grep -n -e "cur_fn=80045" "$LOG" | head -4
echo "===GARBAGE448=== the garbage origin (60B025xx + the font fn)"
grep -n -e "60B02" "$LOG" | head -6
grep -n -e "80036708" "$LOG" | head -6
grep -c -e "wdrop" "$LOG"
echo "===C448DONE=== the file#15 boundary is receipted - R1381 follows from these receipts only"
