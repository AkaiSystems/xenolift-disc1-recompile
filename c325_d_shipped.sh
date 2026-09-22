#!/bin/bash
# c325_tickbody_probe.sh - READ-ONLY probe (NO patch, NO run):
# the rest of the wait-loop tick body (the conversion + the
# collector/slot dispatch loop).
# THE c324 VERDICT: the tick fires 8730 times at the tail with
# pend=3 yet no conversion. The R122 in-body conversion is
# documented 'convert a STUCK pending INT1' - the tail holds an
# INT3 COMMAND RESPONSE: the body may convert only the INT1
# class. THIS CYCLE: (1) sha gate; (2) dump 22010-22720 (the
# conversion + the collector/slot dispatch loop + every
# cd_pending class condition); (3) grep the c322 witness for the
# tick body's delivery receipts.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C325-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="b471baaf00efd956add94db8bba2ade1e7e3e8c3b01897e3cfcd0a83154217b5"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1349 tree b471baaf - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1349 tree)"
echo "===BODY325=== the rest of the tick body (lines 22010-22720)"
python3 - <<'PYEOF'
lines = open("runtime/runtime.c", "rb").read().split(b"\n")
for n in range(22009, min(len(lines), 22720)):
    print("%d: %s" % (n + 1, lines[n].decode("ascii", "replace")))
PYEOF
echo "===LOG325=== the c322 witness: the tick body's delivery receipts"
W=$(ls -1d witness_c322_* 2>/dev/null | tail -1)
echo "WITNESS_DIR=$W"
LOG="$W/run.log"; [ -s "$LOG" ] || LOG="$W/run.log.d"
echo "--- fd-collector tick / pump / would-arm / h2 h4 dispatch prints ---"
grep -n "fd-collector tick" "$LOG" | head -8
grep -n "pump\] slotbits" "$LOG" | head -6
grep -n "would-arm" "$LOG" | tail -4
grep -n "dispatch h2\|dispatch h4\|handler pair" "$LOG" | tail -8
echo "--- the delivery-side counters: rspop/pendclr AFTER the serve line ---"
WS=$(grep -n "wserve" "$LOG" | head -1 | cut -d: -f1)
echo "WSERVE_LINE=$WS"
if [ -n "$WS" ]; then awk -v s="$WS" 'NR>=s && /rspop|pendclr|response consumed/ {print NR": "$0}' "$LOG" | head -8; fi
echo "===C325DONE=== probe complete - the INT3 refusal of the tick body is receipted"
