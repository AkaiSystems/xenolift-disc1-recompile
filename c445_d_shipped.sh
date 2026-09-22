#!/bin/bash
# c445_r1380.sh - HYBRID CENSUS + PATCH CYCLE (R1380).
# The c444 receipts: the tail epochs of the R1379 run
# sit in the chronic site-5 cmd=06 LBA=108933 arm/clear
# treadmill with ZERO fetch/act, ZERO READ ISSUED, ZERO
# DATA HANDLER. ARM SOURCE by elimination: only 2
# site-5 stamps exist (20012 ack-watch, 20069
# stranded-delivery, both R1376 family; prints capped
# n<=16 so tail fires are invisible). CHAIN: the
# stranded-delivery (built for stranded GetTN answers)
# fires on the SCHEDULED file#14 ReadN, clears
# cd_scheduled, delivers a bare INT3 - starving the
# R1365 scheduled-read arming that served the early
# epoch's stream (108933-108938, act=1, DMA). FIX R1380:
# one-term exclusion on the stranded-delivery gate -
# '&& !(cd_last_cmd == 0x06u && cd_seek_lba >=
# 100000u)' - a live file-band ReadN is NOT a stranded
# event; the R1365 arming owns the class. STRICT SHAPE
# GATE: the anchor line (strip == '} else if
# (cd_scheduled && cd_pending == 0u) {') must be
# UNIQUE (exactly 1). CENSUS FIRST: the region
# 19990-20085 prints verbatim (both site-5 arms +
# gates) before the apply. Sandbox-verified: true-
# shape synthetic applies + parses; wrong-anchor and
# two-anchor mutations fail closed with 0 writes.
# PASS = the treadmill stops (no new site-5 cmd=06
# clears growth / serve activity resumes in tail
# epochs: fetch act / READ ISSUED / DATA HANDLER
# after 20000) + forward execution. REVERT = treadmill
# persists with the guard in place (then the ack-watch
# site 20012 is the arm - next census).
set -u
cd "$HOME/Downloads/xenolift" || { echo "C445-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="c9e85ea1d9c6ebfd9145cc948dffd37826385f58bd947267ec37b0d39c34b5fb"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1379 tree c9e85ea1 - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1379 tree)"
echo "===CENSUS445=== the R1376 region verbatim (both site-5 arms + gates)"
awk 'NR>=19990 && NR<=20085 { print NR": "$0 }' "$SRC"
echo "===PREGATE445=== pre-existence gates (fail-closed)"
A=$(grep -c -e "} else if (cd_scheduled && cd_pending == 0u) {" "$SRC")
echo "anchor sites: $A (expect 1)"
if [ "$A" != "1" ]; then echo "GATE-FAILED: anchor count != 1"; exit 0; fi
B=$(grep -c -e "R1380 (c444)" "$SRC")
echo "R1380 marker pre-existing: $B (expect 0)"
if [ "$B" != "0" ]; then echo "GATE-FAILED: marker pre-exists"; exit 0; fi
cp -p "$SRC" runtime/runtime.c.pre_r1380
echo "===APPLY445=== strict shape gate + apply"
cat > /tmp/r1380_patch.py <<'PYEOF'
import sys
def apply_guard(path):
    src = open(path).read()
    lines = src.split("\n")
    cand = [i for i, l in enumerate(lines)
            if l.strip() == "} else if (cd_scheduled && cd_pending == 0u) {"]
    print("anchor sites: %d (expect 1)" % len(cand))
    if len(cand) != 1:
        print("FAIL-CLOSED: anchor count != 1")
        return 1
    j = cand[0]
    old = lines[j]
    indent = old[:len(old) - len(old.lstrip())]
    new = (indent + "} else if (cd_scheduled && cd_pending == 0u\n"
           + indent + "           && !(cd_last_cmd == 0x06u && cd_seek_lba >= 100000u)) { /* R1380 (c444): a live file-band ReadN is NOT a stranded event - the conversion clears cd_scheduled and starves the R1365 serve arming (the site-5 treadmill) */")
    lines[j] = new
    open(path, "w").write("\n".join(lines))
    print("APPLIED: R1380 guard inserted at the stranded-delivery gate (line %d)" % (j + 1))
    return 0
sys.exit(apply_guard(sys.argv[1]))
PYEOF
if ! python3 /tmp/r1380_patch.py "$SRC"; then
  echo "APPLY-FAILED: shape gate refused - NOTHING applied, tree unchanged (region printed above)"
  exit 0
fi
echo "===POSTGATE445=== post-apply marker gates (explicit, full patterns)"
C1=$(grep -c -e "R1380 (c444)" "$SRC"); echo "guard marker: $C1 (expect 1)"
C2=$(grep -c -e "} else if (cd_scheduled && cd_pending == 0u) {" "$SRC"); echo "old anchor form: $C2 (expect 0)"
C3=$(grep -c -e "cd_last_cmd == 0x06u && cd_seek_lba >= 100000u" "$SRC"); echo "guard term: $C3 (expect 1)"
if [ "$C1" != "1" ] || [ "$C2" != "0" ] || [ "$C3" != "1" ]; then
  echo "GATE-FAILED: restoring baseline"; cp -p runtime/runtime.c.pre_r1380 "$SRC"; exit 0
fi
NEW=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "PATCHED_TREE_SHA=$NEW"
echo "===BUILD445=== compile the patched runtime"
if ! ./run.sh build > /tmp/c445_build.txt 2>&1; then
  echo "BUILD-FAILED: restoring baseline"; tail -25 /tmp/c445_build.txt; cp -p runtime/runtime.c.pre_r1380 "$SRC"; exit 0
fi
echo "BUILD OK"
tail -3 /tmp/c445_build.txt
echo "===RUN445=== full run (RUN_BUDGET_S=90)"
RUN_BUDGET_S=90 ./run.sh run > /tmp/run_full_c445.txt 2>&1
echo "RUN_RC=$?"
LOG="run.log"
echo "===DIGEST445==="
echo "--- TREADMILL: site-5 cmd=06 LBA=108933 clear counts (has growth stopped?):"
grep -c -e "site=5 cmd=06 LBA=108933" "$LOG"
grep -n -e "site=5 cmd=06 LBA=108933" "$LOG" | tail -3
echo "--- SERVE: fetch act / READ ISSUED / DATA HANDLER in the tail:"
grep -n -e "act=1" "$LOG" | awk -F: '$1 > 20000' | head -4
grep -n -e "READ ISSUED" "$LOG" | awk -F: '$1 > 20000' | head -4
grep -n -e "DATA HANDLER enter" "$LOG" | awk -F: '$1 > 20000' | head -3
echo "--- STREAM: sector serves for the file-14 band:"
grep -n -e "sector LBA 1089" "$LOG" | tail -6
echo "--- R1376 receipts this run (arm activity):"
grep -n -e "R1376" "$LOG" | tail -5
echo "--- DEATH: rungasp + segv:"
grep -n -e "rungasp\|TRUE DEATH\|SIGSEGV\|BadVAddr" "$LOG" | tail -4
echo "--- TREE: shas:"
echo "baseline=c9e85ea1d9c6ebfd9145cc948dffd37826385f58bd947267ec37b0d39c34b5fb"
echo "patched=$NEW"
shasum -a 256 "$SRC" | cut -d" " -f1
echo "===PRESERVE445=== c118 protocol"
D=$(mktemp -d "$PWD/c445_snap.XXXXXX") || { echo "SNAPSHOT-DIR-FAILED"; exit 0; }
cp -p run.log "$D/run.log" && CP1=0 || CP1=1
cp -p /tmp/run_full_c445.txt "$D/run_full_c445.txt" && CP2=0 || CP2=1
echo "cp_rcs: $CP1 $CP2"
ls -la "$D"
shasum -a 256 "$D/run.log" "$D/run_full_c445.txt"
tail -8 "$D/run_full_c445.txt"
echo "===C445DONE=== R1380 shipped - PASS/REVERT from the digest receipts - REVERT = treadmill persists (then the ack-watch site is the arm)"
