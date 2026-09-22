#!/bin/bash
# c457_r1383.sh - PATCH + BUILD CYCLE (R1383, the
# arm+bell). NO RUN (watchdog math: the NEXT cycle is
# run-only 190s on this fresh binary). The c456
# verdict: the park arrives but the game RETIRES the
# positioning within seconds - the 5s freeze never
# had its window, and R1298's 30s confirm can never
# hold. The font loop's LegacyCdDataWait times out on
# the stale A22C=2 latch (no data at the f15 request).
# FIX R1383 (self-contained): freeze 5s->2s + on fire
# the RECEIPTED BELL (cd_read_active=1; cd_pending=1;
# g_cd_irq_force=1 - the fld-rearm pattern; the sector
# is already staged; the game's own queue consumes;
# zero guest dispatch) - R1298 dependency dropped. +
# budgeted [f15near] no-fire camera naming the
# excluding term at near-miss postures. STRICT SHAPE
# GATE: the arm-gate anchor + freeze/write/print/
# comment/elseif window anchors verified verbatim;
# edits in descending-index order; print replaced by
# content. Sandbox: true-shape applies + parses
# (gcc); wrong-freeze and missing-anchor mutants fail
# closed, 0 writes. Receipt trail tees to
# /tmp/c457_receipts.txt as it runs.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C457-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c457_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="77a9b4fc989d9e287ba1149a9f813a6e12b33fe9d3b68bb0a521c256b6442bed"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1382 tree 77a9b4fc - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1382 tree)"
echo "===PREGATE457=== pre-existence gates (fail-closed)"
A=$(grep -c -e "if (!r1381_fired" "$SRC"); echo "arm-gate sites: $A (expect 1)"
if [ "$A" != "1" ]; then echo "GATE-FAILED: arm-gate count != 1"; exit 0; fi
B=$(grep -c -e "r1381_since >= 5" "$SRC"); echo "freeze-5s lines: $B (expect 1)"
if [ "$B" != "1" ]; then echo "GATE-FAILED: freeze line missing"; exit 0; fi
C=$(grep -c -e "R1383 (c456 receipts)" "$SRC"); echo "R1383 marker: $C (expect 0)"
if [ "$C" != "0" ]; then echo "GATE-FAILED: marker pre-exists"; exit 0; fi
D=$(grep -c -e "f15near" "$SRC"); echo "f15near marker: $D (expect 0)"
if [ "$D" != "0" ]; then echo "GATE-FAILED: camera pre-exists"; exit 0; fi
E=$(grep -c -e "g_cd_irq_force" "$SRC"); echo "g_cd_irq_force refs: $E (expect >0 - the bell variable must exist)"
if [ "$E" -lt 1 ]; then echo "GATE-FAILED: bell variable not found - refusing"; exit 0; fi
cp -p "$SRC" runtime/runtime.c.pre_r1383
echo "===APPLY457=== strict shape gate + apply"
cat > /tmp/r1383_patch.py <<'PYEOF'
import sys
def apply_patch(path):
    lines = open(path).read().split("\n")
    i0 = [i for i, l in enumerate(lines) if l.strip() == "if (!r1381_fired"]
    print("arm-gate sites: %d (expect 1)" % len(i0))
    if len(i0) != 1:
        print("FAIL-CLOSED: arm-gate anchor count != 1"); return 1
    i0 = i0[0]
    win = lines[i0-20 : i0+30]
    def find_win(pred):
        for k, l in enumerate(win):
            if pred(l):
                return i0 - 20 + k
        return -1
    fz = find_win(lambda l: "r1381_since >= 5" in l)
    wr = find_win(lambda l: "xenolift_mem_write32(0x8004FDF8u, 92180u);" in l)
    pr = find_win(lambda l: "[f15arm] R1381: file-15 park frozen 10s" in l)
    cm = find_win(lambda l: "R1381 (c450/c448 receipts)" in l)
    el = find_win(lambda l: l.strip() == "} else if (r1381_since != 0 && r1381_fe04 != 108995u) {")
    print("anchors: freeze=%d write=%d print=%d comment=%d elseif=%d" % (fz, wr, pr, cm, el))
    if min(fz, wr, pr, cm, el) < 0:
        print("FAIL-CLOSED: a window anchor is missing"); return 1
    if lines[el+2].strip() != "}":
        print("FAIL-CLOSED: elseif branch shape unexpected: %r" % lines[el+2]); return 1
    camera = """                { /* R1383 no-fire camera: name the excluding term at near-miss postures */
                    static uint32_t r1383_n; static time_t r1383_t;
                    if (r1383_n < 8u && r1381_fe04 == 108995u && r1381_fdf8 == 0u
                        && xl_wall() != r1383_t) {
                        r1383_t = xl_wall(); r1383_n++;
                        r861_out("[f15near] R1383 near-miss #%u: fe08=%08X seek=%u act=%u pend=%u sched=%u since=%u fired=%d\\n",
                                 r1383_n, r1381_fe08, cd_seek_lba, cd_read_active?1u:0u, (unsigned)cd_pending, cd_scheduled?1u:0u,
                                 (unsigned)(r1381_since ? (uint32_t)(xl_wall() - r1381_since) : 0u), r1381_fired);
                    }
                }"""
    bell = """                        cd_read_active = 1; cd_pending = 1; g_cd_irq_force = 1; /* R1383: the arm + start-bell (the fld-rearm pattern; the sector is already staged; the game's own queue consumes; zero guest dispatch) */"""
    lines.insert(el+3, camera)
    lines.insert(wr+1, bell)
    lines[fz] = lines[fz].replace("r1381_since >= 5", "r1381_since >= 2")
    lines[cm] = lines[cm].replace("R1381 (c450/c448 receipts): the file-15 read-ahead ARM. The field module",
                                  "R1383 (c456 receipts): the file-15 ARM+BELL. The field module")
    done = 0
    for k, l in enumerate(lines):
        if "[f15arm] R1381: file-15 park frozen 10s" in l:
            lines[k] = """                        r861_out("[f15arm] R1383: file-15 park armed (2s freeze): FDF8 0->92180, act=1 pend=1 irq-force=1 (the fld-rearm bell); FE08=%08X\\n", r1381_fe08);"""
            done += 1
    if done != 1:
        print("FAIL-CLOSED: print line replacement count %d != 1" % done); return 1
    open(path, "w").write("\n".join(lines))
    print("APPLIED: R1383 arm+bell + freeze 2s + near-miss camera")
    return 0
sys.exit(apply_patch(sys.argv[1]))
PYEOF
if ! python3 /tmp/r1383_patch.py "$SRC"; then
  echo "APPLY-FAILED: shape gate refused - NOTHING applied, tree unchanged"
  exit 0
fi
echo "===POSTGATE457=== post-apply marker gates (explicit, full patterns)"
C1=$(grep -c -e "R1383 (c456 receipts)" "$SRC"); echo "R1383 marker: $C1 (expect 1)"
C2=$(grep -c -e "f15near" "$SRC"); echo "f15near markers: $C2 (expect 1)"
C3=$(grep -c -e "cd_read_active = 1; cd_pending = 1; g_cd_irq_force = 1;" "$SRC"); echo "bell line: $C3 (expect 1)"
C4=$(grep -c -e "r1381_since >= 2" "$SRC"); echo "freeze-2s line: $C4 (expect 1)"
C5=$(grep -c -e "r1381_since >= 5" "$SRC"); echo "freeze-5s line: $C5 (expect 0)"
C6=$(grep -c -e "if (!r1381_fired" "$SRC"); echo "arm-gate intact: $C6 (expect 1)"
if [ "$C1" != "1" ] || [ "$C2" != "1" ] || [ "$C3" != "1" ] || [ "$C4" != "1" ] || [ "$C5" != "0" ] || [ "$C6" != "1" ]; then
  echo "GATE-FAILED: restoring baseline"; cp -p runtime/runtime.c.pre_r1383 "$SRC"; exit 0
fi
NEW=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "PATCHED_TREE_SHA=$NEW"
echo "===BUILD457=== compile the patched runtime (NO RUN - the run-only cycle follows)"
if ! ./run.sh build > /tmp/c457_build.txt 2>&1; then
  echo "BUILD-FAILED: restoring baseline"; tail -25 /tmp/c457_build.txt; cp -p runtime/runtime.c.pre_r1383 "$SRC"; exit 0
fi
echo "BUILD OK"
tail -3 /tmp/c457_build.txt
echo "--- tree shas:"
echo "baseline=77a9b4fc989d9e287ba1149a9f813a6e12b33fe9d3b68bb0a521c256b6442bed"
echo "patched=$NEW"
shasum -a 256 "$SRC" | cut -d" " -f1
echo "===PRESERVE457=== the receipts + build output"
D=$(mktemp -d "$PWD/c457_snap.XXXXXX") || { echo "SNAPSHOT-DIR-FAILED"; exit 0; }
cp -p /tmp/c457_receipts.txt "$D/c457_receipts.txt" && CP1=0 || CP1=1
cp -p /tmp/c457_build.txt "$D/c457_build.txt" && CP2=0 || CP2=1
cp -p runtime/runtime.c.pre_r1383 "$D/runtime.c.pre_r1383" && CP3=0 || CP3=1
echo "cp_rcs: $CP1 $CP2 $CP3"
ls -la "$D"
echo "===C457DONE=== R1383 landed + compiled - the NEXT cycle runs it (run-only 190s)"
