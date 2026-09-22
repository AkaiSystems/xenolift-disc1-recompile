#!/bin/bash
# c483b_extract.sh - READ-ONLY CENSUS, NO RUN, NO BUILD,
# NO PATCH. Jos's four-part capture plan, in execution
# order, for the movie-stream start/stop transition that
# precedes the deliberate ChangeGameState(0) fallback.
# FDF8=0 may be NORMAL for streaming (the boot-era
# stream armed 0x358->FFFFFB58, a stream counter) - no
# invented length, no Pause suppression, no behavioral
# change. RECEIPTS: (1) BOOTBASE: the boot-era healthy
# stream baseline (log 8200-8270); (2) START: the
# FE04=0x1AA6E stamp writer + dest 801F3300 supplier +
# cmd 06 issuer; (3) DELIVERY: the FIFO sector's
# consumer in the state-6 window; (4) STOP: the cmd 09
# transition + state before Pause; (5) CLEANUP: the FE04
# clear + the end-of-read story. Fail-closed, tee'd to
# /tmp/c483b_receipts.txt.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C483B-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c483b_receipts.txt) 2>&1
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
echo "===BOOTBASE483B=== the boot-era healthy movie-stream baseline (log 8200-8270)"
awk 'NR>=8200 && NR<=8270 { print NR": "$0 }' "$LOG"
echo "===START483B=== who stamps FE04=0x1AA6E, supplies dest 801F3300, issues cmd 06"
echo "--- all 1AA6E/1aa6e receipts (head 12):"
grep -n -e "1AA6E" -e "1aa6e" "$LOG" | head -12
echo "--- the finstamp/hook FE04 receipts in the state-6 window:"
awk 'NR>=29600 && NR<=30150 { print NR": "$0 }' "$LOG" | grep -e "finstamp" -e "\[hook\]" | head -12
echo "--- the 801F3300 destination receipts (all eras, head 8):"
grep -n -e "801F3300" "$LOG" | head -8
echo "===DELIVERY483B=== the FIFO sector consumer in the state-6 window"
awk 'NR>=29890 && NR<=30010 { print NR": "$0 }' "$LOG" | grep -e "FIFO" -e "DATA HANDLER" -e "bigread" -e "A22C" | head -14
echo "--- the FE1C/A22C movement after the 109166 sector:"
awk 'NR>=29890 && NR<=30150 { print NR": "$0 }' "$LOG" | grep -e "FE1C" | head -10
echo "===STOP483B=== the cmd 09 transition + state before Pause"
awk 'NR>=29600 && NR<=30150 { print NR": "$0 }' "$LOG" | grep -e "cmdtl" -e "cmd=09" -e "cmd 09" | head -12
echo "--- cmd-writer receipts in the window (who wrote the command register):"
awk 'NR>=29600 && NR<=30150 { print NR": "$0 }' "$LOG" | grep -e "cmdw" -e "1F801803" | head -8
echo "===CLEANUP483B=== the FE04 clear + the end-of-read story"
awk 'NR>=29900 && NR<=30150 { print NR": "$0 }' "$LOG" | grep -e "FE04" -e "fldfin" -e "end-of-read" | head -12
echo "===C483BDONE=== the four-part stream transition story is in - the fix follows from these only"
