#!/bin/bash
# c305_pendcensus_probe.sh - READ-ONLY: the INT arm/clear census.
# WHICH notification is the one that never cleared?
# THE c304 VERDICT: LegacyCdDataWait returns clean (ret=0,
# FDFC=0, FE1C=0 - all exit conditions hold); pend=3 is chronic
# (present during every successful load) but dropped 3->1 late
# (cmdtl #10 resp=3/0). The 108995 PAUSE got NO INT2 arm (early
# pauses did: 'Pause complete: INT2 armed' + cleared). The game
# holds an armed read batch (FDF8=125304, dest FE08=800A9994,
# cmd=02, act=0) that never restarts; f15 enqueued (F0C=0F,
# ticket 00331524) never issued. HYPOTHESIS: the game waits for
# the pause's INT2 before issuing the next ReadN.
# THIS PROBE: (1) the full pendclr R1167 arm/clear census - which
# INT was armed but never cleared after line 12058; (2) the
# pause-arm census (armed vs occurred); (3) the lad2 ladder
# receipts around the pause; (4) the FE48 door writer/clearer;
# (5) the final pend/fifo posture. No patch, no compile, no run.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C305-FAILED: xenolift dir missing"; exit 1; }
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
if [ ! -s "$LOG" ]; then echo "C305-NO-WITNESS"; exit 0; fi

echo "===PENDCENSUS305=== the full INT arm/clear census (pendclr R1167)"
grep -n "pendclr\]" "$LOG" | head -40
echo "--- pendclr lines after 12058 (the pause era onward):"
awk 'NR>12058 && /pendclr\]/' "$LOG" | head -20
echo "--- pend-arm receipts (pending.*armed / ARMED):"
grep -n "armed" "$LOG" | grep -i "int\|pending" | head -20

echo "===PAUSEARM305=== pause/seek-complete arm census"
grep -n "Pause complete\|Seek complete\|complete: INT" "$LOG" | head -20
echo "--- pauses that OCCURRED (adv599 R1315 + R533 09 transitions):"
grep -c "adv599\] R1315 PAUSE retire" "$LOG"
grep -n "cmd 06->09\|cmd 09->02" "$LOG"

echo "===LADDER305=== the lad2 ladder receipts around the pause"
grep -n "lad2\]" "$LOG" | head -24
echo "--- lad2 after 12058:"
awk 'NR>12058 && /lad2\]/' "$LOG" | head -12

echo "===FE48305=== the door flag writer/clearer"
grep -n "8004FE48\|FE48" "$LOG" | head -16

echo "===TAIL305=== the final pend/fifo posture (last receipts)"
grep -n "wait-loop tick" "$LOG" | tail -6
grep -n "pend=" "$LOG" | tail -4
echo "===C305DONE=== INT census complete - the named-missing-notification verdict comes from these receipts"
