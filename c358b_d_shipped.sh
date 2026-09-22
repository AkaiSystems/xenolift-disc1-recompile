#!/bin/bash
# c358_respnclear.sh - R1363: complete the R1347 watcher's
# stale-discard reset. The c357 code receipts: the discard
# clears cd_pending/data_pos/data_n/data_loaded but NOT
# cd_resp_n/cd_resp_pos - the leftover resp_n=3 permanently
# fails the serve-prime's 'cd_resp_n < 3u' term (and the
# field-seek assist's same term), so the watcher discards
# every tick and NEVER serves the file#14 re-request's live
# Setloc ack. THE FIX: (1) add cd_resp_n=0u; cd_resp_pos=0u;
# after the discard's cd_data_loaded=0u; (2) delete the c355
# R1362 camera line (repairs the orphaned if-structure).
# The prime re-writes the identical 3 bytes (02 01 01), so
# the completed reset loses nothing.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C358-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="ea90a9a404cdb7666eb50af50d92f38c14684bee9feb350291283d9704fc82c5"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1362 tree - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1362 tree)"
TS=$(date +%Y%m%d_%H%M%S)
mkdir -p "patch_c358_$TS"
cp -p "$SRC" "patch_c358_$TS/runtime.c.pre"
echo "PRESERVED: patch_c358_$TS/runtime.c.pre"
python3 - <<'PYEOF'
data = open("runtime/runtime.c", "rb").read()
DISC = b"[stalecd] R1347 watcher-side stale discard"
CAM = b"[wentry] R1362 serve-site reached"
for tok, want in [(b"R1363", 0), (DISC, 1), (CAM, 1), (b"R1362", 2)]:
    c = data.count(tok)
    print("PRE %s count=%d (must be %d)" % (tok.decode()[:64], c, want))
    if c != want:
        print("PATCH-FAILED - pre-token wrong - nothing written, no run")
        raise SystemExit(0)
lines = data.split(b"\n")
icam = [i for i, l in enumerate(lines) if CAM in l]
print("CAMERA-LINE count=%d (must be 1)" % len(icam))
if len(icam) != 1:
    print("PATCH-FAILED - camera line wrong - nothing written, no run")
    raise SystemExit(0)
del lines[icam[0]]
idisc = [i for i, l in enumerate(lines) if DISC in l]
if len(idisc) != 1:
    print("PATCH-FAILED - discard line wrong - nothing written, no run")
    raise SystemExit(0)
itail = -1
for j in range(idisc[0], min(idisc[0] + 10, len(lines))):
    if b"cd_data_loaded = 0u;" in lines[j]:
        itail = j
        break
print("DISCARD-TAIL within 10 lines: %s" % ("FOUND at %d" % itail if itail >= 0 else "NOT FOUND"))
if itail < 0:
    print("PATCH-FAILED - discard tail wrong - nothing written, no run")
    raise SystemExit(0)
CLEAR = b'        cd_resp_n = 0u; cd_resp_pos = 0u; /* R1363 (c358): complete the stale reset - the leftover resp_n=3 blocked every re-serve gate */'
lines.insert(itail + 1, CLEAR)
post = b"\n".join(lines)
checks = [(b"R1363 (c358)", 1), (b"cd_resp_n = 0u; cd_resp_pos = 0u;", 1),
          (DISC, 1), (CAM, 0), (b"R1362", 0), (b"r1362_n", 0),
          (b"cd_data_loaded = 0u;", 3), (b"R1361", 2), (b"R1358", 3),
          (b"R1360", 3), (b"R1351", 4), (b"R1357", 2), (b"[wgen]", 3),
          (b"g_r1351_genuine_answer", 6), (b"L18405", 1), (b"R1349", 2),
          (b"[wopflag]", 1), (b"R1347", 3), (b"R1346", 1),
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
open("/tmp/c358_patched.flag", "w").write("ok")
print("PATCH-APPLIED (R1363 complete stale reset)")
PYEOF
if [ ! -f /tmp/c358_patched.flag ]; then echo "PATCH-FAILED - exiting without parse or run"; exit 0; fi
SS2=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_SHA=$SS2"
clang -fsyntax-only -std=gnu99 "$SRC" 2>/tmp/c358_parse.txt; PRC=$?
echo "PARSE_RC=$PRC"
if [ "$PRC" != "0" ]; then echo "PARSE-FAILED - reverting"; head -8 /tmp/c358_parse.txt; cp -p "patch_c358_$TS/runtime.c.pre" "$SRC"; exit 0; fi
echo "PARSE-OK"
echo "===RUN358=== the R1363 build, 120s budget, first-fault stop"
XENOLIFT_FIRSTFAULT_STOP=1 RUN_BUDGET_S=120 bash run.sh > /tmp/run_full_c358.txt 2>&1; RRC=$?
echo "RUN_RC=$RRC"
WDIR="witness_c358_$TS"; mkdir -p "$WDIR"
for f in run.log run.log.d; do [ -f "$f" ] && cp -p "$f" "$WDIR/$f"; done
cp -p /tmp/run_full_c358.txt "$WDIR/run_full.txt"
echo "WITNESS=$WDIR"
LOG="run.log"; [ -s "$LOG" ] || LOG="run.log.d"
echo "===WSERVE358=== the serve receipts (did the prime fire at the freeze?)"
grep -n "wserve" "$LOG" | head -8
echo "===STALECD358=== the discard receipts"
grep -n "stalecd. R1347" "$LOG" | head -6
echo "===CHAIN358=== the chain receipts"
for TAG in "wopflag" "wconv" "wgen" "wpair"; do
  echo "--- $TAG count=$(grep -c "$TAG" "$LOG")"
  grep -n "$TAG" "$LOG" | head -2
done
echo "===CDCOL358=== the collector-complete inputs (does the collector run now?)"
grep -n "cdcol" "$LOG" | head -8
echo "===CMDTL358=== the command ladder (did we advance past #5?)"
grep -n "cmdtl" "$LOG" | tail -10
echo "===FTAB358=== the file reads (f15?)"
grep -n "READ ISSUED" "$LOG" | tail -8
echo "===SECTORS358=== sectors served"
grep -c "sector LBA" "$LOG"
grep -n "sector LBA 10899" "$LOG" | head -4
echo "===FROZEN358=== the freeze posture receipts"
grep -c "fldfrz2" "$LOG"
grep -n "fldfrz2" "$LOG" | head -2
echo "===FE1C358=== the FE1C walk (late)"
grep -n "chg. FE1C" "$LOG" | tail -8
echo "===FAULT358=== fault census"
grep -c "computed-garbage" "$LOG"
FF=$(grep -n "computed-garbage address" "$LOG" | head -1 | cut -d: -f1)
echo "FIRST_FAULT_LINE=$FF"
if [ -n "$FF" ]; then awk -v s="$((FF-6))" -v e="$((FF+6))" 'NR>=s && NR<=e' "$LOG"; fi
echo "===VIS358=== exits + gpu census"
grep -n "rungasp" "$LOG" | tail -3
grep -n "gpufin" "$LOG" | tail -2
grep -n "nonblank" "$LOG" | tail -3
echo "===C358DONE=== R1363 run complete - the complete-reset verdict comes from these receipts"
