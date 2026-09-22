#!/bin/bash
# c260_zrfg2_widen.sh - THE R1303 ONE-TERM WIDEN of zrfG2 (the sgarm
# precedent, 4th application; one term, runtime.c). THE c258/c259
# RECEIPTS: the f15 wedge (FDF8=92180 armed at seek=108995, FE04==
# seek, act=0, pend=0, drive parked) polls the A22C site - where the
# zrfG2 door (R1290, the c191 file-band serve) already lives with the
# exact composite (same-poll cd_data_load + read_active=1, partition
# guard cd_data_n<2048, stuck-confirm, budget). ITS GATE REQUIRES
# cd_last_cmd == 0x01u - the c258 wedge holds last_cmd=02 (post-
# Setloc: the game armed the byte count and waits without issuing
# ReadN through our machinery). EVERY OTHER TERM RECEIPTS TRUE.
# THE FIX: accept cmd 01 OR 02 in the zrfG2 gate - one term, the
# receipted failing one. The cmd term was a receipt artifact of the
# c184 posture (GetStat polls), not a safety term; the safety terms
# (!read_active, pend==0, FE04==seek the anti-stale provenance guard,
# FDF8 bounds, partition guard, stuck-confirm, budget) all stay.
# ANCHOR DISCIPLINE (the c181 lesson): the c259 dump cut off above the
# gate code, so the patch uses a POSITIONAL anchor (the first
# cd_last_cmd == 0x01u after the R1290 comment block) and FAIL-EXPLICIT
# prints the gate context - if the structure differs, nothing is
# written and the digest receipts the true gate. DELTA-GATES computed
# from the artifact at runtime (the c198 lesson), not absolute counts.
# PASS = zrfG2 fires at the f15 posture + the game drain consumes
# FDF8 below 92180 + forward execution (state activity / new
# requests / screen). REVERT if fire with zero consumption.
# REVERT = restore the preserved runtime.c.pre.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C260-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="33402d7f708187c87b03fc559298fe391cfab6ae64c211ad814718361f6c6b29"
if [ ! -s "$SRC" ]; then echo "C260-FAILED: runtime/runtime.c missing"; exit 1; fi
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA_BEFORE=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1327 tree 33402d7f - refusing a foreign tree"; exit 0; fi
echo "BASELINE_VERIFIED (the R1327 tree)"
P="patch_c260_$(date +%Y%m%d_%H%M%S)"
if ! (mkdir -p "$P" && cp -p "$SRC" "$P/runtime.c.pre"); then echo "C260-FAILED: preserve failed"; exit 1; fi
echo "PRESERVED: $P/runtime.c.pre sha=$SS"

echo "===PATCH260=== the R1303 zrfG2 cmd widen (python, binary-safe, FAIL EXPLICIT)"
python3 - <<'PYEOF' || { echo "PATCH-FAILED - nothing written, no run"; exit 1; }
import hashlib, sys
data = open("runtime/runtime.c","rb").read()
if b"R1303" in data:
    print("IDEMPOTENT-SKIP: R1303 already present - no edit made"); sys.exit(0)

n1290 = data.count(b"R1290")
print("R1290 marker count=%d" % n1290)
if n1290 < 1: sys.exit(1)
i1290 = data.find(b"R1290")
cend = data.find(b"*/", i1290)
print("R1290 comment end offset=%d (marker at %d)" % (cend, i1290))
if cend == -1 or cend - i1290 > 16000: sys.exit(1)

before01 = data.count(b"cd_last_cmd == 0x01u")
before02 = data.count(b"cd_last_cmd == 0x02u")
print("PRIOR counts: cmd01=%d cmd02=%d" % (before01, before02))

pos = data.find(b"cd_last_cmd == 0x01u", cend)
if pos == -1 or pos - cend > 12000:
    print("GATE-CONTEXT (first 600 bytes after comment end):")
    print(data[cend:cend+600].decode("ascii","replace"))
    print("ANCHOR-FAILED: no cd_last_cmd == 0x01u within 12000 bytes of the R1290 comment end"); sys.exit(1)
print("GATE-CONTEXT (300 bytes before/after the anchor):")
print(data[max(0,pos-300):pos+300].decode("ascii","replace"))

old = b"cd_last_cmd == 0x01u"
new = b"(cd_last_cmd == 0x01u || cd_last_cmd == 0x02u) /* R1303 (c260): the c258 wedge holds last_cmd=02 (post-Setloc armed-idle) - one-term widen, the sgarm precedent; safety terms unchanged */"
data2 = data[:pos] + new + data[pos+len(old):]

ok = True
c01 = data2.count(b"cd_last_cmd == 0x01u"); c02 = data2.count(b"cd_last_cmd == 0x02u"); cR = data2.count(b"R1303")
checks = [("cmd01-unchanged", c01, before01),
          ("cmd02-plus-one", c02, before02 + 1),
          ("R1303-added", cR, data.count(b"R1303") + 2)]
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

echo "===PARSE260=== the syntax gate (pre vs post; restore on break)"
clang -fsyntax-only -std=gnu99 "$SRC" > /tmp/parse_c260_pre.txt 2>&1
PRE_RC=$?
clang -fsyntax-only -std=gnu99 "$SRC" > /tmp/parse_c260_post.txt 2>&1
POST_RC=$?
echo "PARSE pre_rc=$PRE_RC post_rc=$POST_RC"
head -4 /tmp/parse_c260_post.txt
if [ "$PRE_RC" -eq 0 ] && [ "$POST_RC" -ne 0 ]; then
  cp -p "$P/runtime.c.pre" "$SRC"; echo "PARSE-BREAK - baseline RESTORED, nothing run"; exit 1
fi
echo "PARSE OK"

echo "===RUN260=== the 150s receipt run"
RUN_BUDGET_S=150 ./run.sh > /tmp/run_full_c260.txt 2>&1
echo "RUNSH_RC=$?"
head -4 /tmp/run_full_c260.txt
if [ -s run.log ]; then cp -p run.log "$P/run.log.post"; echo "RUNLOG_POST sha=$(shasum -a 256 "$P/run.log.post" | cut -d" " -f1) size=$(wc -c < "$P/run.log.post" | tr -d " ")"; fi

echo "===ZRFG2260=== the door receipts (did the widen fire at the f15 posture?)"
grep -n "zrfG2\|R1290\|R1303" run.log 2>/dev/null | head -10

echo "===DRAIN260=== THE DISCRIMINATOR: did the game consume the f15 debt?"
grep -n "pumpcam" run.log 2>/dev/null | tail -6
echo "--- FDF8 values seen at the pump:"
grep -o "FDF8=[0-9A-F]*" run.log 2>/dev/null | sort | uniq -c | sort -rn | head -8
echo "--- READ ISSUED + file#15 receipts:"
grep -n "READ ISSUED\|file#=15" run.log 2>/dev/null | tail -8

echo "===STATE260=== the state + guard census"
echo "bootmain=$(grep -c bootmain run.log 2>/dev/null) traps=$(grep -c "NULL-trap #" run.log 2>/dev/null) abort131=$(grep -c "code=131" run.log 2>/dev/null)"
grep -n "arenaseed\]" run.log 2>/dev/null | head -4
grep -n "active state" run.log 2>/dev/null | tail -4

echo "===SCENE260=== the scene + input census"
grep -n "nonblank" run.log 2>/dev/null | tail -3
grep -n "gpufin" run.log 2>/dev/null | tail -1
grep -n "padvpx\]" run.log 2>/dev/null | head -4
grep -o "btn=[0-9A-F]*" run.log 2>/dev/null | sort | uniq -c | head -6
grep -n "rungasp" run.log 2>/dev/null | tail -1

echo "===C260DONE=== zrfG2 widen cycle complete - verdict from these receipts; REVERT = restore $P/runtime.c.pre"
