#!/bin/bash
# c427_regview.sh - READ-ONLY CENSUS. NO run, NO patch.
# The c426 receipts resolved the five-stage failure at
# stage 3, THE REGISTER VIEW: the mirror cells point at
# the CD registers (0x80056770=1F801800 ... 7C=1F801803),
# and getintr polls the hardware DIRECTLY: SB(0x1F801800,
# 1)=index select 1; LBU(0x1F801803)&7 = the PENDING INT
# FLAGS (index 1); the record copy reads the RESPONSE
# FIFO 0x1F801801; the tail writes 7 to 1803/1802 = the
# ACK. The kernel polls and sees nothing because our INT
# delivery is internal bookkeeping, never exposed on the
# register reads. The game's callbacks ARE registered
# (0x80040DA0 at 0x800564A8, 0x80040DC8 at 0x800564AC).
# THIS PASS: (1) the runtime's 0x1F801800-0x1F801803
# read/write handlers - what they return, whether the
# index select is modeled, where the response FIFO is
# served; (2) the cd_pending ARM sites (where INT1/2/3
# get set) and the pendclr site-6/site-7 hooks (how the
# guest's register ops currently ack our internal
# pending); (3) the cd_force_deliver_int1/2/3 entry
# conditions. NO behavior change - receipts only.
# R1378 follows from these receipts only.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C427-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="6759e34359fdf33df2e78cfaf2c144194da718412f3d42cb022b12e87470a8bb"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1377 tree - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1377 tree)"
echo "===REGHANDLERS427=== the CD register emulation (0x1F801800-0x1F801803)"
for R in 1F801800 1F801801 1F801802 1F801803; do
  N=$(grep -c -e "0x${R}" "$SRC")
  echo "--- 0x${R}: ${N} refs"
  grep -n -e "0x${R}" "$SRC" | head -8
done
echo "--- the read-handler region for 1F801800 (first ref, context +50):"
F=$(grep -n -e "0x1F801800" "$SRC" | head -1 | cut -d: -f1)
echo "first 1F801800 ref at line: $F"
if [ -n "$F" ]; then
  awk -v s="$F" -v e="$((F+50))" 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
fi
echo "===PENDARM427=== the cd_pending arm sites + pendclr hooks"
grep -n -e "cd_pending = " "$SRC" | head -16
echo "--- the pendclr site-6/site-7 hooks:"
grep -n -e "site=6\|site=7\|site6\|site7" "$SRC" | head -10
echo "--- pendclr camera region (first ref, +25):"
P=$(grep -n -e "pendclr" "$SRC" | head -1 | cut -d: -f1)
echo "first pendclr ref at line: $P"
if [ -n "$P" ]; then
  awk -v s="$P" -v e="$((P+25))" 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
fi
echo "===FORCEDELIVER427=== the force-deliver entry conditions"
grep -n -e "cd_force_deliver_int" "$SRC" | head -12
G=$(grep -n -e "static.*cd_force_deliver_int1" "$SRC" | head -1 | cut -d: -f1)
echo "--- cd_force_deliver_int1 head (line $G, +40):"
if [ -n "$G" ]; then
  awk -v s="$G" -v e="$((G+40))" 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
fi
echo "===C427DONE=== the register-view + arm/ack contracts are decoded - R1378 follows from these receipts only"
