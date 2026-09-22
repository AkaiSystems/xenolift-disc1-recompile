#!/bin/bash
# c233_which_runaway.sh - READ-ONLY: no patch, no compile, no run.
# The c232 receipts: the R1319-widened branch FIRED (fldfp #1, guest-native
# for the member-14 stream), 14 natural exits, member-14 chain ran the full
# mount->read->decode path - BUT lzrwatch=1: ONE runaway still converts to
# crash-kit recovery (bootmain=14, era wiped each cycle), and the suspicious
# exit at 10984 (r4=0x801EF305, r5=r15=r14=8006FAF0, zero-progress exit
# shape) points at the movie module's HLE stream. This extraction names
# the remaining runaway stream: all 14 exits with sources, the lzrwatch
# window verbatim, the fencelife arm census, the native decode completion,
# and the HLE'd stream list.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C233-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
LOG="run.log"
EXPECT="b5c2f865979a0de0bc08f3c6afbe7d0672bc687a5c1f420412497dea7ebd42a9"
if [ ! -s "$LOG" ]; then echo "C233-FAILED: run.log missing"; exit 1; fi
SS=$(shasum -a 256 "$LOG" | cut -d" " -f1)
echo "LOG_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: run.log is not the c232 post-run log - refusing a foreign log"; exit 0; fi
echo "BASELINE_VERIFIED (the c232 post-run log)"
P="runlog_preserve_c233_$(date +%Y%m%d_%H%M%S)"
if ! (mkdir -p "$P" && cp -p "$LOG" "$P/run.log"); then echo "C233-FAILED: preserve failed"; exit 1; fi
echo "PRESERVED: $P/run.log sha=$SS"

win() { S=$1; [ "$S" -lt 1 ] && S=1; awk -v s="$S" -v e="$2" 'NR>=s&&NR<=e{printf "%d:%s\n",NR,$0}NR>e{exit}' "$LOG"; }
rng() { awk -v s="$1" -v e="$2" 'NR>=s&&NR<=e{printf "%d:%s\n",NR,$0}NR>e{exit}' "$LOG" | grep "$3" | head -"$4"; }

echo "===EXITS233=== ALL natural exits with sources (the stream census)"
grep -n "lzss-x\] EXIT" "$LOG"

echo "===ARMS233=== every fencelife arm (which streams ran unpacks)"
grep -n "fencelife\] R1169 fence ARMED" "$LOG" | head -16

echo "===HLE233=== the HLE'd streams"
grep -n "lzss-hle\] src=" "$LOG" | head -12

echo "===NATIVE233=== the native member-14 decode progress + completion"
N=$(grep -n "\[fldfp\] R691" "$LOG" | head -1 | cut -d: -f1)
echo "fldfp-line=$N"
if [ -n "$N" ]; then
  S=$((N-6)); [ "$S" -lt 1 ] && S=1
  awk -v s="$S" -v e=$((N+50)) 'NR>=s&&NR<=e{printf "%d:%s\n",NR,$0}NR>e{exit}' "$LOG" | grep -v "^\S*:\[hook\]" | head -40
fi
echo "--- the member-14 unpack/exit receipts (src 801DD680-era):"
grep -n "lzss.*801DD680\|unpackw" "$LOG" | head -10

echo "===RUNAWAY233=== the lzrwatch conversion window VERBATIM (the remaining fault)"
NL=$(grep -n "lzrwatch" "$LOG" | head -1 | cut -d: -f1)
echo "lzrwatch-line=$NL"
if [ -n "$NL" ]; then
  S=$((NL-90)); [ "$S" -lt 1 ] && S=1
  win "$S" $((NL+8))
fi

echo "===GUARD233=== the first suppressed reads of the runaway (the read addresses name the stream)"
grep -n "lzss-guard-r\] suppressed read" "$LOG" | head -8

echo "===ERA233=== the dd680 era span + coordw map"
grep -n "801DD680" "$LOG" | head -2
grep -n "801DD680" "$LOG" | tail -2
grep -n "coordw" "$LOG" | head -6
grep -n "coordw" "$LOG" | tail -3
echo "===C233DONE=== runaway-attribution extraction complete - the c234 fix is decided by these receipts"
