#!/bin/bash
# c534_patch.sh - THE FIX THE RECEIPTS SELECTED: R1396,
# THE EMPTY-DOOR GUARD ON THE R844 BOOT-LOOP BYPASS. THE
# c532/c533 RECEIPTS: the R844 bypass forced the
# field-coordinator door 0x80077E88 at a heapclr-fresh
# restart bounce - BEFORE the epoch's boot reinstalled its
# modules - so the R1394 interpreter ran ~24670 NOPs
# through the all-zero module window and stopped class 3
# (capture 0/135168 nonzero). PRE-heapclr trees left the
# prior epoch's module in RAM so the forced door found
# real code; the c528 heapclr is reboot-faithful and STAYS -
# the BACKUP PLAN must decline instead of forcing an
# uninstalled door. EACH EPOCH PROVABLY REINSTALLS ITS
# MODULES (newmod members 2-7 receipted in ALL three
# epochs), so a declined force leads naturally to a
# POPULATED window on the next bounce. THE FIX: a scan of
# the module window 0x8006F000..0x80090000 for any nonzero
# word, inserted as a declaration + block immediately
# before the R844 gate line, with the gate gaining
# "&& r1396_ok" (ONE term appended to the receipted gate,
# nothing else changes); on empty, the [bypassdecl]
# receipt fires (cap 8, only when the bypass was otherwise
# eligible) and the boot-entry re-dispatch proceeds
# unchanged. GATES: tree sha 663fc0ef, the anchor line
# (pend == 0x80019524u && g_r765_fw_restarts >= 2) unique,
# r1396_ok / [bypassdecl] / R1396 ABSENT pre-patch, exactly
# ONE "!g_splash_live)" substitution ON THE ANCHOR LINE
# (line-scoped awk gsub - co-resident splashgate terms
# elsewhere are untouched), post-counts from the artifact,
# HARD unpiped syntax gate with restore-on-fail, then
# build + the 190s verdict run + digest. PASS = the bypass
# never forces an empty window (declines receipted on
# heapclr-fresh bounces) + the epochs continue + forward
# execution beyond the empty-door stop + NO class-3
# empty-window stop + no c528/c531 regression. REVERT if
# the guard blocks ALL forward progress (the run ends
# without ever forcing - then the boot-loop fault becomes
# the next fix). Fail-closed, tee'd to /tmp/c534_receipts.txt.
# Pure-ASCII output.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C534-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c534_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="663fc0efdb3620943ad1940e1d0892847805dcaab1508fec91f4f0ef6eaae7b7"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the c531 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the c531 tree with the landed zrfF command-byte widen)"
for M in "r1396_ok" "[bypassdecl]" "R1396"; do
  P=$(grep -c -F -e "$M" "$SRC" | tr -d " ")
  echo "pre-count [$M]: $P (expect 0)"
  if [ "$P" != "0" ]; then echo "VALID-FAILED: [$M] already present - refusing (idempotent)"; exit 0; fi
done
ANC=$(grep -c -F -e "pend == 0x80019524u && g_r765_fw_restarts >= 2" "$SRC" | tr -d " ")
echo "anchor count: $ANC (expect 1)"
if [ "$ANC" != "1" ]; then echo "VALID-FAILED: the R844 gate anchor is not unique - refusing"; exit 0; fi
L=$(grep -n -F -e "pend == 0x80019524u && g_r765_fw_restarts >= 2" "$SRC" | head -1 | cut -d: -f1)
echo "===SPLICE534=== inserting the R1396 guard before the R844 gate (line $L)"
cp -p "$SRC" "$SRC.pre_c534"
echo "--- the pre-patch gate line:"
sed -n "${L}p" "$SRC"
cat > /tmp/r1396_insert.c <<'CEOF'
                int r1396_ok; /* R1396 (c534): THE EMPTY-DOOR GUARD - never force a door whose
                   * module is NOT installed. The c532/c533 receipts: the R844 boot-loop
                   * bypass forced the field-coordinator door 0x80077E88 at a heapclr-fresh
                   * restart bounce - BEFORE the epoch's boot reinstalled its modules - so
                   * the R1394 interpreter ran ~24670 NOPs through the all-zero module
                   * window and stopped class 3 (capture 0/135168 nonzero). Pre-heapclr
                   * trees left the prior epoch's module in RAM so the forced door found
                   * real code; the c528 heapclr is reboot-faithful and STAYS - the backup
                   * plan must decline instead. Each epoch provably reinstalls its modules
                   * (newmod members 2-7 receipted in ALL three epochs), so a declined
                   * force leads to a POPULATED window on the next anchor bounce. */
                { uint32_t r1396_q; static int r1396_decl_n;
                  for (r1396_q = 0x8006F000u, r1396_ok = 0; r1396_q < 0x80090000u; r1396_q += 4u) {
                      if (xenolift_mem_read32(r1396_q) != 0u) { r1396_ok = 1; break; }
                  }
                  if (!r1396_ok && pend == 0x80019524u && g_r765_fw_restarts >= 2
                      && r844_bypasses < 12 && !g_splash_live && r1396_decl_n++ < 8) {
                      r861_out("[bypassdecl] R1396 R844 force DECLINED: the module window 0x8006F000..0x80090000 is EMPTY (heapclr-fresh restart; the boot has not reinstalled its modules) - the boot-entry re-dispatch proceeds, the anchor stays live for the next bounce\n");
                  }
                }
CEOF
INS=$(wc -l < /tmp/r1396_insert.c | tr -d " ")
head -n "$((L-1))" "$SRC" > /tmp/runtime_new.c
cat /tmp/r1396_insert.c >> /tmp/runtime_new.c
awk -v L="$L" 'NR>=L { if (NR==L) { i = index($0, "!g_splash_live)"); if (i > 0) { $0 = substr($0,1,i-1) "!g_splash_live && r1396_ok)" substr($0,i+15); n=1 } printf "%s\n", n+0 > "/tmp/c534_subs" } print }' "$SRC" >> /tmp/runtime_new.c
SUBS=$(cat /tmp/c534_subs | tr -d " ")
echo "gate-line substitutions: $SUBS (expect 1)"
if [ "$SUBS" != "1" ]; then
  echo "VALID-FAILED: expected 1 gate-line substitution, got $SUBS - RESTORING the pre-c534 tree"
  cp -p "$SRC.pre_c534" "$SRC"
  exit 0
fi
cp /tmp/runtime_new.c "$SRC"
echo "--- the patched region (the guard + the widened gate):"
sed -n "$((L-2)),$((L+INS+3))p" "$SRC"
echo "===GATES534==="
A_DECL=$(grep -c -F -e "[bypassdecl]" "$SRC" | tr -d " ")
A_OK=$(grep -c -F -e "r1396_ok" "$SRC" | tr -d " ")
A_R1396=$(grep -c -F -e "R1396" "$SRC" | tr -d " ")
A_ANC=$(grep -c -F -e "pend == 0x80019524u && g_r765_fw_restarts >= 2" "$SRC" | tr -d " ")
A_GATED=$(awk -v L="$L" -v I="$INS" 'NR==L+I && /r1396_ok/ {print 1}' "$SRC")
echo "[bypassdecl] refs: got $A_DECL (expect 1)"
echo "r1396_ok refs: got $A_OK (expect 5)"
echo "R1396 refs: got $A_R1396 (expect 2 - the comment line + the decline print)"
echo "anchor refs: got $A_ANC (expect 2 - the original gate line + the insert decline-condition line)"
echo "the patched gate line carries r1396_ok: got ${A_GATED:-0} (expect 1)"
if [ "$A_DECL" != "1" ] || [ "$A_OK" != "5" ] || [ "$A_R1396" != "2" ] || [ "$A_ANC" != "2" ] || [ "${A_GATED:-0}" != "1" ]; then
  echo "VALID-FAILED: gate mismatch - RESTORING the pre-c534 tree"
  cp -p "$SRC.pre_c534" "$SRC"
  exit 0
fi
echo "GATES OK"
echo "===SYNCHK534=== HARD GATE syntax check (unpiped rc)"
cc -w -fsyntax-only -std=gnu99 "$SRC" 2> /tmp/c534_syn_err.txt
RC=$?
head -8 /tmp/c534_syn_err.txt
echo "SYNCHK_RC=$RC"
if [ "$RC" != "0" ]; then
  echo "VALID-FAILED: patched file does not parse - RESTORING the pre-c534 tree"
  cp -p "$SRC.pre_c534" "$SRC"
  exit 0
fi
echo "SYNCHK OK"
NEW=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_TREE_SHA=$NEW"
echo "===RUN534=== build + the 190s verdict run"
export RUN_BUDGET_S=190
bash run.sh 2>&1 | tail -20
echo "RUN_RC=$?"
echo "===DIGEST534==="
LOG="run.log"
if [ ! -s "$LOG" ]; then LOG="run.log.d"; fi
echo "--- the [bypassdecl] receipts (the guard's own evidence - the declines):"
grep -n -e "\[bypassdecl\]" "$LOG" | head -8
echo "--- the [bypassrec] receipts (the forces - now only into a populated window):"
grep -n -e "\[bypassrec\]" "$LOG" | head -8
echo "--- the ovl family (the empty-door class-3 stop must NOT recur on an empty window):"
grep -n -e "\[ovlint\]" -e "\[ovlstop\]" "$LOG" | head -10
echo "--- the epoch timeline (restarts + clears + installs):"
grep -n -e "fwrestart" -e "heapclr" "$LOG" | head -10
grep -n -e "\[newmod\]" "$LOG" | grep -e "member=6" | head -6
echo "--- forward execution (log length vs the 32001 baseline + the tail):"
wc -l < "$LOG" | tr -d " " | sed "s/^/log lines: /"
tail -16 "$LOG"
echo "--- no regression (the c528/c531 fixes hold):"
grep -c -e "r31=0000000A" "$LOG" | tr -d " " | sed "s/^/r31=0A receipts (expect 0): /"
grep -n -e "\[zrfF\]" "$LOG" | head -4
grep -n -e "parkrel" "$LOG" | tail -3
echo "--- the screen witnesses:"
grep -n -e "vram_nonzero" "$LOG" | tail -3
echo "--- tree sha at run time:"
shasum -a 256 "$SRC" | cut -d" " -f1
echo "===C534DONE=== PASS = the bypass declines on empty windows + the epochs continue + forward execution + no class-3 empty-door stop + no regression - digest is pure ASCII"
