#!/bin/bash
# c231_guest_native.sh (v2) - THE R1319 GUEST-NATIVE WIDEN + the receipt run.
# v2 CORRECTION: the only change vs v1 is the fldfp-print marker expectation
# 1 -> 2 (the TRUE in-tree count: the skip-print + the verification print;
# v1's fail-explicit gate caught the bad expectation and wrote NOTHING -
# the baseline c821d139 is intact, so the v2 patch is byte-identical).
# The c230 receipts decoded the fast boot-retry loop completely: the
# state-1 mount's file-14 expansion (src=801DD680 dst=8006FAF0 w0=260862)
# takes the HLE branch, which decodes CORRECTLY, but the R201 exit trick
# fails for this stream - the one-shot zero-read returns 0s, the guest
# loop treats them as data, writes on, reads past the RAM end, R1151
# converts to crash-kit recovery at 1M reads, and the recovery boot
# re-entry WIPES the installed module. The R691 branch (in-tree) already
# runs the game's OWN decoder natively for the staged file-14 stream at
# 0x801D9724 - c257-proven (R690 checksum 0x0DDD880D + coordinator-edge
# words verified at the next walker entry). THE FIX: widen that branch to
# the mount's file-14 stream by its exact shape (dst=0x8006FAF0,
# w0=260862 - the movie module's w0=29779 keeps its working HLE path).
# Guest-native = no exit trick, no zero-read arm, the natural exit.
# PASS = the [lzss-x] EXIT receipt, no lzrwatch conversion, bootmain
# count DROPS, cur=1 held (statetbl active state 1), the coordinator
# entry, menu receipts. REVERT = restore the pre copy.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C231-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
R="runtime/runtime.c"
EXPECT="c821d139f2c30c9aa470ca274656956928f42d0f9989530fdf4aa1db6ac769f4"
if [ ! -s "$R" ]; then echo "C231-FAILED: runtime/runtime.c missing"; exit 1; fi
SS=$(shasum -a 256 "$R" | cut -d" " -f1)
echo "SRC_SHA_BEFORE=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the c821d139 baseline - nothing patched"; exit 0; fi
echo "BASELINE_VERIFIED"
P="patch_c231_$(date +%Y%m%d_%H%M%S)"
if ! (mkdir -p "$P" && cp -p "$R" "$P/runtime.c.pre"); then echo "C231-FAILED: preserve failed"; exit 1; fi
echo "PRESERVED: $P/runtime.c.pre sha=$SS"

echo "===PATCH231=== the R1319 guest-native widen (python, binary-safe, FAIL EXPLICIT)"
python3 - <<'PYEOF' || { echo "PATCH-FAILED - nothing written, no run"; exit 1; }
import hashlib, sys
data = open("runtime/runtime.c","rb").read()
if b"R1319" in data:
    print("IDEMPOTENT-SKIP: R1319 already present - no edit made"); sys.exit(0)
a = b"                if (r[4] == 0x801D9724u) {\n"
n = data.count(a)
print("ANCHOR count=%d (must be 1)" % n)
if n != 1: sys.exit(1)
r = (b"                /* R1319 (c231): WIDEN THE GUEST-NATIVE BRANCH to the\n"
     b"                 * state-1 mount's file-14 stream. The c230 receipts: the\n"
     b"                 * HLE branch decodes this stream correctly, but the R201\n"
     b"                 * exit trick fails for it - the one-shot zero-read\n"
     b"                 * returns 0s, the guest loop treats them as data,\n"
     b"                 * writes on, reads past the RAM end, and R1151 converts\n"
     b"                 * to crash-kit recovery whose boot re-entry WIPES the\n"
     b"                 * installed module (the fast boot-retry loop). The\n"
     b"                 * c257-era receipts PROVED the game's own decoder\n"
     b"                 * handles this exact expansion (R690 checksum verified\n"
     b"                 * at the next walker entry). Guest-native = the proven\n"
     b"                 * path. The w0==260862 term isolates file-14 (the\n"
     b"                 * movie module also targets 8006FAF0 but w0=29779).\n"
     b"                 * PASS = [lzss-x] EXIT receipt, no lzrwatch, cur=1\n"
     b"                 * held, state-1 entry. */\n"
     b"                if (r[4] == 0x801D9724u || (r[5] == 0x8006FAF0u && w0 == 260862u)) {\n")
data = data.replace(a, r, 1)
checks = [("R1319", data.count(b"R1319"), 1),
          ("new-condition", data.count(b"r[4] == 0x801D9724u || (r[5] == 0x8006FAF0u && w0 == 260862u)"), 1),
          ("old-anchor-gone", data.count(a), 0),
          ("fldfp-print", data.count(b"[fldfp] R691"), 2)]  # v2: 2 is the TRUE tree count (the skip-print + the checksum-verification print at the next walker entry) - the c231 cycle receipted got=2 against the actual tree; nothing was written]
ok = True
for name, got, want in checks:
    print("MARKER %s want=%d got=%d %s" % (name, want, got, "OK" if got == want else "FAIL"))
    if got != want: ok = False
if not ok: sys.exit(1)
open("runtime/runtime.c","wb").write(data)
print("NEW_SHA=%s" % hashlib.sha256(data).hexdigest())
PYEOF
echo "PATCH-APPLIED sha=$(shasum -a 256 "$R" | cut -d" " -f1)"

echo "===PARSE231=== the parse gate (pre vs post; restore on break)"
CC_BIN=""
for c in cc clang gcc; do command -v "$c" >/dev/null 2>&1 && { CC_BIN="$c"; break; }; done
PRE_RC=99; POST_RC=99
if [ -n "$CC_BIN" ]; then
  "$CC_BIN" -fsyntax-only -std=gnu99 -I runtime "$P/runtime.c.pre" >/dev/null 2>/tmp/c231_pre.txt; PRE_RC=$?
  "$CC_BIN" -fsyntax-only -std=gnu99 -I runtime "$R" >/dev/null 2>/tmp/c231_post.txt; POST_RC=$?
  echo "PARSE pre_rc=$PRE_RC post_rc=$POST_RC"
  head -4 /tmp/c231_post.txt
fi
if [ "$PRE_RC" -eq 0 ] && [ "$POST_RC" -ne 0 ]; then
  cp -p "$P/runtime.c.pre" "$R"; echo "PARSE-BREAK - baseline RESTORED, nothing run"; exit 1
fi

echo "===RUN231=== the 90s receipt run"
RUN_BUDGET_S=90 ./run.sh > /tmp/run_full_c231.txt 2>&1
echo "RUNSH_RC=$?"
head -4 /tmp/run_full_c231.txt
if [ -s run.log ]; then cp -p run.log "$P/run.log.post"; echo "RUNLOG_POST sha=$(shasum -a 256 "$P/run.log.post" | cut -d" " -f1) size=$(wc -c < "$P/run.log.post" | tr -d " ")"; fi

echo "===NATIVE231=== the guest-native branch receipts"
grep -n "fldfp\|R1319" run.log 2>/dev/null | head -8

echo "===EXIT231=== the natural-exit receipts (THE PASS LINE)"
grep -n "lzss-x\] EXIT" run.log 2>/dev/null | head -8
echo "lzrwatch_count=$(grep -c lzrwatch run.log 2>/dev/null) runaway_lines=$(grep -c lzss-runaway run.log 2>/dev/null)"

echo "===DD680231=== the mount-era receipts"
grep -n "801DD680" run.log 2>/dev/null | grep -v "hook\]\|frontw\|frontguard" | head -16

echo "===STATE231=== the state census (cur=1 held = PASS)"
grep -n "active state 1\|active state 6\|active state 0" run.log 2>/dev/null | head -8
grep -o "cur=0x00000001" run.log 2>/dev/null | wc -l
grep -n "menuchain\|KernelMenu" run.log 2>/dev/null | head -8
grep -n "80077E88" run.log 2>/dev/null | grep -v "coordw\|narrowblast" | head -8

echo "===CENSUS231=== the fault/exit census"
echo "bootmain=$(grep -c bootmain run.log 2>/dev/null) abort130=$(grep -c AbortOnGameFault run.log 2>/dev/null) unpackfix=$(grep -c unpack-fix run.log 2>/dev/null)"
grep -n "rungasp" run.log 2>/dev/null | tail -2
grep -n "bldprov" /tmp/run_full_c231.txt 2>/dev/null | head -1

echo "===SCREEN231=== the visual witnesses + last-frame render"
grep -n "\[screen\]" run.log 2>/dev/null | tail -4
if [ -s vram_live.bin ]; then
  ls -la vram_live.bin | head -1
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
echo "===PAD231==="
echo "padstart=$(grep -c padstart run.log 2>/dev/null) padrd=$(grep -c padrd run.log 2>/dev/null)"
echo "===C231DONE=== guest-native cycle complete - verdict from these receipts; REVERT = restore $P/runtime.c.pre"
