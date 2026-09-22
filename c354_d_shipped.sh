#!/bin/bash
# c354_collectorcam.sh - R1361: CAMERA-ONLY at the collector-
# complete site. The c353 receipts: the R1358 collector prints
# 'pass complete (slots drained, idle, no pending outstanding)'
# while pend=3 sits unconsumed (the file#14 re-request's Setloc
# ack, frozen from t=25s) - its idle predicate reads SLOT
# pending and ignores cd_pending. THIS CYCLE: dump the
# predicate's actual inputs at each pass-complete. ZERO
# behavior change. c355 will fix the predicate from these
# receipts.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C354-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="14bd5f5d96d4b0f33beb05be6ed8d490d71735912b5b8f3949d6bc57682061ea"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1360 tree - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1360 tree)"
TS=$(date +%Y%m%d_%H%M%S)
mkdir -p "patch_c354_$TS"
cp -p "$SRC" "patch_c354_$TS/runtime.c.pre"
echo "PRESERVED: patch_c354_$TS/runtime.c.pre"
python3 - <<'PYEOF'
data = open("runtime/runtime.c", "rb").read()
anchor_sub = b"R1358 genuine-answer collector pass complete"
for tok, want in [(b"R1361", 0), (anchor_sub, 1)]:
    c = data.count(tok)
    print("PRE %s count=%d (must be %d)" % (tok.decode()[:64], c, want))
    if c != want:
        print("PATCH-FAILED - pre-token wrong - nothing written, no run")
        raise SystemExit(0)
lines = data.split(b"\n")
ia = [i for i, l in enumerate(lines) if anchor_sub in l]
print("ANCHOR-LINE count=%d (must be 1)" % len(ia))
if len(ia) != 1:
    print("PATCH-FAILED - anchor wrong - nothing written, no run")
    raise SystemExit(0)
receipt = b'    { static int r1361_n; if (r1361_n++ < 16u) r861_out("[cdcol] R1361 collector-complete inputs: pend=%u resp=%u/%u fdfc=%08X s2=%08X s3=%08X seek=%u\\n", (unsigned)cd_pending, (unsigned)cd_resp_pos, (unsigned)cd_resp_n, xenolift_mem_read32(0x8004FDFCu), xenolift_mem_read32(0x80056788u), xenolift_mem_read32(0x80056789u), cd_seek_lba); } /* R1361 (c354) camera */'
lines.insert(ia[0], receipt)
post = b"\n".join(lines)
checks = [(b"R1361", 2), (b"[cdcol] R1361 collector-complete inputs", 1),
          (b"r1361_n", 2), (anchor_sub, 1), (b"R1358", 3), (b"R1360", 3),
          (b"R1351", 4), (b"R1357", 2), (b"[wgen]", 3),
          (b"g_r1351_genuine_answer", 6), (b"L18405", 1), (b"R1349", 2),
          (b"[wopflag]", 1), (b"R1347", 3), (b"[wserve]", 1), (b"R1346", 1),
          (b"r1346_serve", 3), (b"r1346_armed", 5), (b"R1345", 2),
          (b"seekmism", 1), (b"[stalecd-near]", 1), (b"R1350", 3),
          (b"[wconv]", 1), (b"g_r1350_conv_refill", 5),
          (b"static int fassist_budget = 400;", 1),
          (b"static int iso_resolve(const char *path, uint32_t *out_lba, uint32_t *out_size)", 1)]
for tok, want in checks:
    c = post.count(tok)
    print("POST %s count=%d (must be %d)" % (tok.decode()[:64], c, want))
    if c != want:
        print("PATCH-FAILED - post-token wrong - nothing written, no run")
        raise SystemExit(0)
open("runtime/runtime.c", "wb").write(post)
open("/tmp/c354_patched.flag", "w").write("ok")
print("PATCH-APPLIED (R1361 collector-complete camera)")
PYEOF
if [ ! -f /tmp/c354_patched.flag ]; then echo "PATCH-FAILED - exiting without parse or run"; exit 0; fi
SS2=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_SHA=$SS2"
clang -fsyntax-only -std=gnu99 "$SRC" 2>/tmp/c354_parse.txt; PRC=$?
echo "PARSE_RC=$PRC"
if [ "$PRC" != "0" ]; then echo "PARSE-FAILED - reverting"; head -8 /tmp/c354_parse.txt; cp -p "patch_c354_$TS/runtime.c.pre" "$SRC"; exit 0; fi
echo "PARSE-OK"
echo "===RUN354=== the R1361 build, 120s budget, first-fault stop"
XENOLIFT_FIRSTFAULT_STOP=1 RUN_BUDGET_S=120 bash run.sh > /tmp/run_full_c354.txt 2>&1; RRC=$?
echo "RUN_RC=$RRC"
WDIR="witness_c354_$TS"; mkdir -p "$WDIR"
for f in run.log run.log.d; do [ -f "$f" ] && cp -p "$f" "$WDIR/$f"; done
cp -p /tmp/run_full_c354.txt "$WDIR/run_full.txt"
echo "WITNESS=$WDIR"
LOG="run.log"; [ -s "$LOG" ] || LOG="run.log.d"
echo "===CDCOL354=== the collector-complete input receipts (the misread)"
grep -n "cdcol" "$LOG" | head -20
echo "===COLLPASS354=== the pass-complete receipts themselves"
grep -n "collector pass complete" "$LOG" | head -8
echo "===FROZEN354=== the freeze posture receipts"
grep -n "fldfrz2" "$LOG" | head -4
grep -c "fldfrz2" "$LOG"
echo "===CMDTL354=== the command ladder tail"
grep -n "cmdtl" "$LOG" | tail -6
echo "===FAULT354=== fault census"
grep -c "computed-garbage" "$LOG"
FF=$(grep -n "computed-garbage address" "$LOG" | head -1 | cut -d: -f1)
echo "FIRST_FAULT_LINE=$FF"
if [ -n "$FF" ]; then awk -v s="$((FF-6))" -v e="$((FF+6))" 'NR>=s && NR<=e' "$LOG"; fi
echo "===VIS354=== exits + gpu"
grep -n "rungasp" "$LOG" | tail -3
grep -n "gpufin" "$LOG" | tail -2
grep -n "nonblank" "$LOG" | tail -3
echo "===C354DONE=== R1361 run complete - the misread verdict comes from these receipts"
