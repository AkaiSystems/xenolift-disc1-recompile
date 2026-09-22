#!/bin/bash
# c253_epoch1_run.sh - THE 190s EVIDENCE RUN (no patch; the R1325 tree
# runs unchanged). THE c252 VERDICT: the R1325 guard fired at the walk
# entry (pre-head garbage caught, clean head receipted) but the walk
# then trapped ONCE at a MID-ARENA node (r5=800C8314, next=0, the
# cursor=-8 class, latch=0) - AND THE ERA SURVIVED IT (abort-131 ->
# immediate state-1 recovery; the old 524K death spiral is gone). THE
# ARC: KernelMenuMain/Initialize/Update RAN (choice=0 released=0),
# ReadControllerButtons polled 28K+ at btn=BFFF - but NO presses were
# injected this era: the virtual player re-arms at BOOT EPOCH 1 (R693)
# and the shell-restart into epoch 1 (R692, the atexit door - exit-0
# ownership now receipted as the console shell relaunch) landed at the
# run tail, cut off by the 150s budget. File#15 was stamped+requested.
# The 100% screen is a UNIFORM fill (o/: rows) - recognizable scene
# still unproven. HYPOTHESIS: the epoch-1 era (virtual player armed +
# menu live) completes the press->response story if given run time.
# THIS CYCLE: RUN_BUDGET_S=190 evidence run, no code change, digest on
# the press/menu/choice cells, the f15 story, the trap posture, the
# epoch census, and the screen. PASS = epoch-1 menu era receipted with
# the injection firing (or a named blocker).
set -u
cd "$HOME/Downloads/xenolift" || { echo "C253-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="98c55c8305de9ed239d0e4ba428213b8fc5168adc57ef238a213c01c7bf96243"
if [ ! -s "$SRC" ]; then echo "C253-FAILED: runtime/runtime.c missing"; exit 1; fi
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1325 tree 98c55c83 - refusing a foreign tree"; exit 0; fi
echo "BASELINE_VERIFIED (the R1325 tree)"
P="epoch1_c253_$(date +%Y%m%d_%H%M%S)"
if ! (mkdir -p "$P" && cp -p "$SRC" "$P/runtime.c.snapshot"); then echo "C253-FAILED: preserve failed"; exit 1; fi
echo "PRESERVED: $P/runtime.c.snapshot sha=$SS"

echo "===RUN253=== the 190s epoch-1 evidence run"
RUN_BUDGET_S=190 ./run.sh > /tmp/run_full_c253.txt 2>&1
echo "RUNSH_RC=$?"
head -4 /tmp/run_full_c253.txt
if [ -s run.log ]; then cp -p run.log "$P/run.log"; echo "RUNLOG_POST sha=$(shasum -a 256 "$P/run.log" | cut -d' ' -f1) size=$(wc -c < "$P/run.log" | tr -d ' ')"; fi

echo "===EPOCH253=== the boot-epoch census (did epoch 1 run its menu?)"
grep -n "boot-epoch\|shell RESTART\|bootepoch" run.log 2>/dev/null | head -8
grep -n "rungasp" run.log 2>/dev/null | tail -1
echo "--- state census:"
echo "bootmain=$(grep -c bootmain run.log 2>/dev/null)"
grep -n "active state" run.log 2>/dev/null | tail -6

echo "===GUARD253=== the R1325 guard census"
grep -n "arenaseed\]" run.log 2>/dev/null | head -8
echo "--- trap/abort census:"
echo "traps=$(grep -c "NULL-trap #" run.log 2>/dev/null) abort131=$(grep -c "code=131" run.log 2>/dev/null) abort130=$(grep -c "code=130" run.log 2>/dev/null)"
TN=$(grep -n "NULL-trap #" run.log 2>/dev/null | head -1 | cut -d: -f1)
if [ -n "$TN" ]; then grep -A2 "NULL-trap #1 " run.log 2>/dev/null | head -4; fi

echo "===PAD253=== the press story (did the virtual player fire?)"
grep -n "padstart\] R809" run.log 2>/dev/null | head -10
echo "--- padrd census (btn values seen):"
grep -o "btn=[0-9A-F]*" run.log 2>/dev/null | sort | uniq -c | head -8
echo "--- the menuchain + choice/released cells:"
grep -n "menuchain\]" run.log 2>/dev/null | head -10
grep -n "choice(\|released(8005948C)" run.log 2>/dev/null | tail -6

echo "===F15253=== the file#15 story (requested? issued? completed?)"
grep -n "file#=15\|f15\|F0C(59F0C)=15\|F0C=15" run.log 2>/dev/null | head -10
grep -n "READ ISSUED" run.log 2>/dev/null | tail -6

echo "===SCREEN253=== the screen census"
grep -n "nonblank" run.log 2>/dev/null | tail -4
grep -n "gpufin" run.log 2>/dev/null | tail -2
echo "--- the asciiart variety census (uniform fill vs structured scene):"
grep "asciiart" run.log 2>/dev/null | grep -o "[|:].*[|:]" | tr -d ' ' | awk '{for(i=1;i<=length($0);i++){c=substr($0,i,1); t[c]++}} END{for(k in t) print k, t[k]}' | sort -k2 -rn | head -8

echo "===C253DONE=== epoch-1 evidence run complete - verdict from these receipts"
