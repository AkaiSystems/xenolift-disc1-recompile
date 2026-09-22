#!/bin/bash
# c330_bankset.sh - R1353: the bank-set dispatch for the
# exempted genuine-answer pair.
# THE c329 VERDICT: the camera receipted BANK=0 at the pair
# dispatch - the pair's first read (case 0x1F801803) returns
# cd_pending only when (cd_index & 3)==1, so at bank 0 it
# reads no-INT and exits as a silent no-op.
# THIS CYCLE: (1) preserve pre; (2) R1353 - the exempted block
# saves the bank, sets cd_index=1, dispatches the pair with
# pre/post telemetry, restores the bank; the else-branch keeps
# the original forge-gated dispatches; (3) parse gate;
# (4) 120s run; (5) census: pops, slots, the FE1C walk.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C330-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="09a1c6c6f570d8353230845ab099d6a9b0a1bf0a2e26b37b3f5a83394d163522"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1352 tree 09a1c6c6 - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1352 tree)"
TS=$(date +%Y%m%d_%H%M%S)
mkdir -p "patch_c330_$TS"
cp -p "$SRC" "patch_c330_$TS/runtime.c.pre"
echo "PRESERVED: patch_c330_$TS/runtime.c.pre"
python3 - <<'PYEOF'
data = open("runtime/runtime.c", "rb").read()
lines = data.split(b"\n")
# anchor: the c329 pre-pair telemetry line (first of the 3-line exempted block)
a1 = b"[wpair] R1352 pre-pair"
h1 = [i for i, l in enumerate(lines) if a1 in l]
print("PRETELEM count=%d (must be 1)" % len(h1))
if len(h1) != 1:
    print("PATCH-FAILED - pretelemetry anchor wrong - nothing written, no run")
    raise SystemExit(0)
c0 = h1[0]
ws = lines[c0][:len(lines[c0]) - len(lines[c0].lstrip())]
ok1 = (b'L18047") || g_r1351_genuine_answer' in lines[c0+1])
ok2 = (b'L18048") || g_r1351_genuine_answer' in lines[c0+2])
print("BLOCKSTRUCT_OK=%s/%s (lines +1/+2 are the exempted pair dispatches)" % (ok1, ok2))
if not (ok1 and ok2):
    print("PATCH-FAILED - exempted block structure unexpected - nothing written, no run")
    raise SystemExit(0)
pre_checks = [(b"R1353", 0), (b"R1352", 3), (b"[wpair]", 2), (b"[wgen]", 1),
              (b"g_r1351_genuine_answer", 7), (b"R1351", 5),
              (b"L18047", 1), (b"L18048", 1),
              (b"R1350", 3), (b"[wconv]", 1), (b"conv_budget", 15)]
for tok, want in pre_checks:
    c = data.count(tok)
    print("PRE %s count=%d (must be %d)" % (tok.decode(), c, want))
    if c != want:
        print("PATCH-FAILED - pre-token wrong - nothing written, no run")
        raise SystemExit(0)
new_block = [
    ws + b'if (g_r1351_genuine_answer) { /* R1353 (c330): the pair reads the INT flag via 803-idx1, which returns cd_pending only on bank 1 - the c329 camera receipted bank=0 at dispatch and a silent no-op pair */',
    ws + b'    uint8_t r1353_bank = cd_index;',
    ws + b'    cd_index = 1;',
    ws + b'    r861_out("[wpair] R1353 bank-set pre-pair: bank=%u->1 pend=%u resp=%u/%u fe1c=%08X s2/s3=%02X/%02X\\n", (unsigned)r1353_bank, (unsigned)cd_pending, (unsigned)cd_resp_pos, (unsigned)cd_resp_n, xenolift_mem_read32(0x8004FE1Cu), xenolift_mem[0x56788], xenolift_mem[0x56789]);',
    ws + b'    g_guest_depth++, xenolift_dispatch(0x800409E4u), g_guest_depth--;',
    ws + b'    g_guest_depth++, xenolift_dispatch(0x80040A4Cu), g_guest_depth--;',
    ws + b'    g_r1351_genuine_answer = 0u;',
    ws + b'    r861_out("[wgen] R1351 genuine-answer BIOS-style pair dispatch (serve-armed INT3, bank=1) - the forge-block never meant to stop this\\n");',
    ws + b'    r861_out("[wpair] R1353 post-pair: bank=%u pend=%u resp=%u/%u fe1c=%08X s2/s3=%02X/%02X\\n", (unsigned)(cd_index & 3u), (unsigned)cd_pending, (unsigned)cd_resp_pos, (unsigned)cd_resp_n, xenolift_mem_read32(0x8004FE1Cu), xenolift_mem[0x56788], xenolift_mem[0x56789]);',
    ws + b'    cd_index = r1353_bank; /* R1353 restore */',
    ws + b'} else { /* R1351: the non-exemption path (firstfault off) - original forge-gated dispatches */',
    ws + b'    if (!r1179_forge_blocked("L18047")) { g_guest_depth++, xenolift_dispatch(0x800409E4u), g_guest_depth--; }',
    ws + b'    if (!r1179_forge_blocked("L18048")) { g_guest_depth++, xenolift_dispatch(0x80040A4Cu), g_guest_depth--; }',
    ws + b'} /* R1353 */',
]
lines[c0:c0+3] = new_block
post = b"\n".join(lines)
checks = [(b"R1353", 5), (b"R1352", 0), (b"[wpair]", 2), (b"[wgen]", 1),
          (b"g_r1351_genuine_answer", 4), (b"R1351", 4),
          (b"L18047", 1), (b"L18048", 1),
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
print("PATCH-APPLIED (R1353 bank-set dispatch)")
PYEOF
SS2=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_SHA=$SS2"
clang -fsyntax-only -std=gnu99 "$SRC" 2>/tmp/c330_parse.txt; PRC=$?
echo "PARSE_RC=$PRC"
if [ "$PRC" != "0" ]; then echo "PARSE-FAILED - reverting"; head -8 /tmp/c330_parse.txt; cp -p "patch_c330_$TS/runtime.c.pre" "$SRC"; exit 0; fi
echo "PARSE-OK"
echo "===RUN330=== the R1353 build, 120s budget, first-fault stop"
XENOLIFT_FIRSTFAULT_STOP=1 RUN_BUDGET_S=120 bash run.sh > /tmp/run_full_c330.txt 2>&1; RRC=$?
echo "RUN_RC=$RRC"
WDIR="witness_c330_$TS"; mkdir -p "$WDIR"
for f in run.log run.log.d; do [ -f "$f" ] && cp -p "$f" "$WDIR/$f"; done
cp -p /tmp/run_full_c330.txt "$WDIR/run_full.txt"
echo "WITNESS=$WDIR"
LOG="run.log"; [ -s "$LOG" ] || LOG="run.log.d"
echo "===WPAIR330=== the bank-set pair telemetry (the R1353 verdict)"
grep -n "wpair\|wgen\|wserve\|wconv\|wopflag" "$LOG" | head -14
echo "===POPS330=== pops + pendclr post-serve"
WS=$(grep -n "wserve" "$LOG" | head -1 | cut -d: -f1)
echo "WSERVE_LINE=$WS"
if [ -n "$WS" ]; then awk -v s="$WS" 'NR>=s && /rspop|pendclr|response consumed|interrupt acknowledged/ {print NR": "$0}' "$LOG" | head -14; fi
echo "===FE1C330=== the FE1C walk after the serve"
grep -n "\[chg\] FE1C" "$LOG" | tail -10
echo "===OUTCOME330=== cmdtl + READ ISSUED + tail"
grep -n "cmd 02->06" "$LOG" | head -8
grep -c "READ ISSUED" "$LOG"
grep -n "fld2sig" "$LOG" | tail -3
echo "===FAULT330=== fault census"
grep -c "computed-garbage" "$LOG"
FF=$(grep -n "computed-garbage address" "$LOG" | head -1 | cut -d: -f1)
echo "FIRST_FAULT_LINE=$FF"
echo "===VIS330=== run tail"
tail -4 /tmp/run_full_c330.txt
grep -n "rungasp" "$LOG" | tail -2
echo "===C330DONE=== R1353 run complete - the bank-set verdict comes from these receipts"
