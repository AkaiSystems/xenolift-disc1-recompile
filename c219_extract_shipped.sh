#!/bin/bash
# c219_pause_lifecycle.sh - READ-ONLY extraction. No patch, no compile, no run.
# THE PAUSE-LIFECYCLE DOSSIER: decides the c220 fix from receipts already in
# the preserved c217 log. Questions:
#  (1) the full cmd-09 (PAUSE) lifecycle: every issue + every response;
#  (2) the virtual-INT census: which commands ever got INT3/INT2 deliveries;
#  (3) the zrf0 fire #12 window: posture + where the 2060 bytes landed;
#  (4) the lzss#8 poison-src provenance;
#  (5) the cur/state-install census: was ANY state ever installed;
#  (6) the full t=30s window around the 02->09 transition.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C219-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
echo "===PRE219=== identity gate"
TS=$(shasum -a 256 runtime/runtime.c 2>/dev/null | cut -d" " -f1)
echo "TREE_SHA=$TS"
LOG=""
for c in runlog_preserve_c217_20260917_052223/run.log run.log; do
  if [ -s "$c" ]; then LOG="$c"; break; fi
done
if [ -z "$LOG" ]; then echo "C219-FAILED: no run log found - nothing extracted"; exit 1; fi
LS=$(shasum -a 256 "$LOG" | cut -d" " -f1)
echo "USING_LOG=$LOG"
echo "LOG_SHA=$LS size=$(wc -c < "$LOG" | tr -d " ")"
case "$LS" in
  e1fedb1bdfaa6eb9*) echo "LOG_MATCH=c217-preserved-prefix OK" ;;
  *) echo "LOG_NOTE: sha differs from the c217-preserved prefix - extraction still valid, era noted" ;;
esac
P="runlog_preserve_c219_$(date +%Y%m%d_%H%M%S)"
if ! (mkdir -p "$P" && cp -p "$LOG" "$P/run.log"); then echo "C219-FAILED: preserve copy failed"; exit 1; fi
echo "PRESERVED: $P/run.log sha=$(shasum -a 256 "$P/run.log" | cut -d" " -f1) size=$(wc -c < "$P/run.log" | tr -d " ")"

echo "===CMD09=== every cmd-09 lifecycle receipt"
grep -n "cmd=09\|cmd 0x09\|cmd=0x09\|last_cmd=0x09\|last_cmd=09" "$LOG" | head -80
echo "cmd09_lines=$(grep -c "cmd=09\|cmd 0x09\|cmd=0x09\|last_cmd=0x09\|last_cmd=09" "$LOG")"

echo "===VINT=== the virtual-INT delivery census (all commands)"
grep -n "virtual INT" "$LOG" | head -80
echo "vint_total=$(grep -c "virtual INT" "$LOG")"

echo "===INT2=== the INT2 / pause-completion census"
grep -n "INT2" "$LOG" | head -30
echo "int2_total=$(grep -c "INT2" "$LOG")"

echo "===RSPOP09=== response-pop receipts whose line names 09"
grep -n "rspop" "$LOG" | grep "09" | head -30

echo "===PEND09=== pending receipts whose line names 09"
grep -n "pendclr\|penddossier\|pending INT" "$LOG" | grep "09" | head -30

echo "===ZRF0W=== zrf0 fire #12 window (posture + serve context)"
L=$(grep -n "zrf0" "$LOG" | grep "#12" | head -1 | cut -d: -f1)
echo "zrf0_12_line=$L"
if [ -n "$L" ]; then sed -n "$((L-8)),$((L+16))p" "$LOG"; fi
echo "zrf0_total=$(grep -c "zrf0" "$LOG")"

echo "===FDWALL=== the FDF8 arm-context receipts (who armed which count for which LBA)"
grep -n "fdw" "$LOG" | head -30

echo "===UNPK8=== lzss core #8 poison-src provenance window"
L=$(grep -n "core entry #8" "$LOG" | head -1 | cut -d: -f1)
echo "lzss8_line=$L"
if [ -n "$L" ]; then sed -n "$((L-6)),$((L+14))p" "$LOG"; fi
grep -n "unpack-fix\|DEADFA11" "$LOG" | head -30

echo "===CURHIST=== the cur / idx histograms (was ANY state ever installed)"
grep -o "cur=0x[0-9A-F]*" "$LOG" | sort | uniq -c | sort -rn | head -8
grep -o "cur=[0-9]*" "$LOG" | sort | uniq -c | sort -rn | head -8
grep -o "idx(FAEC)=[0-9A-F]*" "$LOG" | sort | uniq -c | sort -rn | head -8

echo "===CURW=== cur-cell (92C0) receipts, census tags excluded"
grep -n "92C0" "$LOG" | grep -v "kickdue\|pumpcam" | head -40

echo "===T30W=== the t=30s window around the 02->09 transition (full context)"
L=$(grep -n "cell4 02->09" "$LOG" | head -1 | cut -d: -f1)
echo "chg09_line=$L"
if [ -n "$L" ]; then sed -n "$((L-20)),$((L+70))p" "$LOG"; fi

echo "===C219DONE=== read-only extraction complete - the c220 fix is decided by these receipts"
