#!/bin/bash
# c350_eragated.sh - R1360: the ends-reading clear for PAUSE,
# ERA-GATED to the module band. The c348 receipts proved the
# global clear faults the boot's mid-archive-sync pauses (the
# death chain: ArchiveDataSync -> exit 99); the c349 revert
# restored the pristine R1358 baseline. This change keeps the
# 06||09 arm branch byte-identical for the boot era and clears
# read_active ONLY at a module-era PAUSE (cmd==09,
# cd_seek_lba >= 108933u) - the f15-era fd layer waits for
# the drive-done transition that never comes.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C350-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="37a3790a5e6d5e2daebddc6cb9dc67d6bc264bcdff459198f487b30803d5b92a"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the pristine R1358 tree - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the pristine R1358 tree)"
TS=$(date +%Y%m%d_%H%M%S)
mkdir -p "patch_c350_$TS"
cp -p "$SRC" "patch_c350_$TS/runtime.c.pre"
echo "PRESERVED: patch_c350_$TS/runtime.c.pre"
python3 - <<'PYEOF'
data = open("runtime/runtime.c", "rb").read()
anchor = b"        cd_data_loaded = 0; /* load on first demand (status poll/data read) */"
for tok, want in [(b"R1360", 0), (b"R1359", 0), (anchor, 1)]:
    c = data.count(tok)
    print("PRE %s count=%d (must be %d)" % (tok.decode()[:64], c, want))
    if c != want:
        print("PATCH-FAILED - pre-token wrong - nothing written, no run")
        raise SystemExit(0)
lines = data.split(b"\n")
ia = [i for i, l in enumerate(lines) if l == anchor]
print("ANCHOR count=%d (must be 1)" % len(ia))
if len(ia) != 1:
    print("PATCH-FAILED - anchor wrong - nothing written, no run")
    raise SystemExit(0)
newblock = [
 b"        if (cmd == 0x09u && cd_seek_lba >= 108933u) { /* R1360 (c350, era-gated): module-era PAUSE ends reading per PSX-SPX - the f15-era fd layer waits for the drive-done transition; the boot's 09s (seek<=108893, mid-archive-sync - the c348 death chain) keep the R163 continuity */",
 b"            cd_read_active = 0;",
 b"            { static int r1360_n; if (r1360_n++ < 8u) r861_out(\"[cd] R1360 module-era Pause ends reading: read_active cleared (seek=%u FDF8=%u)\\n\", cd_seek_lba, xenolift_mem_read32(0x8004FDF8u)); } /* R1360 */",
 b"        }",
]
for j, nl in enumerate(newblock):
    lines.insert(ia[0] + 1 + j, nl)
post = b"\n".join(lines)
checks = [(b"R1360", 3), (b"R1360 (c350, era-gated)", 1),
          (b"[cd] R1360 module-era Pause ends reading", 1),
          (b"r1360_n", 2), (b"R1359", 0),
          (anchor, 1), (b"R1358", 3), (b"R1351", 4), (b"R1357", 2),
          (b"[wgen]", 3), (b"g_r1351_genuine_answer", 6), (b"L18405", 1),
          (b"R1349", 2), (b"[wopflag]", 1), (b"R1347", 3), (b"[wserve]", 1),
          (b"R1346", 1), (b"r1346_serve", 3), (b"r1346_armed", 5),
          (b"R1345", 2), (b"seekmism", 1), (b"[stalecd-near]", 1),
          (b"R1350", 3), (b"[wconv]", 1), (b"g_r1350_conv_refill", 5),
          (b"static int fassist_budget = 400;", 1),
          (b"static int iso_resolve(const char *path, uint32_t *out_lba, uint32_t *out_size)", 1)]
for tok, want in checks:
    c = post.count(tok)
    print("POST %s count=%d (must be %d)" % (tok.decode()[:64], c, want))
    if c != want:
        print("PATCH-FAILED - post-token wrong - nothing written, no run")
        raise SystemExit(0)
open("runtime/runtime.c", "wb").write(post)
open("/tmp/c350_patched.flag", "w").write("ok")
print("PATCH-APPLIED (R1360 era-gated Pause ends reading)")
PYEOF
if [ ! -f /tmp/c350_patched.flag ]; then echo "PATCH-FAILED - exiting without parse or run"; exit 0; fi
SS2=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_SHA=$SS2"
clang -fsyntax-only -std=gnu99 "$SRC" 2>/tmp/c350_parse.txt; PRC=$?
echo "PARSE_RC=$PRC"
if [ "$PRC" != "0" ]; then echo "PARSE-FAILED - reverting"; head -8 /tmp/c350_parse.txt; cp -p "patch_c350_$TS/runtime.c.pre" "$SRC"; exit 0; fi
echo "PARSE-OK"
echo "===RUN350=== the R1360 build, 120s budget, first-fault stop"
XENOLIFT_FIRSTFAULT_STOP=1 RUN_BUDGET_S=120 bash run.sh > /tmp/run_full_c350.txt 2>&1; RRC=$?
echo "RUN_RC=$RRC"
WDIR="witness_c350_$TS"; mkdir -p "$WDIR"
for f in run.log run.log.d; do [ -f "$f" ] && cp -p "$f" "$WDIR/$f"; done
cp -p /tmp/run_full_c350.txt "$WDIR/run_full.txt"
echo "WITNESS=$WDIR"
LOG="run.log"; [ -s "$LOG" ] || LOG="run.log.d"
echo "===R1360RECEIPTS=== the era-gated clear receipts"
grep -n "R1360" "$LOG" | head -10
echo "===CMDTL350=== the command ladder"
grep -n "cmdtl" "$LOG" | tail -8
echo "===F15READ350=== the f15 read issue + progression"
grep -n "READ ISSUED" "$LOG" | tail -6
grep -n "file#15" "$LOG" | head -8
grep -n "FDF8=92180\|FDF8=0x16814" "$LOG" | head -6
echo "===SECTORS350=== sectors served"
grep -c "sector LBA" "$LOG"
grep -n "sector LBA 10899[0-9]" "$LOG" | head -8
echo "===FE1C350=== the FE1C walk after the module-era pause"
grep -n "\[chg\] FE1C" "$LOG" | tail -10
echo "===FAULT350=== fault census + boot-safety"
grep -c "computed-garbage" "$LOG"
grep -c "cmdtl" "$LOG"
echo "===VIS350=== run tail + gpu census"
grep -n "rungasp" "$LOG" | tail -2
grep -n "gpufin\|gp0_words" "$LOG" | tail -2
grep -n "nonblank" "$LOG" | tail -3
echo "===C350DONE=== R1360 run complete - the era-gated verdict comes from these receipts"
