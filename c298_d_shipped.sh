#!/bin/bash
# c298_loadpath_probe.sh - READ-ONLY: WHAT does run.sh pass as
# argv[1], and does that exe's image match the emitted code?
# THE c297 RECEIPTS: load_exe loads argv[1] (usage: xenogears_boot
# <psx-exe> [disc-image]); the emit's crt0 signature and fn
# 800465EC's words appear NOWHERE in all 718MB (raw-offset-valid
# scan) - the inner game is NOT a raw EXE on the disc; favored:
# the engine is COMPRESSED in the disc data, decompressed by the
# outer loader. The tool's input exe exists as a file somewhere.
# THIS PROBE: (1) run.sh's exact invocation (binary path + args);
# (2) sha + header-parse the argv[1] exe + dump ITS image bytes
# at the crt0 0x80019524, GPU band 0x800569A0+, SPU cells
# 0x80068E08/0x80068E70, ctx 0x80059394 - the direct code-vs-
# data comparison; (3) the FIXED 2352-aligned magic scan (all
# real EXEs on disc); (4) locate the tool's original input exe
# on the Mac. No patch, no compile, no run.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C298-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="ed69fd5f6753b2e0e840ac0471b950b85c2a23c273fcaca356f4ec706831d1dc"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1337 tree ed69fd5f - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1337 tree)"

echo "===RUNSH298=== the exact invocation (what feeds load_exe)"
grep -n "xenogears_boot\|target/release\|\$BIN\|argv" run.sh | head -14
L=$(grep -n "xenogears_boot" run.sh | grep -v "^#" | head -1 | cut -d: -f1)
if [ -n "$L" ]; then echo "--- invocation context (lines $((L-3))..$((L+3))):"; sed -n "$((L-3)),$((L+3))p" run.sh; fi

echo "===EXEFILES298=== every exe/stage file candidate on the Mac tree"
ls -la *.exe 2>/dev/null | head -8
find . -maxdepth 3 \( -name "*.exe" -o -name "*psx*" -o -name "*boot*" \) -type f 2>/dev/null | grep -v "\.git" | head -16

echo "===THE-GUEST-EXE298=== header + image-cell dumps of the receipted argv[1] exe"
EXE=""
for C in $(grep -o "[A-Za-z0-9_./-]*\.exe" run.sh | head -4); do
  [ -f "$C" ] && EXE="$C" && break
  [ -f "$HOME/Downloads/xenolift/$C" ] && EXE="$HOME/Downloads/xenolift/$C" && break
done
if [ -z "$EXE" ]; then
  echo "ARGV1-EXE-NOT-RESOLVED from run.sh text - dumping run.sh head for the receipt:"
  sed -n '1,40p' run.sh
else
  echo "ARGV1_EXE=$EXE"
  echo "EXE_SHA=$(shasum -a 256 "$EXE" | cut -d' ' -f1)"
  echo "EXE_SIZE=$(wc -c < "$EXE" | tr -d ' ')"
  python3 - "$EXE" <<'PYEOF2'
import sys, struct
path = sys.argv[1]
d = open(path, "rb").read()
if len(d) < 0x800 or d[:8] != b"PS-X EXE":
    print("NOT-A-PSX-EXE: %s" % path)
    raise SystemExit(0)
pc = struct.unpack_from("<I", d, 0x10)[0]
t_addr = struct.unpack_from("<I", d, 0x18)[0]
t_size = struct.unpack_from("<I", d, 0x1C)[0]
s_addr = struct.unpack_from("<I", d, 0x20)[0]
s_size = struct.unpack_from("<I", d, 0x24)[0]
print("pc=%08X t_addr=%08X t_size=%08X (%u) s_addr=%08X s_size=%08X" % (
    pc, t_addr, t_size, t_size, s_addr, s_size))
print("file size=%u vs 0x800+t_size=%u" % (len(d), 0x800 + t_size))
print("image range: 0x%08X..0x%08X" % (t_addr, t_addr + t_size))
def cells(c, n=4):
    off = c - t_addr
    if off < 0 or off + n * 4 > t_size:
        return "OUT OF IMAGE"
    ws = []
    for i in range(n):
        ws.append("%08X" % struct.unpack_from("<I", d, 0x800 + off + i * 4)[0])
    return " ".join(ws)
for c in [0x80019524, 0x800569A0, 0x800569A4, 0x800569B0, 0x80059330,
          0x80059394, 0x8005A238, 0x80068E08, 0x80068E70]:
    print("  %08X: %s" % (c, cells(c)))
print("=== CRT0-EXPECT: the emit implies lui r8,0x8006 (3C088006) + addiu r8,0x92B8 (250892B8) at 0x80019524")
w0 = struct.unpack_from("<I", d, 0x800 + (0x80019524 - t_addr))[0] if t_addr <= 0x80019524 < t_addr + t_size else 0
print("crt0 word0=%08X %s" % (w0, "MATCHES-EMIT" if w0 == 0x3C088006 else "does-not-match-emit"))
PYEOF2
fi

echo "===MAGIC298=== FIXED 2352-aligned scan (all real PS-X EXEs on the disc)"
BIN="${XG_DISC_BIN:-$HOME/Desktop/PS7Z/PS1Games/Xenogears (USA) (Disc 1)/Xenogears (USA) (Disc 1)/Xenogears (USA) (Disc 1).bin}"
if [ ! -s "$BIN" ]; then echo "C298-DISC-NOT-FOUND"; exit 0; fi
python3 - "$BIN" <<'PYEOF3'
import sys, struct
path = sys.argv[1]
SEC = 2352
import os
size = os.path.getsize(path)
nsec = size // SEC
CH = SEC * 1800  # 2352-aligned chunk
f = open(path, "rb")
hits = []
pos = 0
while pos < size:
    f.seek(pos)
    chunk = f.read(CH)
    if not chunk: break
    for si in range(len(chunk) // SEC):
        s = chunk[si * SEC:(si + 1) * SEC]
        if s[24:32] == b"PS-X EXE":
            hits.append(pos // SEC + si)
    pos += len(chunk) - (len(chunk) % SEC)
print("PS-X EXE magic hits: %d (scan of %d sectors)" % (len(hits), nsec))
for lba in hits[:16]:
    f.seek(lba * SEC)
    h = f.read(SEC)[24:24 + 2048]
    pc = struct.unpack_from("<I", h, 0x10)[0]
    t_addr = struct.unpack_from("<I", h, 0x18)[0]
    t_size = struct.unpack_from("<I", h, 0x1C)[0]
    print("  LBA %d: pc=%08X t_addr=%08X t_size=%08X (%u)" % (lba, pc, t_addr, t_size, t_size))
PYEOF3

echo "===C298DONE=== load-path probe complete - the code-vs-data match verdict comes from these receipts"
