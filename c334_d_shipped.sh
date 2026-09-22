#!/bin/bash
# c334_collectorexempt.sh - R1355: the genuine-answer exemption
# for the wait-loop collector.
# THE c333 DECODE: the collector (getintr 800415B4 + per-slot
# handler dispatch) is the game's true delivery path, killed by
# the L18405 break under firstfault. The R1183 stale-r[2]
# conviction does not apply when getintr REALLY RUNS.
# THIS CYCLE: (1) preserve pre; (2) R1355 - remove the
# flag-clear from the wrong-pair block, exempt the collector
# break, clear the flag at the slots-drained exit; (3) parse
# gate; (4) 120s run; (5) census: collector slot events,
# consumption, the FE1C walk.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C334-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="2de3899174d063071efad05918f54ae2bbdbd64ebb9392628a9b95b340b2e0f8"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1354 tree 2de38991 - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1354 tree)"
TS=$(date +%Y%m%d_%H%M%S)
mkdir -p "patch_c334_$TS"
cp -p "$SRC" "patch_c334_$TS/runtime.c.pre"
echo "PRESERVED: patch_c334_$TS/runtime.c.pre"
python3 - <<'PYEOF'
data = open("runtime/runtime.c", "rb").read()
lines = data.split(b"\n")
pre_checks = [(b"R1355", 0), (b"g_r1351_genuine_answer = 0u;", 1),
              (b"if (r1179_forge_blocked(\"L18405\")) break;", 1),
              (b"L18405", 1), (b"[wgen]", 1), (b"g_r1351_genuine_answer", 4),
              (b"R1354", 2), (b"R1353", 4), (b"R1351", 4), (b"[wpair]", 2)]
for tok, want in pre_checks:
    c = data.count(tok)
    print("PRE %s count=%d (must be %d)" % (tok.decode(), c, want))
    if c != want:
        print("PATCH-FAILED - pre-token wrong - nothing written, no run")
        raise SystemExit(0)
# anchor A: the 3-line slots block in the collector
patA = b"            uint32_t slots = r[2];\n            if (slots == 0u)\n                break;"
cA = data.count(patA)
print("SLOTSBLOCK count=%d (must be 1)" % cA)
if cA != 1:
    print("PATCH-FAILED - slots block anchor wrong - nothing written, no run")
    raise SystemExit(0)
# site 1: remove the flag-clear line from the wrong-pair block
h1 = [i for i, l in enumerate(lines) if b"g_r1351_genuine_answer = 0u;" in l]
print("FLAGCLEAR count=%d (must be 1)" % len(h1))
if len(h1) != 1:
    print("PATCH-FAILED - flag-clear anchor wrong - nothing written, no run")
    raise SystemExit(0)
del lines[h1[0]]
# site 2: exempt the collector break
data2 = b"\n".join(lines)
h2 = [i for i, l in enumerate(lines) if b"if (r1179_forge_blocked(\"L18405\")) break;" in l]
print("BREAKLINE count=%d (must be 1)" % len(h2))
if len(h2) != 1:
    print("PATCH-FAILED - break anchor wrong - nothing written, no run")
    raise SystemExit(0)
b0 = h2[0]
ws2 = lines[b0][:len(lines[b0]) - len(lines[b0].lstrip())]
lines[b0] = ws2 + b'if (r1179_forge_blocked("L18405") && !g_r1351_genuine_answer) break; /* R1355 (c334): the genuine-answer exemption - a real armed answer is not a forged completion; the collector is the true delivery path (c332/333 decode) */'
# site 3: the slots-drained exit clears the flag
data3 = b"\n".join(lines)
h3 = [i for i, l in enumerate(lines) if l.strip() == b"break;"]
# use the pattern-based replacement instead
old3 = b"            uint32_t slots = r[2];\n            if (slots == 0u)\n                break;"
new3 = (b"            uint32_t slots = r[2];\n"
        b"            if (slots == 0u) {\n"
        b"                if (g_r1351_genuine_answer) { g_r1351_genuine_answer = 0u; r861_out(\"[wgen] R1355 genuine-answer collector pass complete (slots drained)\\n\"); } /* R1355 */\n"
        b"                break;\n"
        b"            }")
data4 = b"\n".join(lines)
c3 = data4.count(old3)
print("SLOTSBLOCK-POST count=%d (must be 1)" % c3)
if c3 != 1:
    print("PATCH-FAILED - slots block lost - nothing written, no run")
    raise SystemExit(0)
data4 = data4.replace(old3, new3)
post = data4
checks = [(b"R1355", 3), (b"[wgen]", 2), (b"[wpair]", 2), (b"g_r1351_genuine_answer", 6),
          (b"g_r1351_genuine_answer = 0u;", 1), (b"R1351", 4), (b"R1353", 4), (b"R1354", 2),
          (b"L18405", 1), (b"L18047", 1), (b"L18048", 1), (b"R1352", 0),
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
print("PATCH-APPLIED (R1355 collector exemption)")
PYEOF
SS2=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_SHA=$SS2"
clang -fsyntax-only -std=gnu99 "$SRC" 2>/tmp/c334_parse.txt; PRC=$?
echo "PARSE_RC=$PRC"
if [ "$PRC" != "0" ]; then echo "PARSE-FAILED - reverting"; head -8 /tmp/c334_parse.txt; cp -p "patch_c334_$TS/runtime.c.pre" "$SRC"; exit 0; fi
echo "PARSE-OK"
echo "===RUN334=== the R1355 build, 120s budget, first-fault stop"
XENOLIFT_FIRSTFAULT_STOP=1 RUN_BUDGET_S=120 bash run.sh > /tmp/run_full_c334.txt 2>&1; RRC=$?
echo "RUN_RC=$RRC"
WDIR="witness_c334_$TS"; mkdir -p "$WDIR"
for f in run.log run.log.d; do [ -f "$f" ] && cp -p "$f" "$WDIR/$f"; done
cp -p /tmp/run_full_c334.txt "$WDIR/run_full.txt"
echo "WITNESS=$WDIR"
LOG="run.log"; [ -s "$LOG" ] || LOG="run.log.d"
echo "===WSERVE334=== the serve chain"
grep -n "wserve\|wopflag\|wconv\|wgen\|wpair" "$LOG" | head -14
echo "===COLLECT334=== the collector slot events + consumption (the R1355 verdict)"
WS=$(grep -n "wserve" "$LOG" | head -1 | cut -d: -f1)
echo "WSERVE_LINE=$WS"
if [ -n "$WS" ]; then awk -v s="$WS" 'NR>=s && /wait-loop event|collector|R1355|rspop|pendclr|response consumed|interrupt acknowledged/ {print NR": "$0}' "$LOG" | head -20; fi
echo "===FE1C334=== the FE1C walk after the serve"
grep -n "\[chg\] FE1C" "$LOG" | tail -10
echo "===OUTCOME334=== cmdtl + READ ISSUED + tail"
grep -n "cmd 02->06" "$LOG" | head -6
grep -c "READ ISSUED" "$LOG"
grep -n "fld2sig" "$LOG" | tail -3
echo "===FAULT334=== fault census"
grep -c "computed-garbage" "$LOG"
FF=$(grep -n "computed-garbage address" "$LOG" | head -1 | cut -d: -f1)
echo "FIRST_FAULT_LINE=$FF"
if [ -n "$FF" ]; then awk -v s="$((FF-6))" -v e="$((FF+6))" 'NR>=s && NR<=e' "$LOG"; fi
echo "===VIS334=== run tail"
tail -4 /tmp/run_full_c334.txt
grep -n "rungasp" "$LOG" | tail -2
echo "===C334DONE=== R1355 run complete - the collector-exemption verdict comes from these receipts"
