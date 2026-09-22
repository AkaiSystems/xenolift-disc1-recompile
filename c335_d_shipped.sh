#!/bin/bash
# c335_datapathprobe.sh - READ-ONLY probe (NO patch, NO run):
# the data-serve path and the ReadN-era census.
# THE c334 BREAKTHROUGH: the collector exemption completed the
# first native handshake of the wedge era - response consumed,
# interrupt acknowledged, cmd 02->06 (ReadN) issued, FE1C 1->2.
# The wedge is now the READN SECTOR STREAM WAIT (data=0/0,
# loaded=0, sched=0). Passes 1-2 served this same request
# natively. WHY is the model's data pipeline not feeding pass 3?
# THIS CYCLE: (1) sha gate; (2) the data-serve path from the
# fresh runtime.c (sector-stream entry + gate conditions);
# (3) the c334 witness census of the ReadN era - which
# data-class receipts fired and which stayed silent.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C335-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="6815e73c2282e3ff3385dc700e022ac1526a82e833e70eb7a1851b4f6b49275c"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1355 tree 6815e73c - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1355 tree)"
echo "===DATASERVE335=== the data-serve sites in the fresh runtime.c"
grep -n "cd_data_load\|site=1\|ReadN INT1 arm\|R496" "$SRC" | head -20
echo "===DATASERVECTX=== the sector-stream entry (context)"
G=$(grep -n "cd_data_load" "$SRC" | head -1 | cut -d: -f1)
echo "FIRST_CD_DATA_LOAD_LINE=$G"
if [ -n "$G" ]; then awk -v s="$((G-14))" -v e="$((G+30))" 'NR>=s && NR<=e {print NR": "$0}' "$SRC"; fi
echo "===READN335=== the READ ISSUED -> serve chain (what feeds the stream)"
grep -n "READ ISSUED" "$SRC" | head -6
G2=$(grep -n "READ ISSUED" "$SRC" | head -1 | cut -d: -f1)
if [ -n "$G2" ]; then awk -v s="$((G2-10))" -v e="$((G2+40))" 'NR>=s && NR<=e {print NR": "$0}' "$SRC"; fi
echo "===W335=== the c334 witness ReadN-era census (which data receipts fired after the 02->06?)"
W=$(ls -1d witness_c334_* 2>/dev/null | tail -1)
echo "WITNESS_DIR=$W"
LOG="$W/run.log"; [ -s "$LOG" ] || LOG="$W/run.log.d"
RN=$(grep -n "cmd 02->06" "$LOG" | tail -1 | cut -d: -f1)
echo "READN_LINE=$RN"
echo "--- the 80 lines after the ReadN issue ---"
if [ -n "$RN" ]; then awk -v s="$RN" -v e="$((RN+80))" 'NR>=s && NR<=e {print NR": "$0}' "$LOG"; fi
echo "===TAILCENSUS335=== the tail-era data-class receipt counts"
for TAG in "\[cd\] lost-register kick" "\[bp\]" "fld-int1" "cdw02" "defib" "\[cd\] sector" "\[cd\] data" "rspop" "pendclr"; do
  C=$(awk -v s="$RN" 'NR>=s' "$LOG" 2>/dev/null | grep -c "$TAG")
  echo "TAIL_COUNT[$TAG]=$C"
done
echo "===C335DONE=== probe complete - the data-serve gate conditions name the next fix"
