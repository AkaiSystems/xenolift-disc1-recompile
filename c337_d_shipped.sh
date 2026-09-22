#!/bin/bash
# c337_posturebreak2.sh - R1356 reship: the posture-based
# collector break, corrected markers.
# THE c336 GATE-FAIL: the replacement anchored a SUBSTRING and
# the old R1355 comment SURVIVED -> POST R1355=4 vs 3. RESHIP:
# the new comment mentions ONLY R1356 -> POST R1355 stays 3.
# THE c335 CONVICTION STANDS: the ReadN's INT3 was armed but
# never consumed - the R1355 exemption is ONE-SHOT and the
# ReadN needs its own collector pass at L18405.
# THIS CYCLE: (1) preserve pre; (2) R1356 - the break gains
# `cd_pending == 0u`; (3) parse gate; (4) 120s run; (5) census.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C337-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="6815e73c2282e3ff3385dc700e022ac1526a82e833e70eb7a1851b4f6b49275c"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1355 tree 6815e73c - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1355 tree)"
TS=$(date +%Y%m%d_%H%M%S)
mkdir -p "patch_c337_$TS"
cp -p "$SRC" "patch_c337_$TS/runtime.c.pre"
echo "PRESERVED: patch_c337_$TS/runtime.c.pre"
python3 - <<'PYEOF'
data = open("runtime/runtime.c", "rb").read()
pre_checks = [(b"R1356", 0), (b"cd_pending == 0u) break;", 0),
              (b"if (r1179_forge_blocked(\"L18405\") && !g_r1351_genuine_answer) break;", 1),
              (b"R1355", 3), (b"L18405", 1), (b"[wgen]", 2), (b"[wpair]", 2),
              (b"g_r1351_genuine_answer", 6), (b"R1351", 4), (b"R1353", 4), (b"R1354", 2)]
for tok, want in pre_checks:
    c = data.count(tok)
    print("PRE %s count=%d (must be %d)" % (tok.decode(), c, want))
    if c != want:
        print("PATCH-FAILED - pre-token wrong - nothing written, no run")
        raise SystemExit(0)
old = b'if (r1179_forge_blocked("L18405") && !g_r1351_genuine_answer) break;'
new = b'if (r1179_forge_blocked("L18405") && !g_r1351_genuine_answer && cd_pending == 0u) break; /* R1356 (c337): posture-based - the collector also runs while an armed model answer is outstanding */'
c1 = data.count(old)
print("BREAKLINE count=%d (must be 1)" % c1)
if c1 != 1:
    print("PATCH-FAILED - break anchor wrong - nothing written, no run")
    raise SystemExit(0)
post = data.replace(old, new)
checks = [(b"R1356", 1), (b"R1355", 3), (b"cd_pending == 0u) break;", 1),
          (b"L18405", 1), (b"[wgen]", 2), (b"[wpair]", 2),
          (b"g_r1351_genuine_answer", 6), (b"R1351", 4), (b"R1353", 4), (b"R1354", 2),
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
print("PATCH-APPLIED (R1356 posture-based collector break, c337 reship)")
PYEOF
SS2=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_SHA=$SS2"
clang -fsyntax-only -std=gnu99 "$SRC" 2>/tmp/c337_parse.txt; PRC=$?
echo "PARSE_RC=$PRC"
if [ "$PRC" != "0" ]; then echo "PARSE-FAILED - reverting"; head -8 /tmp/c337_parse.txt; cp -p "patch_c337_$TS/runtime.c.pre" "$SRC"; exit 0; fi
echo "PARSE-OK"
echo "===RUN337=== the R1356 build, 120s budget, first-fault stop"
XENOLIFT_FIRSTFAULT_STOP=1 RUN_BUDGET_S=120 bash run.sh > /tmp/run_full_c337.txt 2>&1; RRC=$?
echo "RUN_RC=$RRC"
WDIR="witness_c337_$TS"; mkdir -p "$WDIR"
for f in run.log run.log.d; do [ -f "$f" ] && cp -p "$f" "$WDIR/$f"; done
cp -p /tmp/run_full_c337.txt "$WDIR/run_full.txt"
echo "WITNESS=$WDIR"
LOG="run.log"; [ -s "$LOG" ] || LOG="run.log.d"
echo "===READN337=== the ReadN INT3 consumption (the R1356 verdict)"
RN=$(grep -n "STREAM-ARM (ReadN)" "$LOG" | tail -1 | cut -d: -f1)
echo "STREAMARM_LINE=$RN"
if [ -n "$RN" ]; then awk -v s="$RN" -v e="$((RN+140))" 'NR>=s && NR<=e && /rspop|pendclr|response consumed|interrupt acknowledged|wait-loop event|wgen|FE1C|chg\] cell|sector|fld-int1|data handler|mv-conv/ {print NR": "$0}' "$LOG" | head -32; fi
echo "===POPS337=== pops + pendclr post-ReadN (tail census)"
if [ -n "$RN" ]; then
  for TAG in "rspop" "pendclr" "response consumed" "interrupt acknowledged" "fld-int1" "sector"; do
    C=$(awk -v s="$RN" 'NR>=s' "$LOG" | grep -c "$TAG")
    echo "TAIL_COUNT[$TAG]=$C"
  done
fi
echo "===FE1C337=== the FE1C walk after the ReadN"
grep -n "\[chg\] FE1C" "$LOG" | tail -10
echo "===OUTCOME337=== cmdtl + data posture + mvloop exit"
grep -n "cmdtl" "$LOG" | tail -6
grep -n "fld2sig" "$LOG" | tail -3
grep -n "mvloop" "$LOG" | tail -2
echo "===FAULT337=== fault census"
grep -c "computed-garbage" "$LOG"
FF=$(grep -n "computed-garbage address" "$LOG" | head -1 | cut -d: -f1)
echo "FIRST_FAULT_LINE=$FF"
if [ -n "$FF" ]; then awk -v s="$((FF-6))" -v e="$((FF+6))" 'NR>=s && NR<=e' "$LOG"; fi
echo "===VIS337=== run tail + gpu census"
grep -n "rungasp" "$LOG" | tail -2
grep -n "gpufin\|gp0_words" "$LOG" | tail -2
echo "===C337DONE=== R1356 run complete - the posture-break verdict comes from these receipts"
