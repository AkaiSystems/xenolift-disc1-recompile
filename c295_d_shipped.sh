#!/bin/bash
# c295_mips_truth_probe.sh - READ-ONLY: the REAL MIPS vs the
# emitted C, instruction by instruction - the discriminator
# between the EMIT-DEFECT and the GAME-REALLY-DOES-THIS readings.
# THE c294 RECEIPTS: the disc's GPU band (0x80056990+) is a smooth
# monotonic fixed-point series (sine-class math table), NOT
# pointers - yet the emitted fns cwc/param (800465EC/80046638)
# read the cells and SW THROUGH the values as store targets. Both
# consumed heap structs (0x8005A238, 0x8006A238) are OUTSIDE the
# image (runtime-init memory). The image loads byte-exact.
# HYPOTHESES: (a) EMIT DEFECT - the emitted C mis-decodes the
# real MIPS at these fns (TRAILBLAZER/Rust-tool suspect); (b) the
# game really stores through the values (KUSEG-mirror-tolerable)
# and the band is rewritten at runtime by computed-offset code.
# THIS PROBE: (a) dump the REAL MIPS at 0x800465EC (40 insns),
# 0x80046638 (20), 0x80046074 (16) from the disc, decoded by a
# mini-disassembler (lui/ori/lw/sw/addiu/jal/j/beq/bne/special);
# (b) the emitted C for the same fns, side by side; (c) the band
# table bounds + header cells (discontinuity scan around the
# series). VERDICT RULE: MIPS matches emit -> hypothesis (b) ->
# band-write camera next; MIPS differs -> hypothesis (a) -> the
# fix lands in the Rust emitter. No patch, no compile, no run.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C295-FAILED: xenolift dir missing"; exit 1; }
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

BIN="${XG_DISC_BIN:-$HOME/Desktop/PS7Z/PS1Games/Xenogears (USA) (Disc 1)/Xenogears (USA) (Disc 1)/Xenogears (USA) (Disc 1).bin}"
echo "DISC=$BIN"
if [ ! -s "$BIN" ]; then echo "C295-DISC-NOT-FOUND at the receipted path (set XG_DISC_BIN)"; exit 0; fi
python3 - "$BIN" <<'PYEOF'
import sys, struct
path = sys.argv[1]
f = open(path, "rb")
EXE_LBA = 108606
T_ADDR = 0x80010000
def user(lba):
    f.seek(lba * 2352)
    return f.read(2352)[24:24 + 2048]
def file_words(cell, n):
    off = cell - T_ADDR
    ws = []
    sec, o = divmod(off, 2048)
    buf = user(EXE_LBA + sec)
    for i in range(n):
        if o + 4 > 2048:
            sec += 1
            o = 0
            buf = user(EXE_LBA + sec)
        ws.append(struct.unpack_from("<I", buf, o)[0])
        o += 4
    return ws
R = ["r0","r1","r2","r3","r4","r5","r6","r7","r8","r9","r10","r11","r12","r13","r14","r15",
     "r16","r17","r18","r19","r20","r21","r22","r23","r24","r25","r26","r27","r28","r29","r30","r31"]
def dis(w, pc):
    op = w >> 26
    rs = (w >> 21) & 31
    rt = (w >> 16) & 31
    imm = w & 0xFFFF
    s = imm - 0x10000 if imm & 0x8000 else imm
    if w == 0: return "nop"
    if op == 0x0F: return "lui %s, 0x%04X" % (R[rt], imm)
    if op == 0x0D: return "ori %s, %s, 0x%04X" % (R[rt], R[rs], imm)
    if op == 0x0C: return "andi %s, %s, 0x%04X" % (R[rt], R[rs], imm)
    if op == 0x23: return "lw %s, %d(%s)" % (R[rt], s, R[rs])
    if op == 0x2B: return "sw %s, %d(%s)" % (R[rt], s, R[rs])
    if op == 0x28: return "sb %s, %d(%s)" % (R[rt], s, R[rs])
    if op == 0x20: return "lb %s, %d(%s)" % (R[rt], s, R[rs])
    if op == 0x09: return "addiu %s, %s, %d" % (R[rt], R[rs], s)
    if op == 0x08: return "addi %s, %s, %d" % (R[rt], R[rs], s)
    if op == 0x04: return "beq %s, %s, 0x%08X" % (R[rs], R[rt], (pc + 4 + (s << 2)) & 0xFFFFFFFF)
    if op == 0x05: return "bne %s, %s, 0x%08X" % (R[rs], R[rt], (pc + 4 + (s << 2)) & 0xFFFFFFFF)
    if op == 0x03: return "jal 0x%08X" % ((pc & 0xF0000000) | ((w & 0x3FFFFFF) << 2))
    if op == 0x02: return "j 0x%08X" % ((pc & 0xF0000000) | ((w & 0x3FFFFFF) << 2))
    if op == 0x00:
        rd = (w >> 11) & 31
        sh = (w >> 6) & 31
        fn = w & 0x3F
        if fn in (0x20, 0x21): return "addu %s, %s, %s" % (R[rd], R[rs], R[rt])
        if fn == 0x23: return "subu %s, %s, %s" % (R[rd], R[rs], R[rt])
        if fn == 0x25: return "or %s, %s, %s" % (R[rd], R[rs], R[rt])
        if fn == 0x24: return "and %s, %s, %s" % (R[rd], R[rs], R[rt])
        if fn == 0x00: return "sll %s, %s, %d" % (R[rd], R[rt], sh)
        if fn == 0x02: return "srl %s, %s, %d" % (R[rd], R[rt], sh)
        if fn == 0x08: return "jr %s" % R[rs]
        if fn == 0x09: return "jalr %s, %s" % (R[rd], R[rs])
        return "SPECIAL fn=0x%02X" % fn
    return "op=0x%02X ?" % op
print("=== THE REAL MIPS (from the disc) ===")
for cell, n in [(0x800465EC, 40), (0x80046638, 20), (0x80046074, 16)]:
    print("--- fn %08X:" % cell)
    ws = file_words(cell, n)
    for i, w in enumerate(ws):
        pc = cell + i * 4
        print("  %08X: %08X  %s" % (pc, w, dis(w, pc)))
print("=== THE BAND TABLE BOUNDS (discontinuity scan) ===")
base = 0x80056800
ws = file_words(base, 160)
start = None
for i in range(1, len(ws)):
    d = ws[i] - ws[i - 1]
    if 0x0001F000 < d < 0x00040000:
        if start is None:
            start = i
    else:
        if start is not None and i - start > 4:
            print("  series: 0x%08X..0x%08X (%d words)" % (
                base + start * 4, base + (i - 1) * 4, i - start))
        start = None
print("  (scan range 0x80056800..0x80056A80)")
print("  words at 0x80056880 (16): %s" % " ".join("%08X" % w for w in file_words(0x80056880, 16)))
print("  words at 0x80056A00 (16): %s" % " ".join("%08X" % w for w in file_words(0x80056A00, 16)))
PYEOF

echo "===EMIT295=== the emitted C for the same fns (side-by-side)"
for FN in 800465EC 80046638 80046074; do
  L=$(grep -n "^static void xenolift_fn_${FN}" "$DCA" | grep -v ";" | head -1 | cut -d: -f1)
  if [ -z "$L" ]; then echo "--- fn $FN: def not found"; continue; fi
  E=$(awk -v s="$L" 'NR>s && /^static void/{print NR; exit}' "$DCA")
  [ -z "$E" ] && E=$((L+60))
  echo "--- fn $FN (lines $L..$E):"
  awk -v s="$L" -v e="$((E-1))" 'NR>=s && NR<=e' "$DCA" | head -60
done

echo "===C295DONE=== MIPS-truth probe complete - the emit-defect verdict comes from these receipts"
