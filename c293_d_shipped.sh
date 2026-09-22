#!/bin/bash
# c293_exehdr_probe.sh - READ-ONLY: the real disc's EXE header is
# the ground truth for the loader-field-swap hypothesis.
# THE c292 RECEIPTS: the runtime's EXE loader (~line 24037) reads
# t_addr from buf+0x18 and t_size from buf+0x1C - the standard
# PS-X EXE header has t_addr@0x10 and t_size@0x14; 0x18/0x1C are
# the BSS fields (s_addr/s_size). A pre-existing comment at line
# 10198 already flags a discrepancy: (t_addr 0x80019524, size
# 0x49800) but the ORIGINAL FILE HAS ... - truncated in the
# digest.
# HYPOTHESIS (labeled): the loader sprays the text bytes to s_addr
# with s_size = a shifted, truncated image load - predicting zeros
# beyond the loaded window (the SPU mode table + voice base) and
# string fragments in-range ('XYZ[' consumed as GPU pointers).
# THIS PROBE: (a) the full line-10198 comment; (b) the loader body
# (buf provenance); (c) parse the REAL disc .bin: PVD, ISO root
# files, the PS-X EXE, its SIX header fields; (d) map every
# suspect cell against the REAL text/BSS ranges with byte dumps;
# (e) the file size vs the load length (the junk-spray shape).
# No patch, no compile, no run.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C293-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="ed69fd5f6753b2e0e840ac0471b950b85c2a23c273fcaca356f4ec706831d1dc"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1337 tree ed69fd5f - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1337 tree)"

echo "===COMMENT293=== the full line-10198 comment (the flagged discrepancy)"
L=$(grep -n "t_addr 0x80019524" "$SRC" | head -1 | cut -d: -f1)
echo "comment at line $L"
if [ -n "$L" ]; then sed -n "$((L-24)),$((L+30))p" "$SRC" | cut -c1-170; fi

echo "===LOADER293=== the loader body (buf provenance + the load call)"
sed -n '24000,24090p' "$SRC" | cut -c1-170

echo "===HDR293=== the REAL disc: ISO walk + the EXE header (six fields) + cell maps"
BIN="${XG_DISC_BIN:-$HOME/Desktop/PS7Z/PS1Games/Xenogears (USA) (Disc 1)/Xenogears (USA) (Disc 1)/Xenogears (USA) (Disc 1).bin}"
echo "DISC=$BIN"
if [ ! -s "$BIN" ]; then echo "C293-DISC-NOT-FOUND at the receipted path (set XG_DISC_BIN)"; exit 0; fi
echo "DISC_SIZE=$(wc -c < "$BIN" | tr -d ' ')"
python3 - "$BIN" <<'PYEOF'
import sys, struct
path = sys.argv[1]
SEC = 2352
f = open(path, "rb")
def sect(lba):
    f.seek(lba * SEC)
    return f.read(SEC)
def user(lba, off=24):
    return sect(lba)[off:off+2048]
u = user(16)
if u[1:6] != b"CD001":
    u = user(16, 16)
    if u[1:6] != b"CD001":
        print("PVD-NOT-FOUND at either user offset - cannot walk the ISO")
        raise SystemExit(0)
print("PVD OK (user offset 24 assumed)")
root_lba = struct.unpack_from("<I", u, 156 + 2)[0]
root_size = struct.unpack_from("<I", u, 156 + 10)[0]
print("ISO root: LBA=%d size=%d" % (root_lba, root_size))
def dir_entries(lba, size):
    buf = b""
    n = (size + 2047) // 2048
    for i in range(n):
        buf += user(lba + i)
    ents = []
    p = 0
    while p < len(buf):
        ln = buf[p]
        if ln == 0:
            break
        lba2 = struct.unpack_from("<I", buf, p + 2)[0]
        size2 = struct.unpack_from("<I", buf, p + 10)[0]
        flags = buf[p + 25]
        nlen = buf[p + 32]
        name = buf[p + 33:p + 33 + nlen].decode("ascii", "replace").split(";")[0]
        ents.append((name, lba2, size2, flags))
        p += ln
        if p % 2 == 1:
            p += 1
    return ents
ents = dir_entries(root_lba, root_size)
print("root entries: %d" % len(ents))
for nm, lb, sz, fl in ents[:24]:
    print("  %-20s LBA=%-8d size=%-9d dir=%s" % (nm, lb, sz, "Y" if fl & 2 else "N"))
# find the PS-X EXE: check each FILE's first sector for the magic
exes = []
for nm, lb, sz, fl in ents:
    if (fl & 2) or sz < 0x800:
        continue
    head = user(lb)
    if head[:8] == b"PS-X EXE":
        exes.append((nm, lb, sz))
print("PS-X EXE files found: %d" % len(exes))
for nm, lb, sz in exes:
    print("EXE: %s LBA=%d size=%d" % (nm, lb, sz))
if not exes:
    print("NO PS-X EXE in ISO root - probe deeper (subdirs) next cycle")
    raise SystemExit(0)
nm, lb, sz = exes[0]
hdr = user(lb)
pc, gp, t_addr, t_size, s_addr, s_size = struct.unpack_from("<IIIIII", hdr, 0x08)
print("=== THE REAL HEADER ===")
print("pc=%08X gp=%08X t_addr=%08X t_size=%08X (%u) s_addr=%08X s_size=%08X (%u)" % (
    pc, gp, t_addr, t_size, t_size, s_addr, s_size, s_size))
print("file size=%u vs (0x800 + t_size)=%u - extra file bytes beyond text: %u" % (
    sz, 0x800 + t_size, max(0, sz - 0x800 - t_size)))
print("=== WHAT OUR LOADER READS (buf+0x18/0x1C) ===")
print("our t_addr(s_addr field)=%08X our t_size(s_size field)=%08X" % (s_addr, s_size))
print("=== SUSPECT CELL MAP (real ranges) ===")
cells = [0x80010000, 0x80010004, 0x80019524, 0x800569A0, 0x800569A4, 0x800569A8,
         0x800569AC, 0x800569B0, 0x80059330, 0x80059394, 0x8005A238,
         0x80068E08, 0x80068E70, 0x80068E74]
for c in cells:
    if t_addr <= c < t_addr + t_size:
        off = c - t_addr
        sec_i, sec_o = off // 2048, off % 2048
        d = user(lb + sec_i)[sec_o:sec_o + 16]
        print("  %08X: TEXT (off %d) words: %08X %08X %08X %08X" % (
            c, off,
            struct.unpack_from("<I", d, 0)[0],
            struct.unpack_from("<I", d, 4)[0],
            struct.unpack_from("<I", d, 8)[0],
            struct.unpack_from("<I", d, 12)[0]))
    elif s_addr <= c < s_addr + s_size:
        print("  %08X: BSS (real HW: zero at boot)" % c)
    else:
        print("  %08X: OUTSIDE image (uninit RAM at boot)" % c)
print("=== OUR LOAD WINDOW vs REAL ===")
print("ours: 0x%08X + 0x%X (0x%08X..0x%08X)" % (s_addr, s_size, s_addr, s_addr + s_size))
print("real: text 0x%08X..0x%08X, bss 0x%08X..0x%08X" % (
    t_addr, t_addr + t_size, s_addr, s_addr + s_size))
PYEOF

echo "===C293DONE=== EXE-header probe complete - the loader verdict comes from these receipts"
