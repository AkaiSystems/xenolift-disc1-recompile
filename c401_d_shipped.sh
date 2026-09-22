#!/bin/bash
# c401_r1373.sh - THE R1373 PATCH+RUN CYCLE. The c400
# receipts name the excluder: the R260 scheduled-response
# delivery is gated on g_movie_live (0 in the pre-movie era,
# player=0 receipts) - so the Setloc-109166's INT3, armed at
# sched=1 pend=0, is never delivered; the R955/R990 mvkick
# declines too (requires act=1, FDF8!=0, sched=0). THIS
# PATCH: R1373 = a sibling delivery block inside the mvloop,
# the proven R260 composite (cd_restore_pend, sched clear,
# pend=3 + stamp site 5, op flag, cd_force_deliver_int1),
# scoped to the EXACT receipted stuck posture (!g_movie_live,
# last_cmd=02, fe1c=1, sched=1, pend=0, FDF8=0) so the
# working chain is untouched (the R990 stuck-shape lesson).
# PASS = [R1373] delivery receipts + FE1C moving past 1 +
# the spin exiting (n stops growing) + the movie machinery
# (MDEC decode beyond reset, the 239xxx band stream) +
# GPU/VRAM growth + new requests. REVERT on regression.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C401-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="6342434936dcbdbd45e922cc05a72f3ab159225b87cd0d78d2e7ddaf3751d0a6"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1372 tree - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1372 tree)"
TS=$(date +%Y%m%d_%H%M%S)
PDIR="patch_c401_$TS"
mkdir -p "$PDIR"
cp -p "$SRC" "$PDIR/runtime.c.pre"
echo "PRESERVED: $PDIR/runtime.c.pre"
PRE_G1=$(grep -c "R955 \[mvkick\] (ATLAS lane, b8-c64 receipts): the pre-movie" "$SRC" || true)
PRE_G2=$(grep -c "R1373" "$SRC" || true)
PRE_G3=$(grep -c "(mv_n & 0x1FFu) == 0x100u" "$SRC" || true)
echo "PRE anchor count=$PRE_G1 (must be 1)"
echo "PRE R1373 count=$PRE_G2 (must be 0)"
echo "PRE 1ff-100 count=$PRE_G3 (post must be PRE+1)"
if [ "$PRE_G1" != "1" ] || [ "$PRE_G2" != "0" ]; then echo "PRE-GATE-FAILED: refusing, nothing done"; exit 0; fi
python3 - <<'PYEOF'
import sys
p = "runtime/runtime.c"
text = open(p).read()
pre_1ff = text.count("(mv_n & 0x1FFu) == 0x100u")
lines = text.split("\n")
out = []
e = 0
I16 = " " * 16
ANCHOR = "R955 [mvkick] (ATLAS lane, b8-c64 receipts): the pre-movie"
for l in lines:
    if ANCHOR in l:
        new = []
        new.append(I16 + "/* R1373 (c400): the movie-era scheduled-response delivery. The c399")
        new.append(I16 + " * receipts: the pre-movie poll parks at FE1C=1 with last_cmd=02 (Setloc")
        new.append(I16 + " * 109166), sched=1, pend=0, FDF8=0, player=0 - the Setloc's INT3 is")
        new.append(I16 + " * scheduled but the R260 delivery is gated on g_movie_live (0 in this")
        new.append(I16 + " * era) and the kernel collector contexts the movie loop never visits.")
        new.append(I16 + " * Same hardware rationale as R260: IRQs preempt anywhere. Scoped to")
        new.append(I16 + " * the EXACT stuck posture (last_cmd=02, fe1c=1, sched=1, pend=0,")
        new.append(I16 + " * FDF8=0) so the working chain is untouched (the R990 stuck-shape")
        new.append(I16 + " * lesson). Same composite as R260: restore_pend, sched clear, pend=3")
        new.append(I16 + " * + stamp, op flag, force-deliver. */")
        new.append(I16 + "if (!g_movie_live && (mv_n & 0x1FFu) == 0x100u && cd_scheduled")
        new.append(I16 + "    && cd_pending == 0u && cd_last_cmd == 0x02u")
        new.append(I16 + "    && xenolift_mem_read32(0x8004FE1Cu) == 1u")
        new.append(I16 + "    && xenolift_mem_read32(0x8004FDF8u) == 0u) {")
        new.append(I16 + "    static uint32_t r1373_n;")
        new.append(I16 + "    cd_restore_pend(); /* the saved multi-byte Setloc answer, R308 central */")
        new.append(I16 + "    cd_scheduled = 0;")
        new.append(I16 + "    cd_pending = 3; cd_pending_stamp(3u, 5u);")
        new.append(I16 + "    if (!cd_flag_suppressed(cd_last_cmd)) {")
        new.append(I16 + "        uint16_t one = 1;")
        new.append(I16 + "        memcpy(xenolift_mem + (0x800578A6u & 0x1FFFFFFFu), &one, 2);")
        new.append(I16 + "    }")
        new.append(I16 + "    if (++r1373_n <= 16u || (r1373_n % 64u) == 0u)")
        new.append(I16 + '        r861_out("[R1373] movie-era scheduled INT3 delivered from mvloop #%u: cmd 0x%02X seq=%u seek=%u fe1c=%u (the R260 composite at the receipted stuck posture, player=0 era)\\n",')
        new.append(I16 + "                 r1373_n, cd_last_cmd, cd_sched_seq, cd_seek_lba, xenolift_mem_read32(0x8004FE1Cu));")
        new.append(I16 + '    cd_force_deliver_int1("mvloop-r1373");')
        new.append(I16 + "}")
        for n in new:
            out.append(n)
        out.append(l)
        e += 1
        continue
    out.append(l)
if e != 1:
    print("ANCHOR-FAILED: edits %d (must be 1)" % e); sys.exit(1)
patched = "\n".join(out)
if patched.count("R1373") != 2:
    print("POST-FAILED: R1373 count %d (must be 2)" % patched.count("R1373")); sys.exit(1)
if patched.count("(mv_n & 0x1FFu) == 0x100u") != pre_1ff + 1:
    print("POST-FAILED: 1ff-100 delta != 1"); sys.exit(1)
if patched.count("mvloop-r1373") != 1:
    print("POST-FAILED: deliver tag != 1"); sys.exit(1)
open(p, "w").write(patched)
print("PATCH-APPLIED (R1373 movie-era scheduled-response delivery)")
PYEOF
if [ $? -ne 0 ]; then echo "PATCH-STEP-FAILED: nothing to run"; exit 0; fi
NEW_SHA=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_SHA=$NEW_SHA"
POST_G1=$(grep -c "R1373" "$SRC" || true)
POST_G2=$(grep -c "(mv_n & 0x1FFu) == 0x100u" "$SRC" || true)
POST_G3=$(grep -c "mvloop-r1373" "$SRC" || true)
POST_EXPECT=$((PRE_G3+1))
echo "POST R1373 count=$POST_G1 (must be 2)"
echo "POST 1ff-100 count=$POST_G2 (must be $POST_EXPECT = PRE+1)"
echo "POST deliver count=$POST_G3 (must be 1)"
if [ "$POST_G1" != "2" ] || [ "$POST_G2" != "$POST_EXPECT" ] || [ "$POST_G3" != "1" ]; then
  echo "POST-GATE-FAILED: restoring the pristine tree"
  cp -p "$PDIR/runtime.c.pre" "$SRC"
  echo "RESTORED"
  exit 0
fi
cc -fsyntax-only -std=gnu99 -Wno-implicit-function-declaration -Wno-int-conversion -Wno-constant-conversion -Wno-int-to-void-pointer-cast "$SRC" 2>/tmp/c401_parse_err.txt
PARSE_RC=$?
echo "PARSE_RC=$PARSE_RC"
if [ $PARSE_RC -ne 0 ]; then
  echo "PARSE-FAILED: restoring the pristine tree (fail-closed)"
  head -12 /tmp/c401_parse_err.txt
  cp -p "$PDIR/runtime.c.pre" "$SRC"
  echo "RESTORED"
  exit 0
fi
echo "PARSE-OK"
echo "===RUN401=== the R1373 build, 120s budget"
RUN_BUDGET_S=120 ./run.sh > /tmp/run_full_c401.txt 2>&1
RUN_RC=$?
echo "RUN_RC=$RUN_RC"
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
if [ ! -s "$LOG" ]; then
  echo "TREE-ROOT-LOG-MISSING: preserving run_full tail"
  tail -25 /tmp/run_full_c401.txt
  exit 0
fi
echo "AUTHORITATIVE LOG = $LOG ($(wc -l < "$LOG" | tr -d ' ') lines)"
echo "===R1373DEL401=== the delivery receipts"
grep -n "R1373\]" "$LOG" | head -18
echo "===FE1C401=== the FE1C transitions after delivery (past 1?)"
grep -n "finstamp\|actchg" "$LOG" | awk -F: '$1>=31000' | head -12
echo "===SPIN401=== the end spin (exit? n stopped? new family?)"
grep -n "mvloop\]" "$LOG" | tail -4
echo "===MDEC401=== the MDEC receipts (decode beyond reset?)"
grep -n "mdec\]" "$LOG" | tail -8
echo "===SECT401=== the movie-band stream (239xxx sectors?)"
grep -n "sector LBA 239" "$LOG" | tail -8
echo "===GPUVIS401=== the GPU/VRAM story"
grep -n "R694 live" "$LOG" | tail -3
grep -n "nonblank" "$LOG" | tail -3
echo "===EPOCH401=== the boot epochs"
grep -c "bootentry\] R710" "$LOG" || true
echo "===FAULTS401=== the fault census"
echo "computed-garbage $(grep -c "computed-garbage" "$LOG" || true)"
echo "lzss-runaway $(grep -c "lzss-runaway" "$LOG" || true)"
echo "===TAIL401=== the last 20 receipts"
TL=$(wc -l < "$LOG" | tr -d ' ')
S=$((TL-20)); [ $S -lt 1 ] && S=1
awk -v s="$S" -v e="$TL" 'NR>=s && NR<=e { print NR": "$0 }' "$LOG"
echo "===POSTSHA401==="
shasum -a 256 "$SRC" | cut -d' ' -f1
echo "===C401DONE=== the R1373 cycle is complete - the verdict comes from these receipts"
