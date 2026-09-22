#!/bin/bash
# c323_evt_probe.sh - READ-ONLY probe (NO patch, NO run): the evt
# cooperative tick + the virtual-INT3 delivery + the FDFC path.
# THE c322 VERDICT: the op flag was SET by the serve but the evt
# cooperative tick cleared it 2 lines later without game
# consumption. The pass-era recipe ('virtual INT3: response
# delivered, op flag set' -> game pops -> ack -> FE1C walk ->
# ReadN) never fires at the tail; the FDFC-path half-delivery ate
# the scheduled response first.
# THIS CYCLE: (1) sha gate; (2) the evt cooperative tick block;
# (3) evt_deliver_class def + call sites; (4) the virtual-INT3
# delivery site terms; (5) the FDFC-path block; (6) the c322
# witness log window around the op-flag set/clear.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C323-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="b471baaf00efd956add94db8bba2ade1e7e3e8c3b01897e3cfcd0a83154217b5"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1349 tree b471baaf - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1349 tree)"
echo "===EVT323=== the evt cooperative tick block"
python3 - <<'PYEOF'
lines = open("runtime/runtime.c", "rb").read().split(b"\n")
h = [i for i, l in enumerate(lines) if b"cooperative tick" in l]
print("cooperative-tick hits: %d" % len(h))
for i in h[:2]:
    for j in range(max(0, i - 50), min(len(lines), i + 22)):
        print("%d: %s" % (j + 1, lines[j].decode("ascii", "replace")))
    print("----")
PYEOF
echo "===DELIVER323=== evt_deliver_class definition + call sites"
grep -n "evt_deliver_class" "$SRC" | head -12
python3 - <<'PYEOF'
lines = open("runtime/runtime.c", "rb").read().split(b"\n")
h = [i for i, l in enumerate(lines) if b"static void evt_deliver_class(uint32_t cls, uint32_t spec)" in l and b";" not in l]
print("DEF hits: %d" % len(h))
if h:
    i = h[0]
    j = i
    while j < len(lines) and lines[j].strip() != b"{":
        j += 1
    depth = 0; end = j
    for k in range(j, min(len(lines), j + 160)):
        depth += lines[k].count(b"{") - lines[k].count(b"}")
        if k > j and depth <= 0:
            end = k
            break
    for n in range(i, min(end + 2, i + 120)):
        print("%d: %s" % (n + 1, lines[n].decode("ascii", "replace")))
PYEOF
echo "===VINT323=== the virtual-INT3 delivery site (the pass-era recipe)"
python3 - <<'PYEOF'
lines = open("runtime/runtime.c", "rb").read().split(b"\n")
h = [i for i, l in enumerate(lines) if b"virtual INT3" in l]
print("virtual-INT3 hits: %d" % len(h))
for i in h[:2]:
    for j in range(max(0, i - 45), min(len(lines), i + 16)):
        print("%d: %s" % (j + 1, lines[j].decode("ascii", "replace")))
    print("----")
PYEOF
echo "===FDFC323=== the FDFC-path block"
python3 - <<'PYEOF'
lines = open("runtime/runtime.c", "rb").read().split(b"\n")
h = [i for i, l in enumerate(lines) if b"FDFC" in l and (b"delivered" in l or b"forced" in l)]
print("FDFC-delivery hits: %d" % len(h))
for i in h[:2]:
    for j in range(max(0, i - 40), min(len(lines), i + 14)):
        print("%d: %s" % (j + 1, lines[j].decode("ascii", "replace")))
    print("----")
PYEOF
echo "===LOG323=== the c322 witness log: the window around the op-flag set/clear"
W=$(ls -1d witness_c322_* 2>/dev/null | tail -1)
echo "WITNESS_DIR=$W"
LOG="$W/run.log"; [ -s "$LOG" ] || LOG="$W/run.log.d"
WOL=$(grep -n "wopflag" "$LOG" | head -1 | cut -d: -f1)
echo "WOPFLAG_LINE=$WOL"
if [ -n "$WOL" ]; then
  awk -v s="$((WOL-8))" -v e="$((WOL+40))" 'NR>=s && NR<=e {print NR": "$0}' "$LOG" | head -52
fi
echo "===C323DONE=== probe complete - the evt thief and the real recipe are receipted"
