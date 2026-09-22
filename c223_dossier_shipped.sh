#!/bin/bash
# c223_firstfault_dossier.sh - READ-ONLY: no patch, no compile, no run.
# Extracts the NEW first-fault dossier from the preserved c222 post-run log:
# (1) the first abort-130 window; (2) the first poison-unpack + its res-cell
# provenance; (3) the restart/postres/chain/arena receipts; (4) the state-1
# module file trace (file#=14); (5) the clean main-return context; (6) the
# mount/stomp census; (7) an ASCII render of the last frame (the 100%
# nonblank screen - OBSERVED, not a scene claim per the c215 rules).
set -u
cd "$HOME/Downloads/xenolift" || { echo "C223-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
LOG="run.log"
EXPECT="656563091452f56159f5362c96ab0b62b1fa039bebc61269d88a653ecdd35d39"
if [ ! -s "$LOG" ]; then echo "C223-FAILED: run.log missing"; exit 1; fi
SS=$(shasum -a 256 "$LOG" | cut -d" " -f1)
echo "LOG_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: run.log is not the c222 post-run log - refusing to extract a foreign log (preserve-first protocol)"; exit 0; fi
echo "BASELINE_VERIFIED (the c222 post-run log)"
P="runlog_preserve_c223_$(date +%Y%m%d_%H%M%S)"
if ! (mkdir -p "$P" && cp -p "$LOG" "$P/run.log"); then echo "C223-FAILED: preserve failed"; exit 1; fi
echo "PRESERVED: $P/run.log sha=$SS size=$(wc -c < "$P/run.log" | tr -d " ") lines=$(wc -l < "$LOG" | tr -d " ")"

firstline() { grep -n "$1" "$LOG" | head -1 | cut -d: -f1; }
win() {
  S=$1; [ "$S" -lt 1 ] && S=1
  awk -v s="$S" -v e="$2" 'NR>=s && NR<=e {printf "%d:%s\n", NR, $0} NR>e {exit}' "$LOG"
}

echo "===ABRT223=== the first abort-130 dossier (120 before, 12 after)"
N=$(firstline "AbortOnGameFault")
echo "first_abrt_line=$N total_abrt=$(grep -c "AbortOnGameFault" "$LOG")"
[ -n "$N" ] && win $((N-120)) $((N+12))

echo "===UNPK223=== the first poison unpack + res provenance (60 before, 8 after)"
N=$(firstline "unpack-fix")
echo "first_unpackfix_line=$N total=$(grep -c "unpack-fix" "$LOG")"
[ -n "$N" ] && win $((N-60)) $((N+8))

echo "===RESCHAIN223=== the restart/postres/chain/arena receipts (the res-cell writers)"
grep -n "\[restart\]\|\[postres\]\|\[chain\]\|\[arena\]\|table-install" "$LOG" | head -30

echo "===FILE14_223=== the state-1 module file trace"
grep -n "file#=14\|member=14\|size-lookup" "$LOG" | head -20

echo "===MOUNT223=== the mount-cell / stomp census"
grep -n "stompcam\|\[mcw\]" "$LOG" | head -20

echo "===EXIT223=== the clean main-return context (60 before, 5 after)"
N=$(firstline "rungasp")
echo "first_rungasp_line=$N total=$(grep -c "rungasp" "$LOG")"
[ -n "$N" ] && win $((N-60)) $((N+5))

echo "===TAIL223=== final 12 lines (the era the run ended in)"
tail -12 "$LOG"

echo "===SHOT223=== the last-frame ASCII render (OBSERVED only - not a scene claim)"
if [ -s vram_live.bin ]; then
  ls -la vram_live.bin | head -1
  python3 - <<'PYEOF'
data = open("vram_live.bin","rb").read()
W,H = 256,240
def px(x,y):
    off=(y*1024+x)*2
    if off+1 >= len(data): return 0
    w = data[off] | (data[off+1]<<8)
    r=(w&0x1F)<<3; g=((w>>5)&0x1F)<<3; b=((w>>10)&0x1F)<<3
    return (r*299+g*587+b*114)//1000
chars=" .:-=+*#%@"
print("--- luminance grid 32x15 (display 256x240 @0,0, sampled every 8x16):")
for gy in range(0,H,16):
    row=""
    for gx in range(0,W,8):
        row += chars[min(9, px(gx,gy)*10//256)]
    print(row)
from collections import Counter
c = Counter()
for y in range(0,H,4):
    for x in range(0,W,4):
        c[px(x,y)//32] += 1
print("--- luminance histogram (32-step buckets -> pixels sampled at 4px stride):")
for k in sorted(c): print(" lum %3d-%3d : %d" % (k*32, k*32+31, c[k]))
PYEOF
else
  echo "no vram_live.bin present"
fi

echo "===C223DONE=== read-only dossier complete - the c224 fix is decided by these receipts"
