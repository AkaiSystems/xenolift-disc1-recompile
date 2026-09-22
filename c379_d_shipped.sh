#!/bin/bash
# c379_memberwalk.sh - READ-ONLY. NO patch, NO run. The c378
# correction: the archive Pause COMPLETED and the game is
# walking the archive band natively (member=6 at LBA 239411
# requested, DATA HANDLERs consuming, zero rescue fires).
# The c368 deep path reached file#14 at t=31s; the fresh
# path walks the archive at its own pace and the fuse cut
# it mid-member. THIS PASS: map the member walk - every
# member request, the per-member FDF8 drains and timing,
# the boot tails before each fuse kill, the announce-probe
# presence, and any movie-area/file-14 LBAs - to decide
# advance-vs-loop, then single-boot-long-run vs fix.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C379-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="13bc3bafa00d1cb05ddb1496adb335b94c3a49658a5206c2f4f74bd2d7b6c104"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1366 tree - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1366 tree)"
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
if [ ! -s "$LOG" ]; then echo "TREE-ROOT-LOG-MISSING"; exit 0; fi
echo "AUTHORITATIVE LOG = $LOG ($(wc -l < "$LOG" | tr -d ' ') lines)"
echo "===MEMBERWALK379=== every archive member request (the walk order)"
grep -n "stab\] req member=" "$LOG" | head -30
echo "===MEMBERCOUNT379=== the walk census"
echo "member-reqs $(grep -c "stab\] req member=" "$LOG" || true)"
echo "sm6-entries $(grep -c "sm6\] state-6 entry" "$LOG" || true)"
echo "cdcsync $(grep -c "cdcsync" "$LOG" || true)"
echo "data-handlers $(grep -c "DATA HANDLER enter" "$LOG" || true)"
echo "R1360-pauses $(grep -c "R1360 module-era Pause" "$LOG" || true)"
echo "xfer-arms $(grep -c "STREAM-ARM" "$LOG" || true)"
echo "xfer-retires $(grep -c "STREAM retire" "$LOG" || true)"
echo "===ARCHLBA379=== the archive-region sector serves (239xxx band)"
grep -n "LBA 239" "$LOG" | grep -c "loaded into data FIFO" || true
grep -n "sector LBA 239" "$LOG" | grep "loaded into data FIFO" | awk -F: '{ print $1" "$2 }' | tail -12
echo "===FDF8WALK379=== the DATA HANDLER drain story (FDF8 per entry)"
grep -n "DATA HANDLER enter" "$LOG" | tail -14
echo "===TAILBOOT1379=== boot-1 tail: the last 60 receipts before the first fuse"
B1L=$(grep -n "rungasp\] R806 process exit status=137" "$LOG" | head -1 | cut -d: -f1)
echo "boot-1 fuse at line $B1L"
if [ -n "$B1L" ]; then
  S=$((B1L-60)); [ $S -lt 1 ] && S=1
  awk -v s="$S" -v e="$B1L" 'NR>=s && NR<=e { print NR": "$0 }' "$LOG"
fi
echo "===TAILBOOT2379=== boot-2 tail: the last 60 receipts before the second fuse"
B2L=$(grep -n "rungasp\] R806 process exit status=137" "$LOG" | tail -1 | cut -d: -f1)
echo "boot-2 fuse at line $B2L"
if [ -n "$B2L" ] && [ "$B2L" != "$B1L" ]; then
  S=$((B2L-60)); [ $S -lt 1 ] && S=1
  awk -v s="$S" -v e="$B2L" 'NR>=s && NR<=e { print NR": "$0 }' "$LOG"
fi
echo "===ANNOUNCE379=== the module-file announce probe (did ANY module announce happen?)"
grep -n "800295D8\|announce\|R490 DIR-LOOKUP" "$LOG" | head -10
echo "===MOVIEMARK379=== any movie-area or file-14 LBA in this run"
grep -n "109166\|108933\|109158" "$LOG" | head -6
echo "===TIMING379=== the walk pacing (first/last sm6 + stab with t markers)"
grep -n "sm6\] state-6 entry" "$LOG" | head -4
grep -n "@t=" "$LOG" | awk -F: '$1>8200 && $1<12000' | head -8
echo "===C379DONE=== the member walk is mapped"
