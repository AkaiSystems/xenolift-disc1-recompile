#!/bin/bash
# c239_state1_era_census.sh - READ-ONLY: no patch, no compile, no run.
# THE c238 VERDICT: the R1321 state-1 seed LANDED (head cell 59320
# game-set to 800C4A74 = our head node +8, the state-6 pattern to the
# byte), the 524K NULL-trap loop is DEAD (nulltraps=1, lzrwatch=0), and
# STATE 1 ENGAGED AND HELD (statetbl active state 1, pFnMain=80077E88,
# hasOverlay=1, THREE samples to the fuse) - with the game own menu
# code processing a CIRCLE-release and calling ChangeGameState(1)
# itself. The screen painted 100 percent nonblank but UNIFORM (not yet
# a receipted scene). THIS CYCLE receipts WHAT STATE 1 DOES: the
# dispatch census of the state-1 era, GPU activity, CD/asset requests,
# the stuck-or-advancing question, the uniform-screen pixel values, the
# one abort-131 instance, the lone NULL-trap (30113, latch=0), the
# menupunch family, and the exit-99 chain. The c240 fix is decided by
# these receipts.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C239-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
LOG="run.log"
EXPECT="2ebb361ce5dfa31a738b34a4d59cce4584d86c7281f8a723651616004942fe78"
if [ ! -s "$LOG" ]; then echo "C239-FAILED: run.log missing"; exit 1; fi
SS=$(shasum -a 256 "$LOG" | cut -d" " -f1)
echo "LOG_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: run.log is not the c238 post-run log - refusing a foreign log"; exit 0; fi
echo "BASELINE_VERIFIED (the c238 post-run log)"
P="runlog_preserve_c239_$(date +%Y%m%d_%H%M%S)"
if ! (mkdir -p "$P" && cp -p "$LOG" "$P/run.log"); then echo "C239-FAILED: preserve failed"; exit 1; fi
echo "PRESERVED: $P/run.log sha=$SS"

S1=$(grep -n "active state 1" "$LOG" | head -1 | cut -d: -f1)
ENDL=$(wc -l < "$LOG" | tr -d " ")
echo "state1_start_line=$S1 end_line=$ENDL"

win() { S=$1; [ "$S" -lt 1 ] && S=1; awk -v s="$S" -v e="$2" 'NR>=s&&NR<=e{printf "%d:%s\n",NR,$0}NR>e{exit}' "$LOG"; }

echo "===DISP239=== the state-1 era dispatch census (what runs in state 1)"
if [ -n "$S1" ]; then
  win "$S1" "$ENDL" | grep -o "enter 0x[0-9A-F]*" | sort | uniq -c | sort -rn | head -12
  echo "--- the [slot]/[task] starters:"
  win "$S1" "$ENDL" | grep "slot\] h2 STARTER\|task\] enter" | head -12
fi

echo "===GPU239=== the state-1 era GPU activity"
echo "prims=$(grep -c "gpuprim\]" "$LOG") words=$(grep -c "cwb\]\|gpu_words" "$LOG")"
grep -n "gpuprim\] #1 \|gpuprim\] #2 \|gpuprim\] #3 " "$LOG" | head -3
grep -n "gpuprim" "$LOG" | tail -3

echo "===CD239=== the state-1 era CD/asset requests"
grep -n "READ ISSUED\|file25w\] R754" "$LOG" | tail -8
grep -n "schdd\]" "$LOG" | tail -4
echo "--- the LBA walk of the era:"
grep -o "seek=[0-9]*" "$LOG" | sort | uniq -c | sort -rn | head -10

echo "===STUCK239=== advancing or wedged (the stuck-posture census)"
grep -n "STUCK\|stuck-confirmed\|wedge" "$LOG" | tail -6
grep -n "mvloop\] pre-movie polling" "$LOG" | tail -3
grep -n "wait-loop tick\|R967" "$LOG" | tail -4

echo "===PIX239=== the uniform-screen question (actual pixel values)"
grep -n "asciiart\|vramtopng\|shot_t" "$LOG" | tail -4
python3 - <<'PYEOF'
import os
# sample the live vram dump if present: uniform fill vs structured content
p = "vram_live.bin"
if os.path.exists(p):
    d = open(p, "rb").read()
    if len(d) >= 2048:
        words = [d[i] | (d[i+1] << 8) for i in range(0, 2048, 2)]
        uniq = {}
        for w in words:
            uniq[w] = uniq.get(w, 0) + 1
        top = sorted(uniq.items(), key=lambda kv: -kv[1])[:6]
        print("first-1KB word census (value:count):", top)
        print("distinct words:", len(uniq))
else:
    print("no vram_live.bin present")
PYEOF

echo "===ABRT239=== the one abort-131 instance (full context)"
AB=$(grep -n "abrt\] AbortOnGameFault code=131" "$LOG" | head -1 | cut -d: -f1)
echo "abrt131-line=$AB"
if [ -n "$AB" ]; then win "$((AB-12))" "$((AB+8))" "$LOG" | head -20; fi

echo "===TRAP239=== the lone NULL-trap (30113, latch=0) context"
win 30093 30132 "$LOG" | grep -v "bandhist" | head -22

echo "===PUNCH239=== the menupunch family (game-processed button events)"
grep -n "menupunch\]" "$LOG" | head -8
echo "--- pad receipts of the era:"
grep -n "padrd\|ReadControllerButtons\|padcell" "$LOG" | tail -6

echo "===EXIT239=== the exit-99 chain (last lines before the gasp)"
GR=$(grep -n "rungasp" "$LOG" | head -1 | cut -d: -f1)
if [ -n "$GR" ]; then win "$((GR-30))" "$GR" "$LOG" | grep -v "bandhist\|\[hook\]" | head -26; fi

echo "===C239DONE=== state-1 era census complete - the c240 fix is decided by these receipts"
