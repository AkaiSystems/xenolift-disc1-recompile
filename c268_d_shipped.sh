#!/bin/bash
# c268_wedge_dossier.sh - READ-ONLY dossier on the preserved c267 run
# log. THE c267 VERDICT: the R1329 widen applied perfectly (tree
# 513eb593) but zrfG STILL zero fires - with zrfG2 (R1303) also open
# and silent, BOTH serve sites are cold at this wedge's poll rate
# (the 65536-poll stuck-confirms never began). BUT the WATCHER
# doorbell path RAN: 4 mvdoor-near receipts fired during the wedge
# (the watcher sees the posture every tick - no site dependency).
# Per the c259 dump of the R887 gate, the receipted failing terms:
# seek 108995 is OUTSIDE the mvdoor band [108700,108900], and
# FE48(5F)=1 where the gate requires 0 (FE1C=0 passes; A22C
# already dropped by R891). THE NEXT FIX is likely a watcher-door
# widen - but FE48's role must be receipted first (a response-pending
# cell must not be force-bypassed blindly). THIS DOSSIER receipts:
# (1) the full tag census of the wedge window (what the loop
# actually touches, at what cadence); (2) the 4 mvdoor-near lines
# in full; (3) every FE48 receipt in the log (writers, changes,
# mirrors); (4) the cdstate + response-pop census; (5) the pumpcam
# cadence. No patch, no compile, no run.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C268-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
LOG="patch_c265_20260917_075409/run.log.post"
EXPECT="211b4a7544faa0d4ecdbb84953d9bd0a8893e46edbdfc8af1f5460b2c73e8e53"
if [ ! -s "$LOG" ]; then echo "C268-FAILED: preserved log $LOG missing"; exit 1; fi
SS=$(shasum -a 256 "$LOG" | cut -d" " -f1)
echo "LOG_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: preserved log sha mismatch - refusing a foreign log"; exit 0; fi
echo "BASELINE_VERIFIED (the c267 post-run log)"

W1=$(grep -n "f15 request stamped" "$LOG" | head -1 | cut -d: -f1)
ENDL=$(wc -l < "$LOG" | tr -d " ")
echo "wedge_start_line=$W1 end_line=$ENDL"
win() { S=$1; [ "$S" -lt 1 ] && S=1; awk -v s="$S" -v e="$2" 'NR>=s&&NR<=e{printf "%d:%s\n",NR,$0}NR>e{exit}' "$LOG"; }

echo "===TAGS268=== the wedge-window receipt-tag census (what the loop touches)"
if [ -n "$W1" ]; then
  win "$W1" "$ENDL" | grep -o "\[[a-z0-9]*\]" | sort | uniq -c | sort -rn | head -30
fi

echo "===MDOOR268=== the mvdoor-near receipts in full (the watcher saw the posture)"
grep -n "mvdoor-near" "$LOG" | head -8

echo "===FE48W268=== every FE48 receipt (writers, changes, mirrors - is it response-pending?)"
grep -n "FE48" "$LOG" | grep -v "mvdoor-near\|pumpcam" | head -16

echo "===NEARCTX268=== context around the first mvdoor-near (what ran alongside)"
M1=$(grep -n "mvdoor-near" "$LOG" | head -1 | cut -d: -f1)
if [ -n "$M1" ]; then win "$((M1-12))" "$((M1+6))" "$LOG" | head -18; fi

echo "===CD268=== the cdstate + response-pop census of the window"
win "$W1" "$ENDL" | grep "cdstate\|rspop01" | head -14

echo "===CADENCE268=== the pumpcam cadence (rounds/lines - the loop's heartbeat)"
win "$W1" "$ENDL" | grep "pumpcam" | head -3
win "$W1" "$ENDL" | grep "pumpcam" | tail -3
echo "pumpcam_in_window=$(win "$W1" "$ENDL" | grep -c pumpcam)"
echo "padrd_in_window=$(win "$W1" "$ENDL" | grep -c padrd)"
echo "rspop_in_window=$(win "$W1" "$ENDL" | grep -c rspop01)"

echo "===DISSOLVE268=== how the wedge ended (cells cleared, by what receipt)"
grep -n "FDF8=00000000\|FDF8=0 " "$LOG" | awk -F: -v w="$W1" '$1>w' | head -6

echo "===C268DONE=== wedge dossier complete - the mvdoor widen (or its rejection) is decided by these receipts"
