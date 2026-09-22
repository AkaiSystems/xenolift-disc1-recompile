#!/bin/bash
# c430_drdoor.sh - PATCH CYCLE. R1378: THE GENERAL
# DATA-READY DOOR. The c429 receipts: the 803-idx1
# poll returns cd_pending (line 3952), so the
# kernel's own getintr consumes the flag with NO
# forged dispatch (R1179-clean) - but the movie-band
# park (cmdtl #37-38: cmd 09/01->02, seek=109166,
# FE1C=1, data=0/2060, pend=0, sched=0, arm1=0) is
# UNCOVERED by every existing arm gate (R96/R408 need
# cmd 06/09; R453 needs sched==1 - already delivered;
# R113 needs FE1C=5). The fix: arm the data-ready INT1
# when a sector is buffered under an active read with
# bytes owed + nothing pending + the normal ack-pair
# path not in progress + no response about to deliver
# + the R96 4096-poll persistence threshold (healthy
# flows never reach it). Response FIFO primed exactly
# like the proven ack-pair arm. NO era/cmd/size gates
# - the per-posture arm class (R408/R453/R1220)
# retires. Sandbox-verified: replica parses
# (gcc -fsyntax-only -Wall), marker counts from the
# artifact: R1378=2, r1378_door_polls=3,
# r1378_fires=3, [drdoor]=1, stamp-site-8=1, anchor=1.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C430-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="6759e34359fdf33df2e78cfaf2c144194da718412f3d42cb022b12e87470a8bb"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1377 tree - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1377 tree)"
echo "===FETCH430=== fetch the R1378 patch block - sha-gated, 3 attempts"
RC=1; S=none; N=0
while [ $N -lt 3 ]; do
  curl -sSL -m 60 -o /tmp/r1378.blk "https://base44.app/api/apps/6aa26c7ce0ac9a5ee05d2b95/files/mp/public/6aa26c7ce0ac9a5ee05d2b95/548d7aaa2_r1378_drdoor.block"
  RC=$?
  S=$(shasum -a 256 /tmp/r1378.blk | cut -d" " -f1)
  echo "ATTEMPT $((N+1)): CURL_RC=$RC SHA=$S SIZE=$(wc -c < /tmp/r1378.blk | tr -d ' ')"
  if [ "$S" = "e7a58be85744280efd710072cff37bc89315b8b0270fba1750c2f74aa5c2ed09" ]; then break; fi
  N=$((N+1)); sleep 5
done
if [ "$S" != "e7a58be85744280efd710072cff37bc89315b8b0270fba1750c2f74aa5c2ed09" ]; then echo "VALID-FAILED: sha mismatch after 3 attempts - nothing applied"; exit 0; fi
echo "===PREGATE430=== anchor + pre-existence gates (fail-closed)"
A=$(grep -c -e "R96 fallback: kernel polling the INT flag" "$SRC")
echo "anchor count: $A (expect 1)"
if [ "$A" != "1" ]; then echo "GATE-FAILED: anchor not unique - refusing"; exit 0; fi
P1=$(grep -c -e "drdoor" "$SRC"); P2=$(grep -c -e "r1378_" "$SRC")
echo "pre-existing drdoor: $P1 r1378_: $P2 (expect 0/0)"
if [ "$P1" != "0" ] || [ "$P2" != "0" ]; then echo "GATE-FAILED: markers pre-exist - refusing"; exit 0; fi
cp -p "$SRC" runtime/runtime.c.pre_r1378
python3 - <<'PYEOF'
src = open("runtime/runtime.c").read()
blk = open("/tmp/r1378.blk").read()
if not blk.endswith("\n"): blk += "\n"
anchor = "            /* R96 fallback: kernel polling the INT flag with a loaded"
i = src.find(anchor)
assert i >= 0, "anchor line not found"
src2 = src[:i] + blk + src[i:]
open("runtime/runtime.c", "w").write(src2)
print("APPLIED: R1378 block inserted before the R96 fallback comment")
PYEOF
echo "===POSTGATE430=== post-apply marker gates (computed expectations)"
for G in "R1378:2" "r1378_door_polls:3" "r1378_fires:3" "drdoor:1" "cd_pending_stamp(1u, 8u):1"; do
  P="${G%%:*}"; E="${G##*:}"
  C=$(grep -c -e "$P" "$SRC")
  echo "gate $P: count=$C expect=$E"
  if [ "$C" != "$E" ]; then echo "GATE-FAILED: $P count mismatch - RESTORING"; cp -p runtime/runtime.c.pre_r1378 "$SRC"; exit 0; fi
done
NEW=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "PATCHED_TREE_SHA=$NEW"
echo "===BUILD430=== compile the patched runtime"
if ! ./run.sh build > /tmp/c430_build.txt 2>&1; then
  echo "BUILD-FAILED: restoring baseline"; tail -25 /tmp/c430_build.txt; cp -p runtime/runtime.c.pre_r1378 "$SRC"; exit 0
fi
echo "BUILD OK"
tail -5 /tmp/c430_build.txt
echo "===RUN430=== full diagnostic run (RUN_BUDGET_S=120)"
RUN_BUDGET_S=120 ./run.sh run > /tmp/run_full_c430.txt 2>&1
echo "RUN_RC=$?"
echo "===DIGEST430=== receipts"
echo "--- DRDOOR: the R1378 fires:"
grep -n -e "drdoor" run.log | head -12
echo "--- FIVESTAGE: armed -> getintr consumed (pendclr site 8) -> FE1C advance:"
grep -n -e "site=8" run.log | head -10
grep -n -e "cmdtl" run.log | awk -F: '$1 > 30000' | head -14
echo "--- PENDCLR: the general ack receipts (final era):"
grep -n -e "pendclr" run.log | awk -F: '$1 > 30000' | head -8
echo "--- DEATH: crashkit/rungasp:"
grep -n -e "rungasp\|poison-HALT\|TRUE DEATH\|SIGSEGV" run.log | head -10
echo "--- TREE: shas:"
echo "baseline=6759e34359fdf33df2e78cfaf2c144194da718412f3d42cb022b12e87470a8bb"
echo "patched=$NEW"
shasum -a 256 runtime/runtime.c | cut -d" " -f1
echo "===PRESERVE430=== run.log preservation (cp -p, timestamps + sha)"
D=$(mktemp -d "$PWD/c430_snap.XXXXXX") || { echo "SNAPSHOT-DIR-FAILED"; exit 0; }
cp -p run.log "$D/run.log" && CP1=$? || CP1=1
cp -p /tmp/run_full_c430.txt "$D/run_full_c430.txt" && CP2=$? || CP2=1
echo "cp_rcs: $CP1 $CP2"
ls -la "$D"
shasum -a 256 "$D/run.log" "$D/run_full_c430.txt"
echo "SNAPSHOT_DIR=$D"
tail -12 "$D/run_full_c430.txt"
echo "===C430DONE=== R1378 applied+run - the digest decides PASS/REVERT from these receipts"
