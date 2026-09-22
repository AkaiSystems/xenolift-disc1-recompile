#!/bin/bash
# c225_seed_anchor_probe.sh - READ-ONLY: no patch, no compile, no run.
# c224 decoded the fault: the state-1 (menu) mount's 125304-byte alloc
# concludes at the R1275-SEEDED state-6 terminator (flags carry the
# heap-top class, next self-points) whose serve span is region-bounded -
# 16212 fits in-region (hand 8007B4FC = terminator-16212), 125304 lands
# below the region floor -> refused -> hand 0 -> mount aborts -> res=0 ->
# poison unpack -> abort 130 -> clean exit. The TRUE heap-top sentinel
# (801FBFF8, ~820KB free) served every successful big alloc this run and
# is never reached. c226 will re-point the seeded terminator at the
# state-1 mount (next=801FBFF8, strip the false heap-top bit). This probe
# extracts the byte-exact anchors: the R1275 seed site, the R1273 zero
# site, and the [mount] MountGameStateModule camera site.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C225-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
R="runtime/runtime.c"
if [ ! -s "$R" ]; then echo "C225-FAILED: runtime/runtime.c missing"; exit 1; fi
SS=$(shasum -a 256 "$R" | cut -d" " -f1)
echo "SRC_SHA=$SS"
EXPECT="cb31fa9ae0c9fd8eafa224bde313471b552fa5fe45e1db6919cebb77fbbd7967"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the cb31fa9a c222 tree - nothing extracted"; exit 0; fi
echo "BASELINE_VERIFIED (the c222 R1317 tree)"
P="source_probe_c225_$(date +%Y%m%d_%H%M%S)"
if ! (mkdir -p "$P" && cp -p "$R" "$P/runtime.c.probe"); then echo "C225-FAILED: preserve failed"; exit 1; fi
echo "PRESERVED: $P/runtime.c.probe sha=$(shasum -a 256 "$P/runtime.c.probe" | cut -d" " -f1)"

win() { S=$1; [ "$S" -lt 1 ] && S=1; awk -v s="$S" -v e="$2" 'NR>=s&&NR<=e{printf "%d:%s\n",NR,$0}NR>e{exit}' "$R"; }

echo "===HEAPSEED225=== the R1275 seed site (every occurrence + context)"
grep -n "R1275\|heapseed\|SEEDED" "$R" | head -12
N=$(grep -n "heapseed" "$R" | head -1 | cut -d: -f1)
echo "--- context around first heapseed print (line $N, 45 before, 12 after):"
[ -n "$N" ] && win $((N-45)) $((N+12))

echo "===HEAPZERO225=== the R1273 zero site"
grep -n "R1273\|heapzero\|ZEROED" "$R" | head -8
N=$(grep -n "heapzero" "$R" | head -1 | cut -d: -f1)
echo "--- context around first heapzero print (line $N, 45 before, 12 after):"
[ -n "$N" ] && win $((N-45)) $((N+12))

echo "===MOUNT225=== the [mount] MountGameStateModule camera site (the c226 insertion anchor)"
grep -n "MountGameStateModule\|unpack-dest cell set" "$R" | head -12
N=$(grep -n "unpack-dest cell set" "$R" | head -1 | cut -d: -f1)
echo "--- context around the unpack-dest print (line $N, 45 before, 25 after):"
[ -n "$N" ] && win $((N-45)) $((N+25))

echo "===TOPSENT225=== the true heap-top sentinel handling (rectguard R700/R702 sites)"
grep -n "rectguard\|R700\|R702\|801FBFF8\|801FC000" "$R" | head -20

echo "===MEMW225=== the memory-write helper signatures available at the mount site"
grep -n "xenolift_mem_write32" "$R" | head -6

echo "===C225DONE=== anchor probe complete - c226 authors the byte-exact terminator re-point"
