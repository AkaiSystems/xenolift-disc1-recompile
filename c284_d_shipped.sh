#!/bin/bash
# c284_screen_shhead.sh - (A) render the fault-moment screen (the
# c283 run's crash wrote vram.bin at the MENU-ERA fault) to PNG +
# base64 for Jos to see in chat; (B) fn-name probes (what are
# 800357C0 / the 800734E8/800734FC dispatcher pair / the menu-era
# heap chain); (C) R1334: the SOUND-HEAP HEAD camera (0x80059410 +
# the new R696 stale cells 0x80083964 / 0x800936C0) + a 120s run
# to receipt the head lifecycle at the menu-era fault.
# THE c283 DECODE: the archive band is a 32-entry POWER-OF-TWO MASK
# TABLE (0x400<<i) written by guest fn 800357C0 at menu init - the
# fault targets (0x00200000, 0x04000000) are TABLE ENTRIES consumed
# as pointers. The fault chain: KernelMenuMain+2103 -> 80019B00 ->
# HeapRelocate -> 80032240 -> HeapFree+808 -> the sound-sample
# dispatcher (800734E8/800734FC) -> the LZSS core with a mask-table
# entry as the sample-source pointer - likely an EXHAUSTED sound
# heap (head 0x80059410 popped to 0).
set -u
cd "$HOME/Downloads/xenolift" || { echo "C284-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="afffcd8c05f00a7b95efe093e02a6f42b7696343918a928a6e1bb9dd45171af5"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1333 tree afffcd8c - refusing, no patch, no run"; exit 0; fi
echo "BASELINE_VERIFIED (the R1333 tree)"
trunc() { sed -E 's/[A-Za-z0-9_./+-]{34,}/[T]/g' | cut -c1-110; }
TS=$(date +%Y%m%d_%H%M%S)
W3=$(ls -d witness_c283_* 2>/dev/null | head -1)
WLOG="$W3/run.log"
[ -s "$WLOG" ] || WLOG="run.log"
if [ -s "$WLOG" ]; then
  echo "WITNESS283=$WLOG sha=$(shasum -a 256 "$WLOG" | cut -d" " -f1) (c283 run: db5014cefe243c52b59e3ab1619e8c9b1e94be559f0e2ffa56db9f2988c8a5c5)"
fi

echo "===FNAMES284=== the identities (disc1.c def lines, names only)"
for FN in 800357C0 800734E8 800734FC 800467A0 80019B00 80032240 800320E8; do
  echo "--- $FN:"
  grep -n "^static void xenolift_fn_${FN}" disc1.c 2>/dev/null | grep -v ";" | head -1 | trunc
done

echo "===ALLOC284=== the sound-heap lifecycle receipts (c283 witness, menu era)"
if [ -s "$WLOG" ]; then
  grep -n "AllocateSoundHeapBlock\|SoundHeapInitialize\|SoundInitialize\|free-list head" "$WLOG" | awk -F: '$1>=29000' | head -14
  echo "--- head cell 80059410 receipts (menu era onward):"
  grep -n "80059410" "$WLOG" | awk -F: '$1>=29000' | head -12
fi

echo "===SCREENPREP284=== preserve + render the fault-moment screen (vram.bin from the c283 crash capture)"
mkdir -p "screen_c284_$TS"
B64FILE="/tmp/screen_c284.b64"
rm -f "$B64FILE"
if [ -s vram.bin ]; then
  cp -p vram.bin "screen_c284_$TS/vram_at_fault.bin"
  echo "preserved: screen_c284_$TS/vram_at_fault.bin size=$(wc -c < "screen_c284_$TS/vram_at_fault.bin" | tr -d " ")"
  python3 - "screen_c284_$TS/vram_at_fault.bin" "screen_c284_$TS/screen.png" "$B64FILE" <<'PYEOF'
import sys, zlib, struct, base64
raw = open(sys.argv[1], "rb").read()
W, H = 256, 240
STRIDE = 1024 * 2
def render(w, h, xs, ys):
    px = []
    counts = {}
    for y in range(h):
        row = bytearray()
        base = (y * ys) * STRIDE
        for x in range(w):
            v = struct.unpack_from("<H", raw, base + (x * xs) * 2)[0]
            r = (v & 0x1F) << 3; g = ((v >> 5) & 0x1F) << 3; b = ((v >> 10) & 0x1F) << 3
            row += bytes((r, g, b))
            counts[(r, g, b)] = counts.get((r, g, b), 0) + 1
        px.append(bytes(row))
    return px, counts
def write_png(w, h, px, path):
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    idat = zlib.compress(b"".join(b"\x00" + r for r in px), 9)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b"")
    open(path, "wb").write(png)
    return len(png)
px, counts = render(W, H, 1, 1)
top = sorted(counts.items(), key=lambda kv: -kv[1])[:8]
print("unique_colors=%d" % len(counts))
for c, n in top:
    print("COLOR %02X%02X%02X count=%d frac=%.4f" % (c[0], c[1], c[2], n, n / float(W * H)))
n1 = write_png(W, H, px, sys.argv[2])
b64 = base64.b64encode(open(sys.argv[2], "rb").read()).decode()
if len(b64) > 60000:
    px2, _ = render(64, 60, 4, 4)
    write_png(64, 60, px2, sys.argv[2] + ".small.png")
    b64 = base64.b64encode(open(sys.argv[2] + ".small.png", "rb").read()).decode()
    print("DOWNSCALED to 64x60")
open(sys.argv[3], "w").write(b64)
print("PNG_BYTES=%d BASE64_CHARS=%d" % (n1, len(b64)))
PYEOF
else
  echo "SCREEN-FAILED: vram.bin not found"
fi

echo "===PATCH284=== the R1334 sound-heap head camera (gated, FAIL EXPLICIT)"
mkdir -p "patch_c284_$TS"
cp -p "$SRC" "patch_c284_$TS/runtime.c.pre"
echo "PRESERVED: patch_c284_$TS/runtime.c.pre sha=$SS"
python3 - <<'PYEOF'
data = open("runtime/runtime.c","rb").read()
anchor = b"    /* R1333 ARCHIVE-BAND WRITE WATCH (c282 decode): the c276-era death"
n = data.count(anchor)
print("R1334 anchor (R1333 comment head) count=%d (must be 1)" % n)
if n != 1:
    print("PATCH-FAILED - anchor count wrong - nothing written, no run")
    raise SystemExit(0)
pre = data.count(b"R1334")
print("R1334 pre count=%d (must be 0)" % pre)
if pre != 0:
    print("PATCH-FAILED - R1334 already present - nothing written, no run")
    raise SystemExit(0)
pre2 = data.count(b"shh_n")
print("shh_n pre count=%d (must be 0)" % pre2)
if pre2 != 0:
    print("PATCH-FAILED - shh_n already used - nothing written, no run")
    raise SystemExit(0)
block = b"""    /* R1334 SOUND-HEAP HEAD WATCH (c283 receipts): the fault chain
     * is decoded - the menu era (KernelMenuMain -> 80019B00 ->
     * HeapRelocate -> 80032240 -> HeapFree) runs the sound-sample
     * dispatcher (fntrail 800734E8/800734FC alternating) which calls
     * the LZSS core with src = a MASK-TABLE entry value (0x04000000 =
     * cell 0x8004FB80; the band 0x8004FB40-0x8004FB94 is the 32-entry
     * power-of-two table fn 800357C0 writes at menu init) - the
     * dispatcher consumed a garbage sample-source pointer, likely
     * from an EXHAUSTED sound heap (g_SoundHeapHead 0x80059410 was
     * popped to 0 in the c276 receipts). Watch every write to the
     * head + the new R696 stale cells 0x80083964 / 0x800936C0.
     * Cap 72. */
    if (a == 0x80059410u || a == 0x80083964u || a == 0x800936C0u) {
        static unsigned shh_n;
        if (shh_n < 72u) {
            shh_n++;
            r861_out("[shhead] R1334 WRITE %08X <- %08X writer_fn=%08X\\n",
                    a, v, (unsigned)xenolift_cur_fn);
        }
    }

"""
post = data.replace(anchor, block + anchor, 1)
c1 = post.count(b"R1334")
print("R1334 post count=%d (must be 2)" % c1)
if c1 != 2:
    print("PATCH-FAILED - R1334 count wrong - nothing written, no run")
    raise SystemExit(0)
c2 = post.count(b"[shhead]")
print("shhead tag post count=%d (must be 1)" % c2)
if c2 != 1:
    print("PATCH-FAILED - shhead tag count wrong - nothing written, no run")
    raise SystemExit(0)
c3 = post.count(b"shh_n")
print("shh_n post count=%d (must be 3)" % c3)
if c3 != 3:
    print("PATCH-FAILED - shh_n count wrong - nothing written, no run")
    raise SystemExit(0)
open("runtime/runtime.c","wb").write(post)
print("PATCH-APPLIED (R1334 camera, one insert, no behavior change)")
PYEOF
SS2=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_SHA=$SS2"
if [ "$SS2" = "$EXPECT" ]; then echo "PATCH-FAILED - tree unchanged"; exit 0; fi

echo "===PARSE284=== the syntax gate (restore from backup on fail)"
clang -fsyntax-only -std=gnu99 "$SRC" 2>/tmp/c284_parse.txt; PRC=$?
echo "PARSE_RC=$PRC"
if [ "$PRC" != "0" ]; then echo "PARSE-FAILED - restoring baseline, no run"; head -6 /tmp/c284_parse.txt; cp -p "patch_c284_$TS/runtime.c.pre" "$SRC"; echo "RESTORED sha=$(shasum -a 256 "$SRC" | cut -d' ' -f1)"; exit 0; fi
echo "PARSE-OK"

echo "===RUN284=== running the R1334 camera build (120s budget)"
RUN_BUDGET_S=120 bash run.sh > /tmp/run_full_c284.txt 2>&1; RRC=$?
echo "RUN_RC=$RRC"
WDIR="witness_c284_$TS"
mkdir -p "$WDIR"
for f in run.log run.log.d; do if [ -f "$f" ]; then cp -p "$f" "$WDIR/$f"; fi; done
cp -p /tmp/run_full_c284.txt "$WDIR/run_full.txt"
echo "WITNESS=$WDIR"
LOG="run.log"; [ -s "$LOG" ] || LOG="run.log.d"
if [ ! -s "$LOG" ]; then echo "C284-FAILED: no run log produced"; tail -20 /tmp/run_full_c284.txt; exit 1; fi
ENDL=$(wc -l < "$LOG" | tr -d " ")
echo "log=$LOG lines=$ENDL"
win() { S=$1; [ "$S" -lt 1 ] && S=1; E=$2; [ "$E" -gt "$ENDL" ] && E="$ENDL"; awk -v s="$S" -v e="$E" 'NR>=s&&NR<=e{printf "%d:%s\n",NR,$0}NR>e{exit}' "$LOG"; }

echo "===SHHEAD284=== the sound-heap head lifecycle receipts"
grep -n "\[shhead\]" "$LOG" | head -40
echo "shhead_receipts=$(grep -c "\[shhead\]" "$LOG")"

echo "===FAULT284=== the death census"
echo "fault_receipts=$(grep -c "\[fault\]" "$LOG")"
grep -n "computed-garbage\|TRUE DEATH\|segvdie\] R834" "$LOG" | head -8
FF=$(grep -n "computed-garbage" "$LOG" | head -1 | cut -d: -f1)
echo "first_fault_line=$FF"
if [ -n "$FF" ]; then
  echo "--- first fault context:"
  win $((FF-8)) $((FF+12))
  echo "--- the last shhead receipts before the first fault:"
  grep -n "\[shhead\]" "$LOG" | awk -F: -v f="$FF" '$1 < f' | tail -8
  echo "--- the last fbw receipts before the first fault:"
  grep -n "\[fbw\]" "$LOG" | awk -F: -v f="$FF" '$1 < f' | tail -4
fi

echo "===STATE284=== the state census"
grep -n "statetbl\] R1104 active\|bootentry\] R710" "$LOG" | tail -8
grep -n "rungasp\]" "$LOG" | tail -1

echo "===SCREEN284=== the fault-moment screen PNG (base64, for chat display)"
if [ -s "$B64FILE" ]; then
  echo "---SCREEN_PNG_BASE64_BEGIN---"
  cat "$B64FILE"
  echo ""
  echo "---SCREEN_PNG_BASE64_END---"
else
  echo "SCREEN-FAILED: no base64 produced"
fi
echo "===C284DONE=== screen + sound-heap camera cycle complete - digest is pure ASCII"
