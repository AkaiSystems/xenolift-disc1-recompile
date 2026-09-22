#!/bin/bash
# c415_spinanatomy.sh - READ-ONLY CENSUS. NO run, NO patch.
# The c414 verdict: R1377 landed (tree 6759e343) but was
# NOT exercised (no guest exit(0), no relay). No
# regression; the trajectory ran to the 120s fuse. THE
# BLOCKER: the pre-movie mvloop spin at seek=109166,
# last_cmd=02 (Setloc), CD layer FULLY IDLE (pend=0
# sched=0 FE04=0 FDF8=0 FE1C=0), A22C=4 held, F0C=18,
# drawing active (winNZ 896/960). The game Setloc'd to
# the movie sector 109166 but NO read command followed -
# the movie demand is invisible to the CD layer. THIS
# PASS extracts: (1) when/why seek became 109166 (the
# first occurrences + the receipts around them); (2) the
# last full command ladder before the spin (the cmdtl/
# setloc story); (3) the movie machinery state (mtrans/
# movie tags, g_movie_live, the state ladder into F0C=18);
# (4) A22C=4's writer and waiter (who sets it, who
# clears it); (5) the five-stage event posture at the
# wall (any due event, any undelivered response, any
# consumed-but-unacked handshake); (6) the R1377/relay
# status confirmation. NO behavior change - receipts
# only. R1378 follows from these receipts only.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C415-FAILED: xenolift dir missing"; exit 1; }
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
echo "===SEEKORIGIN415=== when did seek become 109166? (first occurrences + context)"
F=$(grep -n "seek=109166\|seek 109166\|109166" "$LOG" | head -1 | cut -d: -f1)
echo "first 109166 receipt at line: $F"
grep -n "109166" "$LOG" | head -8
if [ -n "$F" ]; then
  S=$((F-8)); [ $S -lt 1 ] && S=1
  awk -v s="$S" -v e="$((F+12))" 'NR>=s && NR<=e { print NR": "$0 }' "$LOG" | grep -v "asciiart" | head -16
fi
echo "===CMDLADDER415=== the last full command ladder before the spin (the cmdtl/setloc story)"
grep -n "cmdtl" "$LOG" | tail -14
echo "===SETLOC415=== the Setloc story into 109166"
grep -n "setloc\|Setloc\|SETLOC" "$LOG" | tail -12
echo "===MOVIEMACH415=== the movie machinery state (mtrans + state ladder into F0C=18)"
grep -n "mtrans\|movie_live\|mvstr\|movie-start\|moviestr" "$LOG" | tail -12
grep -n "F0C=00000012\|F0C=18" "$LOG" | head -3
echo "===A22C415=== A22C=4's writer and waiter (who sets, who clears)"
grep -n "A22C" "$LOG" | grep -v "mvloop\|parkcam\|fldfrz" | head -12
echo "===FIVESTAGE415=== the event posture at the wall (due events, undelivered responses, unacked handshakes)"
grep -n "schdd\|pendclr\|penddossier" "$LOG" | tail -10
echo "===R1377STATUS415=== the relay/R1377 confirmation (no relay expected; block armed)"
grep -n "R1377\|R718/R719\|R722 exe image restored\|R725 relay" "$LOG" | head -8
echo "===FAULTS415=== the fault + recovery census"
grep -n "computed-garbage\|segvrec\|segvdie" "$LOG" | head -8
echo "===TAIL415=== the last 10 receipts (non-asciiart)"
awk -v s=$((TL-30)) -v e="$TL" 'NR>=s && NR<=e { print NR": "$0 }' "$LOG" | grep -v "asciiart\|lzss-fence" | head -12
echo "===C415DONE=== the seek=109166 spin anatomy is receipted - R1378 follows from these receipts only"
