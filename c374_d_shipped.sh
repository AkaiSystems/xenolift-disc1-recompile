#!/bin/bash
# c374_carrywin.sh - READ-ONLY. NO patch, NO run. The c373
# reference decode settled the fix: the unpack buffer must
# hold the WHOLE MEMBER (header at dest, word0=0003FAFE,
# stream from +4), scoped to the file#14 class. THIS PASS:
# the last unextracted window of the defib6 carry - lines
# 15346-15430 (the rem/src/doff init, the R495 full-re-shelve
# branch, the dest guard, the copy loop) - so R1366 ships
# with exact anchors. Also: the s_ovl_size / r490_map_lookup
# tables for cmap==14 identity, and any other writer that
# touches cdest==0x801DD680.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C374-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="8d14ab4f2385a0004c28bd5a07bc762c5b9407b6da8a817d96554d5e91f226b0"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1365 tree - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1365 tree)"
echo "===CARRYWIN374=== the defib6 carry setup + R495 branch + guard + loop (15346-15430)"
awk 'NR>=15346 && NR<=15430 { print NR": "$0 }' "$SRC"
echo "===MAP374=== the r490_map_lookup + s_ovl_size tables (the cmap identity)"
grep -n "r490_map_lookup\|s_ovl_size\|s_ovl_lba" "$SRC" | head -12
echo "===MAPDEF374=== the map table definition block"
LM=$(grep -n "static.*s_ovl_size\|s_ovl_size\[" "$SRC" | head -1 | cut -d: -f1)
if [ -n "$LM" ]; then
  S=$((LM-14)); [ $S -lt 1 ] && S=1
  E=$((LM+26))
  awk -v s="$S" -v e="$E" 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
fi
echo "===DESTW374=== other writers of the 801DD680 dest"
grep -n "0x801DD680\|801DD680u" "$SRC" | head -10
echo "===C374DONE=== the carry anchors are extracted"
