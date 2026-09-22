#!/bin/bash
# c289_spuwriter_probe.sh - READ-ONLY: name the runtime-side writer of
# the SPU voice-base cell (0x80068E08) + the HLE reverb-register
# semantics.
# THE c288 VERDICT: RAM is zero-filled by construction (static
# file-scope array) - the junk was WRITTEN at runtime. The c287 fault
# had the CORRECT base (r5=0x1F801C00; the walk's +0x180/+0x1A6/
# +0x1AC/+0x1AE accesses = the reverb work-area registers
# 0x1F801D80-0x1F801DAE) and faulted on a garbage INDEX (0x400-class).
# The head cell value DIFFERS between runs (0x589F8000 vs 0x1F801C00)
# with rvbw=0 GUEST-hook writes -> the writer is RUNTIME-SIDE:
# hle_spu.c (WAVE lane) or a DMA path bypassing the guest hook.
# THIS PROBE: (a) hle_spu.c + runtime.c references to the band
# (0x68E08/8E20/8E58/8E70) + the reverb registers; (b) the disc1.c
# SW-writer hunt for 0x8E08 (does the game itself ever store the
# base?); (c) _spu_init + the 8004CCA8 wrapper bodies; (d) the EXE
# data-segment probe (the initializer truth); (e) the fault-moment
# dump files (best-effort read of the head cell). No patch, no
# compile, no run.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C289-FAILED: xenolift dir missing"; exit 1; }
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

echo "===RTBAND289=== hle_spu.c + runtime.c references to the band (the runtime-side writer hunt)"
for F in hle_spu.c runtime/runtime.c; do
  if [ -s "$F" ]; then
    echo "--- $F band refs:"
    grep -n "68E08\|68E70\|68E20\|68E24\|68E38\|68E48\|68E58" "$F" | head -16 | cut -c1-150
    echo "--- $F reverb-register refs (0x1F801D8x):"
    grep -n "1F801D8\|1F801D9\|1f801d8\|reverb" "$F" | head -20 | cut -c1-150
  else
    echo "--- $F NOT FOUND"
  fi
done
echo "--- the reverb-register READ path (hle_spu.c first-hit context):"
H=$(grep -n "1F801D8\|reverb" hle_spu.c 2>/dev/null | head -1 | cut -d: -f1)
if [ -n "$H" ]; then sed -n "$((H-12)),$((H+24))p" hle_spu.c | trunc; fi

echo "===WRITER289=== does the game itself ever SW-store the base (0x8E08)?"
echo "--- all 0x8E08 lines, LW vs SW classified:"
grep -n "0x8E08" "$DCA" | while IFS=: read -r LN REST; do
  case "$REST" in
    *"SW("*)  echo "$LN: SW  ${REST:0:90}";;
    *"LW("*)  echo "$LN: LW  ${REST:0:90}";;
    *)        echo "$LN: ??  ${REST:0:90}";;
  esac
done | head -20
echo "--- any SW-writer context (first 4):"
for C in $(grep -n "0x8E08" "$DCA" | grep "SW(" | cut -d: -f1 | head -4); do
  echo "--- SW hit at line $C (+-6):"
  sed -n "$((C-6)),$((C+6))p" "$DCA" | trunc
done

echo "===SPINIT289=== _spu_init head (how the driver uses/sets the base)"
fnwindow() {
  FN="$1"; MAXL="${2:-90}"
  L=$(grep -n "^static void xenolift_fn_${FN}" "$DCA" | grep -v ";" | head -1 | cut -d: -f1)
  if [ -z "$L" ] || [ "$L" -lt 1 ] 2>/dev/null; then echo "===FN_${FN}: DEF NOT FOUND"; return; fi
  E=$(awk -v s="$L" 'NR>s && /^static void/{print NR; exit}' "$DCA")
  [ -z "$E" ] && E=$((L+MAXL+2))
  echo "===FN_${FN} (def $L .. next def $E, ${MAXL}-capped)==="
  awk -v s="$L" -v e="$((E-1))" 'NR>=s && NR<=e' "$DCA" | head -"$MAXL" | trunc
}
fnwindow 8004C6DC 90
fnwindow 8004CCA8 60

echo "===EXEDATA289=== the boot-EXE receipts + the image-load code (the initializer truth)"
if [ -s "$WLOG" ]; then
  grep -n "file#=1:\|file#=0:\|SCUS\|PS-X\|0x80010000" "$WLOG" | head -10
fi
echo "--- the image/load code in runtime.c:"
grep -n "PS-X\|0x80010000\|t_addr\|entry" "$SRC" | head -16 | cut -c1-150

echo "===DUMPCELL289=== the fault-moment dump files (best-effort head-cell read)"
grep -n "overlay_fault\|stage2_region\|overlay_region" run.sh 2>/dev/null | head -10
ls -la overlay_fault.bin stage2_region.bin overlay_region.bin 2>/dev/null
grep -n "overlay_fault\|stage2_region\|overlay_region" "$SRC" | head -12 | cut -c1-150

echo "===C289DONE=== SPU-writer probe complete - the c290 fix design comes from these receipts"
