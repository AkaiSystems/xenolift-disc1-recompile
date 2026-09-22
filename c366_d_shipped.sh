#!/bin/bash
# c366_schedentry2.sh - R1365 reship (c365 gate-fix: POST R1365=3).
# The patch introduces THREE R1365 tokens (outer comment +
# [fsent] camera string + camera comment); the c365 gate said 2
# and the fail-closed script refused with the tree pristine.
# Identical patch bytes, corrected gates:
# R1365: the scheduled-read entry arm.
# The c364 receipts: the hook block that owns every serve arm
# (variant-B, R454, the zrf door + R537 lazy-advance) NEVER
# RE-ENTERS at the field-spin park - its outer condition is
# `cd_pending != 0 || kicks`, and after the R1364 arm delivered
# the ack the kernel consumed, cd_pending=0 and the kicks are
# firstfault-suppressed. The file#14 ReadN posture (sched=1,
# act=0, loaded=0, FDF8=125304, seek=108933) sits OUTSIDE the
# block, so the stream never starts and the game unpacks the
# empty buffer. THE FIX: (1) extend the outer condition with
# `|| (cd_scheduled != 0u && a == 0x800286CCu &&
# g_r1351_genuine_answer)` - the genuine flag keeps boot eras
# out; both serve-arms are cmd-02-gated so the post-#7
# GetStat class cannot over-fire; (2) a budgeted [fsent]
# entry camera so a zrf no-fire receipts the exact posture.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C366-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="b6874d751e5c7e653f4052ea352ad3cc526c9dd1d50d2e173163169aaf54e92d"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1364 tree - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1364 tree)"
TS=$(date +%Y%m%d_%H%M%S)
mkdir -p "patch_c366_$TS"
cp -p "$SRC" "patch_c366_$TS/runtime.c.pre"
echo "PRESERVED: patch_c366_$TS/runtime.c.pre"
python3 - <<'PYEOF'
data = open("runtime/runtime.c", "rb").read()
OUTER = b"    if (!cd_tick_busy && (cd_pending != 0u || kick_wanted || kick2_wanted || kick3_wanted)"
BUSY = b"        cd_tick_busy = 1;\n        uint8_t saved_bank = cd_index;"
for tok, want in [(b"R1365", 0), (b"[fsent]", 0), (OUTER, 1), (BUSY, 1)]:
    c = data.count(tok)
    print("PRE %s count=%d (must be %d)" % (tok.decode()[:70], c, want))
    if c != want:
        print("PATCH-FAILED - pre-token wrong - nothing written, no run")
        raise SystemExit(0)
NEW_OUTER = (b"    if (!cd_tick_busy && (cd_pending != 0u || kick_wanted || kick2_wanted || kick3_wanted"
            b" || (cd_scheduled != 0u && a == 0x800286CCu && g_r1351_genuine_answer))) /* R1365 (c365): the scheduled-read entry arm - the c364 receipts: after the ack consumption the park holds sched=1/act=0/loaded=0/FDF8=125304 and this block never re-enters (pend=0, kicks firstfault-suppressed), so the file-14 stream never starts in the field-spin era */")
CAM = (b"        cd_tick_busy = 1;\n"
       b"        { static uint32_t r1365_n; if (r1365_n < 24u) { r1365_n++; r861_out(\"[fsent] R1365 field-spin scheduled-read entry #%u: a=%08X sched=%u act=%u loaded=%u pend=%u arm1=%u cmd=%02X FDF8=%u FE1C=%u seek=%u\\n\", r1365_n, a, cd_scheduled, cd_read_active, cd_data_loaded, cd_pending, cd_arm_int1_pending, cd_last_cmd, xenolift_mem_read32(0x8004FDF8u), xenolift_mem_read32(0x8004FE1Cu), cd_seek_lba); } } /* R1365 (c365): budgeted entry camera - a zrf no-fire names the excluding gate */\n"
       b"        uint8_t saved_bank = cd_index;")
post = data.replace(OUTER, NEW_OUTER).replace(BUSY, CAM)
checks = [(b"R1365", 3), (b"[fsent] R1365", 1), (b"R1365 (c365)", 2), (OUTER, 0),
          (b"cd_scheduled != 0u && a == 0x800286CCu && g_r1351_genuine_answer", 1),
          (b"g_r1351_genuine_answer", 8), (b"a == 0x800286CCu", 2),
          (b"R1364 (c362)", 1), (b"R1363 (c358)", 1), (b"R1351", 4),
          (b"[wgen]", 3), (b"[wserve] R1347 watcher-side SetLoc serve", 1),
          (b"[wopflag]", 1), (b"R1347", 3), (b"R1346", 1), (b"r1346_serve", 3),
          (b"r1346_armed", 5), (b"L18405", 1), (b"R1361", 2), (b"R1358", 3),
          (b"R1360", 3), (b"R1357", 2), (b"[wconv]", 1), (b"g_r1350_conv_refill", 5),
          (b"cd_data_loaded = 0u;", 3), (b"cd_resp_n = 0u; cd_resp_pos = 0u;", 1),
          (b"static int fassist_budget = 400;", 1),
          (b"static int iso_resolve(const char *path, uint32_t *out_lba, uint32_t *out_size)", 1)]
for tok, want in checks:
    c = post.count(tok)
    print("POST %s count=%d (must be %d)" % (tok.decode()[:70], c, want))
    if c != want:
        print("PATCH-FAILED - post-token wrong - nothing written, no run")
        raise SystemExit(0)
open("runtime/runtime.c", "wb").write(post)
open("/tmp/c366_patched.flag", "w").write("ok")
print("PATCH-APPLIED (R1365 scheduled-read entry arm)")
PYEOF
if [ ! -f /tmp/c366_patched.flag ]; then echo "PATCH-FAILED - exiting without parse or run"; exit 0; fi
SS2=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_SHA=$SS2"
clang -fsyntax-only -std=gnu99 "$SRC" 2>/tmp/c366_parse.txt; PRC=$?
echo "PARSE_RC=$PRC"
if [ "$PRC" != "0" ]; then echo "PARSE-FAILED - reverting"; head -8 /tmp/c366_parse.txt; cp -p "patch_c366_$TS/runtime.c.pre" "$SRC"; exit 0; fi
echo "PARSE-OK"
echo "===RUN366=== the R1365 build, 120s budget, first-fault stop"
XENOLIFT_FIRSTFAULT_STOP=1 RUN_BUDGET_S=120 bash run.sh > /tmp/run_full_c366.txt 2>&1; RRC=$?
echo "RUN_RC=$RRC"
WDIR="witness_c366_$TS"; mkdir -p "$WDIR"
for f in run.log run.log.d; do [ -f "$f" ] && cp -p "$f" "$WDIR/$f"; done
cp -p /tmp/run_full_c366.txt "$WDIR/run_full.txt"
echo "WITNESS=$WDIR"
LOG="run.log"; [ -s "$LOG" ] || LOG="run.log.d"
echo "===FSENT366=== the scheduled-read entry receipts"
grep -n "fsent" "$LOG" | head -10
echo "===ZRF366=== the zrf door receipts (did the stream start?)"
grep -n "zrf" "$LOG" | grep -v zrfY | head -8
grep -c "zrf. zero-length read" "$LOG"
echo "===SECT366=== the file-14 sectors (LBA 108933+) - the stream census"
grep -c "sector LBA 1089" "$LOG"
grep -n "sector LBA 1089" "$LOG" | head -6
grep -n "zrfm" "$LOG" | head -4
echo "===LZSS366=== the unpack receipts (sane word0 at 801DD680?)"
grep -n "lzss-t" "$LOG" | grep "801DD680" | head -4
echo "===CMDTL366=== the ladder"
grep -n "cmdtl" "$LOG" | tail -8
echo "===PENDCLR366=== pendclr after the serve"
SL=$(grep -n "wserve" "$LOG" | head -1 | cut -d: -f1)
echo "SERVE_LINE=$SL"
grep -n "pendclr" "$LOG" | awk -v s="$SL" -F: '$1>=s' | head -6
echo "===FTAB366=== the file reads"
grep -n "READ ISSUED" "$LOG" | tail -4
echo "===FE1C366=== the FE1C walk (late)"
grep -n "chg. FE1C" "$LOG" | tail -6
echo "===TRAIL366=== the park census"
grep -n "trail. R642" "$LOG" | head -2
grep -n "trail. R642" "$LOG" | tail -2
echo "===FAULT366=== fault census"
grep -c "computed-garbage" "$LOG"
FF=$(grep -n "computed-garbage address" "$LOG" | head -1 | cut -d: -f1)
echo "FIRST_FAULT_LINE=$FF"
if [ -n "$FF" ]; then awk -v s="$((FF-6))" -v e="$((FF+6))" 'NR>=s && NR<=e' "$LOG"; fi
echo "===VIS366=== exits + gpu census"
grep -n "rungasp" "$LOG" | tail -3
grep -n "gpufin" "$LOG" | tail -2
echo "===C366DONE=== R1365 run complete - the scheduled-read verdict comes from these receipts"
