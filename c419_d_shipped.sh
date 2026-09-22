#!/bin/bash
# c419_looprelease.sh - READ-ONLY CENSUS. NO run, NO
# patch. The c418 verdict: the 'pre-movie polling' loop
# fns DECODED AS THE FONT RENDERER FAMILY
# (EmitFontCharacter / string-length loops /
# FontAddLetterPrimitive) - the camera label was never
# the loop's identity. parkcam shows double-buffer page
# flipping - the game may be RUNNING NORMALLY at frame
# rate showing a text page, waiting for input or an
# event, not spinning. A22C=4 == exactly the four R896
# boot sync-deliveries, never consumed (a latch). The
# R1205 movie-band door can never fire at the final
# posture (needs cmd 06/09 + A22C==0). START presses
# #28-30 injected with NO consumption receipt. THIS PASS
# names the loop's RELEASE: (1) the font loop's PARENT
# function + its termination condition (disc1.c
# ~100820-100930 + the caller of the 80036BE8-region
# fn); (2) the pad story in the final era - does the game
# READ the controller after line 31000 (padrdw/btn/
# census/R1327 receipts), and what does the R809
# injector inject (buttons, cadence); (3) [park] R273
# receipts in the final era - the FE48 4F-copy value;
# (4) the R1291 movsite camera's actual source site (the
# game's own A22C writer gate); (5) the collector's
# A22C/slotbits processing (the R1309 cdcsync site
# context). NO behavior change - receipts only. R1378
# follows from these receipts only.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C419-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="6759e34359fdf33df2e78cfaf2c144194da718412f3d42cb022b12e87470a8bb"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1377 tree - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1377 tree)"
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
echo "===PARENTFN419=== the font loop's parent + termination (disc1.c 100780-100930)"
D="disc1.c"
if [ -f "$D" ]; then
  awk -v s=100780 -v e=100930 'NR>=s && NR<=e { print NR": "$0 }' "$D"
else
  echo "disc1.c missing"
fi
echo "===FONTLOOPCALLER419=== who calls the 80036BE8-region fn? (disc1.c callers)"
if [ -f "$D" ]; then
  grep -n "fn_80036BE8\|80036BE8" "$D" | head -6
  C=$(grep -n "static void xenolift_fn_800366.*(" "$D" | head -3)
  echo "$C"
  F=$(grep -n "xenolift_fn_800366F0_EmitFontCharacter" "$D" | head -1 | cut -d: -f1)
  echo "--- the EmitFontCharacter caller region (the fn that owns the string loop):"
  if [ -n "$F" ]; then
    P=$(awk -v f="$F" 'NR<f && /^static void xenolift_fn_/ { l=NR": "$0 } END { print l }' "$D")
    echo "enclosing fn: $P"
  fi
fi
echo "===PAD419=== the pad story in the final era (after line 31000)"
grep -n "padrdw\|btn\]\|padcensus\|R1327\|ReadControllerButtons\|0x8003569C" "$LOG" | awk -F: '$1 > 31000' | head -12
echo "--- what does R809 inject (the injector source):"
P8=$(grep -n "R809" "$SRC" | head -1 | cut -d: -f1)
if [ -n "$P8" ]; then awk -v s=$((P8-15)) -v e=$((P8+25)) 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"; fi
echo "===PARKFE48419=== [park] R273 receipts in the final era (the FE48 4F copy)"
grep -n "\[park\]" "$LOG" | awk -F: '$1 > 31000' | head -6
echo "--- all FE48 4F-copy receipts after line 31000 (any camera):"
grep -n "FE48" "$LOG" | awk -F: '$1 > 31000' | grep -v "mvloop" | head -8
echo "===R1291SITE419=== the movsite camera's actual source site"
M=$(grep -n "movsite" "$SRC" | head -1 | cut -d: -f1)
echo "site at line: $M"
if [ -n "$M" ]; then awk -v s=$((M-30)) -v e=$((M+12)) 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"; fi
echo "===COLLECTOR419=== the collector's A22C/slotbits processing (the R1309 site)"
C1=$(grep -n "R1309" "$SRC" | head -1 | cut -d: -f1)
echo "R1309 first at line: $C1"
if [ -n "$C1" ]; then awk -v s=$((C1-12)) -v e=$((C1+30)) 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"; fi
echo "===PADPRESS419=== the press/release cadence + consumption in the final era"
grep -n "padstart" "$LOG" | awk -F: '$1 > 31000' | head -12
echo "===C419DONE=== the loop's release contract is receipted - R1378 follows from these receipts only"
