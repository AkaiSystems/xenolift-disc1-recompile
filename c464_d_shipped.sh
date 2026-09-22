#!/bin/bash
# c464_r1385.sh - PATCH + BUILD CYCLE (R1385, the f15
# completion announcement). NO RUN (the NEXT cycle is
# run-only 190s on this fresh binary). The c463
# receipts: the R879 movie-door is RETIRED - c307
# convicted its delivery as forged-completion (stale
# seek/dst, then zeroed request cells); the
# announcement WRITES are the reusable part (every
# R896 sync delivery posts A22C+1 + slotbits|6 +
# flag578A6=1 + FDFC(5F)=0 + FE48(5F)=1 + FE1C(5F)=0,
# and those waits passed); our f15 arrival never
# bumped A22C (stuck 2), so LegacyCdDataWait times
# out. FIX R1385: in the R1384 block, a completion
# watcher - after the arm fires and the drain brings
# FDF8 back to 0 (seen-live first, so the arm's own
# zero start does not false-fire), post the EXACT
# R896-class announcement, one-shot, reset on
# re-arm. NO disc_read_lba, NO zeroing of the game's
# request cells (the forged-completion conviction).
# STRICT SHAPE GATE: the re-arm anchor + body line +
# decl line verified verbatim; the announcement
# inserted after the re-arm branch. Sandbox:
# true-shape applies + parses (gcc); wrong-LBA,
# missing-decl, and differing-body mutants fail
# closed, 0 writes. Receipt trail tees to
# /tmp/c464_receipts.txt.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C464-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c464_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="06e7abc1114ec13b231b5a58621c90732c0c2ed62a27e4502bebe96197e6870b"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1384 tree 06e7abc1 - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1384 tree)"
echo "===PREGATE464=== pre-existence gates (fail-closed)"
A=$(grep -c -e "if (!r1381_fired" "$SRC"); echo "arm-gate sites: $A (expect 1)"
if [ "$A" != "1" ]; then echo "GATE-FAILED: arm-gate count != 1"; exit 0; fi
B=$(grep -c -e "R1385 (c463 receipts)" "$SRC"); echo "R1385 marker: $B (expect 0)"
if [ "$B" != "0" ]; then echo "GATE-FAILED: marker pre-exists"; exit 0; fi
C=$(grep -c -e "r1385_announced" "$SRC"); echo "r1385 refs: $C (expect 0)"
if [ "$C" != "0" ]; then echo "GATE-FAILED: r1385 pre-exists"; exit 0; fi
D=$(grep -c -e "the request moved on - re-arm for the next epoch" "$SRC"); echo "re-arm body lines: $D (expect 1)"
if [ "$D" != "1" ]; then echo "GATE-FAILED: re-arm body not the exact shape"; exit 0; fi
cp -p "$SRC" runtime/runtime.c.pre_r1385
echo "===APPLY464=== strict shape gate + apply"
cat > /tmp/r1385_patch.py <<'PYEOF'
import sys
def apply_patch(path):
    lines = open(path).read().split("\n")
    anchors = [i for i, l in enumerate(lines) if l.strip() == "if (r1381_fired && r1381_fe04 != 108995u) {"]
    print("re-arm sites: %d (expect 1)" % len(anchors))
    if len(anchors) != 1:
        print("FAIL-CLOSED: re-arm anchor count != 1"); return 1
    i0 = anchors[0]
    if lines[i0+1].strip() != "r1381_fired = 0; r1381_since = 0; /* the request moved on - re-arm for the next epoch */":
        print("FAIL-CLOSED: re-arm body shape unexpected: %r" % lines[i0+1]); return 1
    lines[i0+1] = """                    r1381_fired = 0; r1381_since = 0; r1385_announced = 0; /* the request moved on - re-arm for the next epoch (r1385 announcement re-armed too) */"""
    announce = """                if (r1381_fired && !r1385_announced && r1381_fdf8 == 0u) { /* R1385 (c463 receipts): the f15 completion announcement - the R896 sync-delivery pattern (in-tree, proven): LegacyCdDataWait polls flag578A6 via 0x8004B894 and times out on the never-incrementing A22C; the data is ALREADY delivered by the healthy stream (cd-dma receipts), so post ONLY the announcement, never a delivery (the R879 forged-completion conviction) and never zero the game's request cells */
                    static int r1385_seen_live;
                    if (!r1385_seen_live && r1381_fdf8 != 0u) r1385_seen_live = 1;
                    if (r1385_seen_live) { /* the drain completed: FDF8 went 92180->live->0 */
                        r1385_announced = 1;
                        xenolift_mem_write32(0x8006A22Cu, xenolift_mem_read32(0x8006A22Cu) + 1u);
                        { uint32_t sb = xenolift_mem_read32(0x80056788u);
                          xenolift_mem_write32(0x80056788u, sb | 6u); }
                        { uint16_t one2 = 1;
                          memcpy(xenolift_mem + (0x800578A6u & 0x1FFFFFFFu), &one2, 2); }
                        xenolift_mem_write32(0x8005FE48u, 1u);
                        xenolift_mem_write32(0x8005FDFCu, 0u);
                        xenolift_mem_write32(0x8005FE1Cu, 0u);
                        r861_out("[f15post] R1385 f15 completion announcement posted: A22C->%u slotbits|6 flag578A6=1 FE48(5F)=1 FDFC(5F)=0 FE1C(5F)=0 - LegacyCdDataWait's exit contract, data already delivered by the stream\\n",
                                 (unsigned)xenolift_mem_read32(0x8006A22Cu));
                    }
                }"""
    lines.insert(i0+2, announce)
    decl = [i for i, l in enumerate(lines) if "static int r1381_fired; static time_t r1381_since;" in l]
    if len(decl) != 1:
        print("FAIL-CLOSED: decl site count != 1"); return 1
    lines[decl[0]] = lines[decl[0]].replace("static int r1381_fired; static time_t r1381_since;",
        "static int r1381_fired; static time_t r1381_since; static int r1385_announced;")
    open(path, "w").write("\n".join(lines))
    print("APPLIED: R1385 completion announcement")
    return 0
sys.exit(apply_patch(sys.argv[1]))
PYEOF
if ! python3 /tmp/r1385_patch.py "$SRC"; then
  echo "APPLY-FAILED: shape gate refused - NOTHING applied, tree unchanged"
  exit 0
fi
echo "===POSTGATE464=== post-apply marker gates (explicit, full patterns)"
C1=$(grep -c -e "R1385 (c463 receipts)" "$SRC"); echo "R1385 marker: $C1 (expect 1)"
C2=$(grep -c -e "f15post. R1385" "$SRC"); echo "f15post print: $C2 (expect 1)"
C3=$(grep -c -e "r1385_announced" "$SRC"); echo "r1385_announced refs: $C3 (expect 4)"
C4=$(grep -c -e "r1385_seen_live" "$SRC"); echo "r1385_seen_live refs: $C4 (expect 3)"
C5=$(grep -c -e "if (!r1381_fired" "$SRC"); echo "arm-gate intact: $C5 (expect 1)"
C6=$(grep -c -e "cd_read_active = 1; cd_pending = 1; g_cd_irq_force = 1;" "$SRC"); echo "bell line: $C6 (expect 1)"
C7=$(grep -c -e "f15near" "$SRC"); echo "f15near total: $C7 (expect 2)"
C8=$(grep -c -e "re-arm for the next epoch (r1385 announcement re-armed too)" "$SRC"); echo "re-arm updated: $C8 (expect 1)"
if [ "$C1" != "1" ] || [ "$C2" != "1" ] || [ "$C3" != "4" ] || [ "$C4" != "3" ] || [ "$C5" != "1" ] || [ "$C6" != "1" ] || [ "$C7" != "2" ] || [ "$C8" != "1" ]; then
  echo "GATE-FAILED: restoring baseline"; cp -p runtime/runtime.c.pre_r1385 "$SRC"; exit 0
fi
NEW=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "PATCHED_TREE_SHA=$NEW"
echo "===BUILD464=== compile the patched runtime (NO RUN - the run-only cycle follows)"
if ! ./run.sh build > /tmp/c464_build.txt 2>&1; then
  echo "BUILD-FAILED: restoring baseline"; tail -25 /tmp/c464_build.txt; cp -p runtime/runtime.c.pre_r1385 "$SRC"; exit 0
fi
echo "BUILD OK"
tail -3 /tmp/c464_build.txt
echo "--- tree shas:"
echo "baseline=06e7abc1114ec13b231b5a58621c90732c0c2ed62a27e4502bebe96197e6870b"
echo "patched=$NEW"
shasum -a 256 "$SRC" | cut -d" " -f1
echo "===PRESERVE464=== the receipts + build output"
D=$(mktemp -d "$PWD/c464_snap.XXXXXX") || { echo "SNAPSHOT-DIR-FAILED"; exit 0; }
cp -p /tmp/c464_receipts.txt "$D/c464_receipts.txt" && CP1=0 || CP1=1
cp -p /tmp/c464_build.txt "$D/c464_build.txt" && CP2=0 || CP2=1
cp -p runtime/runtime.c.pre_r1385 "$D/runtime.c.pre_r1385" && CP3=0 || CP3=1
echo "cp_rcs: $CP1 $CP2 $CP3"
ls -la "$D"
echo "===C464DONE=== R1385 landed + compiled - the NEXT cycle runs it (run-only 190s)"
