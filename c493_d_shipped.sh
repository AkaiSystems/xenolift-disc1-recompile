#!/bin/bash
# c493_patch.sh - THE c492 RESHIP (the compile-fail lesson
# applied). The c492 build failed: the real runtime.c has
# its #include lines BELOW the cur_fn setter, so the
# prototype landed below the call site; the syntax check
# SAW the errors but its rc was swallowed by a pipe and
# the broken tree reached the run (the compile refused, a
# stale binary never ran). FIXES: (1) RESTORE the
# .pre_c492 backup first; (2) PREPEND the R1392 globals +
# prototype at LINE 1 (always before every use); (3) the
# syntax check is a HARD GATE with the compiler rc
# captured UNPIPED - restore on failure; (4) the call
# splice accounts for the prepend's line-shift. The
# R1392 camera itself is UNCHANGED (cameras only): the
# overlay-identity validation per dispatch. Fail-closed,
# tee'd to /tmp/c493_receipts.txt. Pure-ASCII output.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C493-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c493_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="d86f3deb57aed5b0921ab3a82867dea3a1e1d9960028e360bed8d9bdc90d45f8"
echo "===RESTORE493=== restore the pre-c492 baseline if present"
if [ -f "$SRC.pre_c492" ]; then
  cp -p "$SRC.pre_c492" "$SRC"
  echo "restored from $SRC.pre_c492: sha=$(shasum -a 256 "$SRC" | cut -d" " -f1)"
fi
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the R1387 baseline - refusing"; exit 0; fi
echo "TREE_VERIFIED (the R1387 baseline)"
if grep -q "r1392_check" "$SRC"; then echo "VALID-FAILED: R1392 already present - refusing (idempotent)"; exit 0; fi
SETLN=$(grep -n "xenolift_cur_fn = " "$SRC" | grep -v "==" | head -1 | cut -d: -f1)
if [ -z "$SETLN" ]; then SETLN=$(grep -n "xenolift_cur_fn=" "$SRC" | grep -v "==" | head -1 | cut -d: -f1); fi
if [ -z "$SETLN" ]; then echo "VALID-FAILED: no xenolift_cur_fn setter found - refusing"; exit 0; fi
SETLINE=$(sed -n "${SETLN}p" "$SRC")
echo "SETTER line $SETLN: $SETLINE"
RHS=$(printf "%s" "$SETLINE" | sed "s/^[^=]*= *//; s/;.*//")
echo "RHS=$RHS"
if [ -z "$RHS" ]; then echo "VALID-FAILED: could not extract the setter RHS - refusing"; exit 0; fi
cat > /tmp/r1392_head.c <<'BLOCKEOF'
/* R1392 (c492/c493): OVERLAY-IDENTITY VALIDATION CAMERA - cameras only, no
 * behavior change. The c485-c491 receipts PROVED the dispatcher executed
 * boot-era translations after the movie phase unpacked its own module into
 * the window (word-0 mismatch at 0x800739A0; the emitted bodies match the
 * Sep-16 era dumps; the live movie era holds file#18 unpacked at
 * 8006FAF0). This camera snapshots the module window (0x8006F000..0x80090000)
 * at the FIRST module-window dispatch - the boot-era module, the same
 * content the emitted translations were compiled from - and compares the
 * live first 16 bytes of every dispatched fn against the snapshot.
 * MISMATCH = the installed module was swapped and the emitted translation
 * no longer matches the live code. Rate-limited to 64 fns. Stage B (a later
 * cycle) routes mismatches to a bounded interpreter of the live bytes.
 * (c493: PREPENDED AT LINE 1 - the real file's #include lines sit below
 * the call site, so 'after the last include' broke the build; the
 * definition is appended at the end of the file.) */
static unsigned char g_r1392_snap[0x21000];
static unsigned int g_r1392_armed = 0;
static unsigned int g_r1392_rep[64];
static unsigned int g_r1392_nrep = 0;
static void r1392_check(unsigned int fn);
BLOCKEOF
cat > /tmp/r1392_tail.c <<'TAILEOF'

/* R1392 (c492/c493): the definition - appended at the END of the file so
 * every symbol it references (xenolift_mem, r861_out) is already in scope. */
static void r1392_check(unsigned int fn)
{
    unsigned int i;
    unsigned char lw[16], sw[16];
    unsigned int a0, a1, a2, a3, b0, b1, b2, b3;
    if (fn < 0x8006F000u || fn >= 0x80090000u) { return; }
    if (!g_r1392_armed) {
        memcpy(g_r1392_snap, xenolift_mem + (0x8006F000u - 0x80000000u), 0x21000);
        g_r1392_armed = 1;
        r861_out("[idchk] R1392 module-window snapshot armed (the boot-era module, the emitted source)\n");
        return;
    }
    for (i = 0; i < g_r1392_nrep; i++) { if (g_r1392_rep[i] == fn) { return; } }
    memcpy(lw, xenolift_mem + (fn - 0x80000000u), 16);
    memcpy(sw, g_r1392_snap + (fn - 0x8006F000u), 16);
    for (i = 0; i < 16; i++) { if (lw[i] != sw[i]) { break; } }
    if (i < 16) {
        memcpy(&a0, lw, 4); memcpy(&a1, lw + 4, 4);
        memcpy(&a2, lw + 8, 4); memcpy(&a3, lw + 12, 4);
        memcpy(&b0, sw, 4); memcpy(&b1, sw + 4, 4);
        memcpy(&b2, sw + 8, 4); memcpy(&b3, sw + 12, 4);
        r861_out("[idchk] R1392 MISMATCH fn=0x%08X (the module was swapped - the emitted translation does not match the installed code) live=%08X %08X %08X %08X snap=%08X %08X %08X %08X\n",
            fn, a0, a1, a2, a3, b0, b1, b2, b3);
        if (g_r1392_nrep < 64u) { g_r1392_rep[g_r1392_nrep++] = fn; }
    }
}
TAILEOF
cp -p "$SRC" "$SRC.pre_c493"
HLINES=$(wc -l < /tmp/r1392_head.c | tr -d " ")
echo "HEAD lines=$HLINES - prepending at line 1"
{ cat /tmp/r1392_head.c; cat "$SRC"; } > /tmp/rt_p1.c
NEWSET=$((SETLN + HLINES))
awk -v SETLN="$NEWSET" -v CALL="    r1392_check((unsigned int)(${RHS}));" 'NR==SETLN {print; print CALL; next} {print}' /tmp/rt_p1.c > /tmp/rt_p2.c
{ cat /tmp/rt_p2.c; cat /tmp/r1392_tail.c; } > /tmp/rt_new.c
mv /tmp/rt_new.c "$SRC"
echo "===GATES493==="
E_SNAP=$(grep -c "snapshot armed" /tmp/r1392_tail.c | tr -d " ")
E_MIS=$(grep -c "MISMATCH fn=0x" /tmp/r1392_tail.c | tr -d " ")
A_SNAP=$(grep -c "snapshot armed" "$SRC" | tr -d " ")
A_MIS=$(grep -c "MISMATCH fn=0x" "$SRC" | tr -d " ")
E_CALL=$(grep -c "r1392_check" /tmp/r1392_tail.c | tr -d " ")
E_HEAD=$(grep -c "r1392_check" /tmp/r1392_head.c | tr -d " ")
E_CALL=$((E_CALL + E_HEAD + 1))
A_CALL=$(grep -c "r1392_check" "$SRC" | tr -d " ")
echo "snapshot-armed: expect $E_SNAP got $A_SNAP"
echo "mismatch-print: expect $E_MIS got $A_MIS"
echo "r1392_check refs: expect $E_CALL got $A_CALL"
echo "setter preserved: $(sed -n "${NEWSET}p" "$SRC")"
if [ "$A_SNAP" != "$E_SNAP" ] || [ "$A_MIS" != "$E_MIS" ] || [ "$A_CALL" != "$E_CALL" ]; then
  echo "VALID-FAILED: gate mismatch - RESTORING the pre-c493 tree"
  cp -p "$SRC.pre_c493" "$SRC"
  exit 0
fi
echo "GATES OK - the tree carries R1392 (line-1 layout)"
NEW=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_TREE_SHA=$NEW"
echo "===SYNCHK493=== HARD GATE syntax check (the compiler rc captured UNPIPED)"
cc -fsyntax-only "$SRC" > /tmp/c493_syn.txt 2>&1
SYN_RC=$?
head -8 /tmp/c493_syn.txt
echo "SYNCHK_RC=$SYN_RC"
if [ "$SYN_RC" != "0" ]; then
  echo "VALID-FAILED: the patched tree does not parse - RESTORING the pre-c493 tree"
  cp -p "$SRC.pre_c493" "$SRC"
  exit 0
fi
echo "SYNCHK OK"
echo "===RUN493=== build + the 190s verdict run"
export RUN_BUDGET_S=190
bash run.sh 2>&1 | tail -30
echo "RUN_RC=$?"
echo "===DIGEST493==="
LOG="run.log"
if [ ! -s "$LOG" ]; then LOG="run.log.d"; fi
echo "--- the [idchk] receipts (the identity camera):"
grep -c -e "idchk" "$LOG" | tr -d " " | sed "s/^/idchk count: /"
grep -n -e "idchk" "$LOG" | head -24
echo "--- the standard ladder (mod6/chaincam/fvp):"
grep -n -e "MODULE 6 ENTRY" "$LOG" | tail -3
grep -n -e "chaincam" "$LOG" | tail -4
grep -n -e "fvp" "$LOG" | tail -3
echo "--- death receipts:"
grep -n -e "rungasp" "$LOG" | tail -2
echo "--- tree sha at run time:"
shasum -a 256 "$SRC" | cut -d" " -f1
echo "===C493DONE=== the idchk receipts are in - PASS/REVERT from the digest - digest is pure ASCII"
