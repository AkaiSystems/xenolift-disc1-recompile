#!/bin/bash
# c310_stale_discard.sh - R1341: stale-leftover discard so the
# FIELD-SEEK assist serves the re-read SetLoc posture.
# THE c309 CONVICTION: the game's re-read Setloc at 108933 waits
# at FE1C=1; the hoisted assist refuses the 3-byte answer serve
# because the PREVIOUS request left stale state (cd_pending=1 +
# a stale 2060B sector) though no live stream owns the leftovers
# (cd_read_active=0). fldbell R503 is the discard precedent but
# its gate requires last_cmd=01. All cmd-02 reply clears this
# run were at 108754 (clean state); none at 108933.
# THIS CYCLE: (1) preserve the pre tree; (2) R1341 - insert the
# stale-discard pre-block inside the assist outer if; (3) parse
# gate (restore on fail); (4) 120s run under
# XENOLIFT_FIRSTFAULT_STOP=1; (5) census: the discard receipts,
# the assist fires, the FE1C walk, the ReadN issuance, sector
# flow, mount lifecycle, f15 watch, faults, visuals, run tail.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C310-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="9da166fbd3ba8b18f41fec7defbedde3e62f6b9917f259987ddc91e9c292d91e"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1339 tree 9da166fb - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1339 tree)"
TS=$(date +%Y%m%d_%H%M%S)
mkdir -p "patch_c310_$TS"
cp -p "$SRC" "patch_c310_$TS/runtime.c.pre"
echo "PRESERVED: patch_c310_$TS/runtime.c.pre"
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
prev = lines[i-1]
print("PREV_LINE_HAS_GATE=%s" % (b"cd_last_cmd == 0x02u" in prev))
if b"cd_last_cmd == 0x02u" not in prev:
    print("PATCH-FAILED - preceding line is not the assist outer if - nothing written, no run")
    raise SystemExit(0)
ind = prev[:len(prev) - len(prev.lstrip())]
I = ind + b"    "
block_lines = [
    I + b"/* R1341 (c310): stale-leftover discard for the re-read SetLoc",
    I + b" * posture. The c309 receipts: the game's re-read Setloc at",
    I + b" * 108933 waits at FE1C=1; the assist that serves the 3-byte",
    I + b" * answer refuses because the PREVIOUS request left cd_pending=1",
    I + b" * and a stale 2060B sector (cd_data_n) - leftovers no live",
    I + b" * stream owns (cd_read_active=0). Discard them (the fldbell",
    I + b" * R503 precedent) so the assist's clean-state terms pass and",
    I + b" * the SetLoc reply is served through the established",
    I + b" * handler-pair path. */",
    I + b"{",
    I + b"    uint32_t fe1c_p = ((uint32_t)xenolift_mem[0x4FE1Cu]) | ((uint32_t)xenolift_mem[0x4FE1Du] << 8);",
    I + b"    if (fe1c_p == 1u && !cd_read_active",
    I + b"        && (cd_pending != 0u || cd_data_n != 0u)) {",
    I + b"        static int r1341_n;",
    I + b"        if (r1341_n++ < 8u)",
    I + b"            r861_out(\"[stalecd] R1341 stale CD state discarded for SetLoc serve: pending=%u data_n=%u resp_n=%u seek=%u FE04=%08X\\n\",",
    I + b"                    cd_pending, cd_data_n, cd_resp_n, cd_seek_lba,",
    I + b"                    xenolift_mem_read32(0x8004FE04u));",
    I + b"        cd_pending = 0u;",
    I + b"        cd_data_pos = 0u; cd_data_n = 0u; cd_data_loaded = 0u;",
    I + b"    }",
    I + b"}",
]
pre_checks = [(b"R1341", 0), (b"[stalecd]", 0)]
for tok, want in pre_checks:
    c = data.count(tok)
    print("PRE %s count=%d (must be %d)" % (tok.decode(), c, want))
    if c != want:
        print("PATCH-FAILED - pre-token wrong - nothing written, no run")
        raise SystemExit(0)
lines[i:i] = block_lines
post = b"\n".join(lines)
checks = [(b"R1341", 2), (b"[stalecd]", 1), (b"stalecd] R1341 stale CD state discarded", 1),
          (b"static int fassist_budget = 400;", 1)]
for tok, want in checks:
    c = post.count(tok)
    print("POST %s count=%d (must be %d)" % (tok.decode(), c, want))
    if c != want:
        print("PATCH-FAILED - post-token wrong - nothing written, no run")
        raise SystemExit(0)
open("runtime/runtime.c", "wb").write(post)
print("PATCH-APPLIED (R1341 stale-discard pre-block)")
PYEOF
SS2=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_SHA=$SS2"
clang -fsyntax-only -std=gnu99 "$SRC" 2>/tmp/c310_parse.txt; PRC=$?
echo "PARSE_RC=$PRC"
if [ "$PRC" != "0" ]; then echo "PARSE-FAILED - reverting"; head -5 /tmp/c310_parse.txt; cp -p "patch_c310_$TS/runtime.c.pre" "$SRC"; exit 0; fi
echo "PARSE-OK"
echo "===RUN310=== the R1341 build, 120s budget, first-fault stop"
XENOLIFT_FIRSTFAULT_STOP=1 RUN_BUDGET_S=120 bash run.sh > /tmp/run_full_c310.txt 2>&1; RRC=$?
echo "RUN_RC=$RRC"
WDIR="witness_c310_$TS"; mkdir -p "$WDIR"
for f in run.log run.log.d; do [ -f "$f" ] && cp -p "$f" "$WDIR/$f"; done
cp -p /tmp/run_full_c310.txt "$WDIR/run_full.txt"
echo "WITNESS=$WDIR"
LOG="run.log"; [ -s "$LOG" ] || LOG="run.log.d"
echo "===DISCARD310=== the stale-discard receipts"
grep -n "stalecd" "$LOG" | head -10
echo "===SERVE310=== the assist fires + the FE1C walk"
grep -n "FIELD-SEEK" "$LOG" | head -10
grep -n "\[chg\] FE1C" "$LOG" | head -12
echo "===READN310=== the ReadN issuance + sector flow"
grep -n "cmd 02->06\|cmd 06->" "$LOG" | head -6
grep -n "READ ISSUED" "$LOG"
grep -n "data-ready INT1 armed" "$LOG" | head -6
echo "--- FDF8 drain samples:"
grep -n "fld2sig" "$LOG" | tail -6
echo "===MOUNT310=== mount lifecycle"
grep -n "mount-success" "$LOG" | head -6
grep -c "mount-success refire" "$LOG"
echo "===F15WATCH310=== the file#15 watch"
grep -n "file#=15\|file#15\|F0C=15\|F0C 0000000F" "$LOG" | head -8
echo "===FAULT310=== fault census"
grep -c "computed-garbage" "$LOG"
FF=$(grep -n "computed-garbage address" "$LOG" | head -1 | cut -d: -f1)
echo "FIRST_FAULT_LINE=$FF"
if [ -n "$FF" ]; then awk -v s="$((FF-6))" -v e="$((FF+6))" 'NR>=s && NR<=e' "$LOG"; fi
echo "===VIS310=== visuals"
grep -n "nonblank" "$LOG" | tail -4
echo "--- run tail:"
tail -8 /tmp/run_full_c310.txt
grep -n "rungasp" "$LOG" | tail -2
echo "===C310DONE=== R1341 run complete - the SetLoc-serve verdict comes from these receipts"
