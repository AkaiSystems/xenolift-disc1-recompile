#!/bin/bash
# c530_patch.sh - THE FIX THE RECEIPTS SELECTED: THE ZRFF
# COMMAND-BYTE WIDEN (cmd==01 -> cmd==01||cmd==02). THE
# c529 RECEIPTS: the new terminal wedge is the c179 zrfF
# class verbatim - LegacyCdSectorFetch (fn 80042AA8)
# stuck 80s, FDF8=2048 armed, seek=0, FE04=0, act=0,
# pend=0, sched=0, polling 1F801800 408.9M times (THE
# SITE IS PROVEN HOT - the c184 zrfG cold-site trap does
# not apply), the gate machinery running but declining -
# and the ONE differing term is the command byte: the
# c179 gate requires cmd=01, this posture carries cmd=02
# (the late [setloc-clamp] Setloc MSF 00:00:00 -> LBA 0
# was the last command before the fetch). THE REQUEST IS
# LEGITIMATE: the boot-era LBA-0 sectors landed and were
# consumed (fldsec #1-4), and the fetch chain works when
# the drive is active (the first 80042AA8 context: act=1
# loaded=1, fetch DMA drained 12/12 + 2048/2048 natively).
# THE FIX: widen the zrfF gate's command term, ONE term,
# inside the receipted block (the R1282 comment at the
# block head anchors the window; the composite action is
# UNCHANGED: same-poll cd_data_load + cd_read_active=1 so
# the 0x40 bit computes true, the fetch own DMA drains the
# sector, FDF8 2048 -> 0, the fetch completes natively; no
# INT forge, no guest dispatch, budget 12 unchanged).
# GATES: tree sha db0e8c78, the R1282 zrfF block-comment
# anchor unique, the composite string ABSENT pre-patch
# (idempotent, the c404 co-resident lesson: cd_last_cmd ==
# 0x02u PRE-EXISTS in the R955/R990 mvkick - the composite
# form is the marker), exactly ONE substitution inside the
# window (awk gsub counts, window-scoped - an out-of-window
# 0x01u term must NOT be touched), HARD unpiped syntax gate
# with restore-on-fail, then build + the 190s verdict run +
# digest. PASS = [zrfF] fires at the cmd=02 posture, the
# fetch DMA drains the LBA-0 sector, FDF8 2048 -> 0, forward
# execution past the wedge (new read activity, NO new R967
# STUCK era), no c528 regression (heapclr + member-6 dests).
# REVERT if zrfF fires with zero consumption (the c184
# criteria). Fail-closed, tee'd to /tmp/c530_receipts.txt.
# Pure-ASCII output.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C530-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c530_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="db0e8c78788d5b2ab9045693cb95a21627e678c7da474581bfe2f3bdf028ad76"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the c528 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the c528 tree with the landed R1395 heap-band clear)"
COMP="(cd_last_cmd == 0x01u || cd_last_cmd == 0x02u)"
PRE=$(grep -c -F -e "(cd_last_cmd == 0x01u || cd_last_cmd == 0x02u)" "$SRC" | tr -d " ")
echo "composite pre-count: $PRE (expect 0)"
if [ "$PRE" != "0" ]; then echo "VALID-FAILED: the widened composite already present - refusing (idempotent)"; exit 0; fi
ANC=$(grep -c -F -e "R1282 (c179 verdict): zrfF LEGACY-FETCH CONSUMER DOOR" "$SRC" | tr -d " ")
echo "zrfF block-comment count: $ANC (expect 1)"
if [ "$ANC" != "1" ]; then echo "VALID-FAILED: the zrfF anchor is not unique - refusing"; exit 0; fi
B0=$(grep -n -F -e "R1282 (c179 verdict): zrfF LEGACY-FETCH CONSUMER DOOR" "$SRC" | head -1 | cut -d: -f1)
B1=$((B0+70))
echo "===SPLICE530=== widening the zrfF command term in the window $B0..$B1"
cp -p "$SRC" "$SRC.pre_c530"
echo "--- the pre-patch window (the gate lines):"
sed -n "${B0},$((B0+32))p" "$SRC"
awk -v b0="$B0" -v b1="$B1" '
  NR>=b0 && NR<=b1 && /cd_last_cmd == 0x01u/ { n+=gsub(/cd_last_cmd == 0x01u/, "(cd_last_cmd == 0x01u || cd_last_cmd == 0x02u)") }
  { print }
  END { printf "%s\n", n+0 > "/tmp/c530_subs" }
' "$SRC" > /tmp/runtime_new.c
SUBS=$(cat /tmp/c530_subs | tr -d " ")
echo "substitutions made: $SUBS (expect 1)"
if [ "$SUBS" != "1" ]; then
  echo "VALID-FAILED: expected exactly 1 substitution, got $SUBS - RESTORING the pre-c530 tree"
  cp -p "$SRC.pre_c530" "$SRC"
  exit 0
fi
cp /tmp/runtime_new.c "$SRC"
echo "--- the patched gate line (in context):"
GL=$(awk -v b0="$B0" 'NR>=b0 && NR<=b0+70 && /cd_last_cmd == 0x01u \|\| cd_last_cmd == 0x02u/ {print NR}' "$SRC" | head -1)
if [ -n "$GL" ]; then
  _S0=$((GL-3)); [ "$_S0" -lt 1 ] && _S0=1
  sed -n "${_S0},$((GL+3))p" "$SRC"
fi
echo "===GATES530==="
A_COMP=$(grep -c -F -e "(cd_last_cmd == 0x01u || cd_last_cmd == 0x02u)" "$SRC" | tr -d " ")
A_ANC=$(grep -c -F -e "R1282 (c179 verdict): zrfF LEGACY-FETCH CONSUMER DOOR" "$SRC" | tr -d " ")
A_FIRE=$(grep -c -F -e "[zrfF] R1282 legacy-fetch consumer fire" "$SRC" | tr -d " ")
echo "composite refs: got $A_COMP (expect 1)"
echo "anchor refs: got $A_ANC (expect 1, unchanged)"
echo "fire print refs: got $A_FIRE (expect 1, unchanged)"
if [ "$A_COMP" != "1" ] || [ "$A_ANC" != "1" ] || [ "$A_FIRE" != "1" ]; then
  echo "VALID-FAILED: gate mismatch - RESTORING the pre-c530 tree"
  cp -p "$SRC.pre_c530" "$SRC"
  exit 0
fi
echo "GATES OK"
echo "===SYNCHK530=== HARD GATE syntax check (unpiped rc)"
cc -w -fsyntax-only -std=gnu99 "$SRC" 2> /tmp/c530_syn_err.txt
RC=$?
head -8 /tmp/c530_syn_err.txt
echo "SYNCHK_RC=$RC"
if [ "$RC" != "0" ]; then
  echo "VALID-FAILED: patched file does not parse - RESTORING the pre-c530 tree"
  cp -p "$SRC.pre_c530" "$SRC"
  exit 0
fi
echo "SYNCHK OK"
NEW=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_TREE_SHA=$NEW"
echo "===RUN530=== build + the 190s verdict run"
export RUN_BUDGET_S=190
bash run.sh 2>&1 | tail -24
echo "RUN_RC=$?"
echo "===DIGEST530==="
LOG="run.log"
if [ ! -s "$LOG" ]; then LOG="run.log.d"; fi
echo "--- the [zrfF] receipts (the fix's own evidence - the fires at the cmd=02 posture):"
grep -n -e "\[zrfF\]" "$LOG" | head -8
echo "--- the fetch drain + forward execution (LBA-0 sectors + new activity past the wedge):"
grep -n -e "cd-dma" "$LOG" | grep -e "LBA 0" | tail -6
grep -n -e "fldsec" "$LOG" | tail -6
grep -n -e "R967 STUCK" "$LOG" | tail -6
echo "--- the wedge-era line span vs the last activity:"
wc -l < "$LOG" | tr -d " " | sed "s/^/log lines: /"
tail -16 "$LOG"
echo "--- NO REGRESSION: the c528 fixes still hold:"
grep -n -e "\[heapclr\]" "$LOG" | head -4
grep -n -e "\[newmod\]" "$LOG" | grep -e "member=6" | head -4
grep -c -e "r31=0000000A" "$LOG" | tr -d " " | sed "s/^/r31=0A receipts (expect 0): /"
echo "--- the ladder + screen witnesses:"
grep -n -e "MODULE 6 ENTRY" "$LOG" | head -3
grep -n -e "vram_nonzero" "$LOG" | tail -4
echo "--- tree sha at run time:"
shasum -a 256 "$SRC" | cut -d" " -f1
echo "===C530DONE=== PASS = zrfF fires at the cmd=02 posture + the fetch drains + FDF8 2048->0 + forward execution past the wedge + no c528 regression - digest is pure ASCII"
