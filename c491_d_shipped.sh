#!/bin/bash
# c491_extract.sh - READ-ONLY CENSUS, NO RUN, NO BUILD,
# NO PATCH. The c490 verdict: the module window
# 0x8006F000-0x80090000 is runtime-installed code,
# emitted from overlay_input.bin (the BOOT capture);
# 0x8009A280+ is past the capture (SLUS fill). THE
# OVERLAY-IDENTITY QUESTION (Jos's standing warning):
# did the dispatcher run the WRONG translation at
# 0x800739A0 - the boot-captured module's code while
# the movie phase had unpacked its OWN module into the
# window? RECEIPTS: (1) OVLIN491: overlay_input.bin at
# the fault offsets; (2) GUESTRAM491: the firstfault
# RAM dumps at the same vaddrs; (3) EMITTED491: the
# emitted disc1.c bodies at 800737EC/800739A0; (4)
# IDVERDICT491: the boot-capture bytes vs the LIVE
# movie-era bytes (the c485 wildcode dump). Fail-closed,
# tee'd to /tmp/c491_receipts.txt. Pure-ASCII output.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C491-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c491_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="d86f3deb57aed5b0921ab3a82867dea3a1e1d9960028e360bed8d9bdc90d45f8"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the R1387 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the R1387 tree)"
D="disc1.c"
if [ ! -f "$D" ]; then echo "GATE-FAILED: disc1.c not found"; exit 0; fi
if [ ! -f "overlay_input.bin" ]; then echo "GATE-FAILED: overlay_input.bin not found"; exit 0; fi
echo "===OVLIN491=== the boot-captured module window (overlay_input.bin) at the fault offsets"
echo "--- capture bytes for vaddr 0x800737EC (offset 0x37EC):"
od -An -tx4 -j $((0x37EC)) -N 48 overlay_input.bin | head -3
echo "--- capture bytes for vaddr 0x800739A0 (offset 0x49A0):"
od -An -tx4 -j $((0x49A0)) -N 64 overlay_input.bin | head -4
echo "--- the LIVE movie-era RAM at 0x800739A0 (the c485 wildcode dump):"
echo "340600F0 34070140 0C010E78 AFB00010 26240138 00002821 340600F0 34070140 0C010E4A AFB00010 26240194 00002821 00003021 34070140 0C010E78 AFB00010"
echo "--- vaddr 0x8009A2E0 would be capture offset 0x2B280 vs capture size 135168 (0x21000): OUTSIDE the capture (receipted c490)"
echo "===GUESTRAM491=== the firstfault RAM dumps at the fault vaddrs (offset = vaddr - 0x80000000)"
for G in firstfault.*/guest-ram.bin; do
  echo "--- $G ($(wc -c < "$G" | tr -d " ") bytes, dir mtime: $(ls -ld "$(dirname "$G")" | awk "{print \$6, \$7, \$8}")):"
  echo "  vaddr 0x8006FAF0 (the unpacked module header):"
  od -An -tx4 -j $((0x6FAF0)) -N 16 "$G" 2>/dev/null | head -1
  echo "  vaddr 0x800737EC (the module entry):"
  od -An -tx4 -j $((0x737EC)) -N 32 "$G" 2>/dev/null | head -2
  echo "  vaddr 0x800739A0 (the init that ran):"
  od -An -tx4 -j $((0x739A0)) -N 32 "$G" 2>/dev/null | head -2
  echo "  vaddr 0x8009A2E0 (the walked table):"
  od -An -tx4 -j $((0x9A2E0)) -N 32 "$G" 2>/dev/null | head -2
done
echo "===EMITTED491=== the emitted disc1.c bodies (what the dispatcher actually ran)"
LN=$(grep -n -e "0x800737EC (function)" "$D" | head -1 | cut -d: -f1)
echo "--- fn 0x800737EC marker at line $LN:"
if [ -n "$LN" ]; then sed -n "${LN},$((LN+14))p" "$D"; fi
LN2=$(grep -n -e "L_800739A0" "$D" | head -1 | cut -d: -f1)
echo "--- the first L_800739A0 label at line $LN2 (context):"
if [ -n "$LN2" ]; then sed -n "$((LN2>6 ? LN2-6 : 1)),$((LN2+16))p" "$D" | head -24; fi
echo "===IDVERDICT491=== the boot-capture vs the LIVE movie-era bytes (python)"
python3 - <<'PYEOF'
import struct
data = open("overlay_input.bin", "rb").read()
cap = data[0x49A0:0x49A0+64]
print("capture[0x49A0:0x49E0] words:")
print("  " + " ".join("%08X" % w for w in struct.unpack("<16I", cap[:64])))
live = [0x340600F0, 0x34070140, 0x0C010E78, 0xAFB00010, 0x26240138, 0x00002821, 0x340600F0, 0x34070140]
capw = struct.unpack("<8I", cap[:32])
same = all(a == b for a, b in zip(capw, live))
print("LIVE first 8 words:  " + " ".join("%08X" % w for w in live))
print("capture first 8:     " + " ".join("%08X" % w for w in capw))
if same:
    print("VERDICT: IDENTICAL - the boot capture IS the movie module; the overlay-identity hypothesis FAILS for this site; the wild jump came from the module's own code")
else:
    n = 0
    for a, b in zip(capw, live):
        if a != b:
            break
        n += 1
    print("VERDICT: DIFFERENT (first mismatch at word %d) - the dispatcher ran the BOOT-CAPTURED translation while the movie module had unpacked DIFFERENT code: THE OVERLAY-IDENTITY FAULT" % n)
PYEOF
echo "===C491DONE=== the identity verdict is in - the fix design follows from it only - digest is pure ASCII"
