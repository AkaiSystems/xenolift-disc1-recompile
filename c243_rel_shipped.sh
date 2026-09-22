#!/bin/bash
# c243_seq112_release.sh (v2 of c242) - THE R1322 STATE-1 RE-AIM ACK.
# v2 CORRECTION (parse-gate caught it, baseline restored, nothing ran):
# the c242 insert appended the tail '))) {' but the R614 chain original
# closing already included the arm own close - one EXTRA ')' = parse
# break at line 2681. v2 tail is ')) {'. The arm content is UNCHANGED
# and marker-verified. (c242 v1 of
# receipted term-class). THE c241 receipts: the state-1 era blocks at
# schdd seq 112 (cmd=02 fe1c=0 FDF8=0 FDFC=0 seek=108995 FE04=108989
# resp=0/3) - the R628 concluded-wait arm declines by EXACTLY ONE
# TERM (FE04==seek; the PA restamped FE04 to the next entry LBA while
# the drive sits armed at 108995 with the staged sector), every other
# arm demands the read-in-flight shape (fe1c 1|2 FDF8!=0) or the
# system-area shape (seek==0). The state-1 CB is RUNNING, the f15
# request was stamped, the drive ARMED - but READ ISSUED file#15 never
# fires because the positioning ack never releases. R1322 admits the
# RECEIPTED re-aim posture through the SAME shared body (restore_pend,
# sched retired at L2378 = exactly-once, INT3 + flag 578A6, NO R613
# event). PASS = seq-112-class CLEAR + WIN receipts, READ ISSUED
# file#15, the f15 load walking (FDF8 92180 -> 0), scene content beyond
# the two-word fills. REVERT on parse-break or no-forward-progress.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C242-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
R="runtime/runtime.c"
EXPECT="846085f908bb039278c9f852c44a3a001a961dfbebab5ad702dccb7dd808ecc7"
if [ ! -s "$R" ]; then echo "C242-FAILED: runtime/runtime.c missing"; exit 1; fi
SS=$(shasum -a 256 "$R" | cut -d" " -f1)
echo "SRC_SHA_BEFORE=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the c238 R1321 tree 846085f9 - nothing patched"; exit 0; fi
echo "BASELINE_VERIFIED"
P="patch_c242_$(date +%Y%m%d_%H%M%S)"
if ! (mkdir -p "$P" && cp -p "$R" "$P/runtime.c.pre"); then echo "C242-FAILED: preserve failed"; exit 1; fi
echo "PRESERVED: $P/runtime.c.pre sha=$SS"

echo "===PATCH242=== the R1322 arm insert (python, binary-safe, FAIL EXPLICIT)"
python3 - <<'PYEOF' || { echo "PATCH-FAILED - nothing written, no run"; exit 1; }
import hashlib, sys
data = open("runtime/runtime.c","rb").read()
if b"R1322" in data:
    print("IDEMPOTENT-SKIP: R1322 already present - no edit made"); sys.exit(0)

# THE ANCHOR: the tail of the R1308 system-area arm - the last arm of
# the R614-hoisted OR-chain (the dump-verified closing shape).
a = b"&& xenolift_mem_read32(0x8004FE04u) < 150u))) {\n"
n = data.count(a)
print("R1322 anchor count=%d (must be 1)" % n)
if n != 1: sys.exit(1)

# THE ARM: the receipted re-aim concluded-wait posture, delivered
# through the existing shared body.
arm = (b"            /* R1322 (c242, the seq-112 state-1 re-aim ack): the c239/c241\n"
 + b"             * receipts name the state-1 file#15 chain missing transition -\n"
 + b"             * the state-1 CB entered, the f15 request stamped (FE04=108995\n"
 + b"             * FDF8=92180 F0C=15), the drive ARMED (act=1 seek=108995\n"
 + b"             * data=2060/0), yet READ ISSUED file#15 never fires and\n"
 + b"             * schdd seq 112 BLOCKS x4+ on the receipted posture: cmd=02\n"
 + b"             * fe1c=0 FDF8=0 FDFC=0 seek=108995 FE04=108989 resp=0/3 -\n"
 + b"             * the PA restamped FE04 to the NEXT entry LBA while the\n"
 + b"             * drive sits armed at seek (the R628 arm declines by exactly\n"
 + b"             * one term, FE04==seek; every other arm demands the\n"
 + b"             * read-in-flight shape fe1c 1|2 FDF8!=0 or the system-area\n"
 + b"             * shape seek==0). THIS arm admits the RECEIPTED re-aim\n"
 + b"             * posture: Setloc + fe1c=0 + FDF8=0 + both cells valid\n"
 + b"             * file-band LBAs but unequal + the drive armed - delivered\n"
 + b"             * through the SAME shared body (restore_pend re-primes the\n"
 + b"             * command OWN envelope, sched retired at L2378 =\n"
 + b"             * exactly-once per seq, INT3 + flag 578A6, NO R613 event -\n"
 + b"             * no seek-complete forgery). The data phase is untouched:\n"
 + b"             * the drive serves the next request sectors through its own\n"
 + b"             * machinery once the game issues them. REVERT: if the game\n"
 + b"             * stays parked (no READ ISSUED file#15, no new SETs) after\n"
 + b"             * ack deliveries, revert next cycle. */\n"
 + b"            || (cd_last_cmd == 0x02u\n"
 + b"                && xenolift_mem_read32(0x8004FE1Cu) == 0u\n"
 + b"                && xenolift_mem_read32(0x8004FDF8u) == 0u\n"
 + b"                && cd_seek_lba >= 108900u && cd_seek_lba < 109200u\n"
 + b"                && xenolift_mem_read32(0x8004FE04u) >= 108900u\n"
 + b"                && xenolift_mem_read32(0x8004FE04u) < 109200u\n"
 + b"                && xenolift_mem_read32(0x8004FE04u) != cd_seek_lba\n"
 + b"                && cd_read_active)\n")
data = data.replace(a,
    b"&& xenolift_mem_read32(0x8004FE04u) < 150u)\n" + arm + b"            )) {\n", 1)

tail_pat = b"xenolift_mem_read32(0x8004FE04u) < 150u"
checks = [("R1322", data.count(b"R1322"), 1),
          ("seq112-arm-cmd02", data.count(b"|| (cd_last_cmd == 0x02u\n"), 1),
          ("arm-band-term", data.count(b">= 108900u && cd_seek_lba < 109200u"), 1),
          ("r1308-arm-intact", data.count(tail_pat), 1),
          ("chain-close", data.count(b"            )) {"), 1)]
ok = True
for name, got, want in checks:
    print("MARKER %s want=%d got=%d %s" % (name, want, got, "OK" if got == want else "FAIL"))
    if got != want: ok = False
if not ok: sys.exit(1)
open("runtime/runtime.c","wb").write(data)
print("NEW_SHA=%s" % hashlib.sha256(data).hexdigest())
PYEOF
echo "PATCH-APPLIED sha=$(shasum -a 256 "$R" | cut -d" " -f1)"

echo "===PARSE242=== the parse gate (pre vs post; restore on break)"
CC_BIN=""
for c in cc clang gcc; do command -v "$c" >/dev/null 2>&1 && { CC_BIN="$c"; break; }; done
PRE_RC=99; POST_RC=99
if [ -n "$CC_BIN" ]; then
  "$CC_BIN" -fsyntax-only -std=gnu99 -I runtime "$P/runtime.c.pre" >/dev/null 2>/tmp/c242_pre.txt; PRE_RC=$?
  "$CC_BIN" -fsyntax-only -std=gnu99 -I runtime "$R" >/dev/null 2>/tmp/c242_post.txt; POST_RC=$?
  echo "PARSE pre_rc=$PRE_RC post_rc=$POST_RC"
  head -4 /tmp/c242_post.txt
fi
if [ "$PRE_RC" -eq 0 ] && [ "$POST_RC" -ne 0 ]; then
  cp -p "$P/runtime.c.pre" "$R"; echo "PARSE-BREAK - baseline RESTORED, nothing run"; exit 1
fi

echo "===RUN242=== the 150s receipt run"
RUN_BUDGET_S=150 ./run.sh > /tmp/run_full_c242.txt 2>&1
echo "RUNSH_RC=$?"
head -4 /tmp/run_full_c242.txt
if [ -s run.log ]; then cp -p run.log "$P/run.log.post"; echo "RUNLOG_POST sha=$(shasum -a 256 "$P/run.log.post" | cut -d" " -f1) size=$(wc -c < "$P/run.log.post" | tr -d " ")"; fi

echo "===WIN242=== the seq-112 delivery receipts (CLEAR + WIN + the release print)"
grep -n "CLEAR site L2378" run.log 2>/dev/null | head -4
grep -n "delivery WIN" run.log 2>/dev/null | head -6
grep -n "R612 endgame release" run.log 2>/dev/null | head -6
echo "--- remaining blocks (any):"
grep -c "delivery decision BLOCKED" run.log 2>/dev/null

echo "===F15LOAD242=== the file#15 chain (READ ISSUED + the FDF8 walk)"
grep -n "READ ISSUED" run.log 2>/dev/null | head -8
grep -n "file#15\|F0C=15 " run.log 2>/dev/null | head -6
grep -n "fetchcam" run.log 2>/dev/null | grep "108995\|108996\|108997" | head -8
grep -o "FDF8=[0-9A-F]*" run.log 2>/dev/null | sort | uniq -c | sort -rn | head -6

echo "===STATE242=== the state-1 census"
grep -c "active state 1" run.log 2>/dev/null
grep -n "STATE-1 CB ENTER" run.log 2>/dev/null | head -4
echo "menuchain=$(grep -c menuchain run.log 2>/dev/null) cur1=$(grep -c "cur=0x00000001" run.log 2>/dev/null) mtrans=$(grep -c mtrans run.log 2>/dev/null)"

echo "===CENSUS242=== era map + health"
echo "bootmain=$(grep -c bootmain run.log 2>/dev/null) abort131=$(grep -c "code=131" run.log 2>/dev/null) nulltraps=$(grep -c "NULL-trap #" run.log 2>/dev/null) lzrwatch=$(grep -c lzrwatch run.log 2>/dev/null)"
grep -n "rungasp" run.log 2>/dev/null | tail -1

echo "===SCREEN242=== the scene question (beyond two words?)"
grep -n "\[screen\]" run.log 2>/dev/null | tail -3
python3 - <<'PYEOF'
import os
p = "vram_live.bin"
if os.path.exists(p):
    d = open(p, "rb").read()
    if len(d) >= 2048:
        words = [d[i] | (d[i+1] << 8) for i in range(0, 2048, 2)]
        uniq = {}
        for w in words:
            uniq[w] = uniq.get(w, 0) + 1
        print("first-1KB word census (value:count):", sorted(uniq.items(), key=lambda kv: -kv[1])[:6])
        print("distinct words:", len(uniq))
else:
    print("no vram_live.bin present")
PYEOF

echo "===C242DONE=== seq-112 release cycle complete - verdict from these receipts; REVERT = restore $P/runtime.c.pre"
