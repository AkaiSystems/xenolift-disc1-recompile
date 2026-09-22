#!/bin/bash
# c398_dataload.sh - READ-ONLY CENSUS. NO run, NO patch. The
# c397 verdict: R1371 landed with NO FIRE and NO REGRESSION -
# the deep trajectory recovered (GPU 8.7M words, 3 epochs,
# VRAM content intact) and the ring walk advanced to slots
# 0-11, parking at LBA 14 (FDF8=2048 armed, sched=1, pend=0,
# FE1C=6, seek=14 tracks FE04, last_cmd=09). The door's
# printed terms ALL matched - so the excluder is UNPRINTED:
# either cd_read_active=1 is stale (the walk's own arms; the
# door requires !act), or the door's host site (the R1265/
# R1268 family site) never evaluates at the park because its
# ENCLOSING gate was never extracted. THIS PASS: (1) the
# door-site enclosing context (what if/switch/case contains
# the door family, lines ~2870-3095); (2) the cd_data_load
# body + every call site + its gates (the 0x40 status-bit
# path - when does the sector actually load); (3) the
# actchg/secserve receipts at the walk window (who arms
# act per slot); (4) the walk's +0x800 advance comment site
# (line ~19943). The next fix follows mechanically.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C398-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="0697638566e5c1c24c2e6268b771aa3884aa649ff9d0b5d20520bf86fa13cc16"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1371 tree - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1371 tree)"
echo "===DOORSITE398=== the door-site ENCLOSING context (lines 2870-3096: what gates the door family)"
awk 'NR>=2870 && NR<=3096 { print NR": "$0 }' "$SRC" | grep -v "^\s*[0-9]*: \*" | grep -v "^\s*$" | head -75
echo "===DOORCLOSE398=== the R1268 door close + what follows (lines 3155-3260)"
awk 'NR>=3155 && NR<=3260 { print NR": "$0 }' "$SRC" | grep -v "^\s*[0-9]*: \*" | grep -v "^\s*$" | head -55
echo "===DATALOAD398=== the cd_data_load body + its gates"
LG=$(grep -n "void cd_data_load\|static.*cd_data_load\|cd_data_load(void)\|cd_data_load()" "$SRC" | head -1 | cut -d: -f1)
echo "def at line $LG"
if [ -n "$LG" ]; then
  E=$((LG+60))
  awk -v s="$LG" -v e="$E" 'NR>=s && NR<=e { print NR": "$0 }' "$SRC" | grep -v "^\s*[0-9]*: \*" | head -55
fi
echo "===DLCALL398=== every cd_data_load call site"
grep -n "cd_data_load()" "$SRC" | head -10
echo "===CASE398=== the 0x1F801800 status-read hook (where the doors + load live)"
LG2=$(grep -n "case 0x1F801800" "$SRC" | head -1 | cut -d: -f1)
echo "case at line $LG2"
if [ -n "$LG2" ]; then
  S=$((LG2-10)); [ $S -lt 1 ] && S=1
  awk -v s="$S" -v e=$((LG2+40)) 'NR>=s && NR<=e { print NR": "$0 }' "$SRC" | head -40
fi
echo "===WALKADV398=== the +0x800 walk-advance comment site (~19943)"
awk 'NR>=19930 && NR<=19975 { print NR": "$0 }' "$SRC" | grep -v "^\s*$" | head -30
echo "===ACTCENSUS398=== the act/serve receipts at the walk window (run.log 29900+)"
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
if [ -s "$LOG" ]; then
  grep -n "actchg\|secserve\|stalecd\|finstamp" "$LOG" | awk -F: '$1>=29900' | head -14
  echo "===ACTPRINT398=== any receipt printing act= in the walk window"
  grep -n "act=1 \|act=0 " "$LOG" | awk -F: '$1>=29900' | head -8
else
  echo "LOG-MISSING"
fi
echo "===C398DONE=== the data-load anatomy is receipted"
