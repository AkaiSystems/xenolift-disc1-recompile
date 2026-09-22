#!/bin/bash
# c524_patch.sh - THE FIX THE RECEIPTS SELECTED: R1381,
# THE PARK-ERA SCHEDULED-RESPONSE RELEASE REQUEST. THE
# c520-c523 RECEIPTS: the deepest run ever parked in
# LegacyCdDataWait (fn 800286CC) with the ReadN at LBA
# 108861 SCHEDULED but never delivered - sched=1, pend=0,
# act=0, arm1=0, FE1C=2, FE04==seek, FDF8=23744 armed -
# because the ENTIRE serve chain is register-poll-driven
# (the R96 INT1 arm needs an 1801 response pop; the
# scheduled response is built only by cd_sched_poll_release,
# requested only by 1800/1802 reads) and this wait family
# polls MEMORY CELLS (439M A22C reads, zero CD-register
# reads). THE c523 SOURCE VERDICT: the R397 release gate
# MATCHES this posture exactly (FE1C 1/2 + FE04==seek +
# FDF8!=0, the cmd 02/06 legs) - the release just never
# runs. THE FIX: one self-contained block at the A22C read
# site (the proven-hot park path, 439M reads receipted):
# every 64th A22C read, when the drive-idle-with-
# scheduled-command posture holds (sched && !pend && !act
# && !arm1), request the EXISTING deferred release
# (g_r918_poll_requested=1, the R918/R923 pattern - one
# flag write, no host frame, no guest dispatch). The
# boundary drain runs cd_sched_poll_release; ITS OWN GATES
# remain the safety boundary (this block adds no delivery
# of its own); the EXISTING machinery (response prime ->
# INT3 pending -> fd-tick conversion R471 -> handler pair
# -> guest driver code sets A22C) completes the chain.
# Gates: tree sha 05535414, anchor unique (SELF-DRIVING
# KICK AT THE EVENT-DISABLE POLL == 1), [parkrel] absent
# pre-patch (idempotent), post-counts from the artifact,
# HARD unpiped syntax gate with restore-on-fail, then
# build + the 190s verdict run + digest. PASS = [parkrel]
# receipts + the park-era delivery chain (release WIN,
# conversion, rspop, cd-dma at 108861, FDF8 23744
# countdown) + THE PARK EXITING (mvloop polls stop, forward
# execution past the wait). Fail-closed, tee'd to
# /tmp/c524_receipts.txt. Pure-ASCII output.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C524-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c524_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="05535414f7c77fd05cb4bcfeaf91fdbd239baf7e4c9d7c48b529bbaf658d1233"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the c519 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the c519 tree with the landed post-conversion collector pass)"
if grep -q -F -e "[parkrel]" "$SRC"; then echo "VALID-FAILED: [parkrel] already present - refusing (idempotent)"; exit 0; fi
ANC=$(grep -c -F -e "SELF-DRIVING KICK AT THE EVENT-DISABLE POLL" "$SRC" | tr -d " ")
echo "anchor count: $ANC (expect 1)"
if [ "$ANC" != "1" ]; then echo "VALID-FAILED: anchor not unique - refusing"; exit 0; fi
cp -p "$SRC" "$SRC.pre_c524"
L=$(grep -n -F -e "SELF-DRIVING KICK AT THE EVENT-DISABLE POLL" "$SRC" | head -1 | cut -d: -f1)
echo "===SPLICE524=== inserting the R1381 block before the R1196 pollkick comment (line $L)"
cat > /tmp/r1381_block.c <<'CEOF'
    { /* R1381 (c524): PARK-ERA SCHEDULED-RESPONSE RELEASE REQUEST. The c520-c523
       * receipts: the deepest run ever parked in LegacyCdDataWait (fn 800286CC) with
       * the ReadN at LBA 108861 SCHEDULED but never delivered (sched=1 pend=0 act=0
       * arm1=0 FE1C=2 FE04==seek FDF8=23744 armed) - the entire serve chain is
       * register-poll-driven (the R96 INT1 arm needs an 1801 response pop; the
       * scheduled response is built only by cd_sched_poll_release, requested only by
       * 1800/1802 reads) and this wait family polls MEMORY CELLS (439M A22C reads,
       * zero CD-register reads). The R397 release gate MATCHES this posture exactly
       * (FE1C 1/2 + FE04==seek + FDF8!=0, the cmd 02/06 legs) - the release just
       * never runs. FIX: every 64th A22C read, when the drive-idle-with-scheduled-
       * command posture holds, request the EXISTING deferred release (the R918/R923
       * pattern - one flag write, no host frame, no guest dispatch). The boundary
       * drain runs cd_sched_poll_release; ITS OWN GATES remain the safety boundary
       * (this block delivers nothing itself); the EXISTING machinery (response
       * prime -> INT3 pending -> fd-tick conversion R471 -> handler pair -> guest
       * driver code sets A22C) completes the chain. */
        if (a == 0x8006A22Cu) {
            static uint32_t r1381_n;
            if (++r1381_n >= 64u) {
                r1381_n = 0u;
                if (cd_scheduled && !cd_pending && !cd_read_active && !cd_arm_int1_pending) {
                    g_r918_poll_requested = 1;
                    { static uint32_t r1381_p;
                      if (r1381_p < 16u || (r1381_p % 65536u) == 0u)
                        r861_out("[parkrel] R1381 release requested: sched=1 pend=0 act=0 cmd=%02X seek=%u FE04=%u FDF8=%u fe1c=%u\n",
                                 (unsigned)cd_last_cmd, cd_seek_lba,
                                 xenolift_mem_read32(0x8004FE04u),
                                 xenolift_mem_read32(0x8004FDF8u),
                                 xenolift_mem_read32(0x8004FE1Cu));
                      r1381_p++; }
                }
            }
        }
    }

CEOF
BLK=$(wc -l < /tmp/r1381_block.c | tr -d " ")
INS=$((L-1))
head -n "$INS" "$SRC" > /tmp/runtime_new.c
cat /tmp/r1381_block.c >> /tmp/runtime_new.c
tail -n +"$L" "$SRC" >> /tmp/runtime_new.c
cp /tmp/runtime_new.c "$SRC"
echo "INSERTED before line $L (block $BLK lines)"
echo "--- the splice context (before/after):"
sed -n "$((INS-6)),$((INS))p" "$SRC"
echo "vvvv the inserted block head:"
sed -n "$((INS+1)),$((INS+5))p" "$SRC"
echo "===GATES524==="
A_PARK=$(grep -c -F -e "[parkrel]" "$SRC" | tr -d " ")
A_R1381=$(grep -c -F -e "R1381 (c524)" "$SRC" | tr -d " ")
A_ANC=$(grep -c -F -e "SELF-DRIVING KICK AT THE EVENT-DISABLE POLL" "$SRC" | tr -d " ")
echo "[parkrel] refs: got $A_PARK (expect 1)"
echo "R1381 (c524) refs: got $A_R1381 (expect 1)"
echo "anchor refs: got $A_ANC (expect 1, unchanged)"
if [ "$A_PARK" != "1" ] || [ "$A_R1381" != "1" ] || [ "$A_ANC" != "1" ]; then
  echo "VALID-FAILED: gate mismatch - RESTORING the pre-c524 tree"
  cp -p "$SRC.pre_c524" "$SRC"
  exit 0
fi
echo "GATES OK"
echo "===SYNCHK524=== HARD GATE syntax check (unpiped rc)"
cc -w -fsyntax-only -std=gnu99 "$SRC" 2> /tmp/c524_syn_err.txt
RC=$?
head -8 /tmp/c524_syn_err.txt
echo "SYNCHK_RC=$RC"
if [ "$RC" != "0" ]; then
  echo "VALID-FAILED: patched file does not parse - RESTORING the pre-c524 tree"
  cp -p "$SRC.pre_c524" "$SRC"
  exit 0
fi
echo "SYNCHK OK"
NEW=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_TREE_SHA=$NEW"
echo "===RUN524=== build + the 190s verdict run"
export RUN_BUDGET_S=190
bash run.sh 2>&1 | tail -24
echo "RUN_RC=$?"
echo "===DIGEST524==="
LOG="run.log"
if [ ! -s "$LOG" ]; then LOG="run.log.d"; fi
echo "--- the [parkrel] receipts (the fix's own evidence: the release requested in the park):"
grep -n -e "\[parkrel\]" "$LOG" | head -16
echo "--- the release WIN receipts (R1294) + the park-era conversion chain:"
grep -n -e "R1294" "$LOG" | head -8
grep -n -e "fd-tick: converting" "$LOG" | tail -6
grep -n -e "\[defib5\]" "$LOG" | tail -6
echo "--- the response pops in the park era:"
grep -n -e "rspop" "$LOG" | tail -10
echo "--- the sector landings (tail = the 108861 read must appear):"
grep -n -e "cd-dma" "$LOG" | tail -12
echo "--- the FDF8 countdown (the 23744 request):"
grep -n -e "ea=8004FDF8" "$LOG" | tail -14
echo "--- THE PARK EXIT evidence (mvloop count + what follows the last poll):"
grep -c -e "pre-movie polling" "$LOG" | tr -d " " | sed "s/^/mvloop poll prints: /"
LASTMV=$(grep -n -e "pre-movie polling" "$LOG" | tail -1 | cut -d: -f1)
echo "last mvloop at line $LASTMV"
if [ -n "$LASTMV" ]; then
  _S0=$((LASTMV+1))
  echo "--- the 20 lines after the last mvloop (forward execution?):"
  sed -n "${_S0},$((LASTMV+20))p" "$LOG"
fi
echo "--- the ladder markers:"
grep -n -e "MODULE 6 ENTRY" "$LOG" | head -4
grep -n -e "fldx2" "$LOG" | tail -4
echo "--- the death receipt:"
grep -n -e "rungasp" "$LOG" | tail -2
echo "--- log length + tree sha at run time:"
wc -l < "$LOG" | tr -d " " | sed "s/^/log lines: /"
shasum -a 256 "$SRC" | cut -d" " -f1
echo "===C524DONE=== PASS = [parkrel] receipts + the park-era delivery chain + THE PARK EXITING (mvloop polls stop, forward execution past the wait) - digest is pure ASCII"
