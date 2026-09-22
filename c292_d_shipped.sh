#!/bin/bash
# c292_discfind_probe.sh - READ-ONLY: find the real disc image (by
# SIZE, name-independent), read the EXE's own bytes at the pointer
# cells, and receipt the initial-image load mechanism.
# THE c291 RECEIPTS: DEAD0001 = our own camera sentinel (ctx cell
# 0x80059394 genuinely 0); fault#1 = the GPU/DMA packet family
# writing through pointer cells 0x800569A0-0x800569B0 (0x01000401
# is a WRITTEN VALUE); the disc .bin was not at the probed paths
# (the fallback mis-picked a 16B project file - harmless).
# HYPOTHESIS (labeled): image-data pointer cells zero in our loaded
# image; loader dropped EXE .data OR a runtime bulk-copy never ran.
# THIS PROBE: (a) find the disc by SIZE (>100MB under $HOME);
# (b) if found: magic-scan for PS-X EXE, parse t_addr/t_size, dump
# the EXE's own bytes at the pointer cells; (c) the initial-image
# load mechanism receipts (where 0x80010000-0x8006F000 content
# comes from); (d) the SW-writer census for the 0x69Ax band and
# 0x59394; (e) de-truncated fn names. No patch, no compile, no run.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C292-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="ed69fd5f6753b2e0e840ac0471b950b85c2a23c273fcaca356f4ec706831d1dc"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1337 tree ed69fd5f - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1337 tree)"
DCA="./disc1.c"
DEXPECT="3d78b0e783c9038fa7213ed29bce1d5db9453e6885bac3845bde6369c6338741"
DS=$(shasum -a 256 "$DCA" | cut -d" " -f1)
echo "DISC1_SHA=$DS"
if [ "$DS" != "$DEXPECT" ]; then echo "GATE-FAILED: disc1.c sha mismatch - refusing"; exit 0; fi
echo "DISC1_VERIFIED (fresh emission)"
WLOG="witness_c290b_20260917_090559/run.log"
[ -s "$WLOG" ] && echo "WITNESS=$WLOG sha=$(shasum -a 256 "$WLOG" | cut -d" " -f1)"
trunc() { sed -E 's/[A-Za-z0-9_./+-]{34,}/[T]/g' | cut -c1-110; }

echo "===DISC292=== find the real disc (by SIZE, name-independent)"
echo "--- witness disc/banner receipts (first 40 lines, bin-related):"
head -40 "$WLOG" 2>/dev/null | grep -in "bin\|disc\|cue" | head -12
echo "--- runtime.c disc-open code:"
grep -n "BIN\|\.bin\|\.cue" "$SRC" | head -20 | cut -c1-150
echo "--- run.sh disc refs:"
grep -n "BIN\|\.bin\|\.cue" run.sh 2>/dev/null | head -10 | cut -c1-150
echo "--- big-file scan (>100MB, maxdepth 4):"
BIGFILES=$(find "$HOME" -maxdepth 4 -type f -size +100M 2>/dev/null | head -8)
echo "$BIGFILES" | sed '/^$/d'
BIGBIN=$(echo "$BIGFILES" | head -1)
if [ -z "$BIGBIN" ]; then echo "DISC-NOT-FOUND-BY-SIZE: report the above and skip the EXE read"; else
echo "USING_BIGBIN=$BIGBIN size=$(wc -c < "$BIGBIN" | tr -d ' ')"
echo "===EXE292=== the EXE inside the disc (magic scan + header parse + pointer-cell dumps)"
python3 - "$BIGBIN" <<'PYEOF'
import sys, os, struct
path = sys.argv[1]
size = os.path.getsize(path)
f = open(path, "rb")
CH = 1 << 24
hits = []
pos = 0
prev = b""
while pos < size:
    f.seek(pos)
    chunk = f.read(CH)
    if not chunk: break
    hay = prev + chunk
    idx = 0
    while True:
        idx = hay.find(b"PS-X EXE", idx)
        if idx == -1: break
        hits.append(pos - len(prev) + idx)
        idx += 1
    prev = chunk[-8:]
    pos += CH
    if len(hits) >= 8: break
print("magic_hits=%d" % len(hits))
cells = [0x800569A0, 0x800569A4, 0x800569A8, 0x800569AC, 0x800569B0,
         0x80068E08, 0x80068E0C, 0x80068E70, 0x80068E74,
         0x80059394, 0x8005A238, 0x8006A238]
for h in hits[:4]:
    f.seek(h)
    hdr = f.read(0x800)
    if hdr[:8] != b"PS-X EXE":
        continue
    pc, gp, t_addr, t_size, s_addr, s_size = struct.unpack_from("<IIIIII", hdr, 0x08)
    print("EXE @bin_off=%d: pc=%08X gp=%08X t_addr=%08X t_size=%08X (%u bytes) s_addr=%08X s_size=%08X" % (h, pc, gp, t_addr, t_size, t_size, s_addr, s_size))
    text_off = h + 0x800
    for g in cells:
        if t_addr <= g < t_addr + t_size:
            off = text_off + (g - t_addr)
            f.seek(off)
            d = f.read(16)
            print("  guest %08X -> bin_off=%d words: %08X %08X %08X %08X" % (
                g, off,
                struct.unpack_from("<I", d, 0)[0],
                struct.unpack_from("<I", d, 4)[0],
                struct.unpack_from("<I", d, 8)[0],
                struct.unpack_from("<I", d, 12)[0]))
        else:
            print("  guest %08X -> OUTSIDE text range" % g)
    print("  loaded-image comparison: head=0 mode0=0 mode1=0 ctx=0 (c290b receipts)")
PYEOF
fi

echo "===LOAD292=== the initial-image load mechanism (where does 0x80010000+ content come from?)"
echo "--- EXE-header/segment refs in runtime.c:"
grep -n "PS-X\|t_addr\|t_size\|s_addr\|s_size\|exehdr" "$SRC" | head -16 | cut -c1-150
echo "--- the R722 pristine-capture site context:"
L=$(grep -n "R722 pristine" "$SRC" | head -1 | cut -d: -f1)
if [ -n "$L" ]; then sed -n "$((L-24)),$((L+10))p" "$SRC" | trunc; fi

echo "===PTR292=== the pointer-band SW-writer census (disc1.c)"
for PAT in "0x69A0" "0x69A4" "0x69A8" "0x69AC" "0x69B0" "0x59394"; do
  CNT=$(grep -c "$PAT" "$DCA")
  SW=$(grep "$PAT" "$DCA" | grep -c "SW(")
  LW=$(grep "$PAT" "$DCA" | grep -c "LW(")
  echo "$PAT: total=$CNT SW=$SW LW=$LW"
done
echo "--- the 0x69A4 contexts (first 4 hits, +-4):"
for C in $(grep -n "0x69A4" "$DCA" | cut -d: -f1 | head -4); do
  echo "--- hit at line $C:"
  sed -n "$((C-4)),$((C+4))p" "$DCA" | trunc
done

echo "===FN292=== de-truncated fn names (role hints)"
grep -n "xenolift_fn_800465EC\|xenolift_fn_80046638\|xenolift_fn_80046074\|xenolift_fn_8004668C\|xenolift_fn_80046EFC" "$DCA" | grep "static void" | cut -c1-140 | head -10
echo "--- the 80046074 callee (full call line):"
sed -n '140403,140436p' "$DCA" | grep "xenolift_fn" | cut -c1-140 | head -4

echo "===C292DONE=== disc-find probe complete - the loader-vs-copy verdict comes from these receipts"
