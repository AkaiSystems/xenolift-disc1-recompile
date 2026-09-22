#!/bin/bash
# c414_r1377b.sh - THE R1377 PATCH+RUN CYCLE, reship v2
# with the CORRECTED ANCHOR. The c413 PRE gate refused
# correctly (fail-closed, tree untouched): I had gated
# "R1213: park latch reset" == 1 but the TRUE tree has it
# x3 - an unreceipted anchor assumption (the c404 class
# recurring via the anchor). v2 anchors ONLY on
# receipted-unique strings: the c413 refusal itself
# receipted "R1216 re-entry hygiene EXECUTED" == 1,
# R1376 == 4, the resp0-missing print line == 1. THE
# REPAIR (unchanged from c413): after the R1216 hygiene
# print, before the xenolift_boot_epoch++ line that
# follows it in the relay body (shape receipted by the
# c412 source dump), insert the RELAY COLD-INIT
# COMPLETION - guarded heapHead==0, dispatch the game's
# own SoundInitialize (0x80037B88, the R1012
# static-decode contract; heap args are internal
# constants) with the receipted idiom + a post-dispatch
# head receipt (0 = the 957C gate bailed, named for the
# next census). NOT a seed: the pristine image was just
# restored = the same values boot 1 initialized from.
# PLUS the R1376 print resp0-arg fix (c407 apparatus
# debt). PASS = the R1377 receipt with head!=0 + the
# re-boot survives the sound heap + the trajectory
# continues past the prior death point. ANY FAILURE =
# REVERT. Fail-closed gates on receipted counts only;
# tree sha-gated on the R1376 baseline.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C414-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="f92a451cacc252da4b9e13ea00bc2ebbc8ae8c83716753023fd7f8e631115484"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1376 tree - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1376 tree)"
TS=$(date +%Y%m%d_%H%M%S)
PDIR="patch_c414_$TS"
mkdir -p "$PDIR"
cp -p "$SRC" "$PDIR/runtime.c.pre"
echo "PRESERVED: $PDIR/runtime.c.pre"
PRE_G1=$(grep -c "R1377" "$SRC" || true)
PRE_G2=$(grep -c "R1216 re-entry hygiene EXECUTED" "$SRC" || true)
PRE_G3=$(grep -c "R1376" "$SRC" || true)
PRE_G4=$(grep -c '(unsigned)cd_resp_n, restored ? "OWNED"' "$SRC" || true)
PRE_G5=$(grep -c "xenolift_boot_epoch++" "$SRC" || true)
echo "PRE R1377 count=$PRE_G1 (must be 0)"
echo "PRE R1216 hygiene count=$PRE_G2 (must be 1, receipted by the c413 refusal)"
echo "PRE R1376 count=$PRE_G3 (must be 4, receipted by the c413 refusal)"
echo "PRE resp0-missing line count=$PRE_G4 (must be 1, receipted by the c413 refusal)"
echo "PRE epoch++ line count=$PRE_G5 (recorded, must be unchanged POST)"
if [ "$PRE_G1" != "0" ] || [ "$PRE_G2" != "1" ] || [ "$PRE_G3" != "4" ] || [ "$PRE_G4" != "1" ]; then echo "PRE-GATE-FAILED: refusing, nothing done"; exit 0; fi
python3 - <<'PYEOF'
import sys
p = "runtime/runtime.c"
text = open(p).read()
lines = text.split("\n")
h = None
for i, l in enumerate(lines):
    if "R1216 re-entry hygiene EXECUTED" in l:
        h = i
        break
if h is None:
    print("ANCHOR-FAILED: hygiene print not found"); sys.exit(1)
ep = None
for j in range(h + 1, min(h + 11, len(lines))):
    if "xenolift_boot_epoch++" in lines[j]:
        ep = j
        break
if ep is None:
    print("ANCHOR-FAILED: no xenolift_boot_epoch++ within 10 lines of the hygiene print (relay-body shape changed)"); sys.exit(1)
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
lines = lines[:ep] + new + lines[ep:]
patched = "\n".join(lines)
n_resp = 0
if '(unsigned)cd_resp_n, restored ? "OWNED" : "SKIPPED");' in patched:
    patched = patched.replace('(unsigned)cd_resp_n, restored ? "OWNED" : "SKIPPED");',
                    '(unsigned)cd_resp_n, (unsigned)(cd_resp_n > 0u ? cd_resp[0] : 0u), restored ? "OWNED" : "SKIPPED");')
    n_resp = patched.count("cd_resp_n > 0u ? cd_resp[0] : 0u")
else:
    print("ANCHOR-FAILED: resp0-missing line not found"); sys.exit(1)
if patched.count("R1377") != 2: print("POST-FAILED: R1377 != 2 (got %d)" % patched.count("R1377")); sys.exit(1)
if patched.count("SoundInitialize dispatched") != 1: print("POST-FAILED: dispatch receipt != 1"); sys.exit(1)
if patched.count("R1216 re-entry hygiene EXECUTED") != 1: print("POST-FAILED: hygiene print lost"); sys.exit(1)
if patched.count("R1376") != 4: print("POST-FAILED: R1376 block changed"); sys.exit(1)
if patched.count('(unsigned)cd_resp_n, restored ? "OWNED"') != 0: print("POST-FAILED: old resp0 line remains"); sys.exit(1)
if n_resp != 1: print("POST-FAILED: resp0 fix != 1 (got %d)" % n_resp); sys.exit(1)
if patched.count("xenolift_dispatch(0x80037B88u)") != 1: print("POST-FAILED: dispatch call != 1"); sys.exit(1)
open(p, "w").write(patched)
print("PATCH-APPLIED (R1377 relay cold-init completion via the hygiene-print anchor + the R1376 resp0 print fix)")
PYEOF
if [ $? -ne 0 ]; then echo "PATCH-STEP-FAILED: nothing to run"; exit 0; fi
NEW_SHA=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_SHA=$NEW_SHA"
POST_G1=$(grep -c "R1377" "$SRC" || true)
POST_G2=$(grep -c "SoundInitialize dispatched" "$SRC" || true)
POST_G3=$(grep -c "R1376" "$SRC" || true)
POST_G4=$(grep -c "cd_resp_n > 0u ? cd_resp\[0\] : 0u" "$SRC" || true)
POST_G5=$(grep -c "xenolift_boot_epoch++" "$SRC" || true)
echo "POST R1377 count=$POST_G1 (must be 2)"
echo "POST dispatch receipt count=$POST_G2 (must be 1)"
echo "POST R1376 count=$POST_G3 (must be 4, unchanged)"
echo "POST resp0 fix count=$POST_G4 (must be 1)"
echo "POST epoch++ line count=$POST_G5 (must equal PRE $PRE_G5)"
if [ "$POST_G1" != "2" ] || [ "$POST_G2" != "1" ] || [ "$POST_G3" != "4" ] || [ "$POST_G4" != "1" ] || [ "$POST_G5" != "$PRE_G5" ]; then
  echo "POST-GATE-FAILED: restoring the pristine tree"
  cp -p "$PDIR/runtime.c.pre" "$SRC"
  echo "RESTORED"
  exit 0
fi
cc -fsyntax-only -std=gnu99 -Wno-implicit-function-declaration -Wno-int-conversion -Wno-constant-conversion -Wno-int-to-void-pointer-cast "$SRC" 2>/tmp/c414_parse_err.txt
PARSE_RC=$?
echo "PARSE_RC=$PARSE_RC"
if [ $PARSE_RC -ne 0 ]; then
  echo "PARSE-FAILED: restoring the pristine tree (fail-closed)"
  head -12 /tmp/c414_parse_err.txt
  cp -p "$PDIR/runtime.c.pre" "$SRC"
  echo "RESTORED"
  exit 0
fi
echo "PARSE-OK"
echo "===RUN414=== the R1377 build, 120s budget"
RUN_BUDGET_S=120 ./run.sh > /tmp/run_full_c414.txt 2>&1
RUN_RC=$?
echo "RUN_RC=$RUN_RC"
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
if [ ! -s "$LOG" ]; then
  echo "TREE-ROOT-LOG-MISSING: preserving run_full tail"
  tail -25 /tmp/run_full_c414.txt
  exit 0
fi
TL=$(wc -l < "$LOG" | tr -d ' ')
echo "AUTHORITATIVE LOG = $LOG ($TL lines)"
echo "===R1377RELAY414=== the relay cold-init receipts (head!=0 = the re-boot completes)"
grep -n "R1377" "$LOG" | head -10
echo "===SNDINIT414=== the sound-init entries (does #3+ appear? the R966/R1012 cameras)"
grep -n "sndinit" "$LOG" | head -16
echo "===SHHEAD414=== the 59410 ledger (wipe -> re-init story)"
grep -n "shhead\] R1334\|irqc\] 0x80059410" "$LOG" | head -14
echo "===DEATH414=== the relay/exit/death story (did the spiral break?)"
grep -n "b2x\] R718\|b2x\] R722\|b2x\] R725\|segvdie\] R834 TRUE\|rungasp" "$LOG" | head -12
echo "===FAULTS414=== the census (the null-chain must be GONE)"
echo "computed-garbage $(grep -c "computed-garbage" "$LOG" || true)"
grep -n "computed-garbage address" "$LOG" | head -4
echo "bootentry count $(grep -c "bootentry\] R710" "$LOG" || true)"
echo "===FLOW414=== the trajectory end (GPU + spin + park)"
grep -n "gpufin\] R937 GPU final" "$LOG" | tail -3
grep -n "mvloop\] pre-movie" "$LOG" | tail -2
echo "===TAIL414=== the last 14 receipts (non-asciiart)"
awk -v s=$((TL-40)) -v e="$TL" 'NR>=s && NR<=e { print NR": "$0 }' "$LOG" | grep -v "asciiart\|lzss-fence" | head -16
echo "===POSTSHA414==="
shasum -a 256 "$SRC" | cut -d' ' -f1
echo "===C414DONE=== the R1377 v2 cycle is complete - the verdict comes from these receipts"
