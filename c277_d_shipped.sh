#!/bin/bash
# c277_postconsume_dossier.sh - READ-ONLY: THE POST-CONSUME WINDOW,
# the GetTN/TOC chain, and the FIRST FAULT into the state-0 restart.
# THE c276 VERDICT: CONSUMPTION RECEIPTED - the f15 wedge is CLOSED
# (R1331 band + R1332 sized serve, both landed, no revert). The
# c350 milestone met: correctly completed read (46 sectors, 92180B,
# DATA HANDLER entered with data on board) + forward execution
# beyond the polling loop (command FMS walked FE1C 0->10->11->6->1->
# 2->0 via six game fns; NEW commands: GetStat then cmd 13 GetTN).
# THE OPEN QUESTIONS THIS DOSSIER receipts (on witness log 9193a7cd,
# post-fire window 29449-30174 and the restart chain):
# (1) what did the game DO with the served bytes - decode the new
#     tags ([io] [walk] [descw2] [wdsdiff] receipts);
# (2) the GetTN/TOC chain: cmd 13 lifecycle, rspop13 pops, the
#     stream-node 0x80059F18 result area (cdstate flagged it parked
#     at STAT filler 02020202 - TOC answer never landed?);
# (3) THE FIRST FAULT that leads to the state-0 restart at 30174
#     (90 [fault] tags post-fire; abort131=1; bootmain=7; exit 99).
# No patch, no compile, no run.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C277-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
LOG=$(ls -t witness_c276_*/run.log.witness 2>/dev/null | head -1)
EXPECT="9193a7cd47b9595f8317072207550cab70292e9cd2bfd08f8d20e9219e122e21"
if [ -z "$LOG" ] || [ ! -s "$LOG" ]; then echo "C277-FAILED: preserved witness log missing"; exit 1; fi
SS=$(shasum -a 256 "$LOG" | cut -d" " -f1)
echo "LOG=$LOG"
echo "LOG_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: witness log sha mismatch - refusing a foreign log"; exit 0; fi
echo "BASELINE_VERIFIED (the c276 consumption witness run)"
ENDL=$(wc -l < "$LOG" | tr -d " ")
echo "log_lines=$ENDL"
win() { S=$1; [ "$S" -lt 1 ] && S=1; E=$2; [ "$E" -gt "$ENDL" ] && E=$ENDL; awk -v s="$S" -v e="$E" 'NR>=s&&NR<=e{printf "%d:%s\n",NR,$0}NR>e{exit}' "$LOG"; }

echo "===NEWTAGS277=== what the game did with the served bytes (the new tags decoded)"
echo "--- [walk] receipts:"
win 29449 30174 | grep "\[walk\]" | head -10
echo "--- [io] receipts:"
win 29449 30174 | grep "\[io\]" | head -10
echo "--- [descw2] receipts:"
win 29449 30174 | grep "\[descw2\]" | head -8
echo "--- [wdsdiff] receipts:"
win 29449 30174 | grep "\[wdsdiff\]" | head -8

echo "===GETTN277=== the GetTN/TOC chain"
win 29449 30174 | grep "rspop13\|GetTN\|cmd 13\|TOC" | head -16
echo "--- the stream-node result area story:"
grep -n "stream-node" "$LOG" | tail -6

echo "===FIRSTFAULT277=== the first fault after the consume (what leads to the restart?)"
FF=$(win 29449 30174 | grep "\[fault\]" | head -1 | cut -d: -f1)
echo "first_fault_line=$FF"
if [ -n "$FF" ]; then
  echo "--- context around the first fault:"
  win $((FF-6)) $((FF+10))
fi
echo "--- the abort/trap census in the window:"
win 29449 30174 | grep "abort\|NULL-trap\|segv\|SIGSEGV\|crash" | head -8

echo "===RESTART277=== the chain into the state-0 restart at 30174"
echo "--- context before the first post-consume bootentry:"
win 30150 30180
echo "--- cmdtl census in the window (how far did the drive get?):"
win 29449 30174 | grep "cmdtl" | head -10

echo "===MDEC277=== the 4 mdec receipts (class check)"
grep -n "mdec" "$LOG" | head -6

echo "===C277DONE=== post-consume dossier complete - the next first-fault target comes from these receipts"
