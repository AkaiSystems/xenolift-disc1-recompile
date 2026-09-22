#!/bin/bash
# c275_sized_serve.sh - THE R1332 SIZED-SERVE FIX (one term).
# THE c274 SRC-DUMP CONVICTION: the mvdoor fire body computes the
# batch from the kernel OWN ledger - r891_nsec = (FDF8+2047)/2048 -
# then CLAMPS: if (r891_nsec == 0u || r891_nsec > 24u) r891_nsec =
# 1u. At the f15 wedge FDF8=0x16814 = 92180 bytes -> nsec=46, and
# the >24 sanity guard (calibrated for the file#5/#6 era, 2-7
# sectors) clamped it to 1 SECTOR - then the doorbell zeroed
# FDF8/FE04 and set transfer-DONE: a 46-sector request announced
# complete with 1 sector (the c273 dossier: the game ran its
# post-read chain, found the data short, and tore down - GetStat ->
# PAUSE -> fault-walk restart to state 0). Everything else in the
# composite is the proven sdoor R896 pattern (sync disc_read_lba
# into FE08 dst BEFORE the poll returns; dst 800D0994 passed the
# validity gate; success posture zero FDF8/FE1C/FE04 + FE48(5F)=1 +
# FE1C(5F)=0 - correct ONCE the full batch is on board).
# THE FIX: raise the clamp 24u -> 64u. 64 covers every in-band
# file (max f14 62 sectors) while still guarding absurd counts.
# PASS = the fire receipt prints 46 sectors delivered + the game
# consumes and proceeds past the post-read chain (new commands
# beyond the GetStat/PAUSE teardown ladder, state 1 holds or
# advances). REVERT if the game still tears down despite full data
# (would point at dst mismatch - next dossier would receipt it).
set -u
cd "$HOME/Downloads/xenolift" || { echo "C275-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="30c6d76d8538f951014282f30ed8c2454c2a191aa4eb429a6bb2eee5b4bb5530"
if [ ! -s "$SRC" ]; then echo "C275-FAILED: runtime/runtime.c missing"; exit 1; fi
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA_BEFORE=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1331 tree 30c6d76d - refusing a foreign tree"; exit 0; fi
echo "BASELINE_VERIFIED (the R1331 doorbell-fire tree)"
P="patch_c275_$(date +%Y%m%d_%H%M%S)"
if ! (mkdir -p "$P" && cp -p "$SRC" "$P/runtime.c.pre"); then echo "C275-FAILED: preserve failed"; exit 1; fi
echo "PRESERVED: $P/runtime.c.pre sha=$SS"

echo "===PATCH275=== the R1332 sized-serve clamp raise (one term, FAIL EXPLICIT)"
python3 - <<'PYEOF' || { echo "PATCH-FAILED - nothing written, no run"; exit 1; }
import hashlib, sys
data = open("runtime/runtime.c","rb").read()
if b"R1332" in data:
    print("IDEMPOTENT-SKIP: R1332 already present - no edit made"); sys.exit(0)
if data.count(b"R1332") != 0:
    print("MARKER-COLLISION: R1332 already used in tree - refusing"); sys.exit(1)

old = b"if (r891_nsec == 0u || r891_nsec > 24u) r891_nsec = 1u;"
n = data.count(old)
print("R1332 anchor count=%d (must be exactly 1)" % n)
if n != 1:
    idx = 0
    while True:
        idx = data.find(b"r891_nsec", idx)
        if idx == -1: break
        print("r891_nsec occurrence at offset %d: ...%s..." % (idx, data[max(0,idx-60):idx+70].decode("ascii","replace").replace("\n"," | ")))
        idx += 1
    sys.exit(1)
pos = data.find(old)
print("ANCHOR-CONTEXT (200 bytes before/after):")
print(data[max(0,pos-200):pos+200].decode("ascii","replace"))

new = (b"if (r891_nsec == 0u || r891_nsec > 64u) r891_nsec = 1u; /* R1332 (c275): clamp raised 24->64 - the c272/c273 receipts convicted this clamp as THE undersized-serve cause: the f15 request (FDF8=0x16814=92180B) derived nsec=46, the >24 guard reduced it to 1 sector, then the doorbell zeroed FDF8/FE04 and set transfer-DONE - a 46-sector request announced complete with 1 sector; the game found the data short and tore down (GetStat -> PAUSE -> fault-walk restart to state 0, c273 dossier). 64 covers every in-band file (max f14 = 62 sectors) while still guarding absurd counts */")
data2 = data[:pos] + new + data[pos+len(old):]

ok = True
checks = [("clamp-24-removed", data2.count(b"r891_nsec > 24u"), 0),
          ("clamp-64-added", data2.count(b"r891_nsec > 64u"), 1),
          ("R1332-added", data2.count(b"R1332"), 1),
          ("r891_nsec-arity-intact", data2.count(b"r891_nsec"), data.count(b"r891_nsec"))]
for name, got, want in checks:
    print("MARKER %s want=%d got=%d %s" % (name, want, got, "OK" if got == want else "FAIL"))
    if got != want: ok = False
if not ok: sys.exit(1)
open("runtime/runtime.c","wb").write(data2)
print("NEW_SHA=%s" % hashlib.sha256(data2).hexdigest())
PYEOF
echo "PATCH-APPLIED sha=$(shasum -a 256 "$SRC" | cut -d' ' -f1)"

echo "===PARSE275=== the syntax gate (restore on break)"
clang -fsyntax-only -std=gnu99 "$SRC" > /tmp/parse_c275_post.txt 2>&1
POST_RC=$?
echo "PARSE post_rc=$POST_RC"
head -4 /tmp/parse_c275_post.txt
if [ "$POST_RC" -ne 0 ]; then
  cp -p "$P/runtime.c.pre" "$SRC"; echo "PARSE-BREAK - baseline RESTORED, nothing run"; exit 1
fi
echo "PARSE OK"

echo "===RUN275=== the 150s receipt run"
RUN_BUDGET_S=150 ./run.sh > /tmp/run_full_c275.txt 2>&1
echo "RUNSH_RC=$?"
head -4 /tmp/run_full_c275.txt
if [ -s run.log ]; then cp -p run.log "$P/run.log.post"; echo "RUNLOG_POST sha=$(shasum -a 256 "$P/run.log.post" | cut -d" " -f1) size=$(wc -c < "$P/run.log.post" | tr -d " ")"; fi

echo "===MDOOR275=== the fire receipt (expect the full batch now)"
grep -n "\[mvdoor\]" run.log 2>/dev/null | head -6
echo "--- near-misses:"
grep -n "mvdoor-near" run.log 2>/dev/null | head -4

echo "===CHAIN275=== the game post-serve chain (new commands beyond the teardown ladder?)"
grep -n "cmdtl" run.log 2>/dev/null | head -14

echo "===DST275=== the served destination + consumers"
grep -n "800D0994" run.log 2>/dev/null | head -8

echo "===DRAIN275=== the ledger census"
grep -o "FDF8=[0-9A-F]*" run.log 2>/dev/null | sort | uniq -c | sort -rn | head -8
grep -n "pumpcam" run.log 2>/dev/null | tail -4

echo "===STATE275=== the state census"
echo "bootmain=$(grep -c bootmain run.log 2>/dev/null) traps=$(grep -c "NULL-trap #" run.log 2>/dev/null) abort131=$(grep -c "code=131" run.log 2>/dev/null) mdec=$(grep -c mdec run.log 2>/dev/null)"
grep -n "active state" run.log 2>/dev/null | tail -5

echo "===SCENE275=== the scene + input census"
grep -n "gpufin" run.log 2>/dev/null | tail -1
grep -n "padvpx\]" run.log 2>/dev/null | head -4
grep -n "rungasp" run.log 2>/dev/null | tail -1

echo "===C275DONE=== sized-serve cycle complete - verdict from these receipts; REVERT = restore $P/runtime.c.pre"
