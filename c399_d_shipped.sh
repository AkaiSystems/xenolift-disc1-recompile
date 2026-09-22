#!/bin/bash
# c399_r1372.sh - THE R1372 PATCH+RUN CYCLE. The c398
# receipts NAME THE EXCLUDER: cd_read_active=1 is HELD
# throughout the system-ring walk (finstamp #860-873: the
# game's own fns arm FDF8=2048, advance FE04, drain FDF8 on
# timeout - all with act=1), so the R1371 door's !act term
# never passed. act=1 is the walk's OWN LIVE REQUEST (seek
# tracks FE04); the model owes it the sector - the on-demand
# load is starved by stale loaded/FIFO state. THIS PATCH:
# R1372 = the door v2 - drop the act term, and at the
# receipted posture (FDF8==2048, FE08 in the ring window
# aligned, FE04==slot, pend=0) FORCE the refresh: seek=FE04,
# loaded-flag reset, FIFO flush, then DIRECT cd_data_load() -
# the same-poll serve the door family has proven. One serve
# per FE08 slot. PASS = [R1372] serve receipts (slots 0..16),
# [cd] sector loads at LBA 0-16, the walk completing past the
# PVD, the CDFS mount finishing, the movie machinery, GPU/
# VRAM growth, the spin exiting. REVERT on regression.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C399-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="0697638566e5c1c24c2e6268b771aa3884aa649ff9d0b5d20520bf86fa13cc16"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1371 tree - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1371 tree)"
TS=$(date +%Y%m%d_%H%M%S)
PDIR="patch_c399_$TS"
mkdir -p "$PDIR"
cp -p "$SRC" "$PDIR/runtime.c.pre"
echo "PRESERVED: $PDIR/runtime.c.pre"
PRE_G1=$(grep -c "R1371 (c396): the SYSTEM-RING SERVE" "$SRC" || true)
PRE_G2=$(grep -c "slot_s, fe08_s, fe04_s, fe04_s);" "$SRC" || true)
PRE_G3=$(grep -c "R1372" "$SRC" || true)
PRE_G4=$(grep -c "if (!cd_read_active && !cd_pending" "$SRC" || true)
echo "PRE start-anchor count=$PRE_G1 (must be 1)"
echo "PRE end-anchor count=$PRE_G2 (must be 1)"
echo "PRE R1372 count=$PRE_G3 (must be 0)"
echo "PRE act-gate count=$PRE_G4 (post must be PRE-1: the door drops it, R1268 keeps its own)"
if [ "$PRE_G1" != "1" ] || [ "$PRE_G2" != "1" ] || [ "$PRE_G3" != "0" ]; then echo "PRE-GATE-FAILED: refusing, nothing done"; exit 0; fi
python3 - <<'PYEOF'
import sys
p = "runtime/runtime.c"
text = open(p).read()
lines = text.split("\n")
out = []
IND = " " * 8
START = "R1371 (c396): the SYSTEM-RING SERVE"
END = "slot_s, fe08_s, fe04_s, fe04_s);"
i = 0
e = 0
while i < len(lines):
    if START in lines[i]:
        j = i
        while j < len(lines) and END not in lines[j]:
            j += 1
        if j >= len(lines):
            print("ANCHOR-FAILED: span end not found"); sys.exit(1)
        new = []
        new.append(IND + "/* R1372 (c398): the SYSTEM-RING SERVE v2. The c398 receipts name the")
        new.append(IND + " * excluder: cd_read_active=1 is HELD throughout the walk (finstamp")
        new.append(IND + " * #860-873: the game's own fns arm FDF8=2048 (80041BA8), advance FE04")
        new.append(IND + " * and drain FDF8 on timeout (80041534), all with act=1) - v1 required")
        new.append(IND + " * !act and never fired. act=1 here is the walk's OWN LIVE REQUEST")
        new.append(IND + " * (seek tracks FE04 receipted); the model owes it the sector. At the")
        new.append(IND + " * receipted posture force the refresh: seek=FE04 (idempotent),")
        new.append(IND + " * data_loaded=0 + FIFO flush (kill the stale state that blocks the")
        new.append(IND + " * on-demand load), then DIRECT cd_data_load() - the same-poll serve")
        new.append(IND + " * the R1265/R1268 family uses. One serve per FE08 slot. */")
        new.append(IND + "{")
        new.append(IND + "    static uint32_t r1371_fired[32];")
        new.append(IND + "    uint32_t fe08_s = xenolift_mem_read32(0x8004FE08u);")
        new.append(IND + "    uint32_t fdf8_s = xenolift_mem_read32(0x8004FDF8u);")
        new.append(IND + "    uint32_t fe04_s = xenolift_mem_read32(0x8004FE04u);")
        new.append(IND + "    if (!cd_pending")
        new.append(IND + "        && fdf8_s == 2048u")
        new.append(IND + "        && fe08_s >= 0x801F3300u && fe08_s < 0x8020300u")
        new.append(IND + "        && ((fe08_s - 0x801F3300u) & 0x7FFu) == 0u) {")
        new.append(IND + "        uint32_t slot_s = (fe08_s - 0x801F3300u) >> 11;")
        new.append(IND + "        if (slot_s < 32u && fe04_s == slot_s && r1371_fired[slot_s] != fe08_s) {")
        new.append(IND + "            r1371_fired[slot_s] = fe08_s;")
        new.append(IND + "            cd_seek_lba = fe04_s;")
        new.append(IND + "            cd_read_active = 1; cd_data_loaded = 0;")
        new.append(IND + "            if (cd_scheduled) cd_scheduled = 0;")
        new.append(IND + "            if (cd_data_pos < cd_data_n) {")
        new.append(IND + '                r861_out("[R1371] stale-FIFO flush slot=%u data_n=%u data_pos=%u\\n",')
        new.append(IND + "                         slot_s, cd_data_n, cd_data_pos);")
        new.append(IND + "                cd_data_pos = cd_data_n = 0;")
        new.append(IND + "            }")
        new.append(IND + "            cd_data_load(); /* R1372: the direct same-poll serve - the on-demand path is blocked by the stale loaded/FIFO state */")
        new.append(IND + '            r861_out("[R1372] system-ring serve slot=%u FE08=%08X FE04=%u -> disc sector %u loaded (act=1 live walk request, loaded-flag reset, FIFO flushed), game drains\\n",')
        new.append(IND + "                     slot_s, fe08_s, fe04_s, fe04_s);")
        for nl in new:
            out.append(nl)
        i = j + 1
        e += 1
        continue
    out.append(lines[i])
    i += 1
if e != 1:
    print("ANCHOR-FAILED: edits %d (must be 1)" % e); sys.exit(1)
patched = "\n".join(out)
if patched.count("R1372") != 3:
    print("POST-FAILED: R1372 count %d (must be 3)" % patched.count("R1372")); sys.exit(1)
if patched.count("R1371") != 1:
    print("POST-FAILED: R1371 count %d (must be 1, the flush print)" % patched.count("R1371")); sys.exit(1)
if patched.count("cd_data_load(); /* R1372") != 1:
    print("POST-FAILED: direct load count != 1"); sys.exit(1)
if patched.count("if (!cd_read_active && !cd_pending") != text.count("if (!cd_read_active && !cd_pending") - 1:
    print("POST-FAILED: act-gate did not drop by exactly 1"); sys.exit(1)
open(p, "w").write(patched)
print("PATCH-APPLIED (R1372 system-ring serve v2: act dropped, direct same-poll load)")
PYEOF
if [ $? -ne 0 ]; then echo "PATCH-STEP-FAILED: nothing to run"; exit 0; fi
NEW_SHA=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_SHA=$NEW_SHA"
POST_G1=$(grep -c "R1372" "$SRC" || true)
POST_G2=$(grep -c "R1371" "$SRC" || true)
POST_G3=$(grep -c "cd_data_load(); /\* R1372" "$SRC" || true)
POST_G4=$(grep -c "if (!cd_read_active && !cd_pending" "$SRC" || true)
POST_EXPECT=$((PRE_G4-1))
echo "POST R1372 count=$POST_G1 (must be 3)"
echo "POST R1371 count=$POST_G2 (must be 1)"
echo "POST direct-load count=$POST_G3 (must be 1)"
echo "POST act-gate count=$POST_G4 (must be $POST_EXPECT = PRE-1)"
if [ "$POST_G1" != "3" ] || [ "$POST_G2" != "1" ] || [ "$POST_G3" != "1" ] || [ "$POST_G4" != "$POST_EXPECT" ]; then
  echo "POST-GATE-FAILED: restoring the pristine tree"
  cp -p "$PDIR/runtime.c.pre" "$SRC"
  echo "RESTORED"
  exit 0
fi
cc -fsyntax-only -std=gnu99 -Wno-implicit-function-declaration -Wno-int-conversion -Wno-constant-conversion -Wno-int-to-void-pointer-cast "$SRC" 2>/tmp/c399_parse_err.txt
PARSE_RC=$?
echo "PARSE_RC=$PARSE_RC"
if [ $PARSE_RC -ne 0 ]; then
  echo "PARSE-FAILED: restoring the pristine tree (fail-closed)"
  head -12 /tmp/c399_parse_err.txt
  cp -p "$PDIR/runtime.c.pre" "$SRC"
  echo "RESTORED"
  exit 0
fi
echo "PARSE-OK"
echo "===RUN399=== the R1372 build, 120s budget"
RUN_BUDGET_S=120 ./run.sh > /tmp/run_full_c399.txt 2>&1
RUN_RC=$?
echo "RUN_RC=$RUN_RC"
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
if [ ! -s "$LOG" ]; then
  echo "TREE-ROOT-LOG-MISSING: preserving run_full tail"
  tail -25 /tmp/run_full_c399.txt
  exit 0
fi
echo "AUTHORITATIVE LOG = $LOG ($(wc -l < "$LOG" | tr -d ' ') lines)"
echo "===R1372SERVE399=== the v2 serve receipts (expect slots 0..16)"
grep -n "R1372\]" "$LOG" | head -20
echo "===SECT16399=== the system-area sectors actually served (LBA 0-16)"
grep -n "sector LBA 16 \|sector LBA 1[0-5] \|sector LBA [0-9] loaded" "$LOG" | tail -12
echo "===DHW399=== the DATA HANDLER walk (progress past the park?)"
grep -n "bp\] DATA HANDLER" "$LOG" | tail -10
echo "===MOUNT399=== the CDFS mount (SelectArchive/new requests after the walk)"
grep -n "SelectArchive\|stab\] req" "$LOG" | tail -10
echo "===SPIN399=== the end spin (exit? new family?)"
grep -n "mvloop\]" "$LOG" | tail -4
echo "===MDEC399=== the MDEC receipts (movie decode?)"
grep -n "mdec\]" "$LOG" | tail -6
echo "===GPUVIS399=== the GPU/VRAM story"
grep -n "R694 live" "$LOG" | tail -3
grep -n "nonblank" "$LOG" | tail -3
echo "===EPOCH399=== the boot epochs"
grep -c "bootentry\] R710" "$LOG" || true
echo "===FAULTS399=== the fault census"
echo "computed-garbage $(grep -c "computed-garbage" "$LOG" || true)"
echo "lzss-runaway $(grep -c "lzss-runaway" "$LOG" || true)"
echo "===TAIL399=== the last 20 receipts"
TL=$(wc -l < "$LOG" | tr -d ' ')
S=$((TL-20)); [ $S -lt 1 ] && S=1
awk -v s="$S" -v e="$TL" 'NR>=s && NR<=e { print NR": "$0 }' "$LOG"
echo "===POSTSHA399==="
shasum -a 256 "$SRC" | cut -d' ' -f1
echo "===C399DONE=== the R1372 cycle is complete - the verdict comes from these receipts"
