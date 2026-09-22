#!/bin/bash
# c402_provenance.sh - READ-ONLY CENSUS. NO run, NO patch.
# The c401 verdict (Jos's four-part test): R1373 NEVER FIRED
# - the wedge posture MOVED (last_cmd=06 ReadN, FE1C=0,
# A22C=4, sched=1 held through the whole stream drain,
# pend=0, FDF8=0). The delivery hypothesis is
# runtime-untested; the wedge family has >=2 postures
# (c399: cmd-02/fe1c=1; c401: cmd-06/fe1c=0/A22C=4). THE
# TWO OPEN DETAILS (Jos): (1) does cd_force_deliver_int1
# preserve the INT3 command response despite its name;
# (2) does the saved sched event belong to the CURRENT
# command or is it stale (never deliver an unproven-stale
# event). THIS PASS: the DEFINITION BODIES of
# cd_force_deliver_int1, cd_restore_pend, cd_pending_stamp;
# the scheduled event's provenance (seq/cmd/site/age) at
# the end window; the A22C=4 writer census; the waitbr
# LegacyCdDataWait returns. R1374 follows from these
# receipts only.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C402-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="a9d040824cbf7d8ab262b927579be97e1ab9015af3852361d67aee7d52fd5bc1"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1373 tree - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1373 tree)"
echo "===FDIDEF402=== the cd_force_deliver_int1 DEFINITION (Jos detail 1: does it preserve the INT3 answer?)"
DEF=$(grep -n "^static void cd_force_deliver_int1" "$SRC" | head -1 | cut -d: -f1)
if [ -z "$DEF" ]; then
  DEF=$(awk '/cd_force_deliver_int1\(const char \*why\)$/ { print NR; exit }' "$SRC")
fi
echo "def at line $DEF"
if [ -n "$DEF" ]; then
  awk -v s="$DEF" -v e=$((DEF+80)) 'NR>=s && NR<=e { print NR": "$0 }' "$SRC" | head -70
fi
echo "===RSTORE402=== the cd_restore_pend DEFINITION (Jos detail 2: whose answer gets restored?)"
DEF2=$(grep -n "static void cd_restore_pend" "$SRC" | head -2 | tail -1 | cut -d: -f1)
if [ -z "$DEF2" ]; then DEF2=$(grep -n "void cd_restore_pend" "$SRC" | head -1 | cut -d: -f1); fi
echo "def at line $DEF2"
if [ -n "$DEF2" ]; then
  awk -v s="$DEF2" -v e=$((DEF2+40)) 'NR>=s && NR<=e { print NR": "$0 }' "$SRC" | head -35
fi
echo "===PSTAMP402=== the cd_pending_stamp DEFINITION (the SET provenance machinery)"
DEF3=$(grep -n "void cd_pending_stamp" "$SRC" | head -1 | cut -d: -f1)
echo "def at line $DEF3"
if [ -n "$DEF3" ]; then
  awk -v s="$DEF3" -v e=$((DEF3+30)) 'NR>=s && NR<=e { print NR": "$0 }' "$SRC" | head -28
fi
echo "===PENDANS402=== where cd_pend_ans is SAVED (the answer's owner at schedule time)"
grep -n "cd_pend_ans_n = \|cd_pend_ans_cmd = \|memcpy(cd_pend_ans" "$SRC" | head -8
echo "===LOG402=== the run.log provenance receipts at the end window"
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
if [ -s "$LOG" ]; then
  echo "===PENDDOSSIER402=== the sched event provenance (seq/cmd/site/age) 30500+"
  grep -n "penddossier\|pend-set\|pendset" "$LOG" | awk -F: '$1>=30500' | head -12
  echo "===SCHDW402=== the schdw SET/CLEAR correlation at the stream end"
  grep -n "schdw\]" "$LOG" | awk -F: '$1>=31000' | head -10
  echo "===A22C402=== the A22C writer census (archx/settle + tblw on the A22C cell)"
  grep -n "archx\]" "$LOG" | awk -F: '$1>=30000' | head -8
  echo "===WAITBR402=== the LegacyCdDataWait returns at the final spin"
  grep -n "waitbr\]" "$LOG" | awk -F: '$1>=31000' | head -8
  echo "===CMDTL402=== the command ladder at the stream end"
  grep -n "cmdtl\]" "$LOG" | awk -F: '$1>=31000' | head -10
  echo "===SECCLR402=== when did sched arm last (the finstamp sched=1 SET moment)"
  grep -n "finstamp" "$LOG" | awk -F: '$1>=31000' | head -20
else
  echo "LOG-MISSING"
fi
echo "===C402DONE=== the delivery provenance is receipted"
