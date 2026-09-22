#!/bin/bash
# c384_walkwatch.sh - RUN + END-POSTURE CENSUS. NO patch. The
# c383 verdict: R1367 (the phantom-backlog guard) LANDED and
# the game blasted past the archive wedge (ladder #39, the
# deepest ever; member=18 announced + read; the file#3 big
# archive read armed at the kill). The fuse cut it mid-walk
# with no demonstrated wedge - the walk needs TIME, not a
# fix. THIS CYCLE: rerun the R1367 tree UNCHANGED at 120s and
# census the walk: the file#3 read serve (LBA 108785), the
# ladder depth, the module walk, R1366's whole-member fire
# (if the path reaches file-14), the faults, and the
# end-posture tail.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C384-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="52566422c865ec549026ce84b82e19a568b61b0cdd1e78984656a5b55cc437f2"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1367 tree - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1367 tree)"
echo "===RUN384=== the unchanged R1367 build, 120s budget"
RUN_BUDGET_S=120 ./run.sh > /tmp/run_full_c384.txt 2>&1
RUN_RC=$?
echo "RUN_RC=$RUN_RC"
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
if [ ! -s "$LOG" ]; then
  echo "TREE-ROOT-LOG-MISSING: preserving run_full tail"
  tail -25 /tmp/run_full_c384.txt
  exit 0
fi
echo "AUTHORITATIVE LOG = $LOG ($(wc -l < "$LOG" | tr -d ' ') lines)"
echo "===LADDER384=== the ladder (the depth story)"
grep -n "cmdtl\]" "$LOG" | tail -14
LB=$(grep -n "cmdtl\]" "$LOG" | tail -1 | sed 's/.*R533 #\([0-9]*\).*/\1/')
echo "MAX-LADDER=$LB"
echo "===FILE3SERVE384=== the file#3 big read serve (LBA 108785-108860)"
grep -n "sector LBA 10878[5-9]\|sector LBA 10879\|sector LBA 1088" "$LOG" | grep "loaded into data FIFO" | head -8
grep -n "FDF8=155120\|00025DF0" "$LOG" | head -6
echo "===R1367GUARD384=== the phantom blocks (should stay ~5)"
grep -c "R1367: phantom" "$LOG" || true
echo "===MEMBER384=== the module walk (member announces, full story)"
grep -n "newmod\]" "$LOG" | head -16
echo "===R1366FIRE384=== the whole-member carry (file-14 reached?)"
grep -n "R1366" "$LOG" | head -6
echo "===FTAB384=== the module-file reads issued"
grep -n "READ ISSUED" "$LOG" | head -10
echo "===LZHLE384=== the decode receipts"
grep -n "lzss-hle" "$LOG" | head -12
echo "===WEDGE384=== the spin census"
echo "wedgespin-total $(grep -c "wedgespin" "$LOG" || true)"
grep -n "wedgespin" "$LOG" | tail -4
echo "===FAULTS384=== the fault census"
echo "computed-garbage $(grep -c "computed-garbage" "$LOG" || true)"
echo "firstfault $(grep -c "firstfault\] R1172 BEGIN" "$LOG" || true)"
echo "lzss-runaway $(grep -c "lzss-runaway" "$LOG" || true)"
echo "segvdie $(grep -c "segvdie" "$LOG" || true)"
echo "===VIS384=== the exit + gpu story"
grep -n "rungasp" "$LOG" | tail -2
grep -n "gp0_words" "$LOG" | tail -3
grep -n "screen\] R693 snap" "$LOG" | tail -2
echo "===TAIL384=== the last 30 receipts before the end"
TL=$(wc -l < "$LOG" | tr -d ' ')
S=$((TL-30)); [ $S -lt 1 ] && S=1
awk -v s="$S" -v e="$TL" 'NR>=s && NR<=e { print NR": "$0 }' "$LOG"
echo "===C384DONE=== the walk census is receipted"
