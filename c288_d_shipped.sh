#!/bin/bash
# c288_raminit_probe.sh - READ-ONLY: the deciding receipts for the
# unzeroed-RAM root-cause candidate.
# THE c287 VERDICT: rvbw_receipts=0 - NOBODY ever writes nonzero
# into the reverb band 0x80068E00-0x80068EA0; the list head
# (0x80068E08) is NEVER initialized by anyone. The game TOLERATES
# head=0 on real HW (the walk r5=*(0x80068E08) then LHU(r5+0x1A6)
# with head=0 lands at 0x1A6 = the low KUSEG RAM mirror - valid,
# reads zero, the walk exits gracefully) but FAULTS on junk
# (0x589F8000/0x22000000-class computed-on-the-fly targets, no cell
# contains them). THE ROOT-CAUSE CANDIDATE: guest RAM starts
# UNZEROED (junk instead of the hardware BIOS zero-fill) and/or the
# low mirror is unmapped.
# THIS PROBE: (a) the runtime's RAM allocation + init code (malloc
# vs calloc/memset - is there ANY boot zero-fill?); (b) the fault
# guard's valid address ranges (does 0x00000000-0x1FFFFF count as
# RAM?); (c) the mem hook's address translation (the low-mirror
# handling); (d) the game's own writer census for 0x8E08 (confirm
# no one is SUPPOSED to write the head); (e) the c287 witness's
# sound-init receipts. No patch, no compile, no run.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C288-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="a8676c1011e7742d7f11eec6a9b819009c66f630041458f4db1fddbe504a0873"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1335 tree a8676c10 - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1335 tree)"
DCA="./disc1.c"
DEXPECT="3d78b0e783c9038fa7213ed29bce1d5db9453e6885bac3845bde6369c6338741"
DS=$(shasum -a 256 "$DCA" | cut -d" " -f1)
echo "DISC1_SHA=$DS"
if [ "$DS" != "$DEXPECT" ]; then echo "GATE-FAILED: disc1.c sha mismatch - refusing"; exit 0; fi
echo "DISC1_VERIFIED (fresh emission)"
WLOG="witness_c287_20260917_085033/run.log"
if [ -s "$WLOG" ]; then echo "WITNESS=$WLOG sha=$(shasum -a 256 "$WLOG" | cut -d" " -f1)"; fi
trunc() { sed -E 's/[A-Za-z0-9_./+-]{34,}/[T]/g' | cut -c1-110; }

echo "===RAMINIT288=== the guest RAM allocation + boot init (is there ANY zero-fill?)"
echo "--- allocation calls:"
grep -n "calloc\|malloc(\|posix_memalign\|realloc(" "$SRC" | head -16
echo "--- memset calls:"
grep -n "memset" "$SRC" | head -20
echo "--- file-scope RAM-ish buffers:"
grep -n "^static uint8_t\|^static unsigned char\|^uint8_t\|^static uint32_t.*\[\|^static uint16_t" "$SRC" | head -20 | trunc

echo "===GUARD288=== the fault guard's valid address ranges (is the low mirror RAM?)"
L=$(grep -n "outside RAM and the register district" "$SRC" | head -1 | cut -d: -f1)
echo "guard print at line $L"
if [ -n "$L" ]; then sed -n "$((L-30)),$((L+6))p" "$SRC" | trunc; fi

echo "===MIRROR288=== the mem hook's address translation (low-mirror handling)"
L2=$(grep -n "^uint32_t xenolift_mem_read16\|^uint16_t xenolift_mem_read16\|xenolift_mem_read16(uint32_t" "$SRC" | head -1 | cut -d: -f1)
echo "read16 hook at line $L2"
if [ -n "$L2" ]; then sed -n "$((L2)),$((L2+70))p" "$SRC" | trunc; fi

echo "===WRITER288=== the game's own 0x8E08/0x8E0C references (writer census)"
HITS=$(grep -n "0x8E08\|0x8E0C" "$DCA" | cut -d: -f1 | head -16)
echo "hit_lines=$HITS"
for C in $HITS; do
  FN=$(awk -v c="$C" 'NR<=c && /^static void/ {last=$0} END{print last}' "$DCA" | cut -c1-72)
  echo "--- line $C in: $FN"
done
echo "--- contexts (first 6 hits, +-6 lines):"
for C in $(echo "$HITS" | head -6); do
  echo "--- hit at line $C:"
  sed -n "$((C-6)),$((C+6))p" "$DCA" | trunc
done

echo "===SND288=== the c287 witness's sound-init receipts"
if [ -s "$WLOG" ]; then
  grep -n "sndinit\]" "$WLOG" | head -10
  echo "--- the first-fault era's reverb/receipt context:"
  grep -n "8004E3C8\|8004DD1C\|8004CCA8\|8004CCB8" "$WLOG" | head -10
fi

echo "===C288DONE=== RAM-init probe complete - the c289 fix design comes from these receipts"
