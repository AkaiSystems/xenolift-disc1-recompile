#!/bin/bash
# c348_pausefix.sh - reship of R1359 (c347 gate-fail: the short
# condition substring `cmd == 0x06u || cmd == 0x1Bu` already
# existed 3x tree-wide - gate on FULL unique line text; script
# now fail-closed: a patch failure exits before parse+run).
# R1359: PAUSE (09) ENDS READING at the
# command site - the R163 '0x09=ReadS' reclass retracted there
# too (R1314 fixed the stream layer only; the command site kept
# arming read_active for cmd 09, so post-PAUSE GetStat
# re-primes answered 'still reading' and the fd layer waited
# for the drive-done transition forever - the f15-era stall).
# 0x1B is the real ReadS per the CONFIRMED PSX-SPX model.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C348-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="37a3790a5e6d5e2daebddc6cb9dc67d6bc264bcdff459198f487b30803d5b92a"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1358 tree 37a3790a - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1358 tree)"
TS=$(date +%Y%m%d_%H%M%S)
mkdir -p "patch_c348_$TS"
cp -p "$SRC" "patch_c348_$TS/runtime.c.pre"
echo "PRESERVED: patch_c348_$TS/runtime.c.pre"
python3 - <<'PYEOF'
data = open("runtime/runtime.c", "rb").read()
old1 = b"    } else if (cmd == 0x06u || cmd == 0x09u) { /* ReadN/ReadS: data will be"
old2 = b"    } else if (cmd == 0x08u) { /* Stop (0x09 re-classed ReadS in R163) */"
for tok, want in [(b"R1359", 0), (old1, 1), (old2, 1)]:
    c = data.count(tok)
    print("PRE %s count=%d (must be %d)" % (tok.decode()[:64], c, want))
    if c != want:
        print("PATCH-FAILED - pre-token wrong - nothing written, no run")
        raise SystemExit(0)
lines = data.split(b"\n")
i1 = [i for i, l in enumerate(lines) if l == old1]
i2 = [i for i, l in enumerate(lines) if l == old2]
print("ANCHOR1 count=%d (must be 1) ANCHOR2 count=%d (must be 1)" % (len(i1), len(i2)))
if len(i1) != 1 or len(i2) != 1:
    print("PATCH-FAILED - anchor wrong - nothing written, no run")
    raise SystemExit(0)
new1 = b"    } else if (cmd == 0x06u || cmd == 0x1Bu) { /* R1359 (c348): 0x09 REMOVED - PSX-SPX Pause ENDS reading; the R163 ReadS reclass retracted here too (R1314 fixed the stream layer only); 0x1B is the real ReadS. ReadN/ReadS: data will be"
new2 = b"    } else if (cmd == 0x08u || cmd == 0x09u) { /* R1359 (c348): Stop and Pause BOTH end reading per PSX-SPX - the R163-era 0x09 reclass retracted at the command site */"
receipt = b"        { static int r1359_n; if (r1359_n++ < 8u) r861_out(\"[cd] R1359 Pause/Stop ends reading: read_active cleared at issue (cmd=%02X seek=%u FDF8=%u)\\n\", (unsigned)cd_last_cmd, cd_seek_lba, xenolift_mem_read32(0x8004FDF8u)); } /* R1359 */"
lines[i1[0]] = new1
lines[i2[0]] = new2
lines.insert(i2[0] + 1, receipt)
post = b"\n".join(lines)
checks = [(b"R1359", 4), (b"R1359 (c348): 0x09 REMOVED", 1),
          (b"R1359 (c348): Stop and Pause BOTH end reading", 1),
          (b"[cd] R1359 Pause/Stop ends reading", 1),
          (b"cmd == 0x06u || cmd == 0x09u", 0),
          (b"r1359_n", 2), (b"[cd] R1359 Pause/Stop ends reading", 1),
          (b"R1358", 3), (b"R1351", 4), (b"R1357", 2), (b"[wgen]", 3),
          (b"g_r1351_genuine_answer", 6), (b"L18405", 1),
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
open("/tmp/c348_patched.flag", "w").write("ok")
print("PATCH-APPLIED (R1359 Pause ends reading at the command site)")
PYEOF
if [ ! -f /tmp/c348_patched.flag ]; then echo "PATCH-FAILED - exiting without parse or run"; exit 0; fi
SS2=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_SHA=$SS2"
clang -fsyntax-only -std=gnu99 "$SRC" 2>/tmp/c348_parse.txt; PRC=$?
echo "PARSE_RC=$PRC"
if [ "$PRC" != "0" ]; then echo "PARSE-FAILED - reverting"; head -8 /tmp/c348_parse.txt; cp -p "patch_c348_$TS/runtime.c.pre" "$SRC"; exit 0; fi
echo "PARSE-OK"
echo "===RUN347=== the R1359 build, 120s budget, first-fault stop"
XENOLIFT_FIRSTFAULT_STOP=1 RUN_BUDGET_S=120 bash run.sh > /tmp/run_full_c348.txt 2>&1; RRC=$?
echo "RUN_RC=$RRC"
WDIR="witness_c348_$TS"; mkdir -p "$WDIR"
for f in run.log run.log.d; do [ -f "$f" ] && cp -p "$f" "$WDIR/$f"; done
cp -p /tmp/run_full_c348.txt "$WDIR/run_full.txt"
echo "WITNESS=$WDIR"
LOG="run.log"; [ -s "$LOG" ] || LOG="run.log.d"
echo "===R1359RECEIPTS=== the ends-reading receipts"
grep -n "R1359" "$LOG" | head -10
echo "===CMDTL347=== the command ladder (beyond #12?)"
grep -n "cmdtl" "$LOG" | tail -8
echo "===F15READ347=== the f15 read issue + progression"
grep -n "READ ISSUED" "$LOG" | tail -6
grep -n "file#15" "$LOG" | head -8
grep -n "FDF8=0x16814\|FDF8=92180" "$LOG" | head -6
echo "===SECTORS347=== sectors served at 108995+"
grep -n "sector LBA 1089[9][0-9][0-9]" "$LOG" | head -8
grep -c "sector LBA" "$LOG"
echo "===WGEN347=== the collector receipts"
grep -n "wgen" "$LOG" | tail -6
echo "===FE1C348=== the FE1C walk in the f15 era"
grep -n "\[chg\] FE1C" "$LOG" | tail -10
echo "===FAULT347=== fault census"
grep -c "computed-garbage" "$LOG"
FF=$(grep -n "computed-garbage address" "$LOG" | head -1 | cut -d: -f1)
echo "FIRST_FAULT_LINE=$FF"
if [ -n "$FF" ]; then awk -v s="$((FF-6))" -v e="$((FF+6))" 'NR>=s && NR<=e' "$LOG"; fi
echo "===VIS347=== run tail + gpu census"
grep -n "rungasp" "$LOG" | tail -2
grep -n "gpufin\|gp0_words" "$LOG" | tail -2
grep -n "nonblank" "$LOG" | tail -3
echo "===C348DONE=== R1359 run complete - the f15-era verdict comes from these receipts"
