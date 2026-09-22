#!/bin/bash
# c431_state.sh - READ-ONLY STATE CENSUS after the
# c430 watchdog kill (cycle 39 killed at 240s, "hung
# run; partial evidence" - the block output was lost
# past the header, so the apply/build/run state is
# UNKNOWN). NO new run, NO build, NO patch. THIS PASS:
# (1) the tree state: is R1378 applied (marker
# census) or is the tree still baseline 6759e343?
# (2) the stray-process census: the watchdog kills
# the CYCLE, not necessarily the child emulator - is
# a wedged run still alive? (harvest first, then kill
# by exact PID only if found - it was abandoned by
# the killed cycle); (3) the run.log harvest: [drdoor]
# receipts, pendclr site=8, the final-era cmdtl
# ladder, TRUE DEATH/rungasp, where it hung; (4) the
# pre_r1378 backup + snapshot dirs. Receipts only.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C431-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" = "6759e34359fdf33df2e78cfaf2c144194da718412f3d42cb022b12e87470a8bb" ]; then
  echo "TREE STATE: BASELINE R1377 (patch NOT applied - a gate refused or apply never reached)"
else
  echo "TREE STATE: MODIFIED (candidate R1378 tree) - marker census follows"
fi
for M in "drdoor" "R1378" "r1378_door_polls" "cd_pending_stamp(1u, 8u)" "R96 fallback: kernel polling the INT flag"; do
  C=$(grep -c -e "$M" "$SRC")
  echo "marker $M: $C"
done
echo "--- backup:"
ls -la runtime/runtime.c.pre_r1378 2>/dev/null || echo "no pre_r1378 backup"
[ -f runtime/runtime.c.pre_r1378 ] && shasum -a 256 runtime/runtime.c.pre_r1378
echo "===PROC431=== stray-process census (the watchdog kills the cycle, not the child)"
ps -axo pid,etime,command | grep -e xenogears_boot -e xenolift_run -e "./run.sh" | grep -v -e grep -e c431_state || echo "no stray emulator process"
PIDS=$(ps -axo pid,command | grep -e xenogears_boot | grep -v -e grep -e c431_state | awk '{print $1}')
echo "===LOG431=== run.log harvest (receipts of what the c430 run did)"
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
ls -la "$LOG"
echo "--- drdoor (the R1378 fires):"
N=$(grep -c -e "drdoor" "$LOG")
echo "count: $N"
if [ "$N" -gt 0 ]; then grep -n -e "drdoor" "$LOG" | head -10; fi
echo "--- pendclr site=8 (the door's events consumed by the game's own ack):"
N=$(grep -c -e "site=8" "$LOG")
echo "count: $N"
if [ "$N" -gt 0 ]; then grep -n -e "site=8" "$LOG" | head -8; fi
echo "--- final-era cmdtl ladder:"
grep -n -e "cmdtl" "$LOG" | awk -F: '$1 > 30000' | head -12
echo "--- death receipts:"
grep -n -e "TRUE DEATH" -e "rungasp" "$LOG" | tail -6
echo "--- logcap/end + tail:"
grep -n -e "logcap" "$LOG" | tail -2
tail -16 "$LOG"
echo "===SNAP431=== snapshot dirs from c430"
ls -d c430_snap.* 2>/dev/null || echo "no c430 snapshot dirs (preserve never ran)"
ls -la c430_snap.* 2>/dev/null | head -10
echo "===KILL431=== harvest complete - kill stray abandoned run by exact PID (if any)"
if [ -n "$PIDS" ]; then
  for P in $PIDS; do
    echo "killing abandoned run PID $P"
    kill "$P" 2>/dev/null && echo "kill signal sent to $P" || echo "kill failed for $P"
  done
  sleep 2
  ps -p $PIDS >/dev/null 2>&1 && echo "STILL ALIVE after TERM" || echo "confirmed gone"
else
  echo "no stray run to kill"
fi
echo "===C431DONE=== the c430 post-state is receipted - R1378 verdict + reship plan follow from these receipts only"
