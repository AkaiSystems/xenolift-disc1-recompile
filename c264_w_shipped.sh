#!/bin/bash
# c264_zrfg_widen.sh (v3, marker R1328) - THE ONE-TERM WIDEN of zrfG
# (the sgarm precedent, 5th application; one term, runtime.c).
# v3 CORRECTION (c263 receipts caught a MARKER COLLISION, the c135
# class 5th occurrence): the widen was named R1305 - but the tree
# ALREADY carries R1305+R1306+R1307+R1308 (the c206-era bldprov
# markers), so the idempotent check false-skipped and NO EDIT was
# made; the c263 run was an evidence run on the unchanged R1303
# tree 2b2eb134. LESSON: verify the marker number is unused in-tree
# before shipping. v3 uses R1328 (above R1327, free) and the
# idempotent check keys on R1328 alone. THE c261 RECEIPTS:
# the R1303 widen applied clean at the zrfG2 A22C-site gate (tree
# 2b2eb134) but ZERO fires - the wedge posture byte-identical all
# window (FDF8=00016814 pend=0 act=0 seek=108995) = THE A22C SITE IS
# COLD in this wedge era: the f15 waiter is NOT reading the A22C
# cell (the c190 polls-A22C lesson belonged to the movie-loader
# family). THE LIKELY POLLER: the cdreg block / status register -
# the cdstate census receipts 1991 cdreg READS - and the status site
# is where zrfG (R1285) sits with THE SAME cmd==01 gate that just
# blocked its A22C sibling. THE FIX: accept cmd 01 OR 02 in the zrfG
# gate (gate text receipted byte-exact in the c259 dump: the
# r1285_stuck block). AND THIS RUN'S GOOD RECEIPTS: the deep
# trajectory held - bootmain=2, state 1 ENGAGED AND HELD (pFnMain=
# 80077E88 hasOverlay=1), screen 100 PERCENT nonblank through the
# era, press#1 into a valid buffer (ID=40 preserved) + release +
# press#2 via the epoch re-arm, exit 0 CLEAN MAIN-RETURN at the
# fuse. PASS = zrfG fires at the f15 posture + the game drain
# consumes FDF8 below 92180 + forward execution. REVERT if fire
# with zero consumption. REVERT = restore the preserved
# runtime.c.pre.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C263-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="2b2eb13460b03ed8fd127a6a834f81bc884d00820397c44eab4b5de7440a9bfe"
if [ ! -s "$SRC" ]; then echo "C263-FAILED: runtime/runtime.c missing"; exit 1; fi
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA_BEFORE=$SS"
if [ "$SS" != "$EXPECT" ]; then
  if grep -q "R1328" "$SRC" 2>/dev/null; then
    echo "GATE-ALT: tree already carries R1328 (patch landed before a crash) - IDEMPOTENT mode: no patch, evidence run only; tree=$SS"
    ALREADY=1
  else
    echo "GATE-FAILED: runtime.c is neither the R1303 tree 2b2eb134 nor an R1328 tree - refusing a foreign tree"; exit 0
  fi
fi
ALREADY=${ALREADY:-0}
[ "$ALREADY" -eq 1 ] || echo "BASELINE_VERIFIED (the R1303 tree)"
P="patch_c263_$(date +%Y%m%d_%H%M%S)"
if ! (mkdir -p "$P" && cp -p "$SRC" "$P/runtime.c.pre"); then echo "C263-FAILED: preserve failed"; exit 1; fi
echo "PRESERVED: $P/runtime.c.pre sha=$SS"

if [ "$ALREADY" -eq 1 ]; then
  echo "===PATCH264=== SKIPPED (tree already carries R1328) - parse + evidence run only"
else
echo "===PATCH264=== the R1328 zrfG cmd widen (python, binary-safe, FAIL EXPLICIT)"
python3 - <<'PYEOF' || { echo "PATCH-FAILED - nothing written, no run"; exit 1; }
import hashlib, sys
data = open("runtime/runtime.c","rb").read()
if b"R1328" in data:
    print("IDEMPOTENT-SKIP: R1328 already present - no edit made"); sys.exit(0)

i1285 = data.find(b"r1285_stuck")
print("r1285_stuck anchor offset=%d" % i1285)
if i1285 == -1: sys.exit(1)
cend = data.find(b"*/", i1285)
if cend == -1 or cend - i1285 > 8000:
    print("ANCHOR-FAILED: no comment end near r1285_stuck"); sys.exit(1)

before01 = data.count(b"cd_last_cmd == 0x01u")
before02 = data.count(b"cd_last_cmd == 0x02u")
beforeR5 = data.count(b"R1328")
print("PRIOR counts: cmd01=%d cmd02=%d R1328=%d" % (before01, before02, beforeR5))

pos = data.find(b"cd_last_cmd == 0x01u", cend)
if pos == -1 or pos - cend > 3000:
    print("GATE-CONTEXT (first 600 bytes after comment end):")
    print(data[cend:cend+600].decode("ascii","replace"))
    print("ANCHOR-FAILED: no cmd01 term within 3000 bytes of the r1285 comment end"); sys.exit(1)
print("GATE-CONTEXT (300 bytes before/after the anchor):")
print(data[max(0,pos-300):pos+300].decode("ascii","replace"))

old = b"cd_last_cmd == 0x01u"
new = b"(cd_last_cmd == 0x01u || cd_last_cmd == 0x02u) /* R1328 (c264): the c258 f15 wedge holds last_cmd=02; the A22C-site sibling (R1303) never evaluated - this era polls the status site; one-term widen, sgarm precedent; safety terms unchanged */"
data2 = data[:pos] + new + data[pos+len(old):]

ok = True
checks = [("cmd01-unchanged", data2.count(b"cd_last_cmd == 0x01u"), before01),
          ("cmd02-plus-one", data2.count(b"cd_last_cmd == 0x02u"), before02 + 1),
          ("R1328-added", data2.count(b"R1328"), beforeR5 + 1)]
for name, got, want in checks:
    print("MARKER %s want=%d got=%d %s" % (name, want, got, "OK" if got == want else "FAIL"))
    if got != want: ok = False
if not ok:
    print("PATCHED-CONTEXT (300 bytes at the edit):")
    print(data2[max(0,pos-200):pos+400].decode("ascii","replace"))
    sys.exit(1)
open("runtime/runtime.c","wb").write(data2)
print("NEW_SHA=%s" % hashlib.sha256(data2).hexdigest())
PYEOF
echo "PATCH-APPLIED sha=$(shasum -a 256 "$SRC" | cut -d" " -f1)"
fi

echo "===PARSE263=== the syntax gate (pre vs post; restore on break)"
clang -fsyntax-only -std=gnu99 "$SRC" > /tmp/parse_c263_post.txt 2>&1
POST_RC=$?
echo "PARSE post_rc=$POST_RC"
head -4 /tmp/parse_c263_post.txt
if [ "$POST_RC" -ne 0 ]; then
  cp -p "$P/runtime.c.pre" "$SRC"; echo "PARSE-BREAK - baseline RESTORED, nothing run"; exit 1
fi
echo "PARSE OK"

echo "===RUN263=== the 150s receipt run"
RUN_BUDGET_S=150 ./run.sh > /tmp/run_full_c263.txt 2>&1
echo "RUNSH_RC=$?"
head -4 /tmp/run_full_c263.txt
if [ -s run.log ]; then cp -p run.log "$P/run.log.post"; echo "RUNLOG_POST sha=$(shasum -a 256 "$P/run.log.post" | cut -d" " -f1) size=$(wc -c < "$P/run.log.post" | tr -d " ")"; fi

echo "===ZRFG264=== the door receipts (did the status-site widen fire?)"
grep -n "zrfG\]\|R1285\|R1328" run.log 2>/dev/null | head -12

echo "===DRAIN263=== THE DISCRIMINATOR: did the game consume the f15 debt?"
grep -n "pumpcam" run.log 2>/dev/null | tail -6
echo "--- FDF8 values seen at the pump:"
grep -o "FDF8=[0-9A-F]*" run.log 2>/dev/null | sort | uniq -c | sort -rn | head -8
echo "--- READ ISSUED + file#15 receipts:"
grep -n "READ ISSUED\|file#=15" run.log 2>/dev/null | tail -8

echo "===POLLER263=== who did the wedge-era game read?"
grep -n "cdstate" run.log 2>/dev/null | tail -6
echo "--- response pops + pad polls + mvdoor census (late window):"
grep -c "rspop01" run.log 2>/dev/null
grep -c "padrd\] R811" run.log 2>/dev/null
grep -c "mvdoor-near" run.log 2>/dev/null

echo "===STATE263=== the state + guard census"
echo "bootmain=$(grep -c bootmain run.log 2>/dev/null) traps=$(grep -c "NULL-trap #" run.log 2>/dev/null) abort131=$(grep -c "code=131" run.log 2>/dev/null)"
grep -n "arenaseed\]" run.log 2>/dev/null | head -4
grep -n "active state" run.log 2>/dev/null | tail -4

echo "===SCENE263=== the scene + input census"
grep -n "nonblank" run.log 2>/dev/null | tail -3
grep -n "gpufin" run.log 2>/dev/null | tail -1
grep -n "padvpx\]" run.log 2>/dev/null | head -4
grep -o "btn=[0-9A-F]*" run.log 2>/dev/null | sort | uniq -c | head -6
grep -n "rungasp" run.log 2>/dev/null | tail -1

echo "===C264DONE=== zrfG widen cycle complete - verdict from these receipts; REVERT = restore $P/runtime.c.pre"
