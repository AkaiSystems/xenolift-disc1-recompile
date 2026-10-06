#!/usr/bin/env python3
"""Find the disc file + load base that puts a function prologue (addiu sp,sp,-N) at every given call target.
usage: fitmod.py <target_hex> ...   (scans main-archive files 2..1400, raw and LZSS)"""
import struct, sys, os
sys.path.insert(0, os.path.dirname(__file__))
DISC = os.path.expanduser('~/Desktop/PS7Z/PS1Games/Xenogears (USA) (Disc 1)/Xenogears (USA) (Disc 1)/Xenogears (USA) (Disc 1).bin')
exe = open(os.path.expanduser('~/Downloads/xenolift/SLUS_006.64'), 'rb').read()
f = open(DISC, 'rb')
def ftab(n):  # n = raw entry index in the table at 0x80010004 (main archive file k = entry k + 22)
    o = 0x800 + 0x80010004 + 7 * n - 0x80010000; e = exe[o:o + 7]
    return e[0] | e[1] << 8 | e[2] << 16, e[3] | e[4] << 8 | e[5] << 16
def rd(lba, n):
    out = b''
    for i in range((n + 2047) // 2048):
        f.seek((lba + i) * 2352 + 24); out += f.read(2048)
    return out[:n]
def unlzss(src):
    size = struct.unpack_from('<I', src, 0)[0] & 0x3FFFFF
    if size == 0 or size > 0x200000: return None
    i = 4; out = bytearray()
    try:
        while len(out) < size:
            ctl = src[i]; i += 1
            for b in range(8):
                if len(out) >= size: break
                if ctl & (1 << b):
                    b0, b1 = src[i], src[i + 1]; i += 2
                    off = b0 | ((b1 & 0xF) << 8); ln = (b1 >> 4) + 3; s = len(out) - off
                    if s < 0: return None
                    for k in range(ln): out.append(out[s + k])
                else:
                    out.append(src[i]); i += 1
    except IndexError:
        return None
    return bytes(out)
if __name__ != "__main__": T = []
else: T = sorted(int(a, 16) for a in sys.argv[1:])
def pro(img, o):
    if o < 0 or o + 4 > len(img): return False
    x = struct.unpack_from('<I', img, o)[0]
    if (x >> 16) == 0x27BD and (x & 0x8000): return True
    return o >= 8 and struct.unpack_from('<I', img, o - 8)[0] == 0x03E00008  # leaf: right after a jr ra + delay slot
seen = set()
for n in (range(0, 1500) if __name__ == '__main__' else ()):
    lba, sz = ftab(n)
    if lba < 150 or lba > 330000 or sz < 64 or sz > 0x300000 or (lba, sz) in seen: continue
    seen.add((lba, sz))
    raw = rd(lba, sz)
    for kind, img in (('raw', raw), ('lzss', unlzss(raw + b'\0' * 2048))):
        if not img: continue
        lo = max(T[-1] - len(img) + 4, 0x80000000); hi = T[0]
        for B in range((lo + 3) & ~3, hi + 1, 4):
            if all(pro(img, t - B) for t in T):
                print(f'entry {n} ({kind}) LBA {lba} size {sz} -> {len(img)} bytes, base {B:08X}..{B+len(img):08X}')
