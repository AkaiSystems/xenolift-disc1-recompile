#!/bin/bash
# c535_census.sh - READ-ONLY CENSUS of the c534 verdict's
# next observed blocker, NO RUN, NO BUILD, NO PATCH. THE
# c534 VERDICT (Jos branch A - keep c534): the empty-door
# force WAS prevented (the decline receipted at 25673, the
# epoch-4 heapclr-fresh bounce; NO empty-window class-3
# stop anywhere); installation followed the decline in the
# SAME epoch (member=6 at 28930 after the 25673 decline);
# the R844 bypass NEVER fired - the boot own path carried
# the game: a native dispatch to 0x800737EC hit the
# dispatch-level R1394 guard (live module != emit-era
# ref), the interpreter entered the LIVE module (never the
# wrong translation) with NO FAIL receipt (completed,
# dispatched onward), and the game reached its deepest
# state this tree: ALIVE at the archive loader fn 800286CC
# with the file#2 bulk fetch ARMED (FDF8=61680 = the exact
# ftab size, FE04=108754), START presses injected and seen,
# screen content held, exit 137 = the full fuse. THE BLOCKER
# (receipted): the file#2 fetch armed but FROZEN - FDF8=
# 0xF0F0 unchanged across every spin print, sched=1,
# pend=0, last_cmd=06 - the c176/c182 archive-fetch class
# at its deepest appearance. ONE UNEXPLAINED COUNTER: the
# r31=0000000A receipt family counts 64 (zero in the
# c528-c531 runs) - unidentified; this census prints the
# lines and their context. SECTIONS: (1) the decline + the
# epoch-4 timeline (decline -> installs -> interpreter ->
# the spin); (2) the r31=0A family (count + head + the
# first context); (3) the interpreter path at 800737EC
# (all ovl lines + where control went after); (4) the
# frozen-fetch posture (the R967/fldfrz2/sgdecline/sgarm/
# defib6 decline cameras + the DRV lines); (5) the FDF8
# 0->F0F0 arm (who armed it, for which request). Fail-
# closed, tee'd to /tmp/c535_receipts.txt. Pure-ASCII
# output.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C535-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c535_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="cc637bfb05891064a87390bd8918bf7a1742c45f458a2796bcece5cab02b1602"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the c534 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the c534 tree with the landed R1396 empty-door guard)"
LOG="run.log"
if [ ! -s "$LOG" ]; then echo "GATE-FAILED: no run.log"; exit 0; fi
echo "LOG=run.log ($(wc -l < "$LOG" | tr -d " ") lines)"
echo "===DECL535=== the decline + the epoch-4 timeline (decline -> installs -> interpreter -> spin)"
sed -n "25660,25690p" "$LOG"
echo "--- the ordered epoch-4 receipts after the decline (installs + state + interpreter + spin start):"
awk 'NR>25673 && (/\[newmod\]/ || /statestamp/ || /\[ovlint\]/ || /\[ovlstop\]/ || /coordw/ || /fldx/ || /800286CC/ || /R967 STUCK/)' "$LOG" | head -24
echo "===OA535=== the r31=0A family (count + head + the first context)"
grep -c -e "r31=0000000A" "$LOG" | tr -d " " | sed "s/^/r31=0A total: /"
grep -n -e "r31=0000000A" "$LOG" | head -12
O1=$(grep -n -e "r31=0000000A" "$LOG" | head -1 | cut -d: -f1)
if [ -n "$O1" ]; then
  echo "--- the context of the first r31=0A receipt (line $O1):"
  _O0=$((O1-8)); [ "$_O0" -lt 1 ] && _O0=1
  sed -n "${_O0},$((O1+4))p" "$LOG"
fi
echo "===INTERP535=== the interpreter path at 800737EC (all ovl lines + where control went after)"
grep -n -e "\[ovlint\]" -e "\[ovlstop\]" "$LOG" | head -12
OL=$(grep -n -e "\[ovlint\]" "$LOG" | tail -1 | cut -d: -f1)
if [ -n "$OL" ]; then
  echo "--- the context after the last ovl line (line $OL) - where did control go:"
  sed -n "$((OL+1)),$((OL+16))p" "$LOG"
fi
echo "===SPIN535=== the frozen-fetch posture (the decline cameras + the DRV lines)"
grep -n -e "R967 STUCK" "$LOG" | head -6
grep -n -e "fldfrz2" "$LOG" | head -4
grep -n -e "sgdecline" "$LOG" | head -6
grep -n -e "sgarm" "$LOG" | head -6
grep -n -e "defib6" "$LOG" | head -6
echo "--- the first archive-spin receipt of the final era (the 800286CC entry):"
S1=$(grep -n -e "loop-id fn=800286CC" "$LOG" | head -1 | cut -d: -f1)
if [ -n "$S1" ]; then
  _S0=$((S1-10)); [ "$_S0" -lt 1 ] && _S0=1
  sed -n "${_S0},$((S1+4))p" "$LOG"
fi
echo "===ARM535=== the FDF8 0->F0F0 arm (who armed it, for which request)"
grep -n -e "R1299 FDF8 ARM-CONTEXT" "$LOG" | grep -e "F0F0" | head -6
grep -n -e "finstamp" "$LOG" | grep -e "F0F0" | head -8
echo "--- any fetchcam/receipt naming seek=108754 or FE04=1A8D2:"
grep -n -e "108754" "$LOG" | grep -v -e "mvloop" | head -10
echo "===C535DONE=== the blocker posture + the r31=0A family + the arm owner are receipted - the c536 fix follows from these receipts only - digest is pure ASCII"
