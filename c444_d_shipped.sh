#!/bin/bash
# c444_transition.sh - READ-ONLY BOOT-TRANSITION
# CENSUS on the preserved R1379 run.log (tree c9e85ea1
# verified). NO run, NO patch, NO build. The c443
# receipts: boot A served file#14 sector by sector
# (108933-108938, act=1, DMA delivering, FE04
# advancing) and reached MODULE 6 ENTRY (0x800737EC,
# 'boot wall BROKEN'); the tail section then holds a
# SECOND boot (the pendclr counter went backwards,
# clears 183 -> 125) whose file#14 ReadN (LBA 108933)
# NEVER serves - armed-not-served, the act=0 class.
# The log is logcap-truncated (17MB raw, head 16k +
# tail 16k). THIS PASS: (1) boot-transition receipts:
# what ended boot A (rungasp/SIGSEGV/exit doors +
# epoch banners); (2) mod6 entries per boot (did boot
# B reach the module?); (3) boot-B's site-5 arm source
# (the R1376 family); (4) boot-B fetch entries (act
# anywhere?); (5) boot-B READ ISSUED + DATA HANDLER;
# (6) the raw window at boot-B's first site-5
# treadmill receipt. Receipts only - R1380 follows
# from these only.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C444-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="c9e85ea1d9c6ebfd9145cc948dffd37826385f58bd947267ec37b0d39c34b5fb"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1379 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the R1379 tree)"
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
echo "===TRANSITION444=== boot-transition receipts (what ended boot A)"
grep -n -e "rungasp" "$LOG" | head -6
grep -n -e "SIGSEGV\|BadVAddr\|TRUE DEATH" "$LOG" | head -6
grep -c -e "exit status=99" "$LOG"
echo "--- epoch/boot banners:"
grep -n -e "boot epoch\|BOOT ENTRY\|bootentry\|re-entry\|reentry" "$LOG" | head -8
echo "===MOD6_444=== module-6 entries per boot"
grep -n -e "mod6" "$LOG" | head -10
echo "===ARMSRC444=== boot-B's site-5 arm source (the R1376 family)"
grep -n -e "R1376" "$LOG" | head -8
grep -n -e "R1376" "$LOG" | awk -F: '$1 > 20000' | tail -6
echo "===FETCH444=== boot-B fetch entries (act anywhere in the tail?)"
grep -n -e "fetchcam" "$LOG" | awk -F: '$1 > 20000' | head -6
echo "--- act=1 receipts after line 20000:"
grep -n -e "act=1" "$LOG" | awk -F: '$1 > 20000' | head -6
echo "===REQ444=== boot-B READ ISSUED + DATA HANDLER"
grep -n -e "READ ISSUED" "$LOG" | awk -F: '$1 > 20000' | head -6
grep -n -e "DATA HANDLER enter" "$LOG" | awk -F: '$1 > 20000' | head -4
echo "===TREAD444=== the raw window at boot-B's first site-5 treadmill receipt"
LN=$(grep -n -e "site=5 cmd=06 LBA=108933" "$LOG" | awk -F: '$1 > 20000' | head -1 | cut -d: -f1)
echo "first tail-section site-5 receipt at line: $LN"
if [ -n "$LN" ]; then
  awk -v s=$((LN-30)) -v e=$((LN+3)) 'NR>=s && NR<=e { print NR": "$0 }' "$LOG"
fi
echo "===C444DONE=== the boot transition + boot-B arm source are receipted - R1380 follows from these only"
