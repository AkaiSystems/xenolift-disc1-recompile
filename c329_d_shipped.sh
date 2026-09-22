#!/bin/bash
# c329_pairtelemetry.sh - R1352: pre/post-pair telemetry camera
# at the exempted genuine-answer dispatch.
# THE c328 VERDICT: the exempted pair DISPATCHED (wgen 25396)
# on the correct FIFO but consumed nothing. The pair's own
# internals are the refusing layer; the bank is the prime
# suspect (case 0x1F801803 returns cd_pending only when
# (cd_index & 3)==1). CAMERA-ONLY: no behavior change beyond
# the two telemetry prints around the pair.
# THIS CYCLE: (1) preserve pre; (2) R1352 - [wpair] pre/post
# prints (bank, pend, resp pos/n, FE1C, slot cells) at the wgen
# site; (3) parse gate; (4) 120s run; (5) census.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C329-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="8ba6d947d76e11628b6c6c6e339f98a3e2d6c3cf088022cbbc3b292ee7f972b2"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1351 tree 8ba6d947 - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1351 tree)"
TS=$(date +%Y%m%d_%H%M%S)
mkdir -p "patch_c329_$TS"
cp -p "$SRC" "patch_c329_$TS/runtime.c.pre"
echo "PRESERVED: patch_c329_$TS/runtime.c.pre"
python3 - <<'PYEOF'
data = open("runtime/runtime.c", "rb").read()
lines = data.split(b"\n")
# anchor 1: the exempted 800409E4 dispatch line (insert pre-pair print before it)
a1 = b'if (!r1179_forge_blocked("L18047") || g_r1351_genuine_answer) { g_guest_depth++, xenolift_dispatch(0x800409E4u), g_guest_depth--; }'
h1 = [i for i, l in enumerate(lines) if a1 in l]
print("PAIR47 count=%d (must be 1)" % len(h1))
if len(h1) != 1:
    print("PATCH-FAILED - pair47 anchor wrong - nothing written, no run")
    raise SystemExit(0)
c0 = h1[0]
ws = lines[c0][:len(lines[c0]) - len(lines[c0].lstrip())]
# anchor 2: the exempted 80040A4C line (extend the wgen inner block with the post print)
a2 = b'if (!r1179_forge_blocked("L18048") || g_r1351_genuine_answer) {'
h2 = [i for i, l in enumerate(lines) if a2 in l]
print("PAIR48 count=%d (must be 1)" % len(h2))
if len(h2) != 1:
    print("PATCH-FAILED - pair48 anchor wrong - nothing written, no run")
    raise SystemExit(0)
if h2[0] != c0 + 1:
    print("PATCH-FAILED - pair lines not adjacent - nothing written, no run")
    raise SystemExit(0)
pre_checks = [(b"R1352", 0), (b"[wpair]", 0), (b"[wgen]", 1), (b"g_r1351_genuine_answer", 6),
              (b"R1351", 5), (b"R1350", 3), (b"[wconv]", 1), (b"conv_budget", 15)]
for tok, want in pre_checks:
    c = data.count(tok)
    print("PRE %s count=%d (must be %d)" % (tok.decode(), c, want))
    if c != want:
        print("PATCH-FAILED - pre-token wrong - nothing written, no run")
        raise SystemExit(0)
# insert the pre-pair print line before the 800409E4 dispatch
pre_line = ws + b'if (g_r1351_genuine_answer) { r861_out("[wpair] R1352 pre-pair: bank=%u pend=%u resp=%u/%u fe1c=%08X s2/s3=%02X/%02X\\n", (unsigned)(cd_index & 3u), (unsigned)cd_pending, (unsigned)cd_resp_pos, (unsigned)cd_resp_n, xenolift_mem_read32(0x8004FE1Cu), xenolift_mem[0x56788], xenolift_mem[0x56789]); } /* R1352 */'
lines[c0:c0] = [pre_line]
# extend the wgen inner block (now at c0+2) with the post-pair print
gidx = c0 + 2
gline = lines[gidx]
marker = b'r861_out("[wgen] R1351 genuine-answer BIOS-style pair dispatch (serve-armed INT3) - the forge-block never meant to stop this\\n"); }'
if marker not in gline:
    print("PATCH-FAILED - wgen inner block not found on the pair48 line - nothing written, no run")
    raise SystemExit(0)
post_print = b' r861_out("[wpair] R1352 post-pair: bank=%u pend=%u resp=%u/%u fe1c=%08X s2/s3=%02X/%02X\\n", (unsigned)(cd_index & 3u), (unsigned)cd_pending, (unsigned)cd_resp_pos, (unsigned)cd_resp_n, xenolift_mem_read32(0x8004FE1Cu), xenolift_mem[0x56788], xenolift_mem[0x56789]); }'
new_gline = gline.replace(marker, b'r861_out("[wgen] R1351 genuine-answer BIOS-style pair dispatch (serve-armed INT3) - the forge-block never meant to stop this\\n");' + post_print)
lines[gidx] = new_gline
post = b"\n".join(lines)
checks = [(b"R1352", 3), (b"[wpair]", 2), (b"[wgen]", 1), (b"g_r1351_genuine_answer", 7),
          (b"R1351", 5), (b"R1350", 3), (b"[wconv]", 1), (b"conv_budget", 15),
          (b"L18047", 1), (b"L18048", 1),
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
print("PATCH-APPLIED (R1352 pre/post-pair telemetry camera)")
PYEOF
SS2=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_SHA=$SS2"
clang -fsyntax-only -std=gnu99 "$SRC" 2>/tmp/c329_parse.txt; PRC=$?
echo "PARSE_RC=$PRC"
if [ "$PRC" != "0" ]; then echo "PARSE-FAILED - reverting"; head -8 /tmp/c329_parse.txt; cp -p "patch_c329_$TS/runtime.c.pre" "$SRC"; exit 0; fi
echo "PARSE-OK"
echo "===RUN329=== the R1352 build, 120s budget, first-fault stop"
XENOLIFT_FIRSTFAULT_STOP=1 RUN_BUDGET_S=120 bash run.sh > /tmp/run_full_c329.txt 2>&1; RRC=$?
echo "RUN_RC=$RRC"
WDIR="witness_c329_$TS"; mkdir -p "$WDIR"
for f in run.log run.log.d; do [ -f "$f" ] && cp -p "$f" "$WDIR/$f"; done
cp -p /tmp/run_full_c329.txt "$WDIR/run_full.txt"
echo "WITNESS=$WDIR"
LOG="run.log"; [ -s "$LOG" ] || LOG="run.log.d"
echo "===WPAIR329=== the pre/post-pair telemetry (the R1352 verdict)"
grep -n "wpair\|wgen\|wserve\|wconv\|wopflag" "$LOG" | head -14
echo "===POPS329=== pops + pendclr post-serve"
WS=$(grep -n "wserve" "$LOG" | head -1 | cut -d: -f1)
echo "WSERVE_LINE=$WS"
if [ -n "$WS" ]; then awk -v s="$WS" 'NR>=s && /rspop|pendclr|response consumed|interrupt acknowledged/ {print NR": "$0}' "$LOG" | head -12; fi
echo "===FE1C329=== the FE1C walk after the serve"
grep -n "\[chg\] FE1C" "$LOG" | tail -8
echo "===TAIL329=== the wedge posture tail"
grep -n "fld2sig" "$LOG" | tail -3
echo "===FAULT329=== fault census"
grep -c "computed-garbage" "$LOG"
FF=$(grep -n "computed-garbage address" "$LOG" | head -1 | cut -d: -f1)
echo "FIRST_FAULT_LINE=$FF"
echo "===VIS329=== run tail"
tail -4 /tmp/run_full_c329.txt
grep -n "rungasp" "$LOG" | tail -2
echo "===C329DONE=== R1352 run complete - the pre/post-pair verdict comes from these receipts"
