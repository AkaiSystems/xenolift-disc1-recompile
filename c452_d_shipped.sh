#!/bin/bash
# c452_state.sh - READ-ONLY STATE + VERDICT CENSUS after
# the c451 watchdog kill (241s; the tr-sanitizer pipe
# buffer ate the partial progress trail - only the
# fetch receipt survived; the apply/build/run state is
# UNKNOWN, same class as the c440/c445 kills). NO run,
# NO patch, NO build. ALSO the never-twice lesson:
# future patch scripts must tee their receipts to a
# file AS THEY RUN (exec > >(tee ...) style) so a kill
# can never erase the trail. THIS PASS: (1) the tree
# state: R1380 baseline 2c660613 or R1381-patched
# (f15arm/anchor/comment markers); (2) the pre_r1381
# backup; (3) whether the c451 cycle executed
# (shipped-script copy, build/run temp files + tails,
# snapshot dirs, run.log mtime + the wedge binary
# receipt); (4) stray emulator processes; (5) the
# run.log harvest = the R1381 VERDICT if the run
# completed: the arm fire ([f15arm]), the start (R1298),
# the stream (sectors at 10899x, FDF8 countdown, FE08
# walk), delivery (dstw0), forward execution, death
# receipts. Receipts only.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C452-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" = "2c660613e608e9f878833ece08dcb579a4f431b11c7c4e411323db2c5633f6f2" ]; then
  echo "TREE STATE: R1380 BASELINE (R1381 NOT applied - the c451 cycle died before the apply)"
else
  echo "TREE STATE: MODIFIED (candidate R1381 tree)"
fi
echo "===MARKERS452=== the R1381 marker census"
C0=$(grep -c -e "f15arm" "$SRC"); echo "f15arm marker: $C0 (1 = applied, 0 = not)"
C1=$(grep -c -e "R1381 (c450/c448 receipts)" "$SRC"); echo "R1381 comment: $C1 (1 = applied, 0 = not)"
C2=$(grep -c -e "{ /\* R1298 (c195, THE NEVER-STARTED ARMED READ): the c194 receipts" "$SRC"); echo "R1298 anchor intact: $C2 (1 either way)"
C3=$(grep -c -e "R1380 (c444)" "$SRC"); echo "R1380 lineage intact: $C3 (expect 1)"
echo "--- backup:"
ls -la runtime/runtime.c.pre_r1381 2>/dev/null || echo "no pre_r1381 backup (the apply never ran)"
[ -f runtime/runtime.c.pre_r1381 ] && shasum -a 256 runtime/runtime.c.pre_r1381
echo "===TRACE452=== did the c451 cycle execute?"
ls -la c451_d_shipped.sh 2>/dev/null || echo "no c451 shipped-script copy"
ls -la /tmp/run_full_c451.txt /tmp/c451_build.txt 2>/dev/null || echo "no c451 build/run temp files"
echo "--- build tail (if the build ran):"
tail -8 /tmp/c451_build.txt 2>/dev/null || true
echo "--- run_full tail (if the run started):"
tail -15 /tmp/run_full_c451.txt 2>/dev/null || true
ls -d c451_snap.* 2>/dev/null || echo "no c451 snapshot dirs (preserve never ran)"
ls -la c451_snap.* 2>/dev/null | head -8
echo "--- run.log identity (mtime + the executed-binary wedge receipt):"
ls -la run.log 2>/dev/null || ls -la run.log.d 2>/dev/null
grep -n -e "wedge] R1196" run.log 2>/dev/null | tail -2 || grep -n -e "wedge] R1196" run.log.d 2>/dev/null | tail -2
echo "===PROC452=== stray-process census"
ps aux | grep -i -e "xenolift" | grep -v -e "grep" | head -4 || echo "no stray emulator process"
echo "===VERDICT452=== the run.log harvest (the R1381 verdict if the run completed)"
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
echo "--- THE ARM: [f15arm] receipts:"
grep -n -e "f15arm" "$LOG" | head -4
echo "--- THE START: R1298 receipts:"
grep -n -e "R1298" "$LOG" | head -6
echo "--- THE STREAM: sectors at the file-15 band:"
grep -n -e "sector LBA 10899" "$LOG" | tail -6
echo "--- FDF8 countdown receipts:"
grep -n -e "req] FDF8" "$LOG" | tail -6
echo "--- ring walk (FE08 in the 8007F band):"
grep -n -e "FE08 8007" "$LOG" | tail -6
echo "--- delivery (dstw0 status of the last DATA HANDLER entries):"
grep -e "DATA HANDLER enter" "$LOG" | tail -4
echo "--- forward execution:"
grep -n -e "MODULE 6 ENTRY" "$LOG" | tail -2
grep -n -e "fvp" "$LOG" | tail -3
grep -n -e "READ ISSUED" "$LOG" | tail -3
echo "--- death receipts:"
grep -c -e "SIGSEGV\|BadVAddr\|TRUE DEATH" "$LOG"
grep -n -e "rungasp" "$LOG" | tail -2
echo "--- tree shas:"
echo "baseline=2c660613e608e9f878833ece08dcb579a4f431b11c7c4e411323db2c5633f6f2"
echo "actual=$SS"
echo "===C452DONE=== the c451 post-state + R1381 verdict receipts are harvested - the next step follows from these only"
