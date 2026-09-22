#!/bin/bash
# c357_reextract.sh - READ-ONLY re-extraction with the printer
# FIXED (the c356 awk printf ate the line content). NO patch, NO
# run. Goal: the verbatim stale-vs-serve discriminator of the
# R1347 watcher - lines 12740-12860 (the branch region around
# the stale-discard print at 12804 and the wserve print at
# 12820), the stalecd-near site at 3237, and every r1346_armed
# occurrence with context.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C357-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="ea90a9a404cdb7666eb50af50d92f38c14684bee9feb350291283d9704fc82c5"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1362 tree - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1362 tree)"
echo "===WATCHER357=== the watcher branch region 12740-12860 (the discriminator)"
awk 'NR>=12740 && NR<=12860 { print NR": "$0 }' "$SRC"
echo "===STALENEAR357=== the stalecd-near site 3200-3270"
awk 'NR>=3200 && NR<=3270 { print NR": "$0 }' "$SRC"
echo "===ARMED357=== every r1346_armed occurrence with context"
grep -n -B8 -A8 "r1346_armed" "$SRC"
echo "===STALEALL357=== every stalecd mention with context"
grep -n -B4 -A4 "stalecd" "$SRC"
echo "===C357DONE=== the discriminator is extracted verbatim"
