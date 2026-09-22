#!/bin/bash
# c265_zrfg_widen_v3.sh - THE R1329 zrfG WIDEN, CLEAN RE-APPLY after
# the c264 MISPLACEMENT (a new c135-class variant: correct marker
# deltas at the WRONG SITE). THE c264 POST-MORTEM: the positional
# anchor (first cmd01 term after the next */ following the
# r1285_stuck declaration) hit the R1302 GetStat ack POP CAMERA
# (print-only condition), not the zrfG gate - because the r1285_stuck
# DECLARATION comes AFTER its block comment, the "next */" pointed
# far below and the first cmd01 match belonged to the pop camera.
# The marker deltas passed (they verify counts, NOT location). The
# misplaced edit is print-only (harmless) but mislabeled - REVERT.
# ALSO RECEIPTED: the f15 wedge DISSOLVES (~60s in: cells clear
# FE04=0 FDF8=0, a small seek=0 request, then exitdiag 99) - the
# game TIMES OUT the request rather than draining it; the read still
# never converts.
# v3 PLAN: (1) RESTORE the preserved pre (2b2eb134) - this removes
# the misplaced R1328; verify sha + assert the R1302 camera is
# cmd01-only again; (2) apply the widen with a BYTE-EXACT two-line
# anchor from the c259 dump: the cmd01 gate term plus the seek>=100000u line - unique to zrfG (zrfF holds < 150u; zrfG2 is now the
# R1303 OR-form) - with a count==1 assert BEFORE patching (FAIL
# EXPLICIT prints context if the site is not unique); (3) parse gate,
# 150s run, same digest. PASS = zrfG fires at the f15 posture + the
# drain consumes FDF8 below 92180 + forward execution. REVERT if
# fire with zero consumption.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C265-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
PRE="patch_c263_20260917_074849/runtime.c.pre"
PRE_SHA="2b2eb13460b03ed8fd127a6a834f81bc884d00820397c44eab4b5de7440a9bfe"
CUR="2eab69dc495a22031d482c860f9084da66528cbce5f13690e0623ee53d04a862"
if [ ! -s "$SRC" ]; then echo "C265-FAILED: runtime/runtime.c missing"; exit 1; fi
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA_BEFORE=$SS"
if [ "$SS" != "$CUR" ]; then echo "GATE-FAILED: runtime.c is not the c264 tree 2eab69dc - refusing (expecting the misplaced-R1328 tree to revert)"; exit 0; fi
if [ ! -s "$PRE" ]; then echo "C265-FAILED: preserved pre $PRE missing - cannot revert the misplaced R1328"; exit 1; fi
PS=$(shasum -a 256 "$PRE" | cut -d" " -f1)
echo "PRE_SHA=$PS"
if [ "$PS" != "$PRE_SHA" ]; then echo "C265-FAILED: preserved pre sha mismatch - refusing"; exit 1; fi
cp -p "$PRE" "$SRC"
RS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "REVERTED to $RS"
if [ "$RS" != "$PRE_SHA" ]; then echo "C265-FAILED: revert verification failed"; exit 1; fi
if grep -q "R1328" "$SRC"; then echo "C265-FAILED: R1328 still present after revert"; exit 1; fi
if ! grep -q 'if (cd_last_cmd == 0x01u) { /\* R1302' "$SRC"; then echo "C265-NOTE: R1302 camera form differs - verifying differently"; grep -n "R1302 (c200" "$SRC" | head -2; fi
echo "R1302 CAMERA RESTORED (cmd01-only pop condition)"
P="patch_c265_$(date +%Y%m%d_%H%M%S)"
if ! (mkdir -p "$P" && cp -p "$SRC" "$P/runtime.c.pre"); then echo "C265-FAILED: preserve failed"; exit 1; fi
echo "PRESERVED: $P/runtime.c.pre sha=$RS"

echo "===PATCH265=== the R1329 zrfG cmd widen (byte-exact anchor, FAIL EXPLICIT)"
python3 - <<'PYEOF' || { echo "PATCH-FAILED - nothing written, no run"; exit 1; }
import hashlib, sys
data = open("runtime/runtime.c","rb").read()
if b"R1329" in data:
    print("IDEMPOTENT-SKIP: R1329 already present - no edit made"); sys.exit(0)

old = (b"cd_last_cmd == 0x01u\n"
       b"                && cd_seek_lba >= 100000u")
n = data.count(old)
print("R1329 anchor count=%d (must be exactly 1)" % n)
if n != 1:
    for i, line in enumerate(data.decode("ascii","replace").splitlines(), 1):
        pass
    idx = 0
    while True:
        idx = data.find(b"cd_last_cmd == 0x01u", idx)
        if idx == -1: break
        print("cmd01 occurrence at offset %d: ...%s..." % (idx, data[max(0,idx-60):idx+90].decode("ascii","replace").replace("\n"," | ")))
        idx += 1
    sys.exit(1)
pos = data.find(old)
print("ANCHOR-CONTEXT (300 bytes before/after):")
print(data[max(0,pos-300):pos+300].decode("ascii","replace"))

before01 = data.count(b"cd_last_cmd == 0x01u")
before02 = data.count(b"cd_last_cmd == 0x02u")
new = (b"(cd_last_cmd == 0x01u || cd_last_cmd == 0x02u) /* R1329 (c265): the c258 f15 wedge holds last_cmd=02 post-Setloc; zrfG2's A22C site ran cold (R1303), the status site is the poller; one-term widen, sgarm precedent; safety terms unchanged */\n"
       b"                && cd_seek_lba >= 100000u")
data2 = data[:pos] + new + data[pos+len(old):]

ok = True
checks = [("cmd01-unchanged", data2.count(b"cd_last_cmd == 0x01u"), before01),
          ("cmd02-plus-one", data2.count(b"cd_last_cmd == 0x02u"), before02 + 1),
          ("R1329-added", data2.count(b"R1329"), 1),
          ("zrfG2-R1303-intact", data2.count(b"R1303"), data.count(b"R1303"))]
for name, got, want in checks:
    print("MARKER %s want=%d got=%d %s" % (name, want, got, "OK" if got == want else "FAIL"))
    if got != want: ok = False
if not ok: sys.exit(1)
open("runtime/runtime.c","wb").write(data2)
print("NEW_SHA=%s" % hashlib.sha256(data2).hexdigest())
PYEOF
echo "PATCH-APPLIED sha=$(shasum -a 256 "$SRC" | cut -d' ' -f1)"

echo "===PARSE265=== the syntax gate (restore on break)"
clang -fsyntax-only -std=gnu99 "$SRC" > /tmp/parse_c265_post.txt 2>&1
POST_RC=$?
echo "PARSE post_rc=$POST_RC"
head -4 /tmp/parse_c265_post.txt
if [ "$POST_RC" -ne 0 ]; then
  cp -p "$P/runtime.c.pre" "$SRC"; echo "PARSE-BREAK - baseline RESTORED, nothing run"; exit 1
fi
echo "PARSE OK"

echo "===RUN265=== the 150s receipt run"
RUN_BUDGET_S=150 ./run.sh > /tmp/run_full_c265.txt 2>&1
echo "RUNSH_RC=$?"
head -4 /tmp/run_full_c265.txt
if [ -s run.log ]; then cp -p run.log "$P/run.log.post"; echo "RUNLOG_POST sha=$(shasum -a 256 "$P/run.log.post" | cut -d" " -f1) size=$(wc -c < "$P/run.log.post" | tr -d " ")"; fi

echo "===ZRFG265=== the door receipts (zrfG fires at the status site?)"
grep -n "zrfG\]\|R1285\|R1329" run.log 2>/dev/null | head -12

echo "===DRAIN265=== THE DISCRIMINATOR"
grep -n "pumpcam" run.log 2>/dev/null | tail -6
echo "--- FDF8 values seen at the pump:"
grep -o "FDF8=[0-9A-F]*" run.log 2>/dev/null | sort | uniq -c | sort -rn | head -8
echo "--- READ ISSUED + file#15:"
grep -n "READ ISSUED\|file#=15" run.log 2>/dev/null | tail -6

echo "===STATE265=== the state + guard census"
echo "bootmain=$(grep -c bootmain run.log 2>/dev/null) traps=$(grep -c "NULL-trap #" run.log 2>/dev/null) abort131=$(grep -c "code=131" run.log 2>/dev/null)"
grep -n "arenaseed\]" run.log 2>/dev/null | head -3
grep -n "active state" run.log 2>/dev/null | tail -4

echo "===SCENE265=== the scene + input census"
grep -n "gpufin" run.log 2>/dev/null | tail -1
grep -n "padvpx\]" run.log 2>/dev/null | head -4
grep -o "btn=[0-9A-F]*" run.log 2>/dev/null | sort | uniq -c | head -4
grep -n "rungasp" run.log 2>/dev/null | tail -1

echo "===C265DONE=== clean zrfG widen cycle complete - verdict from these receipts; REVERT = restore $P/runtime.c.pre"
