#!/bin/bash
# c307_stepper_prov.sh - READ-ONLY: the success recipe vs the wedge.
# THE c306 VERDICT: the R892 ARCHIVE-TRANSFER-DONE heal fired on
# the f15 posture (owes 92084) and delivered 46 sectors to the
# STALE file#14 dst 800A9994 - the f15 debt 'completed' into the
# wrong buffer; 17 mount refires; the game never consumes the
# heal's delivery. F0C = FILE NUMBER (confirmed by the hook
# sequence); F0C=0x0F = the game's own file#15 request arm,
# stamped but never converted to READ ISSUED. The c350-era run
# DID convert it - the normal path works in some trajectories.
# THIS PROBE: (1) the witness inventory - does a c350-era
# witness survive? if yes, its READ ISSUED file#15 context is
# the success recipe; (2) the game's post-arm behavior around
# the F0C 0x0F write + the R648 stamp; (3) the R892 gate code;
# (4) the game-side stepper: fn 80041430 body + fn_80029690
# callers. No patch, no compile, no run.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C307-FAILED: xenolift dir missing"; exit 1; }
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
if [ ! -s "$LOG" ]; then echo "C307-NO-WITNESS"; exit 0; fi

echo "===WITLIST307=== the surviving witness inventory"
ls -d witness_* 2>/dev/null
echo "--- any witness with a READ ISSUED file#=15 (the success recipe):"
for D in witness_*; do
  L2="$D/run.log"
  if [ -s "$L2" ]; then
    C=$(grep -c "READ ISSUED.*file#=15" "$L2" 2>/dev/null)
    echo "WITNESS $D: file15_reads=$C"
  fi
done

echo "===F15CTX307=== the game's post-arm behavior (F0C 0x0F write + R648 stamp)"
FL=$(grep -n "0x80059F0C.*-> 0000000F" "$LOG" | head -2 | cut -d: -f1)
echo "F0C_0F_HOOK_LINES=$FL"
for L in $FL; do
  echo "--- context around hook line $L:"
  awk -v s="$((L-8))" -v e="$((L+14))" 'NR>=s && NR<=e' "$LOG"
done
SL=$(grep -n "R648 f15 request stamped" "$LOG" | head -1 | cut -d: -f1)
echo "R648_STAMP_LINE=$SL"
if [ -n "$SL" ]; then awk -v s="$((SL-8))" -v e="$((SL+14))" 'NR>=s && NR<=e' "$LOG"; fi

echo "===R892GATE307=== the R892/R889 heal gate code (full)"
sed -n '980,1120p' "$SRC"

echo "===STEPPER307=== the game-side request stepper"
D1=$(ls runtime/disc1.c 2>/dev/null || ls disc1.c 2>/dev/null | head -1)
echo "DISC1=$D1"
if [ -s "$D1" ]; then
  echo "--- fn 80041430 def (the F0C writer/stepper):"
  L=$(grep -n "xenolift_fn_80041430" "$D1" | head -1 | cut -d: -f1)
  if [ -n "$L" ]; then sed -n "$L,$((L+50))p" "$D1"; else echo "80041430 def not found"; fi
  echo "--- fn_80029690 callers (the read-issue chain):"
  grep -n "xenolift_fn_80029690" "$D1" | head -8
  echo "--- the 80029690 def head:"
  L=$(grep -n "static.*xenolift_fn_80029690" "$D1" | head -1 | cut -d: -f1)
  if [ -n "$L" ]; then sed -n "$L,$((L+40))p" "$D1"; fi
fi
echo "===C307DONE=== stepper provenance complete - the fix design verdict comes from these receipts"
