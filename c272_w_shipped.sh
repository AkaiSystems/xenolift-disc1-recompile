#!/bin/bash
# c271_mvdoor_band_v2.sh (v2 reship) - THE R1331 MVDOOR BAND WIDEN, byte-exact.
# v2: the c271 v1 marker check expected cd_seek_lba <= 109400u count 1,
# but the tree ALREADY carries 2 such terms (the defib6 band family) -
# corrected to existing+1. Nothing else changed.
# THE c270 SRC-DUMP VERDICT: the FE48 question was a RED HERRING -
# the R887 gate reads 0x8004FE48u (the 4F copy) which is 0 at the
# wedge (PASSES); the 5F copy the near-print showed =1 is the
# DEV-MODE flag our own code sets 1 (writers at tree lines
# 1101/1795/2140/11609) and R835 zeroes at the archive door - the
# sdoor receipts show FE48(5F)=1 during HEALTHY boot deliveries.
# Term-by-term against the receipted wedge posture (mvdoor-near
# 30643): fired<16 OK, cmd 02 OK, FDF8!=0 OK, FE1C 0 OK, FDFC(5F)=0
# OK, FE48(4F)=0 OK, FE30(4F)=0 OK - THE ONLY FAILING TERM IS THE
# BAND: seek 108995 > 108900. Also receipted: the ring feeder is
# retired-in-place (R605 log-only, gated to the old f0c==14 era) and
# the full-stream feeder R705/R708 is deliberately pre-spent
# (R1188, the stale-f15-image SIGSEGV conviction) - both stay dead.
# THE FIX: widen the band upper edge 108900u -> 109400u with the
# byte-exact two-term anchor (cd_seek_lba >= 108700u && cd_seek_lba
# <= 108900u - unique in-tree). 109400 matches the defib6 band edge
# precedent (108754-109400); the f15 file family is the same
# armed-idle class. The R887 stickiness fingerprint (two consecutive
# 1-second watcher ticks; healthy reads last milliseconds) + the
# 16-fire budget + re-arm-while-owed stay in place.
# PASS = the doorbell FIRES at the wedge posture ([mvdoor] receipt,
# r879_fired increments) + the game drain consumes FDF8 below
# 92180 + forward execution (new commands/states/mdec-era receipts).
# REVERT if fire with zero consumption.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C271-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="513eb593ec5fcf407a08f0b4072c6670a52c963a61af38e4a2564cbb573ffbd4"
if [ ! -s "$SRC" ]; then echo "C271-FAILED: runtime/runtime.c missing"; exit 1; fi
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA_BEFORE=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1329 tree 513eb593 - refusing a foreign tree"; exit 0; fi
echo "BASELINE_VERIFIED (the R1329 tree)"
P="patch_c271_$(date +%Y%m%d_%H%M%S)"
if ! (mkdir -p "$P" && cp -p "$SRC" "$P/runtime.c.pre"); then echo "C271-FAILED: preserve failed"; exit 1; fi
echo "PRESERVED: $P/runtime.c.pre sha=$SS"

echo "===PATCH271=== the R1331 band widen (byte-exact, FAIL EXPLICIT)"
python3 - <<'PYEOF' || { echo "PATCH-FAILED - nothing written, no run"; exit 1; }
import hashlib, sys
data = open("runtime/runtime.c","rb").read()
if b"R1331" in data:
    print("IDEMPOTENT-SKIP: R1331 already present - no edit made"); sys.exit(0)
if data.count(b"R1331") != 0:
    print("MARKER-COLLISION: R1331 already used in tree - refusing"); sys.exit(1)

old = b"cd_seek_lba >= 108700u && cd_seek_lba <= 108900u"
n = data.count(old)
print("R1331 anchor count=%d (must be exactly 1)" % n)
if n != 1:
    idx = 0
    while True:
        idx = data.find(b"108700u", idx)
        if idx == -1: break
        print("108700u occurrence at offset %d: ...%s..." % (idx, data[max(0,idx-70):idx+80].decode("ascii","replace").replace("\n"," | ")))
        idx += 1
    sys.exit(1)
pos = data.find(old)
print("ANCHOR-CONTEXT (240 bytes before/after):")
print(data[max(0,pos-240):pos+240].decode("ascii","replace"))

new = (b"cd_seek_lba >= 108700u && cd_seek_lba <= 109400u /* R1331 (c271): band upper edge 108900->109400 - covers the f15 file family (file#15 LBA 108995 receipted; the defib6 band-edge precedent 109400) - same armed-idle class; the 5F-copy FE48 the near-print shows is NOT a gate term (the gate reads the 4F copy, verified zero at the wedge by the c270 src-dump) */")
data2 = data[:pos] + new + data[pos+len(old):]

ok = True
before900 = data.count(b"<= 108900u")
checks = [("band-108900-removed", data2.count(b"cd_seek_lba <= 108900u"), 0),
          ("109400-added", data2.count(b"cd_seek_lba <= 109400u"), data.count(b"cd_seek_lba <= 109400u") + 1),
          ("R1331-added", data2.count(b"R1331"), 1),
          ("R891-comment-intact", data2.count(b"R891: A22C check DROPPED"), data.count(b"R891: A22C check DROPPED")),
          ("R1330-absent", data2.count(b"R1330"), 0)]
for name, got, want in checks:
    print("MARKER %s want=%d got=%d %s" % (name, want, got, "OK" if got == want else "FAIL"))
    if got != want: ok = False
if not ok: sys.exit(1)
open("runtime/runtime.c","wb").write(data2)
print("NEW_SHA=%s" % hashlib.sha256(data2).hexdigest())
PYEOF
echo "PATCH-APPLIED sha=$(shasum -a 256 "$SRC" | cut -d' ' -f1)"

echo "===PARSE271=== the syntax gate (restore on break)"
clang -fsyntax-only -std=gnu99 "$SRC" > /tmp/parse_c271_post.txt 2>&1
POST_RC=$?
echo "PARSE post_rc=$POST_RC"
head -4 /tmp/parse_c271_post.txt
if [ "$POST_RC" -ne 0 ]; then
  cp -p "$P/runtime.c.pre" "$SRC"; echo "PARSE-BREAK - baseline RESTORED, nothing run"; exit 1
fi
echo "PARSE OK"

echo "===RUN271=== the 150s receipt run"
RUN_BUDGET_S=150 ./run.sh > /tmp/run_full_c271.txt 2>&1
echo "RUNSH_RC=$?"
head -4 /tmp/run_full_c271.txt
if [ -s run.log ]; then cp -p run.log "$P/run.log.post"; echo "RUNLOG_POST sha=$(shasum -a 256 "$P/run.log.post" | cut -d" " -f1) size=$(wc -c < "$P/run.log.post" | tr -d " ")"; fi

echo "===MDOOR271=== THE DOORBELL: did it fire?"
grep -n "\[mvdoor\]" run.log 2>/dev/null | head -10
echo "--- near-misses after the widen (match should now be 1):"
grep -n "mvdoor-near" run.log 2>/dev/null | head -6

echo "===DRAIN271=== THE DISCRIMINATOR"
grep -n "pumpcam" run.log 2>/dev/null | tail -4
echo "--- FDF8 census at the pump:"
grep -o "FDF8=[0-9A-F]*" run.log 2>/dev/null | sort | uniq -c | sort -rn | head -8
echo "--- READ ISSUED + file#15:"
grep -n "READ ISSUED\|file#=15" run.log 2>/dev/null | tail -6

echo "===STATE271=== the state + guard census"
echo "bootmain=$(grep -c bootmain run.log 2>/dev/null) traps=$(grep -c "NULL-trap #" run.log 2>/dev/null) abort131=$(grep -c "code=131" run.log 2>/dev/null) mdec=$(grep -c mdec run.log 2>/dev/null)"
grep -n "active state" run.log 2>/dev/null | tail -4

echo "===SCENE271=== the scene + input census"
grep -n "gpufin" run.log 2>/dev/null | tail -1
grep -n "padvpx\]" run.log 2>/dev/null | head -3
grep -n "rungasp" run.log 2>/dev/null | tail -1

echo "===C271DONE=== band widen v2 cycle complete - verdict from these receipts; REVERT = restore $P/runtime.c.pre"
