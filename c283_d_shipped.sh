#!/bin/bash
# c283_fbw_camera.sh - THE R1333 ARCHIVE-BAND WRITE CAMERA + 120s
# witness run.
# THE c282 FULL-DECODE VERDICT: the Vsync helper (8004B55C) is
# EXONERATED - pure fixed-cell frame-wait arithmetic; it cannot
# compute 0x00200000. THE FAULT = the LZSS core entry: first
# instruction LW(r4=src=0x00200000 = the heap free-sentinel flags
# value, a FREED NODE consumed as the unpack source) -> BadVAddr at
# EPC 0x80032EB4; dst 0x80400813 garbage; called during the v_wait
# dispatch era. faultctx R696 names stale archive cell 0x8004FB6C
# (pre-FDF0 band) among the cells holding the target - and NO
# writer camera watches that band.
# THIS CYCLE (cameras only, no behavior change, c354 discipline):
# add R1333 - a NONZERO write-watch on 0x8004FB40..0x8004FBF0
# (writer fn + value, cap 64, tag [fbw]), inserted before the R763
# comment block in the same write-hook as R755/R763/R778 (a, v,
# r861_out, xenolift_cur_fn all in scope there). Then a 120s
# witness run to receipt WHO writes 0x00200000 into the band and
# WHEN relative to the first fault. The c276-era death census
# (3 computed-garbage recoveries + segvdie) should be UNCHANGED -
# a camera must not alter behavior; any census change is a
# finding, not an auto-revert.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C283-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="0cc8f8599ef2adcef29ac528864d80eb217a4c8c2a9e597c69b3b435e4982907"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1332 tree 0cc8f859 - refusing, no patch, no run"; exit 0; fi
echo "BASELINE_VERIFIED (the R1332 tree)"
TS=$(date +%Y%m%d_%H%M%S)
mkdir -p "patch_c283_$TS"
cp -p "$SRC" "patch_c283_$TS/runtime.c.pre"
echo "PRESERVED: patch_c283_$TS/runtime.c.pre sha=$(shasum -a 256 "patch_c283_$TS/runtime.c.pre" | cut -d" " -f1)"

echo "===PATCH283=== the R1333 archive-band write camera (gated, FAIL EXPLICIT)"
python3 - <<'PYEOF'
data = open("runtime/runtime.c","rb").read()
anchor = b"    /* R763 INSTANCE-REGION WRITE WATCH: c341 verdict - banks 1-3 are ALL"
n = data.count(anchor)
print("R1333 anchor R763-comment count=%d (must be 1)" % n)
if n != 1:
    print("PATCH-FAILED - anchor count wrong - nothing written, no run")
    raise SystemExit(0)
pre = data.count(b"R1333")
print("R1333 pre count=%d (must be 0)" % pre)
if pre != 0:
    print("PATCH-FAILED - R1333 already present - nothing written, no run")
    raise SystemExit(0)
pre2 = data.count(b"fbw_n")
print("fbw_n pre count=%d (must be 0)" % pre2)
if pre2 != 0:
    print("PATCH-FAILED - fbw_n already used - nothing written, no run")
    raise SystemExit(0)
block = b"""    /* R1333 ARCHIVE-BAND WRITE WATCH (c282 decode): the c276-era death
     * class - the LZSS decompress core entered with src=0x00200000 (the
     * heap free-sentinel flags value, a freed node consumed as the
     * unpack source) at EPC 0x80032EB4; faultctx R696 names 0x8004FB6C
     * (archive cell family, pre-FDF0 band) among the stale cells
     * holding the target. NO writer camera watches that band. Log
     * every NONZERO write with the writer fn; cap 64. */
    if (a >= 0x8004FB40u && a <= 0x8004FBF0u && v != 0u) {
        static int fbw_n;
        if (fbw_n < 64) {
            fbw_n++;
            r861_out("[fbw] R1333 ARCHIVE-BAND WRITE %08X <- %08X writer_fn=%08X\\n",
                    a, v, (unsigned)xenolift_cur_fn);
        }
    }

"""
post = data.replace(anchor, block + anchor, 1)
c1 = post.count(b"R1333")
print("R1333 post count=%d (must be 2)" % c1)
if c1 != 2:
    print("PATCH-FAILED - R1333 post count wrong - nothing written, no run")
    raise SystemExit(0)
c2 = post.count(b"[fbw]")
print("fbw tag post count=%d (must be 1)" % c2)
if c2 != 1:
    print("PATCH-FAILED - fbw tag count wrong - nothing written, no run")
    raise SystemExit(0)
c3 = post.count(b"fbw_n")
print("fbw_n post count=%d (must be 3)" % c3)
if c3 != 3:
    print("PATCH-FAILED - fbw_n count wrong - nothing written, no run")
    raise SystemExit(0)
open("runtime/runtime.c","wb").write(post)
print("PATCH-APPLIED (R1333 camera, one insert, no behavior change)")
PYEOF
SS2=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_SHA=$SS2"
if [ "$SS2" = "$EXPECT" ]; then echo "PATCH-FAILED - tree unchanged"; exit 0; fi

echo "===PARSE283=== the syntax gate (FAIL EXPLICIT, restore from backup on fail)"
clang -fsyntax-only -std=gnu99 "$SRC" 2>/tmp/c283_parse.txt; PRC=$?
echo "PARSE_RC=$PRC"
if [ "$PRC" != "0" ]; then echo "PARSE-FAILED - restoring baseline, no run"; head -6 /tmp/c283_parse.txt; cp -p "patch_c283_$TS/runtime.c.pre" "$SRC"; echo "RESTORED sha=$(shasum -a 256 "$SRC" | cut -d' ' -f1)"; exit 0; fi
echo "PARSE-OK"

echo "===RUN283=== running the R1333 camera build (120s budget)"
RUN_BUDGET_S=120 bash run.sh > /tmp/run_full_c283.txt 2>&1; RRC=$?
echo "RUN_RC=$RRC"
WDIR="witness_c283_$TS"
mkdir -p "$WDIR"
for f in run.log run.log.d; do if [ -f "$f" ]; then cp -p "$f" "$WDIR/$f"; fi; done
cp -p /tmp/run_full_c283.txt "$WDIR/run_full.txt"
echo "WITNESS=$WDIR"
for f in "$WDIR"/run.log "$WDIR"/run.log.d "$WDIR"/run_full.txt; do if [ -f "$f" ]; then echo "  $(basename "$f") size=$(wc -c < "$f" | tr -d ' ') sha=$(shasum -a 256 "$f" | cut -d' ' -f1)"; fi; done

LOG="run.log"; [ -s "$LOG" ] || LOG="run.log.d"
if [ ! -s "$LOG" ]; then echo "C283-FAILED: no run log produced"; tail -20 /tmp/run_full_c283.txt; exit 1; fi
ENDL=$(wc -l < "$LOG" | tr -d " ")
echo "log=$LOG lines=$ENDL"
win() { S=$1; [ "$S" -lt 1 ] && S=1; E=$2; [ "$E" -gt "$ENDL" ] && E=$ENDL; awk -v s="$S" -v e="$E" 'NR>=s&&NR<=e{printf "%d:%s\n",NR,$0}NR>e{exit}' "$LOG"; }

echo "===FBW283=== every archive-band write receipt (the writer hunt)"
grep -n "\[fbw\]" "$LOG" | head -48
FBWC=$(grep -c "\[fbw\]" "$LOG")
echo "fbw_receipts=$FBWC"

echo "===FAULT283=== the death census (must be the c276 class, unchanged by the camera)"
echo "fault_receipts=$(grep -c "\[fault\]" "$LOG")"
grep -n "computed-garbage\|TRUE DEATH\|segvdie" "$LOG" | head -8
FF=$(grep -n "computed-garbage" "$LOG" | head -1 | cut -d: -f1)
echo "first_fault_line=$FF"
if [ -n "$FF" ]; then echo "--- first fault context:"; win $((FF-6)) $((FF+12)); fi
echo "--- the last fbw receipt before the first fault:"
if [ -n "$FF" ]; then grep -n "\[fbw\]" "$LOG" | awk -F: -v f="$FF" '$1 < f' | tail -6; fi

echo "===LZSS283=== the lzss receipts near the fault era"
grep -n "lzss" "$LOG" | awk -F: -v f="${FF:-99999999}" '$1 > (f-400) && $1 < (f+400)' | head -10

echo "===STATE283=== the state census (no behavior change expected)"
grep -n "statetbl\] R1104\|bootentry\] R710" "$LOG" | tail -6
grep -n "exentry\|rungasp\|exit 99\|exitdiag" "$LOG" | tail -6

echo "===RUNMETA283=== build/launch/fuse tail"
tail -18 /tmp/run_full_c283.txt

echo "===DONE283=== R1333 camera cycle complete - the c284 fix design comes from the fbw receipts"
