#!/bin/bash
# c257_site_gate.sh - THE R1327 SITE GATE (one-line insert, runtime.c).
# THE c256 RECEIPTS: the R1326 press/release fired mechanically perfect
# (START PRESSED buf 800625FC FFFF4000->FFF74000 @t=6s, released @t=7s,
# status/ID preserved) - BUT MY V1 BLOCK MISSED ITS SITE GATE (the
# c181-class placement defect): anchored before the R811 camera without
# the a==0x8003569C condition, so it pressed at the FIRST DISPATCH
# after t=5s (line 30585, zero padrd prints nearby, buf from a random
# r[4]) - the empty padrd census receipts it: the game never even
# reached ReadControllerButtons this run. AND the trajectory swung
# shallow: bootmain=10, state 0 held, the menu ran once BEFORE the
# press (menu era ~t=1-2s), then the mvloop spin (old R809 fired 71x
# unconsumed), screen 0%, exit 137 at the fuse - the c178-class
# receipted nondeterminism. THE FIX: gate the whole virtual player on
# the ReadControllerButtons ENTRY (a==0x8003569C) so vbuf uses the
# ACTUALLY-POLLED player's buffer and the press lands AT the polling
# moment - on a deep trajectory (c252/c253: 28K+ polling entries,
# t~1-11s) the t>5s press lands mid-menu-polling. PASS = padvpx fires
# at the polling site (padrd prints adjacent) + the btn census shows
# the press in the game's reads + choice/released cells MOVE.
# REVERT = restore the preserved runtime.c.pre.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C257-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="e3500de93070a1277bee72044d221e80e2a8bb8f229d93aa83427308c93fbb07"
if [ ! -s "$SRC" ]; then echo "C257-FAILED: runtime/runtime.c missing"; exit 1; fi
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA_BEFORE=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1326 tree e3500de9 - refusing a foreign tree"; exit 0; fi
echo "BASELINE_VERIFIED (the R1326 tree)"
P="patch_c257_$(date +%Y%m%d_%H%M%S)"
if ! (mkdir -p "$P" && cp -p "$SRC" "$P/runtime.c.pre"); then echo "C257-FAILED: preserve failed"; exit 1; fi
echo "PRESERVED: $P/runtime.c.pre sha=$SS"

echo "===PATCH257=== the R1327 site gate (python, binary-safe, FAIL EXPLICIT)"
python3 - <<'PYEOF' || { echo "PATCH-FAILED - nothing written, no run"; exit 1; }
import hashlib, sys
data = open("runtime/runtime.c","rb").read()
if b"R1327" in data:
    print("IDEMPOTENT-SKIP: R1327 already present - no edit made"); sys.exit(0)

a = b"        {\n            static uint32_t r1326_epoch = 0xFFFFFFFFu;\n"
n = data.count(a)
print("R1327 anchor count=%d (must be 1)" % n)
if n != 1: sys.exit(1)

rep = (b"        if (a == 0x8003569Cu) { /* R1327 (c257): THE SITE GATE -\n"
 + b"             * the v1 R1326 block (c256) missed its `a` gate (the\n"
 + b"             * c181-class placement defect: it pressed at the FIRST\n"
 + b"             * DISPATCH after t=5s, not at the polling site - the c256\n"
 + b"             * receipts caught it: padvpx fired with zero padrd prints\n"
 + b"             * nearby, buf from a random r[4]). Gate the whole virtual\n"
 + b"             * player on the ReadControllerButtons entry so vbuf uses\n"
 + b"             * the ACTUALLY-POLLED player's buffer and the press lands\n"
 + b"             * AT the polling moment. */\n"
 + b"            static uint32_t r1326_epoch = 0xFFFFFFFFu;\n")

data = data.replace(a, rep, 1)

checks = [("R1327", data.count(b"R1327"), 1),
          ("R1326", data.count(b"R1326"), 4),
          ("padvpx-tag", data.count(b"[padvpx]"), 2),
          ("padrd-site", data.count(b"0x8003569Cu"), 4),
          ("r1326-epoch-decl", data.count(b"static uint32_t r1326_epoch"), 1)]
ok = True
for name, got, want in checks:
    print("MARKER %s want=%d got=%d %s" % (name, want, got, "OK" if got == want else "FAIL"))
    if got != want: ok = False
if not ok: sys.exit(1)
open("runtime/runtime.c","wb").write(data)
print("NEW_SHA=%s" % hashlib.sha256(data).hexdigest())
PYEOF
echo "PATCH-APPLIED sha=$(shasum -a 256 "$SRC" | cut -d" " -f1)"

echo "===PARSE257=== the syntax gate (pre vs post; restore on break)"
clang -fsyntax-only -std=gnu99 "$SRC" > /tmp/parse_c257_pre.txt 2>&1
PRE_RC=$?
clang -fsyntax-only -std=gnu99 "$SRC" > /tmp/parse_c257_post.txt 2>&1
POST_RC=$?
echo "PARSE pre_rc=$PRE_RC post_rc=$POST_RC"
head -4 /tmp/parse_c257_post.txt
if [ "$PRE_RC" -eq 0 ] && [ "$POST_RC" -ne 0 ]; then
  cp -p "$P/runtime.c.pre" "$SRC"; echo "PARSE-BREAK - baseline RESTORED, nothing run"; exit 1
fi
echo "PARSE OK"

echo "===RUN257=== the 150s receipt run"
RUN_BUDGET_S=150 ./run.sh > /tmp/run_full_c257.txt 2>&1
echo "RUNSH_RC=$?"
head -4 /tmp/run_full_c257.txt
if [ -s run.log ]; then cp -p run.log "$P/run.log.post"; echo "RUNLOG_POST sha=$(shasum -a 256 "$P/run.log.post" | cut -d" " -f1) size=$(wc -c < "$P/run.log.post" | tr -d " ")"; fi

echo "===PADVPX257=== the virtual-player receipts (at the polling site this time?)"
grep -n "padvpx\]" run.log 2>/dev/null | head -6

echo "===PADRD257=== the game reads (btn census - did it see the press?)"
grep -o "btn=[0-9A-F]*" run.log 2>/dev/null | sort | uniq -c | head -10
echo "--- player census:"
grep -o "player(r4)=[0-9]*" run.log 2>/dev/null | sort | uniq -c | head -4
echo "--- padrd lines adjacent to the press:"
PL=$(grep -n "padvpx\] R1326 virtual-player START PRESSED" run.log 2>/dev/null | head -1 | cut -d: -f1)
if [ -n "$PL" ]; then
  S=$((PL-3)); [ "$S" -lt 1 ] && S=1
  awk -v s="$S" -v e="$((PL+3))" 'NR>=s&&NR<=e{printf "%d:%s\n",NR,$0}NR>e{exit}' run.log | head -8
fi

echo "===MENU257=== THE RESPONSE: did the menu cells move?"
grep -n "menuchain\]" run.log 2>/dev/null | head -10
echo "--- the choice/released cell history:"
grep -o "choice(4F2D8)=[0-9A-F]*" run.log 2>/dev/null | sort | uniq -c | head -8
grep -o "released(8005948C)=[0-9A-F]*" run.log 2>/dev/null | sort | uniq -c | head -8

echo "===STATE257=== the state + guard census"
echo "bootmain=$(grep -c bootmain run.log 2>/dev/null) traps=$(grep -c "NULL-trap #" run.log 2>/dev/null) abort131=$(grep -c "code=131" run.log 2>/dev/null) padstart809=$(grep -c "padstart\] R809" run.log 2>/dev/null)"
grep -n "arenaseed\]" run.log 2>/dev/null | head -4
grep -n "active state" run.log 2>/dev/null | tail -5

echo "===SCREEN257=== the scene census"
grep -n "nonblank" run.log 2>/dev/null | tail -3
grep -n "gpufin" run.log 2>/dev/null | tail -1
grep -n "rungasp" run.log 2>/dev/null | tail -1

echo "===C257DONE=== site-gate cycle complete - verdict from these receipts; REVERT = restore $P/runtime.c.pre"
