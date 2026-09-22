#!/bin/bash
# c299_localexe_probe.sh - READ-ONLY: dump the LOCAL SLUS_006.64
# (the emit's true source) + receipt the runtime's actual run line.
# THE c298 RECEIPTS: run.sh:139 = ./target/release/xenolift
# SLUS_006.64 disc1.c - the emit's source is the LOCAL cwd file,
# NOT the disc's file (the disc's = the 301KB outer loader; the
# local = the ~456KB game exe). The fixed magic scan: exactly ONE
# PS-X EXE on the whole disc. My c295/c296 emit comparisons used
# the wrong baseline (the disc file).
# THIS PROBE: (1) the runtime's actual invocation line (xenogears_
# boot + args); (2) the local ./SLUS_006.64: sha, size, header
# (pc/t_addr/t_size/s_addr/s_size); (3) its image bytes at the
# crt0 0x80019524 (expect the emit's exact 3C088006 250892B8 -
# the emit-fidelity proof against its true source), the GPU band
# 0x800569A0-69B0, ctx/latch cells, and the SPU cells
# 0x80068E08/0x80068E70; (4) the coverage question: cells within
# t_size that the c290b pristine showed as ZERO = a load defect;
# cells beyond t_size = runtime-init expected. No patch, no
# compile, no run.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C299-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="ed69fd5f6753b2e0e840ac0471b950b85c2a23c273fcaca356f4ec706831d1dc"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1337 tree ed69fd5f - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1337 tree)"

echo "===RUNLINE299=== the runtime's actual invocation (xenogears_boot + args)"
grep -n "xenogears_boot" run.sh | grep -v "^#" | head -12
L=$(grep -n "\./xenogears_boot " run.sh | head -1 | cut -d: -f1)
if [ -z "$L" ]; then L=$(grep -n "xenogears_boot.*BIN" run.sh | head -1 | cut -d: -f1); fi
if [ -n "$L" ]; then echo "--- run line context (lines $((L-4))..$((L+4))):"; sed -n "$((L-4)),$((L+4))p" run.sh; else echo "RUN-LINE NOT FOUND by ./xenogears_boot pattern - full matches above"; fi

echo "===LOCALEXE299=== the local SLUS_006.64 (the emit's true source)"
if [ ! -s "SLUS_006.64" ]; then echo "LOCAL-SLUS-NOT-FOUND in cwd"; ls -la SLUS* 2>/dev/null; exit 0; fi
echo "LOCAL_SHA=$(shasum -a 256 SLUS_006.64 | cut -d' ' -f1)"
echo "LOCAL_SIZE=$(wc -c < SLUS_006.64 | tr -d ' ')"
python3 - <<'PYEOF'
import struct
d = open("SLUS_006.64", "rb").read()
if len(d) < 0x800 or d[:8] != b"PS-X EXE":
    print("LOCAL FILE IS NOT A PS-X EXE (magic mismatch)")
    raise SystemExit(0)
pc = struct.unpack_from("<I", d, 0x10)[0]
t_addr = struct.unpack_from("<I", d, 0x18)[0]
t_size = struct.unpack_from("<I", d, 0x1C)[0]
s_addr = struct.unpack_from("<I", d, 0x20)[0]
s_size = struct.unpack_from("<I", d, 0x24)[0]
print("pc=%08X t_addr=%08X t_size=%08X (%u) s_addr=%08X s_size=%08X (%u)" % (
    pc, t_addr, t_size, t_size, s_addr, s_size, s_size))
print("file size=%u vs 0x800+t_size=%u" % (len(d), 0x800 + t_size))
print("image range: 0x%08X..0x%08X" % (t_addr, t_addr + t_size))
region = d[0x4C:0x4C + 40]
print("region: %s" % region.decode("ascii", "replace").strip())
def cells(c, n=4):
    off = c - t_addr
    if off < 0 or off + n * 4 > t_size:
        return "OUT OF IMAGE (beyond t_size - runtime-init expected)"
    ws = []
    for i in range(n):
        ws.append("%08X" % struct.unpack_from("<I", d, 0x800 + off + i * 4)[0])
    return " ".join(ws)
print("=== THE CRT0 (emit-fidelity proof) ===")
print("  0x80019524 (8 words): %s" % cells(0x80019524, 8))
print("  emit expects: 3C088006 250892B8 3C098007 2529FAEC 25080004 ...")
print("=== THE GPU BAND (the fault family cells) ===")
for c in [0x800569A0, 0x800569A4, 0x800569A8, 0x800569AC, 0x800569B0]:
    print("  %08X: %s" % (c, cells(c)))
print("  window 0x80056990 (16): %s" % cells(0x80056990, 16))
print("=== THE LATCH/CTX/STRUCT CELLS ===")
for c in [0x80059330, 0x80059394, 0x8005A238, 0x8005F0C, 0x80059F18]:
    print("  %08X: %s" % (c, cells(c)))
print("=== THE SPU CELLS (c290b pristine showed ZERO - the coverage question) ===")
for c in [0x80068E08, 0x80068E70, 0x80068E74, 0x800692D0, 0x800692C8, 0x800692B8]:
    print("  %08X: %s" % (c, cells(c)))
print("=== THE IMAGE BASE (self-header) ===")
print("  0x80010000 (8 words): %s" % cells(0x80010000, 8))
PYEOF

echo "===C299DONE=== local-EXE probe complete - the emit-fidelity + coverage verdict comes from these receipts"
