#!/bin/bash
# c315_watcher_serve.sh - R1345 (v3 idle-only camera) + R1344
# (watcher-side SetLoc serve).
# THE c314 VERDICT: the v2 camera receipted the seek-mismatch class
# (FE04=108785 vs cd_seek_lba=108754) but its 40-print cap was
# eaten by the boot-era ACTIVE-STREAM walk - the tail remains
# unreceipted, and the status-poll path may not even run there.
# The mvdoor-near watcher site IS proven live at the tail (c308
# streaks 1-6).
# THIS CYCLE: (1) preserve pre; (2) R1345 - replace the v2 camera
# with the v3 idle-only variant (prints gated on read_active==0,
# cap 40); (3) R1344 - insert the watcher-side discard + 3-byte
# SetLoc serve + INT1 arm before the retired movie-door gate;
# (4) parse gate; (5) 120s run; (6) census: wserve + stalecd
# receipts, v3 near prints (idle holds only), FE1C walk after the
# serve, the ReadN issuance, READ ISSUED, fld2sig tail, faults,
# visuals, run tail.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C315-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="215d84fff553a84c3485a1f9bbacb429cdaae4f0594d40ac1009e4b9d5c4c772"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1343 tree 215d84ff - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1343 tree)"
TS=$(date +%Y%m%d_%H%M%S)
mkdir -p "patch_c315_$TS"
cp -p "$SRC" "patch_c315_$TS/runtime.c.pre"
echo "PRESERVED: patch_c315_$TS/runtime.c.pre"
python3 - <<'PYEOF'
data = open("runtime/runtime.c", "rb").read()
lines = data.split(b"\n")

# --- EDIT 1: replace the v2 camera (23 lines) with the v3 idle-only camera (22 lines)
c0 = b"/* R1343 (c312): the R1342 decline camera was capped out by the"
h1 = [i for i, l in enumerate(lines) if c0 in l]
print("V2ANCHOR count=%d (must be 1)" % len(h1))
if len(h1) != 1:
    print("PATCH-FAILED - v2 anchor count wrong - nothing written, no run")
    raise SystemExit(0)
i0 = h1[0]
ok = True
if lines[i0+6].strip() != b"{": ok = False
if lines[i0+20].strip() != b"}": ok = False
if lines[i0+21].strip() != b"}": ok = False
if lines[i0+22].strip() != b"}": ok = False
if b"fassist_budget" not in lines[i0+23]: ok = False
print("V2STRUCT_OK=%s (5-point: i0+6 open, i0+20/21/22 closes, i0+23 anchor)" % ok)
if not ok:
    print("PATCH-FAILED - v2 block boundary unexpected - nothing written, no run")
    raise SystemExit(0)
line = lines[i0]
ind = line[:len(line) - len(line.lstrip())]
I = ind + b"    "
v3 = [
    I + b"/* R1345 (c315): v3 idle-only - the v2 change-detection cap was",
    I + b" * eaten by the boot-era ACTIVE-STREAM LBA walk (40 prints by",
    I + b" * line 3263, read_active=1 throughout); gate the prints on",
    I + b" * read_active==0 (the idle Setloc-wait class that matters at",
    I + b" * the tail) so the cap survives to the tail era. */",
    I + b"{",
    I + b"    uint32_t fe1c_q = ((uint32_t)xenolift_mem[0x4FE1Cu]) | ((uint32_t)xenolift_mem[0x4FE1Du] << 8);",
    I + b"    if (fe1c_q == 1u && cd_last_cmd == 0x02u) {",
    I + b"        static int r1345_n, have_last;",
    I + b"        static uint32_t l_p, l_d, l_r, l_s, l_f;",
    I + b"        uint32_t vp = cd_pending, vd = cd_data_n;",
    I + b"        uint32_t vr = (uint32_t)cd_read_active, vs = cd_seek_lba;",
    I + b"        uint32_t vf = xenolift_mem_read32(0x8004FE04u);",
    I + b"        if (r1345_n < 40 && vr == 0u && (!have_last || vp != l_p || vd != l_d",
    I + b"                || vr != l_r || vs != l_s || vf != l_f)) {",
    I + b"            r1345_n++; have_last = 1;",
    I + b"            l_p = vp; l_d = vd; l_r = vr; l_s = vs; l_f = vf;",
    I + b'            r861_out("[stalecd-near] R1345 SetLoc-wait state (idle, changed): pending=%u data_n=%u read_active=%u resp_n=%u seek=%u FE04=%08X seekmism=%u\\n",',
    I + b"                    vp, vd, vr, cd_resp_n, vs, vf, (unsigned)(vf != vs));",
    I + b"        }",
    I + b"    }",
    I + b"}",
]
lines[i0:i0+23] = v3
data2 = b"\n".join(lines)

# --- EDIT 2: insert the R1344 watcher-side serve before the retired movie-door gate
lines = data2.split(b"\n")
a2 = b"if (r887_streak >= 2000000000u) {"
h2 = [i for i, l in enumerate(lines) if a2 in l]
print("R887ANCHOR count=%d (must be 1)" % len(h2))
if len(h2) != 1:
    print("PATCH-FAILED - r887 anchor count wrong - nothing written, no run")
    raise SystemExit(0)
j = h2[0]
aline = lines[j]
aind = aline[:len(aline) - len(aline.lstrip())]
w = [
    aind + b"/* R1344 (c315): the c312-c314 receipts: the status-poll assist",
    aind + b" * never fired at the pass-3 tail (cd_data_n stayed 2060, no",
    aind + b" * discard) though its terms look satisfiable - the enclosing",
    aind + b" * status-poll path may not run in the tail era. THIS site (the",
    aind + b" * watcher tick that prints mvdoor-near) is PROVEN live at the",
    aind + b" * tail (c308 streaks 1-6). Same serve, armed from here: the",
    aind + b" * idle Setloc wait (FE1C=1, cmd=02, drive idle, bytes owed) -",
    aind + b" * discard leftovers (fldbell R503 precedent) then prime the",
    aind + b" * canonical 3-byte SetLoc answer + arm INT1 (the R391 pattern)",
    aind + b" * for the established handler-pair conversion. */",
    aind + b"{",
    aind + b"    uint32_t fe1c_w = ((uint32_t)xenolift_mem[0x4FE1Cu]) | ((uint32_t)xenolift_mem[0x4FE1Du] << 8);",
    aind + b"    if (fe1c_w == 1u && cd_last_cmd == 0x02u && !cd_read_active",
    aind + b"        && r879_fdf8 != 0u) {",
    aind + b"        if (cd_pending != 0u || cd_data_n != 0u) {",
    aind + b"            static int r1344d_n;",
    aind + b"            if (r1344d_n++ < 8u)",
    aind + b'                r861_out("[stalecd] R1344 watcher-side stale discard: pending=%u data_n=%u resp_n=%u seek=%u FE04=%08X\\n",',
    aind + b"                        cd_pending, cd_data_n, cd_resp_n, cd_seek_lba,",
    aind + b"                        xenolift_mem_read32(0x8004FE04u));",
    aind + b"            cd_pending = 0u;",
    aind + b"            cd_data_pos = 0u; cd_data_n = 0u; cd_data_loaded = 0u;",
    aind + b"        }",
    aind + b"        if (cd_resp_n < 3u && cd_pending == 0u) {",
    aind + b"            static int r1344p_n;",
    aind + b"            cd_resp[0] = 0x02u; cd_resp[1] = 0x01u; cd_resp[2] = 0x01u;",
    aind + b"            cd_resp_n = 3u; cd_resp_pos = 0u;",
    aind + b"            memcpy(cd_last_full, cd_resp, sizeof cd_resp);",
    aind + b"            cd_last_full_n = 3u;",
    aind + b"            cd_pending = 3u;",
    aind + b"            if (r1344p_n++ < 8u)",
    aind + b'                r861_out("[wserve] R1344 watcher-side SetLoc serve: 3-byte answer primed + INT1 armed (seek=%u FE04=%08X owes=%08X)\\n",',
    aind + b"                        cd_seek_lba, xenolift_mem_read32(0x8004FE04u), r879_fdf8);",
    aind + b"        }",
    aind + b"    }",
    aind + b"}",
]
lines[j:j] = w
post = b"\n".join(lines)

for tok, want in [(b"R1345", 0), (b"R1344", 0), (b"[wserve]", 0)]:
    c = data.count(tok)
    print("PRE %s count=%d (must be %d)" % (tok.decode(), c, want))
    if c != want:
        print("PATCH-FAILED - pre-token wrong - nothing written, no run")
        raise SystemExit(0)
checks = [(b"R1345", 2), (b"R1344", 3), (b"[wserve]", 1), (b"R1344 watcher-side", 2),
          (b"R1343", 0), (b"R1342", 0), (b"seekmism", 1), (b"[stalecd-near]", 1),
          (b"static int fassist_budget = 400;", 1), (b"if (r887_streak >= 2000000000u) {", 1)]
for tok, want in checks:
    c = post.count(tok)
    print("POST %s count=%d (must be %d)" % (tok.decode(), c, want))
    if c != want:
        print("PATCH-FAILED - post-token wrong - nothing written, no run")
        raise SystemExit(0)
open("runtime/runtime.c", "wb").write(post)
print("PATCH-APPLIED (R1345 v3 idle camera + R1344 watcher-side serve)")
PYEOF
SS2=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_SHA=$SS2"
clang -fsyntax-only -std=gnu99 "$SRC" 2>/tmp/c315_parse.txt; PRC=$?
echo "PARSE_RC=$PRC"
if [ "$PRC" != "0" ]; then echo "PARSE-FAILED - reverting"; head -5 /tmp/c315_parse.txt; cp -p "patch_c315_$TS/runtime.c.pre" "$SRC"; exit 0; fi
echo "PARSE-OK"
echo "===RUN315=== the R1345+R1344 build, 120s budget, first-fault stop"
XENOLIFT_FIRSTFAULT_STOP=1 RUN_BUDGET_S=120 bash run.sh > /tmp/run_full_c315.txt 2>&1; RRC=$?
echo "RUN_RC=$RRC"
WDIR="witness_c315_$TS"; mkdir -p "$WDIR"
for f in run.log run.log.d; do [ -f "$f" ] && cp -p "$f" "$WDIR/$f"; done
cp -p /tmp/run_full_c315.txt "$WDIR/run_full.txt"
echo "WITNESS=$WDIR"
LOG="run.log"; [ -s "$LOG" ] || LOG="run.log.d"
echo "===WSERVE315=== the watcher-side serve receipts"
grep -n "wserve" "$LOG" | head -10
echo "===STALECD315=== the discard receipts (both sites)"
grep -n "stalecd\]" "$LOG" | head -12
echo "===NEAR315=== the v3 idle-only receipts (the tail tuple)"
grep -n "stalecd-near" "$LOG" | head -44
echo "===FE1C315=== the FE1C walk after the serve"
grep -n "\[chg\] FE1C" "$LOG" | tail -14
echo "===READN315=== the ReadN after the serve"
grep -n "cmd 02->06" "$LOG" | head -8
echo "===FLOW315=== READ ISSUED + fld2sig tail"
grep -c "READ ISSUED" "$LOG"
grep -n "fld2sig" "$LOG" | tail -4
echo "===FAULT315=== fault census"
grep -c "computed-garbage" "$LOG"
FF=$(grep -n "computed-garbage address" "$LOG" | head -1 | cut -d: -f1)
echo "FIRST_FAULT_LINE=$FF"
if [ -n "$FF" ]; then awk -v s="$((FF-6))" -v e="$((FF+6))" 'NR>=s && NR<=e' "$LOG"; fi
echo "===VIS315=== visuals + run tail"
grep -n "nonblank" "$LOG" | tail -3
tail -6 /tmp/run_full_c315.txt
grep -n "rungasp" "$LOG" | tail -2
echo "===C315DONE=== R1345+R1344 run complete - the serve verdict comes from these receipts"
