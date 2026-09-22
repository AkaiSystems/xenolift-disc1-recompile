#!/bin/bash
# c533_census.sh - READ-ONLY CENSUS of the R844 boot-loop
# bypass + the epoch fault-walk exits, NO RUN, NO BUILD, NO
# PATCH. THE c532 DECODE (complete): the R1394 interpreter
# window is [0x8006F000, 0x80090000) - the OVL window itself
# (0x21000 bytes, matching the capture; the c532 dump used
# the wrong base 0x80077E88 - the capture is 0x8006F000-based,
# but the finding is base-independent). THE CAPTURE IS
# 0/135168 NONZERO - the whole module window was ZERO at the
# stop: the interpreter was dispatched at fn=0x80077E88
# into a sea of zeros, executed ~24670 consecutive NOPs, and
# fell straight through to the window bound at 0x80090000 -
# the honest class-3 stop. THE CHAIN: the R844 boot-loop
# bypass forced the field-coordinator door at epoch-4 boot
# ENTRY - BEFORE the boot could reinstall its modules - and
# the window was empty because the c528 heapclr had just
# zeroed it at the 31986 restart. PRE-heapclr trees left the
# previous epoch's real module in RAM, so the forced door
# found genuine coordinator code; the honest stop now exposes
# the backup plan's flaw: it forces a door whose module is
# NOT installed. THE DEEPER FIRST FAULT remains un-receipted:
# each boot epoch ends in a fault-walk exit (no era handoff) -
# epoch 3 installed all its modules (newmod 29957-31364), ran
# to the 8004B894 event-check era (stompcam 31642), then
# faulted. THIS CENSUS: (1) the R844 source block (the exact
# condition + the force call + its placement - the patch
# anchor); (2) the 40 lines before EACH fault-walk restart
# (12350, 25276, 31985 - what fault ends each epoch?); (3)
# the epoch-3 tail around the 8004B894 stomp; (4) the
# epoch-4 window (31987-32001, boot entry -> bypass -> stop);
# (5) the newmod epoch timeline (each epoch reinstalls);
# (6) the base-corrected capture dump (the true module head
# at 0x8006F000 + the true entry region at 0x80077E88).
# Fail-closed, tee'd to /tmp/c533_receipts.txt.
# Pure-ASCII output.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C533-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c533_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="663fc0efdb3620943ad1940e1d0892847805dcaab1508fec91f4f0ef6eaae7b7"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the c531 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the c531 tree with the landed zrfF command-byte widen)"
LOG="run.log"
if [ ! -s "$LOG" ]; then echo "GATE-FAILED: no run.log"; exit 0; fi
echo "LOG=run.log ($(wc -l < "$LOG" | tr -d " ") lines)"
echo "===BYP533=== the R844 boot-loop bypass source (the patch anchor)"
grep -n -e "R844" "$SRC" | head -10
B1=$(grep -n -F -e "BOOT-LOOP BYPASS" "$SRC" | head -1 | cut -d: -f1)
echo "--- the bypass block (first hit at line $B1) with context:"
if [ -n "$B1" ]; then
  _B0=$((B1-36)); [ "$_B0" -lt 1 ] && _B0=1
  sed -n "${_B0},$((B1+30))p" "$SRC"
fi
echo "--- any additional BOOT-LOOP BYPASS sites:"
grep -c -F -e "BOOT-LOOP BYPASS" "$SRC" | tr -d " " | sed "s/^/BOOT-LOOP BYPASS refs: /"
echo "===FW533=== what fault ends each epoch? (the 40 lines before each fault-walk restart)"
for FWL in 12350 25276 31985; do
  echo "--- the 40 lines before line $FWL (the exit that became a restart):"
  _F0=$((FWL-40)); [ "$_F0" -lt 1 ] && _F0=1
  sed -n "${_F0},$((FWL+2))p" "$LOG" | tail -42
done
echo "===EPC533=== the epoch-3 tail around the 8004B894 stomp (the last pre-exit activity)"
sed -n "31630,31700p" "$LOG"
echo "===E4W533=== the epoch-4 window (boot entry -> bypass -> the honest stop)"
sed -n "31987,32001p" "$LOG"
echo "===NM533=== the newmod epoch timeline (each epoch reinstalls its modules)"
grep -n -e "\[newmod\]" "$LOG" | tail -14
echo "===CAPBASE533=== the base-corrected capture dump (the true module head at 0x8006F000 + the true entry at 0x80077E88)"
python3 - <<'PYEOF'
import struct, os
BASE = 0x8006F000
ENTRY = 0x80077E88
if not os.path.exists("ovlstop_capture.bin"):
    print("(capture absent - section skipped)")
else:
    d = open("ovlstop_capture.bin","rb").read()
    print("capture size: %d bytes (window %08X..%08X)" % (len(d), BASE, BASE+len(d)))
    nz = sum(1 for b in d if b)
    print("capture nonzero bytes: %d / %d" % (nz, len(d)))
    print("--- the true module head (first 16 words at 8006F000):")
    for i in range(0, min(64,len(d)), 4):
        w = struct.unpack_from("<I", d, i)[0]
        print("  %08X: %08X" % (BASE+i, w))
    eo = ENTRY - BASE
    print("--- the true entry region (16 words at 80077E88, capture offset 0x%X):" % eo)
    if 0 <= eo < len(d):
        for i in range(eo, min(len(d),eo+64), 4):
            w = struct.unpack_from("<I", d, i)[0]
            print("  %08X: %08X" % (BASE+i, w))
    else:
        print("entry outside the capture")
PYEOF
echo "===C533DONE=== the R844 source + the epoch fault contexts are receipted - the c534 fix (the empty-window gate on the bypass, or what the epoch faults name) follows from these receipts only - digest is pure ASCII"
