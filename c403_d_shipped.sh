#!/bin/bash
# c403_taildrain.sh - READ-ONLY CENSUS. NO run, NO patch.
# The c402 verdicts: (A) Jos detail 2 ANSWERED - the R307
# save site (line 2226) saves cd_pend_ans ONLY for
# multi-byte answers, so restore_pend after a Setloc
# replays a stale answer (R1373's composite convicted,
# never fired, to be reverted); (B) the full transaction
# receipted: 7 sectors drained, then an FDF8 UNDERFLOW WRAP
# (24-2048=0xFFFFF818, an EXTRA sector drained past the
# 24-byte tail), the re-issued ReadN never arming
# (FDF8=0, INT3 sched=1 undelivered). OPEN: (1) the REAL
# cd_force_deliver_int1 definition (c402's grep hit the
# fwd decl at 771); (2) WHO served LBA 239322 three times
# (an 8th sector past the file end - the over-serve that
# fed the wrap); (3) the cmd-06 ReadN INT3 schedule sites
# (the 3-byte ack that IS multi-byte = restore-safe); (4)
# the re-read's ftab announce (did the game announce
# file#18 again?); (5) the tail-drain anatomy at 80041534
# (guest) vs the runtime serves. THIS PASS extracts all
# five. R1374 follows from these receipts only.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C403-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="a9d040824cbf7d8ab262b927579be97e1ab9015af3852361d67aee7d52fd5bc1"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1373 tree - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1373 tree)"
echo "===FDIDEF403=== the REAL cd_force_deliver_int1 DEFINITION (the occurrence whose next line opens a body)"
OCC=$(grep -n "cd_force_deliver_int1" "$SRC" | cut -d: -f1)
echo "occurrences: $OCC"
DEF=0
for L in $OCC; do
  NXT=$((L+1))
  LINE=$(awk -v n="$NXT" 'NR==n' "$SRC")
  case "$LINE" in
    "{"*) DEF=$L; break ;;
  esac
done
echo "definition at line $DEF"
if [ "$DEF" -gt 0 ]; then
  awk -v s="$DEF" -v e=$((DEF+75)) 'NR>=s && NR<=e { print NR": "$0 }' "$SRC" | head -65
fi
echo "===CMD06SCHED403=== every cd_scheduled=1 site (which is the ReadN INT3 schedule path)"
grep -n "cd_scheduled = 1" "$SRC" | head -10
echo "===SAVEANS403=== the cd_pend_ans save site + surrounding response build (line 2200-2240)"
awk 'NR>=2200 && NR<=2245 { print NR": "$0 }' "$SRC" | grep -v "^\s*$" | head -30
echo "===LOG403=== the run.log tail-serve anatomy"
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
if [ -s "$LOG" ]; then
  echo "===SERVE239322403=== WHO served 239322 x3 (the receipts around each load)"
  grep -n "239322" "$LOG" | head -12
  echo "===TAILCTX403=== the receipts surrounding the 3rd 239322 serve (30300-30600)"
  awk 'NR>=30300 && NR<=30560' "$LOG" | grep -n "secserve\|dirserve\|zrf\|mvkick\|force-sched\|R1373\|secload\|READ ISSUED\|defib\|stagedring\|porter" | head -14
  echo "===FTAB403=== the re-read announce (did the game announce file#18 again?)"
  grep -n "READ ISSUED" "$LOG" | awk -F: '$1>=31000' | head -8
  echo "===WRAPCTX403=== the receipts around the FDF8 wrap (finstamps #849-#850, lines 31225-31240)"
  awk 'NR>=31220 && NR<=31245 { print NR": "$0 }' "$LOG" | head -22
else
  echo "LOG-MISSING"
fi
echo "===C403DONE=== the tail-drain anatomy is receipted"
