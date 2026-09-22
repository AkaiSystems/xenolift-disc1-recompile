#!/bin/bash
# c390_moviereq.sh - READ-ONLY CENSUS. NO run, NO patch.
# The c389 anatomy: the game reached the movie state machine
# (sm10/sm11 receipted) and walks archive members 10/11 (LBA
# 239542/239583, sizes 82080/153864) plus STR setlocs
# (239317/239322) - but every movie-band request holds FDF8=0
# and the length-driven serve cannot start. THIS PASS: the
# sm10/sm11 state walk, the member-10/11 request chain (any
# cmd 06 issued at 239542/239583? any sectors served at
# 2393xx?), the ladder-#61 serve decisions (schdw), the
# A22C=3 writer, and the armst site code - the exact anatomy
# for the R1369 movie-band serve design.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C390-FAILED: xenolift dir missing"; exit 1; }
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
echo "===SMWALK390=== the state-10/11 walk (all entries)"
grep -n "sm10\]\|sm11\]" "$LOG" | head -20
echo "===MEMCHAIN390=== the member 10/11 request chain (reads issued? sectors served?)"
grep -n "239542\|239583" "$LOG" | head -14
grep -n "READ ISSUED" "$LOG" | grep -v "file#=14\|file#=18" | head -8
echo "===STRSECT390=== every sector serve at the movie band (LBA 2393xx)"
grep -n "sector LBA 2393" "$LOG" | head -12
echo "count: $(grep -c "sector LBA 2393" "$LOG" || true)"
echo "===LADDER61390=== the #61 ReadN window (lines 31240-31320)"
awk 'NR>=31240 && NR<=31320 { print NR": "$0 }' "$LOG" | grep -v "lzss-fence\|narrowblast\|bandhist" | head -40
echo "===SCHDW390=== the scheduler decisions at the movie ReadN"
grep -n "schdw\]" "$LOG" | awk -F: '$1>=31240 && $1<=31410' | head -12
echo "===A22CW390=== the A22C=3 writer (the 0->3 transition)"
grep -n "A22C" "$LOG" | grep "0003\|-> 00000003\|arg=00000003" | head -10
grep -n "8006A22C" "$LOG" | head -10
echo "===ARMSTSITE390=== the armst site code (what the state-11 arm expects)"
LG=$(grep -n "armst\]" "$SRC" | head -1 | cut -d: -f1)
echo "armst print at line $LG"
if [ -n "$LG" ]; then
  S=$((LG-40)); [ $S -lt 1 ] && S=1
  E=$((LG+10))
  awk -v s="$S" -v e="$E" 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
fi
echo "===FDF8ZERO390=== the movie-era FDF8 writer census (who wrote 0 at the movie band)"
grep -n "FDF8 ARM-CONTEXT" "$LOG" | awk -F: '$1>=31000 && $1<=31500' | head -10
echo "===WAITBR390=== the LegacyCdDataWait caller anatomy (the spin's exit contract)"
grep -n "waitbr" "$LOG" | head -4
echo "===C390DONE=== the movie-request anatomy is receipted"
