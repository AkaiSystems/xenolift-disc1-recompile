#!/bin/bash
# c454_r1382.sh - PATCH + BUILD CYCLE (R1382, the
# arm-gate WIDEN). NO RUN - the c451/c453 watchdog
# math (build ~140s + run 150s > 240s) forces the
# split: this cycle lands the patch and compiles; the
# NEXT cycle (c455) is run-only 150s on the new
# binary. The c453 verdict: the park was reached but
# R1381 never armed - MY GATE ERROR: I gated on the
# [schdw] POST-CLEAR posture (cmd=06/pend=0/sched=0)
# but the receipted ARRIVAL posture holds cmd=01,
# pend=1, sched=1 (the game's GetStat-poll
# mid-handshake). FIX R1382: drop the cmd/pend/sched
# terms, keep FE04==108995 + FE08 band + FDF8==0 +
# seek==108995 + !act, freeze 10s->5s (the game
# retires the posture within seconds; walker F0C=14
# F10=00201524 = file#14 COMPLETED NATIVELY, then
# FE04->0 into the font loop). STRICT SHAPE GATE: the
# arm-gate anchor ('if (!r1381_fired', unique) + all
# 6 condition lines verified verbatim before the
# splice; the freeze line found-and-replaced.
# Sandbox: true-shape applies + parses (gcc); both
# mutants (missing anchor, wrong condition line) fail
# closed, 0 writes. Receipt trail tees to
# /tmp/c454_receipts.txt as it runs.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C454-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c454_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="8303add53da667af6f70a63ea433c12a8c59377fc87ec57eb4b50d0a461a4b29"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1381 tree 8303add5 - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1381 tree)"
echo "===PREGATE454=== pre-existence gates (fail-closed)"
A=$(grep -c -e "if (!r1381_fired" "$SRC"); echo "arm-gate sites: $A (expect 1)"
if [ "$A" != "1" ]; then echo "GATE-FAILED: arm-gate count != 1"; exit 0; fi
B=$(grep -c -e "r1381_since >= 10" "$SRC"); echo "freeze-10s lines: $B (expect 1)"
if [ "$B" != "1" ]; then echo "GATE-FAILED: freeze line missing"; exit 0; fi
C=$(grep -c -e "R1382 (c453)" "$SRC"); echo "R1382 marker: $C (expect 0)"
if [ "$C" != "0" ]; then echo "GATE-FAILED: marker pre-exists"; exit 0; fi
cp -p "$SRC" runtime/runtime.c.pre_r1382
echo "===APPLY454=== strict shape gate + apply"
cat > /tmp/r1382_patch.py <<'PYEOF'
import sys
COND_LINES = [
    "&& r1381_fe04 == 108995u",
    "&& r1381_fe08 >= 0x8006FAF8u && r1381_fe08 < 0x80080000u",
    "&& r1381_fdf8 == 0u",
    "&& cd_seek_lba == 108995u",
    "&& cd_last_cmd == 0x06u",
    "&& !cd_read_active && !cd_pending && !cd_scheduled) {",
]
NEW_TAIL = [
    "&& r1381_fe04 == 108995u",
    "&& r1381_fe08 >= 0x8006FAF8u && r1381_fe08 < 0x80080000u",
    "&& r1381_fdf8 == 0u",
    "&& cd_seek_lba == 108995u",
    "&& !cd_read_active) { /* R1382 (c453): the cmd/pend/sched terms removed - the receipted ARRIVAL posture holds cmd=01 pend=1 sched=1 (the game's GetStat-poll mid-handshake); the [schdw] posture was POST-CLEAR, not arrival */",
]
def apply_patch(path):
    lines = open(path).read().split("\n")
    idx = [i for i, l in enumerate(lines) if l.strip() == "if (!r1381_fired"]
    print("arm-gate sites: %d (expect 1)" % len(idx))
    if len(idx) != 1:
        print("FAIL-CLOSED: arm-gate anchor count != 1"); return 1
    i0 = idx[0]
    for k, want in enumerate(COND_LINES):
        if lines[i0 + 1 + k].strip() != want:
            print("FAIL-CLOSED: condition line %d mismatch (got %r want %r)" % (k, lines[i0+1+k].strip(), want)); return 1
    del lines[i0+1 : i0+1+len(COND_LINES)]
    ins = i0 + 1
    for k, l in enumerate(NEW_TAIL):
        lines.insert(ins + k, "                    " + l)
    for j, l in enumerate(lines):
        if "r1381_since >= 10" in l:
            lines[j] = l.replace("r1381_since >= 10", "r1381_since >= 5")
            print("freeze 10s->5s updated")
            break
    else:
        print("FAIL-CLOSED: freeze line not found"); return 1
    open(path, "w").write("\n".join(lines))
    print("APPLIED: R1382 gate widened at the arm block (line %d)" % i0)
    return 0
sys.exit(apply_patch(sys.argv[1]))
PYEOF
if ! python3 /tmp/r1382_patch.py "$SRC"; then
  echo "APPLY-FAILED: shape gate refused - NOTHING applied, tree unchanged"
  exit 0
fi
echo "===POSTGATE454=== post-apply marker gates (explicit, full patterns)"
C1=$(grep -c -e "R1382 (c453)" "$SRC"); echo "R1382 marker: $C1 (expect 1)"
C2=$(grep -c -e "r1381_since >= 5" "$SRC"); echo "freeze-5s line: $C2 (expect 1)"
C3=$(grep -c -e "r1381_since >= 10" "$SRC"); echo "freeze-10s line: $C3 (expect 0)"
C4=$(grep -c -e "if (!r1381_fired" "$SRC"); echo "arm-gate intact: $C4 (expect 1)"
if [ "$C1" != "1" ] || [ "$C2" != "1" ] || [ "$C3" != "0" ] || [ "$C4" != "1" ]; then
  echo "GATE-FAILED: restoring baseline"; cp -p runtime/runtime.c.pre_r1382 "$SRC"; exit 0
fi
NEW=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "PATCHED_TREE_SHA=$NEW"
echo "===BUILD454=== compile the patched runtime (NO RUN - the run-only cycle follows)"
if ! ./run.sh build > /tmp/c454_build.txt 2>&1; then
  echo "BUILD-FAILED: restoring baseline"; tail -25 /tmp/c454_build.txt; cp -p runtime/runtime.c.pre_r1382 "$SRC"; exit 0
fi
echo "BUILD OK"
tail -3 /tmp/c454_build.txt
echo "--- tree shas:"
echo "baseline=8303add53da667af6f70a63ea433c12a8c59377fc87ec57eb4b50d0a461a4b29"
echo "patched=$NEW"
shasum -a 256 "$SRC" | cut -d" " -f1
echo "===PRESERVE454=== the receipts + build output"
D=$(mktemp -d "$PWD/c454_snap.XXXXXX") || { echo "SNAPSHOT-DIR-FAILED"; exit 0; }
cp -p /tmp/c454_receipts.txt "$D/c454_receipts.txt" && CP1=0 || CP1=1
cp -p /tmp/c454_build.txt "$D/c454_build.txt" && CP2=0 || CP2=1
cp -p runtime/runtime.c.pre_r1382 "$D/runtime.c.pre_r1382" && CP3=0 || CP3=1
echo "cp_rcs: $CP1 $CP2 $CP3"
ls -la "$D"
echo "===C454DONE=== R1382 landed + compiled - the NEXT cycle runs it (run-only 150s)"
