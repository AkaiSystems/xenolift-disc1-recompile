#!/bin/bash
# c229_reentry_trigger.sh - READ-ONLY: no patch, no compile, no run.
# The c228 receipts closed the consumption question: the menu module is
# READ (FDF8 countdown, sector-by-sector) and UNPACKED FROM REAL DATA
# (lzss-hle src=801DD680 expanded=260862, both eras; computed_exit
# 0x800AF5EE lands at the gdesc[1] region). cur=1 set at mount. The
# remaining fault: a FAST BOOT-RETRY LOOP - unpack -> gtab-init -> boot
# re-entry (fn 80019524) without dispatching the coordinator, zero
# aborts. The re-entry trigger lives in the ~160 raw lines between
# unpack-complete and re-entry that no digest section printed. This
# extraction prints those windows VERBATIM plus the validation census.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C229-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
LOG="run.log"
EXPECT="fef3377465773175d5da73910926f0902cd7fde8ce421271874d98f406f43685"
if [ ! -s "$LOG" ]; then echo "C229-FAILED: run.log missing"; exit 1; fi
SS=$(shasum -a 256 "$LOG" | cut -d" " -f1)
echo "LOG_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: run.log is not the c227 post-run log - refusing a foreign log"; exit 0; fi
echo "BASELINE_VERIFIED"
P="runlog_preserve_c229_$(date +%Y%m%d_%H%M%S)"
if ! (mkdir -p "$P" && cp -p "$LOG" "$P/run.log"); then echo "C229-FAILED: preserve failed"; exit 1; fi
echo "PRESERVED: $P/run.log sha=$SS"

win() { S=$1; [ "$S" -lt 1 ] && S=1; awk -v s="$S" -v e="$2" 'NR>=s&&NR<=e{printf "%d:%s\n",NR,$0}NR>e{exit}' "$LOG"; }
rng() { awk -v s="$1" -v e="$2" 'NR>=s&&NR<=e{printf "%d:%s\n",NR,$0}NR>e{exit}' "$LOG" | grep "$3" | head -"$4"; }

echo "===RAW1_229=== era-1 post-unpack window VERBATIM (14740-14970)"
win 14740 14970

echo "===RAW2_229=== era-2 post-unpack window VERBATIM (19360-19570)"
win 19360 19570

echo "===VALID229=== the validation receipts"
grep -n "validat\|Module-6\|checksu\|\bcrc\b\|CRC" "$LOG" | head -20

echo "===MENU1_229=== the menu/coordinator dispatch receipts, era 1 (11400-15000)"
rng 11400 15000 "menuchain\|KernelMenu\|minput\|80077E88\|DISPATCHER" 24

echo "===MENU2_229=== the menu/coordinator dispatch receipts, era 2 (16000-19600)"
rng 16000 19600 "menuchain\|KernelMenu\|minput\|80077E88\|DISPATCHER" 24

echo "===BOOTC229=== the fn_80019ACC dispatch census (mode args + callers)"
echo "count=$(grep -c "\[boot\] fn_80019ACC" "$LOG")"
grep -n "\[boot\] fn_80019ACC" "$LOG" | head -24

echo "===SUM229=== summary counts"
echo "unpacks_from_dd680=$(grep -c "lzss-hle] src=0x801DD680" "$LOG")"
echo "bootinit_clears_19524=$(grep -c "fn 0x80019524" "$LOG")"
echo "latch_arms_19A2C=$(grep -c "fn 0x80019A2C" "$LOG")"
echo "latch_clears_19A90=$(grep -c "fn 0x80019A90" "$LOG")"
echo "statetbl tail:"
grep -n "statetbl" "$LOG" | tail -6
echo "===C229DONE=== re-entry extraction complete - the c230 fix is decided by these receipts"
