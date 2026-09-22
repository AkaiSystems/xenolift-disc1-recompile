#!/bin/bash
# c273_postdoor_dossier.sh - READ-ONLY: THE CONSUMPTION-vs-TEARDOWN
# DISCRIMINATOR on the doorbell-fire run.
# THE c272 VERDICT: R1331 landed (tree 30c6d76d), the mvdoor FIRED
# (streak 1->2, match=1, R879 posted the shipment at seek=108995
# with sector_loaded=1, A22C->5, slotbits ->106; R892 set
# ARCHIVE-TRANSFER-DONE), THE SPIN EXITED with 1 sector delivered to
# 800D0994 - FIRST MOTION PAST THE f15 WEDGE. BUT the serve was
# UNDERSIZED: f15 is ~45 sectors (92180B); the doorbell announced 1
# sector + DONE (correct for its c476-era file#6 calibration, wrong
# for f15). Post-door the pump moved to a NEW posture (FDF8=0 act=1
# seek=0 FE1C=11 data=2060/0), the game fell back to state 0 at
# 26096, mdec=5 (undetermined class).
# THE DISCRIMINATOR: did the game CONSUME (FDF8 walking down by
# consumption, sector consumers, queue re-arm, new commands =
# progress) or TEAR DOWN (cmdtl 02->01->00->0c chain, cells cleared
# = the timeout class again)? THIS DOSSIER receipts: the full
# [mvdoor] fire count; the door window (24700-26250) tag census; the
# FDF8 walk in the window; the cmdtl/fld2sig chain; the consumer
# receipts; the mdec class; the state-0 transition context; the late
# postures; whether the wedge recurred. No patch, no compile, no run.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C273-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
LOG="patch_c271_20260917_080411/run.log.post"
EXPECT="3b37de34d91775df9ecc52949a1e33db2de357d31fa03360416457c05474c5de"
if [ ! -s "$LOG" ]; then echo "C273-FAILED: preserved log $LOG missing"; exit 1; fi
SS=$(shasum -a 256 "$LOG" | cut -d" " -f1)
echo "LOG_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: preserved log sha mismatch - refusing a foreign log"; exit 0; fi
echo "BASELINE_VERIFIED (the c272 doorbell-fire run)"
ENDL=$(wc -l < "$LOG" | tr -d " ")
echo "log_lines=$ENDL"
win() { S=$1; [ "$S" -lt 1 ] && S=1; E=$2; [ "$E" -gt "$ENDL" ] && E=$ENDL; awk -v s="$S" -v e="$E" 'NR>=s&&NR<=e{printf "%d:%s\n",NR,$0}NR>e{exit}' "$LOG"; }

echo "===FIRE273=== the full doorbell fire census"
echo "mvdoor_posts=$(grep -c "\[mvdoor\] R879" "$LOG")"
grep -n "\[mvdoor\]" "$LOG" | head -20

echo "===TAGS273=== the door-window tag census (24700-26250)"
win 24700 26250 | grep -o "\[[a-z0-9]*\]" | sort | uniq -c | sort -rn | head -28

echo "===WALK273=== the FDF8 walk at the pump (did it drain or clear?)"
win 24700 26250 | grep "pumpcam" | head -24

echo "===CMDTL273=== the command lifecycle in the window (new commands or teardown?)"
win 24700 26250 | grep "cmdtl\|fld2sig" | head -18

echo "===CONSUME273=== the consumer receipts in the window"
win 24700 26250 | grep "cd-dma\|fd-tick\|READ ISSUED\|rspop\|cdstate" | head -14

echo "===MDEC273=== the 5 mdec receipts (real decode activity or init cameras?)"
grep -n "mdec" "$LOG" | head -8

echo "===STATE273=== the state-0 transition context"
grep -n "statetbl\|bootmain" "$LOG" | head -12
echo "--- around the fall to state 0 (26096):"
win 26088 26110

echo "===LATE273=== the late posture + wedge recurrence"
grep -n "f15 request stamped" "$LOG" | head -5
echo "--- first FE1C=11 context:"
L=$(grep -n "FE1C=11 " "$LOG" | head -1 | cut -d: -f1)
if [ -n "$L" ]; then win $((L-4)) $((L+6)); fi
echo "--- the last 6 pumpcam:"
grep -n "pumpcam" "$LOG" | tail -6

echo "===C273DONE=== post-door dossier complete - the consumption-vs-teardown verdict comes from these receipts"
