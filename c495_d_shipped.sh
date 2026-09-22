#!/bin/bash
# c495_patch.sh - THE CAMERA RELOCATION (the c494 census
# receipts applied). The TRUE dispatch site is
# xenolift_trace(uint32_t a): `xenolift_cur_fn = a;` is
# the only functional write (line 1010 comment: written
# ONLY by xenolift_trace) and BOTH receipted overlay
# cameras ([mod6], [ovlcb]) live inside it. The c493
# splice landed on a kick-return register-restore site
# (sv_fn) that never executes for window dispatches -
# hence zero idchk receipts including no arm. THIS PATCH:
# (1) REMOVE the misplaced sv_fn call; (2) ADD
# `r1392_check(a);` immediately after `xenolift_cur_fn =
# a;` in xenolift_trace (gated on exactly ONE such
# line); (3) hard-gated unpiped syntax check; (4) build +
# the 190s verdict run + digest. The R1392 camera logic
# itself is UNCHANGED (cameras only). Fail-closed, tee'd
# to /tmp/c495_receipts.txt. Pure-ASCII output.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C495-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c495_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="40f0659d5039304fcb339df327a09327deecbc7c082e2ab8055d64e7bd43955e"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the c493 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the c493 tree carrying R1392 at the wrong site)"
OLD=$(grep -c -e "r1392_check((unsigned int)(sv_fn));" "$SRC" | tr -d " ")
echo "misplaced sv_fn calls found: $OLD"
if [ "$OLD" != "1" ]; then echo "VALID-FAILED: expected exactly 1 misplaced call - refusing"; exit 0; fi
NEWHITS=$(grep -c -e "xenolift_cur_fn = a;" "$SRC" | tr -d " ")
echo "trace-setter hits: $NEWHITS"
if [ "$NEWHITS" != "1" ]; then echo "VALID-FAILED: expected exactly 1 trace setter - refusing"; exit 0; fi
cp -p "$SRC" "$SRC.pre_c495"
echo "===RELOCATE495=== remove the misplaced call + splice at the TRUE site"
grep -v -e "    r1392_check((unsigned int)(sv_fn));" "$SRC" > /tmp/rt_r1.c
AFTER=$(grep -c -e "r1392_check((unsigned int)(sv_fn));" /tmp/rt_r1.c | tr -d " ")
echo "after removal: $AFTER (expect 0)"
if [ "$AFTER" != "0" ]; then echo "VALID-FAILED: removal failed - RESTORING"; cp -p "$SRC.pre_c495" "$SRC"; exit 0; fi
TL=$(grep -n -e "xenolift_cur_fn = a;" /tmp/rt_r1.c | head -1 | cut -d: -f1)
echo "trace setter at line $TL in the stage-1 file"
awk -v L="$TL" 'NR==L {print; print "    r1392_check(a);"; next} {print}' /tmp/rt_r1.c > /tmp/rt_r2.c
mv /tmp/rt_r2.c "$SRC"
echo "===GATES495==="
G_SV=$(grep -c -e "r1392_check((unsigned int)(sv_fn));" "$SRC" | tr -d " ")
G_NEW=$(grep -c -e "r1392_check(a);" "$SRC" | tr -d " ")
G_TOT=$(grep -c -e "r1392_check" "$SRC" | tr -d " ")
echo "sv_fn calls: expect 0 got $G_SV"
echo "trace calls: expect 1 got $G_NEW"
echo "total r1392_check refs: expect 3 got $G_TOT"
if [ "$G_SV" != "0" ] || [ "$G_NEW" != "1" ] || [ "$G_TOT" != "3" ]; then
  echo "VALID-FAILED: gate mismatch - RESTORING the pre-c495 tree"
  cp -p "$SRC.pre_c495" "$SRC"
  exit 0
fi
echo "GATES OK - the check now sits at the true dispatch site"
NEW=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_TREE_SHA=$NEW"
echo "===SYNCHK495=== HARD GATE syntax check (unpiped rc)"
cc -fsyntax-only "$SRC" > /tmp/c495_syn.txt 2>&1
SYN_RC=$?
head -8 /tmp/c495_syn.txt
echo "SYNCHK_RC=$SYN_RC"
if [ "$SYN_RC" != "0" ]; then
  echo "VALID-FAILED: the patched tree does not parse - RESTORING the pre-c495 tree"
  cp -p "$SRC.pre_c495" "$SRC"
  exit 0
fi
echo "SYNCHK OK"
echo "===RUN495=== build + the 190s verdict run"
export RUN_BUDGET_S=190
bash run.sh 2>&1 | tail -30
echo "RUN_RC=$?"
echo "===DIGEST495==="
LOG="run.log"
if [ ! -s "$LOG" ]; then LOG="run.log.d"; fi
echo "--- the [idchk] receipts (the identity camera at the TRUE site):"
grep -c -e "idchk" "$LOG" | tr -d " " | sed "s/^/idchk count: /"
grep -n -e "idchk" "$LOG" | head -30
echo "--- the standard ladder:"
grep -n -e "MODULE 6 ENTRY" "$LOG" | tail -3
grep -n -e "wildctx" "$LOG" | head -3
grep -n -e "fvp" "$LOG" | tail -3
echo "--- death receipts:"
grep -n -e "rungasp" "$LOG" | tail -2
echo "--- tree sha at run time:"
shasum -a 256 "$SRC" | cut -d" " -f1
echo "===C495DONE=== the identity receipts at the true site are in - PASS/REVERT from the digest - digest is pure ASCII"
