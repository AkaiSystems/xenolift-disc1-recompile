#!/bin/bash
# c290b_sheadrd.sh - THE R1337 HEAD-CELL VALUE-TIMELINE CAMERA.
# THE c290 RECORD: the dispatch-case anchor does not exist (the
# dispatcher is not a per-fn switch); hle/hle_spu.c has ZERO band
# refs (the HLE SPU does not write the band). Jos's spec: FIRST
# CHANGE / WRITER / COVERAGE / raw-bytes-vs-walker-value; snapshots
# only locate the window, then identify the writer, fix the write or
# its ordering, rerun without masking.
# THIS CYCLE: (a) R1337 read-hook camera - every guest read of
# 0x80068E08 prints the first 8 reads + EVERY VALUE CHANGE (cap 40,
# tag [sheadrd]) with the RAW memcpy value (exactly what the walker
# reads) + cur_fn; (b) [sheadcp] at the R722 pristine-capture site
# prints the head + mode table values AT CAPTURE (the loader
# verdict); (c) 120s run; (d) digest: the timeline + the receipted
# events bracketing each change ([b2x] capture, [fwrestart] restores
# with their destination ranges, [rvbw] guest-hook writes) + fault
# census. NO behavior change anywhere.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C290B-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="a8676c1011e7742d7f11eec6a9b819009c66f630041458f4db1fddbe504a0873"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1335 tree a8676c10 - refusing, no patch, no run"; exit 0; fi
echo "BASELINE_VERIFIED (the R1335 tree)"

echo "===PATCH290B=== the R1337 head-timeline camera (two sites, gated, FAIL EXPLICIT)"
TS=$(date +%Y%m%d_%H%M%S)
mkdir -p "patch_c290b_$TS"
cp -p "$SRC" "patch_c290b_$TS/runtime.c.pre"
echo "PRESERVED: patch_c290b_$TS/runtime.c.pre sha=$SS"
python3 - <<'PYEOF'
data = open("runtime/runtime.c","rb").read()
pre = data.count(b"R1337")
print("R1337 pre count=%d (must be 0)" % pre)
if pre != 0:
    print("PATCH-FAILED - R1337 already present - nothing written, no run")
    raise SystemExit(0)
for tok in (b"rd1337_n", b"rd1337_last", b"sheadrd", b"sheadcp"):
    c = data.count(tok)
    print("%s pre count=%d (must be 0)" % (tok.decode(), c))
    if c != 0:
        print("PATCH-FAILED - marker collision - nothing written, no run")
        raise SystemExit(0)

# --- site 1: the read32 hook head (before any early return) ---
a1 = b"g_r1195_r32_hits++;"
n1 = data.count(a1)
print("site1 anchor (g_r1195_r32_hits++) count=%d (must be 1)" % n1)
if n1 != 1:
    print("PATCH-FAILED - site1 anchor count wrong - nothing written, no run")
    idx = 0; shown = 0
    while shown < 4:
        idx = data.find(a1, idx)
        if idx == -1: break
        print("  ctx: ...%s..." % data[max(0,idx-60):idx+60].decode("ascii","replace").replace("\n"," | "))
        idx += 1; shown += 1
    raise SystemExit(0)

block1 = b""" /* R1337 (c290): the SPU voice-base cell (0x80068E08) has NO guest
    * writer (c289: 20 LW reads, zero SW; rvbw=0) - its value comes
    * only from the pristine image (R722 capture / R772 restores).
    * Print the first 8 reads + every VALUE CHANGE: the timeline
    * receipts the first transition (including legitimate values)
    * and brackets the writer window between receipted events. Cap
    * 40 prints. Raw memcpy read = exactly what the walker reads. */
    if (a == 0x80068E08u) {
        static uint32_t rd1337_last = 0x9E3779B9u; static int rd1337_n;
        uint32_t v_h; memcpy(&v_h, xenolift_mem + 0x68E08u, 4);
        if (v_h != rd1337_last || rd1337_n < 8) {
            if (rd1337_n < 40) { rd1337_n++;
                r861_out("[sheadrd] R1337 head READ #%d val=%08X cur_fn=%08X\\n",
                        rd1337_n, v_h, (unsigned)xenolift_cur_fn);
            }
        }
        rd1337_last = v_h;
    }
"""
p1 = data.find(a1)
end1 = data.find(b";", p1) + 1
data2 = data[:end1] + block1 + data[end1:]

# --- site 2: the R722 pristine-capture print (loader verdict) ---
a2 = b"R722 pristine exe image captured"
n2 = data2.count(a2)
print("site2 anchor (R722 capture print) count=%d (must be 1)" % n2)
if n2 != 1:
    print("PATCH-FAILED - site2 anchor count wrong - nothing written, no run")
    raise SystemExit(0)
p2 = data2.find(a2)
bound = max(data2.rfind(b";", 0, p2), data2.rfind(b"}", 0, p2), data2.rfind(b"{", 0, p2)) + 1
block2 = b""" /* R1337 (c290): the pristine head value AT CAPTURE - if the image
     * load put junk at 0x80068E08 the loader is indicted; if correct,
     * corruption happens between capture and the walk. */
    { uint32_t c_h, c_m0, c_m1;
      memcpy(&c_h, xenolift_mem + 0x68E08u, 4);
      memcpy(&c_m0, xenolift_mem + 0x68E70u, 4);
      memcpy(&c_m1, xenolift_mem + 0x68E74u, 4);
      r861_out("[sheadcp] R1337 pristine head @capture head=%08X mode0=%08X mode1=%08X\\n", c_h, c_m0, c_m1); }
"""
data3 = data2[:bound] + block2 + data2[bound:]

c1 = data3.count(b"R1337")
print("R1337 post count=%d (must be 4)" % c1)
if c1 != 4: print("PATCH-FAILED - R1337 count wrong - nothing written, no run"); raise SystemExit(0)
c2 = data3.count(b"[sheadrd]")
print("sheadrd post count=%d (must be 1)" % c2)
if c2 != 1: print("PATCH-FAILED - sheadrd count wrong"); raise SystemExit(0)
c3 = data3.count(b"[sheadcp]")
print("sheadcp post count=%d (must be 1)" % c3)
if c3 != 1: print("PATCH-FAILED - sheadcp count wrong"); raise SystemExit(0)
c4 = data3.count(b"rd1337_n")
print("rd1337_n post count=%d (must be 5)" % c4)
if c4 != 5: print("PATCH-FAILED - rd1337_n count wrong"); raise SystemExit(0)
c5 = data3.count(b"rd1337_last")
print("rd1337_last post count=%d (must be 3)" % c5)
if c5 != 3: print("PATCH-FAILED - rd1337_last count wrong"); raise SystemExit(0)
open("runtime/runtime.c","wb").write(data3)
print("PATCH-APPLIED (R1337 camera, two inserts, no behavior change)")
PYEOF
SS2=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_SHA=$SS2"
if [ "$SS2" = "$EXPECT" ]; then echo "PATCH-FAILED - tree unchanged"; exit 0; fi

echo "===PARSE290B=== the syntax gate (restore from backup on fail)"
clang -fsyntax-only -std=gnu99 "$SRC" 2>/tmp/c290b_parse.txt; PRC=$?
echo "PARSE_RC=$PRC"
if [ "$PRC" != "0" ]; then echo "PARSE-FAILED - restoring baseline, no run"; head -6 /tmp/c290b_parse.txt; cp -p "patch_c290b_$TS/runtime.c.pre" "$SRC"; echo "RESTORED sha=$(shasum -a 256 "$SRC" | cut -d' ' -f1)"; exit 0; fi
echo "PARSE-OK"

echo "===RUN290B=== running the R1337 camera build (120s budget)"
RUN_BUDGET_S=120 bash run.sh > /tmp/run_full_c290b.txt 2>&1; RRC=$?
echo "RUN_RC=$RRC"
WDIR="witness_c290b_$TS"
mkdir -p "$WDIR"
for f in run.log run.log.d; do if [ -f "$f" ]; then cp -p "$f" "$WDIR/$f"; fi; done
cp -p /tmp/run_full_c290b.txt "$WDIR/run_full.txt"
echo "WITNESS=$WDIR"
LOG="run.log"; [ -s "$LOG" ] || LOG="run.log.d"
if [ ! -s "$LOG" ]; then echo "C290B-FAILED: no run log produced"; tail -20 /tmp/run_full_c290b.txt; exit 1; fi
ENDL=$(wc -l < "$LOG" | tr -d " ")
echo "log=$LOG lines=$ENDL"
win() { S=$1; [ "$S" -lt 1 ] && S=1; E=$2; [ "$E" -gt "$ENDL" ] && E="$ENDL"; awk -v s="$S" -v e="$E" 'NR>=s&&NR<=e{printf "%d:%s\n",NR,$0}NR>e{exit}' "$LOG"; }

echo "===TL290B=== the head-cell value timeline"
grep -n "\[sheadcp\]" "$LOG" | head -4
grep -n "\[sheadrd\]" "$LOG" | head -44
echo "sheadrd_receipts=$(grep -c "\[sheadrd\]" "$LOG")"

echo "===CHG290B=== the change windows (receipted events bracketing each transition)"
PREVP=""
for LN in $(grep -n "\[sheadrd\]" "$LOG" | cut -d: -f1 | head -44); do
  V=$(sed -n "${LN}p" "$LOG" | sed -E 's/.*val=([0-9A-F]+).*/\1/')
  if [ -n "$PREVP" ] && [ "$V" != "$PREVP" ]; then
    echo "--- CHANGE at log line $LN ($PREVP -> $V): context:"
    win $((LN-6)) $((LN+4))
  fi
  PREVP="$V"
done | head -90

echo "===FAULT290B=== the death census"
echo "fault_receipts=$(grep -c "\[fault\]" "$LOG")"
grep -n "computed-garbage\|TRUE DEATH" "$LOG" | head -6
FF=$(grep -n "computed-garbage" "$LOG" | head -1 | cut -d: -f1)
echo "first_fault_line=$FF"
if [ -n "$FF" ]; then
  echo "--- first fault context:"
  win $((FF-6)) $((FF+10))
  echo "--- the last sheadrd receipts before the first fault:"
  grep -n "\[sheadrd\]" "$LOG" | awk -F: -v f="$FF" '$1 < f' | tail -6
fi

echo "===BRACKET290B=== the receipted writers/restores in this run"
echo "b2x_captures=$(grep -c "\[b2x\] R722" "$LOG")"
echo "fwrestart_restores=$(grep -c "fwrestart\] R772 pristine exe image restored" "$LOG")"
grep -n "fwrestart\] R772" "$LOG" | head -8
echo "rvbw_receipts=$(grep -c "\[rvbw\]" "$LOG")"

echo "===STATE290B=== the state census"
grep -n "statetbl\] R1104 active" "$LOG" | tail -3
grep -n "rungasp\]" "$LOG" | tail -1

echo "===C290BDONE=== head-timeline cycle complete - the writer verdict comes from these receipts"
