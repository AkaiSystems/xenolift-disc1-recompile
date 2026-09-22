#!/bin/bash
# c301_gpuband_run.sh - R1338: the GPU-band write camera + first-
# fault run. WHO poisons the DMA-pointer band?
# THE c300 CENSUS: the band 0x800569A0-0x800569BC = the DMA
# register table (image values 1F801810/1814, GPU-DMA MADR/BCR/
# CHCR, OTC-DMA, DPCR); the emit has ZERO literal writers of it
# - any non-image value in a band cell is runtime poisoning by a
# computed writer. The c290b fault (read-through-band-value at
# 0x01000401, a DPCR-style VALUE not a register address) matches
# a poisoned pointer cell.
# THIS CYCLE: (1) preserve the pre tree; (2) apply the R1338
# camera (ALL writes to 0x80056980-0x80056A00, zeros included,
# writer_fn, cap 64, tag [gpw]) anchored before the R1333 block;
# (3) syntax-parse gate; (4) 60s run with XENOLIFT_FIRSTFAULT_
# STOP=1 (R1171: no reroute, no band scrub, chronology
# preserved); (5) digest: every [gpw] receipt line-numbered, the
# first fault context, the fault census.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C301-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="ed69fd5f6753b2e0e840ac0471b950b85c2a23c273fcaca356f4ec706831d1dc"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1337 tree ed69fd5f - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1337 tree)"
TS=$(date +%Y%m%d_%H%M%S)
mkdir -p "patch_c301_$TS"
cp -p "$SRC" "patch_c301_$TS/runtime.c.pre"
PRES=$(shasum -a 256 "patch_c301_$TS/runtime.c.pre" | cut -d" " -f1)
echo "PRESERVED: patch_c301_$TS/runtime.c.pre sha=$PRES"
python3 - <<'PYEOF'
data = open("runtime/runtime.c", "rb").read()
anchor = b"    /* R1333 ARCHIVE-BAND WRITE WATCH (c282 decode): the c276-era death"
n = data.count(anchor)
print("ANCHOR R1333-first-line count=%d (must be 1)" % n)
if n != 1:
    print("PATCH-FAILED - anchor count wrong - nothing written, no run")
    raise SystemExit(0)
for tok, want in [(b"R1338", 0), (b"gpw_n", 0), (b"[gpw]", 0)]:
    c = data.count(tok)
    print("PRE %s count=%d (must be %d)" % (tok.decode(), c, want))
    if c != want:
        print("PATCH-FAILED - pre-token count wrong - nothing written, no run")
        raise SystemExit(0)
block = b"""    /* R1338 GPU-BAND WRITE WATCH (c300 census): the emit has ZERO
     * literal writers of the DMA-pointer band 0x800569A0-0x800569BC
     * (SW_refs=0, all reads) - the image values (1F801810/1814,
     * GPU-DMA MADR/BCR/CHCR, OTC-DMA, DPCR) are the only sanctioned
     * init, and the c290b fault (read-through-band-value at
     * 0x01000401, a DPCR-style VALUE, not a register address)
     * matches a poisoned pointer cell. Log EVERY write to the band
     * window (zeros included - zeroing is evidence) with the writer
     * fn; cap 64. */
    if (a >= 0x80056980u && a <= 0x80056A00u) {
        static int gpw_n;
        if (gpw_n < 64) {
            gpw_n++;
            r861_out("[gpw] R1338 GPU-BAND WRITE %08X <- %08X writer_fn=%08X\\n",
                    a, v, (unsigned)xenolift_cur_fn);
        }
    }

"""
post = data.replace(anchor, block + anchor, 1)
checks = [(b"R1338", 2), (b"gpw_n", 3), (b"[gpw]", 1)]
for tok, want in checks:
    c = post.count(tok)
    print("POST %s count=%d (must be %d)" % (tok.decode(), c, want))
    if c != want:
        print("PATCH-FAILED - post-token count wrong - nothing written, no run")
        raise SystemExit(0)
open("runtime/runtime.c", "wb").write(post)
print("PATCH-APPLIED")
PYEOF
SS2=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_SHA=$SS2"
clang -fsyntax-only -std=gnu99 "$SRC" 2>/tmp/c301_parse.txt; PRC=$?
echo "PARSE_RC=$PRC"
if [ "$PRC" != "0" ]; then echo "PARSE-FAILED - reverting to the preserved tree"; head -5 /tmp/c301_parse.txt; cp -p "patch_c301_$TS/runtime.c.pre" "$SRC"; exit 0; fi
echo "PARSE-OK"
echo "===RUN301=== the R1338 camera build, 60s budget, first-fault stop"
XENOLIFT_FIRSTFAULT_STOP=1 RUN_BUDGET_S=60 bash run.sh > /tmp/run_full_c301.txt 2>&1; RRC=$?
echo "RUN_RC=$RRC"
WDIR="witness_c301_$TS"; mkdir -p "$WDIR"
for f in run.log run.log.d; do [ -f "$f" ] && cp -p "$f" "$WDIR/$f"; done
cp -p /tmp/run_full_c301.txt "$WDIR/run_full.txt"
echo "WITNESS=$WDIR"
LOG="run.log"; [ -s "$LOG" ] || LOG="run.log.d"
echo "===GPW301=== every band write (line-numbered, cap 64)"
grep -n "\[gpw\]" "$LOG" | head -64
echo "===FAULT301=== the fault census + first-fault context"
grep -c "\[fault\]" "$LOG"
FF=$(grep -n "computed-garbage address" "$LOG" | head -1 | cut -d: -f1)
echo "FIRST_FAULT_LINE=$FF"
if [ -n "$FF" ]; then awk -v s="$((FF-12))" -v e="$((FF+8))" 'NR>=s && NR<=e' "$LOG"; fi
echo "===GPW-NEAR-FAULT=== band writes within 40 lines before the first fault"
if [ -n "$FF" ]; then awk -v e="$FF" 'NR<=e && /\[gpw\]/' "$LOG" | tail -12; fi
echo "===STATE301=== state + exit census"
grep -n "statetbl\|firstfault\|segvdie\|TRUE DEATH" "$LOG" | tail -8
echo "--- run_full tail:"
tail -12 /tmp/run_full_c301.txt
echo "===C301DONE=== R1338 cycle complete - the poisoner verdict comes from these receipts"
