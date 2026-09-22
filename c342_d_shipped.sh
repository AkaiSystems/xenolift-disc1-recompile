#!/bin/bash
# c342_epochidle3.sh - R1358 reship 2: epoch-idle flag clear with
# corrected marker gates (POST R1357=2: the old slots line
# carries THREE R1357 tokens - receipts plus comment).
# THE c339 GATE-FAIL: the PRE gate anchored the GENERIC token
# `cd_pending == 0u` (60 occurrences tree-wide) - only unique
# lines or patch-introduced strings are safe gate anchors.
# THE c338 CONVICTION STANDS: the SetLoc drain fires while pend
# is 0, before the ReadN's INT3 arms - the epoch boundary is
# the kernel's own idle return (FE1C==0), not pend==0-at-drain.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C342-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="5d0fa5873e625e3691ae266b5e62fb78d999d73453bc59e5b08fac667059c7bd"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1357 tree 5d0fa587 - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1357 tree)"
TS=$(date +%Y%m%d_%H%M%S)
mkdir -p "patch_c342_$TS"
cp -p "$SRC" "patch_c342_$TS/runtime.c.pre"
echo "PRESERVED: patch_c342_$TS/runtime.c.pre"
python3 - <<'PYEOF'
data = open("runtime/runtime.c", "rb").read()
pre_checks = [(b"R1358", 0),
              (b"R1357 genuine-answer collector pass complete (slots drained, no pending outstanding)", 1),
              (b"R1357", 4), (b"R1355", 2), (b"[wgen]", 3),
              (b"g_r1351_genuine_answer", 6), (b"L18405", 1),
              (b"if (r1179_forge_blocked(\"L18405\") && !g_r1351_genuine_answer) break;", 1)]
for tok, want in pre_checks:
    c = data.count(tok)
    print("PRE %s count=%d (must be %d)" % (tok.decode()[:64], c, want))
    if c != want:
        print("PATCH-FAILED - pre-token wrong - nothing written, no run")
        raise SystemExit(0)
lines = data.split(b"\n")
h = [i for i, l in enumerate(lines) if b"R1357 genuine-answer collector pass complete (slots drained, no pending outstanding)" in l]
print("SLOTSLINE count=%d (must be 1)" % len(h))
if len(h) != 1:
    print("PATCH-FAILED - slots anchor wrong - nothing written, no run")
    raise SystemExit(0)
ws = lines[h[0]][:len(lines[h[0]]) - len(lines[h[0]].lstrip())]
lines[h[0]] = ws + b'if (g_r1351_genuine_answer) { if (cd_pending == 0u && xenolift_mem_read32(0x8004FE1Cu) == 0u) { g_r1351_genuine_answer = 0u; r861_out("[wgen] R1358 genuine-answer collector pass complete (slots drained, idle, no pending outstanding)\\n"); } else { static int r1358h_n; if (r1358h_n++ < 12u) r861_out("[wgen] R1358 genuine-answer collector holding (pending=%u FE1C=%08X)\\n", (unsigned)cd_pending, xenolift_mem_read32(0x8004FE1Cu)); } } /* R1355 + R1357 + R1358 */'
post = b"\n".join(lines)
checks = [(b"R1358", 3), (b"R1357", 2), (b"R1355", 2), (b"[wgen]", 3),
          (b"g_r1351_genuine_answer", 6), (b"L18405", 1),
          (b"cd_pending == 0u && xenolift_mem_read32(0x8004FE1Cu) == 0u", 1),
          (b"r1358h_n", 2),
          (b"if (r1179_forge_blocked(\"L18405\") && !g_r1351_genuine_answer) break;", 1),
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
print("PATCH-APPLIED (R1358 epoch-idle flag clear, c342 reship)")
PYEOF
SS2=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_SHA=$SS2"
clang -fsyntax-only -std=gnu99 "$SRC" 2>/tmp/c342_parse.txt; PRC=$?
echo "PARSE_RC=$PRC"
if [ "$PRC" != "0" ]; then echo "PARSE-FAILED - reverting"; head -8 /tmp/c342_parse.txt; cp -p "patch_c342_$TS/runtime.c.pre" "$SRC"; exit 0; fi
echo "PARSE-OK"
echo "===RUN341=== the R1358 build, 120s budget, first-fault stop"
XENOLIFT_FIRSTFAULT_STOP=1 RUN_BUDGET_S=120 bash run.sh > /tmp/run_full_c342.txt 2>&1; RRC=$?
echo "RUN_RC=$RRC"
WDIR="witness_c342_$TS"; mkdir -p "$WDIR"
for f in run.log run.log.d; do [ -f "$f" ] && cp -p "$f" "$WDIR/$f"; done
cp -p /tmp/run_full_c342.txt "$WDIR/run_full.txt"
echo "WITNESS=$WDIR"
LOG="run.log"; [ -s "$LOG" ] || LOG="run.log.d"
echo "===HOLD341=== the holding receipts (the R1358 epoch evidence)"
grep -n "R1358" "$LOG" | head -16
echo "===READN341=== the ReadN INT3 consumption (the R1358 verdict)"
RN=$(grep -n "STREAM-ARM (ReadN)" "$LOG" | tail -1 | cut -d: -f1)
echo "STREAMARM_LINE=$RN"
if [ -n "$RN" ]; then awk -v s="$RN" -v e="$((RN+160))" 'NR>=s && NR<=e && /rspop|pendclr|response consumed|interrupt acknowledged|wait-loop event|wgen|chg\] FE1C|sector|fld-int1|holding|pass complete/ {print NR": "$0}' "$LOG" | head -32; fi
echo "===POPS341=== tail census post-ReadN"
if [ -n "$RN" ]; then
  for TAG in "rspop" "pendclr" "response consumed" "interrupt acknowledged" "fld-int1" "sector"; do
    C=$(awk -v s="$RN" 'NR>=s' "$LOG" | grep -c "$TAG")
    echo "TAIL_COUNT[$TAG]=$C"
  done
fi
echo "===FE1C342=== the FE1C walk after the serve"
grep -n "\[chg\] FE1C" "$LOG" | tail -10
echo "===OUTCOME341=== cmdtl + data posture + mvloop"
grep -n "cmdtl" "$LOG" | tail -4
grep -n "fld2sig" "$LOG" | tail -3
grep -n "mvloop" "$LOG" | tail -2
echo "===FAULT341=== fault census"
grep -c "computed-garbage" "$LOG"
FF=$(grep -n "computed-garbage address" "$LOG" | head -1 | cut -d: -f1)
echo "FIRST_FAULT_LINE=$FF"
if [ -n "$FF" ]; then awk -v s="$((FF-6))" -v e="$((FF+6))" 'NR>=s && NR<=e' "$LOG"; fi
echo "===VIS341=== run tail + gpu census"
grep -n "rungasp" "$LOG" | tail -2
grep -n "gpufin\|gp0_words" "$LOG" | tail -2
echo "===C342DONE=== R1358 run complete - the epoch-idle verdict comes from these receipts"
