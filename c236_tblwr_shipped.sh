#!/bin/bash
# c236_who_writes_the_table.sh - READ-ONLY: no patch, no compile, no run.
# The c235 receipts: the unpack era is CLEAN (R1320 exits held; the member-14
# passes exited on the zeroed header, arms receipt word0=0), and the state-1
# entry chain ran its deepest ever (RESTART STEP idx=1 cur=1 -> POST-RESTORE
# -> table-install ptr=800C4270 -> MoveHeapAllocation(800C4270, 0x8000) ->
# ReleaseAllHeapBlocks). The era dies ONE STEP LATER in the c80/c217b
# null-base heap family: the table at 800C4270 is ALL ZEROS at entry, the
# walker reads FFFFFFFC/FFFFFFF8 (cursor=-8 shape), loops 524K+ NULL-traps
# (caller 0x8003227C, latch=1), converts at 1M ops -> crash-kit recovery ->
# boot re-entry, twice identically. THE QUESTION: who SHOULD write the
# 800C4270 table, and why did they never run? This cycle receipts the
# answer: every 800C4270 mention in the log, the restore-chain window, and
# the STATIC side - the table-install camera site, the walker code, every
# runtime.c reference to 800C4270, the sound-heap head 80059410 and the
# c80 heap 80077458 for writer/reader contrast. No fix ships until the
# missing writer is named by receipts (Jos c80 rule: no speculative
# seeding).
set -u
cd "$HOME/Downloads/xenolift" || { echo "C236-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
LOG="run.log"
SRC="runtime/runtime.c"
EXPECT="20f1921a930682f788d782064d8be19e9232871f14bc9ffbc0de782859327d27"
if [ ! -s "$LOG" ]; then echo "C236-FAILED: run.log missing"; exit 1; fi
SS=$(shasum -a 256 "$LOG" | cut -d" " -f1)
echo "LOG_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: run.log is not the c234/c235-preserved log - refusing a foreign log"; exit 0; fi
echo "BASELINE_VERIFIED (the c234 post-run log)"
if [ ! -s "$SRC" ]; then echo "C236-FAILED: runtime/runtime.c missing"; exit 1; fi
echo "SRC_SHA=$(shasum -a 256 "$SRC" | cut -d" " -f1)"
P="runlog_preserve_c236_$(date +%Y%m%d_%H%M%S)"
if ! (mkdir -p "$P" && cp -p "$LOG" "$P/run.log"); then echo "C236-FAILED: preserve failed"; exit 1; fi
echo "PRESERVED: $P/run.log sha=$SS"

echo "===TBL236=== every 800C4270 mention in the log (writers or none?)"
grep -n "800C4270" "$LOG" | head -20
echo "mention_count=$(grep -c "800C4270" "$LOG")"

echo "===RESTORE236=== the state-1 restore chain window (first RESTART STEP, filtered)"
RS=$(grep -n "RESTART STEP" "$LOG" | head -1 | cut -d: -f1)
echo "restart-step-line=$RS"
if [ -n "$RS" ]; then
  S=$((RS-20)); [ "$S" -lt 1 ] && S=1
  awk -v s="$S" -v e=$((RS+45)) 'NR>=s&&NR<=e{printf "%d:%s\n",NR,$0}NR>e{exit}' "$LOG" | grep -v "bandhist\|\[hook\]\|lzss-guard-r" | head -40
fi

echo "===TRAPS236=== the NULL-trap caller census (one family or several?)"
grep -o "NULL-trap #[0-9]* caller 0x[0-9A-F]* latch 0x[0-9A-F]*" "$LOG" | sed "s/#[0-9]*/#N/" | sort | uniq -c | sort -rn | head -6

echo "===STATIC-TBL236=== the table-install camera site in the translated C"
TI=$(grep -n "table-install" "$SRC" | head -1 | cut -d: -f1)
echo "table-install-line=$TI"
if [ -n "$TI" ]; then
  S=$((TI-60)); [ "$S" -lt 1 ] && S=1
  sed -n "${S},$((TI+10))p" "$SRC" | grep -n "800C4270\|0x800C42\|arena\|install" | head -12
  echo "--- the full install function region:"
  sed -n "${S},$((TI+30))p" "$SRC" | head -70
fi

echo "===STATIC-REF236=== every static reference to the table + neighbor addresses"
grep -n "800C4270\|800C426C\|800C4A70" "$SRC" | head -20
echo "static_ref_count=$(grep -c "800C4270" "$SRC")"

echo "===STATIC-WALK236=== the heap walker (NULL-trap caller 0x8003227C region)"
WK=$(grep -n "0x8003227C\|8003227C" "$SRC" | head -1 | cut -d: -f1)
echo "walker-line=$WK"
if [ -n "$WK" ]; then
  S=$((WK-40)); [ "$S" -lt 1 ] && S=1
  sed -n "${S},$((WK+60))p" "$SRC" | head -80
fi

echo "===STATIC-HEAP236=== the sound-heap head + the c80 heap (writer/reader contrast)"
grep -n "80059410" "$SRC" | head -8
echo "soundheap_ref_count=$(grep -c "80059410" "$SRC")"
grep -n "80077458" "$SRC" | head -8
echo "c80heap_ref_count=$(grep -c "80077458" "$SRC")"

echo "===BANK236=== the bank-write sites (800C4A70 <- 84000000 writer_fn=800320E8)"
grep -n "800C4A70" "$LOG" | head -6
BW=$(grep -n "0x800C4A70\|800C4A70" "$SRC" | head -1 | cut -d: -f1)
echo "bank-static-line=$BW"
echo "===C236DONE=== attribution extraction complete - the c237 fix targets the MISSING WRITER these receipts name"
