#!/bin/bash
# c312_nearcam_v2.sh - R1343: the change-detection decline
# camera v2 (cameras-only, NO behavior change).
# THE c311 VERDICT: the R1342 decline camera was capped out by
# the boot era (8/8 prints at 108754) before the tail wedge -
# print-policy artifact. The discard action is uncapped and
# fired once; at the tail cd_data_n still 2060, so its terms
# genuinely fail there or the enclosing path never runs. Pass-3
# cdw02: 'FE04=108933 FE1C=1 pending=1 read_active=0
# seek(before)=108995' - three candidate refusing terms:
# (1) seek mismatch (cd_seek_lba stale 108995 vs FE04 108933),
# (2) read_active/pending drift, (3) enclosing path never runs.
# THIS CYCLE: (1) preserve pre; (2) R1343 - replace the v1
# decline block with change-detection (tuple change, cap 40) +
# seekmism field; (3) parse gate; (4) 120s run; (5) census: the
# near receipts (all eras incl. tail), discard fires, assist
# serves, FE1C chg tail, READ ISSUED, fld2sig tail, faults,
# visuals, run tail.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C312-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="f6dbc277069d2136f528a6e8c54a326b9c5d4563962950f025ac3c30378ef214"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1342 tree f6dbc277 - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1342 tree)"
TS=$(date +%Y%m%d_%H%M%S)
mkdir -p "patch_c312_$TS"
cp -p "$SRC" "patch_c312_$TS/runtime.c.pre"
echo "PRESERVED: patch_c312_$TS/runtime.c.pre"
python3 - <<'PYEOF'
data = open("runtime/runtime.c", "rb").read()
lines = data.split(b"\n")
c0 = b"/* R1342 (c311): DECLINE receipt at the R1341 discard site -"
hits = [i for i, l in enumerate(lines) if c0 in l]
print("ANCHOR count=%d (must be 1)" % len(hits))
if len(hits) != 1:
    print("PATCH-FAILED - anchor count wrong - nothing written, no run")
    raise SystemExit(0)
i0 = hits[0]
# the v1 block is exactly 15 lines: 6 comment + open brace + body + closes
ok_struct = True
if lines[i0+6].strip() != b"{": ok_struct = False
if lines[i0+14].strip() != b"}": ok_struct = False
print("STRUCT_OK=%s (v1 block boundary check)" % ok_struct)
if not ok_struct:
    print("PATCH-FAILED - v1 block structure unexpected - nothing written, no run")
    raise SystemExit(0)
for tok, want in [(b"R1343", 0), (b"seekmism", 0)]:
    c = data.count(tok)
    print("PRE %s count=%d (must be %d)" % (tok.decode(), c, want))
    if c != want:
        print("PATCH-FAILED - pre-token wrong - nothing written, no run")
        raise SystemExit(0)
line = lines[i0]
ind = line[:len(line) - len(line.lstrip())]
I = ind + b"    "
new_block = [
    I + b"/* R1343 (c312): the R1342 decline camera was capped out by the",
    I + b" * boot-era holds (8/8 prints at 108754) BEFORE the tail wedge -",
    I + b" * a print-policy artifact (the absent-receipts playbook). v2:",
    I + b" * change-detection (print when the tuple changes, cap 40) so",
    I + b" * the TAIL-era model state is receipted; adds seekmism (FE04",
    I + b" * vs cd_seek_lba - the candidate refusing term of the assist). */",
    I + b"{",
    I + b"    uint32_t fe1c_q = ((uint32_t)xenolift_mem[0x4FE1Cu]) | ((uint32_t)xenolift_mem[0x4FE1Du] << 8);",
    I + b"    if (fe1c_q == 1u && cd_last_cmd == 0x02u) {",
    I + b"        static int r1343_n, have_last;",
    I + b"        static uint32_t l_p, l_d, l_r, l_s, l_f;",
    I + b"        uint32_t vp = cd_pending, vd = cd_data_n;",
    I + b"        uint32_t vr = (uint32_t)cd_read_active, vs = cd_seek_lba;",
    I + b"        uint32_t vf = xenolift_mem_read32(0x8004FE04u);",
    I + b"        if (r1343_n < 40 && (!have_last || vp != l_p || vd != l_d",
    I + b"                || vr != l_r || vs != l_s || vf != l_f)) {",
    I + b"            r1343_n++; have_last = 1;",
    I + b"            l_p = vp; l_d = vd; l_r = vr; l_s = vs; l_f = vf;",
    I + b'            r861_out("[stalecd-near] R1343 SetLoc-wait state (changed): pending=%u data_n=%u read_active=%u resp_n=%u seek=%u FE04=%08X seekmism=%u\\n",',
    I + b"                    vp, vd, vr, cd_resp_n, vs, vf, (unsigned)(vf != vs));",
    I + b"        }",
    I + b"    }",
    I + b"}",
]
lines[i0:i0+15] = new_block
post = b"\n".join(lines)
checks = [(b"R1343", 2), (b"seekmism", 1), (b"R1342", 0),
          (b"[stalecd-near]", 1), (b"static int fassist_budget = 400;", 1)]
for tok, want in checks:
    c = post.count(tok)
    print("POST %s count=%d (must be %d)" % (tok.decode(), c, want))
    if c != want:
        print("PATCH-FAILED - post-token wrong - nothing written, no run")
        raise SystemExit(0)
open("runtime/runtime.c", "wb").write(post)
print("PATCH-APPLIED (R1343 change-detection decline camera v2)")
PYEOF
SS2=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_SHA=$SS2"
clang -fsyntax-only -std=gnu99 "$SRC" 2>/tmp/c312_parse.txt; PRC=$?
echo "PARSE_RC=$PRC"
if [ "$PRC" != "0" ]; then echo "PARSE-FAILED - reverting"; head -5 /tmp/c312_parse.txt; cp -p "patch_c312_$TS/runtime.c.pre" "$SRC"; exit 0; fi
echo "PARSE-OK"
echo "===RUN312=== the R1343 build, 120s budget, first-fault stop"
XENOLIFT_FIRSTFAULT_STOP=1 RUN_BUDGET_S=120 bash run.sh > /tmp/run_full_c312.txt 2>&1; RRC=$?
echo "RUN_RC=$RRC"
WDIR="witness_c312_$TS"; mkdir -p "$WDIR"
for f in run.log run.log.d; do [ -f "$f" ] && cp -p "$f" "$WDIR/$f"; done
cp -p /tmp/run_full_c312.txt "$WDIR/run_full.txt"
echo "WITNESS=$WDIR"
LOG="run.log"; [ -s "$LOG" ] || LOG="run.log.d"
echo "===NEAR312=== the v2 decline receipts (all eras incl. the tail)"
grep -n "stalecd-near" "$LOG" | head -44
echo "===DISCARD312=== discard + assist fires"
grep -n "stalecd\] R1341" "$LOG" | head -6
grep -n "FIELD-SEEK" "$LOG" | head -10
echo "===PASS3312=== the pass-3 story"
grep -n "\[chg\] FE1C" "$LOG" | tail -10
grep -n "cdw02" "$LOG" | tail -4
echo "===FLOW312=== READ ISSUED + fld2sig tail"
grep -c "READ ISSUED" "$LOG"
grep -n "fld2sig" "$LOG" | tail -4
echo "===FAULT312=== fault census"
grep -c "computed-garbage" "$LOG"
FF=$(grep -n "computed-garbage address" "$LOG" | head -1 | cut -d: -f1)
echo "FIRST_FAULT_LINE=$FF"
if [ -n "$FF" ]; then awk -v s="$((FF-6))" -v e="$((FF+6))" 'NR>=s && NR<=e' "$LOG"; fi
echo "===VIS312=== visuals + run tail"
grep -n "nonblank" "$LOG" | tail -3
tail -6 /tmp/run_full_c312.txt
grep -n "rungasp" "$LOG" | tail -2
echo "===C312DONE=== R1343 run complete - the tail refusing term is receipted or the path proven never-reached"
