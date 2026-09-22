#!/bin/bash
# c259_door_dump.sh - READ-ONLY: no patch, no compile, no run.
# THE c258 VERDICT: the f15 wedge is receipted - the game armed
# file#15 (FE04=108995 FDF8=92180, the mtrans R648 stamp) after the
# drive had already crossed into LBA 108995 during file#14's stream
# (ReadN serving 108995 kernel-expected, ladder 01->09->02->06
# receipted at t=0s); but the late request sits ARMED-IDLE:
# last_cmd=02 read_active=0 data_loaded=0 pending=0 sched=0, drive
# parked, FDF8=92180 FDFC=1 FE1C=0, no READ ISSUED for file#15, the
# game polling a drive that cannot answer. THE MVDOOR NEAR-MISSES:
# R889 owes=00016814 seek_lba=108995 cmd=02 but match=0 (failing
# terms: FE1C(5F)=0, FE48(5F)=1, A22C=4). zrfB fires are all
# seek<150 (system band) - NOTHING covers the FILE BAND at the A22C
# site, where the game actually polls. THE PLAN: c260 adds the
# A22C-site file-band serve door (the proven zrf composite) gated on
# the c258-receipted posture - but the exact gate/site code must be
# in front of me first (the c181 blind-anchor lesson). THIS CYCLE
# dumps: the A22C read site + zrfB block, the mvdoor R889 gate, the
# zrfG gate, the cdf force-deliver site, and the FDF8-arm writer
# context. The c260 patch is decided by these receipts.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C259-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="33402d7f708187c87b03fc559298fe391cfab6ae64c211ad814718361f6c6b29"
if [ ! -s "$SRC" ]; then echo "C259-FAILED: runtime/runtime.c missing"; exit 1; fi
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1327 tree 33402d7f - refusing a foreign tree"; exit 0; fi
echo "BASELINE_VERIFIED (the R1327 tree)"

echo "===A22CSITE259=== the A22C read site (where the game polls; zrfB lives here)"
ZB=$(grep -n "zrfB\] R1280" "$SRC" | head -1 | cut -d: -f1)
echo "zrfB-receipt-line=$ZB"
if [ -n "$ZB" ]; then
  S=$((ZB-90)); [ "$S" -lt 1 ] && S=1
  sed -n "${S},$((ZB+40))p" "$SRC"
fi

echo "===MVDOOR259=== the mvdoor R889 gate (exact match terms)"
MV=$(grep -n "mvdoor-near\] R889" "$SRC" | head -1 | cut -d: -f1)
echo "mvdoor-line=$MV"
if [ -n "$MV" ]; then
  S=$((MV-70)); [ "$S" -lt 1 ] && S=1
  sed -n "${S},$((MV+20))p" "$SRC"
fi

echo "===ZRFG259=== the zrfG gate + site (the parked file-band composite)"
ZG=$(grep -n "zrfG\|R1285" "$SRC" | head -1 | cut -d: -f1)
echo "zrfG-line=$ZG"
if [ -n "$ZG" ]; then
  S=$((ZG-40)); [ "$S" -lt 1 ] && S=1
  sed -n "${S},$((ZG+40))p" "$SRC"
fi

echo "===CDF259=== the cdf force-deliver site (the INT1 deliver composite)"
CF=$(grep -n "force-deliver" "$SRC" | head -1 | cut -d: -f1)
echo "cdf-line=$CF"
if [ -n "$CF" ]; then
  S=$((CF-20)); [ "$S" -lt 1 ] && S=1
  sed -n "${S},$((CF+20))p" "$SRC"
fi

echo "===FDF8ARM259=== the FDF8-arm writer context (fn 80040FCC, sw_line 71714)"
FW=$(grep -n "80040FCC" "$SRC" | head -3)
echo "$FW"

echo "===C259DONE=== door dump complete - the c260 A22C-site file-band serve is decided by these receipts"
