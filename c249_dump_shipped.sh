#!/bin/bash
# c249_arena_site_dump.sh - READ-ONLY: no patch, no compile, no run.
# THE c248 VERDICT: the abort-131 IS the dispatcher sub-arena trap
# (the c239-identified second install, now caught live): [arena]
# table-install ptr=0x800C4A6C with GARBAGE cells (A8213A5C/6A2D1440/
# EF07F805/28030A88 - our R1321 restart seed was overwritten before
# the install) -> MoveHeapAllocation(800C4A6C,0x8000) release-walk ->
# cursor=-8 -> NULL-trap -> abort-131. AND THE SCREEN PAINTED 100%
# AFTER SURVIVING IT (snap #2/#3: all four regions 4800, nonblank=100%,
# 287 rects, 2.46M vram writes, structured sprite band) - then the
# fault-walk restart, a SIGSEGV at t=11s, and the kit exit 99. THE
# FIX TARGET: zero+seed the 800C4A6C sub-arena AT THE INSTALL SITE
# (the R1273/R1275/R1321 semantics), GUARDED to fire only when the
# cells do not already hold a valid chain (the game leaves valid
# chains in healthy epochs - the guard preserves them). THIS CYCLE
# extracts the byte-exact site: the [arena] table-install camera code,
# the [chain]/[walkcam] hooks, the R1321 heapzero1 seed block (the
# semantics to mirror), and the release-walk entry (fn 80031B24). The
# c250 patch is decided by these receipts.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C249-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="c111b1c34b4ae2a30e6d3647970a0d575fc99fb6a4b412a4ebbc0ce41de30c3a"
if [ ! -s "$SRC" ]; then echo "C249-FAILED: runtime/runtime.c missing"; exit 1; fi
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the c243 R1322 tree c111b1c3 - refusing a foreign tree"; exit 0; fi
echo "BASELINE_VERIFIED (the c243 R1322 tree)"
P="src_probe_c249_$(date +%Y%m%d_%H%M%S)"
if ! (mkdir -p "$P" && cp -p "$SRC" "$P/runtime.c.probe"); then echo "C249-FAILED: preserve failed"; exit 1; fi
echo "PRESERVED: $P/runtime.c.probe sha=$SS"

echo "===ARENASRC249=== the [arena] table-install camera code (the dispatcher install site)"
AN=$(grep -n "arena\] table-install" "$SRC" | head -1 | cut -d: -f1)
echo "arena-line=$AN"
if [ -n "$AN" ]; then
  S=$((AN-46)); [ "$S" -lt 1 ] && S=1
  sed -n "${S},$((AN+26))p" "$SRC"
fi

echo "===CHAINSRC249=== the [chain] MoveHeapAllocation camera code"
CN=$(grep -n "chain\] MoveHeapAllocation" "$SRC" | head -1 | cut -d: -f1)
echo "chain-line=$CN"
if [ -n "$CN" ]; then
  S=$((CN-10)); [ "$S" -lt 1 ] && S=1
  sed -n "${S},$((CN+16))p" "$SRC"
fi

echo "===WALKCAMSRC249=== the walkcam hook (the release-walk entry)"
WN=$(grep -n "walkcam\] R1238" "$SRC" | head -1 | cut -d: -f1)
echo "walkcam-line=$WN"
if [ -n "$WN" ]; then
  S=$((WN-24)); [ "$S" -lt 1 ] && S=1
  sed -n "${S},$((WN+14))p" "$SRC"
fi

echo "===SEEDSRC249=== the R1321 heapzero1/heapseed1 block (the semantics to mirror)"
ZN=$(grep -n "heapzero1\]" "$SRC" | head -1 | cut -d: -f1)
echo "heapzero1-line=$ZN"
if [ -n "$ZN" ]; then
  S=$((ZN-20)); [ "$S" -lt 1 ] && S=1
  sed -n "${S},$((ZN+22))p" "$SRC"
fi

echo "===MOVEHEAP249=== the MoveHeapAllocation fn hooks (0x80019B44 family)"
grep -n "0x80019B44\|0x80019B4Cu" "$SRC" | head -8

echo "===C249DONE=== arena site dump complete - the c250 patch is decided by these receipts"
