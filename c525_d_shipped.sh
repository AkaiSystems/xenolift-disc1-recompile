#!/bin/bash
# c525_census.sh - READ-ONLY CENSUS of the c524 run's new
# ending, NO RUN, NO BUILD, NO PATCH. THE c524 RECEIPTS:
# the R1381 park-release request LANDED clean (tree d1c3d391,
# splice at 5312, gates OK, synchk clean, RUN_RC=0) and the
# mechanism FIRES ([parkrel] x2 at the A22C polls with the
# sched-stuck posture) - but this run's TRAJECTORY SWUNG
# (the receipted nondeterminism): the 108861 park NEVER
# OCCURRED (the 2 fires were boot-era cmd-08 postures the
# release correctly declines - no R1294 WIN printed). THE
# NEW PATH, receipted: the directory band read LBA 4-7 to
# completion (FDF8 2048->0 three times), file#6 (LBA
# 108884, FDF8 2660) armed AND COMPLETED natively
# (2660->612->0, finstamp #773-779), the mvloop family
# shrank to 25 prints (last at line 30000), and the last
# era shows the FULL HANDOFF STAMPED #2, the fldx expansion
# sequence entered, modhdr + trcam activity (writer 8004B894
# touching the module header 8006FAF0+), exit 99 at the kit
# door. TWO NEW QUESTIONS in the receipts: (1) the file#6
# sector DMAs carried GARBAGE DESTINATIONS (dest 0x00000001
# and 0x00000801 at LBA 108884/108885) while the countdown
# completed anyway - did the data land in the game's real
# buffer or in the funnel; (2) the module window base
# 8006F000 is STILL ALL ZEROS at t=5s of the new era (the
# same incomplete-install shape). THIS CENSUS: (1) the
# death dossier (the last era's ending - what stopped it);
# (2) the new-era activity census (the 30000-31998 window);
# (3) the file#6 read trace (the arm, the FE08 dest, the
# garbage-dest question, the completion); (4) did the
# 108861 park posture occur AT ALL this run; (5) the
# release decision trail ([schdw] first-evals, R1294 WIN
# count); (6) the screen/GPU census of the new era.
# Fail-closed, tee'd to /tmp/c525_receipts.txt.
# Pure-ASCII output.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C525-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c525_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="d1c3d3912462c72ac7a811d8ce177c18b56166a6aa4825049cc3b686330b6384"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the c524 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the c524 tree with the landed R1381 park-release request)"
LOG="run.log"
if [ ! -s "$LOG" ]; then echo "GATE-FAILED: no run.log"; exit 0; fi
WC=$(wc -l < "$LOG" | tr -d " ")
echo "LOG=run.log ($WC lines)"
echo "===DEATH525=== the death dossier (what stopped the new era)"
RG=$(grep -n -e "rungasp" "$LOG" | tail -1 | cut -d: -f1)
echo "the rungasp receipt at line $RG:"
if [ -n "$RG" ]; then
  _S0=$((RG-46)); [ "$_S0" -lt 1 ] && _S0=1
  sed -n "${_S0},$((RG+6))p" "$LOG"
fi
echo "--- the crash-kit markers (tail):"
grep -n -e "CRITICAL" -e "firstfault" -e "exitdiag door" "$LOG" | tail -6
echo "===NEWERA=== the new-era activity census (the 30000-31998 window)"
echo "--- the handoff + expansion + module receipts in the window:"
grep -n -e "FULL HANDOFF" -e "fldx" -e "modhdr" -e "MODULE 6 ENTRY" -e "newmod" "$LOG" | awk -F: '$1 > 30000' | head -14
echo "--- the last 20 lines of the log (the ending itself):"
tail -20 "$LOG"
echo "===FILE6=== the file#6 read trace (LBA 108884 - the garbage-dest question)"
grep -n -e "108884" "$LOG" | head -20
echo "--- the tail of it:"
grep -n -e "108884" "$LOG" | tail -8
echo "--- the FE08/dest cells around the arm (finstamp #773 context):"
F773=$(grep -n -e "ea=8004FDF8 0 -> 2660" "$LOG" | head -1 | cut -d: -f1)
if [ -n "$F773" ]; then
  _S0=$((F773-12)); [ "$_S0" -lt 1 ] && _S0=1
  sed -n "${_S0},$((F773+12))p" "$LOG"
fi
echo "===PARK861=== did the 108861 park posture occur AT ALL this run?"
grep -c -e "108861" "$LOG" | tr -d " " | sed "s/^/108861 mentions: /"
grep -n -e "108861" "$LOG" | head -6
echo "--- all parkrel receipts:"
grep -n -e "parkrel" "$LOG"
echo "--- the mvloop prints with their seeks (which parks occurred):"
grep -n -e "pre-movie polling" "$LOG" | sed "s/ (\(mod6=[^|]*\).*(\(R870 loop-id fn=[0-9A-F]*\).*seek=\([0-9]*\).*/ fn-park seek=\3/" | head -12
echo "===RELDEC=== the release decision trail"
echo "--- the R1294 WIN receipts:"
grep -n -e "R1294" "$LOG" | head -6
echo "--- the [schdw] scheduler first-evals (tail):"
grep -n -e "schdw" "$LOG" | tail -10
echo "===SCREEN525=== the screen/GPU census of the new era"
grep -n -e "gpucls" "$LOG" | tail -4
grep -n -e "vram_nonzero" "$LOG" | tail -4
echo "===C525DONE=== the new ending is receipted - the c526 decision (fix follow-up or new fault) follows from these receipts only - digest is pure ASCII"
