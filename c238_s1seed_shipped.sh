#!/bin/bash
# c238_state1_seed.sh (v2) - THE R1321 STATE-1 HEAP SEED (the proven state-6
# v2 CORRECTION: only the anchor-intact gate changes - it hardcoded
# want=2 for the 59320 tail-read pattern, but the ORIGINAL file already
# has 2 occurrences (the R1275 print + the earlier heap-init camera at
# line ~14070) and the insert correctly adds a 3rd. v2 counts
# dynamically: post must equal pre+1. The patch logic is UNCHANGED and
# was verified correct by all seven other markers in v1.
# cure, mapped cell-for-cell). The c237 dump receipted the template: the
# state-6 restore survives because the restart-step hook (ridx==6) zeroes
# [77458,7F458) and seeds head node {next=END, flags=84000000} +
# terminator {next=END, flags=80200000} - the R1275 cure, PASSED since
# c163. The state-1 fault is the SAME shape at the SAME walk: the
# allocator stamps the head node flags at 800C4A70 (= region+0x800, the
# bankw receipt) but the head node next at 800C4A6C and the terminator
# at 800CC268 are zeros -> next=0 -> cursor=-8 -> the FFFFFFFC/FFF8
# reads -> the 524K+ NULL-trap loop -> R1151 conversion, twice
# identically. R1321 = the identical zero+seed gated ridx==1:
# region [800C4270, 800CC270), head node @800C4A6C {next=800CC270,
# flags=0x84000000}, terminator @800CC268 {next=800CC270,
# flags=0x80200000}, head cell 59320 untouched (game-set).
# PASS = [heapzero1]+[heapseed1] fire, the NULL-trap loop dies, no
# conversion, and the ladder test: statetbl "active state 1", cur=1
# held, state-1 chain receipts (clrh/ChangeGameState) past the walk.
# REVERT on parse-break (restore preserved pre-copy).
set -u
cd "$HOME/Downloads/xenolift" || { echo "C238-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
R="runtime/runtime.c"
EXPECT="6c952edb41ab0ab965ffdcccf912a935e02549d646b4a6ab0c8184fd13a590d1"
if [ ! -s "$R" ]; then echo "C238-FAILED: runtime/runtime.c missing"; exit 1; fi
SS=$(shasum -a 256 "$R" | cut -d" " -f1)
echo "SRC_SHA_BEFORE=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the c234 tree 6c952edb - nothing patched"; exit 0; fi
echo "BASELINE_VERIFIED"
P="patch_c238_$(date +%Y%m%d_%H%M%S)"
if ! (mkdir -p "$P" && cp -p "$R" "$P/runtime.c.pre"); then echo "C238-FAILED: preserve failed"; exit 1; fi
echo "PRESERVED: $P/runtime.c.pre sha=$SS"

echo "===PATCH238=== the R1321 state-1 seed insert (python, binary-safe, FAIL EXPLICIT)"
python3 - <<'PYEOF' || { echo "PATCH-FAILED - nothing written, no run"; exit 1; }
import hashlib, sys
data = open("runtime/runtime.c","rb").read()
if b"R1321" in data:
    print("IDEMPOTENT-SKIP: R1321 already present - no edit made"); sys.exit(0)

# THE ANCHOR: the R1275 seed block's closing sequence (the heapseed print
# args -> close the seed block -> close the state-6 if -> close the outer
# R1273 block). Byte-exact, must be unique.
a = (b"                            xenolift_mem_read32(0x80059320u));\n"
     b"                }\n"
     b"            }\n"
     b"        }\n")
n = data.count(a)
print("R1321 anchor count=%d (must be 1)" % n)
if n != 1: sys.exit(1)

# THE INSERT: the state-1 seed, same hook, same shape, gated ridx==1.
tail_pat = b"xenolift_mem_read32(0x80059320u));"
pre_cnt = data.count(tail_pat)
print("tail-read pre-count=%d" % pre_cnt)
ins = (b"            if (ridx == 1u) {\n"
 + b"                /* R1321 (c238): THE STATE-1 HEAP SEED - the proven\n"
 + b"                 * state-6 cure mapped cell-for-cell. The c235/c236\n"
 + b"                 * receipts: the state-1 restore walk (MoveHeapAlloc-\n"
 + b"                 * ation 800C4270,0x8000 -> ReleaseAllHeapBlocks) traps\n"
 + b"                 * on the head node next=0 (cursor=-8, reads at\n"
 + b"                 * FFFFFFFC/FFF8, 524K+ NULL-trap loop, R1151\n"
 + b"                 * conversion, twice identically) - the allocator had\n"
 + b"                 * already stamped the head node flags 84000000 at\n"
 + b"                 * 800C4A70 (the bankw receipt, region+0x800), only\n"
 + b"                 * the next pointer and terminator are missing. THE\n"
 + b"                 * CURE, identical to the state-6 sibling that PASSED\n"
 + b"                 * (TRAP=0 ABRT=0 since c163): zero the region, seed\n"
 + b"                 * head node @800C4A6C {next=END, flags=0x84000000} +\n"
 + b"                 * terminator @800CC268 {next=END, flags=0x80200000},\n"
 + b"                 * head cell 59320 untouched (game-set). PASS = the\n"
 + b"                 * walk completes, no NULL-trap loop, state 1\n"
 + b"                 * engages. */\n"
 + b"                uint32_t pre1a = xenolift_mem_read32(0x800C4270u);\n"
 + b"                uint32_t pre1b = xenolift_mem_read32(0x800C4274u);\n"
 + b"                memset(xenolift_mem + 0xC4270u, 0, 0x8000u);\n"
 + b"                r861_out(\"[heapzero1] R1321 state-1 heap region 0x800C4270..0x800CC270 ZEROED before the install walk (pre w0=%08X w1=%08X, 32768 bytes)\\n\", pre1a, pre1b);\n"
 + b"                xenolift_mem_write32(0x800C4A6Cu, 0x800CC270u);\n"
 + b"                xenolift_mem_write32(0x800C4A70u, 0x84000000u);\n"
 + b"                xenolift_mem_write32(0x800CC268u, 0x800CC270u);\n"
 + b"                xenolift_mem_write32(0x800CC26Cu, 0x80200000u);\n"
 + b"                r861_out(\"[heapseed1] R1321 state-1 heap SEEDED with the same semantics: head@800C4A6C={next=%08X flags=%08X} terminator@800CC268={next=%08X flags=%08X} head cell 59320=%08X\\n\",\n"
 + b"                        xenolift_mem_read32(0x800C4A6Cu), xenolift_mem_read32(0x800C4A70u),\n"
 + b"                        xenolift_mem_read32(0x800CC268u), xenolift_mem_read32(0x800CC26Cu),\n"
 + b"                        xenolift_mem_read32(0x80059320u));\n"
 + b"            }\n")
data = data.replace(a,
    b"                            xenolift_mem_read32(0x80059320u));\n"
    b"                }\n"
    b"            }\n" + ins + b"        }\n", 1)

checks = [("R1321", data.count(b"R1321"), 3),
          ("ridx-eq-1", data.count(b"if (ridx == 1u) {"), 1),
          ("ridx-eq-6-intact", data.count(b"if (ridx == 6u) {"), 1),
          ("heapzero1", data.count(b"heapzero1"), 1),
          ("heapseed1", data.count(b"heapseed1"), 1),
          ("headnode-cell", data.count(b"0x800C4A6Cu"), 2),
          ("anchor-intact", data.count(tail_pat), pre_cnt + 1)]
ok = True
for name, got, want in checks:
    print("MARKER %s want=%d got=%d %s" % (name, want, got, "OK" if got == want else "FAIL"))
    if got != want: ok = False
if not ok: sys.exit(1)
open("runtime/runtime.c","wb").write(data)
print("NEW_SHA=%s" % hashlib.sha256(data).hexdigest())
PYEOF
echo "PATCH-APPLIED sha=$(shasum -a 256 "$R" | cut -d" " -f1)"

echo "===PARSE238=== the parse gate (pre vs post; restore on break)"
CC_BIN=""
for c in cc clang gcc; do command -v "$c" >/dev/null 2>&1 && { CC_BIN="$c"; break; }; done
PRE_RC=99; POST_RC=99
if [ -n "$CC_BIN" ]; then
  "$CC_BIN" -fsyntax-only -std=gnu99 -I runtime "$P/runtime.c.pre" >/dev/null 2>/tmp/c238_pre.txt; PRE_RC=$?
  "$CC_BIN" -fsyntax-only -std=gnu99 -I runtime "$R" >/dev/null 2>/tmp/c238_post.txt; POST_RC=$?
  echo "PARSE pre_rc=$PRE_RC post_rc=$POST_RC"
  head -4 /tmp/c238_post.txt
fi
if [ "$PRE_RC" -eq 0 ] && [ "$POST_RC" -ne 0 ]; then
  cp -p "$P/runtime.c.pre" "$R"; echo "PARSE-BREAK - baseline RESTORED, nothing run"; exit 1
fi

echo "===RUN238=== the 150s receipt run"
RUN_BUDGET_S=150 ./run.sh > /tmp/run_full_c238.txt 2>&1
echo "RUNSH_RC=$?"
head -4 /tmp/run_full_c238.txt
if [ -s run.log ]; then cp -p run.log "$P/run.log.post"; echo "RUNLOG_POST sha=$(shasum -a 256 "$P/run.log.post" | cut -d" " -f1) size=$(wc -c < "$P/run.log.post" | tr -d " ")"; fi

echo "===SEED238=== the R1321 receipts (THE FIRE LINES)"
grep -n "heapzero1\]\|heapseed1\]" run.log 2>/dev/null | head -6
echo "seed_fires=$(grep -c "heapseed1\]" run.log 2>/dev/null)"

echo "===TRAP238=== the trap census (the loop must die)"
echo "nulltraps=$(grep -c "NULL-trap #" run.log 2>/dev/null) guard_reads=$(grep -c "lzss-guard-r\] suppressed read @0xFFFF" run.log 2>/dev/null) lzrwatch=$(grep -c lzrwatch run.log 2>/dev/null)"
grep -n "NULL-trap #1 \|NULL-trap #2 " run.log 2>/dev/null | head -4
grep -n "lzrwatch" run.log 2>/dev/null | head -3

echo "===WALK238=== did the state-1 walk complete (the chain past MoveHeapAllocation)"
grep -n "clrh\]\|ChangeGameState" run.log 2>/dev/null | grep -v "bandhist" | head -8
grep -n "walkcam\] R1238" run.log 2>/dev/null | grep "800C4270" | head -4

echo "===STATE238=== the ladder test (state 1 ENGAGES?)"
grep -n "active state 1" run.log 2>/dev/null | head -6
echo "state1_samples=$(grep -c "active state 1" run.log 2>/dev/null)"
grep -n "active state" run.log 2>/dev/null | head -10
echo "cur1=$(grep -c "cur=0x00000001" run.log 2>/dev/null) coordw=$(grep -c coordw run.log 2>/dev/null) menuchain=$(grep -c menuchain run.log 2>/dev/null)"

echo "===CENSUS238=== era map + exits"
echo "bootmain=$(grep -c bootmain run.log 2>/dev/null) abort131=$(grep -c "code=131" run.log 2>/dev/null)"
grep -n "restart\] R709" run.log 2>/dev/null | head -8
grep -n "rungasp" run.log 2>/dev/null | tail -2

echo "===SCREEN238=== the visual witnesses"
grep -n "\[screen\]" run.log 2>/dev/null | tail -4
if [ -s vram_live.bin ]; then
  python3 - <<'PYEOF'
data = open("vram_live.bin","rb").read()
W,H = 256,240
def px(x,y):
    off=(y*1024+x)*2
    if off+1 >= len(data): return 0
    w = data[off] | (data[off+1]<<8)
    r=(w&0x1F)<<3; g=((w>>5)&0x1F)<<3; b=((w>>10)&0x1F)<<3
    return (r*299+g*587+b*114)//1000
chars=" .:-=+*#%@"
print("--- luminance grid 32x15 (OBSERVED only - not a scene claim):")
for gy in range(0,H,16):
    row=""
    for gx in range(0,W,8):
        row += chars[min(9, px(gx,gy)*10//256)]
    print(row)
PYEOF
fi
echo "===PAD238==="
echo "padstart=$(grep -c padstart run.log 2>/dev/null) padrd=$(grep -c padrd run.log 2>/dev/null)"
echo "===C238DONE=== state-1 seed cycle complete - verdict from these receipts; REVERT = restore $P/runtime.c.pre"
