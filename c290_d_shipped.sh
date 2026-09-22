#!/bin/bash
# c290_spucam.sh - THE R1336 spu_t VALUE-TIMELINE CAMERA + the
# hle_spu.c census at the correct path.
# THE c289 VERDICT: NOBODY writes the SPU voice-base cell (all 20
# disc1.c refs are LW reads, zero SW); *(0x80068E08) comes only from
# the pristine EXE image (R722/R772: captured @first entry
# 0x80010000..0x8006F000, restored at every fault-walk restart).
# c284's junk head (0x589F8000) vs c287's correct head (0x1F801C00)
# at the same image-only cell = era-dependent runtime-side
# corruption OR the eras differ relative to restores.
# THIS CYCLE: (a) find + grep hle_spu.c at the correct path (band +
# reverb-register refs); (b) R1336: a dispatch-case camera at the
# 8004CCA8 case printing the head cell + mode table + state cells
# (raw memcpy reads, no hook reentry), cap 24, tag [spucam]; (c)
# 120s run; (d) digest: the value timeline per call + at the fault.
# PASS-GATE: if the head is CORRECT at every print and junk at the
# fault, the corruption window is receipted; if junk from the FIRST
# print, the loader is indicted.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C290-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="a8676c1011e7742d7f11eec6a9b819009c66f630041458f4db1fddbe504a0873"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1335 tree a8676c10 - refusing, no patch, no run"; exit 0; fi
echo "BASELINE_VERIFIED (the R1335 tree)"

echo "===HLEFIND290=== the HLE file census at the correct path"
find . -maxdepth 3 -type f \( -name "*spu*" -o -name "hle_*" \) 2>/dev/null | grep -v worktrees | head -10
for F in $(find . -maxdepth 3 -type f -name "*spu*" 2>/dev/null | grep -v worktrees | grep -E "\.(c|h)$" | head -4); do
  echo "--- $F band refs:"
  grep -n "68E08\|68E70\|68E20\|68E58\|68E24" "$F" | head -10 | cut -c1-140
  echo "--- $F reverb/voice-register refs:"
  grep -in "reverb\|1F801D8\|1F801C0" "$F" | head -14 | cut -c1-140
done

echo "===PATCH290=== the R1336 spu_t value-timeline camera (gated, FAIL EXPLICIT)"
TS=$(date +%Y%m%d_%H%M%S)
mkdir -p "patch_c290_$TS"
cp -p "$SRC" "patch_c290_$TS/runtime.c.pre"
echo "PRESERVED: patch_c290_$TS/runtime.c.pre sha=$SS"
python3 - <<'PYEOF'
data = open("runtime/runtime.c","rb").read()
anchor = b"case 0x8004CCA8u:"
n = data.count(anchor)
print("R1336 anchor (dispatch case 0x8004CCA8) count=%d (must be 1)" % n)
if n != 1:
    print("PATCH-FAILED - anchor count wrong - nothing written, no run")
    print("diagnostic: all 8004CCA8 refs in runtime.c:")
    idx = 0
    while True:
        idx = data.find(b"8004CCA8", idx)
        if idx == -1: break
        print("  ...%s..." % data[max(0,idx-50):idx+70].decode("ascii","replace").replace("\n"," | "))
        idx += 1
    raise SystemExit(0)
pre = data.count(b"R1336")
print("R1336 pre count=%d (must be 0)" % pre)
if pre != 0:
    print("PATCH-FAILED - R1336 already present - nothing written, no run")
    raise SystemExit(0)
pre2 = data.count(b"r1336_n")
print("r1336_n pre count=%d (must be 0)" % pre2)
if pre2 != 0:
    print("PATCH-FAILED - r1336_n already used - nothing written, no run")
    raise SystemExit(0)
block = b""" /* R1336 (c289 decode): the SPU voice-base cell (0x80068E08) has
     * NO writer in the guest (20 LW reads, zero SW) - its value comes
     * only from the pristine image (R722/R772). Print it + the mode
     * table + state cells at every spu_t dispatch: the value timeline
     * receipts whether the initial load is correct and when it
     * changes relative to the fault. Cap 24. Raw memcpy reads, no
     * hook reentry. */
    { static int r1336_n;
      if (r1336_n < 24) { r1336_n++;
        uint32_t v_h, v_m0, v_m1, v_m2, v_e58; uint16_t v_e20;
        memcpy(&v_h, xenolift_mem + 0x68E08u, 4);
        memcpy(&v_m0, xenolift_mem + 0x68E70u, 4);
        memcpy(&v_m1, xenolift_mem + 0x68E74u, 4);
        memcpy(&v_m2, xenolift_mem + 0x68E78u, 4);
        memcpy(&v_e20, xenolift_mem + 0x68E20u, 2);
        memcpy(&v_e58, xenolift_mem + 0x68E58u, 4);
        r861_out("[spucam] R1336 spu_t entry #%d head=%08X mode0=%08X mode1=%08X mode2=%08X E20=%04X E58=%08X\\n",
                r1336_n, v_h, v_m0, v_m1, v_m2, v_e20, v_e58);
      } }
"""
post = data.replace(anchor, anchor + block, 1)
c1 = post.count(b"R1336")
print("R1336 post count=%d (must be 2)" % c1)
if c1 != 2:
    print("PATCH-FAILED - R1336 count wrong - nothing written, no run")
    raise SystemExit(0)
c2 = post.count(b"[spucam]")
print("spucam tag post count=%d (must be 1)" % c2)
if c2 != 1:
    print("PATCH-FAILED - spucam tag count wrong - nothing written, no run")
    raise SystemExit(0)
c3 = post.count(b"r1336_n")
print("r1336_n post count=%d (must be 4)" % c3)
if c3 != 4:
    print("PATCH-FAILED - r1336_n count wrong - nothing written, no run")
    raise SystemExit(0)
open("runtime/runtime.c","wb").write(post)
print("PATCH-APPLIED (R1336 camera, one insert, no behavior change)")
PYEOF
SS2=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_SHA=$SS2"
if [ "$SS2" = "$EXPECT" ]; then echo "PATCH-FAILED - tree unchanged"; exit 0; fi

echo "===PARSE290=== the syntax gate (restore from backup on fail)"
clang -fsyntax-only -std=gnu99 "$SRC" 2>/tmp/c290_parse.txt; PRC=$?
echo "PARSE_RC=$PRC"
if [ "$PRC" != "0" ]; then echo "PARSE-FAILED - restoring baseline, no run"; head -6 /tmp/c290_parse.txt; cp -p "patch_c290_$TS/runtime.c.pre" "$SRC"; echo "RESTORED sha=$(shasum -a 256 "$SRC" | cut -d' ' -f1)"; exit 0; fi
echo "PARSE-OK"

echo "===RUN290=== running the R1336 camera build (120s budget)"
RUN_BUDGET_S=120 bash run.sh > /tmp/run_full_c290.txt 2>&1; RRC=$?
echo "RUN_RC=$RRC"
WDIR="witness_c290_$TS"
mkdir -p "$WDIR"
for f in run.log run.log.d; do if [ -f "$f" ]; then cp -p "$f" "$WDIR/$f"; fi; done
cp -p /tmp/run_full_c290.txt "$WDIR/run_full.txt"
echo "WITNESS=$WDIR"
LOG="run.log"; [ -s "$LOG" ] || LOG="run.log.d"
if [ ! -s "$LOG" ]; then echo "C290-FAILED: no run log produced"; tail -20 /tmp/run_full_c290.txt; exit 1; fi
ENDL=$(wc -l < "$LOG" | tr -d " ")
echo "log=$LOG lines=$ENDL"
win() { S=$1; [ "$S" -lt 1 ] && S=1; E=$2; [ "$E" -gt "$ENDL" ] && E="$ENDL"; awk -v s="$S" -v e="$E" 'NR>=s&&NR<=e{printf "%d:%s\n",NR,$0}NR>e{exit}' "$LOG"; }

echo "===SPUCAM290=== the value timeline (every receipt)"
grep -n "\[spucam\]" "$LOG" | head -26
echo "spucam_receipts=$(grep -c "\[spucam\]" "$LOG")"

echo "===FAULT290=== the death census"
echo "fault_receipts=$(grep -c "\[fault\]" "$LOG")"
grep -n "computed-garbage\|TRUE DEATH" "$LOG" | head -6
FF=$(grep -n "computed-garbage" "$LOG" | head -1 | cut -d: -f1)
echo "first_fault_line=$FF"
if [ -n "$FF" ]; then
  echo "--- first fault context:"
  win $((FF-6)) $((FF+10))
  echo "--- the last spucam receipts before the first fault:"
  grep -n "\[spucam\]" "$LOG" | awk -F: -v f="$FF" '$1 < f' | tail -6
fi

echo "===RESTORE290=== the pristine-image restores + band guest-writes in this run"
grep -c "fwrestart\] R772 pristine exe image restored" "$LOG"
grep -n "fwrestart\] R772" "$LOG" | head -6
echo "rvbw_receipts=$(grep -c "\[rvbw\]" "$LOG")"

echo "===STATE290=== the state census"
grep -n "statetbl\] R1104 active" "$LOG" | tail -3
grep -n "rungasp\]" "$LOG" | tail -1

echo "===C290DONE=== spu_t value-timeline cycle complete - the fix design comes from these receipts"
