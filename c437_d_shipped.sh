#!/bin/bash
# c437_r1379.sh - HYBRID CENSUS + PATCH CYCLE. The c436
# receipts: TWO spin-discard sites (lines ~7619/7941),
# the R256 comment names the exact hazard class ("a
# pending INT1 during an active read is never dead"),
# and the LBA-9 window receipts our own discard
# killing a LIVE request (FDF8=2048 bytes owed, sector
# loaded seconds before). R1379: one-term guard on the
# discard condition - && FDF8==0 (bytes owed = LIVE
# request, never stale) - the proven zrfB discriminator
# inverted. STRICT SHAPE GATE: the python first prints
# both discard regions (census), then applies ONLY if
# each print site has exactly one nearby condition line
# (cd_data_pos < cd_data_n + !cd_read_active, ending
# ') {'); any ambiguity FAILS CLOSED with the region
# printed. The previous print site is a hard barrier.
# Sandbox-verified: faithful shape applies+parses,
# genuine mutation fails closed with 0 writes, one-line
# condition form also applies+parses. PASS = no discard
# at the live posture + the walk advances past LBA 9 +
# the mount-cell stabilizes. REVERT criteria printed.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C437-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="6c916b3fc08cc29c92247a12aaea6cd4f294e9c395164490e737ab690b782737"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1378 tree - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1378 tree)"
echo "===PREGATE437=== pre-existence gates (fail-closed)"
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
echo "===CENSUS437=== the two discard regions verbatim (printed by the patch logic)"
echo "===APPLY437=== strict shape gate + conditional apply"
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
        print("--- region before print at line %d:" % (d + 1))
        for k in range(max(0, d - 22), d + 3):
            print("%d: %s" % (k + 1, lines[k]))
    changed = 0
    edits = []
    for di in range(len(disc)):
        d = disc[di]
        barrier = disc[di - 1] if di > 0 else -1
        cands = []
        for j in range(d - 1, max(d - 40, barrier), -1):
            l = lines[j]
            if "cd_data_pos < cd_data_n" in l and "!cd_read_active" in l and l.rstrip().endswith("{"):
                cands.append(j)
        if len(cands) != 1:
            print("FAIL-CLOSED: site at print-line %d has %d condition candidates (need exactly 1)" % (d + 1, len(cands)))
            return 1
        j = cands[0]
        old = lines[j]
        indent = old[:len(old) - len(old.lstrip())]
        stripped = old.rstrip()
        if not stripped.endswith(") {"):
            print("FAIL-CLOSED: condition line does not end with ') {'")
            return 1
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
  echo "APPLY-FAILED: shape gate refused - NOTHING applied, tree unchanged (regions printed above for the exact reship)"
  exit 0
fi
echo "===POSTGATE437=== post-apply marker gates"
for G in "bytes owed = LIVE request:2" "spin-discard: dead INT w/ stale FIFO:2" "R1379:2"; do
  P="${G%%:*}"; E="${G##*:}"
  C=$(grep -c -e "$P" "$SRC")
  echo "gate $P: count=$C expect=$E"
  if [ "$C" != "$E" ]; then echo "GATE-FAILED: restoring baseline"; cp -p runtime/runtime.c.pre_r1379 "$SRC"; exit 0; fi
done
NEW=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "PATCHED_TREE_SHA=$NEW"
echo "===BUILD437=== compile the patched runtime"
if ! ./run.sh build > /tmp/c437_build.txt 2>&1; then
  echo "BUILD-FAILED: restoring baseline"; tail -25 /tmp/c437_build.txt; cp -p runtime/runtime.c.pre_r1379 "$SRC"; exit 0
fi
echo "BUILD OK"
tail -3 /tmp/c437_build.txt
echo "===RUN437=== full run (RUN_BUDGET_S=90)"
RUN_BUDGET_S=90 ./run.sh run > /tmp/run_full_c437.txt 2>&1
echo "RUN_RC=$?"
LOG="run.log"
echo "===DIGEST437==="
echo "--- GUARD: discard receipts this run + their postures:"
grep -n -e "spin-discard" "$LOG" | head -8
grep -c -e "spin-discard" "$LOG"
echo "--- WALK: did the walk advance past LBA 9?"
grep -n -e "FE04 00000009->0000000A" "$LOG" | head -4
grep -n -e "pendclr" "$LOG" | grep -e "LBA=9" | tail -4
grep -n -e "pendclr" "$LOG" | grep -e "LBA=10" | tail -3
echo "--- MOUNT: mount-cell stability + mtrans:"
grep -n -e "mtrans" "$LOG" | tail -4
grep -n -e "mcw" "$LOG" | tail -4
echo "--- MOVIE: cmdtl tail + mvdoor:"
grep -n -e "cmdtl" "$LOG" | tail -5
grep -n -e "mvdoor" "$LOG" | tail -3
echo "--- DEATH: rungasp + segv:"
grep -n -e "rungasp\|TRUE DEATH" "$LOG" | tail -4
echo "--- TREE: shas:"
echo "baseline=6c916b3fc08cc29c92247a12aaea6cd4f294e9c395164490e737ab690b782737"
echo "patched=$NEW"
shasum -a 256 "$SRC" | cut -d" " -f1
echo "===PRESERVE437=== c118 protocol"
D=$(mktemp -d "$PWD/c437_snap.XXXXXX") || { echo "SNAPSHOT-DIR-FAILED"; exit 0; }
cp -p run.log "$D/run.log" && CP1=0 || CP1=1
cp -p /tmp/run_full_c437.txt "$D/run_full_c437.txt" && CP2=0 || CP2=1
echo "cp_rcs: $CP1 $CP2"
ls -la "$D"
shasum -a 256 "$D/run.log" "$D/run_full_c437.txt"
tail -8 "$D/run_full_c437.txt"
echo "===C437DONE=== R1379 shipped - PASS = no discard at live posture + walk past LBA 9 + mount stabilizes; REVERT = discard suppressed but walk still stalls (reship with re-serve)"
