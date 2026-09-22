#!/bin/bash
# c343_witness.sh - UNCHANGED-TREE witness run of the R1358
# era. NO patch. The pass-3 wedge is closed (c342): the
# ReadN stream served, FDF8 drained, PAUSE issued, f15 armed
# (seek=108995, FDF8=92180 owed) in a NEW mvloop.
# THIS CYCLE: 180s witness, census of the new era: the PAUSE
# lifecycle, the f15 read issue + progression, sectors at
# 108995, the cmdtl ladder beyond #12, faults, GPU.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C343-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="37a3790a5e6d5e2daebddc6cb9dc67d6bc264bcdff459198f487b30803d5b92a"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1358 tree 37a3790a - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1358 tree - unchanged witness)"
TS=$(date +%Y%m%d_%H%M%S)
WDIR="witness_c343_$TS"; mkdir -p "$WDIR"
echo "===RUN343=== the unchanged R1358 build, 180s budget, first-fault stop"
XENOLIFT_FIRSTFAULT_STOP=1 RUN_BUDGET_S=180 bash run.sh > /tmp/run_full_c343.txt 2>&1; RRC=$?
echo "RUN_RC=$RRC"
for f in run.log run.log.d; do [ -f "$f" ] && cp -p "$f" "$WDIR/$f"; done
cp -p /tmp/run_full_c343.txt "$WDIR/run_full.txt"
echo "WITNESS=$WDIR"
LOG="run.log"; [ -s "$LOG" ] || LOG="run.log.d"
echo "===CMDTL343=== the full command ladder"
grep -n "cmdtl" "$LOG" | tail -12
echo "===PAUSE343=== the PAUSE lifecycle receipts"
grep -n "pause\|PAUSE\|INT2" "$LOG" | grep -v "watchdog" | tail -12
echo "===F15_343=== the f15 request era (seek 108995 / FDF8 92180)"
grep -n "READ ISSUED" "$LOG" | tail -6
grep -n "108995" "$LOG" | tail -12
echo "===F15PROG343=== FDF8 progression at the f15 era"
grep -n "FDF8=0x16814\|FDF8=92180\|FDF8=00016814" "$LOG" | head -8
grep -n "0x16814" "$LOG" | tail -6
echo "===SECTORS343=== sectors served at 108995+"
grep -n "sector LBA 1089[9][0-9][0-9]" "$LOG" | head -6
grep -c "sector LBA" "$LOG"
echo "===FE1C343=== the FE1C walk in the f15 era"
grep -n "\[chg\] FE1C" "$LOG" | tail -12
echo "===WGEN343=== the collector receipts"
grep -n "wgen" "$LOG" | tail -8
echo "===STREAM343=== stream watcher receipts"
grep -n "\[halt\]" "$LOG" | tail -6
echo "===MVLOOP343=== the mvloop posture at the tail"
grep -n "mvloop" "$LOG" | tail -3
echo "===FAULT343=== fault census"
grep -c "computed-garbage" "$LOG"
FF=$(grep -n "computed-garbage address" "$LOG" | head -1 | cut -d: -f1)
echo "FIRST_FAULT_LINE=$FF"
if [ -n "$FF" ]; then awk -v s="$((FF-6))" -v e="$((FF+6))" 'NR>=s && NR<=e' "$LOG"; fi
echo "===VIS343=== run tail + gpu census"
grep -n "rungasp" "$LOG" | tail -2
grep -n "gpufin\|gp0_words" "$LOG" | tail -3
grep -n "R693 snap\|nonblank" "$LOG" | tail -4
echo "===C343DONE=== witness complete - the f15-era verdict comes from these receipts"
