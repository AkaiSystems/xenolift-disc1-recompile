#!/bin/bash
# c224_alloc_fork.sh - READ-ONLY: no patch, no compile, no run.
# The c223 dossier named the fork: the state-1 (menu) mount's 125304-byte
# alloc carve SUCCEEDS (take #7) but the hand returns v0(r2)=0 and the game
# takes the failure branch - no member-14 fetch, res stays 0, poison
# unpack, abort 130, clean exit at t=36s. This extraction decides whether
# r2=0 is the broken return (the c225 fix: make the hand return the block)
# or a status register (fork elsewhere): every hand+take receipt, the
# seeded-terminator cells, the healthy state-6 mount comparison, and the
# state-1 era's request machinery.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C224-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
LOG="run.log"
EXPECT="656563091452f56159f5362c96ab0b62b1fa039bebc61269d88a653ecdd35d39"
if [ ! -s "$LOG" ]; then echo "C224-FAILED: run.log missing"; exit 1; fi
SS=$(shasum -a 256 "$LOG" | cut -d" " -f1)
echo "LOG_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: run.log is not the c222 post-run log - refusing a foreign log"; exit 0; fi
echo "BASELINE_VERIFIED"
P="runlog_preserve_c224_$(date +%Y%m%d_%H%M%S)"
if ! (mkdir -p "$P" && cp -p "$LOG" "$P/run.log"); then echo "C224-FAILED: preserve failed"; exit 1; fi
echo "PRESERVED: $P/run.log sha=$SS size=$(wc -c < "$P/run.log" | tr -d " ")"

win() { S=$1; [ "$S" -lt 1 ] && S=1; awk -v s="$S" -v e="$2" 'NR>=s&&NR<=e{printf "%d:%s\n",NR,$0}NR>e{exit}' "$LOG"; }
rng() { awk -v s="$1" -v e="$2" 'NR>=s&&NR<=e{printf "%d:%s\n",NR,$0}NR>e{exit}' "$LOG" | grep "$3" | head -"$4"; }

echo "===HANDS224=== every alloc hand receipt (the return-value fork)"
echo "hand_count=$(grep -c "\[hand\]" "$LOG")"
grep -n "\[hand\]" "$LOG"
echo "--- windows around the first 12 hands (8 before, 4 after):"
for N in $(grep -n "\[hand\]" "$LOG" | cut -d: -f1 | head -12); do echo "--- hand at line $N:"; win $((N-8)) $((N+4)); done

echo "===TAKES224=== every carve take receipt"
echo "take_count=$(grep -c "\[take\]" "$LOG")"
grep -n "\[take\]" "$LOG" | head -20

echo "===HEAPALLOC224=== every heap alloc"
grep -n "\[heap\] alloc" "$LOG" | head -30

echo "===TERMIN224=== the R1273/R1275 seeded-terminator state"
grep -n "R1273\|R1275\|seeded\|terminator\|heapseed" "$LOG" | head -20
echo "--- the 77450-region cells wherever printed:"
grep -n "77450" "$LOG" | head -20

echo "===MOUNT6224=== the healthy state-6 mount window (the data-adopt comparison)"
win 10315 10380

echo "===STATE1ERA224=== the state-1 era request machinery (10300-13050): arc/req/newmod/stab/slot/sm/menuchain"
rng 10300 13050 "arc\]\|\[req\]\|newmod\]\|\[stab\]\|\[slot\]\|\[sm\|menuchain" 40

echo "===ARCHREQ224=== the archive request cells posture"
grep -n "ARCH-REQ" "$LOG" | head -8
echo "archreq_count=$(grep -c "ARCH-REQ" "$LOG")"

echo "===ASY224=== the PollArchiveTransfer exits in the state-1 era"
rng 10300 13050 "asyctx" 12

echo "===C224DONE=== alloc-fork extraction complete - the c225 fix is decided by these receipts"
