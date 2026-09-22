#!/bin/bash
# c291_discgroundtruth_probe.sh - READ-ONLY: the disc .bin is the
# ground truth for the image-load fidelity question.
# THE c290b RECEIPTS: the pristine capture holds head=0 mode0=0
# mode1=0 (the SPU driver's voice-base AND mode table ALL ZERO in
# the loaded image); the head cell read twice in 120s, both zero,
# no transitions. NEW fault family: fault#1 (target 0x01000401 at
# fn 800465EC, consuming structs at 0x8005A238/0x8005A25C) and
# faults consuming STRING BYTES as pointers (0x5B5A5958='XYZ[').
# HYPOTHESIS (labeled): the image .data may be MIS-LOADED.
# THIS PROBE: (a) find the disc .bin; (b) scan it for the PS-X EXE
# magic, parse t_addr/t_size/s_addr/s_size; (c) dump the DISC's
# own bytes at the exact file offsets for the suspect cells
# (0x80068E08 head, 0x80068E70 mode table, 0x8005A238/0x8005A25C
# fault structs, 0x80059330 latch, 0x80059394 ctx) and compare
# against the loaded zeros; (d) DEAD0001 provenance (whose poison
# is it?); (e) the fault#1 chain decode (fn 800465EC, 80046074,
# 80046638 heads). No patch, no compile, no run.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C291-FAILED: xenolift dir missing"; exit 1; }
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
if [ -s "$WLOG" ]; then echo "WITNESS=$WLOG sha=$(shasum -a 256 "$WLOG" | cut -d" " -f1)"; fi
trunc() { sed -E 's/[A-Za-z0-9_./+-]{34,}/[T]/g' | cut -c1-110; }

echo "===BIN291=== find the disc .bin (the ground truth)"
BIN=""
if [ -s "$WLOG" ]; then
  BIN=$(grep -m1 -o "BIN=[^ ]*" "$WLOG" | cut -d= -f2)
  echo "witness BIN receipt: $BIN"
fi
if [ -z "$BIN" ] || [ ! -s "$BIN" ]; then
  echo "--- witness path unusable; candidate scan:"
  for C in "$HOME"/Desktop/PS7Z/*.bin "$HOME"/Downloads/*.bin ./*.bin; do
    [ -s "$C" ] && echo "candidate: $C ($(wc -c < "$C" | tr -d ' ') bytes)"
  done
  for C in "$HOME"/Desktop/PS7Z/*.bin "$HOME"/Downloads/*.bin ./*.bin; do
    if [ -s "$C" ]; then BIN="$C"; break; fi
  done
fi
if [ -z "$BIN" ] || [ ! -s "$BIN" ]; then echo "C291-BIN-NOT-FOUND: no usable .bin - report candidates and stop"; exit 0; fi
echo "USING_BIN=$BIN size=$(wc -c < "$BIN" | tr -d ' ')"

echo "===EXE291=== the PS-X EXE inside the disc (magic scan + header parse + cell dumps)"
echo "--- magic scan (byte offsets):"
grep -abo "PS-X EXE" "$BIN" | head -6
python3 - "$BIN" <<'PYEOF'
import sys, struct
b = open(sys.argv[1], "rb").read(0)  # placeholder; use seek-based reads below
f = open(sys.argv[1], "rb")
import os
size = os.path.getsize(sys.argv[1])
f.seek(0)
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
cells = [0x80068E08, 0x80068E0C, 0x80068E70, 0x80068E74, 0x80068E78,
         0x8005A238, 0x8005A25C, 0x80059330, 0x80059394]
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
            u32 = struct.unpack_from("<I", d, 0)[0]
            print("  guest %08X -> bin_off=%d words: %08X %08X %08X %08X  raw=%s" % (
                g, off, u32,
                struct.unpack_from("<I", d, 4)[0],
                struct.unpack_from("<I", d, 8)[0],
                struct.unpack_from("<I", d, 12)[0],
                d.hex().upper()))
        else:
            print("  guest %08X -> OUTSIDE text range" % g)
    print("  loaded-image comparison: head=0 mode0=0 mode1=0 (c290b pristine capture)")
PYEOF

echo "===DEAD291=== the DEAD0001 poison provenance"
echo "--- runtime.c refs:"
grep -n "DEAD0001\|0xDEAD" "$SRC" | head -12
H=$(grep -n "DEAD0001" "$SRC" | head -1 | cut -d: -f1)
if [ -n "$H" ]; then sed -n "$((H-10)),$((H+14))p" "$SRC" | trunc; fi
echo "--- witness DEAD0001 receipts:"
if [ -s "$WLOG" ]; then grep -n "DEAD0001" "$WLOG" | head -8; fi

echo "===FN291=== the fault#1 chain decode"
fnwindow() {
  FN="$1"; MAXL="${2:-50}"
  L=$(grep -n "^static void xenolift_fn_${FN}" "$DCA" | grep -v ";" | head -1 | cut -d: -f1)
  if [ -z "$L" ] || [ "$L" -lt 1 ] 2>/dev/null; then echo "===FN_${FN}: DEF NOT FOUND"; return; fi
  E=$(awk -v s="$L" 'NR>s && /^static void/{print NR; exit}' "$DCA")
  [ -z "$E" ] && E=$((L+MAXL+2))
  echo "===FN_${FN} (def $L .. next def $E, ${MAXL}-capped)==="
  awk -v s="$L" -v e="$((E-1))" 'NR>=s && NR<=e' "$DCA" | head -"$MAXL" | trunc
}
fnwindow 800465EC 60
fnwindow 80046074 40
fnwindow 80046638 40

echo "===FKCTX291=== the ctx-cell story + the R423 comment"
if [ -s "$WLOG" ]; then grep -n "fkctx" "$WLOG" | head -8; fi
R=$(grep -n "R423" "$SRC" | head -1 | cut -d: -f1)
if [ -n "$R" ]; then sed -n "$((R-8)),$((R+10))p" "$SRC" | trunc; fi

echo "===C291DONE=== disc-ground-truth probe complete - the loader verdict comes from these receipts"
