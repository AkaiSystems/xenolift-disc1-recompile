#!/bin/bash
# c435_zrfbody.sh - READ-ONLY CENSUS. NO run, NO patch.
# The c434 receipts named the walk's servers: zrfB
# (R1280 system-band serve v2) 6 flushes through LBAs
# 1-6 then silent; zrf0 (R515/R511) at 'fire #13'
# (cap suspected); LBA 7 got a REAL serve ([fldsec]
# #272); LBA 9 got NOTHING. And the game MOVED ON: no
# [bp] probe/pump after ~31900, mount-cell
# 0x800592C8 oscillated then stopped, movie player
# polls pre-movie with stale (seek=9, FDF8=0x800)
# cells - the CALLER is the stall; the remount must
# CONCLUDE for the movie phase to re-engage. THIS
# PASS: (1) the zrfB body (5386+) - gates, budget,
# serve mechanism; (2) the zrf0 doors' fire caps
# (R515/R511); (3) ALL cd_pending_stamp call sites
# (find the site-5 arm); (4) the FDE4 gate contexts
# (5716's 25s gate, 11259's install-mode write);
# (5) the game-side walk entries at LBA 8-9: did the
# dirloop/FILE-CB/paentry even enter for LBA 9?
# Receipts only - the repair follows from these only.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C435-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="6c916b3fc08cc29c92247a12aaea6cd4f294e9c395164490e737ab690b782737"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1378 tree - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1378 tree)"
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
echo "===ZRFB435=== the zrfB body (5380-5475): gates, budget, serve mechanism"
awk 'NR>=5380 && NR<=5475 { print NR": "$0 }' "$SRC" | head -96
echo "===ZRF0435=== the zrf0 doors (R515/R511): fire caps"
grep -n -e "R515" "$SRC" | head -5
grep -n -e "R511" "$SRC" | head -5
LN=$(grep -n -e "zrf0" "$SRC" | head -1 | cut -d: -f1)
echo "--- zrf0 first ref at $LN (+32):"
if [ -n "$LN" ]; then awk -v s="$LN" -v e=$((LN+32)) 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"; fi
echo "===STAMPS435=== ALL cd_pending_stamp call sites (find the site-5 arm)"
grep -n -e "cd_pending_stamp" "$SRC" | head -26
echo "===FDE4GATES435=== the FDE4 gate contexts"
echo "--- the 25s-gated reader (5708-5730):"
awk 'NR>=5708 && NR<=5730 { print NR": "$0 }' "$SRC"
echo "--- the install-mode write (11250-11272):"
awk 'NR>=11250 && NR<=11272 { print NR": "$0 }' "$SRC"
echo "===WALKSIDE435=== the game-side walk entries at LBA 8-9"
echo "--- paentry/cbcall/dirloop after 31780:"
grep -n -e "paentry" "$LOG" | awk -F: '$1 > 31780' | head -5
grep -n -e "cbcall" "$LOG" | awk -F: '$1 > 31780' | head -5
grep -n -e "dirloop" "$LOG" | awk -F: '$1 > 31780' | head -5
echo "--- the LBA-9 era raw window (31880-31935):"
awk 'NR>=31880 && NR<=31935 { print NR": "$0 }' "$LOG" | head -56
echo "===C435DONE=== the serve arm's budget + the game-side LBA-9 posture are receipted - the repair follows from these receipts only"
