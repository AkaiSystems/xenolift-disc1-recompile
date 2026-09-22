#!/bin/bash
# c318_convert_probe.sh - READ-ONLY probe of the cd_pending
# conversion machinery (NO patch, NO run).
# THE c317 VERDICT: the armed-guard serve works (pend=3
# survives, no self-cannibalization) but the game never pops
# the FIFO and the boot-era pendclr conversions never fire at
# the tail - the armed INT1 is never converted to a guest
# interrupt. The tail game is interrupt-driven; the conversion
# path is the missing piece.
# THIS CYCLE: (1) sha gate on the R1347 tree; (2) dump all
# cd_pending references; (3) dump context around every consumer
# site outside the serve fns; (4) dump the response-FIFO case
# handlers; (5) dump the R1167 pendclr block; (6) dump the
# fd-tick handler-pair sites; (7) dump the INT1 state vars.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C318-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="39937fd9177ee05511bd28bcc74bf9ecce83a9d0f56c28a48aa553be603725b2"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1347 tree 39937fd9 - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1347 tree)"
echo "===PENDREFS318=== all cd_pending references (line-numbered)"
grep -n "cd_pending" "$SRC" | head -44
echo "===CONSUMERS318=== context around consumer sites (reads/clears/arms outside the serve fns)"
python3 - <<'PYEOF'
import re
lines = open("runtime/runtime.c", "rb").read().split(b"\n")
hits = [i for i, l in enumerate(lines) if b"cd_pending" in l]
# consumers of interest: lines mentioning pendclr, int1, arm, deliver, clear, convert, or the case handlers
keep = []
for i in hits:
    ctx = b"\n".join(lines[max(0,i-1):i+2]).lower()
    if any(k in ctx for k in [b"pendclr", b"int1", b"int 1", b"deliver", b"handler", b"convert", b"armed", b"case 0x1f80180"]):
        keep.append(i)
print("CONSUMER SITES: %d" % len(keep))
shown = 0
prev_end = -1
for i in keep[:14]:
    a = max(0, i-10); b = min(len(lines), i+14)
    if shown > 320: break
    if a <= prev_end: a = prev_end + 1
    if b <= a: continue
    print("---- context %d..%d ----" % (a+1, b))
    for j in range(a, b):
        print("%d: %s" % (j+1, lines[j].decode("ascii", "replace")))
    prev_end = b; shown += (b - a)
PYEOF
echo "===FIFOCASE318=== the response-FIFO case handlers"
python3 - <<'PYEOF'
lines = open("runtime/runtime.c", "rb").read().split(b"\n")
for pat in (b"case 0x1F801801", b"case 0x1F801802", b"case 0x1F801803"):
    h = [i for i, l in enumerate(lines) if pat in l]
    print("---- %s: %d hit(s) ----" % (pat.decode(), len(h)))
    for i in h[:2]:
        for j in range(max(0,i-6), min(len(lines), i+40)):
            print("%d: %s" % (j+1, lines[j].decode("ascii", "replace")))
PYEOF
echo "===PENDCLR318=== the R1167 pendclr block"
python3 - <<'PYEOF'
lines = open("runtime/runtime.c", "rb").read().split(b"\n")
h = [i for i, l in enumerate(lines) if b"pendclr" in l]
print("hits: %d" % len(h))
if h:
    i = h[0]
    for j in range(max(0,i-30), min(len(lines), i+12)):
        print("%d: %s" % (j+1, lines[j].decode("ascii", "replace")))
PYEOF
echo "===FDTICK318=== the fd-tick handler-pair sites"
grep -n "fd-tick\|fd_tick\|handler-pair\|handler pair" "$SRC" | head -10
python3 - <<'PYEOF'
lines = open("runtime/runtime.c", "rb").read().split(b"\n")
h = [i for i, l in enumerate(lines) if b"fd-tick" in l or b"fd_tick" in l or b"handler-pair" in l]
for i in h[:3]:
    for j in range(max(0,i-12), min(len(lines), i+26)):
        print("%d: %s" % (j+1, lines[j].decode("ascii", "replace")))
    print("----")
PYEOF
echo "===INTVAR318=== the INT1 state variables"
grep -n "cd_arm_int1\|cd_int1\|cd_int_\|arm1" "$SRC" | head -24
echo "===C318DONE=== probe complete - the conversion machinery code is receipted; the c319 delivery fix designs from these terms"
