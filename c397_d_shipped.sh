#!/bin/bash
# c397_r1371.sh - THE R1371 PATCH+RUN CYCLE. The c396
# receipts: revert VERIFIED (the tree is the pristine R1369
# baseline), and the R1265/R1268 door-family site extracted
# (the status-poll site, same-poll cd_data_load, the proven
# composite: FE04 stamp + read_active + stale-FIFO flush +
# stale-sched clear, one serve per slot). The c394 anatomy:
# the CDFS remount walks the system ring (FE08=801F3300+
# slot*0x800, FE04==slot 0..7 receipted, FDF8=2048 armed)
# with EVERY SLOT STARVING, then parks at FE04=16 (the PVD).
# THIS PATCH: R1371 - a THIRD door in the same family, same
# site: FE08 in the new-ring window aligned, FE04==slot (the
# receipted mapping, which also declines the old-ring-base
# posture since slot 10 != FE04 0 - R1268 keeps its own
# serve), FDF8==2048, drive idle -> seek=FE04, read_active,
# FIFO flush, sched clear, budget-stamped camera. PASS =
# serve receipts (slots 0..16+), DATA HANDLER dstw0 nonzero,
# FE04 past 16, the CDFS mount completing, the movie stream,
# GPU/VRAM growth, the spin exiting. REVERT on regression.
# Tree sha-gated on the R1369 baseline.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C397-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="e918ef8605b0c80533c4aa06356fa0fdb6c034fd9fe9e24517a1d1200d09394a"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1369 tree - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1369 tree - the fd-retire era)"
TS=$(date +%Y%m%d_%H%M%S)
PDIR="patch_c397_$TS"
mkdir -p "$PDIR"
cp -p "$SRC" "$PDIR/runtime.c.pre"
echo "PRESERVED: $PDIR/runtime.c.pre"
PRE_G1=$(grep -c "R1268 (c151 verdict): DIRECTORY-SERVE DOOR - the ring base" "$SRC" || true)
PRE_G2=$(grep -c "R1371" "$SRC" || true)
PRE_G3=$(grep -c "system-ring serve slot=%u" "$SRC" || true)
PRE_G4=$(grep -c "0x801F3300u" "$SRC" || true)
echo "PRE anchor count=$PRE_G1 (must be 1)"
echo "PRE R1371 count=$PRE_G2 (must be 0)"
echo "PRE door-text count=$PRE_G3 (must be 0)"
echo "PRE ring-base count=$PRE_G4 (post must be PRE+3)"
if [ "$PRE_G1" != "1" ] || [ "$PRE_G2" != "0" ] || [ "$PRE_G3" != "0" ]; then echo "PRE-GATE-FAILED: refusing, nothing done"; exit 0; fi
python3 - <<'PYEOF'
import sys
p = "runtime/runtime.c"
text = open(p).read()
pre_ring = text.count("0x801F3300u")
lines = text.split("\n")
out = []
e = 0
IND = " " * 8
ANCHOR = "R1268 (c151 verdict): DIRECTORY-SERVE DOOR - the ring base"
for l in lines:
    if ANCHOR in l:
        door = []
        door.append(IND + "/* R1371 (c396): the SYSTEM-RING SERVE - the CDFS remount walk receipts (c394):")
        door.append(IND + " * DATA HANDLER entries at FE08=801F3300+slot*0x800 with FE04==slot (0..7 receipted)")
        door.append(IND + " * and FDF8=2048 armed per slot, every slot starving (dstw0=0), then the walk parks at")
        door.append(IND + " * FE04=16 (the ISO9660 PVD) with nothing serving. The disc-start sectors ARE")
        door.append(IND + " * slot==LBA (R1268 receipted). Same site, same composite as the R1265/R1268 doors:")
        door.append(IND + " * seek stamp = FE04, read_active + !data_loaded (same-poll cd_data_load), stale")
        door.append(IND + " * FIFO flush, stale sched CLEARED (R1269 receipted), one serve per FE08 slot.")
        door.append(IND + " * The FE04==slot guard is the receipted mapping AND excludes the old ring base")
        door.append(IND + " * posture (FE08=801F8300 would be slot 10 with FE04=0 - declined here, served by")
        door.append(IND + " * R1268 below). */")
        door.append(IND + "{")
        door.append(IND + "    static uint32_t r1371_fired[32];")
        door.append(IND + "    uint32_t fe08_s = xenolift_mem_read32(0x8004FE08u);")
        door.append(IND + "    uint32_t fdf8_s = xenolift_mem_read32(0x8004FDF8u);")
        door.append(IND + "    uint32_t fe04_s = xenolift_mem_read32(0x8004FE04u);")
        door.append(IND + "    if (!cd_read_active && !cd_pending")
        door.append(IND + "        && fdf8_s == 2048u")
        door.append(IND + "        && fe08_s >= 0x801F3300u && fe08_s < 0x8020300u")
        door.append(IND + "        && ((fe08_s - 0x801F3300u) & 0x7FFu) == 0u) {")
        door.append(IND + "        uint32_t slot_s = (fe08_s - 0x801F3300u) >> 11;")
        door.append(IND + "        if (slot_s < 32u && fe04_s == slot_s && r1371_fired[slot_s] != fe08_s) {")
        door.append(IND + "            r1371_fired[slot_s] = fe08_s;")
        door.append(IND + "            cd_seek_lba = fe04_s;")
        door.append(IND + "            cd_read_active = 1; cd_data_loaded = 0;")
        door.append(IND + "            if (cd_scheduled) cd_scheduled = 0;")
        door.append(IND + "            if (cd_data_pos < cd_data_n) {")
        door.append(IND + '                r861_out("[R1371] stale-FIFO flush slot=%u data_n=%u data_pos=%u\\n",')
        door.append(IND + "                         slot_s, cd_data_n, cd_data_pos);")
        door.append(IND + "                cd_data_pos = cd_data_n = 0;")
        door.append(IND + "            }")
        door.append(IND + '            r861_out("[R1371] system-ring serve slot=%u FE08=%08X FE04=%u -> disc sector %u armed (sched cleared), same-poll cd_data_load, game drains\\n",')
        door.append(IND + "                     slot_s, fe08_s, fe04_s, fe04_s);")
        door.append(IND + "        }")
        door.append(IND + "    }")
        door.append(IND + "}")
        for d in door:
            out.append(d)
        out.append(l)
        e += 1
        continue
    out.append(l)
if e != 1:
    print("ANCHOR-FAILED: edits %d (must be 1)" % e); sys.exit(1)
patched = "\n".join(out)
if patched.count("R1371") != 3:
    print("POST-FAILED: R1371 count %d (must be 3)" % patched.count("R1371")); sys.exit(1)
if patched.count("system-ring serve slot=%u") != 1:
    print("POST-FAILED: door count != 1"); sys.exit(1)
if patched.count("0x801F3300u") != pre_ring + 3:
    print("POST-FAILED: ring-base delta != 3 (pre=%d post=%d)" % (pre_ring, patched.count("0x801F3300u"))); sys.exit(1)
open(p, "w").write(patched)
print("PATCH-APPLIED (R1371 system-ring serve door)")
PYEOF
if [ $? -ne 0 ]; then echo "PATCH-STEP-FAILED: nothing to run"; exit 0; fi
NEW_SHA=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_SHA=$NEW_SHA"
POST_G1=$(grep -c "R1371" "$SRC" || true)
POST_G2=$(grep -c "system-ring serve slot=%u" "$SRC" || true)
POST_G3=$(grep -c "0x801F3300u" "$SRC" || true)
POST_EXPECT=$((PRE_G4+3))
echo "POST R1371 count=$POST_G1 (must be 3)"
echo "POST door count=$POST_G2 (must be 1)"
echo "POST ring-base count=$POST_G3 (must be $POST_EXPECT = PRE+3)"
if [ "$POST_G1" != "3" ] || [ "$POST_G2" != "1" ] || [ "$POST_G3" != "$POST_EXPECT" ]; then
  echo "POST-GATE-FAILED: restoring the pristine tree"
  cp -p "$PDIR/runtime.c.pre" "$SRC"
  echo "RESTORED"
  exit 0
fi
cc -fsyntax-only -std=gnu99 -Wno-implicit-function-declaration -Wno-int-conversion -Wno-constant-conversion -Wno-int-to-void-pointer-cast "$SRC" 2>/tmp/c397_parse_err.txt
PARSE_RC=$?
echo "PARSE_RC=$PARSE_RC"
if [ $PARSE_RC -ne 0 ]; then
  echo "PARSE-FAILED: restoring the pristine tree (fail-closed)"
  head -12 /tmp/c397_parse_err.txt
  cp -p "$PDIR/runtime.c.pre" "$SRC"
  echo "RESTORED"
  exit 0
fi
echo "PARSE-OK"
echo "===RUN397=== the R1371 build, 120s budget"
RUN_BUDGET_S=120 ./run.sh > /tmp/run_full_c397.txt 2>&1
RUN_RC=$?
echo "RUN_RC=$RUN_RC"
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
if [ ! -s "$LOG" ]; then
  echo "TREE-ROOT-LOG-MISSING: preserving run_full tail"
  tail -25 /tmp/run_full_c397.txt
  exit 0
fi
echo "AUTHORITATIVE LOG = $LOG ($(wc -l < "$LOG" | tr -d ' ') lines)"
echo "===R1371SERVE397=== the system-ring serve receipts"
grep -n "R1371\]" "$LOG" | head -20
echo "===DHW397=== the DATA HANDLER entries after the door (dstw0 nonzero?)"
grep -n "bp\] DATA HANDLER" "$LOG" | awk -F: '$1>=29900' | head -14
echo "===MOUNT397=== the CDFS mount (SelectArchive/new requests?)"
grep -n "SelectArchive\|stab\] req" "$LOG" | awk -F: '$1>=29900' | head -10
echo "===SPIN397=== the end spin (exit? new family?)"
grep -n "mvloop\]" "$LOG" | tail -4
echo "===MDEC397=== the MDEC receipts"
grep -n "mdec\]" "$LOG" | tail -6
echo "===GPUVIS397=== the GPU/VRAM story"
grep -n "R694 live" "$LOG" | tail -3
grep -n "nonblank" "$LOG" | tail -3
echo "===EPOCH397=== the boot epochs"
grep -c "bootentry\] R710" "$LOG" || true
echo "===FAULTS397=== the fault census"
echo "computed-garbage $(grep -c "computed-garbage" "$LOG" || true)"
echo "lzss-runaway $(grep -c "lzss-runaway" "$LOG" || true)"
echo "===TAIL397=== the last 20 receipts"
TL=$(wc -l < "$LOG" | tr -d ' ')
S=$((TL-20)); [ $S -lt 1 ] && S=1
awk -v s="$S" -v e="$TL" 'NR>=s && NR<=e { print NR": "$0 }' "$LOG"
echo "===POSTSHA397==="
shasum -a 256 "$SRC" | cut -d' ' -f1
echo "===C397DONE=== the R1371 cycle is complete - the verdict comes from these receipts"
