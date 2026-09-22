#!/bin/bash
# c451_r1381.sh - PATCH CYCLE (R1381, the file-15 arm).
# Tree 2c660613 verified first. The c450 anchors: every
# completion door gates on FDF8>0 (R489 promote needs
# fdf8>=8, defib6 needs 0<FDF8<200000, R539 park
# handler runs post-R473); the R1298 block (c195, line
# 15173) IS the built-in never-started-armed-read
# starter ('FDF8=92180 ARMED at FE04=108995... stamp
# seek, engage, serve first sector same-poll, pend=1,
# force INT1') waiting for a game arm that never
# comes; the c448 receipts: the field module
# positions the ring (FE04=108995, FE08 in-band,
# FDF8=0) and never issues through the file layer.
# R496 precedent: arm from the native file table. FIX
# R1381 = ARM ONLY: one-shot/re-arming block before
# R1298 - gate: FE04==108995, FE08 in the ring band,
# FDF8==0, seek==108995, cmd==06, act/pend/sched idle,
# frozen 10s; action: FDF8=92180 + receipt; R1298 owns
# the start. STRICT SHAPE GATE: the anchor (strip ==
# '{ /* R1298 (c195, THE NEVER-STARTED ARMED READ):
# the c194 receipts') must be UNIQUE. Sandbox:
# true-shape applies + parses (gcc); wrong-anchor and
# duplicate-anchor mutants fail closed, 0 writes.
# PASS = [f15arm] fire + R1298 start + FDF8 drains +
# FE08 walks + dstw0!=0 + forward execution. REVERT =
# fire with no consumption (FDF8 stuck at 92180, no
# serves at 108995+).
set -u
cd "$HOME/Downloads/xenolift" || { echo "C451-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="2c660613e608e9f878833ece08dcb579a4f431b11c7c4e411323db2c5633f6f2"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1380 tree - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1380 tree)"
echo "===PREGATE451=== pre-existence gates (fail-closed)"
A=$(grep -c -e "{ /\* R1298 (c195, THE NEVER-STARTED ARMED READ): the c194 receipts" "$SRC")
echo "anchor sites: $A (expect 1)"
if [ "$A" != "1" ]; then echo "GATE-FAILED: anchor count != 1"; exit 0; fi
B=$(grep -c -e "f15arm" "$SRC")
echo "f15arm pre-existing: $B (expect 0)"
if [ "$B" != "0" ]; then echo "GATE-FAILED: marker pre-exists"; exit 0; fi
cp -p "$SRC" runtime/runtime.c.pre_r1381
echo "===APPLY451=== strict shape gate + apply"
cat > /tmp/r1381_patch.py <<'PYEOF'
import sys
ANCHOR_STRIP = "{ /* R1298 (c195, THE NEVER-STARTED ARMED READ): the c194 receipts"
NEW_BLOCK = """            { /* R1381 (c450/c448 receipts): the file-15 read-ahead ARM. The field module
             * positions the ring (FE04=108995, FE08 in the ring band, FDF8=0) and never
             * issues through the file layer (no size-lookup, no READ ISSUED); the boot
             * files streamed ONLY with FDF8 armed. R496 precedent: arm from the native
             * file table (92180 = file#15 size, ftab-receipted c448). Drive-state only,
             * no FE1C/sched writes; the R1298 never-started composite (below) owns the
             * start. Re-arms when the request moves on. */
                static int r1381_fired; static time_t r1381_since;
                uint32_t r1381_fe04 = xenolift_mem_read32(0x8004FE04u);
                uint32_t r1381_fe08 = xenolift_mem_read32(0x8004FE08u);
                uint32_t r1381_fdf8 = xenolift_mem_read32(0x8004FDF8u);
                if (r1381_fired && r1381_fe04 != 108995u) {
                    r1381_fired = 0; r1381_since = 0; /* the request moved on - re-arm for the next epoch */
                }
                if (!r1381_fired
                    && r1381_fe04 == 108995u
                    && r1381_fe08 >= 0x8006FAF8u && r1381_fe08 < 0x80080000u
                    && r1381_fdf8 == 0u
                    && cd_seek_lba == 108995u
                    && cd_last_cmd == 0x06u
                    && !cd_read_active && !cd_pending && !cd_scheduled) {
                    if (r1381_since == 0) {
                        r1381_since = xl_wall();
                    } else if (xl_wall() - r1381_since >= 10) {
                        r1381_fired = 1;
                        xenolift_mem_write32(0x8004FDF8u, 92180u);
                        r861_out("[f15arm] R1381: file-15 park frozen 10s (FE04=108995 FE08=%08X FDF8 0->92180, cmd=06 act=0 pend=0 sched=0) - ARMED from the file table (R496 precedent); R1298 owns the start\\n", r1381_fe08);
                    }
                } else if (r1381_since != 0 && r1381_fe04 != 108995u) {
                    r1381_since = 0; /* posture moved before the fire - re-observe */
                }
            }
"""
def apply_patch(path):
    lines = open(path).read().split("\n")
    cand = [i for i, l in enumerate(lines) if l.strip() == ANCHOR_STRIP]
    print("anchor sites: %d (expect 1)" % len(cand))
    if len(cand) != 1:
        print("FAIL-CLOSED: anchor count != 1")
        return 1
    j = cand[0]
    lines.insert(j, NEW_BLOCK.rstrip("\n"))
    open(path, "w").write("\n".join(lines))
    print("APPLIED: R1381 arm block inserted before R1298 (line %d)" % j)
    return 0
sys.exit(apply_patch(sys.argv[1]))
PYEOF
if ! python3 /tmp/r1381_patch.py "$SRC"; then
  echo "APPLY-FAILED: shape gate refused - NOTHING applied, tree unchanged"
  exit 0
fi
echo "===POSTGATE451=== post-apply marker gates (explicit, full patterns)"
C1=$(grep -c -e "f15arm" "$SRC"); echo "f15arm markers: $C1 (expect 1)"
C2=$(grep -c -e "{ /\* R1298 (c195, THE NEVER-STARTED ARMED READ): the c194 receipts" "$SRC"); echo "anchor intact: $C2 (expect 1)"
C3=$(grep -c -e "R1381 (c450/c448 receipts)" "$SRC"); echo "R1381 comment: $C3 (expect 1)"
if [ "$C1" != "1" ] || [ "$C2" != "1" ] || [ "$C3" != "1" ]; then
  echo "GATE-FAILED: restoring baseline"; cp -p runtime/runtime.c.pre_r1381 "$SRC"; exit 0
fi
NEW=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "PATCHED_TREE_SHA=$NEW"
echo "===BUILD451=== compile the patched runtime"
if ! ./run.sh build > /tmp/c451_build.txt 2>&1; then
  echo "BUILD-FAILED: restoring baseline"; tail -25 /tmp/c451_build.txt; cp -p runtime/runtime.c.pre_r1381 "$SRC"; exit 0
fi
echo "BUILD OK"
tail -3 /tmp/c451_build.txt
echo "===RUN451=== full run (RUN_BUDGET_S=90)"
RUN_BUDGET_S=90 ./run.sh run > /tmp/run_full_c451.txt 2>&1
echo "RUN_RC=$?"
LOG="run.log"
echo "===DIGEST451==="
echo "--- THE ARM: [f15arm] receipts:"
grep -n -e "f15arm" "$LOG"
echo "--- THE START: R1298 receipts:"
grep -n -e "R1298" "$LOG" | head -6
echo "--- THE STREAM: sectors at the file-15 band + FDF8 countdown + ring walk:"
grep -n -e "sector LBA 10899" "$LOG" | tail -6
grep -n -e "req] FDF8" "$LOG" | tail -6
grep -n -e "FE08 8007F2F8->\|FE08 8007F" "$LOG" | tail -6
echo "--- DELIVERY: DATA HANDLER dstw0 status:"
grep -e "DATA HANDLER enter" "$LOG" | tail -4
echo "--- FORWARD: fvp/mdec/MODULE 6/menu + READ ISSUED:"
grep -n -e "MODULE 6 ENTRY" "$LOG" | tail -2
grep -n -e "fvp" "$LOG" | tail -4
grep -n -e "READ ISSUED" "$LOG" | tail -4
echo "--- DEATH receipts:"
grep -c -e "SIGSEGV\|BadVAddr\|TRUE DEATH" "$LOG"
grep -n -e "rungasp" "$LOG" | tail -2
echo "--- TREE shas:"
echo "baseline=2c660613e608e9f878833ece08dcb579a4f431b11c7c4e411323db2c5633f6f2"
echo "patched=$NEW"
shasum -a 256 "$SRC" | cut -d" " -f1
echo "===PRESERVE451=== c118 protocol"
D=$(mktemp -d "$PWD/c451_snap.XXXXXX") || { echo "SNAPSHOT-DIR-FAILED"; exit 0; }
cp -p run.log "$D/run.log" && CP1=0 || CP1=1
cp -p /tmp/run_full_c451.txt "$D/run_full_c451.txt" && CP2=0 || CP2=1
echo "cp_rcs: $CP1 $CP2"
ls -la "$D"
shasum -a 256 "$D/run.log" "$D/run_full_c451.txt"
tail -8 "$D/run_full_c451.txt"
echo "===C451DONE=== R1381 shipped - PASS/REVERT from the digest receipts - REVERT = fire with no consumption"
