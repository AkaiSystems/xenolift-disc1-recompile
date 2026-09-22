#!/bin/bash
# c303_wedge_probe.sh - READ-ONLY: extract the first-boot-pass
# wedge posture from the c302 witness.
# THE c302 VERDICT: fault family plausibly dead (180 fault-free
# seconds) - but the run wedged IN THE FIRST BOOT PASS: one
# bootentry (#1, epoch=0, all-zero regs), statetbl printed once
# then never, heap cell 0x80059320=0 (never seeded), file#14/18
# reads re-issued without retiring, f15 STAMPED but never
# issued, nonblank=3%.
# THIS PROBE: (1) bootentry/statetbl full census; (2) the f15
# request lifecycle - every mtrans stamp, ALL READ ISSUED
# line-numbered, every schdd decision for LBA 108995; (3) the
# spin posture - wedgespin/pollkick counters, A22C/mvloop,
# fld2sig; (4) did the R1333 archive-band camera ever fire
# (silence = menu-init never reached); (5) heap cell 0x80059320
# receipts. No patch, no compile, no run.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C303-FAILED: xenolift dir missing"; exit 1; }
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
echo "WITNESS=$LOG sha=$(shasum -a 256 "$LOG" | cut -d' ' -f1)"
if [ ! -s "$LOG" ]; then echo "C303-NO-WITNESS"; exit 0; fi

echo "===BOOTP303=== bootentry + statetbl census (single-pass confirmation)"
grep -c "bootentry" "$LOG"
grep -n "bootentry\] R710" "$LOG" | head -8
grep -c "statetbl" "$LOG"
grep -n "statetbl\] R1104 bootentry pass" "$LOG" | head -8

echo "===F15LIFE303=== the f15 request lifecycle"
grep -n "mtrans\]" "$LOG" | head -10
echo "--- ALL READ ISSUED (line-numbered):"
grep -n "READ ISSUED" "$LOG"
echo "--- file#15 receipts anywhere:"
grep -n "file#=15\|file#15\|108995" "$LOG" | head -12
echo "--- schdd delivery decisions (tail):"
grep -n "schdd" "$LOG" | tail -14

echo "===SPIN303=== the spin posture"
grep -n "wedgespin\|WEDGE-SPIN\|R967" "$LOG" | tail -8
grep -n "pollkick\|R1197" "$LOG" | tail -6
grep -n "A22C" "$LOG" | tail -6
grep -n "fld2sig\|fldfrz" "$LOG" | tail -8
echo "--- the last CD posture (FE1C/FDF8/FE04) receipts:"
grep -n "FE1C=" "$LOG" | tail -8

echo "===CAMERAS303=== did the menu-init cameras ever fire"
echo "--- R1333 archive-band [fbw]: $(grep -c "\[fbw\]" "$LOG")"
grep -n "\[fbw\]" "$LOG" | head -6
echo "--- R1335 reverb-band [rvbw]: $(grep -c "\[rvbw\]" "$LOG")"
grep -n "\[rvbw\]" "$LOG" | head -6
echo "--- R1338b pointer tripwire [gpw]: $(grep -c "\[gpw\]" "$LOG")"
echo "--- R1334 sound-heap [shhead]: $(grep -c "\[shhead\]" "$LOG")"
grep -n "\[shhead\]" "$LOG" | head -6

echo "===HEAP303=== the heap cell 0x80059320 + install receipts"
grep -n "80059320" "$LOG" | head -8
grep -n "seed\|R1321" "$LOG" | tail -8
echo "--- run.log tail (the wedge's own last words):"
tail -14 "$LOG"

echo "===C303DONE=== wedge extraction complete - the retirement-blocker verdict comes from these receipts"
