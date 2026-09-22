#!/bin/bash
# c441_state.sh - READ-ONLY STATE CENSUS after the
# c440 watchdog kill (cycle died at 240s mid-flow,
# partial evidence - the R1379c apply/build/run state
# is UNKNOWN: the script may have applied the guard,
# built, and started the 90s run when killed). NO run, NO patch, NO build.
# THIS PASS: (1) the tree state: baseline 6c916b3f or
# R1379-patched (marker census); (2) the
# pre_r1379 backup; (3) whether the c437 script was
# fetched/executed at all (c437_d_shipped.sh +
# /tmp/run_full_c437.txt + snapshot dirs); (4) stray
# emulator processes; (5) the run.log harvest: the
# spin-discard receipts of the c437 run (did the
# guard hold?), the walk past LBA 9, mount-cell
# stability, death receipts. Receipts only - the
# verdict + next step follow from these only.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C441-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" = "6c916b3fc08cc29c92247a12aaea6cd4f294e9c395164490e737ab690b782737" ]; then
  echo "TREE STATE: BASELINE R1378 (R1379 NOT applied)"
else
  echo "TREE STATE: MODIFIED (candidate R1379 tree) - marker census follows"
fi
C1=$(grep -c -e "bytes owed = LIVE request" "$SRC"); echo "R1379 guard markers: $C1 (2 = applied, 0 = not applied)"
C2=$(grep -c -e "R1379" "$SRC"); echo "R1379 tokens: $C2 (2 = applied, 0 = not applied)"
C3=$(grep -c -e "spin-discard: dead INT w/ stale FIFO" "$SRC"); echo "discard prints: $C3 (expect 2 either way)"
echo "--- backup:"
ls -la runtime/runtime.c.pre_r1379 2>/dev/null || echo "no pre_r1379 backup"
[ -f runtime/runtime.c.pre_r1379 ] && shasum -a 256 runtime/runtime.c.pre_r1379
echo "===TRACE441=== did the c437 cycle execute?"
ls -la c440_d_shipped.sh c439_d_shipped.sh 2>/dev/null || echo "no shipped-script copies"
ls -la /tmp/run_full_c440.txt /tmp/c440_build.txt 2>/dev/null || echo "no c440 build/run temp files"
echo "--- build tail (if the build temp exists):"
tail -6 /tmp/c440_build.txt 2>/dev/null || true
echo "--- run_full tail (if the run started):"
tail -12 /tmp/run_full_c440.txt 2>/dev/null || true
ls -d c440_snap.* 2>/dev/null || echo "no c440 snapshot dirs (preserve never ran)"
ls -la c440_snap.* 2>/dev/null | head -8
echo "===PROC441=== stray-process census"
ps -axo pid,etime,command | grep -e xenogears_boot -e xenolift_run | grep -v -e grep -e c438_state || echo "no stray emulator process"
echo "===LOG441=== run.log harvest (the c437 run receipts, if it ran)"
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
ls -la "$LOG"
echo "--- GUARD: spin-discard receipts + count:"
grep -c -e "spin-discard" "$LOG"
grep -n -e "spin-discard" "$LOG" | head -6
echo "--- WALK: past LBA 9?"
grep -n -e "FE04 00000009->0000000A" "$LOG" | head -3
grep -n -e "LBA=10\|LBA 10 " "$LOG" | head -3
echo "--- MOUNT + fvp (menu/mount activity tail):"
grep -n -e "mcw" "$LOG" | tail -3
grep -n -e "fvp" "$LOG" | tail -3
echo "--- DEATH:"
grep -n -e "rungasp\|TRUE DEATH" "$LOG" | tail -3
echo "--- logcap/tail:"
grep -n -e "logcap end" "$LOG" | tail -1
tail -8 "$LOG"
echo "===C441DONE=== the c437 post-state is receipted - the verdict + next step follow from these receipts only"
