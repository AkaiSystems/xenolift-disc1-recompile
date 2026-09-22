#!/bin/bash
# c226_mount_repoint.sh - THE SEED-TERMINATOR RE-POINT (R1318) + the receipt run.
# The c224/c225 decoded fork: the state-1 (menu) mount's 125304-byte alloc
# walk CONCLUDES at the R1275-seeded state-6 terminator (flags carry the
# free-sentinel CONCLUDE class 0x00200000; next self-points the region
# END). The conclude serve is downward (node - want): the 16212 carve
# landed in-region (hand 8007B4FC = terminator-16212, receipted EXACT),
# the 125304 carve lands below the heap floor -> protectively refused ->
# hand v0=0 -> the game aborts the mount -> res=0 -> poison unpack ->
# abort 130 -> clean exit at 36s. The TRUE heap-top sentinel (801FBFF8)
# served every successful big carve this run, and the c190 trajectory
# receipted the member-14 install at 801DD680 = exactly the true-sentinel
# downward serve for want=125304. FIX (one site, OUR OWN seed, fires only
# at st==1): next=0x801FC000 (the walk reads the next node header at
# next-8 = 801FBFF8), flags=0x84000000 (free-list class, NOT conclude
# class) - the walk passes through and concludes at the true sentinel.
# State-6 installs keep the original seed. Gates: baseline sha, anchor
# count==1, markers exact, idempotent, parse pre-vs-post (restore on
# break), then the 60s receipt run with the member-14 dossier.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C226-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
R="runtime/runtime.c"
EXPECT="cb31fa9ae0c9fd8eafa224bde313471b552fa5fe45e1db6919cebb77fbbd7967"
if [ ! -s "$R" ]; then echo "C226-FAILED: runtime/runtime.c missing"; exit 1; fi
SS=$(shasum -a 256 "$R" | cut -d" " -f1)
echo "SRC_SHA_BEFORE=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the cb31fa9a baseline - nothing patched"; exit 0; fi
echo "BASELINE_VERIFIED"
P="patch_c226_$(date +%Y%m%d_%H%M%S)"
if ! (mkdir -p "$P" && cp -p "$R" "$P/runtime.c.pre"); then echo "C226-FAILED: preserve failed"; exit 1; fi
echo "PRESERVED: $P/runtime.c.pre sha=$SS"

echo "===PATCH226=== the R1318 re-point (python, binary-safe, FAIL EXPLICIT)"
python3 - <<'PYEOF' || { echo "PATCH-FAILED - nothing written, no run"; exit 1; }
import hashlib, sys
data = open("runtime/runtime.c","rb").read()
if b"R1318" in data:
    print("IDEMPOTENT-SKIP: R1318 already present - no edit made"); sys.exit(0)
a = (b"            if (st >= 1u && st <= 6u) {\n"
     b"                memcpy(xenolift_mem + 0x28084u, &base, 4);\n"
     b"                r861_out(\"[mount] unpack-dest cell set to 0x%08X for state %u\\n\", base, st);\n"
     b"            }\n")
n = data.count(a)
print("ANCHOR count=%d (must be 1)" % n)
if n != 1: sys.exit(1)
r = a + (
b"            /* R1318 (c226): THE SEED-TERMINATOR RE-POINT. The c224 receipts\n"
b"             * decoded the state-1 (menu) mount fork: the 125304-byte\n"
b"             * alloc's walk concludes at the R1275-SEEDED state-6\n"
b"             * terminator (flags carry the free-sentinel conclude class,\n"
b"             * next self-points the region END) and its downward serve\n"
b"             * lands below the heap floor - protectively refused, hand\n"
b"             * v0=0 - the game aborts the mount, res=0, poison unpack,\n"
b"             * abort 130. The TRUE heap-top sentinel (801FBFF8) served\n"
b"             * every successful big carve this run and receipted the\n"
b"             * c190-era member-14 install at 801DD680. At the state-1\n"
b"             * mount ONLY, re-point OUR OWN seed terminator to the true\n"
b"             * sentinel chain convention: next=0x801FC000 (the walk\n"
b"             * reads the next node header at next-8 = 801FBFF8),\n"
b"             * flags=0x84000000 (free-list class, NOT the conclude\n"
b"             * class) - the walk passes through and concludes at the\n"
b"             * true sentinel. State-6 installs keep the original seed\n"
b"             * (fires only at st==1). Worst case unchanged: a\n"
b"             * floor-refused serve is protective, never corrupting. */\n"
b"            if (st == 1u) {\n"
b"                xenolift_mem_write32(0x8007F450u, 0x801FC000u);\n"
b"                xenolift_mem_write32(0x8007F454u, 0x84000000u);\n"
b"                r861_out(\"[mountrep] R1318 state-6 seed terminator re-pointed: next=0x801FC000 flags=0x84000000 (chains to the true heap-top sentinel 801FBFF8; PASS = the 125304 hand returns a real block)\\n\");\n"
b"            }\n")
data = data.replace(a, r, 1)
ok = (data.count(b"R1318") == 2 and data.count(b"mountrep") == 1
      and data.count(a) == 1 and data.count(b"[mount] unpack-dest cell set") == 1)
for name, got, want in [("R1318", data.count(b"R1318"), 2),
                        ("mountrep", data.count(b"mountrep"), 1),
                        ("anchor", data.count(a), 1),
                        ("unpackdest-print", data.count(b"[mount] unpack-dest cell set"), 1)]:
    print("MARKER %s want=%d got=%d %s" % (name, want, got, "OK" if got == want else "FAIL"))
if not ok: sys.exit(1)
open("runtime/runtime.c","wb").write(data)
print("NEW_SHA=%s" % hashlib.sha256(data).hexdigest())
PYEOF
echo "PATCH-APPLIED sha=$(shasum -a 256 "$R" | cut -d" " -f1)"

echo "===PARSE226=== the parse gate (pre vs post; restore on break)"
CC_BIN=""
for c in cc clang gcc; do command -v "$c" >/dev/null 2>&1 && { CC_BIN="$c"; break; }; done
PRE_RC=99; POST_RC=99
if [ -n "$CC_BIN" ]; then
  "$CC_BIN" -fsyntax-only -std=gnu99 -I runtime "$P/runtime.c.pre" >/dev/null 2>/tmp/c226_pre.txt; PRE_RC=$?
  "$CC_BIN" -fsyntax-only -std=gnu99 -I runtime "$R" >/dev/null 2>/tmp/c226_post.txt; POST_RC=$?
  echo "PARSE pre_rc=$PRE_RC post_rc=$POST_RC"
  head -6 /tmp/c226_post.txt
fi
if [ "$PRE_RC" -eq 0 ] && [ "$POST_RC" -ne 0 ]; then
  cp -p "$P/runtime.c.pre" "$R"; echo "PARSE-BREAK - baseline RESTORED, nothing run"; exit 1
fi
[ "$PRE_RC" -ne 0 ] && echo "PARSE-CHECK UNUSABLE (baseline errors too) - deferring to the run.sh build gate"

echo "===RUN226=== the 60s receipt run (the game exits natively at ~36s)"
RUN_BUDGET_S=60 ./run.sh > /tmp/run_full_c226.txt 2>&1
echo "RUNSH_RC=$?"
head -6 /tmp/run_full_c226.txt
tail -4 /tmp/run_full_c226.txt

echo "===MOUNTREP226=== the re-point receipts"
grep -n "mountrep" run.log 2>/dev/null | head -6

echo "===HANDS226=== the 125304 hands (the c226 PASS evidence)"
if [ -s run.log ]; then
  grep -n "\[hand\]" run.log | grep "125304" | head -8
  echo "--- windows around each 125304 hand (6 before, 4 after):"
  for N in $(grep -n "\[hand\]" run.log | grep "125304" | cut -d: -f1 | head -4); do
    echo "--- hand at line $N:"
    awk -v s=$((N-6)) -v e=$((N+4)) 'NR>=s&&NR<=e{printf "%d:%s\n",NR,$0}NR>e{exit}' run.log
  done
  echo "--- all hands (count):"
  grep -c "\[hand\]" run.log
fi

echo "===MEMBER226=== the member-14 fetch chain (first time in this chain if PASS)"
grep -n "member=14\|file#=14\|READ ISSUED" run.log 2>/dev/null | head -16

echo "===ABRT226=== the fault/exit census"
if [ -s run.log ]; then
  echo "abort130=$(grep -c "AbortOnGameFault" run.log) unpackfix=$(grep -c "unpack-fix" run.log) bootmain=$(grep -c "bootmain" run.log)"
  grep -n "rungasp" run.log | tail -2
  grep -n "bldprov" run.log | head -2
fi

echo "===STATE226=== the state census"
if [ -s run.log ]; then
  grep -n "statetbl" run.log | head -4
  grep -o "cur=0x[0-9A-F]*" run.log | sort | uniq -c | sort -rn | head -6
  echo "--- screen witnesses:"
  grep -n "\[screen\]" run.log | tail -4
fi
echo "===C226DONE=== re-point cycle complete - verdict from these receipts; REVERT = restore $P/runtime.c.pre"
