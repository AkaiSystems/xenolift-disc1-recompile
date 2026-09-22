#!/bin/bash
# c408_deathdossier.sh - READ-ONLY CENSUS. NO run, NO patch.
# The c407 verdict: R1376 fired 7x with five natural acks
# and two assist clears; the run rendered DEEPER THAN EVER
# (23.8M gp0 words, 102k polys, ~3B VRAM writes) and the
# first MDEC reg writes beyond reset - then died in a NEW
# primary blocker: TRUE DEATH segv at cur_fn=80019524,
# r31=80041BB0, all recoveries declined, exit 99 kit door.
# The final spin holds ALL THREE waitbr exit conditions yet
# loops (the caller branch is the stall). MY APPARATUS
# DEFECTS to confirm: the dossier print's missing resp0
# arg, and the duplicate delivery numbering (multi-site
# statics). THIS PASS extracts: (1) the death dossier -
# fault context, epoch, live request, kit report; (2) the
# render-era story - when the GPU exploded, the epoch
# boundaries, the screen census; (3) the MDEC context; (4)
# the multi-site instantiation count; (5) the final spin
# caller census. R1377 follows from these receipts only.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C408-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="f92a451cacc252da4b9e13ea00bc2ebbc8ae8c83716753023fd7f8e631115484"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1376 tree - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1376 tree)"
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
if [ ! -s "$LOG" ]; then echo "LOG-MISSING: cannot census"; exit 0; fi
TL=$(wc -l < "$LOG" | tr -d ' ')
echo "AUTHORITATIVE LOG = $LOG ($TL lines)"
echo "===MULTISITE408=== the R1376 instantiation count (one site or a macro?)"
echo "stranded-event delivery fmt occurrences: $(grep -c "stranded-event delivery" "$SRC" || true)"
echo "r1376_n occurrences: $(grep -c "r1376_n" "$SRC" || true)"
echo "mvloop-r1376 occurrences: $(grep -c "mvloop-r1376" "$SRC" || true)"
echo "pre-movie polling camera occurrences: $(grep -c "pre-movie polling" "$SRC" || true)"
grep -n "r1376_seq, r1376_watch" "$SRC" | head -4
echo "===DEATH408=== the TRUE DEATH dossier (the segv at 80019524)"
grep -n "segvdie\] R834\|segvdie\] R964\|crashkit\|CRITICAL\|bxcep\|BadVAddr\|EPC" "$LOG" | tail -20
DL=$(grep -n "segvdie\] R834 TRUE DEATH" "$LOG" | tail -1 | cut -d: -f1)
if [ -n "$DL" ]; then
  echo "--- the 60 receipts before the death line ($DL):"
  S=$((DL-60)); [ $S -lt 1 ] && S=1
  awk -v s="$S" -v e="$DL" 'NR>=s && NR<=e { print NR": "$0 }' "$LOG" | grep -v "asciiart\|lzss-fence" | head -40
fi
echo "===EPOCHDEATH408=== the boot-epoch timeline + which era the death hit"
grep -n "bootentry\] R710" "$LOG" | tail -10
echo "===RENDER408=== when did the GPU explode (the activity timeline)"
grep -n "R694 live\|gpufin\] R937" "$LOG" | head -12
grep -n "nonblank=" "$LOG" | head -8
echo "--- the gpucls full census:"
grep -n "gpucls" "$LOG" | head -4
echo "===MDEC408=== the first MDEC reg writes beyond reset (context)"
ML=$(grep -n "hle-mdec\] reg write" "$LOG" | head -1 | cut -d: -f1)
if [ -n "$ML" ]; then
  S=$((ML-15)); [ $S -lt 1 ] && S=1
  awk -v s="$S" -v e="$((ML+15))" 'NR>=s && NR<=e { print NR": "$0 }' "$LOG" | grep -v "asciiart" | head -24
else
  echo "no hle-mdec reg writes found"
fi
echo "===SPIN408=== the final spin callers (all three conditions hold - who is the caller?)"
grep -n "mvloop\]" "$LOG" | tail -3 | head -3
echo "--- the loop-id fn census at the end (which families spin):"
awk -v s=$((TL-3000)) -v e="$TL" 'NR>=s && NR<=e' "$LOG" | grep -o "loop-id fn=[0-9A-F]*" | sort | uniq -c | sort -rn | head -8
echo "--- the last waitbr receipts (conditions all hold?):"
grep -n "waitbr" "$LOG" | tail -4
echo "===CMD01408=== the cmd-01 story at the end (GetStat loop with FE1C=0)"
grep -n "cmdtl" "$LOG" | tail -6
echo "===FAULTS408=== the fault census + garbage receipts"
echo "computed-garbage $(grep -c "computed-garbage" "$LOG" || true)"
echo "lzss-runaway $(grep -c "lzss-runaway" "$LOG" || true)"
grep -n "computed-garbage" "$LOG" | head -4
echo "===TAIL408=== the last 15 receipts (non-asciiart)"
awk -v s=$((TL-60)) -v e="$TL" 'NR>=s && NR<=e { print NR": "$0 }' "$LOG" | grep -v "asciiart\|lzss-fence" | head -18
echo "===C408DONE=== the death dossier is receipted - R1377 follows from these receipts only"
