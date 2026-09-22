#!/bin/bash
# c258_f15_dossier.sh - READ-ONLY: no patch, no compile, no run.
# THE c257 VERDICT: the R1327 site gate WORKED - the press landed at
# the polling site (writer cur_fn=8003569C r31=800358CC), the game
# polled both players (12x r4=0, 19x r4=1) and READ THE PRESS
# (btn=FFF7 in the read census - the first game-consumed injected
# press on this trajectory). BUT the menu cells never moved: the menu
# era ENDED before the press arrived (all six KernelMenuUpdate
# receipts at lines 11144-21412, t~1-3s; the press at t=6s) - the
# game had LEFT the menu and wedged at the next loading step:
# pumpcam FE1C=0 FE04=0001A9BD FDF8=0 pend=0 act=0 seek=108995 =
# THE FILE#15 ARMED-IDLE WEDGE (the known open item: f15 stamped,
# no READ ever issued, drive parked, the game polling a status bit
# that can never set while idle). THE NEXT FIRST FAULT per the
# find-the-first-fault rule: the file#15 request never converts.
# THIS CYCLE receipts the exact posture: which command the wedge
# polls, which existing door (zrfG/zrfB/sgarm/R496/defib6/mvdoor)
# DECLINED it and on which failing term, whether the runtime ftab
# READ path was ever reached, the ftab row for file#15, and the
# menu-vs-press timing. The c259 serve fix is decided by these
# receipts.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C258-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
LOG="run.log"
EXPECT="aaddcf538f198788678308b421dd6209177c4a1c6cd58bd3b89be5f37baf16bc"
if [ ! -s "$LOG" ]; then echo "C258-FAILED: run.log missing"; exit 1; fi
SS=$(shasum -a 256 "$LOG" | cut -d" " -f1)
echo "LOG_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: run.log is not the c257 post-run log"; exit 0; fi
echo "BASELINE_VERIFIED"
P="f15_c258_$(date +%Y%m%d_%H%M%S)"
if ! (mkdir -p "$P" && cp -p "$LOG" "$P/run.log"); then echo "C258-FAILED: preserve failed"; exit 1; fi
echo "PRESERVED: $P/run.log sha=$SS"

echo "===F15STORY258=== the file#15 receipts (line-numbered, full story)"
grep -n "file#=15\|f15pump\|108995\|92180" "$LOG" | head -20
echo "--- READ ISSUED census (what DID issue?):"
grep -n "READ ISSUED" "$LOG" | head -12

echo "===WEDGE258=== the wedge-era drive posture (the door terms)"
grep -n "pumpcam" "$LOG" | tail -8
echo "--- the cdstate/getstat census of the wedge era:"
grep -n "CD-STATE\|cdstate\|GetStat" "$LOG" | tail -8
echo "--- which command does the wedge poll:"
grep -o "last_cmd=[0-9A-F]*" "$LOG" | sort | uniq -c | head -6

echo "===DOORDECL258=== which doors armed/declined at this posture"
grep -n "sgdecline\|sgarm\|zrfB\|zrfG\|R496\|defib6\|mvdoor\|R477\|R1267" "$LOG" | tail -16
echo "--- the ftab row + the request stamps:"
grep -n "ftab\] file#" "$LOG" | head -8
grep -n "mtrans\] R648" "$LOG" | head -6

echo "===MENUTIMING258=== the menu era vs the press timing"
grep -n "menuchain\]\|padvpx\]" "$LOG" | head -16
echo "--- wall-time anchors around the press:"
grep -n "@t=1s\|@t=6s\|@t=7s\|@t=11s" "$LOG" | tail -8

echo "===STATE258=== the mount + trap story this run"
echo "bootmain=$(grep -c bootmain "$LOG") traps=$(grep -c "NULL-trap #" "$LOG") abort131=$(grep -c "code=131" "$LOG")"
grep -n "arenaseed\]" "$LOG" | head -4
grep -n "active state" "$LOG" | tail -4
echo "--- the f15pump cbtab dumps:"
grep -n "f15pump" "$LOG" | head -4

echo "===C258DONE=== f15 dossier complete - the c259 serve fix is decided by these receipts"
