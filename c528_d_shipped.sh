#!/bin/bash
# c528_patch.sh - THE FIX THE RECEIPTS SELECTED: R1395,
# THE REBOOT-FAITHFUL HEAP-BAND CLEAR AT THE FAULT-WALK
# RESTART. THE c525-c527 RECEIPTS: the epoch-4 member-6
# alloc (2660 bytes) entered DEGENERATE (frontier=0x4 vs
# the healthy 0x801FC000/0x8007EBF0 receipted in the
# successful passes), the walk terminated at the
# dash-end without a block, returned v0=1, and the loader
# consumed 1 as the read destination ([ovlread] a1=0x1 ->
# sdoor decline -> LZSS runaway dest=1 -> the CD state
# trashed -> restart #2 -> the interpreter honest stop).
# THE ROOT, receipted epoch by epoch: the game's own
# release NEVER RUNS at the restarts (the RELALL census
# is EMPTY) and the R772 restore covers ONLY the exe band
# (0x80010000..0x8006F000) - so module, archive, and
# staging allocations above it ACCUMULATE across epochs
# until the allocator degenerates. THE HEAP-CELL GARBAGE
# (77450=F4FC0232) IS NOT THE DISCRIMINATOR (identical in
# the successful and failing s5cam receipts). THE FIX: a
# REAL reboot clears all RAM - the fwrestart door must
# ALSO zero guest 0x8006F000..0x80200000 alongside the
# exe-image restore. The boot's own region initializer,
# the carve door, the stage-2 remap, and the per-epoch
# re-staging (fldx2 receipted firing EVERY epoch) own
# their own recovery. The stack region is SAFE: the
# restart conversion is a longjmp that abandons those
# frames, and boot re-enters at sp=0x80200000 (receipted).
# Gates: tree sha d1c3d391, anchor unique (the R772
# print), [heapclr] absent pre-patch (idempotent),
# post-counts from the artifact, HARD unpiped syntax gate
# with restore-on-fail, then build + the 190s verdict run
# + digest. PASS = [heapclr] at each restart + the
# member-6 dest REAL in every epoch (no v0=1, no dash
# terminator at the member-6 alloc, no r31=0xA runaway) +
# deeper/forward execution. Fail-closed, tee'd to
# /tmp/c528_receipts.txt. Pure-ASCII output.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C528-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c528_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="d1c3d3912462c72ac7a811d8ce177c18b56166a6aa4825049cc3b686330b6384"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the c524 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the c524 tree with the landed R1381 park-release request)"
if grep -q -F -e "[heapclr]" "$SRC"; then echo "VALID-FAILED: [heapclr] already present - refusing (idempotent)"; exit 0; fi
ANC=$(grep -c -F -e "pristine exe image restored @fault-walk restart" "$SRC" | tr -d " ")
echo "anchor count: $ANC (expect 1)"
if [ "$ANC" != "1" ]; then echo "VALID-FAILED: anchor not unique - refusing"; exit 0; fi
cp -p "$SRC" "$SRC.pre_c528"
L=$(grep -n -F -e "pristine exe image restored @fault-walk restart" "$SRC" | head -1 | cut -d: -f1)
echo "===SPLICE528=== inserting the R1395 block after the R772 restore receipt (line $L)"
cat > /tmp/r1395_block.c <<'CEOF'
    { /* R1395 (c528): REBOOT-FAITHFUL HEAP-BAND CLEAR AT THE FAULT-WALK RESTART.
       * The c525-c527 receipts: the epoch-4 member-6 alloc entered DEGENERATE
       * (frontier=0x4 vs the healthy 0x801FC000/0x8007EBF0), the walk terminated
       * at the dash-end without a block, returned v0=1, and the loader consumed
       * 1 as the read destination -> the sdoor decline -> the LZSS runaway
       * (dest=1, code-as-source) -> the CD state trashed -> restart -> the
       * interpreter honest stop. THE ROOT: the game's own release NEVER RUNS at
       * the restarts (the RELALL census is empty) and the R772 restore covers
       * ONLY the exe band (0x80010000..0x8006F000) - module, archive, and
       * staging allocations above it ACCUMULATE across epochs until the
       * allocator degenerates. THE HEAP-CELL GARBAGE (77450=F4FC0232) IS NOT
       * THE DISCRIMINATOR (identical in the successful and failing s5cam
       * receipts). A REAL reboot clears all RAM: zero guest
       * 0x8006F000..0x80200000 alongside the exe-image restore. The boot region
       * initializer, the carve door, the stage-2 remap, and the per-epoch
       * re-staging (fldx2 receipted firing EVERY epoch) own their own
       * recovery. The stack region is SAFE: the restart conversion is a
       * longjmp that abandons those frames; boot re-enters at sp=0x80200000. */
        memset(xenolift_mem + (0x8006F000u & 0x1FFFFFFFu), 0,
               (0x80200000u & 0x1FFFFFFFu) - (0x8006F000u & 0x1FFFFFFFu));
        { static int r1395_n;
          if (r1395_n++ < 8)
            r861_out("[heapclr] R1395 restart heap band zeroed 0x8006F000..0x80200000 (reboot-faithful; epoch-accumulated module/archive/staging allocations cleared; the boot region initializer + carve + stage-2 remap + re-staging doors own their own recovery)\n");
        }
    }

CEOF
BLK=$(wc -l < /tmp/r1395_block.c | tr -d " ")
head -n "$L" "$SRC" > /tmp/runtime_new.c
cat /tmp/r1395_block.c >> /tmp/runtime_new.c
tail -n +"$((L+1))" "$SRC" >> /tmp/runtime_new.c
cp /tmp/runtime_new.c "$SRC"
echo "INSERTED after line $L (block $BLK lines)"
echo "--- the splice context:"
sed -n "$((L-2)),$((L+6))p" "$SRC"
echo "===GATES528==="
A_CLR=$(grep -c -F -e "[heapclr]" "$SRC" | tr -d " ")
A_R1395=$(grep -c -F -e "R1395 (c528)" "$SRC" | tr -d " ")
A_ANC=$(grep -c -F -e "pristine exe image restored @fault-walk restart" "$SRC" | tr -d " ")
echo "[heapclr] refs: got $A_CLR (expect 1)"
echo "R1395 (c528) refs: got $A_R1395 (expect 1)"
echo "anchor refs: got $A_ANC (expect 1, unchanged)"
if [ "$A_CLR" != "1" ] || [ "$A_R1395" != "1" ] || [ "$A_ANC" != "1" ]; then
  echo "VALID-FAILED: gate mismatch - RESTORING the pre-c528 tree"
  cp -p "$SRC.pre_c528" "$SRC"
  exit 0
fi
echo "GATES OK"
echo "===SYNCHK528=== HARD GATE syntax check (unpiped rc)"
cc -w -fsyntax-only -std=gnu99 "$SRC" 2> /tmp/c528_syn_err.txt
RC=$?
head -8 /tmp/c528_syn_err.txt
echo "SYNCHK_RC=$RC"
if [ "$RC" != "0" ]; then
  echo "VALID-FAILED: patched file does not parse - RESTORING the pre-c528 tree"
  cp -p "$SRC.pre_c528" "$SRC"
  exit 0
fi
echo "SYNCHK OK"
NEW=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_TREE_SHA=$NEW"
echo "===RUN528=== build + the 190s verdict run"
export RUN_BUDGET_S=190
bash run.sh 2>&1 | tail -24
echo "RUN_RC=$?"
echo "===DIGEST528==="
LOG="run.log"
if [ ! -s "$LOG" ]; then LOG="run.log.d"; fi
echo "--- the [heapclr] receipts (the fix's own evidence: the clear at each restart):"
grep -n -e "\[heapclr\]" "$LOG" | head -8
echo "--- the epoch pairing (restarts + clears):"
grep -n -e "fwrestart" -e "heapclr" "$LOG" | head -12
echo "--- the member-6 dest across ALL epochs (must be REAL, never 00000001):"
grep -n -e "\[newmod\]" "$LOG" | grep -e "member=6" | head -8
echo "--- the alloc-return v0 values (must never be 00000001):"
grep -n -e "s5cam" "$LOG" | head -8
echo "--- the dash-terminator family (the failing-pass shape - absent at member-6 allocs?):"
grep -n -e "dashfix" -e "walkterm" "$LOG" | head -8
echo "--- the member-6 read chain (LBA 108884 to a VALID dst):"
grep -n -e "108884" "$LOG" | grep -e "sdoor" -e "cd-dma" -e "ftab" | tail -10
echo "--- THE RUNAWAY CHECK (r31=0000000A must be ABSENT):"
grep -c -e "r31=0000000A" "$LOG" | tr -d " " | sed "s/^/r31=0A receipts: /"
grep -n -e "unpackw" "$LOG" | tail -4
echo "--- the death + the tail era:"
grep -n -e "rungasp" "$LOG" | tail -2
tail -16 "$LOG"
echo "--- the ladder + screen witnesses:"
grep -n -e "MODULE 6 ENTRY" "$LOG" | head -3
grep -n -e "vram_nonzero" "$LOG" | tail -3
echo "--- log length + tree sha at run time:"
wc -l < "$LOG" | tr -d " " | sed "s/^/log lines: /"
shasum -a 256 "$SRC" | cut -d" " -f1
echo "===C528DONE=== PASS = [heapclr] at each restart + the member-6 dest REAL in every epoch + no v0=1, no r31=0A runaway + deeper/forward execution - digest is pure ASCII"
