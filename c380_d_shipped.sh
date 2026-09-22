#!/bin/bash
# c380_wedgeanatomy.sh - READ-ONLY. NO patch, NO run. The
# c379 census: the run wedged at t=137s in the read-driver
# loop at fn 0x80042AA8 (scanning cell 0x800564A8 + the
# module-window start 0x8006F000-0x8006F0D8) after the
# game requested archive member=6 (LBA 239411, 26012B) -
# FDF8 re-armed to 11644 but NO Setloc/ReadN ever formed
# for 239411: the same ReadN-never-issued class as the
# c353-era file-14 stall. THIS PASS: the wedge anatomy -
# (1) fn 80042AA8 decoded (raw exe words + the disc1.c body
# if present); (2) the kernel request-formation story
# between the Pause completion (~8346) and the spin onset;
# (3) the module-window header values the loop validates.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C380-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="13bc3bafa00d1cb05ddb1496adb335b94c3a49658a5206c2f4f74bd2d7b6c104"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1366 tree - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1366 tree)"
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
if [ ! -s "$LOG" ]; then echo "TREE-ROOT-LOG-MISSING"; exit 0; fi
echo "AUTHORITATIVE LOG = $LOG ($(wc -l < "$LOG" | tr -d ' ') lines)"
echo "===EXELOC380=== the PS-X exe (for the raw decode)"
ls -la SLUS_006.64 2>/dev/null || find . -maxdepth 2 -name "SLUS*" -o -maxdepth 2 -name "*.exe" 2>/dev/null | head -4
EXE="SLUS_006.64"
[ -s "$EXE" ] || EXE=$(find . -maxdepth 2 -name "SLUS*" | head -1)
echo "EXE=$EXE"
echo "===FNDUMP380=== fn 80042AA8 raw instruction words (first 48)"
if [ -s "$EXE" ]; then
  python3 - "$EXE" <<'PYEOF'
import sys, struct
exe = sys.argv[1]
# PS-X exe: 2048-byte header, text at file offset 0x800, loaded at 0x80010000
base_va = 0x80010000
fn_va = 0x80042AA8
off = 0x800 + (fn_va - base_va)
data = open(exe, "rb").read()
if off + 4 > len(data):
    print("FN-OFF-OUT-OF-RANGE off=%d len=%d" % (off, len(data)))
else:
    print("file offset 0x%X (exe size %d)" % (off, len(data)))
    for i in range(48):
        o = off + i*4
        if o + 4 > len(data): break
        w = struct.unpack_from("<I", data, o)[0]
        va = fn_va + i*4
        print("%08X: %08X" % (va, w))
PYEOF
fi
echo "===FNDEC380=== the disc1.c body for 80042AA8 (stale-replica caveat applies)"
DG=$(find . -maxdepth 2 -name "disc1.c" | head -1)
echo "disc1.c = $DG"
if [ -n "$DG" ]; then
  L=$(grep -n "80042AA8" "$DG" | head -3)
  echo "refs: $L"
  FL=$(grep -n "fn_80042AA8" "$DG" | head -1 | cut -d: -f1)
  if [ -n "$FL" ]; then
    S=$((FL-4)); [ $S -lt 1 ] && S=1
    E=$((FL+70))
    awk -v s="$S" -v e="$E" 'NR>=s && NR<=e { print NR": "$0 }' "$DG"
  fi
fi
echo "===REQFORM380=== the kernel story from Pause-completion to the spin (8346-8420 boot 1)"
awk 'NR>=8346 && NR<=8420 { print NR": "$0 }' "$LOG"
echo "===SPINONSET380=== where the wedgespin began (first 4 + count)"
grep -n "wedgespin" "$LOG" | head -4
echo "wedgespin-total $(grep -c "wedgespin" "$LOG" || true)"
echo "===CELLWIN380=== the 0x800564A8 cell receipts (whole log)"
grep -n "564A8" "$LOG" | head -10
echo "===MODWIN380=== the module-window build/content receipts"
grep -n "15205\|window module\|build receipt\|fldsnap" "$LOG" | head -8
echo "===STAB6380=== every 239411 receipt"
grep -n "239411" "$LOG" | head -8
echo "===FDF8ARM380=== the 11644 arm story"
grep -n "2D7C\|2d7c" "$LOG" | head -8
echo "===CURFN380=== the cur_fn/finstamp receipts 8400-11000 (the kernel activity before the spin)"
grep -n "finstamp\|cur_fn" "$LOG" | awk -F: '$1>=8400 && $1<=11000' | head -12
echo "===GETSTATW380=== the game's GetStat polls in the spin era (is the game polling the drive?)"
grep -n "cmd 01\|GetStat" "$LOG" | awk -F: '$1>=8400 && $1<=11000' | head -8
echo "===C380DONE=== the wedge anatomy is extracted"
