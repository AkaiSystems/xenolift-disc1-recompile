#!/bin/bash
# c490_extract.sh - READ-ONLY CENSUS, NO RUN, NO BUILD,
# NO PATCH. The c489 receipts: the disc map is in -
# SLUS_005.53 (the boot target) loads at 0x80020000,
# size 0x12E800 => the game text CONTAINS 0x8009A280.
# The correct PS-EXE fields: +0x18 = LOAD BASE, +0x1C =
# LOAD SIZE (c489 read +0x10 = the initial PC and
# wrongly reported OUTSIDE). THE QUESTIONS: (1) what
# are the ORIGINAL SLUS bytes at 0x8009A280 (the nop
# region - real code the emitter skipped, or zeros?);
# (2) is overlay_input.bin (the emitter's ONLY input,
# main.rs:429) TRUNCATED relative to the SLUS text?
# Fail-closed, tee'd to /tmp/c490_receipts.txt.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C490-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c490_receipts.txt) 2>&1
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
import struct, sys, os, hashlib
img = open(sys.argv[1], "rb")
SEC, UD, BLK = 2352, 24, 2048
def rd_sector(n):
    img.seek(n * SEC + UD)
    return img.read(BLK)
def read_extent(lba, size):
    out = b""
    for i in range((size + BLK - 1) // BLK):
        out += rd_sector(lba + i)
    return out[:size]
print("===WALKVERIFY490===")
pvd = rd_sector(16)
print("PVD magic:", pvd[1:6])
if pvd[1:6] != b"CD001":
    print("GATE-FAILED: no ISO9660 PVD")
    sys.exit(0)
rr = pvd[156:190]
root_lba = struct.unpack("<I", rr[2:6])[0]
print("root_lba=%d (expect 22 per the c489 receipts)" % root_lba)
SLUS_LBA, SLUS_SIZE = 66309, 1241088
head = read_extent(SLUS_LBA, 0x800)
print("magic:", head[0:8])
pc = struct.unpack("<I", head[0x10:0x14])[0]
load_base = struct.unpack("<I", head[0x18:0x1C])[0]
load_size = struct.unpack("<I", head[0x1C:0x20])[0]
sp = struct.unpack("<I", head[0x30:0x34])[0]
print("===SLUSHDR490=== pc=0x%08X load_base=0x%08X load_size=0x%X sp=0x%08X" % (pc, load_base, load_size, sp))
exe = read_extent(SLUS_LBA, SLUS_SIZE)
def dump_at(vaddr, nbytes, tag):
    foff = 0x800 + (vaddr - load_base)
    if foff < 0 or foff + nbytes > len(exe):
        print("--- %s vaddr 0x%08X OUTSIDE the file" % (tag, vaddr))
        return
    chunk = exe[foff:foff + nbytes]
    print("--- %s vaddr 0x%08X (file_off=0x%X):" % (tag, vaddr, foff))
    for i in range(0, len(chunk), 16):
        ws = " ".join("%08X" % w for w in struct.unpack("<4I", chunk[i:i+16]))
        print("  0x%08X: %s" % (vaddr + i, ws))
print("===SLUSBYTES490=== the ORIGINAL SLUS bytes at the fault region")
dump_at(0x8009A280, 512, "THE QUESTION")
dump_at(0x8009A2F8, 128, "JUMP TARGET")
dump_at(0x800739A0, 128, "CONTROL (the running init)")
dump_at(0x80036044, 64, "CONTROL (the initial PC)")
dump_at(0x8009A200, 128, "STOP TRANSITION (emission ends ~here)")
print("===TRUNC490=== overlay_input.bin vs the SLUS text prefix")
if os.path.exists("overlay_input.bin"):
    olen = os.path.getsize("overlay_input.bin")
    data = open("overlay_input.bin", "rb").read()
    print("overlay_input.bin size=%d sha256=%s" % (olen, hashlib.sha256(data).hexdigest()))
    ref = exe[0x800:0x800 + olen]
    if len(data) == len(ref) and data == ref:
        print("IDENTICAL to the first %d bytes of the SLUS text" % olen)
    else:
        fd = -1
        for i in range(min(len(data), len(ref))):
            if data[i] != ref[i]:
                fd = i
                break
        print("DIFFERS: len_overlay=%d len_slus_text=%d first_diff_at=%d (0x%X)" % (len(data), len(ref), fd, max(fd, 0)))
        if fd >= 0:
            print("  overlay bytes at first_diff:", " ".join("%02X" % b for b in data[fd:fd+16]))
            print("  slus   bytes at first_diff:", " ".join("%02X" % b for b in ref[fd:fd+16]))
        stop_foff = 0x800 + (0x8009A248 - load_base)
        print("the nop-region start maps to SLUS file offset 0x%X; overlay_input covers %s" % (stop_foff, "YES" if olen >= stop_foff else "NO - TRUNCATED BEFORE THE NOP REGION"))
else:
    print("(overlay_input.bin NOT FOUND in the tree root - searching:)")
    os.system("find . -maxdepth 3 -iname \"overlay_input*\" 2>/dev/null | head -6")
PYEOF
echo "===EMITSTOP490=== the last emitted markers in disc1.c"
grep -n -e "---------- 0x" disc1.c | tail -4
echo "--- the R1260 emitter-input region in main.rs (lines 420-465):"
sed -n "420,465p" src/main.rs 2>/dev/null
echo "===C490DONE=== the SLUS bytes + overlay_input.bin size decide emission-gap vs truncation - digest is pure ASCII"
