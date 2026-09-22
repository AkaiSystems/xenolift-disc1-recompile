#!/bin/bash
# c237_seed_site_dump.sh - READ-ONLY: no patch, no compile, no run.
# The c236 receipts: the state-6 restore chain survives because R1273
# (region zero) + R1275 (fn_80031A68-semantics seed: head node, terminator,
# head cell 59320) heal its heap BEFORE the install walk; the state-1 chain
# runs the SAME code (table-install -> MoveHeapAllocation -> ReleaseAllHeap-
# Blocks) with NO equivalent seed and traps at head=0 -> node=-8 (the R911/
# R912 dead-terminator class, guard reads FFFFFFFC/FFF8, 524K+ NULL-traps).
# The state-1 region is receipted twice: 800C4270..800CC270 (a1=0x8000),
# head node expected at region+0x7FC (the game's own bank write at 800C4A70
# = the node's flags cell). THE FIX is R1275-for-state-1 (c238) - but no
# blind splice (the c181 lesson): this cycle dumps the EXACT R1273/R1275
# hook block (gate, scope, seed writes) and the head-cell receipts in the
# state-1 era, so the c238 insert anchors byte-exact.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C237-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
LOG="run.log"
SRC="runtime/runtime.c"
EXPECT="20f1921a930682f788d782064d8be19e9232871f14bc9ffbc0de782859327d27"
if [ ! -s "$LOG" ]; then echo "C237-FAILED: run.log missing"; exit 1; fi
SS=$(shasum -a 256 "$LOG" | cut -d" " -f1)
echo "LOG_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: run.log is not the preserved c234 log"; exit 0; fi
if [ ! -s "$SRC" ]; then echo "C237-FAILED: runtime/runtime.c missing"; exit 1; fi
echo "SRC_SHA=$(shasum -a 256 "$SRC" | cut -d" " -f1)"
echo "BASELINE_VERIFIED"

echo "===LOCATE237=== the R1273/R1274/R1275 sites in runtime.c"
grep -n "heapzero\|heapseed\|heapshape\|R1273\|R1274\|R1275" "$SRC" | head -20

echo "===SEEDBLOCK237=== the full R1273/R1275 hook block (the c238 template)"
HZ=$(grep -n "heapzero" "$SRC" | head -1 | cut -d: -f1)
echo "heapzero-line=$HZ"
if [ -n "$HZ" ]; then
  S=$((HZ-90)); [ "$S" -lt 1 ] && S=1
  sed -n "${S},$((HZ+90))p" "$SRC"
fi

echo "===RESTART237=== the R709 restart-step site (the hook's dispatch context)"
RS2=$(grep -n "RESTART STEP" "$SRC" | head -1 | cut -d: -f1)
echo "restart-site-line=$RS2"
if [ -n "$RS2" ]; then
  S=$((RS2-30)); [ "$S" -lt 1 ] && S=1
  sed -n "${S},$((RS2+30))p" "$SRC"
fi

echo "===HEAD237=== the head-cell 59320 receipts per era (state-6 vs state-1)"
echo "--- state-6 era (lines 10990-11035):"
awk 'NR>=10990&&NR<=11035{printf "%d:%s\n",NR,$0}NR>11035{exit}' "$LOG" | grep "59320\|59324" | head -6
echo "--- state-1 era (lines 14740-14795):"
awk 'NR>=14740&&NR<=14795{printf "%d:%s\n",NR,$0}NR>14795{exit}' "$LOG" | grep "59320\|59324" | head -6
echo "--- all [hook] head-cell writers across the run:"
grep -n "hook\].*80059320\|hook\].*59320" "$LOG" | head -12

echo "===TRAPCTX237=== the state-1 trap regs context (what cell was null)"
awk 'NR>=14786&&NR<=14795{printf "%d:%s\n",NR,$0}NR>14795{exit}' "$LOG" | grep -v "bandhist\|\[hook\]" | head -12

echo "===C237DONE=== seed-site dump complete - c238 ships the state-1 seed from this template"
