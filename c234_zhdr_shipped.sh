#!/bin/bash
# c234_zero_header_exit.sh (v2) - THE R1319 REVERT + R1320 ZERO-HEADER EXIT.
# v2 CORRECTION: the ONLY change is one comment line in the R1320 insert -
# v1's comment contained the literal 'R1319' inside the R1320 text, so the
# R1319-gone==0 gate counted my own comment and refused (nothing written,
# tree 3196afd3 intact - the fail-explicit design working as intended).
# The c233 receipts overturned the guest-native hypothesis: the widened
# branch FIRED (fldfp #1) and the game's own decoder wrote real module
# bytes - then ran away on the 125304-byte input (reads past RAM, 1M+ ops,
# R1151 conversion, era wiped). The "c257-proven oracle" claim was an
# over-read of the R691 comment (a plan, never a receipted success) -
# RETRACTED. The receipted facts: (1) the HLE decode of file-14 is
# correct and complete (c227/c228); (2) the guest core is faithful on
# small streams (natural exits after every small HLE); (3) a ZERO
# compressed header makes the core exit CLEANLY at its first group check
# (the 10984 receipt: r5=r15=r14=dst). THE FIX: revert R1319, and after
# a successful HLE decode of the file-14 shape, zero the compressed
# source's header word - the redundant guest pass then reads word0=0,
# computes exit=dst, exits at its first check. The compressed buffer is
# dead scratch after the install (each era re-reads from disc, READ
# ISSUED receipted every era). PASS = [lzss-x] EXIT r5=r15=r14=8006FAF0,
# zero lzrwatch, cur=1 held, state-1 entry. REVERT on parse-break.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C234-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
R="runtime/runtime.c"
EXPECT="3196afd3620848ed4de8c6660c66b99e2e9f0dd8e8edce4d003b466164bff836"
if [ ! -s "$R" ]; then echo "C234-FAILED: runtime/runtime.c missing"; exit 1; fi
SS=$(shasum -a 256 "$R" | cut -d" " -f1)
echo "SRC_SHA_BEFORE=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the c231 tree 3196afd3 - nothing patched"; exit 0; fi
echo "BASELINE_VERIFIED"
P="patch_c234_$(date +%Y%m%d_%H%M%S)"
if ! (mkdir -p "$P" && cp -p "$R" "$P/runtime.c.pre"); then echo "C234-FAILED: preserve failed"; exit 1; fi
echo "PRESERVED: $P/runtime.c.pre sha=$SS"

echo "===PATCH234=== the R1319 revert + R1320 insert (python, binary-safe, FAIL EXPLICIT)"
python3 - <<'PYEOF' || { echo "PATCH-FAILED - nothing written, no run"; exit 1; }
import hashlib, sys
data = open("runtime/runtime.c","rb").read()
if b"R1320" in data:
    print("IDEMPOTENT-SKIP: R1320 already present - no edit made"); sys.exit(0)

# --- 1. THE R1319 REVERT: replace the inserted comment block + widened
#        condition with the original single line (byte-exact block assert).
start = data.find(b"                /* R1319 (c231): WIDEN THE GUEST-NATIVE BRANCH to the\n")
if start < 0: print("REVERT-FAILED: R1319 block not found"); sys.exit(1)
cond = b"                if (r[4] == 0x801D9724u || (r[5] == 0x8006FAF0u && w0 == 260862u)) {\n"
ci = data.find(cond, start)
if ci < 0: print("REVERT-FAILED: widened condition not found after block"); sys.exit(1)
end = ci + len(cond)
block = data[start:end]
n_r1319 = block.count(b"R1319")
print("R1319 block found: %d bytes, R1319 count=%d" % (len(block), n_r1319))
if n_r1319 != 1: print("REVERT-FAILED: unexpected block shape"); sys.exit(1)
data = data[:start] + b"                if (r[4] == 0x801D9724u) {\n" + data[end:]

# --- 2. THE R1320 INSERT: after the lzss-hle success print's closing
#        arg line, inside the prod==w0 gate. The movie-module receipt
#        (exit r5=r15=r14=dst on word0=0) proves the core exits cleanly
#        at its first group check when the compressed header is zero.
a = b"                                r[4], r[5], w0, _f0, _f1);\n"
n = data.count(a)
print("R1320 anchor count=%d (must be 1)" % n)
if n != 1: sys.exit(1)
ins = (a
 + b"        /* R1320 (c234): THE FILE-14 GUEST-PASS EXIT. The c233 receipts:\n"
 + b"         * the guest-native decode RUNS AWAY on this stream (reads past\n"
 + b"         * RAM, R1151 conversion) - the c231 guest-native widen reverted;\n"
 + b"         * the R691 oracle was\n"
 + b"         * a plan, never receipted. The HLE decode is the receipted\n"
 + b"         * oracle (c227/c228: 260862 expanded, coordinator written).\n"
 + b"         * The movie-module receipt (exit r5=r15=r14=dst on a zero\n"
 + b"         * word0) proves the core exits CLEANLY at its first group\n"
 + b"         * check when the compressed header is zero. Zero the source\n"
 + b"         * header AFTER the successful HLE decode: the redundant\n"
 + b"         * guest pass computes exit=dst+0 and exits at its first\n"
 + b"         * check - the same receipted shape. The compressed buffer is\n"
 + b"         * dead scratch after the install (each era re-reads from\n"
 + b"         * disc, READ ISSUED receipted every era). PASS = [lzss-x]\n"
 + b"         * EXIT r5=r15=r14=8006FAF0, zero lzrwatch, cur=1 held. */\n"
 + b"        if (r[5] == 0x8006FAF0u && w0 == 260862u) {\n"
 + b"            xenolift_mem_write32(r[4], 0u);\n"
 + b"        }\n")
data = data.replace(a, ins, 1)

checks = [("R1320", data.count(b"R1320"), 1),
          ("R1319-gone", data.count(b"R1319"), 0),
          ("r1320-gate", data.count(b"if (r[5] == 0x8006FAF0u && w0 == 260862u) {"), 1),
          ("orig-cond-restored", data.count(b"                if (r[4] == 0x801D9724u) {"), 1),
          ("widen-gone", data.count(b"r[4] == 0x801D9724u || (r[5] == 0x8006FAF0u && w0 == 260862u)"), 0),
          ("fldfp-print", data.count(b"[fldfp] R691"), 2)]
ok = True
for name, got, want in checks:
    print("MARKER %s want=%d got=%d %s" % (name, want, got, "OK" if got == want else "FAIL"))
    if got != want: ok = False
if not ok: sys.exit(1)
open("runtime/runtime.c","wb").write(data)
print("NEW_SHA=%s" % hashlib.sha256(data).hexdigest())
PYEOF
echo "PATCH-APPLIED sha=$(shasum -a 256 "$R" | cut -d" " -f1)"

echo "===PARSE234=== the parse gate (pre vs post; restore on break)"
CC_BIN=""
for c in cc clang gcc; do command -v "$c" >/dev/null 2>&1 && { CC_BIN="$c"; break; }; done
PRE_RC=99; POST_RC=99
if [ -n "$CC_BIN" ]; then
  "$CC_BIN" -fsyntax-only -std=gnu99 -I runtime "$P/runtime.c.pre" >/dev/null 2>/tmp/c234_pre.txt; PRE_RC=$?
  "$CC_BIN" -fsyntax-only -std=gnu99 -I runtime "$R" >/dev/null 2>/tmp/c234_post.txt; POST_RC=$?
  echo "PARSE pre_rc=$PRE_RC post_rc=$POST_RC"
  head -4 /tmp/c234_post.txt
fi
if [ "$PRE_RC" -eq 0 ] && [ "$POST_RC" -ne 0 ]; then
  cp -p "$P/runtime.c.pre" "$R"; echo "PARSE-BREAK - baseline RESTORED, nothing run"; exit 1
fi

echo "===RUN234=== the 150s receipt run"
RUN_BUDGET_S=150 ./run.sh > /tmp/run_full_c234.txt 2>&1
echo "RUNSH_RC=$?"
head -4 /tmp/run_full_c234.txt
if [ -s run.log ]; then cp -p run.log "$P/run.log.post"; echo "RUNLOG_POST sha=$(shasum -a 256 "$P/run.log.post" | cut -d" " -f1) size=$(wc -c < "$P/run.log.post" | tr -d " ")"; fi

echo "===HLE234=== the file-14 HLE + R1320 exit receipts (THE PASS LINE)"
grep -n "lzss-hle\] src=0x801DD680" run.log 2>/dev/null | head -4
grep -n "lzss-x\] EXIT" run.log 2>/dev/null | grep "8006FAF0\|800AF5EE" | head -6
echo "lzrwatch=$(grep -c lzrwatch run.log 2>/dev/null) runaway=$(grep -c lzss-runaway run.log 2>/dev/null) fldfp=$(grep -c fldfp run.log 2>/dev/null)"

echo "===STATE234=== the state census (cur=1 held = PASS)"
grep -n "active state" run.log 2>/dev/null | head -8
echo "cur1=$(grep -c "cur=0x00000001" run.log 2>/dev/null) coordw=$(grep -c coordw run.log 2>/dev/null)"
grep -n "menuchain\|KernelMenu" run.log 2>/dev/null | head -6
grep -n "80077E88" run.log 2>/dev/null | grep -v "coordw\|narrowblast\|statetbl\|bandhist" | head -6

echo "===CENSUS234=== the fault/exit census"
echo "bootmain=$(grep -c bootmain run.log 2>/dev/null) abort130=$(grep -c AbortOnGameFault run.log 2>/dev/null) unpackfix=$(grep -c unpack-fix run.log 2>/dev/null)"
grep -n "rungasp" run.log 2>/dev/null | tail -2
grep -n "bldprov" /tmp/run_full_c234.txt 2>/dev/null | head -1

echo "===SCREEN234=== the visual witnesses + last-frame render"
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
echo "===PAD234==="
echo "padstart=$(grep -c padstart run.log 2>/dev/null) padrd=$(grep -c padrd run.log 2>/dev/null)"
echo "===C234DONE=== zero-header cycle complete - verdict from these receipts; REVERT = restore $P/runtime.c.pre"
