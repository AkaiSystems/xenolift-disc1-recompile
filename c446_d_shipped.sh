#!/bin/bash
# c446_state.sh - READ-ONLY STATE + VERDICT CENSUS
# after the c445 watchdog kill (240s, mid-flow; the
# census region printed - revealing the R260
# movie-loop delivery as the true 20012 site-5 arm
# and the R1376 gate at 20059 strip-matching the
# R1380 anchor - but the apply/build/run state is
# UNKNOWN, same class as the c440 kill). NO run, NO patch, NO build.
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
cd "$HOME/Downloads/xenolift" || { echo "C446-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" = "c9e85ea1d9c6ebfd9145cc948dffd37826385f58bd947267ec37b0d39c34b5fb" ]; then
  echo "TREE STATE: R1379 BASELINE (R1380 NOT applied - the c445 cycle died before the apply)"
else
  echo "TREE STATE: MODIFIED (candidate R1380 tree)"
fi
C0=$(grep -c -e "R1380 (c444)" "$SRC"); echo "R1380 guard marker: $C0 (1 = applied, 0 = not applied)"
C1=$(grep -c -e "cd_last_cmd == 0x06u && cd_seek_lba >= 100000u" "$SRC"); echo "R1380 term: $C1 (1 = applied, 0 = not)"
C2=$(grep -c -e "} else if (cd_scheduled && cd_pending == 0u) {" "$SRC"); echo "old anchor form: $C2 (0 = patched, 1 = baseline)"
C3=$(grep -c -e "R1379: bytes owed = LIVE request" "$SRC"); echo "R1379 lineage intact: $C3 (expect 2)"
echo "--- backup:"
ls -la runtime/runtime.c.pre_r1379 2>/dev/null || echo "no pre_r1379 backup"
[ -f runtime/runtime.c.pre_r1379 ] && shasum -a 256 runtime/runtime.c.pre_r1379
echo "===TRACE446=== did the c437 cycle execute?"
ls -la c445_d_shipped.sh 2>/dev/null || echo "no c445 shipped-script copy"
ls -la /tmp/run_full_c445.txt /tmp/c445_build.txt 2>/dev/null || echo "no c445 build/run temp files"
echo "--- build tail (if the build temp exists):"
tail -6 /tmp/c445_build.txt 2>/dev/null || true
echo "--- run_full tail (if the run started):"
tail -12 /tmp/run_full_c445.txt 2>/dev/null || true
ls -d c445_snap.* 2>/dev/null || echo "no c445 snapshot dirs (preserve never ran)"
ls -la c445_snap.* 2>/dev/null | head -8
echo "===PROC446=== stray-process census"
ps -axo pid,etime,command | grep -e xenogears_boot -e xenolift_run | grep -v -e grep -e c438_state || echo "no stray emulator process"
echo "===LOG446=== run.log harvest (the c437 run receipts, if it ran)"
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
ls -la "$LOG"
echo "--- TREADMILL (the R1380 verdict): site-5 cmd=06 LBA=108933 receipts (count + tail):"
grep -c -e "site=5 cmd=06 LBA=108933" "$LOG"
grep -n -e "site=5 cmd=06 LBA=108933" "$LOG" | tail -3
echo "--- SERVE in the tail (act=1 / READ ISSUED / DATA HANDLER after 20000):"
grep -n -e "act=1" "$LOG" | awk -F: '$1 > 20000' | head -4
grep -n -e "READ ISSUED" "$LOG" | awk -F: '$1 > 20000' | head -4
grep -n -e "DATA HANDLER enter" "$LOG" | awk -F: '$1 > 20000' | head -3
echo "--- STREAM: sector serves for the file-14 band:"
grep -n -e "sector LBA 1089" "$LOG" | tail -5
echo "--- R1376 receipts (arm activity):"
grep -n -e "R1376" "$LOG" | tail -5
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
echo "===C446DONE=== the c437 post-state is receipted - the verdict + next step follow from these receipts only"
