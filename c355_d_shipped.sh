#!/bin/bash
# c355_serveprobe.sh - (a) READ-ONLY mining of the c354 witness
# for the serve-chain receipts (does the R1346-R1351 chain fire
# anywhere on the R1360 tree?), THEN (b) the R1362 entry camera
# at the unique [wserve] R1347 site. The c354 receipts: the
# collector never runs in the R1360 era; the freeze posture
# carries act=0 after the R1360 clear. HYPOTHESIS: the clear
# disarms the serve chain. The camera receipts whether the
# serve site is reached and with what gate inputs.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C355-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="281a6d5eaae687e94ba5eea6c53043d7b1355bf905be42b9421e848adadd30d1"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1361 camera tree - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1361 tree)"
WD="witness_c354_20260917_135232"
LOG="$WD/run.log"
[ -s "$LOG" ] || LOG="$WD/run.log.d"
if [ ! -s "$LOG" ]; then echo "WITNESS-MISSING: the c354 witness is not on disk"; exit 0; fi
echo "WITNESS=$WD LOG=$LOG SIZE=$(wc -l < "$LOG" | tr -d ' ') lines"
echo "===CHAINMINE355=== the serve-chain receipts on the R1360 tree (whole run)"
for TAG in "wserve" "wopflag" "wconv" "wgen" "wpair" "R1346" "R1347" "R1349" "R1350" "R1351" "R1358"; do
  C=$(grep -c "$TAG" "$LOG")
  echo "--- $TAG count=$C"
  grep -n "$TAG" "$LOG" | head -3
done
echo "===ACTSTORY355=== the read_active (act) story at the freeze: early vs late fldfrz2"
grep -n "fldfrz2" "$LOG" | head -2
grep -n "fldfrz2" "$LOG" | tail -2
echo "===PAUSE355=== the R1360 clear receipts in the c354 run"
grep -n "R1360" "$LOG" | head -4
TS=$(date +%Y%m%d_%H%M%S)
mkdir -p "patch_c355_$TS"
cp -p "$SRC" "patch_c355_$TS/runtime.c.pre"
echo "PRESERVED: patch_c355_$TS/runtime.c.pre"
python3 - <<'PYEOF'
data = open("runtime/runtime.c", "rb").read()
anchor_sub = b"[wserve] R1347"
for tok, want in [(b"R1362", 0), (anchor_sub, 1)]:
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
receipt = b'    { static int r1362_n; if (r1362_n++ < 12u) r861_out("[wentry] R1362 serve-site reached: pend=%u act=%u resp=%u/%u sched=%08X seek=%u FDF8=%08X\\n", (unsigned)cd_pending, (unsigned)cd_read_active, (unsigned)cd_resp_pos, (unsigned)cd_resp_n, xenolift_mem_read32(0x8004FDFCu), cd_seek_lba, xenolift_mem_read32(0x8004FDF8u)); } /* R1362 (c355) camera */'
lines.insert(ia[0], receipt)
post = b"\n".join(lines)
checks = [(b"R1362", 2), (b"[wentry] R1362 serve-site reached", 1),
          (b"r1362_n", 2), (anchor_sub, 1), (b"R1361", 2), (b"R1358", 3),
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
open("/tmp/c355_patched.flag", "w").write("ok")
print("PATCH-APPLIED (R1362 serve-site entry camera)")
PYEOF
if [ ! -f /tmp/c355_patched.flag ]; then echo "PATCH-FAILED - exiting without parse or run"; exit 0; fi
SS2=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_SHA=$SS2"
clang -fsyntax-only -std=gnu99 "$SRC" 2>/tmp/c355_parse.txt; PRC=$?
echo "PARSE_RC=$PRC"
if [ "$PRC" != "0" ]; then echo "PARSE-FAILED - reverting"; head -8 /tmp/c355_parse.txt; cp -p "patch_c355_$TS/runtime.c.pre" "$SRC"; exit 0; fi
echo "PARSE-OK"
echo "===RUN355=== the R1362 build, 120s budget, first-fault stop"
XENOLIFT_FIRSTFAULT_STOP=1 RUN_BUDGET_S=120 bash run.sh > /tmp/run_full_c355.txt 2>&1; RRC=$?
echo "RUN_RC=$RRC"
WDIR="witness_c355_$TS"; mkdir -p "$WDIR"
for f in run.log run.log.d; do [ -f "$f" ] && cp -p "$f" "$WDIR/$f"; done
cp -p /tmp/run_full_c355.txt "$WDIR/run_full.txt"
echo "WITNESS=$WDIR"
NLOG="run.log"; [ -s "$NLOG" ] || NLOG="run.log.d"
echo "===WENTRY355=== the serve-site entry receipts"
grep -n "wentry" "$NLOG" | head -14
echo "===WSERVE355=== the serve receipts themselves"
grep -n "wserve" "$NLOG" | head -6
echo "===CHAIN355=== the chain receipts on the camera run"
for TAG in "wopflag" "wconv" "wgen"; do
  echo "--- $TAG count=$(grep -c "$TAG" "$NLOG")"
  grep -n "$TAG" "$NLOG" | head -2
done
echo "===FROZEN355=== the freeze posture"
grep -c "fldfrz2" "$NLOG"
grep -n "fldfrz2" "$NLOG" | head -2
echo "===CMDTL355=== the ladder tail"
grep -n "cmdtl" "$NLOG" | tail -6
echo "===FAULT355=== fault census"
grep -c "computed-garbage" "$NLOG"
FF=$(grep -n "computed-garbage address" "$NLOG" | head -1 | cut -d: -f1)
echo "FIRST_FAULT_LINE=$FF"
if [ -n "$FF" ]; then awk -v s="$((FF-6))" -v e="$((FF+6))" 'NR>=s && NR<=e' "$NLOG"; fi
echo "===VIS355=== exits + gpu"
grep -n "rungasp" "$NLOG" | tail -3
grep -n "gpufin" "$NLOG" | tail -2
grep -n "nonblank" "$NLOG" | tail -3
echo "===C355DONE=== the chain-silence verdict is receipted"
