#!/bin/bash
# c436_discardbody.sh - READ-ONLY CENSUS. NO run, NO
# patch. The c435 receipts caught the LBA-9 killer:
# our own spin-discard fired at 31912 on a LIVE
# request (FDF8=2048 bytes owed, sector loaded
# seconds before, INT1 armed+acked+re-asserted) -
# the R1265-era discard was built for COMPLETED
# requests and lacks the FDF8==0 guard the zrfB
# family has. The fix (R1379) is a one-term FDF8==0
# guard - but the patch must anchor on the TRUE
# discard condition, not an inferred one. THIS PASS:
# (1) the spin-discard body (exact condition terms);
# (2) the wait-loop tick loader (what loads the
# sector + what it arms); (3) the fd-tick converter;
# (4) the defib5 stacked-pending drain; (5) the R1376
# ownership-gate context (the stranded cmd-0x13
# answer). Receipts only - the patch follows from
# these only.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C436-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="6c916b3fc08cc29c92247a12aaea6cd4f294e9c395164490e737ab690b782737"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1378 tree - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1378 tree)"
echo "===DISCARD436=== the spin-discard body (exact condition terms)"
grep -n -e "spin-discard" "$SRC" | head -4
LN=$(grep -n -e "spin-discard" "$SRC" | head -1 | cut -d: -f1)
if [ -n "$LN" ]; then
  echo "--- context ($((LN-38))..$((LN+12)):"
  awk -v s=$((LN-38)) -v e=$((LN+12)) 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
fi
echo "===WLLOAD436=== the wait-loop tick loader"
grep -n -e "loaded into data FIFO" "$SRC" | head -4
LN=$(grep -n -e "loaded into data FIFO" "$SRC" | head -1 | cut -d: -f1)
if [ -n "$LN" ]; then
  echo "--- context ($((LN-20))..$((LN+16)):"
  awk -v s=$((LN-20)) -v e=$((LN+16)) 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
fi
echo "===FDTICK436=== the fd-tick converter"
grep -n -e "fd-tick" "$SRC" | head -3
LN=$(grep -n -e "fd-tick" "$SRC" | head -1 | cut -d: -f1)
if [ -n "$LN" ]; then
  echo "--- context ($((LN-14))..$((LN+14)):"
  awk -v s=$((LN-14)) -v e=$((LN+14)) 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
fi
echo "===DEFIB436=== the defib5 stacked-pending drain"
grep -n -e "stacked-pending" "$SRC" | head -4
LN=$(grep -n -e "stacked-pending" "$SRC" | head -1 | cut -d: -f1)
if [ -n "$LN" ]; then
  echo "--- context ($((LN-12))..$((LN+12)):"
  awk -v s=$((LN-12)) -v e=$((LN+12)) 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
fi
echo "===OWNERSHIP436=== the R1376 ownership gate (the stranded cmd-0x13 answer)"
grep -n -e "ownership gate" "$SRC" | head -4
LN=$(grep -n -e "ownership gate" "$SRC" | head -1 | cut -d: -f1)
if [ -n "$LN" ]; then
  echo "--- context ($((LN-16))..$((LN+10)):"
  awk -v s=$((LN-16)) -v e=$((LN+10)) 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
fi
echo "===C436DONE=== the discard's true terms are receipted - R1379 anchors on these only"
