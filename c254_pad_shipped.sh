#!/bin/bash
# c254_pad_machinery_dump.sh - READ-ONLY: no patch, no compile, no run.
# THE c253 VERDICT (190s evidence run, no code change): the interior
# trap (r5=800C8314) is DETERMINISTIC AND SURVIVABLE (same single
# trap, same guard postures, abort-131 -> immediate recovery, every
# arc). THE VIRTUAL PLAYER NEVER FIRED IN 190s: zero padstart
# receipts, btn=BFFF in all 32 polled samples - while the game menu
# machinery ran the whole time (KernelMenuMain/Initialize/Update
# entries across epochs, choice=0 released=0, ReadControllerButtons
# polling live at buf=8006261E). THE PRESS->RESPONSE MILESTONE IS
# BLOCKED BY THE INJECTION NOT FIRING AT THIS ERA's POSTURE (the old
# padstart fires belonged to the earlier pre-movie polling path).
# ALSO: file#15 stamped+requested (FDF8=92180) but NO READ ISSUED
# receipt for file#15 - the next loading-chain item after the menu.
# THIS CYCLE extracts the injection machinery byte-exactly: the
# padstart/R809 site + its fire condition, the R693 virtual-player
# re-arm code, the padrd/R811 site + the START-posture decode, and
# the controller buffer path - so the c255 patch fires a deliberate
# press-and-release into the MENU-ERA polling (the receipted-live
# posture). The c255 patch is decided by these receipts.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C254-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="98c55c8305de9ed239d0e4ba428213b8fc5168adc57ef238a213c01c7bf96243"
if [ ! -s "$SRC" ]; then echo "C254-FAILED: runtime/runtime.c missing"; exit 1; fi
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1325 tree 98c55c83 - refusing a foreign tree"; exit 0; fi
echo "BASELINE_VERIFIED (the R1325 tree)"

echo "===PADSTART254=== the R809 padstart injection site + its fire condition"
PN=$(grep -n "padstart\] R809" "$SRC" | head -1 | cut -d: -f1)
echo "padstart-line=$PN"
if [ -n "$PN" ]; then
  S=$((PN-50)); [ "$S" -lt 1 ] && S=1
  sed -n "${S},$((PN+20))p" "$SRC"
fi

echo "===REARM254=== the R693 virtual-player re-arm code"
RN=$(grep -n "R693" "$SRC" | head -1 | cut -d: -f1)
echo "rearm-line=$RN"
if [ -n "$RN" ]; then
  S=$((RN-30)); [ "$S" -lt 1 ] && S=1
  sed -n "${S},$((RN+30))p" "$SRC"
fi

echo "===PADRD254=== the R811 ReadControllerButtons camera + the START-posture decode"
DN=$(grep -n "padrd\] R811" "$SRC" | head -1 | cut -d: -f1)
echo "padrd-line=$DN"
if [ -n "$DN" ]; then
  S=$((DN-40)); [ "$S" -lt 1 ] && S=1
  sed -n "${S},$((DN+20))p" "$SRC"
fi
echo "--- the START-held posture decode:"
grep -n "START-held\|BFFF4000" "$SRC" | head -6

echo "===PADCELL254=== the controller buffer + pad cell path (where a press lands)"
grep -n "8006261E\|8006261Cu\|0x8006261" "$SRC" | head -8
echo "--- the mvloop padcell path (the earlier era injection target):"
MC=$(grep -n "mvloop\] pre-movie polling" "$SRC" | head -1 | cut -d: -f1)
echo "mvloop-line=$MC"
if [ -n "$MC" ]; then
  S=$((MC-20)); [ "$S" -lt 1 ] && S=1
  sed -n "${S},$((MC+16))p" "$SRC"
fi

echo "===VPLAYER254=== the virtual player machinery (all sites)"
grep -n "virtual player\|vplayer\|virt_pad\|R693\|padstart" "$SRC" | head -16

echo "===C254DONE=== pad machinery dump complete - the c255 patch is decided by these receipts"
