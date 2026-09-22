#!/bin/bash
# c433_lba9diff.sh - READ-ONLY CENSUS. NO run, NO patch.
# The c432 verdict: the LBA-9 park is a GENUINE
# system-ring walk stalled one sector short. The game
# reset FE04 to 0 and walked the disc start one
# 2048B sector/step (FDF8 armed 0x800 per step at fn
# 800409E4, FE04 stepping at fn 80040FCC, sectors
# consumed through LBA 8, INTs armed by SITE-5/cdf
# receipted per-step). Parked at 9: FDF8=0x800 owed,
# cmd=09, pend=0, no arm fired, data=0/0, and the
# game's settle-fn 0x8004247C wrote A22C 2->3 (the
# game believes data arrived). KEY: cd_seek_lba
# STALE at 109166 while FE04 walked 0-9 - every
# FE04==cd_seek_lba gate is dead this era. THIS PASS:
# the LBA-8-served vs LBA-9-stalled DIFFERENTIAL:
# (1) the arm-site ladder through the whole walk
# (pendclr tail - where the arms STOPPED); (2) the
# walk-era serve receipts tag-filtered (req/fdw/bp/
# cbcall/cmdtl/adv599/cdf/schdd/fldsec); (3) the raw
# pre-park window; (4) the A22C writer + settle-fn
# receipts; (5) the FE08 ring receipts. Receipts
# only - the next repair follows from these only.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C433-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="6c916b3fc08cc29c92247a12aaea6cd4f294e9c395164490e737ab690b782737"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1378 tree - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1378 tree)"
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
echo "===WALKMAP433=== the arm-site ladder through the walk (where the arms STOPPED)"
grep -n -e "pendclr" "$LOG" | awk -F: '$1 > 31040' | head -16
echo "--- the LAST walk-era arms:"
grep -n -e "pendclr" "$LOG" | awk -F: '$1 > 31040' | tail -12
echo "--- fldsec consumption tail:"
grep -n -e "fldsec" "$LOG" | tail -10
echo "===LASTSTEP433=== the walk-era serve receipts (31040-31970, tag-filtered, last 36)"
awk 'NR>=31040 && NR<=31970 && (/fldsec/ || /req\]/ || /fdw\]/ || /bp\]/ || /cbcall/ || /cmdtl/ || /adv599/ || /cdf/ || /schdd/ || /slot\]/)' "$LOG" | tail -36
echo "===PREPARK433=== raw window 31935-31966 (the immediate pre-park)"
awk 'NR>=31935 && NR<=31966 { print NR": "$0 }' "$LOG" | head -32
echo "===A22CWR433=== the A22C writer + settle-fn receipts"
grep -n -e "8006A22C" "$LOG" | tail -5
grep -n -e "0x8004247C" "$LOG" | tail -5
echo "===RING433=== FE08 ring receipts walk-era tail"
grep -n -e "FE08" "$LOG" | awk -F: '$1 > 31040' | tail -10
echo "===C433DONE=== the LBA-8 vs LBA-9 differential is receipted - the repair follows from these receipts only"
