#!/bin/bash
# c469_r1387.sh - PATCH + BUILD CYCLE (R1387, the
# RE-HOMED f15 announcement). NO RUN (the NEXT cycle
# is run-only 190s on this fresh binary). The c468
# receipts: host-cold CONFIRMED - the R1381 block
# lives in the f15-wait loop and dies with it once
# the arm's bell releases the game (f15near printed
# exactly once all run); the mv-loop is the live host
# (prints across the whole park; the R845 re-force
# precedent lives there). FIX R1387: (1) file-scope
# g_r1385_armed/g_r1385_seen_live/g_r1385_announced
# defined after the R879 fwd-decl comment (before both
# sites, the c482 lesson); (2) the fire sets the
# globals; (3) the in-block watcher + its statics
# RETIRE (brace-balance span delete, 17 lines); (4)
# the watcher lives in the mv loop, right after the
# R313 print - fresh FDF8 read32 each pass, announce
# when seen_live && FDF8==0: the proven R896 cell
# post (A22C+1, slotbits|6, flag578A6=1, FE48(5F)=1,
# FDFC(5F)=0, FE1C(5F)=0), one-shot, re-armed per
# fire. NO disc_read_lba, NO zeroing of the game's
# request cells (the forged-completion conviction).
# STRICT SHAPE GATE: 5 verbatim anchors (R879 decl
# line, fire line, in-block watcher gate, block decl
# line, mvloop print tail). Sandbox: true-shape
# applies + parses (gcc); fire/tail/gate/decl mutants
# fail closed, 0 writes. Receipt trail tees to
# /tmp/c469_receipts.txt.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C469-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c469_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="01b37d7c7252f8a29650cf8f0a27875a0ef1ea15dc62870a55417a77b194daa6"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1386 tree 01b37d7c - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1386 tree)"
echo "===PREGATE469=== pre-existence gates (fail-closed)"
A=$(grep -c -e "if (!r1381_fired" "$SRC"); echo "arm-gate sites: $A (expect 1)"
if [ "$A" != "1" ]; then echo "GATE-FAILED: arm-gate count != 1"; exit 0; fi
B=$(grep -c -e "R1386 (c465 receipts)" "$SRC"); echo "R1386 markers: $B (expect 3)"
if [ "$B" != "3" ]; then echo "GATE-FAILED: R1386 markers wrong count"; exit 0; fi
C=$(grep -c -e "R1387 (c468 receipts)" "$SRC"); echo "R1387 marker: $C (expect 0)"
if [ "$C" != "0" ]; then echo "GATE-FAILED: marker pre-exists"; exit 0; fi
D=$(grep -c -e "g_r1385_armed" "$SRC"); echo "g_r1385_armed refs: $D (expect 0)"
if [ "$D" != "0" ]; then echo "GATE-FAILED: g_r1385_armed pre-exists"; exit 0; fi
E=$(grep -c -e "R879 fwd decls for the movie-door event post in r825_frz_watch" "$SRC"); echo "R879 decl line: $E (expect 1)"
if [ "$E" != "1" ]; then echo "GATE-FAILED: R879 decl anchor not found"; exit 0; fi
F=$(grep -c -e "xenolift_mem_read32(0x8005FDF0u), xenolift_mem_read32(0x8005FDF4u), xenolift_mem_read32(0x8005FE14u));" "$SRC"); echo "mvloop print tail: $F (expect 1)"
if [ "$F" != "1" ]; then echo "GATE-FAILED: mvloop tail anchor not unique"; exit 0; fi
G=$(grep -c -e "if (r1385_armed && !r1385_announced)" "$SRC"); echo "in-block watcher gate: $G (expect 1)"
if [ "$G" != "1" ]; then echo "GATE-FAILED: in-block watcher gate not found"; exit 0; fi
cp -p "$SRC" runtime/runtime.c.pre_r1387
echo "===APPLY469=== strict shape gate + apply"
cat > /tmp/r1387_patch.py <<'PYEOF'
import sys
def apply_patch(path):
    lines = open(path).read().split("\n")
    def one(pred, label):
        hits = [i for i, l in enumerate(lines) if pred(l)]
        print("%s: %d (expect 1)" % (label, len(hits)))
        if len(hits) != 1:
            print("FAIL-CLOSED: %s anchor count != 1" % label); return -1
        return hits[0]
    # 1. file-scope globals after the R879 fwd-decl comment
    i1 = one(lambda l: l.strip() == "/* R879 fwd decls for the movie-door event post in r825_frz_watch */", "R879 decl line")
    if i1 < 0: return 1
    lines[i1] = lines[i1] + "\nstatic int g_r1385_armed, g_r1385_seen_live, g_r1385_announced; /* R1387 (c468 receipts): file-scope so the fire site and the mv-loop watcher share state (the R1381 host goes cold after the bell) */"
    # 2. the fire line: set the globals
    i2 = one(lambda l: "r1385_armed = 1; r1385_seen_live = 0; r1385_announced = 0;" in l and "R1386 (c465 receipts): the announcement watcher armed" in l, "fire line")
    if i2 < 0: return 1
    lines[i2] = """                        g_r1385_armed = 1; g_r1385_seen_live = 0; g_r1385_announced = 0; /* R1387 (c468 receipts): armed at the fire; the watcher lives in the mv loop - this host goes cold once the bell releases the game's own wait */"""
    # 3. retire the in-block watcher: brace-balance span delete from its gate line
    i3 = one(lambda l: l.strip().startswith("if (r1385_armed && !r1385_announced) {"), "in-block watcher gate")
    if i3 < 0: return 1
    bal = 0; j = i3
    while True:
        bal += lines[j].count("{") - lines[j].count("}")
        if bal == 0 and j > i3: break
        j += 1
        if j >= len(lines):
            print("FAIL-CLOSED: watcher span unterminated"); return 1
    print("watcher span: %d lines" % (j - i3 + 1))
    del lines[i3:j+1]
    # 4. strip the r1385 statics from the block decl line
    i4 = one(lambda l: "static int r1381_fired; static time_t r1381_since; static int r1385_announced; static int r1385_armed; static int r1385_seen_live;" in l, "block decl line")
    if i4 < 0: return 1
    lines[i4] = lines[i4].replace("static int r1385_announced; static int r1385_armed; static int r1385_seen_live;", "")
    # 5. the mv-loop watcher, after the R313 print tail
    i5 = one(lambda l: l.strip() == "xenolift_mem_read32(0x8005FDF0u), xenolift_mem_read32(0x8005FDF4u), xenolift_mem_read32(0x8005FE14u));", "mvloop print tail")
    if i5 < 0: return 1
    watcher = """                    { uint32_t w = xenolift_mem_read32(0x8004FDF8u); /* R1387 (c468 receipts): the re-homed f15 announcement watcher - the R1381 host goes cold after the bell; this loop runs through the drain and the park */
                      if (g_r1385_armed && !g_r1385_announced) {
                        if (!g_r1385_seen_live && w != 0u) g_r1385_seen_live = 1;
                        if (g_r1385_seen_live && w == 0u) { /* the drain completed: FDF8 went 92180->live->0 */
                          g_r1385_announced = 1; g_r1385_armed = 0;
                          xenolift_mem_write32(0x8006A22Cu, xenolift_mem_read32(0x8006A22Cu) + 1u);
                          { uint32_t sb = xenolift_mem_read32(0x80056788u);
                            xenolift_mem_write32(0x80056788u, sb | 6u); }
                          { uint16_t one2 = 1;
                            memcpy(xenolift_mem + (0x800578A6u & 0x1FFFFFFFu), &one2, 2); }
                          xenolift_mem_write32(0x8005FE48u, 1u);
                          xenolift_mem_write32(0x8005FDFCu, 0u);
                          xenolift_mem_write32(0x8005FE1Cu, 0u);
                          r861_out("[f15post] R1387 f15 completion announcement posted: A22C->%u slotbits|6 flag578A6=1 FE48(5F)=1 FDFC(5F)=0 FE1C(5F)=0 - from the mv-loop watcher (the R1381 host goes cold; data already delivered by the stream)\\n",
                                   (unsigned)xenolift_mem_read32(0x8006A22Cu));
                        }
                      }
                    }"""
    lines[i5] = lines[i5] + "\n" + watcher
    open(path, "w").write("\n".join(lines))
    print("APPLIED: R1387 re-homed announcement watcher")
    return 0
sys.exit(apply_patch(sys.argv[1]))
PYEOF
if ! python3 /tmp/r1387_patch.py "$SRC"; then
  echo "APPLY-FAILED: shape gate refused - NOTHING applied, tree unchanged"
  exit 0
fi
echo "===POSTGATE469=== post-apply marker gates (explicit, full patterns)"
C1=$(grep -c -e "R1387 (c468 receipts)" "$SRC"); echo "R1387 markers: $C1 (expect 3)"
C2=$(grep -c -e "f15post. R1387" "$SRC"); echo "f15post R1387 print: $C2 (expect 1)"
C3=$(grep -c -e "f15post. R1386" "$SRC"); echo "f15post R1386 print: $C3 (expect 0)"
C4=$(grep -c -e "g_r1385_armed" "$SRC"); echo "g_r1385_armed refs: $C4 (expect 4)"
C5=$(grep -c -e "g_r1385_seen_live" "$SRC"); echo "g_r1385_seen_live refs: $C5 (expect 4)"
C6=$(grep -c -e "g_r1385_announced" "$SRC"); echo "g_r1385_announced refs: $C6 (expect 4)"
C7=$(grep -c -e "static int r1385_armed" "$SRC"); echo "old block statics: $C7 (expect 0)"
C8=$(grep -c -e "if (r1385_armed && !r1385_announced)" "$SRC"); echo "old watcher gate: $C8 (expect 0)"
C9=$(grep -c -e "R1386 (c465 receipts)" "$SRC"); echo "R1386 markers: $C9 (expect 1)"
C10=$(grep -c -e "if (!r1381_fired" "$SRC"); echo "arm-gate intact: $C10 (expect 1)"
C11=$(grep -c -e "cd_read_active = 1; cd_pending = 1; g_cd_irq_force = 1;" "$SRC"); echo "bell line: $C11 (expect 1)"
C12=$(grep -c -e "f15near" "$SRC"); echo "f15near total: $C12 (expect 2)"
if [ "$C1" != "3" ] || [ "$C2" != "1" ] || [ "$C3" != "0" ] || [ "$C4" != "4" ] || [ "$C5" != "4" ] || [ "$C6" != "4" ] || [ "$C7" != "0" ] || [ "$C8" != "0" ] || [ "$C9" != "1" ] || [ "$C10" != "1" ] || [ "$C11" != "1" ] || [ "$C12" != "2" ]; then
  echo "GATE-FAILED: restoring baseline"; cp -p runtime/runtime.c.pre_r1387 "$SRC"; exit 0
fi
NEW=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "PATCHED_TREE_SHA=$NEW"
echo "===BUILD469=== compile the patched runtime (NO RUN - the run-only cycle follows)"
if ! ./run.sh build > /tmp/c469_build.txt 2>&1; then
  echo "BUILD-FAILED: restoring baseline"; tail -25 /tmp/c469_build.txt; cp -p runtime/runtime.c.pre_r1387 "$SRC"; exit 0
fi
echo "BUILD OK"
tail -3 /tmp/c469_build.txt
echo "--- tree shas:"
echo "baseline=01b37d7c7252f8a29650cf8f0a27875a0ef1ea15dc62870a55417a77b194daa6"
echo "patched=$NEW"
shasum -a 256 "$SRC" | cut -d" " -f1
echo "===PRESERVE469=== the receipts + build output"
D=$(mktemp -d "$PWD/c469_snap.XXXXXX") || { echo "SNAPSHOT-DIR-FAILED"; exit 0; }
cp -p /tmp/c469_receipts.txt "$D/c469_receipts.txt" && CP1=0 || CP1=1
cp -p /tmp/c469_build.txt "$D/c469_build.txt" && CP2=0 || CP2=1
cp -p runtime/runtime.c.pre_r1387 "$D/runtime.c.pre_r1386" && CP3=0 || CP3=1
echo "cp_rcs: $CP1 $CP2 $CP3"
ls -la "$D"
echo "===C469DONE=== R1387 landed + compiled - the NEXT cycle runs it (run-only 190s)"
