#!/bin/bash
# c373_refdec.sh - READ-ONLY. NO patch, NO run. The c372
# verdict: the LZSS core reads the size word from r4[0:4],
# so the unpack src must begin with the sane expanded size
# (0003FAFE, member offset 0); payload-only delivery can
# never terminate the core. The receipted-working shape: the
# staged copy at 801D9724 = the WHOLE MEMBER, HLE-decoded
# (c227/c228, 260,862 expanded). THIS PASS: the decisive
# offline discriminator - reference-decode staged_f14.bin
# in-probe with both candidate stream starts (member+4 vs
# member+8) and check which yields FieldMain's execution-
# proven prologue (27BDFFC8 3C038001 8C630000 2402FFFF) and
# the R690 expansion checksum 0x0DDD880D.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C373-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="8d14ab4f2385a0004c28bd5a07bc762c5b9407b6da8a817d96554d5e91f226b0"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1365 tree - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1365 tree)"
echo "===STAGED373=== the staged_f14.bin file"
ls -la staged_f14.bin 2>/dev/null || { echo "STAGED-MISSING: staged_f14.bin not on the tree root"; }
find . -name "staged_f14.bin" -maxdepth 3 2>/dev/null | head -4
if [ -s staged_f14.bin ]; then
  echo "--- first 64 bytes ---"
  xxd -l 64 staged_f14.bin
  echo "--- last 16 bytes ---"
  xxd -s -16 staged_f14.bin
fi
echo "===REFDEC373=== the reference decode (both candidate starts)"
python3 - <<'PYEOF'
import struct, os
p = "staged_f14.bin"
if not os.path.exists(p):
    print("REFDEC-SKIP: staged file absent")
else:
    data = open(p, "rb").read()
    print("staged size = %d bytes" % len(data))
    w0 = struct.unpack_from("<I", data, 0)[0]
    w1 = struct.unpack_from("<I", data, 4)[0]
    print("word0 = %08X  word1 = %08X" % (w0, w1))
    PROLOGUE = bytes.fromhex("C8FFBD27") + bytes.fromhex("0180033C") + bytes.fromhex("0000638C") + bytes.fromhex("FFFF0224")
    # little-endian words 27BDFFC8 3C038001 8C630000 2402FFFF as raw bytes
    PRO = struct.pack("<4I", 0x27BDFFC8, 0x3C038001, 0x8C630000, 0x2402FFFF)
    def refdec(data, start, size):
        # the HLE format: groups of [ctrl][8 tokens] LSB-first,
        # bit SET = match (off=((b2&0xF)<<8)|b1, len=(b2>>4)+3,
        # forward copy, overlap allowed), CLEAR = literal.
        # back-references read the WINDOW's current bytes; a read
        # past pos mirrors the C HLE reading stale dst content
        # (modeled here as zeros via the pre-allocated window).
        out = bytearray(size)
        i = start
        lim = len(data)
        pos = 0
        ops = 0
        while pos < size:
            if i >= lim: return None, pos, "input exhausted"
            ctrl = data[i]; i += 1
            for t in range(8):
                if pos >= size: break
                if ctrl & 1:
                    if i + 1 >= lim: return None, pos, "input exhausted"
                    b1 = data[i]; b2 = data[i+1]; i += 2
                    off = ((b2 & 0xF) << 8) | b1
                    ln = (b2 >> 4) + 3
                    sp = pos - off
                    if sp < 0: return None, pos, "before-block at op %d" % ops
                    for k in range(ln):
                        if pos >= size: break
                        out[pos] = out[sp + k]; pos += 1
                    ops += 1
                else:
                    if i >= lim: return None, pos, "input exhausted"
                    out[pos] = data[i]; i += 1; pos += 1
                    ops += 1
                ctrl >>= 1
        return bytes(out), pos, "complete"
    for name, start in [("A: member+4 (staged decode start)", 4), ("B: member+8 (payload start)", 8)]:
        res, n, why = refdec(data, start, w0)
        print("--- candidate %s ---" % name)
        if res is None:
            print("  FAIL: %s (pos=%d)" % (why, n))
        else:
            first4 = struct.unpack_from("<4I", res, 0)
            print("  expanded %d bytes; first words: %08X %08X %08X %08X" % (n, *first4))
            print("  prologue match: %s" % ("YES" if res[:16] == PRO else "no"))
            ck = 0
            for o in range(0, n, 4):
                ck = (ck * 2654435761 + struct.unpack_from("<I", res, o)[0]) & 0xFFFFFFFF
            print("  R690-style checksum: %08X (oracle 0DDD880D)" % ck)
            coord = res[0x8398:0x83A8] if len(res) >= 0x83A8 else b""
            if coord:
                cw = struct.unpack_from("<4I", coord, 0)
                print("  coordinator +0x8398 words: %08X %08X %08X %08X" % cw)
    # also: compare staged+8 with the receipted dest bytes
    print("--- dest-byte check: staged[8:16] = %s (receipted dest[0:8] = FFFF9C30 0702D0FF)" %
          " ".join("%02X" % b for b in data[8:16]))
PYEOF
echo "===OLDWIT373=== the R690/fldgate receipts in the c368 witness (the oracle references)"
WD="witness_c368_20260917_144156"
LOG="$WD/run.log"
[ -s "$LOG" ] || LOG="$WD/run.log.d"
if [ -s "$LOG" ]; then
  grep -n "checksum\|fldgate\|prologue" "$LOG" | head -8
fi
echo "===C373DONE=== the stream start is settled by the reference decode"
