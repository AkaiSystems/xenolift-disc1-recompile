#!/bin/bash
# c362_fieldspin.sh - R1364: give the serve-armed genuine answer
# a conversion arm that runs in the 800286CC field-spin park.
# The c361 receipts: the fd-tick conversion block is a
# dispatch-context hook (fires only on a==0x80041410@r31=
# 80028704 / 0x800415B4 / 0x80042A54/58); 422 fd-ticks ALL in
# early eras, ZERO in the park - the park dispatches none of
# those fns, so the armed answer sits unconvertible. THE FIX:
# add `|| (a == 0x800286CCu && g_r1351_genuine_answer)` to the
# hook's context disjunction. The flag gate keeps boot-era
# 800286CC spins (the c178 wedge class) out.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C362-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="2a9235b6bf9480e309fd14ccfea09189ae7175b8360aef2fc032c29f8cb6e238"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1363 tree - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1363 tree)"
TS=$(date +%Y%m%d_%H%M%S)
mkdir -p "patch_c362_$TS"
cp -p "$SRC" "patch_c362_$TS/runtime.c.pre"
echo "PRESERVED: patch_c362_$TS/runtime.c.pre"
python3 - <<'PYEOF'
data = open("runtime/runtime.c", "rb").read()
ANCH = b"            || a == 0x80042A54u || a == 0x80042A58u)) {"
for tok, want in [(b"R1364", 0), (ANCH, 1)]:
    c = data.count(tok)
    print("PRE %s count=%d (must be %d)" % (tok.decode()[:60], c, want))
    if c != want:
        print("PATCH-FAILED - pre-token wrong - nothing written, no run")
        raise SystemExit(0)
NEW = (b"            || a == 0x80042A54u || a == 0x80042A58u\n"
       b"            || (a == 0x800286CCu && g_r1351_genuine_answer))) { /* R1364 (c362): the field-spin park dispatches no collector-context fn (c361: 422 fd-ticks all early-era, zero in the park), so the serve-armed genuine answer needs its own context arm; the flag gate keeps boot-era 800286CC spins (the c178 class) out */")
post = data.replace(ANCH, NEW)
checks = [(b"R1364 (c362)", 1), (b"a == 0x800286CCu && g_r1351_genuine_answer", 1),
          (ANCH, 0), (b"g_r1351_genuine_answer", 7),
          (b"R1351", 4), (b"[wgen]", 3), (b"L18405", 1), (b"R1349", 2),
          (b"[wopflag]", 1), (b"R1347", 3), (b"R1346", 1), (b"r1346_serve", 3),
          (b"r1346_armed", 5), (b"R1363 (c358)", 1), (b"R1361", 2),
          (b"R1358", 3), (b"R1360", 3), (b"R1357", 2), (b"R1350", 3),
          (b"[wconv]", 1), (b"g_r1350_conv_refill", 5), (b"R1345", 2),
          (b"seekmism", 1), (b"[stalecd-near]", 1),
          (b"cd_data_loaded = 0u;", 3),
          (b"cd_resp_n = 0u; cd_resp_pos = 0u;", 1),
          (b"[stalecd] R1347 watcher-side stale discard", 1),
          (b"[wserve] R1347 watcher-side SetLoc serve", 1),
          (b"static int fassist_budget = 400;", 1),
          (b"static int iso_resolve(const char *path, uint32_t *out_lba, uint32_t *out_size)", 1)]
for tok, want in checks:
    c = post.count(tok)
    print("POST %s count=%d (must be %d)" % (tok.decode()[:60], c, want))
    if c != want:
        print("PATCH-FAILED - post-token wrong - nothing written, no run")
        raise SystemExit(0)
open("runtime/runtime.c", "wb").write(post)
open("/tmp/c362_patched.flag", "w").write("ok")
print("PATCH-APPLIED (R1364 field-spin conversion arm)")
PYEOF
if [ ! -f /tmp/c362_patched.flag ]; then echo "PATCH-FAILED - exiting without parse or run"; exit 0; fi
SS2=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_SHA=$SS2"
clang -fsyntax-only -std=gnu99 "$SRC" 2>/tmp/c362_parse.txt; PRC=$?
echo "PARSE_RC=$PRC"
if [ "$PRC" != "0" ]; then echo "PARSE-FAILED - reverting"; head -8 /tmp/c362_parse.txt; cp -p "patch_c362_$TS/runtime.c.pre" "$SRC"; exit 0; fi
echo "PARSE-OK"
echo "===RUN362=== the R1364 build, 120s budget, first-fault stop"
XENOLIFT_FIRSTFAULT_STOP=1 RUN_BUDGET_S=120 bash run.sh > /tmp/run_full_c362.txt 2>&1; RRC=$?
echo "RUN_RC=$RRC"
WDIR="witness_c362_$TS"; mkdir -p "$WDIR"
for f in run.log run.log.d; do [ -f "$f" ] && cp -p "$f" "$WDIR/$f"; done
cp -p /tmp/run_full_c362.txt "$WDIR/run_full.txt"
echo "WITNESS=$WDIR"
LOG="run.log"; [ -s "$LOG" ] || LOG="run.log.d"
echo "===SERVE362=== the serve chain (both boots)"
grep -n "wserve\|wopflag\|wconv" "$LOG" | head -8
echo "===PARKCONV362=== fd-tick + pair receipts AT park lines (after the serve)"
SL=$(grep -n "wserve" "$LOG" | head -1 | cut -d: -f1)
echo "SERVE_LINE=$SL"
grep -n "fd-tick" "$LOG" | awk -v s="$SL" -F: '$1>=s' | head -8
grep -c "fd-tick" "$LOG"
echo "===WGEN362=== the genuine pair receipts"
grep -n "wpair\|wgen" "$LOG" | head -8
echo "===CONSUME362=== pendclr + response consumed after the serve"
grep -n "pendclr" "$LOG" | awk -v s="$SL" -F: '$1>=s' | head -8
grep -n "response consumed" "$LOG" | awk -v s="$SL" -F: '$1>=s' | head -6
echo "===CMDTL362=== the ladder (past #5?)"
grep -n "cmdtl" "$LOG" | tail -8
echo "===FTAB362=== the file reads"
grep -n "READ ISSUED" "$LOG" | tail -6
echo "===SECTORS362=== sectors served"
grep -c "sector LBA" "$LOG"
echo "===FE1C362=== the FE1C walk (late)"
grep -n "chg. FE1C" "$LOG" | tail -6
echo "===FROZEN362=== the freeze census"
grep -c "fldfrz2" "$LOG"
echo "===TRAIL362=== the park census (did the park move?)"
grep -n "trail. R642" "$LOG" | head -3
grep -n "trail. R642" "$LOG" | tail -2
echo "===FAULT362=== fault census"
grep -c "computed-garbage" "$LOG"
FF=$(grep -n "computed-garbage address" "$LOG" | head -1 | cut -d: -f1)
echo "FIRST_FAULT_LINE=$FF"
if [ -n "$FF" ]; then awk -v s="$((FF-6))" -v e="$((FF+6))" 'NR>=s && NR<=e' "$LOG"; fi
echo "===VIS362=== exits + gpu census"
grep -n "rungasp" "$LOG" | tail -3
grep -n "gpufin" "$LOG" | tail -2
echo "===C362DONE=== R1364 run complete - the field-spin verdict comes from these receipts"
