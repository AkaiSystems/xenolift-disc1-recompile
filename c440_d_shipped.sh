#!/bin/bash
# c440_r1379c.sh - HYBRID CENSUS + PATCH CYCLE (R1379
# reship). The c437 cycle fail-closed exactly as
# designed and printed the TRUE discard regions: the
# condition is TWO lines - '} else if (cd_pending !=
# 0u && cd_arm_int1_pending == 0u' / '&& cd_data_pos
# < cd_data_n) {' - with NO active-read guard and NO
# FE1C gate (the R161 comment claims FE1C==0 but the
# code never checks it). The LBA-9 kill was
# structurally inevitable. R1379: insert the guard
# term '&& FDF8==0 (bytes owed = LIVE request, never
# stale)' after the '&& cd_data_pos < cd_data_n'
# continuation line at BOTH sites. STRICT SHAPE GATE
# (updated for the true anchor): the candidate line
# must STRIP-start with '&& cd_data_pos < cd_data_n'
# AND end with ') {', exactly one per print site, the
# previous print is a hard barrier. Sandbox-verified:
# true-shape synthetic (verbatim from the receipts)
# applies at 2 sites + parses; the zrfB co-resident
# trap line ('if (cd_data_n > 0u && cd_data_pos <
# cd_data_n) {') is NOT matched; missing-leading-&&
# and missing-'){ ' mutations fail closed with 0
# writes. PASS = no discard at the live posture + the
# walk advances past LBA 9 + the mount-cell
# stabilizes.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C440-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="6c916b3fc08cc29c92247a12aaea6cd4f294e9c395164490e737ab690b782737"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1378 baseline - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1378 tree)"
echo "===PREGATE440=== pre-existence gates (fail-closed)"
A=$(grep -c -e "spin-discard: dead INT w/ stale FIFO" "$SRC")
echo "discard sites: $A (expect 2)"
if [ "$A" != "2" ]; then echo "GATE-FAILED: site count != 2"; exit 0; fi
B=$(grep -c -e "bytes owed = LIVE request" "$SRC")
echo "R1379 marker pre-existing: $B (expect 0)"
if [ "$B" != "0" ]; then echo "GATE-FAILED: marker pre-exists"; exit 0; fi
C=$(grep -c -e "R1379" "$SRC")
echo "R1379 token pre-existing: $C (expect 0)"
if [ "$C" != "0" ]; then echo "GATE-FAILED: R1379 pre-exists"; exit 0; fi
cp -p "$SRC" runtime/runtime.c.pre_r1379
echo "===CENSUS440=== the two discard conditions (printed by the patch logic)"
echo "===APPLY440=== strict shape gate (true anchor) + conditional apply"
cat > /tmp/r1379_patch.py <<'PYEOF'
import sys
def apply_guard(path):
    src = open(path).read()
    lines = src.split("\n")
    disc = [i for i, l in enumerate(lines) if "spin-discard: dead INT w/ stale FIFO" in l]
    print("spin-discard print sites: %d (expect 2)" % len(disc))
    if len(disc) != 2:
        print("FAIL-CLOSED: print-site count != 2")
        return 1
    for d in disc:
        print("--- condition before print at line %d:" % (d + 1))
        for k in range(max(0, d - 12), d + 2):
            print("%d: %s" % (k + 1, lines[k]))
    changed = 0
    edits = []
    for di in range(len(disc)):
        d = disc[di]
        barrier = disc[di - 1] if di > 0 else -1
        cands = []
        for j in range(d - 1, max(d - 40, barrier), -1):
            l = lines[j]
            if l.strip().startswith("&& cd_data_pos < cd_data_n") and l.rstrip().endswith(") {"):
                cands.append(j)
        if len(cands) != 1:
            print("FAIL-CLOSED: site at print-line %d has %d condition candidates (need exactly 1)" % (d + 1, len(cands)))
            return 1
        j = cands[0]
        old = lines[j]
        indent = old[:len(old) - len(old.lstrip())]
        stripped = old.rstrip()
        new1 = stripped[:-3]
        new2 = indent + "    && xenolift_mem_read32(0x8004FDF8u) == 0u) { /* R1379: bytes owed = LIVE request, never stale */"
        edits.append((j, new1 + "\n" + new2))
        changed += 1
    for j, new in edits:
        lines[j] = new
    open(path, "w").write("\n".join(lines))
    print("APPLIED: R1379 guard inserted at %d site(s)" % changed)
    return 0
sys.exit(apply_guard(sys.argv[1]))
PYEOF
if ! python3 /tmp/r1379_patch.py "$SRC"; then
  echo "APPLY-FAILED: shape gate refused - NOTHING applied, tree unchanged (conditions printed above)"
  exit 0
fi
echo "===POSTGATE440=== post-apply marker gates (explicit, full patterns - colon-containing patterns must never go through a colon-split gate loop)"
C1=$(grep -c -e "bytes owed = LIVE request" "$SRC")
echo "gate bytes-owed marker: count=$C1 expect=2"
C2=$(grep -c -e "spin-discard: dead INT w/ stale FIFO" "$SRC")
echo "gate discard prints: count=$C2 expect=2"
C3=$(grep -c -e "R1379" "$SRC")
echo "gate R1379 token: count=$C3 expect=2"
if [ "$C1" != "2" ] || [ "$C2" != "2" ] || [ "$C3" != "2" ]; then
  echo "GATE-FAILED: restoring baseline"; cp -p runtime/runtime.c.pre_r1379 "$SRC"; exit 0
fi
NEW=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "PATCHED_TREE_SHA=$NEW"
echo "===BUILD440=== compile the patched runtime"
if ! ./run.sh build > /tmp/c440_build.txt 2>&1; then
  echo "BUILD-FAILED: restoring baseline"; tail -25 /tmp/c440_build.txt; cp -p runtime/runtime.c.pre_r1379 "$SRC"; exit 0
fi
echo "BUILD OK"
tail -3 /tmp/c440_build.txt
echo "===RUN440=== full run (RUN_BUDGET_S=90)"
RUN_BUDGET_S=90 ./run.sh run > /tmp/run_full_c440.txt 2>&1
echo "RUN_RC=$?"
LOG="run.log"
echo "===DIGEST440==="
echo "--- GUARD: discard receipts this run (postures + count):"
grep -c -e "spin-discard" "$LOG"
grep -n -e "spin-discard" "$LOG" | head -6
echo "--- WALK: did the walk advance past LBA 9?"
grep -n -e "FE04 00000009->0000000A" "$LOG" | head -4
grep -n -e "pendclr" "$LOG" | grep -e "LBA=9" | tail -4
grep -n -e "pendclr" "$LOG" | grep -e "LBA=10" | tail -3
echo "--- MOUNT: mount-cell + fvp menu:"
grep -n -e "mcw" "$LOG" | tail -3
grep -n -e "fvp" "$LOG" | tail -4
echo "--- MOVIE/STATE: cmdtl tail + mvdoor:"
grep -n -e "cmdtl" "$LOG" | tail -5
grep -n -e "mvdoor" "$LOG" | tail -3
echo "--- DEATH: rungasp + TRUE DEATH:"
grep -n -e "rungasp\|TRUE DEATH" "$LOG" | tail -4
echo "--- TREE: shas:"
echo "baseline=6c916b3fc08cc29c92247a12aaea6cd4f294e9c395164490e737ab690b782737"
echo "patched=$NEW"
shasum -a 256 "$SRC" | cut -d" " -f1
echo "===PRESERVE440=== c118 protocol"
D=$(mktemp -d "$PWD/c440_snap.XXXXXX") || { echo "SNAPSHOT-DIR-FAILED"; exit 0; }
cp -p run.log "$D/run.log" && CP1=0 || CP1=1
cp -p /tmp/run_full_c440.txt "$D/run_full_c440.txt" && CP2=0 || CP2=1
echo "cp_rcs: $CP1 $CP2"
ls -la "$D"
shasum -a 256 "$D/run.log" "$D/run_full_c440.txt"
tail -8 "$D/run_full_c440.txt"
echo "===C440DONE=== R1379b shipped - PASS = no discard at live posture + walk past LBA 9 + mount stabilizes; REVERT = discard suppressed but walk still stalls (next: re-serve the LBA-9 sector)"
