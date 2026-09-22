#!/bin/bash
# c459_r1384.sh - PATCH + BUILD CYCLE (R1384, the
# immediate fire). NO RUN (the NEXT cycle is run-only
# 190s on this fresh binary). The c458 verdict: the
# [f15near] camera FIRED ONCE and named the fault -
# near-miss #1: fe08=8007F2F8 seek=108995 act=0
# pend=0 sched=0 SINCE=0 - the positioning window is
# SUB-SECOND (the camera samples 1/sec; the game
# retires FE04 before the next sample); no freeze,
# not even 2s, can elapse. FIX R1384: fire on the
# POSTURE itself, first hot-loop pass - the 4196C
# write sets FE04/FE08/FDF8 together, so the first
# pass after positioning sees the complete posture;
# the ultra-specific gate (FE04==108995 + ring band +
# FDF8==0 + seek==108995 + !act) is its own
# discriminator. The bell (act/pend/irq-force) +
# FDF8=92180 (file table) unchanged; one-shot +
# re-arm. STRICT SHAPE GATE: the freeze-block shape
# (open line, since-stamp, 2s line contiguous)
# verified before the splice; comment + print
# replaced by content. Sandbox: true-shape applies +
# parses (gcc); wrong-freeze, missing-anchor, and
# shape-shift mutants all fail closed, 0 writes.
# Receipt trail tees to /tmp/c459_receipts.txt.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C459-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c459_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="ef5508cecdb61e35bf5307cf7b887fa59b776932a71df5896d2d7189bd631e13"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1383 tree ef5508ce - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1383 tree)"
echo "===PREGATE459=== pre-existence gates (fail-closed)"
A=$(grep -c -e "if (!r1381_fired" "$SRC"); echo "arm-gate sites: $A (expect 1)"
if [ "$A" != "1" ]; then echo "GATE-FAILED: arm-gate count != 1"; exit 0; fi
B=$(grep -c -e "r1381_since >= 2" "$SRC"); echo "freeze-2s lines: $B (expect 1)"
if [ "$B" != "1" ]; then echo "GATE-FAILED: freeze-2s line missing"; exit 0; fi
C=$(grep -c -e "R1384 (c458 receipts)" "$SRC"); echo "R1384 marker: $C (expect 0)"
if [ "$C" != "0" ]; then echo "GATE-FAILED: marker pre-exists"; exit 0; fi
D=$(grep -c -e "f15arm. R1384" "$SRC"); echo "f15arm-R1384 marker: $D (expect 0)"
if [ "$D" != "0" ]; then echo "GATE-FAILED: print marker pre-exists"; exit 0; fi
cp -p "$SRC" runtime/runtime.c.pre_r1384
echo "===APPLY459=== strict shape gate + apply"
cat > /tmp/r1384_patch.py <<'PYEOF'
import sys
def apply_patch(path):
    lines = open(path).read().split("\n")
    i0 = [i for i, l in enumerate(lines) if l.strip() == "if (!r1381_fired"]
    print("arm-gate sites: %d (expect 1)" % len(i0))
    if len(i0) != 1:
        print("FAIL-CLOSED: arm-gate anchor count != 1"); return 1
    i0 = i0[0]
    win = lines[i0-20 : i0+35]
    def find_win(pred):
        for k, l in enumerate(win):
            if pred(l):
                return i0 - 20 + k
        return -1
    fz1 = find_win(lambda l: l.strip() == "if (r1381_since == 0) {")
    fz2 = find_win(lambda l: "r1381_since >= 2" in l)
    print("anchors: freeze-open=%d freeze-2s=%d" % (fz1, fz2))
    if min(fz1, fz2) < 0:
        print("FAIL-CLOSED: a window anchor is missing"); return 1
    if fz2 != fz1 + 2:
        print("FAIL-CLOSED: freeze block shape unexpected (fz2-fz1=%d, expect 2)" % (fz2-fz1)); return 1
    lines[fz1] = """                    { /* R1384 (c458 receipts): the positioning window is SUB-SECOND (the [f15near] camera sampled once with since=0; the game retires FE04 within 1s of the 4196C write) - no freeze can elapse; fire on the posture itself, first pass */"""
    del lines[fz1+1 : fz2+1]
    done_cm = 0
    done_pr = 0
    for k, l in enumerate(lines):
        if "R1383 (c456 receipts): the file-15 ARM+BELL. The field module" in l:
            lines[k] = l.replace("R1383 (c456 receipts): the file-15 ARM+BELL. The field module",
                                 "R1384 (c458 receipts): the file-15 ARM+BELL, IMMEDIATE. The field module")
            done_cm += 1
        if "[f15arm] R1383: file-15 park armed (2s freeze):" in l:
            lines[k] = l.replace("[f15arm] R1383: file-15 park armed (2s freeze): FDF8 0->92180, act=1 pend=1 irq-force=1 (the fld-rearm bell); FE08=%08X",
                                 "[f15arm] R1384: file-15 posture armed on FIRST PASS: FDF8 0->92180, act=1 pend=1 irq-force=1 (the fld-rearm bell); FE08=%08X")
            done_pr += 1
    if done_cm != 1 or done_pr != 1:
        print("FAIL-CLOSED: comment/print replacement counts %d/%d != 1/1" % (done_cm, done_pr)); return 1
    open(path, "w").write("\n".join(lines))
    print("APPLIED: R1384 immediate fire")
    return 0
sys.exit(apply_patch(sys.argv[1]))
PYEOF
if ! python3 /tmp/r1384_patch.py "$SRC"; then
  echo "APPLY-FAILED: shape gate refused - NOTHING applied, tree unchanged"
  exit 0
fi
echo "===POSTGATE459=== post-apply marker gates (explicit, full patterns)"
C1=$(grep -c -e "R1384 (c458 receipts)" "$SRC"); echo "R1384 marker: $C1 (expect 2 - the block opener + the comment)"
C2=$(grep -c -e "f15arm. R1384" "$SRC"); echo "f15arm-R1384 print: $C2 (expect 1)"
C3=$(grep -c -e "r1381_since >= 2" "$SRC"); echo "freeze-2s line: $C3 (expect 0)"
C4=$(grep -c -e "if (r1381_since == 0)" "$SRC"); echo "freeze-open line: $C4 (expect 0)"
C5=$(grep -c -e "if (!r1381_fired" "$SRC"); echo "arm-gate intact: $C5 (expect 1)"
C6=$(grep -c -e "cd_read_active = 1; cd_pending = 1; g_cd_irq_force = 1;" "$SRC"); echo "bell line: $C6 (expect 1)"
C7=$(grep -c -e "f15near" "$SRC"); echo "f15near total: $C7 (expect 2 - camera comment + print)"
if [ "$C1" != "2" ] || [ "$C2" != "1" ] || [ "$C3" != "0" ] || [ "$C4" != "0" ] || [ "$C5" != "1" ] || [ "$C6" != "1" ] || [ "$C7" != "2" ]; then
  echo "GATE-FAILED: restoring baseline"; cp -p runtime/runtime.c.pre_r1384 "$SRC"; exit 0
fi
NEW=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "PATCHED_TREE_SHA=$NEW"
echo "===BUILD459=== compile the patched runtime (NO RUN - the run-only cycle follows)"
if ! ./run.sh build > /tmp/c459_build.txt 2>&1; then
  echo "BUILD-FAILED: restoring baseline"; tail -25 /tmp/c459_build.txt; cp -p runtime/runtime.c.pre_r1384 "$SRC"; exit 0
fi
echo "BUILD OK"
tail -3 /tmp/c459_build.txt
echo "--- tree shas:"
echo "baseline=ef5508cecdb61e35bf5307cf7b887fa59b776932a71df5896d2d7189bd631e13"
echo "patched=$NEW"
shasum -a 256 "$SRC" | cut -d" " -f1
echo "===PRESERVE459=== the receipts + build output"
D=$(mktemp -d "$PWD/c459_snap.XXXXXX") || { echo "SNAPSHOT-DIR-FAILED"; exit 0; }
cp -p /tmp/c459_receipts.txt "$D/c459_receipts.txt" && CP1=0 || CP1=1
cp -p /tmp/c459_build.txt "$D/c459_build.txt" && CP2=0 || CP2=1
cp -p runtime/runtime.c.pre_r1384 "$D/runtime.c.pre_r1384" && CP3=0 || CP3=1
echo "cp_rcs: $CP1 $CP2 $CP3"
ls -la "$D"
echo "===C459DONE=== R1384 landed + compiled - the NEXT cycle runs it (run-only 190s)"
