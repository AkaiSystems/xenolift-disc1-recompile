#!/bin/bash
# c246_promotion_gate_dump.sh - READ-ONLY: no patch, no compile, no run.
# THE c245 VERDICT: the stage-2 module emit is a SELF-POISONING FEEDBACK
# LOOP - [fldcap2] R704 captures the stage-2 window at FIELD FAULT
# (-> stage2_field.bin; run.sh promotes it to stage2_region.bin for the
# next emit), and stage2_field.bin == stage2_region.bin BYTE-IDENTICAL
# (sha f65d956e): a capture taken while the module was half-installed
# is the CURRENT EMIT INPUT. Receipts: the module walks its callback
# table into ASCII strings (16 skiphook services: Mod/Stre/Paus/ Err/
# d ST/Wait/ing = the string table read as function pointers), the live
# module head at 801D3000 is garbled, and [ovlfault] R786 ALREADY
# REJECTED a capture as not-real-module-code - the validation concept
# EXISTS but covers only overlay_fault, not the stage-2 promotion. Also
# landed this run: the R1318 terminator re-point PASSed (hand #14
# v0=0x801DD680, a real block), zrfF fired its first legacy-fetch
# consumer serve, all 564 traps latch=1 (the held class).
# THE FIX TARGET: gate the fldcap2->stage2_region promotion on a
# content check (module head = real MIPS, not strings), keeping the
# previous good capture on mismatch. THIS CYCLE extracts the promotion
# machinery byte-exactly: the run.sh promote step, the R704 fldcap2
# camera code, the R786 ovlfault validation code, and the head words of
# all three emit-input artifacts. The c247 patch is decided by these
# receipts.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C246-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
LOG="run.log"
SRC="runtime/runtime.c"
EXPECT="c010aab8ef71f1b011136a03c294e49d2202238fe52f49976845d7c125c633c1"
if [ ! -s "$LOG" ]; then echo "C246-FAILED: run.log missing"; exit 1; fi
SS=$(shasum -a 256 "$LOG" | cut -d" " -f1)
echo "LOG_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: run.log is not the c243 post-run log"; exit 0; fi
echo "BASELINE_VERIFIED"
P="promo_c246_$(date +%Y%m%d_%H%M%S)"
if ! (mkdir -p "$P" && cp -p "$LOG" "$P/run.log"); then echo "C246-FAILED: preserve failed"; exit 1; fi
echo "PRESERVED: $P/run.log sha=$SS"

echo "===PROMOSH=== the run.sh promotion step (stage2_field -> stage2_region)"
grep -n "stage2" run.sh | head -12
PN=$(grep -n "stage2_field" run.sh | head -1 | cut -d: -f1)
echo "promote-line=$PN"
if [ -n "$PN" ]; then
  S=$((PN-14)); [ "$S" -lt 1 ] && S=1
  sed -n "${S},$((PN+14))p" run.sh
fi

echo "===FLDCAP2SRC=== the R704 fldcap2 camera code (the capture site)"
FN=$(grep -n "fldcap2\]" "$SRC" | head -1 | cut -d: -f1)
echo "fldcap2-line=$FN"
if [ -n "$FN" ]; then
  S=$((FN-30)); [ "$S" -lt 1 ] && S=1
  sed -n "${S},$((FN+14))p" "$SRC"
fi

echo "===OVLFAULTSRC=== the R786 ovlfault validation code (the existing prologue gate)"
ON=$(grep -n "ovlfault\]" "$SRC" | head -1 | cut -d: -f1)
echo "ovlfault-line=$ON"
if [ -n "$ON" ]; then
  S=$((ON-30)); [ "$S" -lt 1 ] && S=1
  sed -n "${S},$((ON+16))p" "$SRC"
fi

echo "===HEADWORDS=== the three emit-input artifacts: head words (which is real MIPS?)"
python3 - <<'PYEOF'
import os, hashlib

def words_of(path, n=16, off=0):
    if not os.path.exists(path):
        return None
    with open(path, "rb") as f:
        f.seek(off)
        d = f.read(n*4)
    if len(d) < n*4:
        return None
    return [d[i*4] | (d[i*4+1]<<8) | (d[i*4+2]<<16) | (d[i*4+3]<<24) for i in range(n)]

def looks_mips(ws):
    # rough MIPS-opcode sanity: top 6 bits of each word in 0x00-0x3F is
    # ALWAYS true for any word; use the classic prologue patterns instead
    hits = 0
    for w in ws:
        if (w & 0xFFFF0000) == 0x27BD0000 or (w & 0xFFFF0000) == 0x3C030000:
            hits += 1
        if (w & 0xFC000000) in (0x0C000000, 0x8C000000, 0xAC000000):
            hits += 1
    return hits

for name in ("stage2_region.bin", "stage2_field.bin", "overlay_fault.bin", "overlay_region.bin"):
    ws = words_of(name)
    if ws is None:
        print("%s: absent" % name)
        continue
    print("%s: %s" % (name, " ".join("%08X" % w for w in ws[:12])))
    print("   mips-ish hits=%d/12" % looks_mips(ws[:12]))
    # ASCII-ness census of the first 1KB (a string table masquerading as code?)
    with open(name, "rb") as f:
        head = f.read(1024)
    printable = sum(1 for b in head if 32 <= b < 127 or b in (0, 9, 10))
    print("   first-1KB printable-bytes=%d/1024" % printable)
PYEOF

echo "===VTSVC246=== the vtable-cell consumer family (who reads 801D3008+)"
grep -c "vtcell\]" "$LOG"
grep -n "vtcell\]" "$LOG" | head -4

echo "===SKIPHOOK246=== the skiphook census (string-table callbacks)"
grep -c "skiphook\]" "$LOG"
echo "--- decoded targets (hex -> ASCII, the string-table proof):"
grep -o "invalid dispatch target [0-9A-F]*" "$LOG" | awk '{print $4}' | sort -u | head -12 | while read H; do
  A=$(printf "%s" "$H" | python3 -c "import sys; h=sys.stdin.read().strip(); print(''.join(chr(int(h[i:i+2],16)) if 32<=int(h[i:i+2],16)<127 else '.' for i in range(0,len(h),2))" 2>/dev/null)
  echo "$H -> $A"
done

echo "===C246DONE=== promotion gate dump complete - the c247 patch is decided by these receipts"
