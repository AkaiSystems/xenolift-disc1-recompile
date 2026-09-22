#!/bin/bash
# c244_trapwalk_locator.sh - READ-ONLY: no patch, no compile, no run.
# THE c243 VERDICT: R1322 patched+parsed but INERT (0 BLOCKED, 0 WIN - the
# seq-112 posture never occurred; the receipted nondeterminism swing).
# The trajectory regressed: bootmain=9, nulltraps=564 (the c162-era
# all-zero-walk ~565 signature = an UNSEEDED walk ran), lzrwatch=1, the
# state-1 CB entered x2 requesting file#14 (READ ISSUED x4 = a
# request-restart loop), final screen BLANK, exit 137 at the fuse.
# THIS CYCLE names the walk: the first NULL-trap context (which a0, which
# caller), the walkcam/arena/chain receipts around it, the seed census
# (did R1273/R1275/R1321 fire?), the era map (which idx values restart),
# the file#14 loop between two READ ISSUEDs, and the lzrwatch context.
# The c245 fix is decided by these receipts.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C244-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
LOG="run.log"
EXPECT="c010aab8ef71f1b011136a03c294e49d2202238fe52f49976845d7c125c633c1"
if [ ! -s "$LOG" ]; then echo "C244-FAILED: run.log missing"; exit 1; fi
SS=$(shasum -a 256 "$LOG" | cut -d" " -f1)
echo "LOG_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: run.log is not the c243 post-run log - refusing a foreign log"; exit 0; fi
echo "BASELINE_VERIFIED (the c243 post-run log)"
P="runlog_preserve_c244_$(date +%Y%m%d_%H%M%S)"
if ! (mkdir -p "$P" && cp -p "$LOG" "$P/run.log"); then echo "C244-FAILED: preserve failed"; exit 1; fi
echo "PRESERVED: $P/run.log sha=$SS"

echo "===SEEDS244=== did the three seeds fire? (R1273/R1275 zero+seed, R1321 state-1)"
echo "heapzero6=$(grep -c "heapzero\]" "$LOG") heapseed6=$(grep -c "heapseed\]" "$LOG") heapzero1=$(grep -c "heapzero1\]" "$LOG") heapseed1=$(grep -c "heapseed1\]" "$LOG")"
grep -n "heapzero\]\|heapseed\]\|heapzero1\]\|heapseed1\]" "$LOG" | head -8

echo "===TRAP244=== the first NULL-trap + its walk (which region, which caller)"
TN=$(grep -n "NULL-trap #" "$LOG" | head -1 | cut -d: -f1)
echo "first_trap_line=$TN total_traps=$(grep -c "NULL-trap #" "$LOG")"
if [ -n "$TN" ]; then
  S=$((TN-30)); [ "$S" -lt 1 ] && S=1
  awk -v s="$S" -v e="$((TN+3))" 'NR>=s&&NR<=e{printf "%d:%s\n",NR,$0}NR>e{exit}' "$LOG" | grep -v "bandhist\|\[hook\]" | head -24
fi
echo "--- the walkcam/arena/chain receipts of the whole run (which a0 values):"
grep -n "walkcam\] R1238\|arena\] table-install\|chain\] MoveHeapAllocation" "$LOG" | head -14
echo "--- the trap3 register receipts:"
grep -n "trap3\]" "$LOG" | head -6

echo "===ERA244=== the restart/idx map"
grep -n "restart\] R709" "$LOG" | head -12
echo "--- boot entries:"
grep -n "bootentry\] R710" "$LOG" | head -10
echo "--- statetbl samples:"
grep -n "active state" "$LOG" | head -8

echo "===F14LOOP244=== the file#14 request-restart loop (the chain between issues)"
grep -n "READ ISSUED" "$LOG" | head -6
I2=$(grep -n "READ ISSUED" "$LOG" | sed -n '2p' | cut -d: -f1)
if [ -n "$I2" ]; then
  S=$((I2-12)); [ "$S" -lt 1 ] && S=1
  awk -v s="$S" -v e="$((I2+2))" 'NR>=s&&NR<=e{printf "%d:%s\n",NR,$0}NR>e{exit}' "$LOG" | grep -v "bandhist\|\[hook\]\|pumpcam" | head -12
fi
echo "--- mtrans receipts:"
grep -n "mtrans\]" "$LOG" | head -8

echo "===LZRW244=== the lzrwatch conversion context"
LN=$(grep -n "lzrwatch" "$LOG" | head -1 | cut -d: -f1)
echo "lzrwatch_line=$LN"
if [ -n "$LN" ]; then
  S=$((LN-10)); [ "$S" -lt 1 ] && S=1
  awk -v s="$S" -v e="$((LN+6))" 'NR>=s&&NR<=e{printf "%d:%s\n",NR,$0}NR>e{exit}' "$LOG" | head -14
fi

echo "===EXIT244=== the fuse context (last lines before the gasp)"
GR=$(grep -n "rungasp" "$LOG" | head -1 | cut -d: -f1)
if [ -n "$GR" ]; then
  S=$((GR-24)); [ "$S" -lt 1 ] && S=1
  awk -v s="$S" -v e="$((GR-1))" 'NR>=s&&NR<=e{printf "%d:%s\n",NR,$0}NR>e{exit}' "$LOG" | grep -v "bandhist\|\[hook\]\|pumpcam\|\[spu\]" | head -18
fi

echo "===C244DONE=== trap-walk locator complete - the c245 fix is decided by these receipts"
