#!/bin/bash
# c309_setloc_prov.sh - READ-ONLY: the Setloc-reply gate that
# misses the 108933 re-read posture.
# THE c308 VERDICT: R1339 PASS (zero door fires, zero faults,
# clean exit-0, the mount thrash gone) - and the retire exposed
# the underlying defect: the game wedges at the SETLOC REPLY
# WAIT (cmd=02 issued, FE1C=1 holding, owes=125048
# seek=108933 dst=800A9994, the ReadN never issues). FIELD-SEEK
# assist v4 served SetLoc answers at 108754 early - the
# machinery exists; its gate misses 108933.
# THIS PROBE: (1) the FIELD-SEEK assist gate code; (2) this
# run's FIELD-SEEK + pendclr receipts (which LBAs got replies);
# (3) the cmd-02 dispatch path in the CD model; (4) the FE1C
# 1->0 writer census. No patch, no compile, no run.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C309-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="9da166fbd3ba8b18f41fec7defbedde3e62f6b9917f259987ddc91e9c292d91e"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1339 tree 9da166fb - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1339 tree)"
W=$(ls -d witness_c308_* 2>/dev/null | head -1)
LOG="$W/run.log"
[ -s "$LOG" ] || LOG="run.log"
echo "WITNESS=$LOG"
if [ ! -s "$LOG" ]; then echo "C309-NO-WITNESS"; exit 0; fi

echo "===ASSIST309=== the FIELD-SEEK assist gate code"
grep -n "FIELD-SEEK" "$SRC" | head -6
L=$(grep -n "FIELD-SEEK assist" "$SRC" | head -1 | cut -d: -f1)
if [ -n "$L" ]; then echo "--- context around line $L:"; sed -n "$((L-30)),$((L+40))p" "$SRC"; else echo "FIELD-SEEK site not found by tag - searching the receipt text:"; grep -n "SetLoc answer" "$SRC" | head -4; L=$(grep -n "SetLoc answer" "$SRC" | head -1 | cut -d: -f1); [ -n "$L" ] && sed -n "$((L-30)),$((L+40))p" "$SRC"; fi

echo "===SERVED309=== this run's Setloc replies (FIELD-SEEK fires + pendclr clears)"
grep -n "FIELD-SEEK" "$LOG" | head -10
grep -n "pendclr" "$LOG" | head -30
echo "--- pendclr for cmd=02 (which LBAs got reply clears):"
grep -n "pendclr.*cmd=02" "$LOG" | head -12

echo "===STOPCTX309=== where the protocol stopped (context around the last READ ISSUED)"
RL=$(grep -n "READ ISSUED" "$LOG" | tail -1 | cut -d: -f1)
echo "LAST_READ_LINE=$RL"
if [ -n "$RL" ]; then awk -v s="$((RL-6))" -v e="$((RL+20))" 'NR>=s && NR<=e' "$LOG"; fi

echo "===CMD2DISP309=== the cmd-02 dispatch path in the CD model"
grep -n "case 0x02u\|case 0x02:" "$SRC" | head -8
for L in $(grep -n "case 0x02" "$SRC" | head -3 | cut -d: -f1); do echo "--- context around line $L:"; sed -n "$((L-8)),$((L+24))p" "$SRC"; done

echo "===FE1CW309=== the FE1C 1->0 writer census (the transition the game awaits)"
grep -n "8004FE1C" "$SRC" | grep -n "write32\|memcpy\|= 0u" | head -12
grep -n "xenolift_mem_write32(0x8004FE1C" "$SRC" | head -12
echo "===C309DONE=== Setloc-reply provenance complete - the c310 fix design comes from these receipts"
