#!/bin/bash
# c531_patch.sh - THE c530 RESHIP (the gate fix, the widen
# UNCHANGED). THE c530 REFUSAL RECEIPTED A NEW INSTANCE OF
# THE c404 CO-RESIDENT CLASS: the composite string
# (cd_last_cmd == 0x01u || cd_last_cmd == 0x02u) PRE-EXISTS
# TWICE in the true tree (other doors already accept both
# commands) - the c530 sandbox synthetic omitted them, so
# the whole-file pre-count==0 gate was wrong against the
# TRUE shape. The tree is UNTOUCHED (db0e8c78) - fail-closed
# held; the MARKER was the defect, not the widen. THE WEDGE
# ITSELF PROVES the zrfF gate does NOT have the composite
# (cmd=02 would have fired it) - the widen remains THE fix
# the receipts selected: the legacy fetch (80042AA8)
# starves 80s, FDF8=2048 armed, seek=0, FE04=0, act=0,
# pend=0, cmd=02, polling 1F801800 408.9M times; the site
# is HOT, the request LEGITIMATE (the late setloc-clamp
# Setloc 00:00:00 -> LBA 0), the boot-era LBA-0 sectors
# landed and were consumed. THE GATE FIX (the never-twice
# rule): idempotency + post-count gates are WINDOW-SCOPED
# to the zrfF block (B0..B0+70 from the unique R1282
# block-comment anchor) - the window composite pre-count
# MUST be 0 (a composite inside the window would also
# corrupt the gsub - refuse), the window MUST contain the
# plain cd_last_cmd == 0x01u term, the substitution count
# MUST be exactly 1, the window composite post-count MUST
# be 1. Whole-file composite counts are PRINTED, never
# gated (co-residents are legitimate). HARD unpiped syntax
# gate with restore-on-fail, then build + the 190s verdict
# run + digest. PASS = [zrfF] fires at the cmd=02 posture +
# the fetch DMA drains the LBA-0 sector + FDF8 2048 -> 0 +
# forward execution past the wedge + no c528 regression.
# REVERT if zrfF fires with zero consumption. Fail-closed,
# tee'd to /tmp/c531_receipts.txt. Pure-ASCII output.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C531-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c531_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="db0e8c78788d5b2ab9045693cb95a21627e678c7da474581bfe2f3bdf028ad76"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the c528 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the c528 tree with the landed R1395 heap-band clear)"
ANC=$(grep -c -F -e "R1282 (c179 verdict): zrfF LEGACY-FETCH CONSUMER DOOR" "$SRC" | tr -d " ")
echo "zrfF block-comment count: $ANC (expect 1)"
if [ "$ANC" != "1" ]; then echo "VALID-FAILED: the zrfF anchor is not unique - refusing"; exit 0; fi
B0=$(grep -n -F -e "R1282 (c179 verdict): zrfF LEGACY-FETCH CONSUMER DOOR" "$SRC" | head -1 | cut -d: -f1)
B1=$((B0+70))
echo "zrfF window: $B0..$B1"
echo "--- whole-file composite count (INFORMATION ONLY, never gated - co-residents are legitimate):"
grep -c -F -e "(cd_last_cmd == 0x01u || cd_last_cmd == 0x02u)" "$SRC" | tr -d " " | sed "s/^/whole-file composite count: /"
WPRE=$(awk -v b0="$B0" -v b1="$B1" 'NR>=b0 && NR<=b1 && /\(cd_last_cmd == 0x01u \|\| cd_last_cmd == 0x02u\)/ {c++} END {print c+0}' "$SRC")
echo "window composite pre-count: $WPRE (expect 0)"
if [ "$WPRE" != "0" ]; then echo "VALID-FAILED: a composite already exists INSIDE the zrfF window - refusing (the gsub would corrupt it)"; exit 0; fi
WT=$(awk -v b0="$B0" -v b1="$B1" 'NR>=b0 && NR<=b1 && /cd_last_cmd == 0x01u/ {c++} END {print c+0}' "$SRC")
echo "window plain-cmd-term lines: $WT (expect >=1)"
if [ "$WT" -lt 1 ]; then echo "VALID-FAILED: no cd_last_cmd == 0x01u term inside the zrfF window - refusing"; exit 0; fi
echo "===SPLICE531=== widening the zrfF command term in the window $B0..$B1"
cp -p "$SRC" "$SRC.pre_c531"
echo "--- the pre-patch window (the gate lines):"
sed -n "${B0},$((B0+32))p" "$SRC"
awk -v b0="$B0" -v b1="$B1" '
  NR>=b0 && NR<=b1 && /cd_last_cmd == 0x01u/ { n+=gsub(/cd_last_cmd == 0x01u/, "(cd_last_cmd == 0x01u || cd_last_cmd == 0x02u)") }
  { print }
  END { printf "%s\n", n+0 > "/tmp/c531_subs" }
' "$SRC" > /tmp/runtime_new.c
SUBS=$(cat /tmp/c531_subs | tr -d " ")
echo "substitutions made: $SUBS (expect 1)"
if [ "$SUBS" != "1" ]; then
  echo "VALID-FAILED: expected exactly 1 substitution, got $SUBS - RESTORING the pre-c531 tree"
  cp -p "$SRC.pre_c531" "$SRC"
  exit 0
fi
cp /tmp/runtime_new.c "$SRC"
echo "--- the patched gate line (in context):"
GL=$(awk -v b0="$B0" 'NR>=b0 && NR<=b0+70 && /cd_last_cmd == 0x01u \|\| cd_last_cmd == 0x02u/ {print NR}' "$SRC" | head -1)
if [ -n "$GL" ]; then
  _S0=$((GL-3)); [ "$_S0" -lt 1 ] && _S0=1
  sed -n "${_S0},$((GL+3))p" "$SRC"
fi
echo "===GATES531==="
WPOST=$(awk -v b0="$B0" -v b1="$B1" 'NR>=b0 && NR<=b1 && /\(cd_last_cmd == 0x01u \|\| cd_last_cmd == 0x02u\)/ {c++} END {print c+0}' "$SRC")
A_ANC=$(grep -c -F -e "R1282 (c179 verdict): zrfF LEGACY-FETCH CONSUMER DOOR" "$SRC" | tr -d " ")
A_FIRE=$(grep -c -F -e "[zrfF] R1282 legacy-fetch consumer fire" "$SRC" | tr -d " ")
WPRE2=$(awk -v b0="$B0" -v b1="$B1" 'NR>=b0 && NR<=b1 && /cd_last_cmd == 0x01u/ && !/0x02u/ {c++} END {print c+0}' "$SRC")
echo "window composite post-count: got $WPOST (expect 1)"
echo "anchor refs: got $A_ANC (expect 1, unchanged)"
echo "fire print refs: got $A_FIRE (expect 1, unchanged)"
echo "window plain-term remainder: got $WPRE2 (expect 0 - every plain term in-window was widened)"
if [ "$WPOST" != "1" ] || [ "$A_ANC" != "1" ] || [ "$A_FIRE" != "1" ] || [ "$WPRE2" != "0" ]; then
  echo "VALID-FAILED: gate mismatch - RESTORING the pre-c531 tree"
  cp -p "$SRC.pre_c531" "$SRC"
  exit 0
fi
echo "GATES OK"
echo "===SYNCHK531=== HARD GATE syntax check (unpiped rc)"
cc -w -fsyntax-only -std=gnu99 "$SRC" 2> /tmp/c531_syn_err.txt
RC=$?
head -8 /tmp/c531_syn_err.txt
echo "SYNCHK_RC=$RC"
if [ "$RC" != "0" ]; then
  echo "VALID-FAILED: patched file does not parse - RESTORING the pre-c531 tree"
  cp -p "$SRC.pre_c531" "$SRC"
  exit 0
fi
echo "SYNCHK OK"
NEW=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_TREE_SHA=$NEW"
echo "===RUN531=== build + the 190s verdict run"
export RUN_BUDGET_S=190
bash run.sh 2>&1 | tail -24
echo "RUN_RC=$?"
echo "===DIGEST531==="
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
echo "===C531DONE=== PASS = zrfF fires at the cmd=02 posture + the fetch drains + FDF8 2048->0 + forward execution past the wedge + no c528 regression - digest is pure ASCII"
