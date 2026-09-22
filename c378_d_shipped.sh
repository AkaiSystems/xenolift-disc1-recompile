#!/bin/bash
# c378_pauselife.sh - READ-ONLY. NO patch, NO run. The c377
# census: R1366 untested (the run never reached file#14);
# the run wedged at the ARCHIVE-END PAUSE class - ladder
# #2 06->09 PAUSE at seek=239322, #3 09->02 parked FE1C=6,
# both boots, fuse kill (exit 137), zero faults. THIS PASS:
# the wedge window on the R1366 tree - (1) the pause
# lifecycle receipts (actchg, INT2 arm/deliver, R1314/R1317
# sites) between ladder #2 and the fuse; (2) the archive
# sector serve (did the 9048-byte read at 239317 ever
# serve? data=0/2060); (3) the R1314 Pause-INT2 era-gate
# conditions in runtime.c - which postures does the gate
# cover, and why did the archive-end Pause at 239322 fall
# outside it.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C378-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="13bc3bafa00d1cb05ddb1496adb335b94c3a49658a5206c2f4f74bd2d7b6c104"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1366 tree - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1366 tree)"
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
if [ ! -s "$LOG" ]; then echo "TREE-ROOT-LOG-MISSING"; exit 0; fi
echo "AUTHORITATIVE LOG = $LOG ($(wc -l < "$LOG" | tr -d ' ') lines)"
echo "===WEDGEWIN378=== boot-1 wedge window: the 80 lines from ladder #2 (line 8266)"
awk 'NR>=8266 && NR<=8346 { print NR": "$0 }' "$LOG"
echo "===PAUSELIFE378=== the pause-lifecycle receipts (arm, INT2, actchg, retire) - whole log"
grep -n "actchg\|pause.*INT2\|INT2.*pause\|R1314\|R1317\|pause-retire\|pause2" "$LOG" | head -20
echo "===ARCHSERVE378=== the archive read serve (239317-239322 sector story)"
grep -n "LBA 23931[789]\|LBA 23932[012]" "$LOG" | head -14
grep -n "FDF8=9048" "$LOG" | head -10
echo "===DATALOAD378=== the FIFO/data-handler receipts in the wedge window"
grep -n "data FIFO\|data_load\|DATA HANDLER\|mv-conv" "$LOG" | awk -F: '$1>=8200 && $1<=9000' | head -12
echo "===ERAGATE378=== the R1314 Pause-INT2 era-gate conditions (the runtime.c sites)"
grep -n "R1314\|pause_int2\|INT2 complete\|terminal INT2" "$SRC" | head -14
LG=$(grep -n "R1314" "$SRC" | head -1 | cut -d: -f1)
if [ -n "$LG" ]; then
  S=$((LG-20)); [ $S -lt 1 ] && S=1
  E=$((LG+40))
  echo "--- gate block at line $LG (+-20/+40) ---"
  awk -v s="$S" -v e="$E" 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
fi
echo "===GETSTAT378=== the drive's GetStat answers in the wedge window (the re-prime story)"
grep -n "reprime\|GetStat\|cmd 01" "$LOG" | awk -F: '$1>=8266 && $1<=11052' | head -12
echo "===PARK378=== the park/fd receipts in the wedge window"
grep -n "park\]\|fd-retire\|f18\|schdd" "$LOG" | awk -F: '$1>=8266 && $1<=11052' | head -14
echo "===C378DONE=== the pause-wedge story is extracted"
