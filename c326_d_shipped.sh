#!/bin/bash
# c326_convrefill.sh - R1350: the conversion-budget refill from
# the watcher serve.
# THE c325 VERDICT: the tick's conversion block HANDLES pend=3
# (cd_restore_pend + handler pair + R471 drain) but its static
# 100000 conv_budget EXHAUSTED at ~L25092 - the conversions ran
# on the STALE FIFO era, died, and THEN the serve primed the
# CORRECT answer at 25455: the answer never got its conversion
# pass. Proven by elimination: the body runs at the tail
# (camera 22540 fires past the block), pend=3 arm1=0 receipted.
# THIS CYCLE: (1) preserve pre; (2) R1350 - file-scope
# g_r1350_conv_refill global (set 1000 by the serve post-arm)
# + the tick refill check at conv_budget + [wconv] receipt;
# (3) parse gate; (4) 120s run; (5) census: the conversion
# receipts POST-serve, pops, the FE1C walk, cmdtl, faults.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C326-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="b471baaf00efd956add94db8bba2ade1e7e3e8c3b01897e3cfcd0a83154217b5"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1349 tree b471baaf - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1349 tree)"
TS=$(date +%Y%m%d_%H%M%S)
mkdir -p "patch_c326_$TS"
cp -p "$SRC" "patch_c326_$TS/runtime.c.pre"
echo "PRESERVED: patch_c326_$TS/runtime.c.pre"
python3 - <<'PYEOF'
data = open("runtime/runtime.c", "rb").read()
lines = data.split(b"\n")
# anchor 1: the global definition site (top-of-file, before first use)
a1 = b"uint32_t g_r1194_wedge_streak = 0;"
h1 = [i for i, l in enumerate(lines) if a1 in l]
print("GLOBANCHOR count=%d (must be 1)" % len(h1))
if len(h1) != 1:
    print("PATCH-FAILED - global anchor wrong - nothing written, no run")
    raise SystemExit(0)
g0 = h1[0]
# anchor 2: the serve's wopflag receipt tail (insert the refill request after it)
a2 = b"(unsigned)cd_pending, (unsigned)cd_resp_pos, (unsigned)cd_resp_n, xenolift_mem_read32(0x8004FE1Cu), cd_seek_lba); } }"
h2 = [i for i, l in enumerate(lines) if a2 in l]
print("SERVEANCHOR count=%d (must be 1)" % len(h2))
if len(h2) != 1:
    print("PATCH-FAILED - serve anchor wrong - nothing written, no run")
    raise SystemExit(0)
s0 = h2[0]
# anchor 3: the tick's conv_budget definition line
a3 = b"        static int conv_budget = 100000;"
h3 = [i for i, l in enumerate(lines) if a3 in l]
print("TICKANCHOR count=%d (must be 1)" % len(h3))
if len(h3) != 1:
    print("PATCH-FAILED - tick anchor wrong - nothing written, no run")
    raise SystemExit(0)
t0 = h3[0]
ok = (lines[t0+1] == b"        if (cd_pending != 0u && cd_arm_int1_pending == 0 && conv_budget > 0) {")
print("TICKSTRUCT_OK=%s (+1 is the conversion if)" % ok)
if not ok:
    print("PATCH-FAILED - tick boundary unexpected - nothing written, no run")
    raise SystemExit(0)
pre_cb = data.count(b"conv_budget")
print("PRE conv_budget count=%d (POST must be %d)" % (pre_cb, pre_cb + 1))
for tok, want in [(b"R1350", 0), (b"[wconv]", 0), (b"g_r1350_conv_refill", 0)]:
    c = data.count(tok)
    print("PRE %s count=%d (must be %d)" % (tok.decode(), c, want))
    if c != want:
        print("PATCH-FAILED - pre-token wrong - nothing written, no run")
        raise SystemExit(0)
# insert 1: the global after g_r1194_wedge_streak
g_new = [
    b"uint32_t g_r1350_conv_refill = 0; /* R1350 (c326): >0 = the watcher serve asks the",
    b" * tick's stuck-INT conversion block to refill its budget. The c325 receipts:",
    b" * the conversion ran on the STALE 1-byte FIFO era until the static 100000",
    b" * budget died (~L25092), the serve then primed the CORRECT 3-byte answer -",
    b" * which never got its conversion pass. One refill unit set per serve fire. */",
]
lines[g0+1:g0+1] = g_new
# insert 2: the serve's refill request (indices after insert 1 shift by 5)
s0 += 5
s_new = [
    b"        g_r1350_conv_refill = 1000u;",
    b"        { static int r1350_n; if (r1350_n++ < 8u)",
    b'            r861_out("[wconv] R1350 conversion-budget refill requested (1000) - the serve answer gets its conversion pass at the next tick\\n"); }',
]
lines[s0+1:s0+1] = s_new
# insert 3: the tick's refill check (indices shift again by 5+3=8 from g0)
t0 += 8
t_new = [
    b"        if (g_r1350_conv_refill) { conv_budget += (int)g_r1350_conv_refill; g_r1350_conv_refill = 0; } /* R1350 */",
]
lines[t0+1:t0+1] = t_new
post = b"\n".join(lines)
checks = [(b"R1350", 3), (b"[wconv]", 1), (b"g_r1350_conv_refill", 5),
          (b"conv_budget", pre_cb + 1),
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
print("PATCH-APPLIED (R1350 conversion-budget refill)")
PYEOF
SS2=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_SHA=$SS2"
clang -fsyntax-only -std=gnu99 "$SRC" 2>/tmp/c326_parse.txt; PRC=$?
echo "PARSE_RC=$PRC"
if [ "$PRC" != "0" ]; then echo "PARSE-FAILED - reverting"; head -8 /tmp/c326_parse.txt; cp -p "patch_c326_$TS/runtime.c.pre" "$SRC"; exit 0; fi
echo "PARSE-OK"
echo "===RUN326=== the R1350 build, 120s budget, first-fault stop"
XENOLIFT_FIRSTFAULT_STOP=1 RUN_BUDGET_S=120 bash run.sh > /tmp/run_full_c326.txt 2>&1; RRC=$?
echo "RUN_RC=$RRC"
WDIR="witness_c326_$TS"; mkdir -p "$WDIR"
for f in run.log run.log.d; do [ -f "$f" ] && cp -p "$f" "$WDIR/$f"; done
cp -p /tmp/run_full_c326.txt "$WDIR/run_full.txt"
echo "WITNESS=$WDIR"
LOG="run.log"; [ -s "$LOG" ] || LOG="run.log.d"
echo "===WSERVE326=== the serve + refill receipts"
grep -n "wconv\|wserve\|wopflag" "$LOG" | head -12
echo "===CONV326=== the conversion receipts POST-serve (the R1350 verdict)"
WS=$(grep -n "wserve" "$LOG" | head -1 | cut -d: -f1)
echo "WSERVE_LINE=$WS"
if [ -n "$WS" ]; then awk -v s="$WS" 'NR>=s && /converting stuck|fd-tick: conv|handler pair|wconv/ {print NR": "$0}' "$LOG" | head -16; fi
echo "===POPS326=== rspop + pendclr + response consumed POST-serve"
if [ -n "$WS" ]; then awk -v s="$WS" 'NR>=s && /rspop|pendclr|response consumed|interrupt acknowledged/ {print NR": "$0}' "$LOG" | head -14; fi
echo "===FE1C326=== the FE1C walk after the serve"
grep -n "\[chg\] FE1C" "$LOG" | tail -12
echo "===OUTCOME326=== cmdtl + READ ISSUED + fld2sig tail"
grep -n "cmd 02->06" "$LOG" | head -8
grep -c "READ ISSUED" "$LOG"
grep -n "fld2sig" "$LOG" | tail -3
echo "===FAULT326=== fault census"
grep -c "computed-garbage" "$LOG"
FF=$(grep -n "computed-garbage address" "$LOG" | head -1 | cut -d: -f1)
echo "FIRST_FAULT_LINE=$FF"
if [ -n "$FF" ]; then awk -v s="$((FF-6))" -v e="$((FF+6))" 'NR>=s && NR<=e' "$LOG"; fi
echo "===VIS326=== visuals + run tail"
grep -n "nonblank" "$LOG" | tail -3
tail -6 /tmp/run_full_c326.txt
grep -n "rungasp" "$LOG" | tail -2
echo "===C326DONE=== R1350 run complete - the refill verdict comes from these receipts"
