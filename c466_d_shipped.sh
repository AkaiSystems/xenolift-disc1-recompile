#!/bin/bash
# c466_r1386.sh - PATCH + BUILD CYCLE (R1386, the
# decoupled f15 announcement). NO RUN (the NEXT cycle
# is run-only 190s on this fresh binary). The c465
# verdict: the stream completed a THIRD time BUT the
# announcement NEVER POSTED - the R1381 re-arm clause
# (FE04 != 108995) resets r1381_fired ONE PASS after
# the fire because the drain stepper advances FE04
# sector-by-sector, killing the watcher's
# precondition. ALSO receipted: waitbr (8 total, all
# boot-era) proves LegacyCdDataWait is NEVER CALLED
# in the pre-movie era - the R878 exit-note is stale
# decode; the park lead is fn 0x800465EC reading
# 0x8007B540-548 (132M hits). FIX R1386: the watcher
# is DECOUPLED - r1385_armed set at the fire
# (survives the FE04-advance re-arm), announces when
# seen_live && FDF8==0, clears armed after posting.
# NO disc_read_lba, NO zeroing of the game's request
# cells (the forged-completion conviction). STRICT
# SHAPE GATE: 8 verbatim anchors (re-arm body, fire
# line, watcher gate, inner gate, announce set, inner
# decl, top decl, print tag) verified before apply -
# single-line edits, no structural inserts. Sandbox:
# true-shape applies + parses (gcc); re-arm-body,
# print-tag, and inner-gate mutants fail closed, 0
# writes. Receipt trail tees to /tmp/c466_receipts.txt.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C466-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c466_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="92094801fa5c24d4d205da04b5ae313269bcdc55e5af9883f71672ce8ebdddad"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1385 tree 92094801 - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1385 tree)"
echo "===PREGATE466=== pre-existence gates (fail-closed)"
A=$(grep -c -e "if (!r1381_fired" "$SRC"); echo "arm-gate sites: $A (expect 1)"
if [ "$A" != "1" ]; then echo "GATE-FAILED: arm-gate count != 1"; exit 0; fi
B=$(grep -c -e "R1385 (c463 receipts)" "$SRC"); echo "R1385 marker: $B (expect 1)"
if [ "$B" != "1" ]; then echo "GATE-FAILED: R1385 watcher not in baseline"; exit 0; fi
C=$(grep -c -e "R1386 (c465 receipts)" "$SRC"); echo "R1386 marker: $C (expect 0)"
if [ "$C" != "0" ]; then echo "GATE-FAILED: marker pre-exists"; exit 0; fi
D=$(grep -c -e "r1385_armed" "$SRC"); echo "r1385_armed refs: $D (expect 0)"
if [ "$D" != "0" ]; then echo "GATE-FAILED: r1385_armed pre-exists"; exit 0; fi
E=$(grep -c -e "re-armed too" "$SRC"); echo "c464 re-arm body: $E (expect 1)"
if [ "$E" != "1" ]; then echo "GATE-FAILED: re-arm body not the c464 shape"; exit 0; fi
cp -p "$SRC" runtime/runtime.c.pre_r1386
echo "===APPLY466=== strict shape gate + apply"
cat > /tmp/r1386_patch.py <<'PYEOF'
import sys
def apply_patch(path):
    lines = open(path).read().split("\n")
    def one(pred, label):
        hits = [i for i, l in enumerate(lines) if pred(l)]
        print("%s: %d (expect 1)" % (label, len(hits)))
        if len(hits) != 1:
            print("FAIL-CLOSED: %s anchor count != 1" % label); return -1
        return hits[0]
    # 1. the re-arm body (drop the r1385_announced reset; FE04 advances during the drain)
    i1 = one(lambda l: l.strip() == "r1381_fired = 0; r1381_since = 0; r1385_announced = 0; /* the request moved on - re-arm for the next epoch (r1385 announcement re-armed too) */", "re-arm body")
    if i1 < 0: return 1
    lines[i1] = """                    r1381_fired = 0; r1381_since = 0; /* R1386 (c465 receipts): the drain stepper advances FE04 sector-by-sector, so this branch fires ONE PASS after the arm - the r1385 watcher state must live independent of r1381_fired */"""
    # 2. the fire block: arm the watcher at the fire
    i2 = one(lambda l: l.strip() == "r1381_fired = 1;", "fire line")
    if i2 < 0: return 1
    lines[i2] = """                        r1381_fired = 1;
                        r1385_armed = 1; r1385_seen_live = 0; r1385_announced = 0; /* R1386 (c465 receipts): the announcement watcher armed at the fire, decoupled from the FE04-advance re-arm */"""
    # 3. the watcher gate: decouple from r1381_fired
    i3 = one(lambda l: l.strip().startswith("if (r1381_fired && !r1385_announced && r1381_fdf8 == 0u) {"), "watcher gate")
    if i3 < 0: return 1
    lines[i3] = """                if (r1385_armed && !r1385_announced) { /* R1386 (c465 receipts): the FE04-advance re-arm resets r1381_fired during the drain - the watcher is decoupled (r1385_armed survives); the data is ALREADY delivered by the healthy stream, so post ONLY the announcement, never a delivery (the R879 forged-completion conviction) and never zero the game's request cells */"""
    # 4. the inner gate: require FDF8==0 at the announce moment
    i4 = one(lambda l: l.strip() == "if (r1385_seen_live) { /* the drain completed: FDF8 went 92180->live->0 */", "inner gate")
    if i4 < 0: return 1
    lines[i4] = """                    if (r1385_seen_live && r1381_fdf8 == 0u) { /* the drain completed: FDF8 went 92180->live->0 */"""
    # 5. the announce action: clear armed too
    i5 = one(lambda l: l.strip() == "r1385_announced = 1;", "announce set")
    if i5 < 0: return 1
    lines[i5] = """                        r1385_announced = 1;
                        r1385_armed = 0;"""
    # 6. the inner static decl moves to the top decl line
    i6 = one(lambda l: l.strip() == "static int r1385_seen_live;", "inner decl")
    if i6 < 0: return 1
    del lines[i6]
    i7 = one(lambda l: "static int r1381_fired; static time_t r1381_since; static int r1385_announced;" in l, "top decl")
    if i7 < 0: return 1
    lines[i7] = lines[i7].replace("static int r1385_announced;",
        "static int r1385_announced; static int r1385_armed; static int r1385_seen_live;")
    # 7. the print tag: R1385 -> R1386
    i8 = one(lambda l: "[f15post] R1385 f15 completion announcement posted:" in l, "print tag")
    if i8 < 0: return 1
    lines[i8] = lines[i8].replace("[f15post] R1385 f15 completion announcement posted:",
                                   "[f15post] R1386 f15 completion announcement posted:")
    open(path, "w").write("\n".join(lines))
    print("APPLIED: R1386 decoupled announcement watcher")
    return 0
sys.exit(apply_patch(sys.argv[1]))
PYEOF
if ! python3 /tmp/r1386_patch.py "$SRC"; then
  echo "APPLY-FAILED: shape gate refused - NOTHING applied, tree unchanged"
  exit 0
fi
echo "===POSTGATE466=== post-apply marker gates (explicit, full patterns)"
C1=$(grep -c -e "R1386 (c465 receipts)" "$SRC"); echo "R1386 markers: $C1 (expect 3)"
C2=$(grep -c -e "f15post. R1386" "$SRC"); echo "f15post R1386 print: $C2 (expect 1)"
C3=$(grep -c -e "f15post. R1385" "$SRC"); echo "f15post R1385 print: $C3 (expect 0)"
C4=$(grep -c -e "r1385_armed" "$SRC"); echo "r1385_armed refs: $C4 (expect 4)"
C5=$(grep -c -e "r1385_seen_live" "$SRC"); echo "r1385_seen_live refs: $C5 (expect 4)"
C6=$(grep -c -e "r1385_announced" "$SRC"); echo "r1385_announced refs: $C6 (expect 4)"
C7=$(grep -c -e "if (!r1381_fired" "$SRC"); echo "arm-gate intact: $C7 (expect 1)"
C8=$(grep -c -e "cd_read_active = 1; cd_pending = 1; g_cd_irq_force = 1;" "$SRC"); echo "bell line: $C8 (expect 1)"
C9=$(grep -c -e "f15near" "$SRC"); echo "f15near total: $C9 (expect 2)"
if [ "$C1" != "3" ] || [ "$C2" != "1" ] || [ "$C3" != "0" ] || [ "$C4" != "4" ] || [ "$C5" != "4" ] || [ "$C6" != "4" ] || [ "$C7" != "1" ] || [ "$C8" != "1" ] || [ "$C9" != "2" ]; then
  echo "GATE-FAILED: restoring baseline"; cp -p runtime/runtime.c.pre_r1386 "$SRC"; exit 0
fi
NEW=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "PATCHED_TREE_SHA=$NEW"
echo "===BUILD466=== compile the patched runtime (NO RUN - the run-only cycle follows)"
if ! ./run.sh build > /tmp/c466_build.txt 2>&1; then
  echo "BUILD-FAILED: restoring baseline"; tail -25 /tmp/c466_build.txt; cp -p runtime/runtime.c.pre_r1386 "$SRC"; exit 0
fi
echo "BUILD OK"
tail -3 /tmp/c466_build.txt
echo "--- tree shas:"
echo "baseline=92094801fa5c24d4d205da04b5ae313269bcdc55e5af9883f71672ce8ebdddad"
echo "patched=$NEW"
shasum -a 256 "$SRC" | cut -d" " -f1
echo "===PRESERVE466=== the receipts + build output"
D=$(mktemp -d "$PWD/c466_snap.XXXXXX") || { echo "SNAPSHOT-DIR-FAILED"; exit 0; }
cp -p /tmp/c466_receipts.txt "$D/c466_receipts.txt" && CP1=0 || CP1=1
cp -p /tmp/c466_build.txt "$D/c466_build.txt" && CP2=0 || CP2=1
cp -p runtime/runtime.c.pre_r1386 "$D/runtime.c.pre_r1386" && CP3=0 || CP3=1
echo "cp_rcs: $CP1 $CP2 $CP3"
ls -la "$D"
echo "===C466DONE=== R1386 landed + compiled - the NEXT cycle runs it (run-only 190s)"
