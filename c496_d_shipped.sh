#!/bin/bash
# c496_extract.sh - READ-ONLY CENSUS, NO RUN, NO BUILD,
# NO PATCH, NO ARTIFACT MODIFICATION. The c495 camera
# CONFIRMED the same-dispatch overlay-identity fault
# LIVE (5 mismatches -> the wild jump -> the fallback)
# and revealed the arm snapshot is a THIRD era
# (Zf16sz-class fragments) - neither the emit source
# (pSYW6z-class) nor the movie module. BEFORE the guard
# design: the era semantics must be receipted
# window-wide. RECEIPTS: (1) ERA496: overlay_input.bin
# vs ALL firstfault windows, byte-compare + cluster,
# with a byteswap-aware matcher (some era dumps hold
# swapped-looking patterns); (2) FRAG496: per-address
# era ID of the R1392 arm-snapshot fragments and the
# movie-phase LIVE fragments (from the c495 receipts)
# against every era dump; (3) EMITPROV496: which input
# produced the emitted translation (disc1.c/map stamps,
# the tool's write path); (4) WINFN496: the emitted
# window-fn inventory (the identity-keyed dispatch
# scope). Fail-closed, tee'd to /tmp/c496_receipts.txt.
# Pure-ASCII output.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C496-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c496_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="2b78e89b5a8af077eb73e21c18882705ebfd01a0d9b311295c1104278ae547ae"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the c495 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the c495 tree with the live-working R1392 camera)"
if [ ! -f "disc1.c" ] || [ ! -f "overlay_input.bin" ]; then echo "GATE-FAILED: artifacts missing"; exit 0; fi
echo "===ERA496=== overlay_input.bin vs every fault-era window (byte-compare + cluster)"
python3 - <<'PYEOF'
import hashlib, glob
ovl = open("overlay_input.bin", "rb").read()
print("overlay_input.bin size=%d sha=%s" % (len(ovl), hashlib.sha256(ovl).hexdigest()[:16]))
def wswap(b):
    out = bytearray(b)
    for i in range(0, len(out) - 3, 4):
        out[i], out[i+1], out[i+2], out[i+3] = out[i+3], out[i+2], out[i+1], out[i]
    return bytes(out)
ovl_sw = wswap(ovl)
groups = {}
for g in sorted(glob.glob("firstfault.*/guest-ram.bin")):
    win = open(g, "rb").read()[0x6F000:0x90000]
    if len(win) != len(ovl):
        print("%-38s window short (%d)" % (g, len(win))); continue
    sha = hashlib.sha256(win).hexdigest()[:16]
    same = (win == ovl)
    samesw = (win == ovl_sw)
    fd = -1
    for i in range(len(ovl)):
        if win[i] != ovl[i]:
            fd = i; break
    groups.setdefault(sha, []).append(g)
    print("%-38s sha=%s same=%s same-byteswapped=%s first_diff=%s" % (g, sha, same, samesw, ("0x%X" % fd) if fd >= 0 else "-"))
print("--- clusters:")
for sha, members in groups.items():
    print("  %s : %d dumps : %s" % (sha, len(members), ", ".join(m.split("/")[0] for m in members)))
PYEOF
echo "===FRAG496=== per-address era ID: the R1392 arm fragments + the LIVE movie fragments vs every era dump"
python3 - <<'PYEOF'
import struct, glob, os
def words(g, off, n):
    with open(g, "rb") as f:
        f.seek(off)
        return list(struct.unpack("<%dI" % n, f.read(4*n)))
def ovlw(off, n):
    data = open("overlay_input.bin", "rb").read()
    return list(struct.unpack("<%dI" % n, data[off:off+4*n]))
ADDRS = [0x800737EC, 0x800738A8, 0x800738B4, 0x800738DC, 0x800739A0]
SNAP = {
    0x800737EC: [0xCE53EBD4, 0xD1400231, 0xFF22EF20, 0x1DF4FEE1],
    0x800738A8: [0x0D141C03, 0x0E242D02, 0x1D040231, 0x1012ED25],
    0x800738B4: [0x1012ED25, 0x3EC141F0, 0xDF161CF4, 0x33200231],
    0x800738DC: [0xDDF2FBDF, 0x130F0231, 0xDE202EEF, 0x0EEEF43E],
    0x800739A0: [0x24000231, 0x30E132FF, 0x1FE133F0, 0x021F1221],
}
LIVE = {
    0x800737EC: [0x27BDFFA8, 0xAFBF0054, 0xAFB40050, 0xAFB3004C],
    0x800738A8: [0x34040001, 0x02802821, 0x00003021, 0x0C00A576],
    0x800738B4: [0x0C00A576, 0x00003821, 0x0C00A298, 0x00002021],
    0x800738DC: [0x34020800, 0xAFA20014, 0x34020003, 0x0C074D4E],
    0x800739A0: [0x340600F0, 0x34070140, 0x0C010E78, 0xAFB00010],
}
eras = sorted(glob.glob("firstfault.*/guest-ram.bin"))
for a in ADDRS:
    print("--- 0x%08X (window offset 0x%X):" % (a, a - 0x8006F000))
    print("  arm-snap: %s | LIVE movie: %s | overlay_input: %s" % (
        " ".join("%08X" % w for w in SNAP[a]),
        " ".join("%08X" % w for w in LIVE[a]),
        " ".join("%08X" % w for w in ovlw(a - 0x8006F000, 4))))
    for g in eras:
        ww = words(g, a - 0x80000000, 4)
        tag = []
        if ww == SNAP[a]: tag.append("== ARM-SNAP")
        if ww == LIVE[a]: tag.append("== LIVE-MOVIE")
        if tag:
            print("  %-38s %s  %s" % (g.split("/")[0], " ".join("%08X" % w for w in ww), " ".join(tag)))
PYEOF
echo "===EMITPROV496=== which input produced the emitted translation"
echo "--- disc1.c head (emit stamps?):"
head -12 disc1.c
echo "--- disc1.map:"
ls -la disc1.map 2>/dev/null
head -6 disc1.map 2>/dev/null
echo "--- the tool's write path + input stamping:"
grep -rn -e "fs::write" src/*.rs 2>/dev/null | head -10
grep -rn -e "overlay_input" src/*.rs 2>/dev/null | head -6
echo "===WINFN496=== the emitted window-fn inventory (identity-keyed dispatch scope)"
grep -n -e "0x8006F" -e "0x80070" -e "0x80071" -e "0x80072" -e "0x80073" -e "0x80074" -e "0x80075" -e "0x80076" -e "0x80077" -e "0x80078" -e "0x80079" -e "0x8007A" -e "0x8007B" -e "0x8007C" -e "0x8007D" -e "0x8007E" -e "0x8007F" -e "0x80080" -e "0x80081" -e "0x80082" -e "0x80083" -e "0x80084" -e "0x80085" -e "0x80086" -e "0x80087" -e "0x80088" -e "0x80089" -e "0x8008A" -e "0x8008B" -e "0x8008C" -e "0x8008D" -e "0x8008E" -e "0x8008F" disc1.c | grep -e "(function)" -e "(split chunk)" | head -48
echo "window-fn marker count:"
grep -n -e "0x8006F" -e "0x80070" -e "0x80071" -e "0x80072" -e "0x80073" -e "0x80074" -e "0x80075" -e "0x80076" -e "0x80077" -e "0x80078" -e "0x80079" -e "0x8007A" -e "0x8007B" -e "0x8007C" -e "0x8007D" -e "0x8007E" -e "0x8007F" -e "0x80080" -e "0x80081" -e "0x80082" -e "0x80083" -e "0x80084" -e "0x80085" -e "0x80086" -e "0x80087" -e "0x80088" -e "0x80089" -e "0x8008A" -e "0x8008B" -e "0x8008C" -e "0x8008D" -e "0x8008E" -e "0x8008F" disc1.c | grep -c -e "(function)" -e "(split chunk)"
echo "===C496DONE=== the era semantics are receipted - the guard design follows from these only - digest is pure ASCII"
