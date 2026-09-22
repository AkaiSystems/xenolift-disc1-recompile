#!/bin/bash
# c505_extract.sh - READ-ONLY CAPTURE CENSUS, NO RUN, NO
# BUILD, NO PATCH. The c504 ship PASSED as designed: the
# R1394 guard intercepted the wrong-module dispatch at
# 0x800737EC, the interpreter entered with real guest
# state (r31=80019C0C sp=80200000), and the FIRST word at
# the entry was CE53EBD4 (op=0x33, the LWC3/COP3-load
# family - which has NO meaning on PSX hardware) -> the
# explicit [ovlstop] class=3, exit 99, the whole 135168-byte
# window captured to ovlstop_capture.bin. THE QUESTION NOW:
# is CE53EBD4 CODE (a genuinely different module whose
# entry instruction the interpreter must learn) or DATA
# (the movie module's entry is NOT at 0x47EC - the game
# dispatched a boot-era address into a movie-era window)?
# THIS CENSUS receipts: (1) the capture at the entry
# offset 0x47EC +/- context words; (2) the module base
# region (offset 0); (3) the emit_ref.bin at the same
# offsets + the first-difference scan; (4) the window's
# nz-density (dense code vs sparse); (5) the [lzss]/
# module-6 install receipts (where file#18 actually
# unpacked); (6) the guard-fire caller context.
# Fail-closed, tee'd to /tmp/c505_receipts.txt.
# Pure-ASCII output.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C505-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c505_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="13aab535963b12c3ff0515d0c2892e8d7625327afa09a3569ae1f2d7b3e1c5d4"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the c504 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the c504 tree with the landed interpreter)"
CAP="ovlstop_capture.bin"
REF="emit_ref.bin"
for F in "$CAP" "$REF"; do
  if [ ! -s "$F" ]; then echo "GATE-FAILED: $F missing/empty"; exit 0; fi
done
echo "CAP_SHA=$(shasum -a 256 "$CAP" | cut -d" " -f1) ($(wc -c < "$CAP" | tr -d " ") bytes)"
echo "REF_SHA=$(shasum -a 256 "$REF" | cut -d" " -f1)"
echo "===ENTRY505=== the live capture at the entry offset 0x47EC (+/- context, as words)"
python3 - <<'PEOF'
cap = open("ovlstop_capture.bin", "rb").read()
ref = open("emit_ref.bin", "rb").read()
base = 0x8006F000
off = 0x800737EC - base
print("entry offset in capture: 0x%X (%d)" % (off, off))
def words(buf, o, n):
    out = []
    for i in range(n):
        w = int.from_bytes(buf[o+4*i:o+4*i+4], "little")
        out.append(w)
    return out
print("--- 8 words BEFORE the entry (offset 0x%X):" % (off-32))
for i, w in enumerate(words(cap, off-32, 8)):
    pc = base + off - 32 + 4*i
    print("  %08X: %08X" % (pc, w))
print("--- 16 words FROM the entry:")
for i, w in enumerate(words(cap, off, 16)):
    pc = base + off + 4*i
    print("  %08X: %08X" % (pc, w))
w = int.from_bytes(cap[off:off+4], "little")
op = (w >> 26) & 0x3F
rs = (w >> 21) & 0x1F
rt = (w >> 16) & 0x1F
imm = w & 0xFFFF
print("--- the entry word decoded: w=%08X op=0x%02X(%d) rs=r%d rt=r%d imm=0x%04X" % (w, op, op, rs, rt, imm))
print("--- emit_ref at the same offset: %08X (the boot-era code)" % int.from_bytes(ref[off:off+4], "little"))
for i, w in enumerate(words(ref, off, 8)):
    pc = base + off + 4*i
    print("  ref %08X: %08X" % (pc, w))
print("===FIRSTDIFF===")
n = 0
first = -1
for i in range(0, len(cap), 4):
    if cap[i:i+4] != ref[i:i+4]:
        n += 1
        if first < 0:
            first = i
print("differing 4-byte words: %d of %d; first difference at offset 0x%X (vaddr %08X)" % (n, len(cap)//4, first, base+first))
nz = sum(1 for b in cap if b)
print("===NZ505=== live capture nonzero bytes: %d of %d (%.2f%%); emit_ref nonzero: %d of %d" % (nz, len(cap), 100.0*nz/len(cap), sum(1 for b in ref if b), len(ref)))
print("--- the module base region (offset 0, first 64 bytes, words):")
for i, w in enumerate(words(cap, 0, 16)):
    print("  %08X: %08X" % (base + 4*i, w))
PEOF
echo "===LZSS505=== the file#18/movie-module unpack + install receipts"
LOG="run.log"
if [ ! -s "$LOG" ]; then LOG="run.log.d"; fi
grep -n -e "\[lzss\]" "$LOG" | head -20
echo "--- the module-6 entry + install family:"
grep -n -e "MODULE 6 ENTRY" "$LOG" | head -6
grep -n -e "\[stab\]" "$LOG" | head -8
echo "===CTX505=== the guard-fire caller context (r31=80019C0C)"
grep -n -e "ovlint" "$LOG" | head -8
grep -n -B2 -A2 -e "r31=80019C0C" "$LOG" | head -12
echo "--- what dispatched 0x800737EC (the receipt era):"
grep -n -e "800737EC" "$LOG" | head -12
echo "===C505DONE=== the capture is decoded: code-or-data is receipted - the c506 step follows from these receipts only - digest is pure ASCII"
