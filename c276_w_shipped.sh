#!/bin/bash
# c276_consume_witness.sh - WITNESS RUN + THE POST-FIRE CONSUMPTION
# DOSSIER. No patch, no compile change: the tree stands at the R1332
# fire (0cc8f859).
# THE c275 VERDICT: the sized serve FIRED CORRECTLY - 46 sectors
# delivered to 800D0994 (the FULL 92180B batch), STATE 1 HELD PAST
# THE FIRE (first time; c272 undersized serve fell to state 0), and
# the process EXITED STATUS 0 (clean main-return). BUT the wedge
# formed late (~96% of the log) so the fire landed near budget end -
# the game CONSUMPTION of the 46 sectors is not yet receipted.
# THIS CYCLE: a witness run (RUN_BUDGET_S=170 - the compile cache is
# valid so build ~50s + run 170s fits the 240s bridge window) with
# the digest focused on the POST-FIRE WINDOW: the full tag census
# after the fire, the game command lifecycle, the consumer receipts,
# the state census (does state 1 hold/advance?), the scene receipts
# (mdec/asciiart/gpufin), and the exit class.
# PASS for the f15 request = consumption receipts (the game drains
# the served data and issues NEW commands beyond the post-read
# ladder) + forward execution. If the fire again lands too late in
# the budget, the receipts still name the timing distribution.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C276-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="0cc8f8599ef2adcef29ac528864d80eb217a4c8c2a9e597c69b3b435e4982907"
if [ ! -s "$SRC" ]; then echo "C276-FAILED: runtime/runtime.c missing"; exit 1; fi
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1332 tree 0cc8f859 - refusing a foreign tree"; exit 0; fi
echo "BASELINE_VERIFIED (the R1332 sized-serve tree, unchanged)"
P="witness_c276_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$P"

echo "===RUN276=== the 170s witness run"
RUN_BUDGET_S=170 ./run.sh > /tmp/run_full_c276.txt 2>&1
echo "RUNSH_RC=$?"
head -4 /tmp/run_full_c276.txt
if [ -s run.log ]; then cp -p run.log "$P/run.log.witness"; echo "RUNLOG_WITNESS sha=$(shasum -a 256 "$P/run.log.witness" | cut -d" " -f1) size=$(wc -c < "$P/run.log.witness" | tr -d " ")"; fi

LOG="run.log"
ENDL=$(wc -l < "$LOG" | tr -d " ")
echo "log_lines=$ENDL"
win() { S=$1; [ "$S" -lt 1 ] && S=1; E=$2; [ "$E" -gt "$ENDL" ] && E=$ENDL; awk -v s="$S" -v e="$E" 'NR>=s&&NR<=e{printf "%d:%s\n",NR,$0}NR>e{exit}' "$LOG"; }

echo "===FIRE276=== the fire receipts + timing"
grep -n "\[mvdoor\]" "$LOG" | head -8
FL=$(grep -n "ARCHIVE-TRANSFER-DONE SET" "$LOG" | head -1 | cut -d: -f1)
echo "fire_line=$FL log_end=$ENDL postfire_lines=$((ENDL-FL+1))"
if [ -n "$FL" ]; then
  echo "===TIMING276=== the wall-clock era at the fire"
  win $((FL-2)) $((FL+2)) | grep -o "t=[0-9]*s\|@t=[0-9]*s" | head -4
  grep -o "@t=[0-9]*s" "$LOG" | tail -3
  echo "===POSTTAGS276=== the post-fire tag census"
  win "$FL" "$ENDL" | grep -o "\[[a-z0-9]*\]" | sort | uniq -c | sort -rn | head -24
  echo "===POSTCHAIN276=== the game post-fire command lifecycle"
  win "$FL" "$ENDL" | grep "cmdtl\|fld2sig\|rspop" | head -20
  echo "===POSTCONSUME276=== the consumer receipts after the fire"
  win "$FL" "$ENDL" | grep "cd-dma\|fd-tick\|READ ISSUED\|mtrans\|cdstate\|DATA HANDLER\|finstamp" | head -16
  echo "===POSTSTATE276=== the state census after the fire"
  win "$FL" "$ENDL" | grep "statetbl\|active state" | head -8
  echo "===POSTSCENE276=== the scene receipts after the fire"
  win "$FL" "$ENDL" | grep "mdec\|gpufin\|screen\]\|asciiart" | head -10
fi

echo "===STATE276=== the whole-run state census"
echo "bootmain=$(grep -c bootmain "$LOG") traps=$(grep -c "NULL-trap #" "$LOG") abort131=$(grep -c "code=131" "$LOG") mdec=$(grep -c mdec "$LOG")"
grep -n "active state" "$LOG" | tail -4
echo "===EXIT276==="
grep -n "rungasp" "$LOG" | tail -1
echo "===C276DONE=== consumption witness complete - the verdict comes from these receipts; the tree is unchanged (no revert path needed)"
