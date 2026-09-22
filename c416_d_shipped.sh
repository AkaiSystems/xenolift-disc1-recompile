#!/bin/bash
# c416_waitanatomy.sh - READ-ONLY CENSUS. NO run, NO patch.
# The c415 verdict: the command ladder into the
# seek=109166 spin is COMPLETE and CORRECT (movie read ->
# Pause -> Setloc 109158 (FDF8=14360, file#18) -> ReadN
# (5 clean INT1 deliveries, data handler ran) -> advance
# to 109166 -> Pause (INT3+INT2 acked) -> GetStat acked
# -> Setloc 109166 acked) - NO stranded events, every
# handshake acked. The game then NEVER issues the movie
# ReadS and spins ~28M iterations polling LegacyCdDataWait
# with ALL camera-listed exit conditions holding
# (FDFC=0 ret=0 FE1C=0). Per c1306: the loop's REAL
# release contract is something else. THE TWO HELD CELLS
# are the prime candidates: FE48=1 (the R874 DOOR
# register - c305: 'hangs while the Door register flag
# is active') and A22C=4 (the CD-data-arrived/timeout
# cell - R1291 site: 'entries present + 0 movq = gate
# declined'). THIS PASS extracts: (1) FE48's FULL writer
# trace (who set it 1, when, who ever writes 0); (2)
# A22C=4's writer moment + context; (3) the
# LegacyCdDataWait release contract at the spin (the
# [cdcsync] R1309/R874 receipts in the spin era); (4) the
# file#18 read-completion story (the 14360 bytes, dest
# 801F3300 region, fldfin/reshtail); (5) the spin-start
# window (the receipts around the first mvloop at
# seek=109166); (6) the state ladder (F0C=18 story).
# NO behavior change - receipts only. R1378 follows from
# these receipts only.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C416-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="6759e34359fdf33df2e78cfaf2c144194da718412f3d42cb022b12e87470a8bb"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1377 tree - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1377 tree)"
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
if [ ! -s "$LOG" ]; then echo "LOG-MISSING: cannot census"; exit 0; fi
TL=$(wc -l < "$LOG" | tr -d ' ')
echo "AUTHORITATIVE LOG = $LOG ($TL lines)"
echo "===FE48WRITER416=== the DOOR register's full writer trace (who set 1, who ever clears)"
grep -n "FE48" "$LOG" | grep -v "mvloop" | head -20
echo "--- when did FE48 become 1? (the transition receipts)"
grep -n "FE48.*->\|chg\].*FE48\|req\].*FE48\|hook\].*FE48" "$LOG" | head -10
echo "===A22CWRITER416=== the A22C=4 writer moment + context"
grep -n "A22C" "$LOG" | grep -v "mvloop\|parkcam\|fldfrz" | grep "00000004\|-> 00000004" | head -8
grep -n "tblw\].*A22C" "$LOG" | head -10
echo "===CDSYNC416=== the LegacyCdDataWait release contract at the spin (the cdcsync/waitbr receipts in the era)"
grep -n "cdcsync\|waitbr\|LegacyCdDataWait" "$LOG" | grep -v "mvloop" | tail -14
echo "===F18STORY416=== the file#18 read-completion story (14360 bytes, the dest region)"
grep -n "fldfin\|reshtail\|801F3300\|109158" "$LOG" | grep -v "fe34fix\|pendclr" | head -12
echo "===SPINSTART416=== the spin-start window (the first mvloop at seek=109166 + its predecessors)"
F=$(grep -n "mvloop\] pre-movie" "$LOG" | head -1 | cut -d: -f1)
echo "first pre-movie mvloop at line: $F"
if [ -n "$F" ]; then
  S=$((F-12)); [ $S -lt 1 ] && S=1
  awk -v s="$S" -v e="$((F+4))" 'NR>=s && NR<=e { print NR": "$0 }' "$LOG" | grep -v "asciiart" | head -16
fi
echo "===STATE416=== the state ladder (the F0C=18 story)"
grep -n "R670\|statetbl\|stepper\] R596" "$LOG" | tail -10
echo "===HALT416=== the watchdog deferrals at the spin (the R325 movie-poll receipts)"
grep -n "halt\]" "$LOG" | tail -6
echo "===TAIL416=== the last 8 receipts (non-asciiart)"
awk -v s=$((TL-25)) -v e="$TL" 'NR>=s && NR<=e { print NR": "$0 }' "$LOG" | grep -v "asciiart\|lzss-fence\|mvloop" | head -10
echo "===C416DONE=== the wait-anatomy is receipted - R1378 follows from these receipts only"
