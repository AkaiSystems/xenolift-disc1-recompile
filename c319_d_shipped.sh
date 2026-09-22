#!/bin/bash
# c319_direct_delivery.sh - R1348: the proven direct delivery
# called from the watcher-side SetLoc serve.
# THE c318 PROBE VERDICT: the armed INT1 never converts at the
# tail because the native conversion (g_cd_irq_force) only
# dispatches at a WAIT TICK, and the tail RAM-poll spin produces
# no wait ticks and no FIFO reads. The tree already contains the
# PROVEN direct delivery: cd_force_deliver_int1 (handler pair +
# collector + h4; R898 defer-safe; R1181 no-forge guards inside),
# built for exactly this posture class.
# THIS CYCLE: (1) preserve pre; (2) R1348 - in r1346_serve,
# right after the armed serve, call cd_force_deliver_int1 with a
# [wforce] post-call state receipt; (3) parse gate; (4) 120s
# run; (5) census: wserve/wforce/stalecd, the FE1C walk after
# the call, ReadN/pendclr/rspop outcomes, READ ISSUED, fld2sig
# tail, faults, visuals, run tail.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C319-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="39937fd9177ee05511bd28bcc74bf9ecce83a9d0f56c28a48aa553be603725b2"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1347 tree 39937fd9 - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1347 tree)"
TS=$(date +%Y%m%d_%H%M%S)
mkdir -p "patch_c319_$TS"
cp -p "$SRC" "patch_c319_$TS/runtime.c.pre"
echo "PRESERVED: patch_c319_$TS/runtime.c.pre"
python3 - <<'PYEOF'
data = open("runtime/runtime.c", "rb").read()
lines = data.split(b"\n")
a = b"cd_seek_lba, xenolift_mem_read32(0x8004FE04u), owed);"
h = [i for i, l in enumerate(lines) if a in l]
print("ARGANCHOR count=%d (must be 1)" % len(h))
if len(h) != 1:
    print("PATCH-FAILED - arg anchor wrong - nothing written, no run")
    raise SystemExit(0)
i0 = h[0]
ok = (lines[i0+1] == b"    }") and (lines[i0+2] == b"}")
print("STRUCT_OK=%s (arg line, +1 serve-if close, +2 fn close)" % ok)
if not ok:
    print("PATCH-FAILED - boundary unexpected - nothing written, no run")
    raise SystemExit(0)
pre_force = data.count(b"cd_force_deliver_int1")
print("PRE cd_force_deliver_int1 count=%d (POST must be %d)" % (pre_force, pre_force + 1))
for tok, want in [(b"R1348", 0), (b"[wforce]", 0)]:
    c = data.count(tok)
    print("PRE %s count=%d (must be %d)" % (tok.decode(), c, want))
    if c != want:
        print("PATCH-FAILED - pre-token wrong - nothing written, no run")
        raise SystemExit(0)
new = [
    b"        /* R1348 (c319): the c317/c318 verdicts - the armed INT1",
    b"         * never converts at the tail (no wait ticks in the",
    b"         * RAM-poll spin, no FIFO reads); call the PROVEN direct",
    b"         * delivery (handler pair + collector + h4, R1181",
    b"         * no-forge guards inside decide). */",
    b'        cd_force_deliver_int1("R1348 watcher SetLoc serve");',
    b"        { static int r1348f_n; if (r1348f_n++ < 8u)",
    b'            r861_out("[wforce] R1348 direct delivery called post-serve: pend=%u resp=%u/%u fe1c=%u seek=%u\\n", (unsigned)cd_pending, (unsigned)cd_resp_pos, (unsigned)cd_resp_n, xenolift_mem_read32(0x8004FE1Cu), cd_seek_lba); }',
]
lines[i0+1:i0+1] = new
post = b"\n".join(lines)
checks = [(b"R1348", 3), (b"[wforce]", 1),
          (b"cd_force_deliver_int1", pre_force + 1),
          (b"R1347", 3), (b"[wserve]", 1), (b"R1346", 1),
          (b"r1346_serve", 3), (b"r1346_armed", 5),
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
print("PATCH-APPLIED (R1348 direct delivery from the watcher serve)")
PYEOF
SS2=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_SHA=$SS2"
clang -fsyntax-only -std=gnu99 "$SRC" 2>/tmp/c319_parse.txt; PRC=$?
echo "PARSE_RC=$PRC"
if [ "$PRC" != "0" ]; then echo "PARSE-FAILED - reverting"; head -8 /tmp/c319_parse.txt; cp -p "patch_c319_$TS/runtime.c.pre" "$SRC"; exit 0; fi
echo "PARSE-OK"
echo "===RUN319=== the R1348 build, 120s budget, first-fault stop"
XENOLIFT_FIRSTFAULT_STOP=1 RUN_BUDGET_S=120 bash run.sh > /tmp/run_full_c319.txt 2>&1; RRC=$?
echo "RUN_RC=$RRC"
WDIR="witness_c319_$TS"; mkdir -p "$WDIR"
for f in run.log run.log.d; do [ -f "$f" ] && cp -p "$f" "$WDIR/$f"; done
cp -p /tmp/run_full_c319.txt "$WDIR/run_full.txt"
echo "WITNESS=$WDIR"
LOG="run.log"; [ -s "$LOG" ] || LOG="run.log.d"
echo "===WSERVE319=== the serve + direct delivery receipts"
grep -n "wserve\|wforce" "$LOG" | head -14
grep -n "stalecd\] R13" "$LOG" | head -8
echo "===FE1C319=== the FE1C walk after the delivery"
grep -n "\[chg\] FE1C" "$LOG" | tail -16
echo "===OUTCOME319=== ReadN + pendclr + rspop after the delivery"
grep -n "cmd 02->06" "$LOG" | head -8
grep -n "pendclr" "$LOG" | tail -8
grep -n "rspop" "$LOG" | tail -8
echo "===FLOW319=== READ ISSUED + fld2sig tail"
grep -c "READ ISSUED" "$LOG"
grep -n "fld2sig" "$LOG" | tail -4
echo "===FAULT319=== fault census"
grep -c "computed-garbage" "$LOG"
FF=$(grep -n "computed-garbage address" "$LOG" | head -1 | cut -d: -f1)
echo "FIRST_FAULT_LINE=$FF"
if [ -n "$FF" ]; then awk -v s="$((FF-6))" -v e="$((FF+6))" 'NR>=s && NR<=e' "$LOG"; fi
echo "===VIS319=== visuals + run tail"
grep -n "nonblank" "$LOG" | tail -3
tail -6 /tmp/run_full_c319.txt
grep -n "rungasp" "$LOG" | tail -2
echo "===C319DONE=== R1348 run complete - the delivery verdict comes from these receipts"
