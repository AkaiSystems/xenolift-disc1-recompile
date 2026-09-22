#!/bin/bash
# c404_r1374.sh - THE R1374 PATCH+RUN CYCLE (one narrowly
# scoped repair, one focused validation). THE DEFECT
# (receipted, c401-c403): the re-issued ReadN(109158)'s
# scheduled INT3 is undelivered at the movie-loop contexts
# (sched=1, pend=0, FDF8=0, the pre-movie spin 200M passes;
# R260 is g_movie_live-gated OFF in this era). THE REPAIR:
# replace the CONVICTED R1373 block (its unconditional
# restore_pend replays a stale answer for single-byte
# responses - the R307 save site saves only cd_resp_n > 1)
# with R1374: deliver at the receipted stuck posture
# (cmd-06, fe1c=0, sched=1, pend=0, FDF8=0, !g_movie_live)
# with ANSWER-OWNERSHIP-gated restore (cd_pend_ans_cmd ==
# cd_last_cmd; the schedule site 2236 is line-adjacent to
# the save 2226) and a full identity dossier (seq, cmd,
# ans_cmd, response bytes, restore verdict) so the receipts
# judge the delivered instance. PASS = the dossier + guest
# consumption (pendclr/rspop, no repeat-reappearance) + the
# wait genuinely releasing (FE1C advance, a new poll family,
# not a frozen counter) + the re-read arming + MDEC decode
# beyond reset. ANY FAILURE = REVERT (pivot to
# visibility-based delivery). Fail-closed pre/post gates +
# tolerant parse gate, tree sha-gated on the R1373 baseline.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C404-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="a9d040824cbf7d8ab262b927579be97e1ab9015af3852361d67aee7d52fd5bc1"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1373 tree - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1373 tree)"
TS=$(date +%Y%m%d_%H%M%S)
PDIR="patch_c404_$TS"
mkdir -p "$PDIR"
cp -p "$SRC" "$PDIR/runtime.c.pre"
echo "PRESERVED: $PDIR/runtime.c.pre"
PRE_G1=$(grep -c "R1373" "$SRC" || true)
PRE_G2=$(grep -c "mvloop-r1373" "$SRC" || true)
PRE_G3=$(grep -c "R1374" "$SRC" || true)
echo "PRE R1373 count=$PRE_G1 (must be 2, the shipped block)"
echo "PRE mvloop-r1373 count=$PRE_G2 (must be 1)"
echo "PRE R1374 count=$PRE_G3 (must be 0)"
if [ "$PRE_G1" != "2" ] || [ "$PRE_G2" != "1" ] || [ "$PRE_G3" != "0" ]; then echo "PRE-GATE-FAILED: refusing, nothing done"; exit 0; fi
python3 - <<'PYEOF'
import sys
p = "runtime/runtime.c"
text = open(p).read()
lines = text.split("\n")
out = []
I16 = " " * 16
START = "R1373 (c400): the movie-era scheduled-response delivery"
END = 'cd_force_deliver_int1("mvloop-r1373");'
i = 0; e = 0
while i < len(lines):
    if START in lines[i]:
        j = i
        while j < len(lines) and END not in lines[j]:
            j += 1
        if j + 1 >= len(lines) or lines[j+1].strip() != "}":
            print("ANCHOR-FAILED: span end/brace not found"); sys.exit(1)
        new = []
        new.append(I16 + "/* R1374 (c403): the movie-era scheduled-response delivery v2, replacing the")
        new.append(I16 + " * convicted predecessor. The c401/c403 receipts: the pre-movie poll parks")
        new.append(I16 + " * at last_cmd=06 (the re-issued ReadN 109158), FE1C=0, sched=1, pend=0,")
        new.append(I16 + " * FDF8=0 - the ReadN's INT3 armed (the single schedule site 2236,")
        new.append(I16 + " * line-adjacent to the R307 save) but undelivered at the movie-loop")
        new.append(I16 + " * contexts (R260 is g_movie_live-gated OFF in this era). The prior")
        new.append(I16 + " * composite is CONVICTED for its scoped Setloc posture: unconditional")
        new.append(I16 + " * restore_pend replays a stale answer for single-byte responses (the")
        new.append(I16 + " * R307 save site saves only cd_resp_n > 1). v2: gate restore on ANSWER")
        new.append(I16 + " * OWNERSHIP (cd_pend_ans_cmd == cd_last_cmd); if ownership fails,")
        new.append(I16 + " * deliver cd_resp AS-IS (the schedule site's own bytes) - the dossier")
        new.append(I16 + " * prints seq/cmd/ans_cmd/resp bytes so the receipts judge the delivered")
        new.append(I16 + " * instance. Scoped to the receipted stuck posture (cmd-06, fe1c=0,")
        new.append(I16 + " * sched=1, pend=0, FDF8=0, !g_movie_live). The [firstfault] R1179")
        new.append(I16 + " * receipts expose any handler-dispatch suppression. PASS = consumption")
        new.append(I16 + " * + the wait genuinely releasing (FE1C advance + a new poll family) +")
        new.append(I16 + " * the re-read arming + MDEC decode beyond reset; any failure = REVERT")
        new.append(I16 + " * (the design pivots to visibility-based delivery). */")
        new.append(I16 + "if (!g_movie_live && (mv_n & 0x1FFu) == 0x100u && cd_scheduled")
        new.append(I16 + "    && cd_pending == 0u && cd_last_cmd == 0x06u")
        new.append(I16 + "    && xenolift_mem_read32(0x8004FE1Cu) == 0u")
        new.append(I16 + "    && xenolift_mem_read32(0x8004FDF8u) == 0u) {")
        new.append(I16 + "    static uint32_t r1374_n;")
        new.append(I16 + "    int restored = (cd_pend_ans_n > 0u && cd_pend_ans_cmd == cd_last_cmd);")
        new.append(I16 + "    if (restored) cd_restore_pend(); /* ownership-proven: the answer saved at THIS command's schedule (site 2226/2236 adjacency) */")
        new.append(I16 + "    if (++r1374_n <= 16u || (r1374_n % 64u) == 0u)")
        new.append(I16 + '        r861_out("[R1374] movie-era ReadN INT3 delivery #%u: cmd 0x%02X seq=%u seek=%u fe1c=%u ans_cmd=0x%02X ans_n=%u resp_n=%u resp0=%02X resp1=%02X restore=%s (ownership gate)\\n",')
        new.append(I16 + "                 r1374_n, (unsigned)cd_last_cmd, cd_sched_seq, cd_seek_lba,")
        new.append(I16 + "                 xenolift_mem_read32(0x8004FE1Cu), (unsigned)cd_pend_ans_cmd, (unsigned)cd_pend_ans_n,")
        new.append(I16 + "                 (unsigned)cd_resp_n, (unsigned)(cd_resp_n > 0 ? cd_resp[0] : 0),")
        new.append(I16 + "                 (unsigned)(cd_resp_n > 1 ? cd_resp[1] : 0), restored ? \"OWNED\" : \"SKIPPED\");")
        new.append(I16 + "    cd_scheduled = 0;")
        new.append(I16 + "    cd_pending = 3; cd_pending_stamp(3u, 5u);")
        new.append(I16 + "    if (!cd_flag_suppressed(cd_last_cmd)) {")
        new.append(I16 + "        uint16_t one = 1;")
        new.append(I16 + "        memcpy(xenolift_mem + (0x800578A6u & 0x1FFFFFFFu), &one, 2);")
        new.append(I16 + "    }")
        new.append(I16 + '    cd_force_deliver_int1("mvloop-r1374");')
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
if patched.count("R1374") != 2: print("POST-FAILED: R1374 != 2"); sys.exit(1)
if patched.count("R1373") != 0 or patched.count("r1373") != 0: print("POST-FAILED: R1373 residue"); sys.exit(1)
if patched.count("mvloop-r1374") != 1: print("POST-FAILED: deliver tag != 1"); sys.exit(1)
if patched.count("restore_pend(); /* ownership-proven") != 1: print("POST-FAILED: ownership gate != 1"); sys.exit(1)
if "cd_last_cmd == 0x02u" in patched and patched.count("cd_last_cmd == 0x02u") != 0: print("POST-FAILED: old posture residue"); sys.exit(1)
open(p, "w").write(patched)
print("PATCH-APPLIED (R1374 replaces the convicted block: ownership-gated restore + identity dossier)")
PYEOF
if [ $? -ne 0 ]; then echo "PATCH-STEP-FAILED: nothing to run"; exit 0; fi
NEW_SHA=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_SHA=$NEW_SHA"
POST_G1=$(grep -c "R1374" "$SRC" || true)
POST_G2=$(grep -c "R1373\|r1373" "$SRC" || true)
POST_G3=$(grep -c "mvloop-r1374" "$SRC" || true)
echo "POST R1374 count=$POST_G1 (must be 2)"
echo "POST R1373 residue count=$POST_G2 (must be 0)"
echo "POST deliver count=$POST_G3 (must be 1)"
if [ "$POST_G1" != "2" ] || [ "$POST_G2" != "0" ] || [ "$POST_G3" != "1" ]; then
  echo "POST-GATE-FAILED: restoring the pristine tree"
  cp -p "$PDIR/runtime.c.pre" "$SRC"
  echo "RESTORED"
  exit 0
fi
cc -fsyntax-only -std=gnu99 -Wno-implicit-function-declaration -Wno-int-conversion -Wno-constant-conversion -Wno-int-to-void-pointer-cast "$SRC" 2>/tmp/c404_parse_err.txt
PARSE_RC=$?
echo "PARSE_RC=$PARSE_RC"
if [ $PARSE_RC -ne 0 ]; then
  echo "PARSE-FAILED: restoring the pristine tree (fail-closed)"
  head -12 /tmp/c404_parse_err.txt
  cp -p "$PDIR/runtime.c.pre" "$SRC"
  echo "RESTORED"
  exit 0
fi
echo "PARSE-OK"
echo "===RUN404=== the R1374 build, 120s budget"
RUN_BUDGET_S=120 ./run.sh > /tmp/run_full_c404.txt 2>&1
RUN_RC=$?
echo "RUN_RC=$RUN_RC"
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
if [ ! -s "$LOG" ]; then
  echo "TREE-ROOT-LOG-MISSING: preserving run_full tail"
  tail -25 /tmp/run_full_c404.txt
  exit 0
fi
echo "AUTHORITATIVE LOG = $LOG ($(wc -l < "$LOG" | tr -d ' ') lines)"
echo "===R1374DOSSIER404=== the delivery dossiers (identity judged from these)"
grep -n "R1374\]" "$LOG" | head -18
echo "===SUPPRESS404=== any R1179/R898 suppression receipts at the delivery (the stop-discipline veto)"
grep -n "firstfault\] R1179\|R898 force-deliver" "$LOG" | awk -F: '$1>=28000' | head -8
echo "===CONSUME404=== guest consumption after the delivery (pendclr/rspop/schdw - no repeat-reappearance)"
grep -n "pendclr\|rspop\] R" "$LOG" | awk -F: '$1>=28000' | head -12
echo "===RELEASE404=== the wait release (FE1C advance + spin family change)"
grep -n "finstamp\|cmdtl" "$LOG" | awk -F: '$1>=28000' | head -16
echo "===SPIN404=== the end spin (exited? new family? n growth?)"
grep -n "mvloop\]" "$LOG" | tail -4
echo "===REREAD404=== the re-read arming (FDF8 re-arm + 109158+ serves)"
grep -n "109158\|FDF8.*14360\|READ ISSUED" "$LOG" | awk -F: '$1>=28000' | head -10
echo "===MDEC404=== MDEC beyond reset?"
grep -n "mdec\]" "$LOG" | tail -8
echo "===GPUVIS404=== the GPU/VRAM story"
grep -n "R694 live" "$LOG" | tail -3
grep -n "nonblank" "$LOG" | tail -3
echo "===EPOCH404=== the boot epochs"
grep -c "bootentry\] R710" "$LOG" || true
echo "===FAULTS404=== the fault census"
echo "computed-garbage $(grep -c "computed-garbage" "$LOG" || true)"
echo "lzss-runaway $(grep -c "lzss-runaway" "$LOG" || true)"
echo "===TAIL404=== the last 20 receipts"
TL=$(wc -l < "$LOG" | tr -d ' ')
S=$((TL-20)); [ $S -lt 1 ] && S=1
awk -v s="$S" -v e="$TL" 'NR>=s && NR<=e { print NR": "$0 }' "$LOG"
echo "===POSTSHA404==="
shasum -a 256 "$SRC" | cut -d' ' -f1
echo "===C404DONE=== the R1374 cycle is complete - the verdict comes from these receipts"
