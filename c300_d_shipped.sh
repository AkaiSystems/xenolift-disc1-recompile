#!/bin/bash
# c300_regwindow_probe.sh - READ-ONLY: does the runtime funnel
# handle the register window the game's driver writes through?
# THE c299 VERDICT: ONE game exe (the local SLUS_006.64 = the
# disc's; the c294-296 loader/emit theories were MY 0x800
# read-offset bug). EMIT PROVEN FAITHFUL (crt0 word-exact). THE
# GPU BAND 0x800569A0+ = REGISTER POINTER TABLE (1F801810,
# 1F801814 MDEC0/1 + 1F8010A0-1F8010F0 GPU/timer window); the
# 'stores through band values' are NORMAL register-command
# writes. SPU cells beyond t_size = BSS (no load defect).
# FAULT CANDIDATES: (a) the funnel lacks the register window ->
# register stores routed as computed-garbage -> kernel exception
# -> restart loop; (b) the band cells get poisoned at runtime
# pre-t=9s (0x01000401 is ALSO a driver command value).
# THIS PROBE: (1) the funnel's register-window routing census
# (via the known 0x1F801800 CD-reg case); (2) the band-cell
# writer census in disc1.c (every literal ref to 0x800569A0-
# 0x800569BC); (3) the fault-classification code (how
# computed-garbage targets get reported). No patch, no compile,
# no run.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C300-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="ed69fd5f6753b2e0e840ac0471b950b85c2a23c273fcaca356f4ec706831d1dc"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1337 tree ed69fd5f - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1337 tree)"
DCA="./disc1.c"
DEXPECT="3d78b0e783c9038fa7213ed29bce1d5db9453e6885bac3845bde6369c6338741"
DS=$(shasum -a 256 "$DCA" | cut -d" " -f1)
echo "DISC1_SHA=$DS"
if [ "$DS" != "$DEXPECT" ]; then echo "GATE-FAILED: disc1.c sha mismatch - refusing"; exit 0; fi
echo "DISC1_VERIFIED (fresh emission)"

echo "===REGWINDOW300=== the funnel's register-window routing (0x1F801xxx handling)"
grep -n "0x1F801800\|0x1F801810\|0x1F801814\|0x1F8010A0\|0x1F8010A4\|0x1F8010A8\|0x1F8010E0\|0x1F8010E4\|0x1F8010E8\|0x1F8010F0\|0x1F801014\|1F801050" "$SRC" | head -24
echo "--- the store-funnel routing section (via the CD-reg case):"
L=$(grep -n "0x1F801800" "$SRC" | head -1 | cut -d: -f1)
if [ -n "$L" ]; then sed -n "$((L-30)),$((L+40))p" "$SRC"; else echo "NO 0x1F801800 CASE FOUND - the CD register routing uses a different form; census:"; grep -n "1F8018\|1F8010\|1F8011" "$SRC" | head -20; fi

echo "===BANDCENSUS300=== every literal band-cell ref in the emit (writers vs readers)"
for C in 0x69A0 0x69A4 0x69A8 0x69AC 0x69B0 0x69B4 0x69B8 0x69BC; do
  N=$(grep -c "0x0000${C#0x}\|${C}\b" "$DCA" 2>/dev/null)
  SWC=$(grep -c "SW(r\[.\] + (int32_t)(int16_t)${C}\|SW(r\[.\] + (int32_t)(int16_t)0x${C#0x}" "$DCA" 2>/dev/null)
  LWC=$(grep -c "LW(r\[.\] + (int32_t)(int16_t)0x${C#0x}\|LW(r\[.\] + (int32_t)(int16_t)${C}" "$DCA" 2>/dev/null)
  echo "  band cell ${C}: total_refs=$N SW_refs=$SWC LW_refs=$LWC"
done
echo "--- any literal WRITE to a band cell (SW form):"
grep -n "SW(.*0x69A[0-9A-F]\|SW(.*0x69B[0-9A-F]" "$DCA" | head -8 | cut -c1-140
echo "--- band-adjacent computed writers (r16/r17-based stores near the driver init, first 8):"
grep -n "SW(r\[16\] + \|SW(r\[17\] + " "$DCA" | head -8 | cut -c1-140

echo "===FAULTCLASS300=== how computed-garbage targets get reported"
grep -n "computed-garbage\|computed_garbage" "$SRC" | head -8
L2=$(grep -n "computed-garbage" "$SRC" | head -1 | cut -d: -f1)
if [ -n "$L2" ]; then sed -n "$((L2-25)),$((L2+25))p" "$SRC"; fi

echo "===C300DONE=== register-window probe complete - the funnel-fix vs camera decision comes from these receipts"
