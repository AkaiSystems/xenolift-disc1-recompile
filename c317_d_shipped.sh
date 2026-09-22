#!/bin/bash
# c317_armed_guard.sh - R1347: the watcher-side SetLoc serve v2
# (the armed guard).
# THE c316 VERDICT: the serve FIRED at the tail and receipted the
# true model state (pending=3, data_n=2060, seek==FE04, no seek
# mismatch; the status-poll path proven dead in the tail era) -
# but the discard SELF-CANNIBALIZED on the next tick: the serve's
# own armed pending=3 matched the discard's leftover terms and was
# cleared before the fd-tick conversion could act.
# THIS CYCLE: (1) preserve pre; (2) R1347 - replace r1346_serve
# with v2: r1346_armed set at serve, reset when FE1C leaves 1,
# the discard skips the armed state; (3) parse gate; (4) 120s run;
# (5) census: wserve/stalecd receipts, pendclr + rspop (the
# conversion outcome), FE1C walk, ReadN, READ ISSUED, fld2sig
# tail, faults, visuals, run tail.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C317-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="1868efadb50c88f974453841b51942e2612bc7f17c9f175f1c4afb0fdd9c95c3"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1346 tree 1868efad - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1346 tree)"
TS=$(date +%Y%m%d_%H%M%S)
mkdir -p "patch_c317_$TS"
cp -p "$SRC" "patch_c317_$TS/runtime.c.pre"
echo "PRESERVED: patch_c317_$TS/runtime.c.pre"
python3 - <<'PYEOF'
data = open("runtime/runtime.c", "rb").read()
lines = data.split(b"\n")
c0 = b"/* R1346 (c316): the watcher-side SetLoc serve, factored to file"
h = [i for i, l in enumerate(lines) if c0 in l]
print("FNANCHOR count=%d (must be 1)" % len(h))
if len(h) != 1:
    print("PATCH-FAILED - function anchor wrong - nothing written, no run")
    raise SystemExit(0)
i0 = h[0]
ok = True
if b"static void r1346_serve(void)" not in lines[i0+10]: ok = False
if lines[i0+11].strip() != b"{": ok = False
if lines[i0+37].strip() != b"}": ok = False
if lines[i0+38].strip() != b"": ok = False
if b"iso_resolve" not in lines[i0+39]: ok = False
print("FNSTRUCT_OK=%s (5-point: +10 sig, +11 open, +37 close, +38 blank, +39 iso anchor)" % ok)
if not ok:
    print("PATCH-FAILED - function boundary unexpected - nothing written, no run")
    raise SystemExit(0)
for tok, want in [(b"R1347", 0), (b"r1346_armed", 0)]:
    c = data.count(tok)
    print("PRE %s count=%d (must be %d)" % (tok.decode(), c, want))
    if c != want:
        print("PATCH-FAILED - pre-token wrong - nothing written, no run")
        raise SystemExit(0)
v2 = [
    b"/* R1347 (c317): the watcher-side SetLoc serve v2. The c316 receipts:",
    b" * the serve FIRED at the tail (stale pending=3 + data_n=2060",
    b" * discarded, 3-byte answer primed, INT1 armed - the tail model",
    b" * state at last receipted: seek==FE04, NO seek mismatch; the",
    b" * status-poll path is proven dead in the tail era, so the",
    b" * watcher is the right site). BUT the discard SELF-CANNIBALIZED",
    b" * on the next tick: the serve's own armed pending=3 matched the",
    b" * discard's leftover terms and was cleared before conversion.",
    b" * v2 adds the armed guard: r1346_armed set at serve, reset when",
    b" * FE1C leaves 1; the discard skips the armed state. */",
    b"static void r1346_serve(void)",
    b"{",
    b"    static int r1346_armed;",
    b"    uint32_t fe1c_w = ((uint32_t)xenolift_mem[0x4FE1Cu]) | ((uint32_t)xenolift_mem[0x4FE1Du] << 8);",
    b"    uint32_t owed = xenolift_mem_read32(0x8004FDF8u);",
    b"    if (fe1c_w != 1u) {",
    b"        r1346_armed = 0;",
    b"        return;",
    b"    }",
    b"    if (!(cd_last_cmd == 0x02u && !cd_read_active && owed != 0u))",
    b"        return;",
    b"    if (!r1346_armed && (cd_pending != 0u || cd_data_n != 0u)) {",
    b"        static int r1346d_n;",
    b"        if (r1346d_n++ < 8u)",
    b'            r861_out("[stalecd] R1347 watcher-side stale discard: pending=%u data_n=%u resp_n=%u seek=%u FE04=%08X\\n",',
    b"                    cd_pending, cd_data_n, cd_resp_n, cd_seek_lba,",
    b"                    xenolift_mem_read32(0x8004FE04u));",
    b"        cd_pending = 0u;",
    b"        cd_data_pos = 0u; cd_data_n = 0u; cd_data_loaded = 0u;",
    b"    }",
    b"    if (cd_resp_n < 3u && cd_pending == 0u) {",
    b"        static int r1346p_n;",
    b"        cd_resp[0] = 0x02u; cd_resp[1] = 0x01u; cd_resp[2] = 0x01u;",
    b"        cd_resp_n = 3u; cd_resp_pos = 0u;",
    b"        memcpy(cd_last_full, cd_resp, sizeof cd_resp);",
    b"        cd_last_full_n = 3u;",
    b"        cd_pending = 3u;",
    b"        r1346_armed = 1;",
    b"        if (r1346p_n++ < 8u)",
    b'            r861_out("[wserve] R1347 watcher-side SetLoc serve: 3-byte answer primed + INT1 armed (seek=%u FE04=%08X owes=%08X)\\n",',
    b"                    cd_seek_lba, xenolift_mem_read32(0x8004FE04u), owed);",
    b"    }",
    b"}",
]
lines[i0:i0+38] = v2
post = b"\n".join(lines)
checks = [(b"R1347", 3), (b"[wserve]", 1), (b"R1347 watcher-side", 2),
          (b"r1346_armed", 5), (b"r1346_serve", 3), (b"R1346", 1),
          (b"R1346 watcher-side", 0),
          (b"R1345", 2), (b"seekmism", 1), (b"[stalecd-near]", 1),
          (b"R1343", 0), (b"R1342", 0),
          (b"static int fassist_budget = 400;", 1),
          (b"if (r887_streak >= 2000000000u) {", 1),
          (b"static int disc_read_lba(uint32_t lba, void *dst);", 1),
          (b"static int iso_resolve(const char *path, uint32_t *out_lba, uint32_t *out_size)", 1)]
for tok, want in checks:
    c = post.count(tok)
    print("POST %s count=%d (must be %d)" % (tok.decode(), c, want))
    if c != want:
        print("PATCH-FAILED - post-token wrong - nothing written, no run")
        raise SystemExit(0)
open("runtime/runtime.c", "wb").write(post)
print("PATCH-APPLIED (R1347 armed-guard serve v2)")
PYEOF
SS2=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_SHA=$SS2"
clang -fsyntax-only -std=gnu99 "$SRC" 2>/tmp/c317_parse.txt; PRC=$?
echo "PARSE_RC=$PRC"
if [ "$PRC" != "0" ]; then echo "PARSE-FAILED - reverting"; head -8 /tmp/c317_parse.txt; cp -p "patch_c317_$TS/runtime.c.pre" "$SRC"; exit 0; fi
echo "PARSE-OK"
echo "===RUN317=== the R1347 build, 120s budget, first-fault stop"
XENOLIFT_FIRSTFAULT_STOP=1 RUN_BUDGET_S=120 bash run.sh > /tmp/run_full_c317.txt 2>&1; RRC=$?
echo "RUN_RC=$RRC"
WDIR="witness_c317_$TS"; mkdir -p "$WDIR"
for f in run.log run.log.d; do [ -f "$f" ] && cp -p "$f" "$WDIR/$f"; done
cp -p /tmp/run_full_c317.txt "$WDIR/run_full.txt"
echo "WITNESS=$WDIR"
LOG="run.log"; [ -s "$LOG" ] || LOG="run.log.d"
echo "===WSERVE317=== the serve v2 receipts"
grep -n "wserve" "$LOG" | head -10
grep -n "stalecd\] R1347" "$LOG" | head -10
echo "===CONV317=== the conversion outcome (pendclr + rspop after the serve)"
grep -n "pendclr" "$LOG" | tail -16
grep -n "rspop" "$LOG" | tail -8
echo "===FE1C317=== the FE1C walk after the serve"
grep -n "\[chg\] FE1C" "$LOG" | tail -14
echo "===READN317=== the ReadN after the serve"
grep -n "cmd 02->06" "$LOG" | head -8
grep -n "cdw02" "$LOG" | tail -4
echo "===FLOW317=== READ ISSUED + fld2sig tail"
grep -c "READ ISSUED" "$LOG"
grep -n "fld2sig" "$LOG" | tail -4
echo "===FAULT317=== fault census"
grep -c "computed-garbage" "$LOG"
FF=$(grep -n "computed-garbage address" "$LOG" | head -1 | cut -d: -f1)
echo "FIRST_FAULT_LINE=$FF"
if [ -n "$FF" ]; then awk -v s="$((FF-6))" -v e="$((FF+6))" 'NR>=s && NR<=e' "$LOG"; fi
echo "===VIS317=== visuals + run tail"
grep -n "nonblank" "$LOG" | tail -3
tail -6 /tmp/run_full_c317.txt
grep -n "rungasp" "$LOG" | tail -2
echo "===C317DONE=== R1347 run complete - the conversion verdict comes from these receipts"
