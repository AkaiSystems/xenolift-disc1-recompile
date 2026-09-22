#!/bin/bash
# c497_patch.sh - STAGE B-1 OF THE OVERLAY-IDENTITY FIX:
# THE R1393 GUARD (Jos's mandate implemented): dispatch
# selects translations by (address, identity); unknown code
# STOPS EXPLICITLY - never an unrelated translation. (1)
# EXTRACT the emit-era reference window from
# firstfault.pSYW6z/guest-ram.bin (the ONLY full-window
# artifact whose bytes at the receipted fault addresses
# match the emitted bodies exactly) to emit_ref.bin;
# BYTE-VERIFY it against 27BDFFB8 3C041F80 3C051F80
# 34A50028 @0x47EC and 8FB20030 8FB1002C 8FB00028 27BD0048
# @0x49A0 - refuse everything if either differs. (2) PATCH
# runtime.c: the R1393 guard - at every module-window
# dispatch in xenolift_trace, compare the live first 16
# bytes vs the reference; MISMATCH -> the [ovlstop]
# dossier + capture the window to ovlstop_capture.bin +
# _exit(99), the diagnostic-stop door. CAMERAS + the stop
# are the ONLY behavior change. (3) Hard-gated unpiped
# syntax check; build + the 190s verdict run + digest.
# EXPECTED PASS: [ovlstop] at boot's module-6 entry
# (live = the YMPIkM-class != the pSYW6z-class ref), exit
# 99, NO wild jump, NO menu park (the ladder shrinks
# honestly until the interpreter stage). Fail-closed,
# tee'd to /tmp/c497_receipts.txt. Pure-ASCII output.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C497-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c497_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="2b78e89b5a8af077eb73e21c18882705ebfd01a0d9b311295c1104278ae547ae"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the c495 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the c495 tree)"
echo "===REF497=== extract + byte-verify the emit-era reference"
if [ ! -f "firstfault.pSYW6z/guest-ram.bin" ]; then echo "GATE-FAILED: the pSYW6z dump is missing - refusing"; exit 0; fi
dd bs=4096 skip=111 count=33 if="firstfault.pSYW6z/guest-ram.bin" of=emit_ref.bin 2>/dev/null
RSZ=$(wc -c < emit_ref.bin | tr -d " ")
echo "emit_ref.bin size=$RSZ sha=$(shasum -a 256 emit_ref.bin | cut -d" " -f1)"
if [ "$RSZ" != "135168" ]; then echo "GATE-FAILED: reference extraction short - refusing"; exit 0; fi
python3 - <<'PYEOF'
import struct
ref = open("emit_ref.bin", "rb").read()
ok1 = list(struct.unpack("<4I", ref[0x47EC:0x47EC+16])) == [0x27BDFFB8, 0x3C041F80, 0x3C051F80, 0x34A50028]
ok2 = list(struct.unpack("<4I", ref[0x49A0:0x49A0+16])) == [0x8FB20030, 0x8FB1002C, 0x8FB00028, 0x27BD0048]
print("ref @0x47EC: %s (expect 27BDFFB8 3C041F80 3C051F80 34A50028) -> %s" % (" ".join("%08X" % w for w in struct.unpack("<4I", ref[0x47EC:0x47EC+16])), "MATCH" if ok1 else "DIFFER"))
print("ref @0x49A0: %s (expect 8FB20030 8FB1002C 8FB00028 27BD0048) -> %s" % (" ".join("%08X" % w for w in struct.unpack("<4I", ref[0x49A0:0x49A0+16])), "MATCH" if ok2 else "DIFFER"))
if not (ok1 and ok2):
    print("GATE-FAILED: the reference does not match the receipted emit-source bytes - refusing")
    raise SystemExit(3)
print("REFERENCE VERIFIED (the emit-era window, receipted at the fault addresses)")
PYEOF
if [ "$?" != "0" ]; then echo "GATE-FAILED: reference verify failed"; exit 0; fi
if grep -q "r1393_guard" "$SRC"; then echo "VALID-FAILED: R1393 already present - refusing (idempotent)"; exit 0; fi
CL=$(grep -n -e "r1392_check(a);" "$SRC" | head -1 | cut -d: -f1)
if [ -z "$CL" ]; then echo "VALID-FAILED: the r1392_check call site not found - refusing"; exit 0; fi
echo "guard call splice after line $CL"
cat > /tmp/r1393_head.c <<'BLOCKEOF'
/* R1393 (c497): OVERLAY-IDENTITY GUARD, stage B-1 (Jos c493 mandate):
 * dispatch selects translations by (address, overlay identity); unknown code
 * stops EXPLICITLY - never an unrelated translation. The emit-era reference
 * is emit_ref.bin (firstfault.pSYW6z/guest-ram.bin's module window, the only
 * full-window artifact whose bytes at 0x800737EC and 0x800739A0 match the
 * emitted bodies exactly - c491/c495 receipts). At every module-window
 * dispatch (0x8006F000..0x80090000) the live first 16 bytes are compared
 * against the reference; MISMATCH = the installed module is not the one this
 * translation was compiled from: print the dossier, capture the window for
 * the interpreter stage, and stop via the diagnostic door (exit 99). Limit
 * (receipted, stage B-1): a 16-byte entry check; whole-body identity checks
 * belong to the emitter (per-fn source stamps). */
static unsigned char g_r1393_ref[0x21000];
static int g_r1393_ref_loaded = 0;
static int r1393_guard(unsigned int fn);
BLOCKEOF
cat > /tmp/r1393_tail.c <<'TAILEOF'

/* R1393 (c497): the guard definition - appended at the END of the file so
 * every symbol it references is already in scope. SELF-CONTAINED includes
 * (the sandbox synchk caught the missing stdio: never assume the host file
 * already included what the appended code needs). */
#include <stdio.h>
#include <string.h>
#include <unistd.h>
static int r1393_guard(unsigned int fn)
{
    unsigned char lw[16];
    unsigned int a0, a1, a2, a3, b0, b1, b2, b3;
    unsigned int off;
    if (fn < 0x8006F000u || fn >= 0x80090000u) { return 0; }
    if (g_r1393_ref_loaded == 0) {
        FILE *f = fopen("emit_ref.bin", "rb");
        if (!f) {
            r861_out("[ovlstop] R1393 emit_ref.bin missing - guard INACTIVE (place the reference next to the runtime)\n");
            g_r1393_ref_loaded = -1; return 0;
        }
        if (fread(g_r1393_ref, 1u, 0x21000u, f) != 0x21000u) {
            r861_out("[ovlstop] R1393 emit_ref.bin short - guard INACTIVE\n");
            fclose(f); g_r1393_ref_loaded = -1; return 0;
        }
        fclose(f);
        g_r1393_ref_loaded = 1;
        r861_out("[ovlstop] R1393 emit-era reference loaded (the pSYW6z window, receipted at the fault addresses)\n");
    }
    if (g_r1393_ref_loaded < 0) { return 0; }
    off = fn - 0x8006F000u;
    memcpy(lw, xenolift_mem + (fn - 0x80000000u), 16);
    if (memcmp(lw, g_r1393_ref + off, 16) == 0) { return 0; }
    memcpy(&a0, lw, 4); memcpy(&a1, lw + 4, 4);
    memcpy(&a2, lw + 8, 4); memcpy(&a3, lw + 12, 4);
    memcpy(&b0, g_r1393_ref + off, 4); memcpy(&b1, g_r1393_ref + off + 4, 4);
    memcpy(&b2, g_r1393_ref + off + 8, 4); memcpy(&b3, g_r1393_ref + off + 12, 4);
    r861_out("[ovlstop] R1393 UNSUPPORTED-OVERLAY STOP fn=0x%08X: the installed module is NOT this translation's source (live=%08X %08X %08X %08X ref=%08X %08X %08X %08X) - halting instead of executing an unrelated translation; the window is captured for the interpreter stage\n",
        fn, a0, a1, a2, a3, b0, b1, b2, b3);
    {
        FILE *cf = fopen("ovlstop_capture.bin", "wb");
        if (cf) {
            fwrite(xenolift_mem + 0x6F000u, 1u, 0x21000u, cf);
            fclose(cf);
            r861_out("[ovlstop] R1393 window captured to ovlstop_capture.bin (135168 bytes, for the interpreter stage)\n");
        }
    }
    fflush(0);
    _exit(99);
    return 0;
}
TAILEOF
cp -p "$SRC" "$SRC.pre_c497"
HLINES=$(wc -l < /tmp/r1393_head.c | tr -d " ")
echo "HEAD lines=$HLINES - prepending at line 1"
{ cat /tmp/r1393_head.c; cat "$SRC"; } > /tmp/rt_p1.c
NEWCL=$((CL + HLINES))
awk -v L="$NEWCL" 'NR==L {print; print "    r1393_guard(a);"; next} {print}' /tmp/rt_p1.c > /tmp/rt_p2.c
{ cat /tmp/rt_p2.c; cat /tmp/r1393_tail.c; } > /tmp/rt_new.c
mv /tmp/rt_new.c "$SRC"
echo "===GATES497==="
E_OVL=$(grep -c "ovlstop" /tmp/r1393_tail.c | tr -d " ")
A_OVL=$(grep -c "ovlstop" "$SRC" | tr -d " ")
E_GRD=$(grep -c "r1393_guard" /tmp/r1393_tail.c | tr -d " ")
E_HD=$(grep -c "r1393_guard" /tmp/r1393_head.c | tr -d " ")
E_GRD=$((E_GRD + E_HD + 1))
A_GRD=$(grep -c "r1393_guard" "$SRC" | tr -d " ")
echo "ovlstop refs: expect $E_OVL got $A_OVL"
echo "r1393_guard refs: expect $E_GRD got $A_GRD"
echo "guard call line: $(sed -n "${NEWCL}p" "$SRC") + $(sed -n "$((NEWCL+1))p" "$SRC")"
if [ "$A_OVL" != "$E_OVL" ] || [ "$A_GRD" != "$E_GRD" ]; then
  echo "VALID-FAILED: gate mismatch - RESTORING the pre-c497 tree"
  cp -p "$SRC.pre_c497" "$SRC"
  exit 0
fi
echo "GATES OK - the tree carries R1393"
NEW=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_TREE_SHA=$NEW"
echo "===SYNCHK497=== HARD GATE syntax check (unpiped rc)"
cc -fsyntax-only "$SRC" > /tmp/c497_syn.txt 2>&1
SYN_RC=$?
head -8 /tmp/c497_syn.txt
echo "SYNCHK_RC=$SYN_RC"
if [ "$SYN_RC" != "0" ]; then
  echo "VALID-FAILED: the patched tree does not parse - RESTORING the pre-c497 tree"
  cp -p "$SRC.pre_c497" "$SRC"
  exit 0
fi
echo "SYNCHK OK"
echo "===RUN497=== build + the 190s verdict run"
export RUN_BUDGET_S=190
bash run.sh 2>&1 | tail -30
echo "RUN_RC=$?"
echo "===DIGEST497==="
LOG="run.log"
if [ ! -s "$LOG" ]; then LOG="run.log.d"; fi
echo "--- the [ovlstop] receipts (the guard):"
grep -n -e "ovlstop" "$LOG" | head -12
echo "--- the capture:"
ls -la ovlstop_capture.bin 2>/dev/null
if [ -f ovlstop_capture.bin ]; then shasum -a 256 ovlstop_capture.bin | cut -d" " -f1; fi
echo "--- the early ladder + the death receipt:"
grep -n -e "MODULE 6 ENTRY" "$LOG" | head -3
grep -n -e "wildctx" "$LOG" | head -2
grep -n -e "rungasp" "$LOG" | tail -2
echo "--- tree sha at run time:"
shasum -a 256 "$SRC" | cut -d" " -f1
echo "===C497DONE=== PASS = [ovlstop] at the first wrong dispatch + exit 99 + NO wild jump; the interpreter stage follows - digest is pure ASCII"
