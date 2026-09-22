#!/bin/bash
# c407_r1376.sh - THE R1376 PATCH+RUN CYCLE (stranded-
# handshake completion v3). THE c406 VERDICT: the prior
# gate fired 64x but mostly on MID-FLIGHT boot-era events
# (resp_n=0 empty deliveries, epochs 4->8 - the churn
# receipted), AND at the new park (seek=265744, FE04=
# 0x40E10, past every known band) the five-stage test
# named the missing stage: the stranded Setloc's INT3 was
# DELIVERED + CONSUMED but FE1C STUCK AT 1 - the ACK: its
# only clearers are kernel IRQ contexts the movie loop
# never runs; hardware's IRQ would preempt the loop.
# THE REPAIR, two halves of one handshake: (1) the
# PERSISTENCE GATE - fire only when the SAME seq is
# sched=1 at two consecutive 512-pass boundaries (a
# stranded event survives a window; a mid-flight one gets
# consumed); (2) the POST-CONSUMPTION ACK ASSIST - after
# our delivery, if the response is consumed (pend==0) but
# FE1C still 1 across another window, write FE1C->0 with a
# receipt (modeling the kernel handler's clear); a natural
# clear is receipted and the watch stands down. Ownership
# gate + dossier stay. PASS = no boot-era dossiers +
# epochs back to baseline + the spin EXITS (waitbr
# ret=0+FDFC=0+FE1C=0 all hold) + a NEW poll family +
# downstream reads/MDEC decode. ANY FAILURE = REVERT.
# Fail-closed pre/post gates + tolerant parse gate, tree
# sha-gated on the R1375 baseline.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C407-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="8f1c37622daa79f6894a7f4908509c01abd125926a11141f7fbf34279f175c9c"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1375 tree - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1375 tree)"
TS=$(date +%Y%m%d_%H%M%S)
PDIR="patch_c407_$TS"
mkdir -p "$PDIR"
cp -p "$SRC" "$PDIR/runtime.c.pre"
echo "PRESERVED: $PDIR/runtime.c.pre"
PRE_G1=$(grep -c "R1375" "$SRC" || true)
PRE_G2=$(grep -c "mvloop-r1375" "$SRC" || true)
PRE_G3=$(grep -c "R1376" "$SRC" || true)
echo "PRE R1375 count=$PRE_G1 (must be 2, the shipped block)"
echo "PRE mvloop-r1375 count=$PRE_G2 (must be 1)"
echo "PRE R1376 count=$PRE_G3 (must be 0)"
if [ "$PRE_G1" != "2" ] || [ "$PRE_G2" != "1" ] || [ "$PRE_G3" != "0" ]; then echo "PRE-GATE-FAILED: refusing, nothing done"; exit 0; fi
python3 - <<'PYEOF'
import sys
p = "runtime/runtime.c"
text = open(p).read()
lines = text.split("\n")
out = []
I16 = " " * 16
START = "R1375 (c405): the movie-era scheduled-response delivery, GENERALIZED"
END = 'cd_force_deliver_int1("mvloop-r1375");'
i = 0; e = 0
while i < len(lines):
    if START in lines[i]:
        j = i
        while j < len(lines) and END not in lines[j]:
            j += 1
        if j + 1 >= len(lines) or lines[j+1].strip() != "}":
            print("ANCHOR-FAILED: span end/brace not found"); sys.exit(1)
        new = []
        new.append(I16 + "/* R1376 (c406): the stranded-handshake completion, v3. The c406")
        new.append(I16 + " * receipts convicted the prior gate as too weak: it fired on")
        new.append(I16 + " * MID-FLIGHT boot-era events (seqs 21-127, resp_n=0 empty")
        new.append(I16 + " * deliveries armed with pend=3) - epochs 4->8, the churn receipted.")
        new.append(I16 + " * And at this run's new park (seek=265744, FE04=0x40E10, past")
        new.append(I16 + " * every known band) the five-stage test named the missing stage:")
        new.append(I16 + " * the stranded Setloc's INT3 DELIVERED + CONSUMED (pendclr) but")
        new.append(I16 + " * FE1C STUCK AT 1 - the ACK: its only clearers are the kernel")
        new.append(I16 + " * IRQ contexts the movie loop never runs (receipted writers")
        new.append(I16 + " * 80040FB4/8002A394); hardware's IRQ would preempt the loop and")
        new.append(I16 + " * the handler would clear it. v3 = TWO HALVES OF ONE HANDSHAKE:")
        new.append(I16 + " * (1) the PERSISTENCE GATE - fire only when the SAME seq is")
        new.append(I16 + " * sched=1 at two consecutive 512-pass boundaries (a stranded")
        new.append(I16 + " * event survives a window; a mid-flight one gets consumed);")
        new.append(I16 + " * (2) the POST-CONSUMPTION ACK ASSIST - after our delivery, if")
        new.append(I16 + " * the response is consumed (pend==0) but FE1C still 1 across")
        new.append(I16 + " * another window, write FE1C->0 with a receipt (modeling the")
        new.append(I16 + " * kernel handler's clear); a natural clear is receipted and the")
        new.append(I16 + " * watch stands down. Ownership gate + dossier stay. PASS = no")
        new.append(I16 + " * boot-era dossiers + epochs back to baseline + the spin EXITS")
        new.append(I16 + " * (waitbr ret=0+FDFC=0+FE1C=0 all hold) + a NEW poll family +")
        new.append(I16 + " * downstream reads/MDEC decode. ANY FAILURE = REVERT. */")
        new.append(I16 + "if (!g_movie_live && (mv_n & 0x1FFu) == 0x100u) {")
        new.append(I16 + "    static uint32_t r1376_seq, r1376_watch, r1376_wn;")
        new.append(I16 + "    if (r1376_watch) {")
        new.append(I16 + "        if (cd_pending == 0u) { /* our delivery was consumed */")
        new.append(I16 + "            if (xenolift_mem_read32(0x8004FE1Cu) == 0u) {")
        new.append(I16 + '                r861_out("[R1376] ack observed naturally (fe1c 0 after consumption) - watch stands down\\n");')
        new.append(I16 + "                r1376_watch = 0;")
        new.append(I16 + "            } else if (++r1376_wn >= 2u) {")
        new.append(I16 + "                uint32_t z = 0;")
        new.append(I16 + "                memcpy(xenolift_mem + (0x8004FE1Cu & 0x1FFFFFFFu), &z, 4);")
        new.append(I16 + '                r861_out("[R1376] ACK-COMPLETION assist: response consumed, FE1C stuck 1 across %u windows, kernel-handler clear modeled: FE1C 1->0\\n", r1376_wn);')
        new.append(I16 + "                r1376_watch = 0;")
        new.append(I16 + "            }")
        new.append(I16 + "        } /* pend!=0: still mid-handshake - keep watching */")
        new.append(I16 + "    } else if (cd_scheduled && cd_pending == 0u) {")
        new.append(I16 + "        if (cd_sched_seq != 0u && r1376_seq == cd_sched_seq) {")
        new.append(I16 + "            static uint32_t r1376_n;")
        new.append(I16 + "            int restored = (cd_pend_ans_n > 0u && cd_pend_ans_cmd == cd_last_cmd);")
        new.append(I16 + "            if (restored) cd_restore_pend(); /* ownership-proven: the answer saved at THIS command's schedule (site 2226/2236 adjacency) */")
        new.append(I16 + "            if (++r1376_n <= 16u || (r1376_n % 64u) == 0u)")
        new.append(I16 + '                r861_out("[R1376] stranded-event delivery #%u (same seq %u across a full window): cmd 0x%02X seek=%u fe1c=%u fdf8=%u ans_cmd=0x%02X ans_n=%u resp_n=%u resp0=%02X restore=%s (ownership gate)\\n",')
        new.append(I16 + "                         r1376_n, cd_sched_seq, (unsigned)cd_last_cmd, cd_seek_lba,")
        new.append(I16 + "                         xenolift_mem_read32(0x8004FE1Cu), xenolift_mem_read32(0x8004FDF8u),")
        new.append(I16 + "                         (unsigned)cd_pend_ans_cmd, (unsigned)cd_pend_ans_n,")
        new.append(I16 + "                         (unsigned)cd_resp_n, restored ? \"OWNED\" : \"SKIPPED\");")
        new.append(I16 + "            cd_scheduled = 0;")
        new.append(I16 + "            cd_pending = 3; cd_pending_stamp(3u, 5u);")
        new.append(I16 + "            if (!cd_flag_suppressed(cd_last_cmd)) {")
        new.append(I16 + "                uint16_t one = 1;")
        new.append(I16 + "                memcpy(xenolift_mem + (0x800578A6u & 0x1FFFFFFFu), &one, 2);")
        new.append(I16 + "            }")
        new.append(I16 + '            cd_force_deliver_int1("mvloop-r1376");')
        new.append(I16 + "            r1376_watch = 1; r1376_wn = 0;")
        new.append(I16 + "            r1376_seq = 0;")
        new.append(I16 + "        } else {")
        new.append(I16 + "            r1376_seq = cd_sched_seq; /* first sighting - do not fire on mid-flight events */")
        new.append(I16 + "        }")
        new.append(I16 + "    } else {")
        new.append(I16 + "        r1376_seq = 0; /* nothing scheduled at this boundary */")
        new.append(I16 + "    }")
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
if patched.count("R1376") != 4: print("POST-FAILED: R1376 != 4 (1 comment + 3 prints)"); sys.exit(1)
if patched.count("R1375") != 0 or patched.count("r1375") != 0: print("POST-FAILED: prior residue"); sys.exit(1)
if patched.count("mvloop-r1376") != 1: print("POST-FAILED: deliver tag != 1"); sys.exit(1)
if patched.count("restore_pend(); /* ownership-proven") != 1: print("POST-FAILED: ownership gate != 1"); sys.exit(1)
if patched.count("cd_sched_seq != 0u && r1376_seq == cd_sched_seq") != 1: print("POST-FAILED: persistence gate != 1"); sys.exit(1)
if patched.count("ACK-COMPLETION assist") != 1: print("POST-FAILED: ack assist != 1"); sys.exit(1)
open(p, "w").write(patched)
print("PATCH-APPLIED (R1376 v3: persistence gate + post-consumption ack assist + dossier)")
PYEOF
if [ $? -ne 0 ]; then echo "PATCH-STEP-FAILED: nothing to run"; exit 0; fi
NEW_SHA=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_SHA=$NEW_SHA"
POST_G1=$(grep -c "R1376" "$SRC" || true)
POST_G2=$(grep -c "R1375\|r1375" "$SRC" || true)
POST_G3=$(grep -c "mvloop-r1376" "$SRC" || true)
echo "POST R1376 count=$POST_G1 (must be 4)"
echo "POST R1375 residue count=$POST_G2 (must be 0)"
echo "POST deliver count=$POST_G3 (must be 1)"
if [ "$POST_G1" != "4" ] || [ "$POST_G2" != "0" ] || [ "$POST_G3" != "1" ]; then
  echo "POST-GATE-FAILED: restoring the pristine tree"
  cp -p "$PDIR/runtime.c.pre" "$SRC"
  echo "RESTORED"
  exit 0
fi
cc -fsyntax-only -std=gnu99 -Wno-implicit-function-declaration -Wno-int-conversion -Wno-constant-conversion -Wno-int-to-void-pointer-cast "$SRC" 2>/tmp/c407_parse_err.txt
PARSE_RC=$?
echo "PARSE_RC=$PARSE_RC"
if [ $PARSE_RC -ne 0 ]; then
  echo "PARSE-FAILED: restoring the pristine tree (fail-closed)"
  head -12 /tmp/c407_parse_err.txt
  cp -p "$PDIR/runtime.c.pre" "$SRC"
  echo "RESTORED"
  exit 0
fi
echo "PARSE-OK"
echo "===RUN407=== the R1376 build, 120s budget"
RUN_BUDGET_S=120 ./run.sh > /tmp/run_full_c407.txt 2>&1
RUN_RC=$?
echo "RUN_RC=$RUN_RC"
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
if [ ! -s "$LOG" ]; then
  echo "TREE-ROOT-LOG-MISSING: preserving run_full tail"
  tail -25 /tmp/run_full_c407.txt
  exit 0
fi
echo "AUTHORITATIVE LOG = $LOG ($(wc -l < "$LOG" | tr -d ' ') lines)"
echo "===R1376DOSSIER407=== the stranded-event dossiers (boot-era noise must be GONE)"
grep -n "R1376\]" "$LOG" | head -18
echo "===ACK407=== the ack-completion story (natural clear or assist)"
grep -n "ack observed naturally\|ACK-COMPLETION assist" "$LOG" | head -8
echo "===CONSUME407=== guest consumption after the delivery (pendclr - no repeat-reappearance)"
grep -n "pendclr" "$LOG" | awk -F: '$1>=28000' | head -10
echo "===RELEASE407=== the wait release (all three waitbr conditions hold?)"
grep -n "waitbr" "$LOG" | tail -6
grep -n "cmdtl" "$LOG" | tail -8
echo "===SPIN407=== the end spin (exited? new family?)"
grep -n "mvloop\]" "$LOG" | tail -4
echo "===DOWNSTREAM407=== new reads + MDEC beyond reset?"
grep -n "READ ISSUED\|mdec\]" "$LOG" | awk -F: '$1>=28000' | head -10
echo "===GPUVIS407=== the GPU/VRAM story"
grep -n "R694 live\|nonblank" "$LOG" | tail -4
echo "===EPOCH407=== the boot epochs (must be back at baseline ~4, not 8)"
grep -c "bootentry\] R710" "$LOG" || true
echo "===FAULTS407=== the fault census"
echo "computed-garbage $(grep -c "computed-garbage" "$LOG" || true)"
echo "lzss-runaway $(grep -c "lzss-runaway" "$LOG" || true)"
echo "===TAIL407=== the last 20 receipts"
TL=$(wc -l < "$LOG" | tr -d ' ')
S=$((TL-20)); [ $S -lt 1 ] && S=1
awk -v s="$S" -v e="$TL" 'NR>=s && NR<=e { print NR": "$0 }' "$LOG"
echo "===POSTSHA407==="
shasum -a 256 "$SRC" | cut -d' ' -f1
echo "===C407DONE=== the R1376 cycle is complete - the verdict comes from these receipts"
