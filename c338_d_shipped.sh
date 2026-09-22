#!/bin/bash
# c338_flagpersist.sh - R1357: revert the pend term, make the
# genuine-answer flag persistent.
# THE c337 CONVICTION: pend!=0 is NEAR-UNIVERSAL (boot AND
# pass-3 eras both sit at pend=3) - the posture gate over-fired
# in the boot era and the run regressed to the 108754 wedge,
# exiting via the door twice, never reaching the ReadN.
# THIS CYCLE: (1) preserve pre; (2) R1357 - the break reverts
# to flag-based; the slots-drained exit clears the flag ONLY
# when cd_pending==0u (holding receipt otherwise); (3) parse
# gate; (4) 120s run; (5) census: the ReadN INT3 consumption.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C338-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="499a90e5bd61260d881c8346a75a3931d0de437936b48a5226edc40375eac52b"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1356 tree 499a90e5 - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1356 tree)"
TS=$(date +%Y%m%d_%H%M%S)
mkdir -p "patch_c338_$TS"
cp -p "$SRC" "patch_c338_$TS/runtime.c.pre"
echo "PRESERVED: patch_c338_$TS/runtime.c.pre"
python3 - <<'PYEOF'
data = open("runtime/runtime.c", "rb").read()
pre_checks = [(b"R1357", 0), (b"if (r1179_forge_blocked(\"L18405\") && !g_r1351_genuine_answer && cd_pending == 0u) break;", 1),
              (b"cd_pending == 0u) break;", 1),
              (b"g_r1351_genuine_answer) { g_r1351_genuine_answer = 0u; r861_out(\"[wgen] R1355 genuine-answer collector pass complete (slots drained)", 1),
              (b"R1355", 3), (b"R1356", 1), (b"[wgen]", 2), (b"g_r1351_genuine_answer", 6), (b"L18405", 1)]
for tok, want in pre_checks:
    c = data.count(tok)
    print("PRE %s count=%d (must be %d)" % (tok.decode()[:64], c, want))
    if c != want:
        print("PATCH-FAILED - pre-token wrong - nothing written, no run")
        raise SystemExit(0)
lines = data.split(b"\n")
# site 1: the break line (full-line replace, no surviving-comment hazard)
h1 = [i for i, l in enumerate(lines) if b"cd_pending == 0u) break;" in l]
print("BREAKLINE count=%d (must be 1)" % len(h1))
if len(h1) != 1:
    print("PATCH-FAILED - break anchor wrong - nothing written, no run")
    raise SystemExit(0)
ws1 = lines[h1[0]][:len(lines[h1[0]]) - len(lines[h1[0]].lstrip())]
lines[h1[0]] = ws1 + b'if (r1179_forge_blocked("L18405") && !g_r1351_genuine_answer) break; /* R1355 (c334) + R1356 (c337) + R1357 (c338): genuine-answer exemption; the c337 pend term REVERTED (pend=3 is near-universal, it over-fired in the boot era); the flag now persists while a pending answer is outstanding, cleared in the slots-drain exit only when no pending remains */'
# site 2: the slots-drained clear (full-line replace)
h2 = [i for i, l in enumerate(lines) if b"g_r1351_genuine_answer) { g_r1351_genuine_answer = 0u; r861_out(\"[wgen] R1355 genuine-answer collector pass complete (slots drained)" in l]
print("SLOTSLINE count=%d (must be 1)" % len(h2))
if len(h2) != 1:
    print("PATCH-FAILED - slots anchor wrong - nothing written, no run")
    raise SystemExit(0)
ws2 = lines[h2[0]][:len(lines[h2[0]]) - len(lines[h2[0]].lstrip())]
lines[h2[0]] = ws2 + b'if (g_r1351_genuine_answer) { if (cd_pending == 0u) { g_r1351_genuine_answer = 0u; r861_out("[wgen] R1357 genuine-answer collector pass complete (slots drained, no pending outstanding)\\n"); } else { r861_out("[wgen] R1357 genuine-answer collector holding - pending outstanding\\n"); } } /* R1355 + R1357 */'
post = b"\n".join(lines)
checks = [(b"R1357", 4), (b"R1356", 1), (b"R1355", 2),
          (b"cd_pending == 0u) break;", 0),
          (b"if (r1179_forge_blocked(\"L18405\") && !g_r1351_genuine_answer) break;", 1),
          (b"L18405", 1), (b"[wgen]", 3), (b"g_r1351_genuine_answer", 6),
          (b"[wpair]", 2), (b"R1351", 4), (b"R1353", 4), (b"R1354", 2),
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
    print("POST %s count=%d (must be %d)" % (tok.decode()[:64], c, want))
    if c != want:
        print("PATCH-FAILED - post-token wrong - nothing written, no run")
        raise SystemExit(0)
open("runtime/runtime.c", "wb").write(post)
print("PATCH-APPLIED (R1357 flag-persistent collector exemption)")
PYEOF
SS2=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_SHA=$SS2"
clang -fsyntax-only -std=gnu99 "$SRC" 2>/tmp/c338_parse.txt; PRC=$?
echo "PARSE_RC=$PRC"
if [ "$PRC" != "0" ]; then echo "PARSE-FAILED - reverting"; head -8 /tmp/c338_parse.txt; cp -p "patch_c338_$TS/runtime.c.pre" "$SRC"; exit 0; fi
echo "PARSE-OK"
echo "===RUN338=== the R1357 build, 120s budget, first-fault stop"
XENOLIFT_FIRSTFAULT_STOP=1 RUN_BUDGET_S=120 bash run.sh > /tmp/run_full_c338.txt 2>&1; RRC=$?
echo "RUN_RC=$RRC"
WDIR="witness_c338_$TS"; mkdir -p "$WDIR"
for f in run.log run.log.d; do [ -f "$f" ] && cp -p "$f" "$WDIR/$f"; done
cp -p /tmp/run_full_c338.txt "$WDIR/run_full.txt"
echo "WITNESS=$WDIR"
LOG="run.log"; [ -s "$LOG" ] || LOG="run.log.d"
echo "===DEEP338=== the deep-run restore check"
grep -n "rungasp" "$LOG" | tail -2
grep -n "cmdtl" "$LOG" | tail -4
echo "===READN338=== the ReadN INT3 consumption (the R1357 verdict)"
RN=$(grep -n "STREAM-ARM (ReadN)" "$LOG" | tail -1 | cut -d: -f1)
echo "STREAMARM_LINE=$RN"
if [ -n "$RN" ]; then awk -v s="$RN" -v e="$((RN+140))" 'NR>=s && NR<=e && /rspop|pendclr|response consumed|interrupt acknowledged|wait-loop event|wgen|chg\] FE1C|sector|fld-int1/ {print NR": "$0}' "$LOG" | head -30; fi
echo "===POPS338=== tail census post-ReadN"
if [ -n "$RN" ]; then
  for TAG in "rspop" "pendclr" "response consumed" "interrupt acknowledged" "fld-int1" "sector"; do
    C=$(awk -v s="$RN" 'NR>=s' "$LOG" | grep -c "$TAG")
    echo "TAIL_COUNT[$TAG]=$C"
  done
fi
echo "===FE1C338=== the FE1C walk after the serve"
grep -n "\[chg\] FE1C" "$LOG" | tail -8
echo "===OUTCOME338=== data posture + mvloop"
grep -n "fld2sig" "$LOG" | tail -3
grep -n "mvloop" "$LOG" | tail -2
echo "===FAULT338=== fault census"
grep -c "computed-garbage" "$LOG"
FF=$(grep -n "computed-garbage address" "$LOG" | head -1 | cut -d: -f1)
echo "FIRST_FAULT_LINE=$FF"
if [ -n "$FF" ]; then awk -v s="$((FF-6))" -v e="$((FF+6))" 'NR>=s && NR<=e' "$LOG"; fi
echo "===VIS338=== gpu census"
grep -n "gpufin\|gp0_words" "$LOG" | tail -2
echo "===C338DONE=== R1357 run complete - the flag-persistence verdict comes from these receipts"
