#!/bin/bash
# c332_queuetelemetry.sh - R1354: the kernel-queue telemetry at
# the pre-pair site + the disc1 arming-protocol grep.
# THE c331 DECODE: the pair (800409E4/80040A4C) NEVER touches
# the CD registers - 800409E4 works on *(0x80056418), 80040A4C
# tests a queue struct at *(0x8005641C) (bit0@+4 SET, bit0@+0
# CLEAR). The pair is the kernel event-QUEUE processor; the
# BIOS-side translation that ARMS the queue is the missing half.
# THIS CYCLE: (1) preserve pre; (2) R1354 - the pre-pair print
# gains q1/q2/p2w0/p2w4; (3) parse gate; (4) 120s run;
# (5) grep the fresh disc1.c for all 56418/5641C references;
# (6) census.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C332-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="1415b5ccfa38535bdbada7677029073e26e2d99e6a8ad909e86710e48702b261"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1353 tree 1415b5cc - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1353 tree)"
TS=$(date +%Y%m%d_%H%M%S)
mkdir -p "patch_c332_$TS"
cp -p "$SRC" "patch_c332_$TS/runtime.c.pre"
echo "PRESERVED: patch_c332_$TS/runtime.c.pre"
python3 - <<'PYEOF'
data = open("runtime/runtime.c", "rb").read()
lines = data.split(b"\n")
# anchor: the pre-pair telemetry line from c330
a1 = b"[wpair] R1353 bank-set pre-pair"
h1 = [i for i, l in enumerate(lines) if a1 in l]
print("PREPRINT count=%d (must be 1)" % len(h1))
if len(h1) != 1:
    print("PATCH-FAILED - pre-pair print anchor wrong - nothing written, no run")
    raise SystemExit(0)
c0 = h1[0]
ws = lines[c0][:len(lines[c0]) - len(lines[c0].lstrip())]
pre_checks = [(b"R1354", 0), (b"R1353", 5), (b"[wpair]", 2), (b"[wgen]", 1),
              (b"g_r1351_genuine_answer", 4), (b"R1351", 4),
              (b"L18047", 1), (b"L18048", 1), (b"R1352", 0),
              (b"R1350", 3), (b"[wconv]", 1), (b"conv_budget", 15)]
for tok, want in pre_checks:
    c = data.count(tok)
    print("PRE %s count=%d (must be %d)" % (tok.decode(), c, want))
    if c != want:
        print("PATCH-FAILED - pre-token wrong - nothing written, no run")
        raise SystemExit(0)
new_lines = [
    ws + b'    uint32_t r1354_p2 = xenolift_mem_read32(0x8005641Cu); int r1354_ok = (r1354_p2 >= 0x80010000u && r1354_p2 < 0x80200000u); /* R1354 */',
    ws + b'    r861_out("[wpair] R1354 queue-telemetry pre-pair: bank=%u->1 pend=%u resp=%u/%u q1=%08X q2=%08X p2w0=%08X p2w4=%08X s2/s3=%02X/%02X\\n", (unsigned)r1353_bank, (unsigned)cd_pending, (unsigned)cd_resp_pos, (unsigned)cd_resp_n, xenolift_mem_read32(0x80056418u), r1354_p2, (r1354_ok ? xenolift_mem_read32(r1354_p2) : 0u), (r1354_ok ? xenolift_mem_read32(r1354_p2 + 4u) : 0u), xenolift_mem[0x56788], xenolift_mem[0x56789]);',
]
lines[c0:c0+1] = new_lines
post = b"\n".join(lines)
checks = [(b"R1354", 2), (b"R1353", 4), (b"[wpair]", 2), (b"[wgen]", 1),
          (b"g_r1351_genuine_answer", 4), (b"R1351", 4),
          (b"L18047", 1), (b"L18048", 1), (b"R1352", 0),
          (b"R1350", 3), (b"[wconv]", 1), (b"g_r1350_conv_refill", 5), (b"conv_budget", 15),
          (b"R1349", 2), (b"[wopflag]", 1), (b"R1347", 3), (b"[wserve]", 1),
          (b"R1346", 1), (b"r1346_serve", 3), (b"r1346_armed", 5),
          (b"R1345", 2), (b"seekmism", 1), (b"[stalecd-near]", 1),
          (b"R1343", 0), (b"R1342", 0),
          (b"static int fassist_budget = 400;", 1),
          (b"if (r887_streak >= 2000000000u) {", 1),
          (b"static int iso_resolve(const char *path, uint32_t *out_lba, uint32_t *out_size)", 1)]
for tok, want in checks:
    c = post.count(tok)
    print("POST %s count=%d (must be %d)" % (tok.decode(), c, want))
    if c != want:
        print("PATCH-FAILED - post-token wrong - nothing written, no run")
        raise SystemExit(0)
open("runtime/runtime.c", "wb").write(post)
print("PATCH-APPLIED (R1354 queue telemetry)")
PYEOF
SS2=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_SHA=$SS2"
clang -fsyntax-only -std=gnu99 "$SRC" 2>/tmp/c332_parse.txt; PRC=$?
echo "PARSE_RC=$PRC"
if [ "$PRC" != "0" ]; then echo "PARSE-FAILED - reverting"; head -8 /tmp/c332_parse.txt; cp -p "patch_c332_$TS/runtime.c.pre" "$SRC"; exit 0; fi
echo "PARSE-OK"
echo "===ARMREF332=== the fresh disc1.c references to the queue cells (the arming protocol)"
grep -n "56418\|5641C" disc1.c | head -20
echo "===RUN332=== the R1354 build, 120s budget, first-fault stop"
XENOLIFT_FIRSTFAULT_STOP=1 RUN_BUDGET_S=120 bash run.sh > /tmp/run_full_c332.txt 2>&1; RRC=$?
echo "RUN_RC=$RRC"
WDIR="witness_c332_$TS"; mkdir -p "$WDIR"
for f in run.log run.log.d; do [ -f "$f" ] && cp -p "$f" "$WDIR/$f"; done
cp -p /tmp/run_full_c332.txt "$WDIR/run_full.txt"
echo "WITNESS=$WDIR"
LOG="run.log"; [ -s "$LOG" ] || LOG="run.log.d"
echo "===WPAIR332=== the queue telemetry (the R1354 verdict)"
grep -n "wpair\|wgen\|wserve\|wconv\|wopflag" "$LOG" | head -12
echo "===POPS332=== pops + pendclr post-serve"
WS=$(grep -n "wserve" "$LOG" | head -1 | cut -d: -f1)
echo "WSERVE_LINE=$WS"
if [ -n "$WS" ]; then awk -v s="$WS" 'NR>=s && /rspop|pendclr|response consumed|interrupt acknowledged/ {print NR": "$0}' "$LOG" | head -12; fi
echo "===FE1C332=== the FE1C walk after the serve"
grep -n "\[chg\] FE1C" "$LOG" | tail -6
echo "===FAULT332=== fault census"
grep -c "computed-garbage" "$LOG"
FF=$(grep -n "computed-garbage address" "$LOG" | head -1 | cut -d: -f1)
echo "FIRST_FAULT_LINE=$FF"
echo "===C332DONE=== R1354 run complete - the queue-cell values name the arming posture"
