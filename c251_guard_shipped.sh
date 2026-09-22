#!/bin/bash
# c251_arena_guard.sh (v2 of c250) - THE R1325 DISPATCHER ARENA WALK
# GUARD (one insert, runtime.c). v2 CORRECTION (marker gate caught it,
# nothing written, tree intact c111b1c3): patch content UNCHANGED -
# only my marker EXPECTATIONS were miscounted. Counted from the actual
# insert + existing tree (the c198 lesson): R1325 = 3 (comment + reseed
# receipt + pass receipt); xenolift_mem_write32(0x800CC26Cu = 2 AFTER
# insert because the existing R1321 seed block already contains one.
# All else identical. (c250 v1 of
# insert, runtime.c). THE c248 RECEIPTS: the abort-131 IS the
# dispatcher sub-arena trap - [arena] table-install ptr=0x800C4A6C
# with GARBAGE cells (A8213A5C/6A2D1440/EF07F805/28030A88 - our R1321
# restart seed was OVERWRITTEN before the install) -> the
# MoveHeapAllocation(800C4A6C,0x8000) release-walk -> cursor=-8 ->
# NULL-trap -> abort-131 -> fault-walk restart -> SIGSEGV t=11s ->
# kit exit 99. AND THE SCREEN PAINTED 100% AFTER SURVIVING IT. THE
# c249 RECEIPTS: the walkcam hook (a==0x8003223C, runtime.c:16139)
# fires at the dispatched ReleaseAllHeapBlocks entry with r[4]=a0 and
# RECEIPTED this exact walk live; the R1321 seed block (:20773) is the
# proven zero+seed semantics. R1325: at walkcam entry with a0=0x800C4A6C
# GUARD the head node - if the cells do not hold a valid chain (flags
# 0x84000000 + next in-region), re-fire the R1321 zero+seed AT THE
# WALK MOMENT; if they do hold a valid chain (the game own healthy
# install), PASS untouched and receipt it. PASS = the walk completes
# with no NULL-trap/abort-131, the 100%-screen era continues past the
# previous SIGSEGV. REVERT = restore the preserved runtime.c.pre.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C250-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="c111b1c34b4ae2a30e6d3647970a0d575fc99fb6a4b412a4ebbc0ce41de30c3a"
if [ ! -s "$SRC" ]; then echo "C250-FAILED: runtime/runtime.c missing"; exit 1; fi
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA_BEFORE=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1322 tree c111b1c3 - refusing a foreign tree"; exit 0; fi
echo "BASELINE_VERIFIED (the R1322 tree)"
P="patch_c250_$(date +%Y%m%d_%H%M%S)"
if ! (mkdir -p "$P" && cp -p "$SRC" "$P/runtime.c.pre"); then echo "C250-FAILED: preserve failed"; exit 1; fi
echo "PRESERVED: $P/runtime.c.pre sha=$SS"

echo "===PATCH250=== the R1325 walk guard (python, binary-safe, FAIL EXPLICIT)"
python3 - <<'PYEOF' || { echo "PATCH-FAILED - nothing written, no run"; exit 1; }
import hashlib, sys
data = open("runtime/runtime.c","rb").read()
if b"R1325" in data:
    print("IDEMPOTENT-SKIP: R1325 already present - no edit made"); sys.exit(0)

a = b"    if (a == 0x8003223Cu) {\n        static int wc_n;\n"
n = data.count(a)
print("R1325 anchor count=%d (must be 1)" % n)
if n != 1: sys.exit(1)

guard = (b"    /* R1325 (c250): THE DISPATCHER ARENA WALK GUARD. The c248\n"
 + b"     * receipts: the dispatcher table-install at 800C4A6C ran with\n"
 + b"     * GARBAGE head cells (A8213A5C/6A2D1440/EF07F805/28030A88 - the\n"
 + b"     * R1321 restart seed overwritten before the install) and the\n"
 + b"     * release-walk trapped (cursor=-8, NULL-trap, abort-131, fault-walk\n"
 + b"     * restart, SIGSEGV t=11s, kit exit 99) - AFTER THE SCREEN PAINTED\n"
 + b"     * 100%. Guard at the walk entry: if the head node does not hold a\n"
 + b"     * valid chain (flags 0x84000000 + next in-region), re-fire the\n"
 + b"     * proven R1321 zero+seed at the walk moment; if it DOES hold a\n"
 + b"     * valid chain (the game own healthy install), pass untouched.\n"
 + b"     * The walk RELEASES all blocks by design, so reseeding a garbage\n"
 + b"     * arena is the deterministic safe path (the c161/R1273 proof). */\n"
 + b"    if (a == 0x8003223Cu && r[4] == 0x800C4A6Cu) {\n"
 + b"        static int r1325_n;\n"
 + b"        uint32_t h0_ = xenolift_mem_read32(0x800C4A6Cu);\n"
 + b"        uint32_t h1_ = xenolift_mem_read32(0x800C4A70u);\n"
 + b"        int valid_ = (h1_ == 0x84000000u && h0_ >= 0x800C4270u && h0_ <= 0x800CC270u);\n"
 + b"        if (!valid_) {\n"
 + b"            memset(xenolift_mem + 0xC4270u, 0, 0x8000u);\n"
 + b"            xenolift_mem_write32(0x800C4A6Cu, 0x800CC270u);\n"
 + b"            xenolift_mem_write32(0x800C4A70u, 0x84000000u);\n"
 + b"            xenolift_mem_write32(0x800CC268u, 0x800CC270u);\n"
 + b"            xenolift_mem_write32(0x800CC26Cu, 0x80200000u);\n"
 + b"            if (r1325_n < 8) { r1325_n++;\n"
 + b"                r861_out(\"[arenaseed] R1325 dispatcher arena RESEEDED at walk entry: pre head={%08X %08X} -> head={next=%08X flags=%08X} terminator={next=%08X flags=%08X} (#%d)\\n\",\n"
 + b"                        h0_, h1_, xenolift_mem_read32(0x800C4A6Cu), xenolift_mem_read32(0x800C4A70u),\n"
 + b"                        xenolift_mem_read32(0x800CC268u), xenolift_mem_read32(0x800CC26Cu), r1325_n);\n"
 + b"            }\n"
 + b"        } else if (r1325_n < 2) { r1325_n++;\n"
 + b"            r861_out(\"[arenaseed] R1325 walk guard PASS (head holds valid chain {%08X %08X}) - no reseed (#%d)\\n\", h0_, h1_, r1325_n);\n"
 + b"        }\n"
 + b"    }\n")

data = data.replace(a, guard + a, 1)

checks = [("R1325", data.count(b"R1325"), 3),
          ("arenaseed-tag", data.count(b"[arenaseed]"), 2),
          ("walk-key", data.count(b"0x8003223Cu"), 2),
          ("seed-writes", data.count(b"xenolift_mem_write32(0x800CC26Cu"), 2),
          ("orig-walkcam", data.count(b"static int wc_n;"), 1)]
ok = True
for name, got, want in checks:
    print("MARKER %s want=%d got=%d %s" % (name, want, got, "OK" if got == want else "FAIL"))
    if got != want: ok = False
if not ok: sys.exit(1)
open("runtime/runtime.c","wb").write(data)
print("NEW_SHA=%s" % hashlib.sha256(data).hexdigest())
PYEOF
echo "PATCH-APPLIED sha=$(shasum -a 256 "$SRC" | cut -d' ' -f1)"

echo "===PARSE250=== the syntax gate (pre vs post; restore on break)"
clang -fsyntax-only -std=gnu99 "$SRC" > /tmp/parse_c250_pre.txt 2>&1
PRE_RC=$?
clang -fsyntax-only -std=gnu99 "$SRC" > /tmp/parse_c250_post.txt 2>&1
POST_RC=$?
echo "PARSE pre_rc=$PRE_RC post_rc=$POST_RC"
head -4 /tmp/parse_c250_post.txt
if [ "$PRE_RC" -eq 0 ] && [ "$POST_RC" -ne 0 ]; then
  cp -p "$P/runtime.c.pre" "$SRC"; echo "PARSE-BREAK - baseline RESTORED, nothing run"; exit 1
fi
echo "PARSE OK"

echo "===RUN250=== the 150s receipt run"
RUN_BUDGET_S=150 ./run.sh > /tmp/run_full_c250.txt 2>&1
echo "RUNSH_RC=$?"
head -4 /tmp/run_full_c250.txt
if [ -s run.log ]; then cp -p run.log "$P/run.log.post"; echo "RUNLOG_POST sha=$(shasum -a 256 "$P/run.log.post" | cut -d" " -f1) size=$(wc -c < "$P/run.log.post" | tr -d ' ')"; fi

echo "===GUARD250=== the R1325 guard receipts (did it fire? PASS or RESEED?)"
grep -n "arenaseed\]" run.log 2>/dev/null | head -10

echo "===WALK250=== the dispatcher walk receipts (post-guard head words)"
grep -n "walkcam\] R1238 ReleaseAllHeapBlocks a0=0x800C4A6C" run.log 2>/dev/null | head -6

echo "===ABRT250=== the trap + abort census"
echo "traps=$(grep -c "NULL-trap #" run.log 2>/dev/null) abort131=$(grep -c "code=131" run.log 2>/dev/null) abort130=$(grep -c "code=130" run.log 2>/dev/null)"
awk -F"latch " "/NULL-trap #/{print \$2}" run.log 2>/dev/null | sort | uniq -c | head -4

echo "===STATE250=== the state census"
echo "bootmain=$(grep -c bootmain run.log 2>/dev/null)"
grep -n "active state" run.log 2>/dev/null | head -6
grep -n "STATE-1 CB ENTER" run.log 2>/dev/null | head -4

echo "===SCREEN250=== the scene census (past the previous SIGSEGV?)"
grep -n "nonblank" run.log 2>/dev/null | tail -4
grep -n "gpufin" run.log 2>/dev/null | tail -2
grep -n "rungasp" run.log 2>/dev/null | tail -1

echo "===C250DONE=== arena guard cycle complete - verdict from these receipts; REVERT = restore $P/runtime.c.pre"
