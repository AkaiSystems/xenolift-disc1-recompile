#!/bin/bash
# c324_waitloop_probe.sh - READ-ONLY probe (NO patch, NO run):
# the wait-loop delivery block (the runtime's pump-substitute).
# THE c323 VERDICT: the game's event pump NEVER runs at the
# tail; the wait-loop delivery block (21804+) is the runtime's
# designed answer ('deliver here exactly the way the pump
# would') and the [cd] wait-loop tick receipts prove it runs at
# the tail with pend=3 - but its delivery terms refuse.
# THIS CYCLE: (1) sha gate; (2) dump the full block 21790-22010
# (delivery terms, event classes, camera conditions); (3) the
# wait-loop tick + delivery receipts from the c322 witness log.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C324-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="b471baaf00efd956add94db8bba2ade1e7e3e8c3b01897e3cfcd0a83154217b5"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1349 tree b471baaf - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1349 tree)"
echo "===BLOCK324=== the wait-loop delivery block (lines 21790-22010)"
python3 - <<'PYEOF'
lines = open("runtime/runtime.c", "rb").read().split(b"\n")
for n in range(21789, min(len(lines), 22010)):
    print("%d: %s" % (n + 1, lines[n].decode("ascii", "replace")))
PYEOF
echo "===TICKCODE324=== the wait-loop tick camera site"
grep -n "wait-loop tick" "$SRC" | head -4
echo "===LOG324=== the c322 witness: wait-loop tick cadence + any delivery receipts near the serve"
W=$(ls -1d witness_c322_* 2>/dev/null | tail -1)
echo "WITNESS_DIR=$W"
LOG="$W/run.log"; [ -s "$LOG" ] || LOG="$W/run.log.d"
grep -c "wait-loop tick" "$LOG"
grep -n "wait-loop deliver\|wldeliver\|wl: " "$LOG" | tail -10
echo "===C324DONE=== probe complete - the wait-loop delivery terms are receipted"
