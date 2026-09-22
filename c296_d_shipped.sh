#!/bin/bash
# c296_emitcensus_probe.sh - READ-ONLY: the emit-fidelity census -
# is the defect localized or global, and where did the broken
# bodies come from?
# THE c295 VERDICT: EMIT DEFECT CONFIRMED at fn 800465EC/80046074/
# 80046638 - the emitted bodies are NOT translations of the disc
# bytes at their own addresses; the emitted garbage stores are the
# manufactured origin of the c290b computed-garbage fault family.
# SUB-CANDIDATES: (a1) stale symbol/address map; (a2) the emitter
# decoded from a different or self-poisoned input capture.
# THIS PROBE: (1) real MIPS vs emitted C at three KNOWN-WORKING
# fns (boot entry 80019524, the LegacyCdDataWait spin 800286CC,
# KernelMenuMain 8001A4B4) - match = localized defect, mismatch =
# global; (2) disc-wide byte search for the broken body's implied
# instruction words (8C4269A4, 34630002, 3C030400, 3C028005+3463)
# - found-at-X = measure the constant misalignment K; NOT FOUND =
# the emitter input was not this disc; (3) the Rust tool source's
# symbol/input handling (TRAILBLAZER zone). No patch, no compile,
# no run.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C296-FAILED: xenolift dir missing"; exit 1; }
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
if [ ! -s "$BIN" ]; then echo "C296-DISC-NOT-FOUND (set XG_DISC_BIN)"; exit 0; fi
python3 - "$BIN" <<'PYEOF'
import sys, struct
path = sys.argv[1]
f = open(path, "rb")
EXE_LBA = 108606
T_ADDR = 0x80010000
T_SIZE = 0x49800
def user(lba):
    f.seek(lba * 2352)
    return f.read(2352)[24:24 + 2048]
def file_bytes(off, n):
    out = b""
    while n > 0:
        sec, o = divmod(off, 2048)
        buf = user(EXE_LBA + sec)
        take = min(n, 2048 - o)
        out += buf[o:o + take]
        n -= take
        off += take
    return out
R = ["r%d" % i for i in range(32)]
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
    if op == 0x0A: return "slti %s, %s, %d" % (R[rt], R[rs], s)
    if op == 0x23: return "lw %s, %d(%s)" % (R[rt], s, R[rs])
    if op == 0x2B: return "sw %s, %d(%s)" % (R[rt], s, R[rs])
    if op == 0x28: return "sb %s, %d(%s)" % (R[rt], s, R[rs])
    if op == 0x29: return "sh %s, %d(%s)" % (R[rt], s, R[rs])
    if op == 0x20: return "lb %s, %d(%s)" % (R[rt], s, R[rs])
    if op == 0x21: return "lh %s, %d(%s)" % (R[rt], s, R[rs])
    if op == 0x24: return "lbu %s, %d(%s)" % (R[rt], s, R[rs])
    if op == 0x25: return "lhu %s, %d(%s)" % (R[rt], s, R[rs])
    if op == 0x09: return "addiu %s, %s, %d" % (R[rt], R[rs], s)
    if op == 0x04: return "beq %s, %s, 0x%08X" % (R[rs], R[rt], (pc + 4 + (s << 2)) & 0xFFFFFFFF)
    if op == 0x05: return "bne %s, %s, 0x%08X" % (R[rs], R[rt], (pc + 4 + (s << 2)) & 0xFFFFFFFF)
    if op == 0x01:
        if rt == 0: return "bltz %s, 0x%08X" % (R[rs], (pc + 4 + (s << 2)) & 0xFFFFFFFF)
        if rt == 1: return "bgez %s, 0x%08X" % (R[rs], (pc + 4 + (s << 2)) & 0xFFFFFFFF)
        return "REGIMM rt=%d" % rt
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
        if fn == 0x2A: return "slt %s, %s, %s" % (R[rd], R[rs], R[rt])
        if fn == 0x00: return "sll %s, %s, %d" % (R[rd], R[rt], sh)
        if fn == 0x02: return "srl %s, %s, %d" % (R[rd], R[rt], sh)
        if fn == 0x08: return "jr %s" % R[rs]
        if fn == 0x09: return "jalr %s, %s" % (R[rd], R[rs])
        return "SPECIAL fn=0x%02X" % fn
    return "op=0x%02X ?" % op
print("=== REAL MIPS AT THE WORKING FNS (the fidelity census) ===")
for cell, n in [(0x80019524, 22), (0x800286CC, 22), (0x8001A4B4, 22)]:
    print("--- %08X:" % cell)
    d = file_bytes(cell - T_ADDR, n * 4)
    for i in range(n):
        w = struct.unpack_from("<I", d, i * 4)[0]
        pc = cell + i * 4
        print("  %08X: %08X  %s" % (pc, w, dis(w, pc)))
print("=== DISC-WIDE SEARCH FOR THE BROKEN BODY'S IMPLIED WORDS ===")
img = file_bytes(0, T_SIZE)
pats = [
    ("lw r2,0x69A4(r2)", b"\x8C\x42\x69\xA4"),
    ("ori r3,r3,2", b"\x34\x63\x00\x02"),
    ("ori r3,r3,0x0401", b"\x34\x63\x04\x01"),
    ("lui r3,0x0400", b"\x3C\x03\x04\x00"),
    ("lui r3,0x0100", b"\x3C\x03\x01\x00"),
]
for name, p in pats:
    hits = []
    i = 0
    while len(hits) < 10:
        i = img.find(p, i)
        if i == -1: break
        if i % 4 == 0:
            hits.append(T_ADDR + i)
        i += 1
    print("  %-20s hits=%d: %s" % (name, len(hits), " ".join("%08X" % h for h in hits)))
PYEOF

echo "===EMIT296=== the emitted C at the working fns (side-by-side)"
for FN in 80019524 800286CC 8001A4B4; do
  L=$(grep -n "^static void xenolift_fn_${FN}" "$DCA" | grep -v ";" | head -1 | cut -d: -f1)
  if [ -z "$L" ]; then echo "--- fn $FN: def not found"; continue; fi
  E=$(awk -v s="$L" 'NR>s && /^static void/{print NR; exit}' "$DCA")
  [ -z "$E" ] && E=$((L+40))
  echo "--- fn $FN (lines $L..$E):"
  awk -v s="$L" -v e="$((E-1))" 'NR>=s && NR<=e' "$DCA" | head -26
done

echo "===TOOL296=== the Rust tool's symbol/input handling (TRAILBLAZER zone)"
ls src/ 2>/dev/null | head -8
grep -rn "Ghidra\|symbol_DB\|prior_RE" src/ 2>/dev/null | head -8 | cut -c1-150
grep -rn "overlay_region\|overlay_input\|PS-X EXE\|t_addr" src/ 2>/dev/null | head -12 | cut -c1-150
echo "--- tool input files (what the emitter reads):"
grep -rn "\.bin\|fopen\|read" src/main.rs 2>/dev/null | head -12 | cut -c1-150

echo "===C296DONE=== emit-fidelity census complete - the K-measure / poisoned-input verdict comes from these receipts"
