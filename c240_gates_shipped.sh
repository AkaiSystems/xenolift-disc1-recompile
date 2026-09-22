#!/bin/bash
# c240_f15_gate_dump.sh - READ-ONLY: no patch, no compile, no run.
# THE c239 VERDICT: state 1 SURVIVED its abort-131 (the dispatcher-own
# heap install at 800C4A6C trapped on stale junk; the boot re-entry
# receipted g_CurGameState=1 with the gdesc-1 record REAL and the era
# continued ACTIVE IN STATE 1). The screen is TWO WORDS (background
# fills, no scene). THE SCENE BLOCKER, receipted: [mtrans] f15 request
# stamped (FE04=108995 FDF8=92180 F0C=15) but [ftab] READ ISSUED never
# fires for file#15 - instead 4+ [schdd] delivery-decision-BLOCKED
# after all gates declined (seq=112): cmd=02 fe1c=0 FDF8=0
# seek=108995 FE08=800D0994 resp=0/3 A22C=4 - the c206 class at a new
# sequence, camera challenge: NAME THE GATE THAT SHOULD HAVE MATCHED.
# THIS CYCLE receipts the answer: the [schdd] release-gate ladder in
# runtime.c (every branch + term), the seq-112 window in the log, the
# full f15 chain, and the dispatcher-install trap site for the
# follow-up. The c241 fix widens by exactly the receipted term.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C240-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
LOG="run.log"
SRC="runtime/runtime.c"
EXPECT="2ebb361ce5dfa31a738b34a4d59cce4584d86c7281f8a723651616004942fe78"
if [ ! -s "$LOG" ]; then echo "C240-FAILED: run.log missing"; exit 1; fi
SS=$(shasum -a 256 "$LOG" | cut -d" " -f1)
echo "LOG_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: run.log is not the c238/c239-preserved log"; exit 0; fi
if [ ! -s "$SRC" ]; then echo "C240-FAILED: runtime/runtime.c missing"; exit 1; fi
echo "SRC_SHA=$(shasum -a 256 "$SRC" | cut -d" " -f1)"
echo "BASELINE_VERIFIED"
P="runlog_preserve_c240_$(date +%Y%m%d_%H%M%S)"
if ! (mkdir -p "$P" && cp -p "$LOG" "$P/run.log"); then echo "C240-FAILED: preserve failed"; exit 1; fi
echo "PRESERVED: $P/run.log sha=$SS"

echo "===SCHDD-SRC=== the [schdd] camera + the release-gate ladder in runtime.c"
SL=$(grep -n "delivery decision BLOCKED" "$SRC" | head -1 | cut -d: -f1)
echo "schdd-print-line=$SL"
if [ -n "$SL" ]; then
  S=$((SL-160)); [ "$S" -lt 1 ] && S=1
  sed -n "${S},$((SL+12))p" "$SRC"
fi

echo "===GATES-SRC=== the release branches feeding the decision (grep the gate terms)"
grep -n "GATE-CHANGE\|release gate\|schdd" "$SRC" | head -16

echo "===SEQ112=== the seq-112 window in the log (what precedes the blocks)"
SB=$(grep -n "seq=112" "$LOG" | head -1 | cut -d: -f1)
echo "seq112-first-line=$SB"
if [ -n "$SB" ]; then
  S=$((SB-25)); [ "$S" -lt 1 ] && S=1
  awk -v s="$S" -v e="$((SB+2))" 'NR>=s&&NR<=e{printf "%d:%s\n",NR,$0}NR>e{exit}' "$LOG" | grep -v "bandhist\|\[hook\]" | head -22
fi

echo "===F15CHAIN=== the full file#15 chain (stamp -> issue -> delivery)"
grep -n "mtrans\]" "$LOG" | head -6
grep -n "file#=15\|file#15\|F0C=15" "$LOG" | head -8
echo "--- the ftab member 15 (LBA/size from the table walk):"
grep -n "READ ISSUED" "$LOG" | tail -6
echo "--- the response staging around seq 112:"
grep -n "rspop\] byte#1" "$LOG" | awk -F: '$1>30000' | head -6

echo "===DISPTRAP=== the dispatcher-install trap site (for the follow-up fix)"
grep -n "0x80019B44\|gdisp\] dispatcher" "$SRC" | head -8
DT=$(grep -n "gdisp\] dispatcher" "$SRC" | head -1 | cut -d: -f1)
if [ -n "$DT" ]; then
  S=$((DT-20)); [ "$S" -lt 1 ] && S=1
  sed -n "${S},$((DT+20))p" "$SRC"
fi

echo "===ERA236=== the post-reentry state-1 era activity (what actually runs)"
awk 'NR>=30135&&NR<=30260{printf "%d:%s\n",NR,$0}NR>30260{exit}' "$LOG" | grep -v "bandhist\|\[hook\]" | head -34

echo "===C240DONE=== gate dump complete - c241 widens by the receipted term"
