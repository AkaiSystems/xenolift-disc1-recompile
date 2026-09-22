#!/bin/bash
# c396_revert.sh - REVERT + READ-ONLY SITE CENSUS. The c395
# verdict: R1370 landed but the serve door never fired (zero
# receipts) while the entry arm admitted the conversion
# block's side machinery into boot-era directory postures -
# the directory walk re-read LBA 2-5 in loops, the GPU
# regressed 15x, and the run ended in a NEW wedge (the CDFS
# settle family at FE1C=0A, last_cmd=0A, trashed CD cells).
# Per the c351 discipline: REVERT, don't widen. THIS PASS:
# (1) restore the pristine R1369 tree from the preserved
# runtime.c.pre and VERIFY the sha; (2) read-only extraction
# of the DATA HANDLER entry site (the R1265/R1268/R1269 door
# family, lines ~3060-3260) - the R1371 system-ring door
# belongs THERE (its own site, no conversion-block entry
# needed). NO run this cycle.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C396-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
PRE_DIR="patch_c395_20260917_163918"
EXPECT_PRE="e918ef8605b0c80533c4aa06356fa0fdb6c034fd9fe9e24517a1d1200d09394a"
echo "===REVERT396=== restoring the pristine R1369 tree"
CUR=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "CUR_SHA=$CUR"
if [ "$CUR" != "$EXPECT_PRE" ]; then
  echo "NOTE: tree is not the R1370 build - checking state"
fi
if [ ! -f "$PRE_DIR/runtime.c.pre" ]; then
  echo "REVERT-FAILED: preserved pre-patch file missing - NOTHING DONE, refusing to guess"
  ls -d patch_c395_* 2>/dev/null || true
  exit 0
fi
PRE_SHA=$(shasum -a 256 "$PRE_DIR/runtime.c.pre" | cut -d" " -f1)
echo "PRESERVED_PRE_SHA=$PRE_SHA"
if [ "$PRE_SHA" != "$EXPECT_PRE" ]; then
  echo "REVERT-FAILED: preserved file is not the R1369 baseline - NOTHING DONE, refusing"
  exit 0
fi
cp -p "$PRE_DIR/runtime.c.pre" "$SRC"
NEW=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "RESTORED_SHA=$NEW"
if [ "$NEW" != "$EXPECT_PRE" ]; then
  echo "REVERT-FAILED: restore did not produce the R1369 baseline - restoring nothing further, reporting"
  exit 0
fi
echo "REVERT-VERIFIED: the tree is the pristine R1369 baseline (the fd-retire era)"
echo "===SITE396=== read-only: the DATA HANDLER door family (R1265/R1268/R1269, lines 3060-3260)"
awk 'NR>=3060 && NR<=3260 { print NR": "$0 }' "$SRC" | grep -v "^\s*$" | head -95
echo "===DHSITE396=== the [bp] DATA HANDLER camera site (where the handler entries print from)"
LG=$(grep -n "DATA HANDLER" "$SRC" | head -3)
echo "$LG"
LG1=$(grep -n "bp\] DATA HANDLER" "$SRC" | head -1 | cut -d: -f1)
if [ -n "$LG1" ]; then
  S=$((LG1-25)); [ $S -lt 1 ] && S=1
  E=$((LG1+15))
  awk -v s="$S" -v e="$E" 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
fi
echo "===FE08CELL396=== the FE08/FE34 read sites in the handler family (the ring math anchors)"
grep -n "0x8004FE08" "$SRC" | head -10
echo "===C396DONE=== revert verified + the DATA HANDLER site is receipted"
