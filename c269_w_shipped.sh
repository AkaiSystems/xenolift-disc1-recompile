#!/bin/bash
# c269_mvdoor_band_widen.sh - THE R1330 MVDOOR BAND WIDEN (one token)
# + THE SOURCE DUMPS that decide the FE48 term next cycle.
# THE c268 DOSSIER VERDICT: the mvdoor watcher is THE live mechanism
# (4 byte-identical near-miss receipts; the alarm pump, SPU DMA
# notifiers, and pad polls all alive in the window). The failing
# terms isolated: (1) seek 108995 OUTSIDE the band [108700,108900]
# - and 108995 is file#15's receipted LBA, with the defib6 band
# (108754-109400) already covering the same file family - a
# calibration miss, not a safety term: WIDEN to 109400. (2) FE48(5F)=1
# where the gate requires 0 - the ONE term with unreceipted
# semantics: the 5F copy has NO writer camera (the watch table covers
# only the 4F copy; its receipts show the teardown fn writing 0->0).
# Per the verify-before-clearing rule the FE48 term STAYS this
# cycle. THIS CYCLE also receipts: the wedge window is fault-heal
# churn (16 segvrec + 12 defib5 + 12 exitdiag) and the dissolve is a
# game-driven teardown (cells clear, then cmd 02->01->00->0c, 3
# responses pending); the wedge loop is NOT the mvloop family
# (parkcam cur_fn=800357C0; no mvloop tag in the window).
# THE DIGEST dumps the R887 gate source, the defib6 gate source,
# and the FE48 watch config - the byte-exact anchors for the FE48
# decision. PASS for the eventual door = fire + FDF8 drains below
# 92180 + forward execution. REVERT if fire with zero consumption.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C269-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="513eb593ec5fcf407a08f0b4072c6670a52c963a61af38e4a2564cbb573ffbd4"
if [ ! -s "$SRC" ]; then echo "C269-FAILED: runtime/runtime.c missing"; exit 1; fi
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA_BEFORE=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1329 tree 513eb593 - refusing a foreign tree"; exit 0; fi
echo "BASELINE_VERIFIED (the R1329 tree)"
P="patch_c269_$(date +%Y%m%d_%H%M%S)"
if ! (mkdir -p "$P" && cp -p "$SRC" "$P/runtime.c.pre"); then echo "C269-FAILED: preserve failed"; exit 1; fi
echo "PRESERVED: $P/runtime.c.pre sha=$SS"

echo "===PATCH269=== the R1330 band widen (one token, FAIL EXPLICIT)"
python3 - <<'PYEOF' || { echo "PATCH-FAILED - nothing written, no run"; exit 1; }
import hashlib, sys
data = open("runtime/runtime.c","rb").read()
if b"R1330" in data:
    print("IDEMPOTENT-SKIP: R1330 already present - no edit made"); sys.exit(0)
if data.count(b"R1330") != 0:
    print("MARKER-COLLISION: R1330 already used in tree - refusing"); sys.exit(1)

old = b"108900u"
n = data.count(old)
print("R1330 anchor count=%d (must be exactly 1)" % n)
if n != 1:
    idx = 0
    while True:
        idx = data.find(b"1089", idx)
        if idx == -1: break
        print("1089xx occurrence at offset %d: ...%s..." % (idx, data[max(0,idx-70):idx+60].decode("ascii","replace").replace("\n"," | ")))
        idx += 1
    sys.exit(1)
pos = data.find(old)
print("ANCHOR-CONTEXT (300 bytes before/after):")
print(data[max(0,pos-300):pos+300].decode("ascii","replace"))

new = b"109400u /* R1330 (c269): band upper edge widened 108900->109400 - covers file#15 LBA 108995 (receipted ftab) and matches the defib6 band edge (108754-109400, same file family); the FE48(5F) term stays this cycle */"
data2 = data[:pos] + new + data[pos+len(old):]

ok = True
checks = [("108900-removed", data2.count(b"108900u"), 0),
          ("109400-added", data2.count(b"109400u"), data.count(b"109400u") + 1),
          ("R1330-added", data2.count(b"R1330"), 1)]
for name, got, want in checks:
    print("MARKER %s want=%d got=%d %s" % (name, want, got, "OK" if got == want else "FAIL"))
    if got != want: ok = False
if not ok: sys.exit(1)
open("runtime/runtime.c","wb").write(data2)
print("NEW_SHA=%s" % hashlib.sha256(data2).hexdigest())
PYEOF
echo "PATCH-APPLIED sha=$(shasum -a 256 "$SRC" | cut -d' ' -f1)"

echo "===PARSE269=== the syntax gate (restore on break)"
clang -fsyntax-only -std=gnu99 "$SRC" > /tmp/parse_c269_post.txt 2>&1
POST_RC=$?
echo "PARSE post_rc=$POST_RC"
head -4 /tmp/parse_c269_post.txt
if [ "$POST_RC" -ne 0 ]; then
  cp -p "$P/runtime.c.pre" "$SRC"; echo "PARSE-BREAK - baseline RESTORED, nothing run"; exit 1
fi
echo "PARSE OK"

echo "===SRCDUMP269=== the byte-exact anchors for the FE48 decision (read-only)"
echo "--- the R887 mvdoor gate source:"
grep -n -B2 -A30 "r887_streak" "$SRC" | head -44
echo "--- the defib6 gate source:"
grep -n -B2 -A26 "defib6" "$SRC" | head -40
echo "--- the FE48 watch config:"
grep -n "FE48" "$SRC" | head -12

echo "===RUN269=== the 150s receipt run"
RUN_BUDGET_S=150 ./run.sh > /tmp/run_full_c269.txt 2>&1
echo "RUNSH_RC=$?"
head -4 /tmp/run_full_c269.txt
if [ -s run.log ]; then cp -p run.log "$P/run.log.post"; echo "RUNLOG_POST sha=$(shasum -a 256 "$P/run.log.post" | cut -d" " -f1) size=$(wc -c < "$P/run.log.post" | tr -d " ")"; fi

echo "===MDOOR269=== the door receipts (band fixed; FE48 term still required)"
grep -n "mvdoor" run.log 2>/dev/null | head -8

echo "===DRAIN269=== THE DISCRIMINATOR"
grep -n "pumpcam" run.log 2>/dev/null | tail -4
echo "--- READ ISSUED + file#15:"
grep -n "READ ISSUED\|file#=15" run.log 2>/dev/null | tail -6

echo "===STATE269=== the state + guard census"
echo "bootmain=$(grep -c bootmain run.log 2>/dev/null) traps=$(grep -c "NULL-trap #" run.log 2>/dev/null) abort131=$(grep -c "code=131" run.log 2>/dev/null)"
grep -n "active state" run.log 2>/dev/null | tail -3

echo "===SCENE269=== the scene + input census"
grep -n "gpufin" run.log 2>/dev/null | tail -1
grep -n "padvpx\]" run.log 2>/dev/null | head -3
grep -n "rungasp" run.log 2>/dev/null | tail -1

echo "===C269DONE=== band widen cycle complete - the FE48 decision is made from these receipts; REVERT = restore $P/runtime.c.pre"
