#!/usr/bin/env python3
"""Rebuild a decompressed boot-archive module image from the disc, then disassemble it.
LZSS = the game's own UnpackCompressedBuffer (0x80032EB4): u32 expanded size, then
control bytes (8 flags, LSB first; 1 = back-ref, 0 = literal); back-ref = 2 bytes:
off = b0 | (b1 & 0xF) << 8, len = (b1 >> 4) + 3, copied from out - off.
usage: modimg.py <file#> <load_base_hex> [dis_start_hex dis_end_hex]
writes tools/mod<file#>.bin; with a range, disassembles it from the image."""
import struct, sys, os
sys.path.insert(0, os.path.dirname(__file__))
import dis as D
DISC = os.path.expanduser('~/Desktop/PS7Z/PS1Games/Xenogears (USA) (Disc 1)/Xenogears (USA) (Disc 1)/Xenogears (USA) (Disc 1).bin')
exe = open(os.path.expanduser('~/Downloads/xenolift/SLUS_006.64'), 'rb').read()
def ftab(n):
    o = 0x800 + 0x800100AC + 7 * (n - 2) - 0x80010000; e = exe[o:o + 7]
    return e[0] | e[1] << 8 | e[2] << 16, e[3] | e[4] << 8 | e[5] << 16
def rd(lba, n):
    f = open(DISC, 'rb'); out = b''
    for i in range((n + 2047) // 2048):
        f.seek((lba + i) * 2352 + 24); out += f.read(2048)
    return out  # whole sectors: the game unpacker reads past the member end (R1366)
def unlzss(src):
    size = struct.unpack_from('<I', src, 0)[0] & 0x3FFFFF; i = 4; out = bytearray()
    while len(out) < size:
        ctl = src[i]; i += 1
        for b in range(8):
            if len(out) >= size: break
            if ctl & (1 << b):
                b0, b1 = src[i], src[i + 1]; i += 2
                off = b0 | ((b1 & 0xF) << 8); ln = (b1 >> 4) + 3; s = len(out) - off
                for k in range(ln): out.append(out[s + k])
            else:
                out.append(src[i]); i += 1
    return bytes(out[:size])
n = int(sys.argv[1]); base = int(sys.argv[2], 16)
lba, sz = ftab(n); img = unlzss(rd(lba, sz + 2048))
path = os.path.join(os.path.dirname(__file__), f'mod{n}.bin'); open(path, 'wb').write(img)
print(f'file {n}: LBA {lba} size {sz} -> expanded {len(img)} bytes at {base:08X}..{base+len(img):08X} -> {path}')
if len(sys.argv) > 4:
    lo, hi = int(sys.argv[3], 16), int(sys.argv[4], 16)
    def w(a): return struct.unpack_from('<I', img, a - base)[0]
    D.w = w
    for a in range(lo, hi, 4): print('%08X %08X %s' % (a, w(a), D.dis(a)))
