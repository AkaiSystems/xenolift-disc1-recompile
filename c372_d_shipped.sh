#!/bin/bash
# c372_gatewin.sh - READ-ONLY. NO patch, NO run. The c371
# receipts decoded the runaway: the guest decoder uses
# word0 (src[0:4]) as the terminus; with the payload-only
# buffer the terminus wraps BACKWARD (80069720) and the
# decode runs away. The HLE path exists (16722) but its
# gate declined (no lzss-hle receipt). THIS PASS: the three
# missing windows - the HLE gate condition (16680-16730),
# the R1320 file-14 guest-pass exit body, and the
# xenolift_lzss_hle definition (4840-4960) for the
# src-layout semantics.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C372-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="8d14ab4f2385a0004c28bd5a07bc762c5b9407b6da8a817d96554d5e91f226b0"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1365 tree - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1365 tree)"
echo "===GATEWIN372=== the HLE gate condition (16680-16732)"
awk 'NR>=16680 && NR<=16732 { print NR": "$0 }' "$SRC"
echo "===R1320WIN372=== the R1320 file-14 guest-pass exit body (16729-16800)"
awk 'NR>=16733 && NR<=16800 { print NR": "$0 }' "$SRC"
echo "===HLEDEF372=== xenolift_lzss_hle definition (4846-4960)"
awk 'NR>=4846 && NR<=4960 { print NR": "$0 }' "$SRC"
echo "===ZERO372=== the fake-zero one-shot site (16960-16985)"
awk 'NR>=16960 && NR<=16985 { print NR": "$0 }' "$SRC"
echo "===C372DONE=== the gate + exit + decoder semantics are extracted"
