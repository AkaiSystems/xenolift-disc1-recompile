#!/bin/bash
# c297_innerexe_probe.sh - READ-ONLY: find the INNER GAME EXE on
# the retail disc and verify the unified theory.
# THE c296 UNIFYING THEORY: the retail SLUS_006.64 = the OUTER
# BOOT LOADER (its image holds Cdl* symbol strings, 301KB); the
# emitted guest code = the INNER GAME EXE (crt0 clears BSS to
# 0x8007FAEC, ~456KB image) - the tool emitted it faithfully,
# but load_exe loads the LOADER's image as guest DATA. Driver
# cells hold loader ASCII; cells beyond 0x80059800 hold zeros -
# ONE mismatch explains the whole computed-garbage fault family.
# THIS PROBE: (a) full-disc scan for the PS-X EXE magic outside
# LBA 108606 (all ~305K sectors, user data at +24); (b) full-disc
# scan for the crt0 signature (lui r8,0x8006 + addiu 0x92B8 =
# 3C088006 250892B8) and fn 800465EC's words (8C4269A4, 34630002,
# 3C030400); (c) parse any inner EXE header (pc@[0x10],
# t_addr@[0x18], t_size@[0x1C]); (d) dump its real bytes at the
# GPU band 0x800569A0-69B0, the SPU cells 0x80068E08/0x80068E70,
# and the crt0 0x80019524; (e) receipt what path the runtime's
# load_exe actually loads. No patch, no compile, no run.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C297-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="ed69fd5f6753b2e0e840ac0471b950b85c2a23c273fcaca356f4ec706831d1dc"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1337 tree ed69fd5f - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1337 tree)"

echo "===LOADPATH297=== what does load_exe actually load?"
grep -n "load_exe" "$SRC" | head -6
L=$(grep -n "load_exe(" "$SRC" | grep -v "^.*static void load_exe" | head -1 | cut -d: -f1)
if [ -n "$L" ]; then sed -n "$((L-6)),$((L+4))p" "$SRC"; fi

BIN="${XG_DISC_BIN:-$HOME/Desktop/PS7Z/PS1Games/Xenogears (USA) (Disc 1)/Xenogears (USA) (Disc 1)/Xenogears (USA) (Disc 1).bin}"
echo "DISC=$BIN"
if [ ! -s "$BIN" ]; then echo "C297-DISC-NOT-FOUND (set XG_DISC_BIN)"; exit 0; fi
echo "DISC_SIZE=$(wc -c < "$BIN" | tr -d ' ')"
python3 - "$BIN" <<'PYEOF'
import sys, struct, os
path = sys.argv[1]
SEC = 2352
size = os.path.getsize(path)
nsec = size // SEC
f = open(path, "rb")
print("===MAGICSCAN297=== PS-X EXE magic at sector user-data (all %d sectors) ===" % nsec)
exes = []
CH = 1 << 22
pos = 0
prev = b""
sec_idx = 0
magic_hits = []
sig_3C088006 = []
sig_8C4269A4 = []
sig_34630002 = []
sig_3C030400 = []
pats = [(b"\x3C\x08\x80\x06\x25\x08\x92\xB8", sig_3C088006),
        (b"\x8C\x42\x69\xA4", sig_8C4269A4),
        (b"\x34\x63\x00\x02", sig_34630002),
        (b"\x3C\x03\x04\x00", sig_3C030400)]
while pos < size:
    f.seek(pos)
    chunk = f.read(CH)
    if not chunk: break
    base_sec = pos // SEC
    for si in range(0, len(chunk) // SEC):
        s = chunk[si * SEC:(si + 1) * SEC]
        lba = base_sec + si
        if s[24:32] == b"PS-X EXE":
            magic_hits.append(lba)
    hay = chunk
    for p, out in pats:
        i = 0
        while len(out) < 12:
            i = hay.find(p, i)
            if i == -1: break
            out.append(pos + i)
            i += 1
    pos += CH
    if pos >= size: break
print("PS-X EXE magic sector hits: %d" % len(magic_hits))
for lba in magic_hits[:16]:
    print("  magic at LBA %d (file off %d)" % (lba, lba * SEC))
print("===PATTERNS=== (file offsets -> LBA, intra-sector offset)")
def show(name, offs):
    print("  %s hits=%d:" % (name, len(offs)))
    for o in offs[:12]:
        lba, io = o // SEC, o % SEC
        print("    file_off=%d LBA=%d intra=%d" % (o, lba, io))
show("crt0 sig lui8006+addiu92B8", sig_3C088006)
show("lw r2,0x69A4(r2)", sig_8C4269A4)
show("ori r3,r3,2", sig_34630002)
show("lui r3,0x0400", sig_3C030400)
print("===INNER EXE PARSE===")
def user(lba):
    f.seek(lba * SEC)
    return f.read(SEC)[24:24 + 2048]
for lba in magic_hits:
    if lba == 108606:
        print("  LBA %d = the known outer loader (skip)" % lba)
        continue
    h = user(lba)
    pc = struct.unpack_from("<I", h, 0x10)[0]
    t_addr = struct.unpack_from("<I", h, 0x18)[0]
    t_size = struct.unpack_from("<I", h, 0x1C)[0]
    print("  LBA %d: pc=%08X t_addr=%08X t_size=%08X (%u bytes)" % (lba, pc, t_addr, t_size, t_size))
    if t_addr == 0x80010000 and 0x40000 < t_size < 0x100000:
        print("  ^ CANDIDATE INNER GAME EXE (image 0x%08X..0x%08X)" % (t_addr, t_addr + t_size))
        def fb(cell, n):
            off = cell - t_addr
            out = b""
            while len(out) < n * 4:
                secn, o = divmod(off, 2048)
                u = user(lba + secn)
                out += u[o:o + (n * 4 - len(out))]
                off += len(out)
                if len(out) == 0: break
            return out
        for cell in [0x80010004, 0x80019524, 0x800569A0, 0x800569A4, 0x800569B0,
                     0x80059330, 0x80059394, 0x80068E08, 0x80068E70]:
            d = fb(cell, 4)
            if len(d) >= 16:
                ws = " ".join("%08X" % struct.unpack_from("<I", d, i)[0] for i in range(0, 16, 4))
                print("    %08X: %s" % (cell, ws))
            else:
                print("    %08X: OUT OF RANGE" % cell)
PYEOF

echo "===C297DONE=== inner-EXE probe complete - the loader-handoff verdict comes from these receipts"
