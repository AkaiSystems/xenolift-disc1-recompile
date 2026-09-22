#!/bin/bash
cd "$HOME/Downloads/xenolift" || exit 1
# c217 THE FIRST-FAULT EXTRACTION - READ-ONLY: no patch, no compile, no run.
# The c216 gameplay test VERDICT (tightened rules applied to the receipts):
# NOT GAMEPLAY-DEMONSTRATED - (a) shot hashes identical x4 = held frame
# (the late-era 100% nonblank regions are display-buffer activity, not
# proven scene content); (b) no press-response receipt (interaction
# UNPROVEN); (c) active state 0 at EVERY statetbl print, g_CurGameState=0,
# abort 130 + boot re-entry - the state machine never reaches a scene state.
# THREE NEW RECEIPT CLASSES DECIDE THE NEXT FIX - this cycle extracts them:
# (1) THE FIRST FAULT - faultctx target 0x00FFFF63 at pc=0x8004B55C
#     (r31=0x80042960, the pre-movie family), "no cell contains the target -
#     computed on the fly"; then the poison-HALT era: [poison] store
#     0x8004B520 <- 8F5A0008 at fn 0x8004B694 (poison INTO guest code);
#     run died exit 137 = SIGKILL fuse at t=120s, ALIVE at cutoff mid-dump.
# (2) THE STATE-RECORD/RESTART CHAIN - abort 130 at 80031DC8 (era 2, the
#     c193 class), Module-6 spike (15 dispatcher calls), boot re-entry,
#     and the LATE descw2 queue-cell writes (0x80018088+ = the pFnMain
#     table re-written AT the fuse, t=120s).
# (3) THE PAD CENSUS - [padrd] receipts (9537B): which fn reads the pad,
#     at what cadence, with what cell values; plus padstart press/release.
# ALSO SETTLED THIS RUN (no extraction needed): exit-0 ownership for c215 =
# the 120s budget-controlled return (b2exit "epoch=1 era-returned @t=120s"
# immediately precedes rungasp exit 0 - NOT genuine completion; c200 also
# had one); command trace = 48 bytes ALL boot-era, ReadN/ReadS absence
# after boot RECEIPTED from the trace; FE1C receipts show a cyclic state
# machine (0->A->6->1->0 via fns 40FB4/358BC/40FCC/409E4), NOT a
# pending-event count - the classification is updated by evidence.
# FAIL EXPLICIT. Sources gated. Nothing runs, nothing changes.
TS=$(date +%Y%m%d_%H%M%S)
SNAP="runlog_preserve_c217_$TS"
mkdir -p "$SNAP" || { echo "PRESERVE-FAILED: mkdir"; exit 0; }
if ! cp -p run.log "$SNAP/run.log"; then echo "PRESERVE-FAILED: run.log copy failed - nothing extracted"; exit 0; fi
echo "PRESERVED: $SNAP/run.log sha=$(shasum -a 256 "$SNAP/run.log" | cut -c1-16) size=$(wc -c < "$SNAP/run.log") ts=$TS"
echo "===PRE217=== identity gate (the c215/216-run tree cdfa6b41, receipted by cycles 215+216)"
T=$(shasum -a 256 runtime/runtime.c | cut -d" " -f1)
echo "TREE_SHA=$T"
if [ "$T" != "cdfa6b41dacf69db720ed5faec83d0fa477c865082c6accc989845c51038a45c" ]; then echo "DRIFT-FAILED: tree is not the c215/216-run tree cdfa6b41 - nothing extracted from a foreign tree"; exit 0; fi
echo "BASELINE_VERIFIED"
echo "===PAD217=== THE PAD CENSUS (which fn reads the controller, cadence, cell values)"
echo "padrd lines total: $(grep -c "\[padrd\]" run.log || true)"
grep -n "\[padrd\]" run.log | head -24
echo "--- padrd tail:"
grep -n "\[padrd\]" run.log | tail -8
echo "--- padstart press/release receipts (all):"
grep -n "\[padstart\]" run.log
echo "--- starter-heal receipts (all):"
grep -n "\[starter-heal\]" run.log
echo "--- minput receipts (first 12):"
grep -n "\[minput\]" run.log | head -12
echo "===FAULT217=== THE FIRST-FAULT DOSSIER (line-numbered, the actual block)"
F=$(grep -n "faultctx\] R696 target" run.log | head -1 | cut -d: -f1)
if [ -n "$F" ]; then
  awk -v S="$F" 'NR>=S && NR<=S+70 {printf "%d:%s\n", NR, $0}' run.log
else
  echo "NO faultctx target line in this log"
fi
echo "--- every receipt naming the fault family (8004B55C / 8004B694 / 8004B520 / 80042960), first 40:"
grep -n "8004B55C\|8004B694\|8004B520\|80042960" run.log | head -40
echo "--- the poison-store context (line-numbered, -8/+8):"
P=$(grep -n "poison\] store 0x8004B520" run.log | head -1 | cut -d: -f1)
if [ -n "$P" ]; then awk -v S="$P" 'NR>=S-8 && NR<=S+8 {printf "%d:%s\n", NR, $0}' run.log; else echo "no poison-store line"; fi
echo "===ABORT217=== THE ABORT-130 BLOCK (era-2 resident-loop fault, -100/+60 lines)"
A=$(grep -n "fn_80019ACC(130)" run.log | head -1 | cut -d: -f1)
if [ -n "$A" ]; then
  awk -v S="$A" 'NR>=S-100 && NR<=S+60 {printf "%d:%s\n", NR, $0}' run.log
else
  echo "NO abort-130 line this log"
fi
echo "===STATE217=== THE STATE-RECORD STORY (population + the late table re-write)"
grep -n "\[statetbl\]" run.log
echo "--- gtab receipts (first 12):"
grep -n "\[gtab\]" run.log | head -12
echo "--- descw2 queue-cell writes (tail 16 - the pFnMain cells at 0x80018088+):"
grep -n "\[descw2\]" run.log | tail -16
echo "--- widx mirror receipts (tail 8):"
grep -n "\[widx\]" run.log | tail -8
echo "===EXIT217=== EXIT OWNERSHIP (this run: exit 137 = SIGKILL fuse - alive at cutoff?)"
grep -n "rungasp\] R806\|b2exit\] R713\|crashkit\] R777" run.log
echo "===FE1C217=== THE FE1C STATE-MACHINE TRAIL (per-fn writer census + total)"
grep -o "\[chg\] FE1C [0-9A-F]*->[0-9A-F]* at fn 0x[0-9A-F]*" run.log | sort | uniq -c | sort -rn | head -20
echo "total FE1C writer lines: $(grep -c "\[chg\] FE1C" run.log || true)"
echo "===CMD217=== THE COMMAND CENSUS (from the trace)"
echo "total CMD-byte audit lines: $(grep -c "R1314 CMD byte" run.log || true)"
L18=$(grep -n "newmod\] fn_800295D8 member=18" run.log | tail -1 | cut -d: -f1)
if [ -n "$L18" ]; then echo "CMD bytes after the LAST member=18 install (line $L18): $(awk -v L="$L18" 'NR>L && /R1314 CMD byte/' run.log | wc -l)"; fi
echo "===CONTENT217=== CONTENT-EXACTNESS (open: length-match receipted, contents unproven)"
grep -n "R495 carry-v3\|\[reshtail\]" run.log | head -12
echo "===END217==="
