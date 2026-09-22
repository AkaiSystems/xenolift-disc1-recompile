#!/bin/bash
# c413_r1377.sh - THE R1377 PATCH+RUN CYCLE (relay
# cold-init completion). THE c407-c412 receipts closed
# the death spiral: a guest exit(0) relays a
# console-faithful re-boot (R722 pristine exe restore +
# R1216 hygiene + bootmain re-entry), but the re-booted
# walk SKIPPED SoundInitialize - 59410 stayed null, the
# re-boot walked the null sound heap into the
# free-sentinel mask -> computed-garbage -> recoveries ->
# TRUE DEATH. A real shell relaunch re-runs the FULL
# boot. THE REPAIR: after the R1216 hygiene, guarded
# heapHead==0 (cold boots + healthy re-boots
# unaffected), dispatch the game's own SoundInitialize
# (0x80037B88, the R1012 static-decode contract; the
# heap args are internal constants) with the receipted
# idiom (g_guest_depth++/dispatch/guest_depth--) + a
# post-dispatch head receipt (0 = the 957C gate bailed,
# named for the next census). NOT a seed: the pristine
# image was just restored = the same values boot 1
# initialized from. PLUS the c407 apparatus debt: the
# R1376 dossier print's missing resp0 argument (verified
# with a format-attributed stub, -Wall -Wformat clean).
# PASS = the R1377 receipt with head!=0 + the re-boot
# survives the sound heap (no null-chain computed-garbage
# at the sound head) + the trajectory continues past the
# prior death point. ANY FAILURE = REVERT. Fail-closed
# pre/post gates + tolerant parse gate, tree sha-gated on
# the R1376 baseline.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C413-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="f92a451cacc252da4b9e13ea00bc2ebbc8ae8c83716753023fd7f8e631115484"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1376 tree - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1376 tree)"
TS=$(date +%Y%m%d_%H%M%S)
PDIR="patch_c413_$TS"
mkdir -p "$PDIR"
cp -p "$SRC" "$PDIR/runtime.c.pre"
echo "PRESERVED: $PDIR/runtime.c.pre"
PRE_G1=$(grep -c "R1377" "$SRC" || true)
PRE_G2=$(grep -c "R1213: park latch reset" "$SRC" || true)
PRE_G3=$(grep -c "R1216 re-entry hygiene EXECUTED" "$SRC" || true)
PRE_G4=$(grep -c "R1376" "$SRC" || true)
PRE_G5=$(grep -c '(unsigned)cd_resp_n, restored ? "OWNED"' "$SRC" || true)
echo "PRE R1377 count=$PRE_G1 (must be 0)"
echo "PRE R1213 anchor count=$PRE_G2 (must be 1)"
echo "PRE R1216 hygiene count=$PRE_G3 (must be 1)"
echo "PRE R1376 count=$PRE_G4 (must be 4, the shipped block)"
echo "PRE resp0-missing line count=$PRE_G5 (must be 1)"
if [ "$PRE_G1" != "0" ] || [ "$PRE_G2" != "1" ] || [ "$PRE_G3" != "1" ] || [ "$PRE_G4" != "4" ] || [ "$PRE_G5" != "1" ]; then echo "PRE-GATE-FAILED: refusing, nothing done"; exit 0; fi
python3 - <<'PYEOF'
import sys
p = "runtime/runtime.c"
text = open(p).read()
lines = text.split("\n")
out = []
e = 0
for l in lines:
    if "R1213: park latch reset" in l:
        I = " " * 12
        new = []
        new.append(I + "{   /* R1377 (c412): RELAY COLD-INIT COMPLETION. The c407-c412")
        new.append(I + " * receipts closed the death spiral: a guest exit(0) relays a")
        new.append(I + " * console-faithful re-boot, but the re-booted walk SKIPPED")
        new.append(I + " * SoundInitialize (no entry #3 anywhere; the boot wipes 59410")
        new.append(I + " * and nothing re-initializes it), so the re-booted trajectory")
        new.append(I + " * walked the null sound heap into the free-sentinel mask ->")
        new.append(I + " * computed-garbage -> recoveries -> TRUE DEATH. A real shell")
        new.append(I + " * relaunch re-runs the FULL boot; complete the relay's")
        new.append(I + " * semantics by dispatching the game's own sound init once")
        new.append(I + " * per relay, guarded to fire ONLY when the head is still")
        new.append(I + " * null (cold boots and healthy re-boots unaffected). The")
        new.append(I + " * R722 pristine image was just restored, so the gate cell")
        new.append(I + " * 957C and the heap region hold the same values boot 1")
        new.append(I + " * initialized from - this is the boot-1 call replayed by the")
        new.append(I + " * same dispatch idiom, NOT a seed. The receipt prints the")
        new.append(I + " * post-dispatch head: 0 = the gate bailed (957C story next). */")
        new.append(I + "    if (xenolift_mem_read32(0x80059410u) == 0u) {")
        new.append(I + "        g_guest_depth++, xenolift_dispatch(0x80037B88u), g_guest_depth--;")
        new.append(I + '        r861_out("[b2x] R1377 relay cold-init: SoundInitialize dispatched (head was 0, post-dispatch head=%08X) - the re-boot completes the shell-relaunch semantics\\n",')
        new.append(I + "                xenolift_mem_read32(0x80059410u));")
        new.append(I + "    }")
        new.append(I + "}")
        out.extend(new)
        e += 1
        out.append(l)
        continue
    if '(unsigned)cd_resp_n, restored ? "OWNED" : "SKIPPED");' in l:
        out.append(l.replace('(unsigned)cd_resp_n, restored ? "OWNED" : "SKIPPED");',
                        '(unsigned)cd_resp_n, (unsigned)(cd_resp_n > 0u ? cd_resp[0] : 0u), restored ? "OWNED" : "SKIPPED");'))
        e += 1
        continue
    out.append(l)
if e != 2:
    print("ANCHOR-FAILED: edits %d (must be 2)" % e); sys.exit(1)
patched = "\n".join(out)
if patched.count("R1377") != 2: print("POST-FAILED: R1377 != 2"); sys.exit(1)
if patched.count("SoundInitialize dispatched") != 1: print("POST-FAILED: dispatch receipt != 1"); sys.exit(1)
if patched.count("R1213: park latch reset") != 1: print("POST-FAILED: anchor lost"); sys.exit(1)
if patched.count("R1216 re-entry hygiene EXECUTED") != 1: print("POST-FAILED: hygiene print lost"); sys.exit(1)
if patched.count("R1376") != 4: print("POST-FAILED: R1376 block changed"); sys.exit(1)
if patched.count('(unsigned)cd_resp_n, restored ? "OWNED"') != 0: print("POST-FAILED: old resp0 line remains"); sys.exit(1)
if patched.count("cd_resp_n > 0u ? cd_resp[0] : 0u") != 1: print("POST-FAILED: resp0 fix != 1"); sys.exit(1)
if patched.count("xenolift_dispatch(0x80037B88u)") != 1: print("POST-FAILED: dispatch call != 1"); sys.exit(1)
open(p, "w").write(patched)
print("PATCH-APPLIED (R1377 relay cold-init completion + the R1376 resp0 print fix)")
PYEOF
if [ $? -ne 0 ]; then echo "PATCH-STEP-FAILED: nothing to run"; exit 0; fi
NEW_SHA=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_SHA=$NEW_SHA"
POST_G1=$(grep -c "R1377" "$SRC" || true)
POST_G2=$(grep -c "SoundInitialize dispatched" "$SRC" || true)
POST_G3=$(grep -c "R1376" "$SRC" || true)
POST_G4=$(grep -c "cd_resp_n > 0u ? cd_resp\[0\] : 0u" "$SRC" || true)
echo "POST R1377 count=$POST_G1 (must be 2)"
echo "POST dispatch receipt count=$POST_G2 (must be 1)"
echo "POST R1376 count=$POST_G3 (must be 4, unchanged)"
echo "POST resp0 fix count=$POST_G4 (must be 1)"
if [ "$POST_G1" != "2" ] || [ "$POST_G2" != "1" ] || [ "$POST_G3" != "4" ] || [ "$POST_G4" != "1" ]; then
  echo "POST-GATE-FAILED: restoring the pristine tree"
  cp -p "$PDIR/runtime.c.pre" "$SRC"
  echo "RESTORED"
  exit 0
fi
cc -fsyntax-only -std=gnu99 -Wno-implicit-function-declaration -Wno-int-conversion -Wno-constant-conversion -Wno-int-to-void-pointer-cast "$SRC" 2>/tmp/c413_parse_err.txt
PARSE_RC=$?
echo "PARSE_RC=$PARSE_RC"
if [ $PARSE_RC -ne 0 ]; then
  echo "PARSE-FAILED: restoring the pristine tree (fail-closed)"
  head -12 /tmp/c413_parse_err.txt
  cp -p "$PDIR/runtime.c.pre" "$SRC"
  echo "RESTORED"
  exit 0
fi
echo "PARSE-OK"
echo "===RUN413=== the R1377 build, 120s budget"
RUN_BUDGET_S=120 ./run.sh > /tmp/run_full_c413.txt 2>&1
RUN_RC=$?
echo "RUN_RC=$RUN_RC"
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
if [ ! -s "$LOG" ]; then
  echo "TREE-ROOT-LOG-MISSING: preserving run_full tail"
  tail -25 /tmp/run_full_c413.txt
  exit 0
fi
TL=$(wc -l < "$LOG" | tr -d ' ')
echo "AUTHORITATIVE LOG = $LOG ($TL lines)"
echo "===R1377RELAY413=== the relay cold-init receipts (head!=0 = the re-boot completes)"
grep -n "R1377" "$LOG" | head -10
echo "===SNDINIT413=== the sound-init entries (does #3+ appear? the R966/R1012 cameras)"
grep -n "sndinit" "$LOG" | head -16
echo "===SHHEAD413=== the 59410 ledger (wipe -> re-init story)"
grep -n "shhead\] R1334\|irqc\] 0x80059410" "$LOG" | head -14
echo "===DEATH413=== the relay/exit/death story (did the spiral break?)"
grep -n "b2x\] R718\|b2x\] R722\|b2x\] R725\|segvdie\] R834 TRUE\|rungasp" "$LOG" | head -12
echo "===FAULTS413=== the census (the null-chain must be GONE)"
echo "computed-garbage $(grep -c "computed-garbage" "$LOG" || true)"
grep -n "computed-garbage address" "$LOG" | head -4
echo "bootentry count $(grep -c "bootentry\] R710" "$LOG" || true)"
echo "===FLOW413=== the trajectory end (GPU + spin + park)"
grep -n "gpufin\] R937 GPU final" "$LOG" | tail -3
grep -n "mvloop\] pre-movie" "$LOG" | tail -2
echo "===TAIL413=== the last 14 receipts (non-asciiart)"
awk -v s=$((TL-40)) -v e="$TL" 'NR>=s && NR<=e { print NR": "$0 }' "$LOG" | grep -v "asciiart\|lzss-fence" | head -16
echo "===POSTSHA413==="
shasum -a 256 "$SRC" | cut -d' ' -f1
echo "===C413DONE=== the R1377 cycle is complete - the verdict comes from these receipts"
