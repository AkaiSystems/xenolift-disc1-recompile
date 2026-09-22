#!/bin/bash
# c392_fdretire.sh - READ-ONLY CENSUS. NO run, NO patch. The
# c391 anatomy: the epoch-3 Pause COMPLETED (INT2 armed +
# cleared + acked), the R814 FULL HANDOFF STAMPED, the fldx
# expansion ran - and the END BLOCKER is now precise: the
# pre-movie spin exits on ret=0+FDFC=0+FE1C=0 and FE1C=6
# (guest-set at fn 80041820, never retired) is the SOLE hold.
# The fd-retire class (receipted firing at 31411 inside the
# conversion block) cannot reach the end posture because the
# block's outer condition needs pend!=0/kicks/R1365-arm and
# the end holds pend=0 sched=0. THIS PASS: the fd-retire site
# code, the hook block's CURRENT outer condition + context
# disjunction (R1368 tree), and the end-spin's dispatch
# census - the exact anatomy for the R1369 entry-arm design.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C392-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="456a8dcd3e3987a3ff79b490133d5ff63c6f1f2961dfbd6d9b336d945da7e141"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1368 tree - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1368 tree)"
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
if [ ! -s "$LOG" ]; then echo "TREE-ROOT-LOG-MISSING"; exit 0; fi
echo "AUTHORITATIVE LOG = $LOG ($(wc -l < "$LOG" | tr -d ' ') lines)"
echo "===FDRETIRESITE392=== the fd-retire site code (the stale-empty-request release)"
LG=$(grep -n "fd-retire" "$SRC" | head -1 | cut -d: -f1)
echo "print at line $LG"
if [ -n "$LG" ]; then
  S=$((LG-40)); [ $S -lt 1 ] && S=1
  E=$((LG+20))
  awk -v s="$S" -v e="$E" 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
fi
echo "===FDRETIREALL392=== every fd-retire receipt in the log (when does it fire?)"
grep -n "fd-retire" "$LOG" | head -12
echo "===BLOCKOUTER392=== the conversion block's CURRENT outer condition + context disjunction (R1368 tree)"
LG2=$(grep -n "kick2_wanted || kick3_wanted" "$SRC" | head -1 | cut -d: -f1)
echo "outer at line $LG2"
if [ -n "$LG2" ]; then
  S=$((LG2-12)); [ $S -lt 1 ] && S=1
  E=$((LG2+16))
  awk -v s="$S" -v e="$E" 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
fi
echo "===CTXLIST392=== the context disjunction line (the a== conditions)"
grep -n "a == 0x800415B4u" "$SRC" | head -3
LG3=$(grep -n "a == 0x800415B4u" "$SRC" | head -1 | cut -d: -f1)
if [ -n "$LG3" ]; then
  S=$((LG3-6)); E=$((LG3+8))
  awk -v s="$S" -v e="$E" 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
fi
echo "===SPINCTX392=== the end-spin's dispatch contexts (which fns the spin loops through)"
grep -n "loop-id" "$LOG" | tail -12 | sed 's/.*loop-id /loop-id /' | sort | uniq -c | sort -rn | head -10
echo "===FE1C6HOLD392=== the FE1C=6 hold window (31500-31600: what runs after the expansion)"
awk 'NR>=31448 && NR<=31530 { print NR": "$0 }' "$LOG" | grep -v "lzss-fence\|narrowblast\|bandhist" | head -40
echo "===C392DONE=== the fd-retire anatomy is receipted"
