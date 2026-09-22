#!/bin/bash
# c492_patch.sh - STAGE A OF THE OVERLAY-IDENTITY FIX:
# the R1392 [idchk] VALIDATION CAMERA. CAMERAS ONLY, NO
# BEHAVIOR CHANGE. The c485-c491 receipts PROVED the
# dispatcher ran boot-era translations after the movie
# phase unpacked its own module into the window (word-0
# mismatch at 0x800739A0; the emitted bodies match the
# Sep-16 pSYW6z-era dumps; the live era = file#18 at
# 8006FAF0). R1392: snapshot the module window
# (0x8006F000..0x80090000) at the FIRST window dispatch
# (= the boot-era module = the emitted source), then
# compare every dispatched window fn's first 16 bytes
# against the snapshot; MISMATCH prints [idchk]
# rate-limited to 64 fns. Fail-closed, tee'd to
# /tmp/c492_receipts.txt. Pure-ASCII output.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C492-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c492_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="d86f3deb57aed5b0921ab3a82867dea3a1e1d9960028e360bed8d9bdc90d45f8"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the R1387 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the R1387 tree)"
if grep -q "r1392_check" "$SRC"; then echo "VALID-FAILED: R1392 already present - refusing (idempotent)"; exit 0; fi
SETLN=$(grep -n "xenolift_cur_fn = " "$SRC" | grep -v "==" | head -1 | cut -d: -f1)
if [ -z "$SETLN" ]; then SETLN=$(grep -n "xenolift_cur_fn=" "$SRC" | grep -v "==" | head -1 | cut -d: -f1); fi
if [ -z "$SETLN" ]; then echo "VALID-FAILED: no xenolift_cur_fn setter found - refusing"; exit 0; fi
SETLINE=$(sed -n "${SETLN}p" "$SRC")
echo "SETTER line $SETLN: $SETLINE"
RHS=$(printf "%s" "$SETLINE" | sed "s/^[^=]*= *//; s/;.*//")
echo "RHS=$RHS"
if [ -z "$RHS" ]; then echo "VALID-FAILED: could not extract the setter RHS - refusing"; exit 0; fi
INCLN=$(grep -n "#include" "$SRC" | tail -1 | cut -d: -f1)
if [ -z "$INCLN" ]; then echo "VALID-FAILED: no #include lines - refusing"; exit 0; fi
echo "INSERT after the last #include at line $INCLN"
cat > /tmp/r1392_head.c <<'BLOCKEOF'

/* R1392 (c492): OVERLAY-IDENTITY VALIDATION CAMERA - cameras only, no
 * behavior change. The c485-c491 receipts PROVED the dispatcher executed
 * boot-era translations after the movie phase unpacked its own module into
 * the window (word-0 mismatch at 0x800739A0, three independent receipts:
 * the emitted bodies match the Sep-16 era dumps; the live movie era holds
 * file#18 unpacked at 8006FAF0). This camera snapshots the module window
 * (0x8006F000..0x80090000) at the FIRST module-window dispatch - the
 * boot-era module, the same content the emitted translations were compiled
 * from (stability receipted) - and compares the live first 16 bytes of
 * every dispatched fn against the snapshot. MISMATCH = the installed
 * module was swapped and the emitted translation no longer matches the
 * live code. Rate-limited to 64 fns. Stage B (a later cycle) routes
 * mismatches to a bounded interpreter of the live bytes. */
static unsigned char g_r1392_snap[0x21000];
static unsigned int g_r1392_armed = 0;
static unsigned int g_r1392_rep[64];
static unsigned int g_r1392_nrep = 0;
static void r1392_check(unsigned int fn);
BLOCKEOF
cat > /tmp/r1392_tail.c <<'TAILEOF'

/* R1392 (c492): the definition - placed at the END of the file so every
 * symbol it references (xenolift_mem, r861_out) is already in scope. */
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
cp -p "$SRC" "$SRC.pre_c492"
{ sed -n "1,${INCLN}p" "$SRC"; cat /tmp/r1392_head.c; sed -n "$((INCLN+1)),\$p" "$SRC"; } > /tmp/rt_stage1.c
awk -v SETLN="$SETLN" -v CALL="    r1392_check((unsigned int)(${RHS}));" 'NR==SETLN {print; print CALL; next} {print}' /tmp/rt_stage1.c > /tmp/rt_stage2.c
{ cat /tmp/rt_stage2.c; cat /tmp/r1392_tail.c; } > /tmp/rt_new.c
mv /tmp/rt_new.c "$SRC"
echo "===GATES492==="
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
if [ "$A_SNAP" != "$E_SNAP" ] || [ "$A_MIS" != "$E_MIS" ] || [ "$A_CALL" != "$E_CALL" ]; then
  echo "VALID-FAILED: gate mismatch - RESTORING the pre-c492 tree"
  cp -p "$SRC.pre_c492" "$SRC"
  exit 0
fi
echo "GATES OK - the tree carries R1392"
NEW=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_TREE_SHA=$NEW"
echo "===SYNCHK492=== report-only syntax check (the run.sh BUILD is the real gate)"
cc -fsyntax-only "$SRC" 2>&1 | head -8
echo "SYNCHK_RC=$? (0 = parses clean; nonzero = inspect above)"
echo "===RUN492=== build + the 190s verdict run"
export RUN_BUDGET_S=190
bash run.sh 2>&1 | tail -30
echo "RUN_RC=$?"
echo "===DIGEST492==="
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
echo "===C492DONE=== the idchk receipts are in - PASS/REVERT from the digest - digest is pure ASCII"
