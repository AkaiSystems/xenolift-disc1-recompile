#!/bin/bash
# c294_discbytes_probe.sh - READ-ONLY: the disc's own bytes at the
# in-image suspect cells (the dumps my c293 classification bug
# skipped) + the true BSS fields.
# THE c293 RECEIPTS: the loader is EXONERATED (real disc SLUS_006.64
# = 0x800 header + 0x49800 image exactly; PC=0x80019524@[0x10],
# t_addr=0x80010000@[0x18], t_size=0x49800@[0x1C] = our loader's
# offsets). In-image cells: GPU pointer band 0x800569A0-69B0, latch
# 0x80059330, ctx 0x80059394. Out-of-image: 0x8005A238, 0x80068E08,
# 0x80068E70 (uninit at boot; the module loads that should fill
# them never ran in c290b).
# HYPOTHESIS (labeled): the in-image band holds real disc values at
# boot; the fault-era garbage ('XYZ[' digit packs) came from a WILD
# WRITE between boot and fault (matches R186 stack-clobber + R717
# digit-formatter receipts).
# THIS PROBE: (a) parse the header with the DISC-CONFIRMED layout
# (PC/GP @0x10/0x14, t_addr/t_size @0x18/0x1C, s_addr/s_size
# @0x20/0x24, SP/FP @0x28/0x2C); (b) dump the disc's own bytes at
# every in-image suspect cell; (c) a 16-word window around the GPU
# band; (d) the ftab cells + the boot-code prologue as sanity
# anchors. VERDICT RULE: sane pointers in the disc = runtime
# corruption (band write-watch next); zeros in the disc = runtime
# init expected (boot-chain transition hunt). No patch, no
# compile, no run.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C294-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="ed69fd5f6753b2e0e840ac0471b950b85c2a23c273fcaca356f4ec706831d1dc"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1337 tree ed69fd5f - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1337 tree)"

BIN="${XG_DISC_BIN:-$HOME/Desktop/PS7Z/PS1Games/Xenogears (USA) (Disc 1)/Xenogears (USA) (Disc 1)/Xenogears (USA) (Disc 1).bin}"
echo "DISC=$BIN"
if [ ! -s "$BIN" ]; then echo "C294-DISC-NOT-FOUND at the receipted path (set XG_DISC_BIN)"; exit 0; fi
echo "DISC_SIZE=$(wc -c < "$BIN" | tr -d ' ')"
python3 - "$BIN" <<'PYEOF'
import sys, struct
path = sys.argv[1]
SEC = 2352
f = open(path, "rb")
def user(lba):
    f.seek(lba * SEC)
    return f.read(SEC)[24:24 + 2048]
hdr = user(108606)  # SLUS_006.64 LBA receipted by c293
if hdr[:8] != b"PS-X EXE":
    print("MAGIC-FAIL: first sector at LBA 108606 is not the EXE - abort")
    raise SystemExit(0)
print("=== THE HEADER (disc-confirmed layout) ===")
pc, gp, t_addr, t_size = struct.unpack_from("<IIII", hdr, 0x10)
s_addr, s_size, sp0, fp0 = struct.unpack_from("<IIII", hdr, 0x20)
print("pc=%08X gp=%08X t_addr=%08X t_size=%08X (%u)" % (pc, gp, t_addr, t_size, t_size))
print("s_addr=%08X s_size=%08X (%u)  sp0=%08X fp0=%08X" % (s_addr, s_size, s_size, sp0, fp0))
region = hdr[0x4C:0x4C + 40]
print("region string: %s" % region.decode("ascii", "replace").strip())
print("image range: 0x%08X..0x%08X  BSS range: 0x%08X..0x%08X" % (
    t_addr, t_addr + t_size, s_addr, s_addr + s_size))
EXE_LBA = 108606
def file_bytes(off, n):
    out = b""
    while n > 0:
        u = user(EXE_LBA + off // 2048)
        chunk = u[off % 2048:off % 2048 + n]
        if not chunk:
            u2 = user(EXE_LBA + off // 2048 + 1)
            chunk = u2[:n]
        out += chunk
        got = len(chunk)
        n -= got
        off += got
        if got == 0:
            break
    return out
def words_at(cell, n):
    off = cell - t_addr
    d = file_bytes(off, n * 4)
    ws = []
    for i in range(0, len(d) - 3, 4):
        ws.append("%08X" % struct.unpack_from("<I", d, i)[0])
    return " ".join(ws)
def classify(cell):
    if t_addr <= cell < t_addr + t_size:
        return "IN-IMAGE"
    if s_addr <= cell < s_addr + s_size:
        return "BSS"
    return "OUTSIDE"
print("=== SUSPECT CELLS (the disc's OWN bytes) ===")
cells = [0x80010000, 0x80010004, 0x80019524, 0x800569A0, 0x800569A4, 0x800569A8,
         0x800569AC, 0x800569B0, 0x80059330, 0x80059394, 0x8005A238,
         0x80068E08, 0x80068E70, 0x80068E74]
for c in cells:
    cl = classify(c)
    if cl == "IN-IMAGE":
        print("  %08X %s words: %s" % (c, cl, words_at(c, 4)))
    else:
        print("  %08X %s (uninit at boot)" % (c, cl))
print("=== THE GPU BAND WINDOW (16 words from 0x80056990) ===")
base = 0x80056990 & ~3
print("  %08X..: %s" % (base, words_at(base, 16)))
print("=== SANITY ANCHORS ===")
print("  ftab head (0x80010004, 8 words): %s" % words_at(0x80010004, 8))
print("  boot prologue (0x80019524, 4 words): %s" % words_at(0x80019524, 4))
print("=== VERDICT INPUT ===")
band = [words_at(c, 1) for c in [0x800569A0, 0x800569A4, 0x800569A8, 0x800569AC, 0x800569B0]]
nz = [w for w in band if w != "00000000"]
print("GPU band nonzero values in disc: %d/5 -> %s" % (len(nz), " ".join(nz)))
PYEOF

echo "===C294DONE=== disc-bytes probe complete - the wild-write-vs-runtime-init verdict comes from these receipts"
