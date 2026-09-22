#!/bin/bash
# c322_opflag_recipe.sh - R1349: complete the scheduled-delivery
# door's recipe from the serve (pending + the kernel op flag),
# retiring the R1348 out-of-context force.
# THE c321 VERDICT: the frontguard exonerated (reverts in all
# eras; passes completed with them); the DISCOVERY is the
# scheduled-delivery door's recipe: set pending AND set the
# kernel op flag (0x800578A6) - the collector runs when the
# game's flag check (8004B894/8004293C, cycling every tail
# iteration) returns nonzero. The serve never set the op flag;
# the R1348 force ran the collector out-of-context and the evt
# tick cleared the flag.
# THIS CYCLE: (1) preserve pre; (2) R1349 - replace the R1348
# block with the op-flag set per the door's recipe; (3) parse
# gate; (4) 120s run; (5) census: wopflag/wserve/stalecd, the
# FE1C walk after, ReadN/pendclr/rspop outcomes, READ ISSUED,
# fld2sig tail, faults, visuals, run tail.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C322-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="687b335e2bd29812e99394aef378f7ca8eea545ab6d29a647a034a89a9bf588d"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1348 tree 687b335e - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1348 tree)"
TS=$(date +%Y%m%d_%H%M%S)
mkdir -p "patch_c322_$TS"
cp -p "$SRC" "patch_c322_$TS/runtime.c.pre"
echo "PRESERVED: patch_c322_$TS/runtime.c.pre"
python3 - <<'PYEOF'
data = open("runtime/runtime.c", "rb").read()
lines = data.split(b"\n")
a = b"/* R1348 (c319): the c317/c318 verdicts - the armed INT1"
h = [i for i, l in enumerate(lines) if a in l]
print("R1348ANCHOR count=%d (must be 1)" % len(h))
if len(h) != 1:
    print("PATCH-FAILED - R1348 anchor wrong - nothing written, no run")
    raise SystemExit(0)
i0 = h[0]
ok = (b"[wforce]" in lines[i0+7]) and (lines[i0+8] == b"    }") and (lines[i0+9] == b"}")
print("STRUCT_OK=%s (+7 wforce line, +8 serve-if close, +9 fn close)" % ok)
if not ok:
    print("PATCH-FAILED - boundary unexpected - nothing written, no run")
    raise SystemExit(0)
pre_78A6 = data.count(b"0x800578A6")
print("PRE 0x800578A6 count=%d (POST must be %d)" % (pre_78A6, pre_78A6 + 2))
for tok, want in [(b"R1349", 0), (b"[wopflag]", 0)]:
    c = data.count(tok)
    print("PRE %s count=%d (must be %d)" % (tok.decode(), c, want))
    if c != want:
        print("PATCH-FAILED - pre-token wrong - nothing written, no run")
        raise SystemExit(0)
r1349 = [
    b"        /* R1349 (c322): the c319-c321 verdicts - the armed INT1 never",
    b"         * converts because the delivery recipe is incomplete: the",
    b"         * scheduled-delivery door's proven recipe is pending + the",
    b"         * KERNEL OP FLAG (0x800578A6) - the game's flag-check fns",
    b"         * (8004B894/8004293C, cycling every tail iteration) run the",
    b"         * collector only when the op flag is nonzero. The c319",
    b"         * out-of-context force ran the collector early and the evt",
    b"         * tick cleared the flag - retired (removed below). Set the",
    b"         * flag per the door's recipe; the pop handler clears it on",
    b"         * consumption. */",
    b"        { uint16_t one = 1;",
    b"          memcpy(xenolift_mem + (0x800578A6u & 0x1FFFFFFFu), &one, 2);",
    b"          { static int r1349_n; if (r1349_n++ < 8u)",
    b'            r861_out("[wopflag] R1349 kernel op flag SET post-arm: pend=%u resp=%u/%u fe1c=%u seek=%u - door recipe completed (collector runs at the next flag check)\\n",',
    b"                    (unsigned)cd_pending, (unsigned)cd_resp_pos, (unsigned)cd_resp_n, xenolift_mem_read32(0x8004FE1Cu), cd_seek_lba); } }",
]
lines[i0:i0+8] = r1349
post = b"\n".join(lines)
checks = [(b"R1349", 2), (b"[wopflag]", 1), (b"0x800578A6", pre_78A6 + 2),
          (b"R1348", 0), (b"[wforce]", 0), (b"cd_force_deliver_int1", 22),
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
print("PATCH-APPLIED (R1349 op-flag recipe; R1348 force retired)")
PYEOF
SS2=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_SHA=$SS2"
clang -fsyntax-only -std=gnu99 "$SRC" 2>/tmp/c322_parse.txt; PRC=$?
echo "PARSE_RC=$PRC"
if [ "$PRC" != "0" ]; then echo "PARSE-FAILED - reverting"; head -8 /tmp/c322_parse.txt; cp -p "patch_c322_$TS/runtime.c.pre" "$SRC"; exit 0; fi
echo "PARSE-OK"
echo "===RUN322=== the R1349 build, 120s budget, first-fault stop"
XENOLIFT_FIRSTFAULT_STOP=1 RUN_BUDGET_S=120 bash run.sh > /tmp/run_full_c322.txt 2>&1; RRC=$?
echo "RUN_RC=$RRC"
WDIR="witness_c322_$TS"; mkdir -p "$WDIR"
for f in run.log run.log.d; do [ -f "$f" ] && cp -p "$f" "$WDIR/$f"; done
cp -p /tmp/run_full_c322.txt "$WDIR/run_full.txt"
echo "WITNESS=$WDIR"
LOG="run.log"; [ -s "$LOG" ] || LOG="run.log.d"
echo "===WSERVE322=== the serve + op-flag receipts"
grep -n "wopflag\|wserve" "$LOG" | head -12
grep -n "stalecd\] R13" "$LOG" | head -6
echo "===FE1C322=== the FE1C walk after the op-flag set"
grep -n "\[chg\] FE1C" "$LOG" | tail -16
echo "===OUTCOME322=== ReadN + pendclr + rspop + op-flag events after the serve"
grep -n "cmd 02->06" "$LOG" | head -8
grep -n "pendclr" "$LOG" | tail -6
grep -n "rspop" "$LOG" | tail -6
grep -n "op flag" "$LOG" | tail -8
echo "===FLOW322=== READ ISSUED + fld2sig tail"
grep -c "READ ISSUED" "$LOG"
grep -n "fld2sig" "$LOG" | tail -4
echo "===FAULT322=== fault census"
grep -c "computed-garbage" "$LOG"
FF=$(grep -n "computed-garbage address" "$LOG" | head -1 | cut -d: -f1)
echo "FIRST_FAULT_LINE=$FF"
if [ -n "$FF" ]; then awk -v s="$((FF-6))" -v e="$((FF+6))" 'NR>=s && NR<=e' "$LOG"; fi
echo "===VIS322=== visuals + run tail"
grep -n "nonblank" "$LOG" | tail -3
tail -6 /tmp/run_full_c322.txt
grep -n "rungasp" "$LOG" | tail -2
echo "===C322DONE=== R1349 run complete - the recipe verdict comes from these receipts"
