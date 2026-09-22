#!/bin/bash
# c406_r1375.sh - THE R1375 PATCH+RUN CYCLE (generalized
# delivery). THE STRUCTURAL FACT (three runs, receipted):
# the follow-up command after the file#18 stream (Setloc
# at fe1c=1 in c399/c405, ReadN at fe1c=0 in c401) gets
# its INT3 scheduled and it NEVER delivers at the
# movie-loop contexts (R260 is g_movie_live-gated OFF in
# this era; the loop never visits the kernel collector
# contexts). Per-posture scoping over-fit single-run
# shapes. THE REPAIR (Jos's durable gate): deliver on the
# STRUCTURAL INVARIANT - !g_movie_live && sched && pend==0
# at the 512-pass cadence, ANY command shape - with the
# ANSWER-OWNERSHIP gate (multi-byte answers only, the save
# site 2226 adjacent to the schedule site 2236) and the
# full identity dossier (seq, cmd, ans_cmd, resp bytes,
# fe1c, fdf8, restore verdict). PASS = the dossier + guest
# consumption (pendclr/rspop, no repeat-reappearance) + the
# wait genuinely releasing (a NEW poll family, not a frozen
# counter) + downstream reads + MDEC decode beyond reset.
# ANY FAILURE = REVERT (pivot to visibility-based
# delivery). Fail-closed pre/post gates + tolerant parse
# gate, tree sha-gated on the R1374 baseline.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C406-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="bec84efbfde796e15107d07e9e28fa6a6062b9cd6e815ebcd17026c444170a15"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1374 tree - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1374 tree)"
TS=$(date +%Y%m%d_%H%M%S)
PDIR="patch_c406_$TS"
mkdir -p "$PDIR"
cp -p "$SRC" "$PDIR/runtime.c.pre"
echo "PRESERVED: $PDIR/runtime.c.pre"
PRE_G1=$(grep -c "R1374" "$SRC" || true)
PRE_G2=$(grep -c "mvloop-r1374" "$SRC" || true)
PRE_G3=$(grep -c "R1375" "$SRC" || true)
echo "PRE R1374 count=$PRE_G1 (must be 2, the shipped block)"
echo "PRE mvloop-r1374 count=$PRE_G2 (must be 1)"
echo "PRE R1375 count=$PRE_G3 (must be 0)"
if [ "$PRE_G1" != "2" ] || [ "$PRE_G2" != "1" ] || [ "$PRE_G3" != "0" ]; then echo "PRE-GATE-FAILED: refusing, nothing done"; exit 0; fi
python3 - <<'PYEOF'
import sys
p = "runtime/runtime.c"
text = open(p).read()
lines = text.split("\n")
out = []
I16 = " " * 16
START = "R1374 (c403): the movie-era scheduled-response delivery v2"
END = 'cd_force_deliver_int1("mvloop-r1374");'
i = 0; e = 0
while i < len(lines):
    if START in lines[i]:
        j = i
        while j < len(lines) and END not in lines[j]:
            j += 1
        if j + 1 >= len(lines) or lines[j+1].strip() != "}":
            print("ANCHOR-FAILED: span end/brace not found"); sys.exit(1)
        new = []
        new.append(I16 + "/* R1375 (c405): the movie-era scheduled-response delivery, GENERALIZED.")
        new.append(I16 + " * Three runs receipt the same structural strand at three postures: the")
        new.append(I16 + " * follow-up command after the file#18 stream (Setloc c399/c405 at fe1c=1,")
        new.append(I16 + " * ReadN c401 at fe1c=0) gets its INT3 scheduled (the single site 2236,")
        new.append(I16 + " * line-adjacent to the R307 save) and it NEVER delivers at the")
        new.append(I16 + " * movie-loop contexts (R260 is g_movie_live-gated OFF in this era; the")
        new.append(I16 + " * loop never visits the kernel collector contexts - receipted). The")
        new.append(I16 + " * per-posture scoping was over-fit to single-run shapes; the durable")
        new.append(I16 + " * gate (Jos): the STRUCTURAL INVARIANT - a scheduled response with")
        new.append(I16 + " * pending=0 held across many loop passes in the pre-movie era. Gate =")
        new.append(I16 + " * !g_movie_live && sched && pend==0 at the 512-pass cadence, for ANY")
        new.append(I16 + " * command shape. The ANSWER-OWNERSHIP gate stays (multi-byte answers")
        new.append(I16 + " * only; the dossier prints seq/cmd/ans_cmd/resp bytes/fe1c/fdf8 so the")
        new.append(I16 + " * receipts judge the delivered instance). The [firstfault] R1179 prints")
        new.append(I16 + " * (print-budget capped) + the h4 dispatch receipts expose whether the")
        new.append(I16 + " * delivery engine can consume under the stop discipline. PASS =")
        new.append(I16 + " * consumption (pendclr/rspop, no repeat-reappearance) + the wait")
        new.append(I16 + " * genuinely releasing (a NEW poll family, not a frozen counter) +")
        new.append(I16 + " * downstream reads/MDEC decode beyond reset. ANY FAILURE = REVERT (the")
        new.append(I16 + " * pivot is visibility-based delivery). */")
        new.append(I16 + "if (!g_movie_live && (mv_n & 0x1FFu) == 0x100u && cd_scheduled")
        new.append(I16 + "    && cd_pending == 0u) {")
        new.append(I16 + "    static uint32_t r1375_n;")
        new.append(I16 + "    int restored = (cd_pend_ans_n > 0u && cd_pend_ans_cmd == cd_last_cmd);")
        new.append(I16 + "    if (restored) cd_restore_pend(); /* ownership-proven: the answer saved at THIS command's schedule (site 2226/2236 adjacency) */")
        new.append(I16 + "    if (++r1375_n <= 16u || (r1375_n % 64u) == 0u)")
        new.append(I16 + '        r861_out("[R1375] movie-era scheduled-response delivery #%u: cmd 0x%02X seq=%u seek=%u fe1c=%u fdf8=%u ans_cmd=0x%02X ans_n=%u resp_n=%u resp0=%02X resp1=%02X restore=%s (ownership gate, general posture)\\n",')
        new.append(I16 + "                 r1375_n, (unsigned)cd_last_cmd, cd_sched_seq, cd_seek_lba,")
        new.append(I16 + "                 xenolift_mem_read32(0x8004FE1Cu), xenolift_mem_read32(0x8004FDF8u),")
        new.append(I16 + "                 (unsigned)cd_pend_ans_cmd, (unsigned)cd_pend_ans_n,")
        new.append(I16 + "                 (unsigned)cd_resp_n, (unsigned)(cd_resp_n > 0 ? cd_resp[0] : 0),")
        new.append(I16 + "                 (unsigned)(cd_resp_n > 1 ? cd_resp[1] : 0), restored ? \"OWNED\" : \"SKIPPED\");")
        new.append(I16 + "    cd_scheduled = 0;")
        new.append(I16 + "    cd_pending = 3; cd_pending_stamp(3u, 5u);")
        new.append(I16 + "    if (!cd_flag_suppressed(cd_last_cmd)) {")
        new.append(I16 + "        uint16_t one = 1;")
        new.append(I16 + "        memcpy(xenolift_mem + (0x800578A6u & 0x1FFFFFFFu), &one, 2);")
        new.append(I16 + "    }")
        new.append(I16 + '    cd_force_deliver_int1("mvloop-r1375");')
        new.append(I16 + "}")
        for n in new:
            out.append(n)
        i = j + 2
        e += 1
        continue
    out.append(lines[i])
    i += 1
if e != 1:
    print("ANCHOR-FAILED: edits %d (must be 1)" % e); sys.exit(1)
patched = "\n".join(out)
if patched.count("R1375") != 2: print("POST-FAILED: R1375 != 2"); sys.exit(1)
if patched.count("R1374") != 0 or patched.count("r1374") != 0: print("POST-FAILED: R1374 residue"); sys.exit(1)
if patched.count("mvloop-r1375") != 1: print("POST-FAILED: deliver tag != 1"); sys.exit(1)
if patched.count("restore_pend(); /* ownership-proven") != 1: print("POST-FAILED: ownership gate != 1"); sys.exit(1)
open(p, "w").write(patched)
print("PATCH-APPLIED (R1375 generalized delivery: structural invariant gate + ownership + dossier)")
PYEOF
if [ $? -ne 0 ]; then echo "PATCH-STEP-FAILED: nothing to run"; exit 0; fi
NEW_SHA=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_SHA=$NEW_SHA"
POST_G1=$(grep -c "R1375" "$SRC" || true)
POST_G2=$(grep -c "R1374\|r1374" "$SRC" || true)
POST_G3=$(grep -c "mvloop-r1375" "$SRC" || true)
echo "POST R1375 count=$POST_G1 (must be 2)"
echo "POST R1374 residue count=$POST_G2 (must be 0)"
echo "POST deliver count=$POST_G3 (must be 1)"
if [ "$POST_G1" != "2" ] || [ "$POST_G2" != "0" ] || [ "$POST_G3" != "1" ]; then
  echo "POST-GATE-FAILED: restoring the pristine tree"
  cp -p "$PDIR/runtime.c.pre" "$SRC"
  echo "RESTORED"
  exit 0
fi
cc -fsyntax-only -std=gnu99 -Wno-implicit-function-declaration -Wno-int-conversion -Wno-constant-conversion -Wno-int-to-void-pointer-cast "$SRC" 2>/tmp/c406_parse_err.txt
PARSE_RC=$?
echo "PARSE_RC=$PARSE_RC"
if [ $PARSE_RC -ne 0 ]; then
  echo "PARSE-FAILED: restoring the pristine tree (fail-closed)"
  head -12 /tmp/c406_parse_err.txt
  cp -p "$PDIR/runtime.c.pre" "$SRC"
  echo "RESTORED"
  exit 0
fi
echo "PARSE-OK"
echo "===RUN406=== the R1375 build, 120s budget"
RUN_BUDGET_S=120 ./run.sh > /tmp/run_full_c406.txt 2>&1
RUN_RC=$?
echo "RUN_RC=$RUN_RC"
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
if [ ! -s "$LOG" ]; then
  echo "TREE-ROOT-LOG-MISSING: preserving run_full tail"
  tail -25 /tmp/run_full_c406.txt
  exit 0
fi
echo "AUTHORITATIVE LOG = $LOG ($(wc -l < "$LOG" | tr -d ' ') lines)"
echo "===R1375DOSSIER406=== the delivery dossiers (identity judged from these)"
grep -n "R1375\]" "$LOG" | head -18
echo "===H4DISP406=== the h4 dispatch receipts at the delivery (the unsuppressed mirror)"
grep -n "wl: dispatch h4\|DATA HANDLER enter" "$LOG" | awk -F: '$1>=28000' | head -10
echo "===SUPPRESS406=== any R1179/R898 receipts near the delivery (print-budget capped - absence is print policy)"
grep -n "firstfault\] R1179\|R898 force-deliver" "$LOG" | tail -8
echo "===CONSUME406=== guest consumption after the delivery (pendclr/rspop - no repeat-reappearance)"
grep -n "pendclr\|rspop\] R" "$LOG" | awk -F: '$1>=28000' | head -12
echo "===RELEASE406=== the wait release (FE1C advance + spin family change)"
grep -n "finstamp\|cmdtl" "$LOG" | awk -F: '$1>=28000' | head -14
echo "===SPIN406=== the end spin (exited? new family? n growth?)"
grep -n "mvloop\]" "$LOG" | tail -4
echo "===DOWNSTREAM406=== new reads + MDEC beyond reset?"
grep -n "READ ISSUED\|mdec\]" "$LOG" | awk -F: '$1>=28000' | head -10
echo "===GPUVIS406=== the GPU/VRAM story"
grep -n "R694 live" "$LOG" | tail -3
grep -n "nonblank" "$LOG" | tail -3
echo "===EPOCH406=== the boot epochs (must not grow)"
grep -c "bootentry\] R710" "$LOG" || true
echo "===FAULTS406=== the fault census"
echo "computed-garbage $(grep -c "computed-garbage" "$LOG" || true)"
echo "lzss-runaway $(grep -c "lzss-runaway" "$LOG" || true)"
echo "===TAIL406=== the last 20 receipts"
TL=$(wc -l < "$LOG" | tr -d ' ')
S=$((TL-20)); [ $S -lt 1 ] && S=1
awk -v s="$S" -v e="$TL" 'NR>=s && NR<=e { print NR": "$0 }' "$LOG"
echo "===POSTSHA406==="
shasum -a 256 "$SRC" | cut -d' ' -f1
echo "===C406DONE=== the R1375 cycle is complete - the verdict comes from these receipts"
