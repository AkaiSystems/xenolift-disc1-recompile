#!/bin/bash
# c395_r1370.sh - THE R1370 PATCH+RUN CYCLE. The c394
# anatomy: the CDFS remount walks the ring (DATA HANDLER at
# FE08=801F3300+slot*0x800, FE04==slot 0..7 receipted,
# FDF8=2048 armed per slot) with EVERY SLOT STARVING
# (dstw0=0), then parks at FE04=16 (the ISO9660 PVD) with
# FDF8=2048 armed, sched=1, pend=0, FE1C=6 - and the DECLINE
# section is empty: the block never enters, no serve arm
# even evaluated. The contract is proven (R1269: the
# disc-start sectors ARE slot==LBA; c152: drop the stale
# sched term, clear it on serve). THIS PATCH: (1) the
# system-ring entry arm in the outer group (FDF8==2048,
# FE04<0x40, drive idle); (2) the serve door inside the
# block: seek=FE04, read_active=1, data_loaded=0, stale
# sched cleared, budget-12 camera - the game's own fetch
# drains the ring. PASS = serve receipts (slots 0..16+), the
# ring walk completing (FE04 past 16, FDF8 cycling 2048->0),
# the CDFS mount completing (new file-lookup requests), the
# movie stream serving, GPU/VRAM growth, the spin exiting.
# REVERT on regression. Tree sha-gated on the R1369
# baseline e918ef86.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C395-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="e918ef8605b0c80533c4aa06356fa0fdb6c034fd9fe9e24517a1d1200d09394a"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1369 tree - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1369 tree)"
TS=$(date +%Y%m%d_%H%M%S)
PDIR="patch_c395_$TS"
mkdir -p "$PDIR"
cp -p "$SRC" "$PDIR/runtime.c.pre"
echo "PRESERVED: $PDIR/runtime.c.pre"
PRE_G1=$(grep -c "xenolift_mem_read32(0x8004FDF8u) == 0u && !cd_read_active && !cd_scheduled && !cd_pending))" "$SRC" || true)
PRE_G2=$(grep -c "stale-empty entry #%u: a=%08X FE1C=%u" "$SRC" || true)
PRE_G3=$(grep -c "R1370" "$SRC" || true)
PRE_G4=$(grep -c "system-ring serve #%u" "$SRC" || true)
PRE_G5=$(grep -c "0x8004FE04u) < 0x40u" "$SRC" || true)
echo "PRE arm-anchor count=$PRE_G1 (must be 1)"
echo "PRE camera-anchor count=$PRE_G2 (must be 1)"
echo "PRE R1370 count=$PRE_G3 (must be 0)"
echo "PRE door-text count=$PRE_G4 (must be 0)"
echo "PRE fe04-40 count=$PRE_G5 (post must be PRE+1)"
if [ "$PRE_G1" != "1" ] || [ "$PRE_G2" != "1" ] || [ "$PRE_G3" != "0" ] || [ "$PRE_G4" != "0" ]; then echo "PRE-GATE-FAILED: refusing, nothing done"; exit 0; fi
python3 - <<'PYEOF'
import sys
p = "runtime/runtime.c"
text = open(p).read()
pre_fe04_40 = text.count("0x8004FE04u) < 0x40u")
lines = text.split("\n")
out = []
e1 = 0
e2 = 0
IND = " " * 8
ARM_TAIL = "xenolift_mem_read32(0x8004FDF8u) == 0u && !cd_read_active && !cd_scheduled && !cd_pending))"
for l in lines:
    if ARM_TAIL in l:
        new_tail = ("xenolift_mem_read32(0x8004FDF8u) == 0u && !cd_read_active && !cd_scheduled && !cd_pending)"
                    " /* R1370 (c394): the system-ring entry arm - the CDFS remount walk receipts FE04==slot 0..7 at FE08 801F3300+slot*0x800 with FDF8=2048 armed and every slot starving (dstw0=0), then parks at FE04=16 (the ISO9660 PVD) with nothing serving; the boot ladder proved the disc-start sectors ARE slot==LBA */"
                    " || (xenolift_mem_read32(0x8004FDF8u) == 2048u && xenolift_mem_read32(0x8004FE04u) < 0x40u && !cd_read_active && !cd_pending))")
        l = l.replace(ARM_TAIL, new_tail, 1)
        out.append(l)
        e1 += 1
        continue
    if "stale-empty entry #%u: a=%08X FE1C=%u" in l:
        out.append(l)
        out.append(IND + "/* R1370 (c394): the system-ring/PVD serve door - serve the disc sector FE04 on demand")
        out.append(IND + " * (the disc-start sectors ARE slot==LBA, R1269-receipted) and let the game's own fetch")
        out.append(IND + " * drain the ring; the sched term is DROPPED (R1269/c152 lesson: stale sched blocks the")
        out.append(IND + " * door) and the stale sched is CLEARED on serve so it stops blocking downstream arms. */")
        out.append(IND + "{")
        out.append(IND + "    uint32_t r1370_fdf8 = xenolift_mem_read32(0x8004FDF8u);")
        out.append(IND + "    uint32_t r1370_fe04 = xenolift_mem_read32(0x8004FE04u);")
        out.append(IND + "    if (r1370_fdf8 == 2048u && r1370_fe04 < 0x40u && !cd_read_active && !cd_pending) {")
        out.append(IND + "        cd_seek_lba = r1370_fe04;")
        out.append(IND + "        cd_read_active = 1; cd_data_loaded = 0;")
        out.append(IND + "        if (cd_scheduled) cd_scheduled = 0;")
        out.append(IND + "        { static uint32_t r1370_n;")
        out.append(IND + "          if (r1370_n < 12u) { r1370_n++;")
        out.append(IND + '            r861_out("[R1370] system-ring serve #%u: FE04=%u FDF8=%u FE08=%08X FE1C=%u - serving disc sector %u on demand, sched cleared\\n",')
        out.append(IND + "                    r1370_n, r1370_fe04, r1370_fdf8, xenolift_mem_read32(0x8004FE08u), xenolift_mem_read32(0x8004FE1Cu), r1370_fe04); } }")
        out.append(IND + "    }")
        out.append(IND + "}")
        e2 += 1
        continue
    out.append(l)
if e1 != 1 or e2 != 1:
    print("ANCHOR-FAILED: edits %d/%d (must be 1/1)" % (e1, e2)); sys.exit(1)
patched = "\n".join(out)
if patched.count("R1370") != 3:
    print("POST-FAILED: R1370 count %d (must be 3)" % patched.count("R1370")); sys.exit(1)
if patched.count("system-ring serve #%u") != 1:
    print("POST-FAILED: door count != 1"); sys.exit(1)
if patched.count("0x8004FE04u) < 0x40u") != pre_fe04_40 + 1:
    print("POST-FAILED: arm delta != 1 (pre=%d post=%d)" % (pre_fe04_40, patched.count("0x8004FE04u) < 0x40u"))); sys.exit(1)
open(p, "w").write(patched)
print("PATCH-APPLIED (R1370 system-ring entry arm + serve door)")
PYEOF
if [ $? -ne 0 ]; then echo "PATCH-STEP-FAILED: nothing to run"; exit 0; fi
NEW_SHA=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_SHA=$NEW_SHA"
POST_G1=$(grep -c "R1370" "$SRC" || true)
POST_G2=$(grep -c "system-ring serve #%u" "$SRC" || true)
POST_G3=$(grep -c "0x8004FE04u) < 0x40u" "$SRC" || true)
POST_EXPECT=$((PRE_G5+1))
echo "POST R1370 count=$POST_G1 (must be 3)"
echo "POST door count=$POST_G2 (must be 1)"
echo "POST arm count=$POST_G3 (must be $POST_EXPECT = PRE+1)"
if [ "$POST_G1" != "3" ] || [ "$POST_G2" != "1" ] || [ "$POST_G3" != "$POST_EXPECT" ]; then
  echo "POST-GATE-FAILED: restoring the pristine tree"
  cp -p "$PDIR/runtime.c.pre" "$SRC"
  echo "RESTORED"
  exit 0
fi
cc -fsyntax-only -std=gnu99 -Wno-implicit-function-declaration -Wno-int-conversion -Wno-constant-conversion -Wno-int-to-void-pointer-cast "$SRC" 2>/tmp/c395_parse_err.txt
PARSE_RC=$?
echo "PARSE_RC=$PARSE_RC"
if [ $PARSE_RC -ne 0 ]; then
  echo "PARSE-FAILED: restoring the pristine tree (fail-closed)"
  head -12 /tmp/c395_parse_err.txt
  cp -p "$PDIR/runtime.c.pre" "$SRC"
  echo "RESTORED"
  exit 0
fi
echo "PARSE-OK"
echo "===RUN395=== the R1370 build, 120s budget"
RUN_BUDGET_S=120 ./run.sh > /tmp/run_full_c395.txt 2>&1
RUN_RC=$?
echo "RUN_RC=$RUN_RC"
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
if [ ! -s "$LOG" ]; then
  echo "TREE-ROOT-LOG-MISSING: preserving run_full tail"
  tail -25 /tmp/run_full_c395.txt
  exit 0
fi
echo "AUTHORITATIVE LOG = $LOG ($(wc -l < "$LOG" | tr -d ' ') lines)"
echo "===R1370SERVE395=== the serve receipts (the ring slots + the PVD)"
grep -n "R1370\]" "$LOG" | head -14
echo "===RINGWALK395=== the ring walk completion (FE04 past 16? FDF8 cycling?)"
grep -n "bp\] DATA HANDLER" "$LOG" | awk -F: '$1>=29900' | head -14
echo "===SECT16395=== the system-area sectors actually served (LBA 0-16)"
grep -n "sector LBA 16 \|sector LBA 1[0-5] \|sector LBA [0-9] " "$LOG" | tail -10
echo "===MOUNT395=== the CDFS mount completion (new file lookups? stab/ftab requests?)"
grep -n "stab\] req\|READ ISSUED\|SelectArchive" "$LOG" | awk -F: '$1>=29900' | head -12
echo "===SPIN395=== the end spin (did it exit? n stopped? new loop family?)"
grep -n "mvloop\]" "$LOG" | tail -4
echo "===MDEC395=== the MDEC receipts (movie decode?)"
grep -n "mdec\]" "$LOG" | tail -6
echo "===GPUVIS395=== the GPU/VRAM story"
grep -n "R694 live" "$LOG" | tail -3
grep -n "R693 vram_nonzero\|nonblank" "$LOG" | tail -3
echo "===EPOCH395=== the boot epochs"
grep -c "bootentry\] R710" "$LOG" || true
echo "===FAULTS395=== the fault census"
echo "computed-garbage $(grep -c "computed-garbage" "$LOG" || true)"
echo "lzss-runaway $(grep -c "lzss-runaway" "$LOG" || true)"
echo "===TAIL395=== the last 20 receipts"
TL=$(wc -l < "$LOG" | tr -d ' ')
S=$((TL-20)); [ $S -lt 1 ] && S=1
awk -v s="$S" -v e="$TL" 'NR>=s && NR<=e { print NR": "$0 }' "$LOG"
echo "===POSTSHA395==="
shasum -a 256 "$SRC" | cut -d' ' -f1
echo "===C395DONE=== the R1370 cycle is complete - the verdict comes from these receipts"
