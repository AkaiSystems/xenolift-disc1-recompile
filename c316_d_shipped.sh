#!/bin/bash
# c316_serve_filescope.sh - R1345 (v3 idle camera, unchanged) +
# R1346 (the watcher-side SetLoc serve, factored to file scope).
# THE c315 VERDICT: the parse gate caught a scope error - the
# r887 watcher site (~line 1066) precedes the CD model globals,
# so the inline serve block failed on cd_data_n. Reverted clean,
# tree 215d84ff. c316 factors the serve into r1346_serve():
# fwd decl after the disc_read_lba declaration (~747), definition
# before iso_resolve (~12695, after all globals), one call at the
# watcher site. No r879_fdf8 reference - the owed gate reads the
# FDF8 cell directly. Same self-limiting serve semantics.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C316-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="215d84fff553a84c3485a1f9bbacb429cdaae4f0594d40ac1009e4b9d5c4c772"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1343 tree 215d84ff - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1343 tree)"
TS=$(date +%Y%m%d_%H%M%S)
mkdir -p "patch_c316_$TS"
cp -p "$SRC" "patch_c316_$TS/runtime.c.pre"
echo "PRESERVED: patch_c316_$TS/runtime.c.pre"
python3 - <<'PYEOF'
data = open("runtime/runtime.c", "rb").read()

for tok, want in [(b"R1345", 0), (b"R1346", 0), (b"[wserve]", 0), (b"r1346_serve", 0)]:
    c = data.count(tok)
    print("PRE %s count=%d (must be %d)" % (tok.decode(), c, want))
    if c != want:
        print("PATCH-FAILED - pre-token wrong - nothing written, no run")
        raise SystemExit(0)

lines = data.split(b"\n")

# --- anchors (all indices in the ORIGINAL; asserted ordering)
a_iso = b"static int iso_resolve(const char *path, uint32_t *out_lba, uint32_t *out_size)"
h_iso = [i for i, l in enumerate(lines) if a_iso in l]
print("ISOANCHOR count=%d (must be 1)" % len(h_iso))
if len(h_iso) != 1:
    print("PATCH-FAILED - iso anchor wrong - nothing written, no run"); raise SystemExit(0)
j_iso = h_iso[0]

a_v2 = b"/* R1343 (c312): the R1342 decline camera was capped out by the"
h_v2 = [i for i, l in enumerate(lines) if a_v2 in l]
print("V2ANCHOR count=%d (must be 1)" % len(h_v2))
if len(h_v2) != 1:
    print("PATCH-FAILED - v2 anchor wrong - nothing written, no run"); raise SystemExit(0)
i0 = h_v2[0]

a_w = b"if (r887_streak >= 2000000000u) {"
h_w = [i for i, l in enumerate(lines) if a_w in l]
print("R887ANCHOR count=%d (must be 1)" % len(h_w))
if len(h_w) != 1:
    print("PATCH-FAILED - r887 anchor wrong - nothing written, no run"); raise SystemExit(0)
j_w = h_w[0]

a_decl = b"static int disc_read_lba(uint32_t lba, void *dst);"
h_d = [i for i, l in enumerate(lines) if a_decl in l]
print("DECLANCHOR count=%d (must be 1)" % len(h_d))
if len(h_d) != 1:
    print("PATCH-FAILED - decl anchor wrong - nothing written, no run"); raise SystemExit(0)
k_d = h_d[0]

print("ORDER_DECL=%d WATCHER=%d V3SITE=%d ISO=%d (must be ascending)" % (k_d, j_w, i0, j_iso))
if not (k_d < j_w < i0 < j_iso):
    print("PATCH-FAILED - site ordering unexpected - nothing written, no run"); raise SystemExit(0)

# --- block D: the r1346_serve definition (file scope, col 0)
defblock = [
    b"/* R1346 (c316): the watcher-side SetLoc serve, factored to file",
    b" * scope where the CD model globals are in scope. The inline c315",
    b" * attempt at the watcher's early line parse-failed on cd_data_n",
    b" * (caught by the parse gate, reverted, tree 215d84ff). The serve:",
    b" * the idle Setloc wait (FE1C=1, cmd=02, drive idle, bytes owed) -",
    b" * discard leftovers (the fldbell R503 precedent) then prime the",
    b" * canonical 3-byte SetLoc answer + arm INT1 (the R391 pattern) for",
    b" * the established handler-pair conversion. The watcher site is",
    b" * PROVEN live at the tail (c308 mvdoor-near streaks 1-6) where the",
    b" * status-poll assist never fires. */",
    b"static void r1346_serve(void)",
    b"{",
    b"    uint32_t fe1c_w = ((uint32_t)xenolift_mem[0x4FE1Cu]) | ((uint32_t)xenolift_mem[0x4FE1Du] << 8);",
    b"    uint32_t owed = xenolift_mem_read32(0x8004FDF8u);",
    b"    if (fe1c_w == 1u && cd_last_cmd == 0x02u && !cd_read_active",
    b"        && owed != 0u) {",
    b"        if (cd_pending != 0u || cd_data_n != 0u) {",
    b"            static int r1346d_n;",
    b"            if (r1346d_n++ < 8u)",
    b'                r861_out("[stalecd] R1346 watcher-side stale discard: pending=%u data_n=%u resp_n=%u seek=%u FE04=%08X\\n",',
    b"                        cd_pending, cd_data_n, cd_resp_n, cd_seek_lba,",
    b"                        xenolift_mem_read32(0x8004FE04u));",
    b"            cd_pending = 0u;",
    b"            cd_data_pos = 0u; cd_data_n = 0u; cd_data_loaded = 0u;",
    b"        }",
    b"        if (cd_resp_n < 3u && cd_pending == 0u) {",
    b"            static int r1346p_n;",
    b"            cd_resp[0] = 0x02u; cd_resp[1] = 0x01u; cd_resp[2] = 0x01u;",
    b"            cd_resp_n = 3u; cd_resp_pos = 0u;",
    b"            memcpy(cd_last_full, cd_resp, sizeof cd_resp);",
    b"            cd_last_full_n = 3u;",
    b"            cd_pending = 3u;",
    b"            if (r1346p_n++ < 8u)",
    b'                r861_out("[wserve] R1346 watcher-side SetLoc serve: 3-byte answer primed + INT1 armed (seek=%u FE04=%08X owes=%08X)\\n",',
    b"                        cd_seek_lba, xenolift_mem_read32(0x8004FE04u), owed);",
    b"        }",
    b"    }",
    b"}",
    b"",
]
lines[j_iso:j_iso] = defblock

# --- block C: v3 idle-only camera replaces the v2 block (23 lines -> 22)
ok = True
if lines[i0+6].strip() != b"{": ok = False
if lines[i0+20].strip() != b"}": ok = False
if lines[i0+21].strip() != b"}": ok = False
if lines[i0+22].strip() != b"}": ok = False
if b"fassist_budget" not in lines[i0+23]: ok = False
print("V2STRUCT_OK=%s" % ok)
if not ok:
    print("PATCH-FAILED - v2 boundary unexpected - nothing written, no run"); raise SystemExit(0)
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

# --- block B: the watcher call site (indent from the anchor line)
aline = lines[j_w]
aind = aline[:len(aline) - len(aline.lstrip())]
callblock = [
    aind + b"/* R1346 (c316): the tail-proven watcher calls the serve",
    aind + b" * (factored to file scope; this scope precedes the CD model",
    aind + b" * globals). */",
    aind + b"r1346_serve();",
]
lines[j_w:j_w] = callblock

# --- block A: forward declaration after the disc_read_lba declaration
lines[k_d+1:k_d+1] = [b"", b"static void r1346_serve(void);"]

post = b"\n".join(lines)
checks = [(b"R1346", 4), (b"r1346_serve", 3), (b"[wserve]", 1), (b"R1346 watcher-side", 2),
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
print("PATCH-APPLIED (R1345 v3 idle camera + R1346 file-scoped watcher serve)")
PYEOF
SS2=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_SHA=$SS2"
clang -fsyntax-only -std=gnu99 "$SRC" 2>/tmp/c316_parse.txt; PRC=$?
echo "PARSE_RC=$PRC"
if [ "$PRC" != "0" ]; then echo "PARSE-FAILED - reverting"; head -8 /tmp/c316_parse.txt; cp -p "patch_c316_$TS/runtime.c.pre" "$SRC"; exit 0; fi
echo "PARSE-OK"
echo "===RUN316=== the R1345+R1346 build, 120s budget, first-fault stop"
XENOLIFT_FIRSTFAULT_STOP=1 RUN_BUDGET_S=120 bash run.sh > /tmp/run_full_c316.txt 2>&1; RRC=$?
echo "RUN_RC=$RRC"
WDIR="witness_c316_$TS"; mkdir -p "$WDIR"
for f in run.log run.log.d; do [ -f "$f" ] && cp -p "$f" "$WDIR/$f"; done
cp -p /tmp/run_full_c316.txt "$WDIR/run_full.txt"
echo "WITNESS=$WDIR"
LOG="run.log"; [ -s "$LOG" ] || LOG="run.log.d"
echo "===WSERVE316=== the watcher-side serve receipts"
grep -n "wserve" "$LOG" | head -10
echo "===STALECD316=== the discard receipts (both sites)"
grep -n "stalecd\]" "$LOG" | head -12
echo "===NEAR316=== the v3 idle-only receipts (the tail tuple)"
grep -n "stalecd-near" "$LOG" | head -44
echo "===FE1C316=== the FE1C walk after the serve"
grep -n "\[chg\] FE1C" "$LOG" | tail -14
echo "===READN316=== the ReadN after the serve"
grep -n "cmd 02->06" "$LOG" | head -8
echo "===FLOW316=== READ ISSUED + fld2sig tail"
grep -c "READ ISSUED" "$LOG"
grep -n "fld2sig" "$LOG" | tail -4
echo "===FAULT316=== fault census"
grep -c "computed-garbage" "$LOG"
FF=$(grep -n "computed-garbage address" "$LOG" | head -1 | cut -d: -f1)
echo "FIRST_FAULT_LINE=$FF"
if [ -n "$FF" ]; then awk -v s="$((FF-6))" -v e="$((FF+6))" 'NR>=s && NR<=e' "$LOG"; fi
echo "===VIS316=== visuals + run tail"
grep -n "nonblank" "$LOG" | tail -3
tail -6 /tmp/run_full_c316.txt
grep -n "rungasp" "$LOG" | tail -2
echo "===C316DONE=== R1345+R1346 run complete - the serve verdict comes from these receipts"
