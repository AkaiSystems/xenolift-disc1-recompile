#!/bin/bash
# c331_pairbodies.sh - READ-ONLY probe (NO patch, NO run):
# the pair's emitted bodies from the Mac's FRESH disc1.c.
# THE c330 VERDICT: the bank-set fired correctly and the pair
# STILL refused (post-pair byte-identical). The refusal is
# inside the pair's own code path - its first branch checks
# something other than the INT flag. THE CODE ITSELF names the
# term. THIS CYCLE: (1) sha gate; (2) the pair's emitted
# bodies + context; (3) the SysEnqIntRP registration struct;
# (4) the raw c330 window around the dispatch; (5) the evt
# registration state if receiptable.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C331-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="1415b5ccfa38535bdbada7677029073e26e2d99e6a8ad909e86710e48702b261"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1353 tree 1415b5cc - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1353 tree)"
echo "===DISC1LOC=== locate the emitted guest source (fresh, Mac-side)"
ls -la disc1.c runtime/disc1.c 2>/dev/null
for F in disc1.c runtime/disc1.c; do
  if [ -s "$F" ]; then echo "FOUND=$F SIZE=$(wc -c < "$F" | tr -d ' ')"; fi
done
D="disc1.c"
[ -s "$D" ] || D="runtime/disc1.c"
if [ ! -s "$D" ]; then echo "PROBE-FAILED: no disc1.c found"; exit 0; fi
echo "DISC1=$D"
echo "===PAIRHITS=== the pair function hits in the emitted source"
grep -n "800409E4\|80040A4C" "$D" | head -12
echo "===PAIRBODY47=== the 800409E4 body (context around each hit)"
python3 - "$D" <<'PYEOF'
import sys
path = sys.argv[1]
lines = open(path, "rb").read().split(b"\n")
hits = [i for i, l in enumerate(lines) if b"800409E4" in l]
print("hits: %d" % len(hits))
for h in hits[:3]:
    lo = max(0, h - 6); hi = min(len(lines), h + 34)
    for j in range(lo, hi):
        print("%d: %s" % (j + 1, lines[j].decode("ascii", "replace")))
    print("--------")
PYEOF
echo "===PAIRBODY48=== the 80040A4C body (context around each hit)"
python3 - "$D" <<'PYEOF'
import sys
path = sys.argv[1]
lines = open(path, "rb").read().split(b"\n")
hits = [i for i, l in enumerate(lines) if b"80040A4C" in l]
print("hits: %d" % len(hits))
for h in hits[:3]:
    lo = max(0, h - 6); hi = min(len(lines), h + 34)
    for j in range(lo, hi):
        print("%d: %s" % (j + 1, lines[j].decode("ascii", "replace")))
    print("--------")
PYEOF
echo "===ENQINT=== the SysEnqIntRP registration struct (0x8005A200)"
grep -n "8005A200" "$D" | head -6
python3 - "$D" <<'PYEOF'
import sys
path = sys.argv[1]
lines = open(path, "rb").read().split(b"\n")
hits = [i for i, l in enumerate(lines) if b"8005A200" in l]
for h in hits[:2]:
    lo = max(0, h - 4); hi = min(len(lines), h + 14)
    for j in range(lo, hi):
        print("%d: %s" % (j + 1, lines[j].decode("ascii", "replace")))
    print("--------")
PYEOF
echo "===W330=== the raw c330 window around the dispatch (any hooked activity during the pair?)"
W=$(ls -1d witness_c330_* 2>/dev/null | tail -1)
echo "WITNESS_DIR=$W"
LOG="$W/run.log"; [ -s "$LOG" ] || LOG="$W/run.log.d"
G=$(grep -n "\[wgen\]" "$LOG" | head -1 | cut -d: -f1)
echo "WGEN_LINE=$G"
if [ -n "$G" ]; then awk -v s="$((G-4))" -v e="$((G+4))" 'NR>=s && NR<=e {print NR": "$0}' "$LOG"; fi
echo "===EVTREG=== the evt registration state cells (0x8005A200 area) if receiptable in the log"
grep -n "8005A200\|evt_tab\|enqint" "$LOG" | head -8
echo "===C331DONE=== probe complete - the pair's first-branch condition is the named term"
