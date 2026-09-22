#!/bin/bash
# c304_queue_trace.sh - READ-ONLY: the pre-movie wedge's command
# timeline, the pause-INT2 lifecycle, and the jammed queue.
# THE c303 VERDICT: state 1 mounted clean; the wedge = the
# pre-movie poll on LegacyCdDataWait with last_cmd=02 (Setloc,
# seek=108933), pend=3, and NO command issued after the Setloc.
# The f15 stream (LBA 108995) was PAUSED (cmd 06->09, R1315
# retire) with NO INT2 completion receipted; the queue cell
# 0x80059F18 is parked at the 02020202 STAT filler (the c277-era
# GetTN stall).
# THIS PROBE: (1) the full command timeline; (2) the complete
# cmd-09/pause lifecycle - every INT2 armed/cleared receipt; (3)
# the queue nodes 0x80059F10/F14/F18/F1C - values, writers, the
# parked cell's provenance; (4) the pend=3 items + the Setloc
# writer; (5) the LegacyCdDataWait poll state. No patch, no
# compile, no run.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C304-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="82853e3bc9c2b5be37c893f608f4f57b46123a2c9ff829c47a03e589a9b5dccd"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1338b tree 82853e3b - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1338b tree)"
W=$(ls -d witness_c302_* 2>/dev/null | head -1)
LOG="$W/run.log"
[ -s "$LOG" ] || LOG="run.log"
echo "WITNESS=$LOG"
if [ ! -s "$LOG" ]; then echo "C304-NO-WITNESS"; exit 0; fi

echo "===CMDTL304=== the full command timeline"
grep -n "cmdtl\] R533" "$LOG" | head -40
echo "--- commands AFTER the pause (lines > 12058):"
awk 'NR>12058 && /cmdtl\]|last_cmd|actchg/' "$LOG" | head -16

echo "===PAUSE304=== the cmd-09 / INT2 lifecycle"
grep -n "INT2" "$LOG" | head -24
echo "--- pause/09 receipts:"
grep -n "cmd=09\|cmd 09\|PAUSE\|Pause" "$LOG" | head -24

echo "===QNODE304=== the queue nodes 0x80059F10/F14/F18/F1C"
grep -n "80059F10\|80059F14\|80059F18\|80059F1C\|59F18\|59F10" "$LOG" | head -24
echo "--- 02020202 receipts anywhere:"
grep -n "02020202" "$LOG" | head -12

echo "===PEND304=== the pend=3 items + the Setloc writer"
grep -n "pend=3" "$LOG" | head -6
grep -n "finstamp\] R1248" "$LOG" | head -12
echo "--- FE04 writer receipts (who Setloc'd 108933/1A9C3):"
grep -n "1A9C3" "$LOG" | head -12

echo "===WAIT304=== the LegacyCdDataWait / WaitForCdData poll state"
grep -n "LegacyCdDataWait\|WaitForCdData\|80041410" "$LOG" | head -16
echo "--- the last 20 lines of the loop tail:"
tail -20 "$LOG"

echo "===C304DONE=== queue trace complete - the first-missing-transition verdict comes from these receipts"
