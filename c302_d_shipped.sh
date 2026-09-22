#!/bin/bash
# c302_rescope_run.sh - R1338b: rescope the GPU-band camera to the
# pointer cells + 120s census run.
# THE c301 VERDICT: the DMA pointer cells 0x800569A0-0x800569BC
# got ZERO writes in 60s and ZERO faults occurred (the c290b
# death family did NOT reproduce; the healthy load path ran to
# budget). The window's OTHER cells are legitimate driver
# behavior (callback registration at 0x800569C4-CC, frame
# counter at 0x800569E8) - and the frame-counter writes FLOOD
# the camera's 64 cap in seconds, blinding it to any later
# poison event.
# THIS CYCLE: (1) preserve the pre tree; (2) R1338b - replace
# the camera block: watch ONLY 0x80056990-0x800569C0 (the
# pointer cells, zero legit writes, cap 64 lasts the run);
# (3) parse gate; (4) 120s run under XENOLIFT_FIRSTFAULT_STOP=1;
# (5) full census: fault count, band writes, state table, ftab
# reads, VRAM nonblank, run tail.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C302-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="b06f1ffbb3f86b16829a9d09dc1bb81f53dbf0c67167dc2189debe530b4a385e"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1338 tree b06f1ffb - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1338 tree)"
TS=$(date +%Y%m%d_%H%M%S)
mkdir -p "patch_c302_$TS"
cp -p "$SRC" "patch_c302_$TS/runtime.c.pre"
echo "PRESERVED: patch_c302_$TS/runtime.c.pre"
python3 - <<'PYEOF'
data = open("runtime/runtime.c", "rb").read()
old = b"""    /* R1338 GPU-BAND WRITE WATCH (c300 census): the emit has ZERO
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
new = b"""    /* R1338b GPU-BAND WRITE WATCH, RESCOPED (c301 verdict): the 60s
     * run receipted ZERO writes to the pointer cells and ZERO faults -
     * but the window's other cells (callback registration at
     * 0x800569C4-CC, frame counter at 0x800569E8 - written every
     * frame by the Vsync chain) FLOODED the 64 cap in seconds,
     * blinding the camera to any later poison event. RESCOPE: watch
     * ONLY the pointer cells 0x80056990-0x800569C0 (zero legitimate
     * writes - the cap now lasts the whole run). */
    if (a >= 0x80056990u && a <= 0x800569C0u) {
        static int gpw_n;
        if (gpw_n < 64) {
            gpw_n++;
            r861_out("[gpw] R1338b GPU-BAND POINTER WRITE %08X <- %08X writer_fn=%08X\\n",
                    a, v, (unsigned)xenolift_cur_fn);
        }
    }
"""
n = data.count(old)
print("OLD-BLOCK count=%d (must be 1)" % n)
if n != 1:
    print("PATCH-FAILED - old block count wrong - nothing written, no run")
    raise SystemExit(0)
for tok, want in [(b"R1338b", 0), (b"0x80056990u", 0), (b"0x800569C0u", 0)]:
    c = data.count(tok)
    print("PRE %s count=%d (must be %d)" % (tok.decode(), c, want))
    if c != want:
        print("PATCH-FAILED - pre-token wrong - nothing written, no run")
        raise SystemExit(0)
post = data.replace(old, new, 1)
checks = [(b"R1338b", 2), (b"0x80056990u", 1), (b"0x800569C0u", 1),
          (b"0x80056980u", 0), (b"gpw_n", 3), (b"[gpw]", 1), (b"R1338", 2)]
for tok, want in checks:
    c = post.count(tok)
    print("POST %s count=%d (must be %d)" % (tok.decode(), c, want))
    if c != want:
        print("PATCH-FAILED - post-token wrong - nothing written, no run")
        raise SystemExit(0)
open("runtime/runtime.c", "wb").write(post)
print("PATCH-APPLIED")
PYEOF
SS2=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_SHA=$SS2"
clang -fsyntax-only -std=gnu99 "$SRC" 2>/tmp/c302_parse.txt; PRC=$?
echo "PARSE_RC=$PRC"
if [ "$PRC" != "0" ]; then echo "PARSE-FAILED - reverting"; head -5 /tmp/c302_parse.txt; cp -p "patch_c302_$TS/runtime.c.pre" "$SRC"; exit 0; fi
echo "PARSE-OK"
echo "===RUN302=== the R1338b census build, 120s budget, first-fault stop"
XENOLIFT_FIRSTFAULT_STOP=1 RUN_BUDGET_S=120 bash run.sh > /tmp/run_full_c302.txt 2>&1; RRC=$?
echo "RUN_RC=$RRC"
WDIR="witness_c302_$TS"; mkdir -p "$WDIR"
for f in run.log run.log.d; do [ -f "$f" ] && cp -p "$f" "$WDIR/$f"; done
cp -p /tmp/run_full_c302.txt "$WDIR/run_full.txt"
echo "WITNESS=$WDIR"
LOG="run.log"; [ -s "$LOG" ] || LOG="run.log.d"
echo "===FAULT302=== fault census"
grep -c "\[fault\]" "$LOG"
FF=$(grep -n "computed-garbage address" "$LOG" | head -1 | cut -d: -f1)
echo "FIRST_FAULT_LINE=$FF"
if [ -n "$FF" ]; then awk -v s="$((FF-12))" -v e="$((FF+8))" 'NR>=s && NR<=e' "$LOG"; fi
echo "===GPW302=== pointer-cell writes (the poison tripwire)"
grep -n "\[gpw\]" "$LOG" | head -64
echo "===STATE302=== state table census"
grep -n "statetbl" "$LOG" | tail -6
grep -n "bootentry" "$LOG" | tail -3
echo "===FTAB302=== file reads issued"
grep -c "READ ISSUED" "$LOG"
grep "READ ISSUED" "$LOG" | tail -6
echo "===VRAM302=== visual census"
grep -n "nonblank\|vram_nz\|non-blank" "$LOG" | tail -6
echo "--- run_full tail:"
tail -12 /tmp/run_full_c302.txt
echo "===C302DONE=== R1338b census complete - the recur-or-dead verdict comes from these receipts"
