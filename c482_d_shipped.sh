#!/bin/bash
# c482_extract.sh - READ-ONLY CENSUS, NO RUN, NO BUILD,
# NO PATCH. The c481 decode: the state-6 (movie) load
# is TWO members - member 1 (file#18, LBA 109158,
# 14360B) loaded, unpacked, MODULE 6 ENTRY dispatched;
# the final pass positioned at MEMBER 2 (LBA 109166,
# dest 801F3300) but FDF8 NEVER ARMED (the size-lookup
# never ran) - load stalled - the deliberate
# ChangeGameState(0) fallback. RECEIPTS: (1) FTABW482:
# the ftab lines in the window (the missing lookups);
# (2) STEPPER482: the fn_80019A48 stepper entries;
# (3) FE04CLR482: the FE04-clear writer; (4) MEMBER482:
# member-2's identity in the file table (LBA=109166/
# file#=19, all eras); (5) R1360W482: the pause-end
# receipts. Fail-closed, tee'd to /tmp/c482_receipts.txt.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C482-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c482_receipts.txt) 2>&1
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
echo "===FTABW482=== the ftab lines in the state-6 window (29600-30150)"
awk 'NR>=29600 && NR<=30150' "$LOG" | grep -n -e "ftab" | head -8
echo "--- the ovlread lines in the window:"
awk 'NR>=29600 && NR<=30150' "$LOG" | grep -n -e "ovlread" | head -6
echo "===STEPPER482=== the fn_80019A48 stepper entries"
echo "--- in window:"
awk 'NR>=29600 && NR<=30150' "$LOG" | grep -n -e "80019A48" | head -6
echo "--- all eras (head 4):"
grep -n -e "80019A48" "$LOG" | head -4
echo "===FE04CLR482=== the FE04 writer/clear receipts in the window"
awk 'NR>=29600 && NR<=30150' "$LOG" | grep -n -e "0x8004FE04" | head -8
echo "--- the FE04 hook lines all eras around the window (tail 4):"
grep -n -e "\[hook\] 0x8004FE04" "$LOG" | head -8
echo "===MEMBER482=== member-2's identity in the file table (all eras)"
grep -n -e "LBA=109166" "$LOG" | head -8
grep -n -e "file#=19" "$LOG" | head -8
grep -n -e "size-lookup" "$LOG" | tail -6
echo "===R1360W482=== the R1360 pause-end receipts in the window"
awk 'NR>=29600 && NR<=30150' "$LOG" | grep -n -e "R1360" | head -6
grep -n -e "R1360" "$LOG" | head -6
echo "===C482DONE=== the member-2 identity + missing lookup are in - the c483 arm follows from these only"
