#!/bin/bash
# c381_fe34site.sh - READ-ONLY. NO patch, NO run. The c380
# anatomy: the R554 fe34fix MISFIRE armed FDF8=11644 as a
# 'file-14 backlog' (offset 113660, 113660+11644=125304 =
# file#14's size exactly) on the ARCHIVE request (9048B at
# 239317, already DRAINED to FDF8=0) - no file-14 read was
# ever issued this run. The kernel then believes it owes
# 11644, no ReadN forms, and the game's getsector data-wait
# spins to the fuse. THIS PASS: the fe34fix R554 site + its
# file-14 ledger computation + the [req] FDF8 arm camera +
# the R889 owes logic - the exact code for the R1367
# identity-check fix.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C381-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="13bc3bafa00d1cb05ddb1496adb335b94c3a49658a5206c2f4f74bd2d7b6c104"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1366 tree - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1366 tree)"
echo "===FE34REFS381=== every fe34fix/R554 reference"
grep -n "fe34fix\|R554" "$SRC" | head -20
echo "===FE34BLOCK381=== the fe34fix site block (+-50 around the restore print)"
LG=$(grep -n "fdf8-restored" "$SRC" | head -1 | cut -d: -f1)
echo "restore print at line $LG"
if [ -n "$LG" ]; then
  S=$((LG-50)); [ $S -lt 1 ] && S=1
  E=$((LG+50))
  awk -v s="$S" -v e="$E" 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
fi
echo "===LEDGER381=== the file-14 ledger state (where offset/remaining come from)"
grep -n "r554_\|fe34_\|backlog\|remaining" "$SRC" | head -20
echo "===REQARM381=== the [req] FDF8 arm camera site"
LG2=$(grep -n "\[req\] FDF8" "$SRC" | head -1 | cut -d: -f1)
echo "[req] camera at line $LG2"
if [ -n "$LG2" ]; then
  S=$((LG2-25)); [ $S -lt 1 ] && S=1
  E=$((LG2+25))
  awk -v s="$S" -v e="$E" 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
fi
echo "===MVDOOR381=== the R889 owes computation"
LG3=$(grep -n "owes=" "$SRC" | head -1 | cut -d: -f1)
echo "owes print at line $LG3"
if [ -n "$LG3" ]; then
  S=$((LG3-40)); [ $S -lt 1 ] && S=1
  E=$((LG3+20))
  awk -v s="$S" -v e="$E" 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
fi
echo "===FILECB381=== the R603 FILE-CB camera (the request context cells)"
LG4=$(grep -n "R603 entry FILE-CB" "$SRC" | head -1 | cut -d: -f1)
echo "R603 camera at line $LG4"
if [ -n "$LG4" ]; then
  S=$((LG4-15)); [ $S -lt 1 ] && S=1
  E=$((LG4+15))
  awk -v s="$S" -v e="$E" 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
fi
echo "===C381DONE=== the fe34fix site is extracted"
