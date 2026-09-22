#!/bin/bash
# c520_census.sh - READ-ONLY VERDICT CENSUS of the c519
# verdict run's log, NO RUN, NO BUILD, NO PATCH. THE c519
# RECEIPTS: the R1380 post-conversion collector pass
# LANDED clean (tree 05535414, splice at 22417, gates OK,
# synchk clean, RUN_RC=0) and the MECHANISM IS PROVEN:
# [postconv] slots=4 + h4 0x8002B084 dispatched
# in-context repeatedly through the boot reads (receipts
# 987-4712), the run reached 32k log lines (deeper than
# any prior run's ~21k), and NO unpack-on-zeros marker
# appeared in the digest. OPEN: the file#18 PASS bar -
# the print cap (first 24) consumed the visible postconv
# receipts in the boot era, and the digest's 109158
# greps came back empty; the behavior ran past 4712
# regardless, but the file#18-era delivery (cd-dma at
# 109158, FDF8 14360 countdown, member consumed, movie
# module load) needs receipting from the EXISTING log.
# ALSO OPEN: the death at line 31998 (exit 99, the
# kit/exitdiag door) - a NEW, deeper stopping point; the
# dossier around it names the door. THIS CENSUS: (1) the
# full 109158 request trace; (2) the death dossier at the
# rungasp line; (3) the ladder markers (MODULE 6 ENTRY,
# the field/movie module receipts); (4) the unpack
# family (did the unpack-on-zeros vanish); (5) the FDF8
# countdown/arm evidence; (6) the cd-dma tail (what
# sectors landed in the deep era); (7) the postconv
# volume counts. Fail-closed, tee'd to
# /tmp/c520_receipts.txt. Pure-ASCII output.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C520-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c520_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="05535414f7c77fd05cb4bcfeaf91fdbd239baf7e4c9d7c48b529bbaf658d1233"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the c519 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the c519 tree with the landed post-conversion collector pass)"
LOG="run.log"
if [ ! -s "$LOG" ]; then echo "GATE-FAILED: no run.log"; exit 0; fi
WC=$(wc -l < "$LOG" | tr -d " ")
echo "LOG=run.log ($WC lines)"
echo "===SEEK158=== the full file#18 request trace (LBA 109158)"
grep -n -e "109158" "$LOG" | head -40
echo "--- the tail of it:"
grep -n -e "109158" "$LOG" | tail -24
echo "===DEATH520=== the death dossier at the rungasp line"
RG=$(grep -n -e "rungasp" "$LOG" | tail -1 | cut -d: -f1)
echo "the rungasp receipt at line $RG:"
if [ -n "$RG" ]; then
  S0=$((RG-44)); [ "$S0" -lt 1 ] && S0=1
  sed -n "${S0},$((RG+6))p" "$LOG"
fi
echo "--- the crash-kit / firstfault markers in the log (tail):"
grep -n -e "CRITICAL" -e "firstfault" -e "kit door" -e "exitdiag" "$LOG" | tail -12
echo "===LADDER520=== the ladder markers"
echo "--- MODULE 6 ENTRY:"
grep -n -e "MODULE 6 ENTRY" "$LOG" | head -8
echo "--- the field/movie module receipts (fldx, expansion):"
grep -n -e "fldx" -e "R790 expansion" "$LOG" | head -12
echo "--- the movie-era markers:"
grep -n -e "pre-movie" -e "movie band" -e "mod6" -e "chaincam" "$LOG" | head -16
echo "===UNPACK520=== the unpack family (did the unpack-on-zeros vanish?)"
grep -c -e "unpack" "$LOG" | tr -d " " | sed "s/^/unpack-family lines: /"
grep -n -e "unpack" "$LOG" | head -12
echo "--- the zero-variant specifically:"
grep -n -e "unpack.*zero" "$LOG" | head -6
echo "===FDF8DEC=== the FDF8 arm + countdown evidence"
grep -n -F -e "-> 14360" "$LOG" | head -8
grep -n -e "finstamp" "$LOG" | awk -F"ea=8004FDF8 " '{ if (NF>1) print }' | tail -24
echo "===CDCDMA520=== the cd-dma tail (what sectors landed in the deep era)"
grep -n -e "cd-dma" "$LOG" | tail -24
echo "===POSTCONV520=== the postconv volume"
echo "postconv scan receipts:"
grep -c -e "post-conversion collector scan" "$LOG" | tr -d " " | sed "s/^/scans: /"
echo "postconv h4 dispatch receipts:"
grep -c -e "R1380 dispatch h4" "$LOG" | tr -d " " | sed "s/^/h4 in-context dispatches: /"
echo "--- the cbcall tail (the FILE-CB path in the deep era):"
grep -n -e "cbcall" "$LOG" | tail -10
echo "===C520DONE=== the c519 verdict evidence is receipted from the run's own log - the c521 decision (fix follow-up or new fault) follows from these receipts only - digest is pure ASCII"
