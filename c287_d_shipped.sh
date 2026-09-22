#!/bin/bash
# c287_rvbw_camera.sh - THE R1335 REVERB-BAND CAMERA + walk-region
# dump + all-cbguard census + 120s run.
# THE c286 VERDICT: fn 8004CCB8 is a LIST WALK (r5 = LW(r5 + 0x8E08)
# x3 + LW(r5 + 0x8E0C)), reading a 16-bit field at +0x1A6; entered
# with garbage head r5=0x589F8000, the first +0x1A6 read faulted.
# SpuClearReverbWorkArea + SpuSetReverbModeType share the MODE TABLE
# at 0x80068E70 (mode<<2 per-mode fn pointers); list heads near
# 0x80068E08/0x80068E0C. STRONG SUSPECT: the R1139 cbguard BLOCKED a
# game store '0x800564A8 <- 1' (writer 8004247C, CD_cbsync) shortly
# before the fault - if that cell is a legit ENABLE FLAG, our heal
# corrupted state and may have SKIPPED the work-area init, leaving
# the head stale. THE RECEIPTS DECIDE heal-vs-game.
# THIS CYCLE: (a) static: the 8004CCB8 walk region + its callsites;
# (b) R1335 camera: every NONZERO write into 0x80068E00-0x80068EA0
# (writer fn + value, cap 64, tag [rvbw]); (c) 120s run; (d) digest:
# the band's write lifecycle + ALL cbguard blocks + fault census +
# timing correlation.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C287-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="ab668553a3e45945572b5c9d41f3e7fbe1726fa67e8796772c83c6a0ff9faf70"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1334 tree ab668553 - refusing, no patch, no run"; exit 0; fi
echo "BASELINE_VERIFIED (the R1334 tree)"
DCA="./disc1.c"
DEXPECT="3d78b0e783c9038fa7213ed29bce1d5db9453e6885bac3845bde6369c6338741"
DS=$(shasum -a 256 "$DCA" | cut -d" " -f1)
echo "DISC1_SHA=$DS"
if [ "$DS" != "$DEXPECT" ]; then echo "GATE-FAILED: disc1.c is not the 3d78b0e7 emission - refusing"; exit 0; fi
echo "DISC1_VERIFIED (fresh emission)"
trunc() { sed -E 's/[A-Za-z0-9_./+-]{34,}/[T]/g' | cut -c1-110; }

echo "===WALK287=== the 8004CCB8 walk region (the chain + the +0x1A6 field read)"
sed -n '155300,155405p' "$DCA" | trunc

echo "===CALLERS287=== who calls 8004CCB8 (callsites + enclosing fn)"
CL=$(grep -n "xenolift_fn_8004CCB8" "$DCA" | grep -v "static void" | cut -d: -f1 | head -8)
echo "callsite_lines=$CL"
for C in $CL; do
  FN=$(awk -v c="$C" 'NR<=c && /^static void/ {last=$0} END{print last}' "$DCA" | cut -c1-72)
  echo "--- line $C in: $FN"
done

echo "===CBGUARD287=== ALL cbguard blocks + cbreg receipts (the c284 witness)"
WLOG="witness_c284_20260917_084145/run.log"
if [ -s "$WLOG" ]; then
  grep -n "cbguard\]" "$WLOG" | head -20
  echo "--- cbreg receipts:"
  grep -n "cbreg\]" "$WLOG" | head -12
fi

echo "===PATCH287=== the R1335 reverb-band camera (gated, FAIL EXPLICIT)"
TS=$(date +%Y%m%d_%H%M%S)
mkdir -p "patch_c287_$TS"
cp -p "$SRC" "patch_c287_$TS/runtime.c.pre"
echo "PRESERVED: patch_c287_$TS/runtime.c.pre sha=$SS"
python3 - <<'PYEOF'
data = open("runtime/runtime.c","rb").read()
anchor = b"    /* R1333 ARCHIVE-BAND WRITE WATCH (c282 decode): the c276-era death"
n = data.count(anchor)
print("R1335 anchor (R1333 comment head) count=%d (must be 1)" % n)
if n != 1:
    print("PATCH-FAILED - anchor count wrong - nothing written, no run")
    raise SystemExit(0)
pre = data.count(b"R1335")
print("R1335 pre count=%d (must be 0)" % pre)
if pre != 0:
    print("PATCH-FAILED - R1335 already present - nothing written, no run")
    raise SystemExit(0)
pre2 = data.count(b"rvb_n")
print("rvb_n pre count=%d (must be 0)" % pre2)
if pre2 != 0:
    print("PATCH-FAILED - rvb_n already used - nothing written, no run")
    raise SystemExit(0)
block = b"""    /* R1335 REVERB-BAND WRITE WATCH (c286 receipts): the fault chain
     * is SpuSetReverbModeType -> SpuClearReverbWorkArea -> the
     * work-area list walk (fn 8004CCB8: r5 = LW(r5 + 0x8E08), field
     * reads at +0x1A6), entered with garbage head r5=0x589F8000 -
     * the first +0x1A6 read faulted (0x589F81A6). The mode table
     * lives at 0x80068E70 (per-mode fn pointers) and the list-head
     * cells near 0x80068E08/0x80068E0C. Watch every NONZERO write
     * into 0x80068E00-0x80068EA0 with the writer fn; cap 64. The
     * receipts decide heal-vs-game: the R1139 cbguard blocked a
     * game store '0x800564A8 <- 1' shortly before the fault - if
     * that block skipped the work-area init, the head stays stale. */
    if (a >= 0x80068E00u && a <= 0x80068EA0u && v != 0u) {
        static int rvb_n;
        if (rvb_n < 64) {
            rvb_n++;
            r861_out("[rvbw] R1335 REVERB-BAND WRITE %08X <- %08X writer_fn=%08X\\n",
                    a, v, (unsigned)xenolift_cur_fn);
        }
    }

"""
post = data.replace(anchor, block + anchor, 1)
c1 = post.count(b"R1335")
print("R1335 post count=%d (must be 2)" % c1)
if c1 != 2:
    print("PATCH-FAILED - R1335 count wrong - nothing written, no run")
    raise SystemExit(0)
c2 = post.count(b"[rvbw]")
print("rvbw tag post count=%d (must be 1)" % c2)
if c2 != 1:
    print("PATCH-FAILED - rvbw tag count wrong - nothing written, no run")
    raise SystemExit(0)
c3 = post.count(b"rvb_n")
print("rvb_n post count=%d (must be 3)" % c3)
if c3 != 3:
    print("PATCH-FAILED - rvb_n count wrong - nothing written, no run")
    raise SystemExit(0)
open("runtime/runtime.c","wb").write(post)
print("PATCH-APPLIED (R1335 camera, one insert, no behavior change)")
PYEOF
SS2=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_SHA=$SS2"
if [ "$SS2" = "$EXPECT" ]; then echo "PATCH-FAILED - tree unchanged"; exit 0; fi

echo "===PARSE287=== the syntax gate (restore from backup on fail)"
clang -fsyntax-only -std=gnu99 "$SRC" 2>/tmp/c287_parse.txt; PRC=$?
echo "PARSE_RC=$PRC"
if [ "$PRC" != "0" ]; then echo "PARSE-FAILED - restoring baseline, no run"; head -6 /tmp/c287_parse.txt; cp -p "patch_c287_$TS/runtime.c.pre" "$SRC"; echo "RESTORED sha=$(shasum -a 256 "$SRC" | cut -d' ' -f1)"; exit 0; fi
echo "PARSE-OK"

echo "===RUN287=== running the R1335 camera build (120s budget)"
RUN_BUDGET_S=120 bash run.sh > /tmp/run_full_c287.txt 2>&1; RRC=$?
echo "RUN_RC=$RRC"
WDIR="witness_c287_$TS"
mkdir -p "$WDIR"
for f in run.log run.log.d; do if [ -f "$f" ]; then cp -p "$f" "$WDIR/$f"; fi; done
cp -p /tmp/run_full_c287.txt "$WDIR/run_full.txt"
echo "WITNESS=$WDIR"
LOG="run.log"; [ -s "$LOG" ] || LOG="run.log.d"
if [ ! -s "$LOG" ]; then echo "C287-FAILED: no run log produced"; tail -20 /tmp/run_full_c287.txt; exit 1; fi
ENDL=$(wc -l < "$LOG" | tr -d " ")
echo "log=$LOG lines=$ENDL"
win() { S=$1; [ "$S" -lt 1 ] && S=1; E=$2; [ "$E" -gt "$ENDL" ] && E="$ENDL"; awk -v s="$S" -v e="$E" 'NR>=s&&NR<=e{printf "%d:%s\n",NR,$0}NR>e{exit}' "$LOG"; }

echo "===RVBW287=== the reverb-band write lifecycle"
grep -n "\[rvbw\]" "$LOG" | head -48
echo "rvbw_receipts=$(grep -c "\[rvbw\]" "$LOG")"

echo "===FAULT287=== the death census"
echo "fault_receipts=$(grep -c "\[fault\]" "$LOG")"
grep -n "computed-garbage\|TRUE DEATH\|segvdie\] R834" "$LOG" | head -8
FF=$(grep -n "computed-garbage" "$LOG" | head -1 | cut -d: -f1)
echo "first_fault_line=$FF"
if [ -n "$FF" ]; then
  echo "--- first fault context:"
  win $((FF-8)) $((FF+12))
  echo "--- the last rvbw receipts before the first fault:"
  grep -n "\[rvbw\]" "$LOG" | awk -F: -v f="$FF" '$1 < f' | tail -8
fi

echo "===CBG287=== ALL cbguard blocks in the NEW run (the heal-vs-game discriminator)"
grep -n "cbguard\]" "$LOG" | head -20
echo "cbguard_blocks=$(grep -c "cbguard\]" "$LOG")"

echo "===STATE287=== the state census"
grep -n "statetbl\] R1104 active" "$LOG" | tail -4
grep -n "rungasp\]" "$LOG" | tail -1

echo "===RUNMETA287=== build/launch/fuse tail"
tail -12 /tmp/run_full_c287.txt
echo "===C287DONE=== reverb-band camera cycle complete - the fix design comes from these receipts"
