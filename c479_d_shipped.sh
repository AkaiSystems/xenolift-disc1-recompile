#!/bin/bash
# c479_extract.sh - READ-ONLY CENSUS, NO RUN, NO BUILD,
# NO PATCH. The c478 receipts: the file#14 unpack
# COMPLETED (line 24534: LZSS 260862 of 260862, the
# coordinator slot holds the REAL prologue 27BDFFC8)
# - the install-frozen hypothesis is retired. OPEN:
# what did the walker do AFTER the expansion? FAEC
# was stamped 1 at 24524 (R814) yet reads 0 at the
# park; F0C=0x0e/q14=1 frozen; the kernel menu header
# re-rendered at line 30194 (park era). RECEIPTS:
# (1) POSTEXP479: the post-expansion window (24534+)
# tag census - ChangeGameState, state stamps, winheal,
# coordinator writes, phase entries; (2) FVP479: all
# the fvp lines (the menu re-render eras); (3) FAEC479:
# the walker-latch writer receipts; (4) WRT479: the
# runtime's ownership of the walker cells (F0C/F14);
# (5) CHAIN479: the ChangeGameState story.
# Fail-closed, tee'd to /tmp/c479_receipts.txt.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C479-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c479_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="d86f3deb57aed5b0921ab3a82867dea3a1e1d9960028e360bed8d9bdc90d45f8"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the R1387 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the R1387 tree)"
LOG="run.log"
if [ ! -s "$LOG" ]; then LOG="run.log.d"; fi
if [ ! -s "$LOG" ]; then echo "GATE-FAILED: no preserved run log"; exit 0; fi
echo "LOG=$LOG ($(wc -l < "$LOG" | tr -d " ") lines)"
echo "===POSTEXP479=== the post-expansion window (line 24534 onward) tag census"
for TAG in "chaincam" "statetbl" "statestamp" "phasecb" "coordw" "winheal" "stg2heal" "fldx2" "fldfin" "cbmod" "cbreal" "latchhw"; do
  C=$(awk 'NR>24534' "$LOG" | grep -c -e "$TAG" | tr -d " ")
  echo "$TAG after-expansion: $C"
done
echo "--- chaincam receipts (head 6):"
grep -n -e "chaincam" "$LOG" | head -6
echo "--- coordw + winheal + stg2heal receipts (head 8):"
grep -n -e "coordw" -e "winheal" -e "stg2heal" "$LOG" | head -8
echo "--- fldx2 + fldfin receipts (all 3 known, head 8):"
grep -n -e "fldx2" -e "fldfin" "$LOG" | head -8
echo "===FVP479=== all the fvp lines (the menu render eras)"
grep -n -e "\[fvp\]" "$LOG" | head -26
echo "===FAEC479=== the walker-latch receipts"
grep -n -e "9FAEC" -e "R814 FULL" "$LOG" | head -12
echo "===WRT479=== the runtime's walker-cell ownership (F0C/F14/F18)"
grep -n -e "0x80059F0C" "$SRC" | head -6
grep -n -e "0x80059F14" "$SRC" | head -6
grep -n -e "0x80059F18" "$SRC" | head -6
echo "===CHAIN479=== the ChangeGameState trail (all eras)"
grep -n -e "chaincam" "$LOG" | tail -6
echo "===C479DONE=== the post-expansion walker story is in - the c480 fix follows from these only"
