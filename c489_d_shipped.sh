#!/bin/bash
# c489_extract.sh - READ-ONLY CENSUS, NO RUN, NO BUILD,
# NO PATCH. The c488 receipts: the 'PS-X EXE' magic
# scan found only data occurrences (headers do not
# parse). THE RIGHT WAY: walk the disc's own ISO9660
# filesystem. RECEIPTS: (1) WALK489: the PVD + the ROOT
# DIRECTORY LISTING (names+lba+size - the disc map);
# (2) BOOT489: SYSTEM.CNF's boot target + the real EXE
# header; (3) ORIG489: the ORIGINAL BYTES at 0x8009A280
# + the CONTROLS at 0x800739A0 (known-real init) and
# 0x8009A2F8 (the jump target); (4) HITS489: the 64-byte
# headers of the four magic hits; (5) EMITIN489: the
# emit stage's input in main.rs. Fail-closed, tee'd to
# /tmp/c489_receipts.txt. Pure-ASCII output.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C489-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c489_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="d86f3deb57aed5b0921ab3a82867dea3a1e1d9960028e360bed8d9bdc90d45f8"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the R1387 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the R1387 tree)"
IMG="duckstation/xenogears.bin"
if [ ! -f "$IMG" ]; then IMG=$(find . -maxdepth 3 -iname "xenogears.bin" 2>/dev/null | head -1); fi
if [ -z "$IMG" ] || [ ! -f "$IMG" ]; then echo "GATE-FAILED: the disc image not found"; exit 0; fi
echo "IMG=$IMG"
python3 - "$IMG" <<'PYEOF'
import struct, sys
img = open(sys.argv[1], "rb")
SEC, UD, BLK = 2352, 24, 2048
def rd_sector(n):
    img.seek(n * SEC + UD)
    return img.read(BLK)
def read_extent(lba, size):
    out = b""
    nsec = (size + BLK - 1) // BLK
    for i in range(nsec):
        out += rd_sector(lba + i)
    return out[:size]
print("===WALK489=== the PVD + the root directory listing")
pvd = rd_sector(16)
print("PVD magic:", pvd[1:6])
if pvd[1:6] != b"CD001":
    print("GATE-FAILED: no ISO9660 PVD at sector 16")
    sys.exit(0)
rr = pvd[156:190]
root_lba = struct.unpack("<I", rr[2:6])[0]
root_size = struct.unpack("<I", rr[10:14])[0]
print("root dir: lba=%d size=%d" % (root_lba, root_size))
def parse_dir(data):
    entries = []
    off = 0
    while off < len(data):
        ln = data[off]
        if ln == 0:
            off = (off // BLK + 1) * BLK
            continue
        rec = data[off:off + ln]
        if len(rec) < 34:
            break
        lba = struct.unpack("<I", rec[2:6])[0]
        size = struct.unpack("<I", rec[10:14])[0]
        nlen = rec[32]
        name = rec[33:33 + nlen].decode("latin1")
        flags = rec[25]
        entries.append((name, lba, size, flags))
        off += ln
    return entries
root = parse_dir(read_extent(root_lba, root_size))
print("--- the root entries (name | lba | size | dir?):")
for n, l, s, f in root:
    print("  %-24s %8d %10d dir=%d" % (n, l, s, 1 if f & 2 else 0))
print("===BOOT489=== SYSTEM.CNF boot target + the real EXE header")
scnf = [e for e in root if e[0].upper().startswith("SYSTEM.CNF")]
boot_name = None
if scnf:
    data = read_extent(scnf[0][1], scnf[0][2]).decode("latin1")
    print("SYSTEM.CNF content:")
    for line in data.splitlines():
        print("  " + line)
        if line.upper().lstrip().startswith("BOOT"):
            boot_name = line.split("=")[-1].strip().strip()
else:
    print("(no SYSTEM.CNF in the root)")
print("boot_name = %r" % (boot_name,))
if boot_name:
    base = boot_name.replace("cdrom:", "").replace("\\", "/").strip("/")
    base = base.split(";")[0]
    parts = base.split("/")
    dir_lba, dir_size = root_lba, root_size
    exe_ent = None
    for i, p in enumerate(parts):
        ents = parse_dir(read_extent(dir_lba, dir_size))
        match = [e for e in ents if e[0].upper().split(";")[0] == p.upper()]
        if not match:
            print("NOT FOUND: %r in the directory walk" % (p,))
            exe_ent = None
            break
        exe_ent = match[0]
        if i < len(parts) - 1:
            dir_lba, dir_size = match[0][1], match[0][2]
    if exe_ent:
        name, lba, size, flags = exe_ent
        print("EXE record: %s lba=%d size=%d" % (name, lba, size))
        head = read_extent(lba, 0x800)
        print("EXE head magic:", head[0:8])
        t_addr = struct.unpack("<I", head[16:20])[0]
        t_size = struct.unpack("<I", head[20:24])[0]
        print("t_addr=0x%08X t_size=0x%X (%d bytes)" % (t_addr, t_size, t_size))
        print("===ORIG489=== the ORIGINAL BYTES at the target vaddrs")
        def dump_at(vaddr, nbytes):
            if not (t_addr <= vaddr < t_addr + t_size):
                print("vaddr 0x%08X OUTSIDE the EXE text range" % (vaddr,))
                return
            foff = 0x800 + (vaddr - t_addr)
            sec = lba + foff // BLK
            data = read_extent(sec, (foff % BLK) + nbytes)
            chunk = data[foff % BLK:foff % BLK + nbytes]
            print("--- vaddr 0x%08X (file_off=0x%X, sector=%d):" % (vaddr, foff, sec))
            for i in range(0, len(chunk), 16):
                ws = " ".join("%08X" % w for w in struct.unpack("<4I", chunk[i:i+16]))
                print("  0x%08X: %s" % (vaddr + i, ws))
        print("THE QUESTION: 0x8009A280 (the movie module second-stage region):")
        dump_at(0x8009A280, 256)
        print("CONTROL 1: 0x800739A0 (the module's running init code, KNOWN REAL):")
        dump_at(0x800739A0, 128)
        print("CONTROL 2: 0x8009A2F8 (the unresolved jump target):")
        dump_at(0x8009A2F8, 128)
print("===HITS489=== the 64-byte headers of the four magic hits")
for off in (155958792, 157384104, 158308440, 158590680):
    sec = off // SEC
    data = rd_sector(sec)
    print("--- hit@%d (sector %d): %s" % (off, sec, " ".join("%08X" % w for w in struct.unpack("<16I", data[0:64]))))
PYEOF
echo "===EMITIN489=== the emit stage's input in main.rs"
grep -n -e "disc1" -e "_stage_main" -e "emit" src/main.rs 2>/dev/null | head -12
echo "===C489DONE=== the ISO walk + the EXE bytes decide emission-gap vs runtime-load - digest is pure ASCII"
