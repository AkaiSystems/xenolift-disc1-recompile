#!/bin/bash
# c235_remaining_runaways.sh - READ-ONLY: no patch, no compile, no run.
# The c234 receipts: R1320 WORKED for its stream - the member-14 guest pass
# exited cleanly at its first group check ([lzss-x] EXIT r5=r15=r14=
# 8006FAF0 r4=801DD685, twice), HLE decoded 260862 with the correct module
# header. NEW SIGNAL: cur1=6 (zero in c232) - the state-1 mount latch fires
# repeatedly now. BUT lzrwatch=2/runaway=200: TWO OTHER streams still
# convert to crash-kit recovery each run (bootmain=8). This extraction
# names them: both lzrwatch windows verbatim, the full arm/exit stream
# census, and all cur=1 windows (does state 1 engage, or does the
# remaining conversion eat the era?). The c236 fix is decided by these
# receipts.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C235-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
LOG="run.log"
EXPECT="20f1921a930682f788d782064d8be19e9232871f14bc9ffbc0de782859327d27"
if [ ! -s "$LOG" ]; then echo "C235-FAILED: run.log missing"; exit 1; fi
SS=$(shasum -a 256 "$LOG" | cut -d" " -f1)
echo "LOG_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: run.log is not the c234 post-run log - refusing a foreign log"; exit 0; fi
echo "BASELINE_VERIFIED (the c234 post-run log)"
P="runlog_preserve_c235_$(date +%Y%m%d_%H%M%S)"
if ! (mkdir -p "$P" && cp -p "$LOG" "$P/run.log"); then echo "C235-FAILED: preserve failed"; exit 1; fi
echo "PRESERVED: $P/run.log sha=$SS"

win() { S=$1; [ "$S" -lt 1 ] && S=1; awk -v s="$S" -v e="$2" 'NR>=s&&NR<=e{printf "%d:%s\n",NR,$0}NR>e{exit}' "$LOG"; }

echo "===ARMS235=== every fencelife arm (the stream census)"
grep -n "fencelife\] R1169 fence ARMED" "$LOG"

echo "===EXITS235=== ALL natural exits"
grep -n "lzss-x\] EXIT" "$LOG"

echo "===HLE235=== the HLE'd streams"
grep -n "lzss-hle\] src=" "$LOG"

echo "===RUNAWAY235=== BOTH lzrwatch conversion windows (the remaining faults)"
for NL in $(grep -n "lzrwatch" "$LOG" | cut -d: -f1); do
  echo "--- lzrwatch at line $NL (context):"
  S=$((NL-30)); [ "$S" -lt 1 ] && S=1
  win "$S" $((NL+4)) | grep -v "lzss-runaway\] .* ops suppressed"
  echo "--- the runaway stream's march (sampled):"
  win "$S" "$NL" | grep "lzss-runaway\]" | awk 'NR<=3 || NR%20==0'
done

echo "===GUARD235=== the first suppressed reads of each runaway"
grep -n "lzss-guard-r\] suppressed read" "$LOG" | head -12

echo "===CUR235=== the cur=1 windows (does state 1 ENGAGE?)"
grep -n "cur=0x00000001" "$LOG" | head -8
for CL in $(grep -n "cur=0x00000001" "$LOG" | head -3 | cut -d: -f1); do
  echo "--- cur=1 at line $CL (+30):"
  win "$CL" $((CL+30)) | grep -v "bandhist\|\[hook\]" | head -24
done
echo "--- all statetbl state-1 samples:"
grep -n "active state 1" "$LOG" | head -8

echo "===CENSUS235=== era map"
grep -n "bootmain" "$LOG" | head -10
echo "===C235DONE=== extraction complete - the c236 fix is decided by these receipts"
