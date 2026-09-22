#!/bin/bash
# c252_finalera_dossier.sh - READ-ONLY: no patch, no compile, no run.
# THE c251 VERDICT: R1325 PASS - the dispatcher arena guard fired 3x
# at exactly the right postures (two all-zero heads + the EXACT c248
# garbage {EF07F805 28030A88} caught live and reseeded), every
# post-guard walk clean. THE RUN: FIRST CLEAN MAIN-RETURN EXIT
# (status 0 - project first), the 100% screen painted AND HELD (snaps
# 2/3 all regions 4800, stride4 nz 119231), state 1 engaged and HELD
# through exit (no state-0 fall-back), bootmain=2, no crash-kit.
# REMAINING QUESTIONS: (1) the lone abort-131 site, (2) the SCENE
# CONTENT question - recognizable scene vs loading screen (the Jos
# rule: changed screenshot != scene advancement; needs the asciiart
# structure + the era story), (3) the pad consumption story (did the
# game consume our injected presses this era?), (4) the clean-exit
# chain (what the game did before main-return). THIS CYCLE receipts
# those four. The c253 fix is decided by these receipts.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C252-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
LOG="run.log"
EXPECT="094a08acdec924afe4e59deacc7fb4a3abce587adc5e2acb42f802c478f87419"
if [ ! -s "$LOG" ]; then echo "C252-FAILED: run.log missing"; exit 1; fi
SS=$(shasum -a 256 "$LOG" | cut -d" " -f1)
echo "LOG_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: run.log is not the c251 post-run log"; exit 0; fi
echo "BASELINE_VERIFIED"
P="finale_c252_$(date +%Y%m%d_%H%M%S)"
if ! (mkdir -p "$P" && cp -p "$LOG" "$P/run.log"); then echo "C252-FAILED: preserve failed"; exit 1; fi
echo "PRESERVED: $P/run.log sha=$SS"

echo "===ABRT252=== the lone abort-131 (which site this time?)"
AN=$(grep -n "code=131" "$LOG" | head -1 | cut -d: -f1)
echo "abort131_line=$AN"
if [ -n "$AN" ]; then
  S=$((AN-22)); [ "$S" -lt 1 ] && S=1
  awk -v s="$S" -v e="$((AN+6))" 'NR>=s&&NR<=e{printf "%d:%s\n",NR,$0}NR>e{exit}' "$LOG" | grep -v "bandhist\|\[hook\]\|pumpcam\|\[spu\]" | head -20
fi
echo "--- the lone NULL-trap context:"
TN=$(grep -n "NULL-trap #" "$LOG" | head -1 | cut -d: -f1)
if [ -n "$TN" ]; then
  S=$((TN-12)); [ "$S" -lt 1 ] && S=1
  awk -v s="$S" -v e="$((TN+4))" 'NR>=s&&NR<=e{printf "%d:%s\n",NR,$0}NR>e{exit}' "$LOG" | grep -v "bandhist\|\[hook\]\|pumpcam" | head -12
fi

echo "===GASP252=== the clean-exit chain (what ran before main-return?)"
GR=$(grep -n "rungasp" "$LOG" | head -1 | cut -d: -f1)
echo "gasp_line=$GR"
if [ -n "$GR" ]; then
  S=$((GR-60)); [ "$S" -lt 1 ] && S=1
  awk -v s="$S" -v e="$((GR+2))" 'NR>=s&&NR<=e{printf "%d:%s\n",NR,$0}NR>e{exit}' "$LOG" | grep -v "bandhist\|\[hook\]\|pumpcam\|\[spu\]" | head -40
fi

echo "===SCENE252=== the scene content (recognizable or loading screen?)"
grep -n "asciiart" "$LOG" | tail -2
echo "--- the last full-screen asciiart block:"
AL=$(grep -n "asciiart\] R949 full screen" "$LOG" | tail -1 | cut -d: -f1)
echo "fullscreen-line=$AL"
if [ -n "$AL" ]; then
  awk -v s="$AL" -v e="$((AL+34))" 'NR>=s&&NR<=e{printf "%d:%s\n",NR,$0}NR>e{exit}' "$LOG" | head -34
fi
echo "--- the sprite-region asciiart block:"
SL=$(grep -n "asciiart\] R949 sprite region" "$LOG" | tail -1 | cut -d: -f1)
if [ -n "$SL" ]; then
  awk -v s="$SL" -v e="$((SL+12))" 'NR>=s&&NR<=e{printf "%d:%s\n",NR,$0}NR>e{exit}' "$LOG" | head -12
fi
echo "--- the drawcmd/drawprim story of the final era:"
grep -n "drawcam\|gpuprim" "$LOG" | tail -6

echo "===PAD252=== the pad consumption story (presses injected vs read)"
grep -n "padstart\] R809" "$LOG" | head -8
echo "--- padcell reads by the game (the posture receipts):"
grep -n "padcell" "$LOG" | tail -8
echo "--- any key-press consumption receipts:"
grep -n "padrd\|padread\|keyrd\|pressed" "$LOG" | grep -v padstart | tail -6

echo "===CB252=== the state-1 CB census (the callback era story)"
grep -n "STATE-1 CB ENTER" "$LOG" | head -8
grep -n "mtrans" "$LOG" | head -8
echo "--- the state-1 module entries (coordinator runs):"
grep -n "coordw\|KernelMenu\|menumain" "$LOG" | tail -6

echo "===C252DONE=== final-era dossier complete - the c253 fix is decided by these receipts"
