#!/bin/bash
# c393_r1369.sh - THE R1369 PATCH+RUN CYCLE. The c392
# extraction: the conversion block's outer condition needs
# pend!=0/kicks/the R1365 sched-arm, so the end-of-run
# pre-movie spin (pend=0 sched=0, FE1C=6, FDF8=0, drive
# idle) never enters and the fd-retire release (12 receipted
# fires incl. FE1C=6->0, all 'no length, drive idle') never
# runs - the spin's exit contract (ret=0+FDFC=0+FE1C=0)
# holds everything but FE1C. THIS PATCH: ONE arm in the
# outer group - (FE1C==6 && FDF8==0 && !act && !sched &&
# !pend) - letting the block enter at the spin's matched
# contexts (80042A58 / 80041410+80028704) so the inner
# fd-retire gate decides; plus a budget-8 entry camera.
# PASS = entry receipts + a late fd-retire FE1C=6->0 + the
# mvloop n stops growing + the post-exit walk (movie start?
# MDEC? Setmode 0x80? new LBAs? GPU beyond 944,490 words).
# REVERT on regression. Tree sha-gated on the R1368
# baseline 456a8dcd.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C393-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="456a8dcd3e3987a3ff79b490133d5ff63c6f1f2961dfbd6d9b336d945da7e141"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1368 tree - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1368 tree)"
TS=$(date +%Y%m%d_%H%M%S)
PDIR="patch_c393_$TS"
mkdir -p "$PDIR"
cp -p "$SRC" "$PDIR/runtime.c.pre"
echo "PRESERVED: $PDIR/runtime.c.pre"
PRE_G1=$(grep -c "g_r1351_genuine_answer)) /\* R1365 (c365):" "$SRC" || true)
PRE_G2=$(grep -c "budgeted entry camera - a zrf no-fire names the excluding gate" "$SRC" || true)
PRE_G3=$(grep -c "R1369" "$SRC" || true)
PRE_G4=$(grep -c "stale-empty entry" "$SRC" || true)
echo "PRE outer-anchor count=$PRE_G1 (must be 1)"
echo "PRE camera-anchor count=$PRE_G2 (must be 1)"
echo "PRE R1369 count=$PRE_G3 (must be 0)"
echo "PRE cam-text count=$PRE_G4 (must be 0)"
if [ "$PRE_G1" != "1" ] || [ "$PRE_G2" != "1" ] || [ "$PRE_G3" != "0" ] || [ "$PRE_G4" != "0" ]; then echo "PRE-GATE-FAILED: refusing, nothing done"; exit 0; fi
python3 - <<'PYEOF'
import sys
p = "runtime/runtime.c"
text = open(p).read()
lines = text.split("\n")
out = []
i = 0
e1 = 0
e2 = 0
IND = " " * 8
while i < len(lines):
    l = lines[i]
    if "g_r1351_genuine_answer)) /* R1365 (c365):" in l:
        l2 = l.replace(
            "g_r1351_genuine_answer))",
            "g_r1351_genuine_answer) /* R1369 (c392): the stale-empty-request entry arm - the c391/c392 receipts: the end-of-run pre-movie spin holds FE1C=6 with FDF8=0 and the drive idle, and the fd-retire release (12 receipted fires incl. FE1C=6->0) cannot reach it because this outer needed pend/kicks/sched; a no-length idle request has nothing to wait for - let the block enter and the inner fd-retire gate decide */ || (xenolift_mem_read32(0x8004FE1Cu) == 6u && xenolift_mem_read32(0x8004FDF8u) == 0u && !cd_read_active && !cd_scheduled && !cd_pending))",
            1)
        if l2 == l:
            print("ANCHOR-FAILED: outer replace no-op at %d" % i); sys.exit(1)
        out.append(l2)
        e1 += 1
        i += 1
        continue
    if "budgeted entry camera - a zrf no-fire names the excluding gate" in l:
        out.append(l)
        out.append(IND + "/* R1369 (c392): the entry camera - receipts each entry the new arm admitted */")
        out.append(IND + "{ static uint32_t r1369_n; if (r1369_n < 8u && !cd_read_active && !cd_scheduled && !cd_pending && xenolift_mem_read32(0x8004FDF8u) == 0u) { r1369_n++;")
        out.append(IND + '  r861_out("[R1369] stale-empty entry #%u: a=%08X FE1C=%u - the fd-retire gate decides next\\n", r1369_n, a, xenolift_mem_read32(0x8004FE1Cu)); } }')
        e2 += 1
        i += 1
        continue
    out.append(l)
    i += 1
if e1 != 1 or e2 != 1:
    print("ANCHOR-FAILED: edits %d/%d (must be 1/1)" % (e1, e2)); sys.exit(1)
patched = "\n".join(out)
if patched.count("R1369") != 3:
    print("POST-FAILED: R1369 count %d (must be 3)" % patched.count("R1369")); sys.exit(1)
if patched.count("0x8004FE1Cu) == 6u") != 1:
    print("POST-FAILED: arm count != 1"); sys.exit(1)
if patched.count("stale-empty entry") != 1:
    print("POST-FAILED: camera count != 1"); sys.exit(1)
open(p, "w").write(patched)
print("PATCH-APPLIED (R1369 stale-empty entry arm + camera)")
PYEOF
if [ $? -ne 0 ]; then echo "PATCH-STEP-FAILED: nothing to run"; exit 0; fi
NEW_SHA=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_SHA=$NEW_SHA"
POST_G1=$(grep -c "R1369" "$SRC" || true)
POST_G2=$(grep -c "0x8004FE1Cu) == 6u" "$SRC" || true)
POST_G3=$(grep -c "stale-empty entry" "$SRC" || true)
echo "POST R1369 count=$POST_G1 (must be 3)"
echo "POST arm count=$POST_G2 (must be 1)"
echo "POST camera count=$POST_G3 (must be 1)"
if [ "$POST_G1" != "3" ] || [ "$POST_G2" != "1" ] || [ "$POST_G3" != "1" ]; then
  echo "POST-GATE-FAILED: restoring the pristine tree"
  cp -p "$PDIR/runtime.c.pre" "$SRC"
  echo "RESTORED"
  exit 0
fi
cc -fsyntax-only -std=gnu99 -Wno-implicit-function-declaration -Wno-int-conversion -Wno-constant-conversion -Wno-int-to-void-pointer-cast "$SRC" 2>/tmp/c393_parse_err.txt
PARSE_RC=$?
echo "PARSE_RC=$PARSE_RC"
if [ $PARSE_RC -ne 0 ]; then
  echo "PARSE-FAILED: restoring the pristine tree (fail-closed)"
  head -12 /tmp/c393_parse_err.txt
  cp -p "$PDIR/runtime.c.pre" "$SRC"
  echo "RESTORED"
  exit 0
fi
echo "PARSE-OK"
echo "===RUN393=== the R1369 build, 120s budget"
RUN_BUDGET_S=120 ./run.sh > /tmp/run_full_c393.txt 2>&1
RUN_RC=$?
echo "RUN_RC=$RUN_RC"
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
if [ ! -s "$LOG" ]; then
  echo "TREE-ROOT-LOG-MISSING: preserving run_full tail"
  tail -25 /tmp/run_full_c393.txt
  exit 0
fi
echo "AUTHORITATIVE LOG = $LOG ($(wc -l < "$LOG" | tr -d ' ') lines)"
echo "===R1369GUARD393=== the entry receipts (the new arm admitting the spin)"
grep -n "R1369" "$LOG" | head -10
echo "===FDRETIRE393=== every fd-retire fire (expect a LATE FE1C=6->0 at the end posture)"
grep -n "fd-retire" "$LOG" | tail -8
echo "===FE1CRET393=== the FE1C=6 retirement window (the last chg/receipts at FE1C)"
grep -n "chg\] FE1C 0006->0000\|FE1C 0006 -> 0" "$LOG" | tail -6
echo "===MVEXIT393=== did the pre-movie spin exit? (n stops growing / loop-id changes)"
grep -n "mvloop\]" "$LOG" | tail -6
echo "===WALK393=== the post-exit walk (movie start? MDEC? Setmode? new LBAs?)"
grep -n "Setmode\|mdec\]" "$LOG" | tail -10
grep -n "cmdtl\] R533" "$LOG" | tail -10
echo "===SECT393=== the movie-band serves (2393xx sectors after the release)"
grep -n "sector LBA 2393" "$LOG" | tail -8
echo "count: $(grep -c "sector LBA 2393" "$LOG" || true)"
echo "===EPOCH393=== the boot epoch count"
grep -c "bootentry\] R710" "$LOG" || true
grep -n "fn_80019ACC error-dispatcher" "$LOG" | head -3
echo "===GPUVIS393=== the GPU/screen story (beyond 944,490 words?)"
grep -n "R694 live" "$LOG" | tail -3
grep -n "R693 snap\|vram_nonzero" "$LOG" | tail -3
echo "===FAULTS393=== the fault census"
echo "computed-garbage $(grep -c "computed-garbage" "$LOG" || true)"
echo "lzss-runaway $(grep -c "lzss-runaway" "$LOG" || true)"
echo "segvdie $(grep -c "segvdie" "$LOG" || true)"
echo "===TAIL393=== the last 20 receipts"
TL=$(wc -l < "$LOG" | tr -d ' ')
S=$((TL-20)); [ $S -lt 1 ] && S=1
awk -v s="$S" -v e="$TL" 'NR>=s && NR<=e { print NR": "$0 }' "$LOG"
echo "===POSTSHA393==="
shasum -a 256 "$SRC" | cut -d' ' -f1
echo "===C393DONE=== the R1369 cycle is complete - the verdict comes from these receipts"
