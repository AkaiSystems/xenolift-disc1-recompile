#!/bin/bash
# c311_decline_receipt.sh - R1342: the decline receipt at the
# R1341 discard site (cameras-only, NO behavior change).
# THE c310 VERDICT: R1341 PARTIAL PASS - the discard unblocked
# the boot Setloc (108754 discard + v4 serve + the first full
# FE1C walks, re-read passes 1-2 completed through ReadN at
# 108933 + pause at 108995); but the pass-3 Setloc wait persists
# (cmd=02 FE1C=1 pend=3 data=0/2060 act=0) with NO discard fire
# - either the enclosing status-poll path never runs in that
# era or a model counter differs from what fld2sig prints.
# THIS CYCLE: (1) preserve the pre tree; (2) R1342 - add the
# decline receipt block inside the assist outer if (print
# pending/data_n/read_active/resp_n/seek/FE04/fe1c once per
# hold when FE1C==1 && cmd==02, cap 8); (3) parse gate; (4)
# 120s run under XENOLIFT_FIRSTFAULT_STOP=1; (5) census: the
# stalecd + stalecd-near receipts, pass-3 cmdtl uncapped, FE1C
# chg tail, cdw02, fld-int1, READ ISSUED, FDF8 tail, faults,
# visuals, run tail.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C311-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="da3918d9440f61511d1306491f08eb4c2421d5ae876eb5a7978f2e6a2857f4c5"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1341 tree da3918d9 - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1341 tree)"
TS=$(date +%Y%m%d_%H%M%S)
mkdir -p "patch_c311_$TS"
cp -p "$SRC" "patch_c311_$TS/runtime.c.pre"
echo "PRESERVED: patch_c311_$TS/runtime.c.pre"
python3 - <<'PYEOF'
data = open("runtime/runtime.c", "rb").read()
lines = data.split(b"\n")
anchor = b"static int fassist_budget = 400;"
hits = [i for i, l in enumerate(lines) if anchor in l]
print("ANCHOR count=%d (must be 1)" % len(hits))
if len(hits) != 1:
    print("PATCH-FAILED - anchor count wrong - nothing written, no run")
    raise SystemExit(0)
i = hits[0]
line = lines[i]
ind = line[:len(line) - len(line.lstrip())]
I = ind + b"    "
block_lines = [
    I + b"/* R1342 (c311): DECLINE receipt at the R1341 discard site -",
    I + b" * cameras-only, no behavior change. The c310 run left the",
    I + b" * pass-3 Setloc wait (FE1C=1, cmd=02) un-served with no",
    I + b" * discard fire; print the exact model state each hold so",
    I + b" * the refusing term - or the never-reached path - is",
    I + b" * receipted. */",
    I + b"{",
    I + b"    uint32_t fe1c_q = ((uint32_t)xenolift_mem[0x4FE1Cu]) | ((uint32_t)xenolift_mem[0x4FE1Du] << 8);",
    I + b"    if (fe1c_q == 1u && cd_last_cmd == 0x02u) {",
    I + b"        static int r1342_n;",
    I + b"        if (r1342_n++ < 8u)",
    I + b"            r861_out(\"[stalecd-near] R1342 SetLoc-wait model state: pending=%u data_n=%u read_active=%u resp_n=%u seek=%u FE04=%08X fe1c=%u\\n\",",
    I + b"                    cd_pending, cd_data_n, (unsigned)cd_read_active, cd_resp_n, cd_seek_lba,",
    I + b"                    xenolift_mem_read32(0x8004FE04u), fe1c_q);",
    I + b"    }",
    I + b"}",
]
pre_checks = [(b"R1342", 0), (b"[stalecd-near]", 0)]
for tok, want in pre_checks:
    c = data.count(tok)
    print("PRE %s count=%d (must be %d)" % (tok.decode(), c, want))
    if c != want:
        print("PATCH-FAILED - pre-token wrong - nothing written, no run")
        raise SystemExit(0)
lines[i:i] = block_lines
post = b"\n".join(lines)
checks = [(b"R1342", 2), (b"[stalecd-near]", 1),
          (b"stalecd-near] R1342 SetLoc-wait model state", 1),
          (b"static int fassist_budget = 400;", 1)]
for tok, want in checks:
    c = post.count(tok)
    print("POST %s count=%d (must be %d)" % (tok.decode(), c, want))
    if c != want:
        print("PATCH-FAILED - post-token wrong - nothing written, no run")
        raise SystemExit(0)
open("runtime/runtime.c", "wb").write(post)
print("PATCH-APPLIED (R1342 decline receipt, cameras-only)")
PYEOF
SS2=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_SHA=$SS2"
clang -fsyntax-only -std=gnu99 "$SRC" 2>/tmp/c311_parse.txt; PRC=$?
echo "PARSE_RC=$PRC"
if [ "$PRC" != "0" ]; then echo "PARSE-FAILED - reverting"; head -5 /tmp/c311_parse.txt; cp -p "patch_c311_$TS/runtime.c.pre" "$SRC"; exit 0; fi
echo "PARSE-OK"
echo "===RUN311=== the R1342 build, 120s budget, first-fault stop"
XENOLIFT_FIRSTFAULT_STOP=1 RUN_BUDGET_S=120 bash run.sh > /tmp/run_full_c311.txt 2>&1; RRC=$?
echo "RUN_RC=$RRC"
WDIR="witness_c311_$TS"; mkdir -p "$WDIR"
for f in run.log run.log.d; do [ -f "$f" ] && cp -p "$f" "$WDIR/$f"; done
cp -p /tmp/run_full_c311.txt "$WDIR/run_full.txt"
echo "WITNESS=$WDIR"
LOG="run.log"; [ -s "$LOG" ] || LOG="run.log.d"
echo "===NEAR311=== the decline receipts (the model state at the Setloc waits)"
grep -n "stalecd" "$LOG" | head -20
echo "===PASS3311=== the pass-3 story (uncapped cmdtl + FE1C tail + cdw02 + fld-int1)"
grep -n "cmd 02->06" "$LOG" | head -12
grep -n "\[chg\] FE1C" "$LOG" | tail -12
grep -n "cdw02" "$LOG" | tail -8
grep -n "fld-int1" "$LOG" | tail -6
echo "===FLOW311=== READ ISSUED + FDF8 tail"
grep -n "READ ISSUED" "$LOG"
grep -n "fld2sig" "$LOG" | tail -4
echo "===FAULT311=== fault census"
grep -c "computed-garbage" "$LOG"
FF=$(grep -n "computed-garbage address" "$LOG" | head -1 | cut -d: -f1)
echo "FIRST_FAULT_LINE=$FF"
if [ -n "$FF" ]; then awk -v s="$((FF-6))" -v e="$((FF+6))" 'NR>=s && NR<=e' "$LOG"; fi
echo "===VIS311=== visuals + run tail"
grep -n "nonblank" "$LOG" | tail -3
tail -6 /tmp/run_full_c311.txt
grep -n "rungasp" "$LOG" | tail -2
echo "===C311DONE=== R1342 run complete - the decline receipt names the refusing term or the never-reached path"
