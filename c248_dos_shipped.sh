#!/bin/bash
# c248_health_dossier.sh - READ-ONLY: no patch, no compile, no run.
# THE c247 VERDICT: the R1324 gate landed (PASS) and the run is the
# HEALTHIEST SINCE c238 - the module string-walk GONE (fhelp=0
# wildctx=0 vtcell=5), traps=1 (was 564), no crash-kit conversion, the
# SCREEN HAS STRUCTURE (regions C/D 3840 nz, stride4 nz=84992, 6 blits,
# asciiart fired), state-1 CB ENTER x3 at t=11s, state 1 active then a
# transition BACK to state 0, one abort-131 (latch=0), exit 99 via the
# kit door. THIS CYCLE receipts the FIRST-FAULT DOSSIER of the healthy
# trajectory: (1) the abort-131 arena+caller, (2) the exit-99 trigger
# chain (the last faults before the kit door), (3) the state 1->0
# transition window (reboot or designed teardown?), (4) the state-1 CB
# story (cur=0 req=0 FE1C=6 - what the callback did), (5) the screen
# content (what regions C/D hold - the asciiart + snap receipts), (6)
# the kernel skiphook cells (targets 0/0x00801021/0x001423B6 at
# 8004B748/80040B84 + the svcguard 80068934 receipt), (7) the
# promote-block placement (why no stage2: echo fired this cycle). The
# c249 fix is decided by these receipts.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C248-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
LOG="run.log"
EXPECT="8d9b5551c32fae561a2bf110fb9a8141d3cbb98302339097aa83abca89f60367"
if [ ! -s "$LOG" ]; then echo "C248-FAILED: run.log missing"; exit 1; fi
SS=$(shasum -a 256 "$LOG" | cut -d" " -f1)
echo "LOG_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: run.log is not the c247 post-run log"; exit 0; fi
echo "BASELINE_VERIFIED"
P="dossier_c248_$(date +%Y%m%d_%H%M%S)"
if ! (mkdir -p "$P" && cp -p "$LOG" "$P/run.log"); then echo "C248-FAILED: preserve failed"; exit 1; fi
echo "PRESERVED: $P/run.log sha=$SS"

echo "===ABRT248=== the abort-131 (which arena, which caller)"
AN=$(grep -n "code=131" "$LOG" | head -1 | cut -d: -f1)
echo "abort131_line=$AN"
if [ -n "$AN" ]; then
  S=$((AN-20)); [ "$S" -lt 1 ] && S=1
  awk -v s="$S" -v e="$((AN+6))" 'NR>=s&&NR<=e{printf "%d:%s\n",NR,$0}NR>e{exit}' "$LOG" | grep -v "bandhist\|\[hook\]\|pumpcam\|\[spu\]" | head -18
fi
echo "--- the lone NULL-trap + its walk:"
TN=$(grep -n "NULL-trap #" "$LOG" | head -1 | cut -d: -f1)
echo "trap_line=$TN"
if [ -n "$TN" ]; then
  S=$((TN-14)); [ "$S" -lt 1 ] && S=1
  awk -v s="$S" -v e="$((TN+4))" 'NR>=s&&NR<=e{printf "%d:%s\n",NR,$0}NR>e{exit}' "$LOG" | grep -v "bandhist\|\[hook\]\|pumpcam" | head -14
fi

echo "===EXIT248=== the exit-99 trigger chain (the last faults before the kit door)"
GR=$(grep -n "rungasp" "$LOG" | head -1 | cut -d: -f1)
if [ -n "$GR" ]; then
  S=$((GR-40)); [ "$S" -lt 1 ] && S=1
  awk -v s="$S" -v e="$((GR+2))" 'NR>=s&&NR<=e{printf "%d:%s\n",NR,$0}NR>e{exit}' "$LOG" | grep -v "bandhist\|\[hook\]\|pumpcam\|\[spu\]\|mvloop" | head -26
fi
echo "--- the kit/exitdiag door receipts:"
grep -n "kit\|exitdiag" "$LOG" | grep -v "crash-kit recovery (R926" | head -8

echo "===TRANS248=== the state 1 -> 0 transition window (reboot or teardown?)"
grep -n "active state 1\|active state 0" "$LOG" | head -8
T1=$(grep -n "active state 1" "$LOG" | head -1 | cut -d: -f1)
T0=$(grep -n "active state 0" "$LOG" | awk -F: -v t="$T1" '$1>t' | head -1 | cut -d: -f1)
echo "state1_line=$T1 back_to_state0_line=$T0"
if [ -n "$T0" ]; then
  S=$((T0-24)); [ "$S" -lt 1 ] && S=1
  awk -v s="$S" -v e="$((T0+4))" 'NR>=s&&NR<=e{printf "%d:%s\n",NR,$0}NR>e{exit}' "$LOG" | grep -v "bandhist\|\[hook\]\|pumpcam\|\[spu\]\|mvloop" | head -18
fi

echo "===CB248=== the state-1 CB story (what did the callback do?)"
grep -n "STATE-1 CB ENTER" "$LOG" | head -6
C1=$(grep -n "STATE-1 CB ENTER" "$LOG" | head -1 | cut -d: -f1)
if [ -n "$C1" ]; then
  S=$((C1-8)); [ "$S" -lt 1 ] && S=1
  awk -v s="$S" -v e="$((C1+18))" 'NR>=s&&NR<=e{printf "%d:%s\n",NR,$0}NR>e{exit}' "$LOG" | grep -v "bandhist\|\[hook\]\|pumpcam\|\[spu\]" | head -18
fi

echo "===SCREEN248=== the screen content (what regions C/D hold)"
grep -n "asciiart" "$LOG" | head -3
grep -n "\[screen\] R693\|\[screen\] R736\|\[screen\] R695" "$LOG" | tail -8
grep -n "screen.png" "$LOG" | tail -3
python3 - <<'PYEOF'
import os
best = None
for cand in ("screen.png", "screen_snap.png", "shot_final.png"):
    if os.path.exists(cand):
        sz = os.path.getsize(cand)
        print("%s: %d bytes" % (cand, sz))
        if best is None or sz > best[1]:
            best = (cand, sz)
if best:
    with open(best[0], "rb") as f:
        d = f.read()
    # PNG dims from IHDR
    if d[:8] == b"\x89PNG\r\n\x1a\n" and len(d) > 24:
        import struct
        w, h = struct.unpack(">II", d[16:24])
        print("png: %dx%d" % (w, h))
# vram census if present
for v in ("vram_live.bin", "vram.bin"):
    if os.path.exists(v):
        d = open(v, "rb").read()
        if len(d) >= 2048:
            nz = sum(1 for i in range(0, min(len(d), 131072), 2) if d[i] or d[i+1])
            print("%s: %d bytes, nonzero words in first 64K samples: %d" % (v, len(d), nz))
        break
else:
    print("no vram dump present")
PYEOF

echo "===KSKIP248=== the kernel skiphook cells + svcguard"
grep -n "skiphook\]\|svcguard\]" "$LOG" | head -10
echo "--- the faultregs family:"
grep -c "faultregs" "$LOG"
grep -n "faultregs" "$LOG" | head -4

echo "===PROMOBLOCK248=== why no promotion echo this cycle (the block placement)"
grep -n "R704: promote" run.sh | head -2
PB=$(grep -n "R704: promote" run.sh | head -1 | cut -d: -f1)
if [ -n "$PB" ]; then
  S=$((PB-14)); [ "$S" -lt 1 ] && S=1
  sed -n "${S},$((PB+4))p" run.sh
fi

echo "===C248DONE=== first-fault dossier complete - the c249 fix is decided by these receipts"
