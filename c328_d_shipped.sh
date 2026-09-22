#!/bin/bash
# c328_genuineanswer.sh - R1351: the one-shot genuine-answer
# exemption at the conversion's pair sites.
# THE c327 VERDICT: the tick body runs at the tail and the
# conversion fires ~3.2M times (prints throttled by the R1287
# per-tag governor), but under firstfault-stop EVERY pair
# dispatch site is r1179-forge-blocked (L18047/L18048 among
# them) - the serve's genuine armed answer is undeliverable by
# design. The BIOS-style pair on a REAL armed ISO answer is the
# native IRQ-context mechanism, not a forged completion.
# THIS CYCLE: (1) preserve pre; (2) R1351 - the serve sets
# g_r1351_genuine_answer=1 after priming; the conversion pair
# sites bypass the forge-block when set, dispatch once, clear
# the flag, [wgen] receipt; (3) parse gate; (4) 120s run;
# (5) census: wgen, pops, the FE1C walk, cmdtl, faults.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C328-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="6be94374b28c9f81a005522c546e39fe50dc17307e35d34481e9ed52837e1e36"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1350 tree 6be94374 - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1350 tree)"
TS=$(date +%Y%m%d_%H%M%S)
mkdir -p "patch_c328_$TS"
cp -p "$SRC" "patch_c328_$TS/runtime.c.pre"
echo "PRESERVED: patch_c328_$TS/runtime.c.pre"
python3 - <<'PYEOF'
data = open("runtime/runtime.c", "rb").read()
lines = data.split(b"\n")
# anchor A: the R1350 global comment tail (insert the R1351 global after it)
aA = b"* which never got its conversion pass. One refill unit set per serve fire. */"
hA = [i for i, l in enumerate(lines) if aA in l]
print("GLOBANCHOR count=%d (must be 1)" % len(hA))
if len(hA) != 1:
    print("PATCH-FAILED - global anchor wrong - nothing written, no run")
    raise SystemExit(0)
g0 = hA[0]
# anchor B: the wconv print line (insert the serve set after it)
aB = b"conversion pass at the next tick\\n\"); }"
hB = [i for i, l in enumerate(lines) if aB in l]
print("SERVEANCHOR count=%d (must be 1)" % len(hB))
if len(hB) != 1:
    print("PATCH-FAILED - serve anchor wrong - nothing written, no run")
    raise SystemExit(0)
s0 = hB[0]
# anchor C: the conversion pair lines (adjacent L18047/L18048)
aC = b'if (!r1179_forge_blocked("L18047")) { g_guest_depth++, xenolift_dispatch(0x800409E4u), g_guest_depth--; }'
aD = b'if (!r1179_forge_blocked("L18048")) { g_guest_depth++, xenolift_dispatch(0x80040A4Cu), g_guest_depth--; }'
hC = [i for i, l in enumerate(lines) if aC in l]
hD = [i for i, l in enumerate(lines) if aD in l]
print("PAIR47 count=%d (must be 1) PAIR48 count=%d (must be 1)" % (len(hC), len(hD)))
if len(hC) != 1 or len(hD) != 1:
    print("PATCH-FAILED - pair anchors wrong - nothing written, no run")
    raise SystemExit(0)
c0 = hC[0]
if hD[0] != c0 + 1:
    print("PATCH-FAILED - pair lines not adjacent (%d vs %d) - nothing written, no run" % (c0, hD[0]))
    raise SystemExit(0)
ws = lines[c0][:len(lines[c0]) - len(lines[c0].lstrip())]
print("LEADING_WS=%d spaces" % len(ws))
pre_checks = [(b"R1351", 0), (b"[wgen]", 0), (b"g_r1351_genuine_answer", 0),
              (b"L18047", 1), (b"L18048", 1),
              (b"R1350", 3), (b"[wconv]", 1), (b"g_r1350_conv_refill", 5),
              (b"conv_budget", 15)]
for tok, want in pre_checks:
    c = data.count(tok)
    print("PRE %s count=%d (must be %d)" % (tok.decode(), c, want))
    if c != want:
        print("PATCH-FAILED - pre-token wrong - nothing written, no run")
        raise SystemExit(0)
# insert A: the R1351 global (5 lines) after the R1350 comment tail
g_new = [
    b"uint32_t g_r1351_genuine_answer = 0; /* R1351 (c328): set by the serve after priming a",
    b" * REAL ISO answer + arming INT3. The c327 receipts: under firstfault-stop every",
    b" * pair dispatch site is forge-blocked, so a genuine armed answer is undeliverable",
    b" * by design - the BIOS-style pair on a REAL armed response is the native",
    b" * IRQ-context mechanism, not a forged completion. One-shot, cleared after use. */",
]
lines[g0+1:g0+1] = g_new
# insert B: the serve set (1 line) - indices shift +5
s0 += 5
s_new = [
    b"        g_r1351_genuine_answer = 1u; /* R1351: a real ISO answer is primed - exempt the BIOS-style pair */",
]
lines[s0+1:s0+1] = s_new
# replace C+D: the pair lines - indices shift +5+1
c0 += 6
new1 = ws + b'if (!r1179_forge_blocked("L18047") || g_r1351_genuine_answer) { g_guest_depth++, xenolift_dispatch(0x800409E4u), g_guest_depth--; } /* R1351 */'
new2 = ws + b'if (!r1179_forge_blocked("L18048") || g_r1351_genuine_answer) { g_guest_depth++, xenolift_dispatch(0x80040A4Cu), g_guest_depth--; if (g_r1351_genuine_answer) { g_r1351_genuine_answer = 0u; r861_out("[wgen] R1351 genuine-answer BIOS-style pair dispatch (serve-armed INT3) - the forge-block never meant to stop this\\n"); } } /* R1351 */'
lines[c0] = new1
lines[c0+1] = new2
post = b"\n".join(lines)
checks = [(b"R1351", 5), (b"[wgen]", 1), (b"g_r1351_genuine_answer", 6),
          (b"L18047", 1), (b"L18048", 1),
          (b"R1350", 3), (b"[wconv]", 1), (b"g_r1350_conv_refill", 5),
          (b"conv_budget", 15),
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
print("PATCH-APPLIED (R1351 genuine-answer exemption)")
PYEOF
SS2=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_SHA=$SS2"
clang -fsyntax-only -std=gnu99 "$SRC" 2>/tmp/c328_parse.txt; PRC=$?
echo "PARSE_RC=$PRC"
if [ "$PRC" != "0" ]; then echo "PARSE-FAILED - reverting"; head -8 /tmp/c328_parse.txt; cp -p "patch_c328_$TS/runtime.c.pre" "$SRC"; exit 0; fi
echo "PARSE-OK"
echo "===RUN328=== the R1351 build, 120s budget, first-fault stop"
XENOLIFT_FIRSTFAULT_STOP=1 RUN_BUDGET_S=120 bash run.sh > /tmp/run_full_c328.txt 2>&1; RRC=$?
echo "RUN_RC=$RRC"
WDIR="witness_c328_$TS"; mkdir -p "$WDIR"
for f in run.log run.log.d; do [ -f "$f" ] && cp -p "$f" "$WDIR/$f"; done
cp -p /tmp/run_full_c328.txt "$WDIR/run_full.txt"
echo "WITNESS=$WDIR"
LOG="run.log"; [ -s "$LOG" ] || LOG="run.log.d"
echo "===WSERVE328=== the serve chain receipts"
grep -n "wserve\|wopflag\|wconv\|wgen" "$LOG" | head -12
echo "===POPS328=== the pop + pendclr receipts POST-serve (the R1351 verdict)"
WS=$(grep -n "wserve" "$LOG" | head -1 | cut -d: -f1)
echo "WSERVE_LINE=$WS"
if [ -n "$WS" ]; then awk -v s="$WS" 'NR>=s && /rspop|pendclr|response consumed|interrupt acknowledged|wgen/ {print NR": "$0}' "$LOG" | head -16; fi
echo "===FE1C328=== the FE1C walk after the serve"
grep -n "\[chg\] FE1C" "$LOG" | tail -10
echo "===OUTCOME328=== cmdtl + READ ISSUED + fld2sig tail"
grep -n "cmd 02->06" "$LOG" | head -8
grep -c "READ ISSUED" "$LOG"
grep -n "fld2sig" "$LOG" | tail -3
echo "===FAULT328=== fault census"
grep -c "computed-garbage" "$LOG"
FF=$(grep -n "computed-garbage address" "$LOG" | head -1 | cut -d: -f1)
echo "FIRST_FAULT_LINE=$FF"
if [ -n "$FF" ]; then awk -v s="$((FF-6))" -v e="$((FF+6))" 'NR>=s && NR<=e' "$LOG"; fi
echo "===VIS328=== visuals + run tail"
grep -n "nonblank" "$LOG" | tail -3
tail -6 /tmp/run_full_c328.txt
grep -n "rungasp" "$LOG" | tail -2
echo "===C328DONE=== R1351 run complete - the genuine-answer verdict comes from these receipts"
