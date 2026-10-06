#!/usr/bin/env python3
"""Offline STR v2 frame -> MDEC RLE (halfwords), to check what the runtime feeds the MDEC.
usage: strv2.py <disc.bin> <lba>[:frame] [cmp_rle.bin]   (scan from lba, 2352-byte raw sectors, for that STR frame number)"""
import struct, sys
AC = {  # MPEG-1 table B.14 (sign bit follows), code -> (run, level)
 '11':(0,1),'011':(1,1),'0100':(0,2),'0101':(2,1),'00101':(0,3),'00111':(3,1),'00110':(4,1),'000110':(1,2),'000111':(5,1),
 '000101':(6,1),'000100':(7,1),'0000110':(0,4),'0000100':(2,2),'0000111':(8,1),'0000101':(9,1),'00100110':(0,5),'00100001':(0,6),
 '00100101':(1,3),'00100100':(3,2),'00100111':(10,1),'00100011':(11,1),'00100010':(12,1),'00100000':(13,1),'0000001010':(0,7),
 '0000001100':(1,4),'0000001011':(2,3),'0000001111':(4,2),'0000001001':(5,2),'0000001110':(14,1),'0000001101':(15,1),'0000001000':(16,1),
 '000000011101':(0,8),'000000011000':(0,9),'000000010011':(0,10),'000000010000':(0,11),'000000011011':(1,5),'000000010100':(2,4),
 '000000011100':(3,3),'000000010010':(4,3),'000000011110':(6,2),'000000010101':(7,2),'000000010001':(8,2),'000000011111':(17,1),
 '000000011010':(18,1),'000000011001':(19,1),'000000010111':(20,1),'000000010110':(21,1),'0000000011010':(0,12),'0000000011001':(0,13),
 '0000000011000':(0,14),'0000000010111':(0,15),'0000000010110':(1,6),'0000000010101':(1,7),'0000000010100':(2,5),'0000000010011':(3,4),
 '0000000010010':(5,3),'0000000010001':(9,2),'0000000010000':(10,2),'0000000011111':(22,1),'0000000011110':(23,1),'0000000011101':(24,1),
 '0000000011100':(25,1),'0000000011011':(26,1)}
for k in range(16): AC['0000000001' + format(15 - k, '04b')] = (0, 16 + k)          # (0,16)..(0,31), 14 bits
for k in range(9): AC['00000000001' + format(8 - k, '04b')] = (0, 32 + k)            # (0,32)..(0,40), 15 bits
for k, lv in enumerate(range(8, 15)): AC['00000000001' + format(0b1111 - k, '04b')] = (1, lv)
for code, rl in {'0000000000010011':(1,15),'0000000000010010':(1,16),'0000000000010001':(1,17),'0000000000010000':(1,18),'0000000000010100':(6,3),
 '0000000000011010':(11,2),'0000000000011001':(12,2),'0000000000011000':(13,2),'0000000000010111':(14,2),'0000000000010110':(15,2),
 '0000000000010101':(16,2),'0000000000011111':(27,1),'0000000000011110':(28,1),'0000000000011101':(29,1),'0000000000011100':(30,1),'0000000000011011':(31,1)}.items(): AC[code] = rl

def frame_bytes(disc, lba, frame=None):
    """Collect one frame's video sectors (skipping interleaved XA audio) from lba on; frame=None takes the first frame found."""
    f = open(disc, 'rb'); out = b''; k = 0; got = 0
    while True:
        f.seek((lba + k) * 2352); sec = f.read(2352); hdr = sec[24:56]; k += 1
        if hdr[:4] != b'\x60\x01\x01\x80': continue      # interleaved XA audio sector
        fno = struct.unpack('<I', hdr[8:12])[0]
        if frame is None: frame = fno
        if fno != frame: continue
        cnt = struct.unpack('<H', hdr[6:8])[0]; out += sec[56:56 + 2016]; got += 1
        if got >= cnt: return out, fno, struct.unpack('<HH', hdr[16:20])

def decode(data, nblocks=None):
    nwords, magic, q, ver = struct.unpack('<HHHH', data[:8]); assert magic == 0x3800 and ver == 2, (hex(magic), ver)
    bits = ''.join(format(struct.unpack('<H', data[i:i + 2])[0], '016b') for i in range(8, len(data) - 1, 2))
    p = 0; rle = []; blocks = 0
    def take(n):
        nonlocal p; v = bits[p:p + n]; p += n; return v
    while (blocks < nblocks if nblocks else len(rle) < nwords * 2) and p < len(bits) - 32:
        dc = int(take(10), 2); rle.append((q << 10) | dc); blocks += 1
        while True:
            if bits.startswith('10', p): p += 2; rle.append(0xFE00); break
            if bits.startswith('000001', p):
                p += 6; run = int(take(6), 2); lv = int(take(10), 2); rle.append((run << 10) | lv); continue
            for L in range(2, 17):
                c = bits[p:p + L]
                if c in AC:
                    p += L; run, lv = AC[c]; s = take(1)
                    rle.append((run << 10) | ((-lv if s == '1' else lv) & 0x3FF)); break
            else: raise ValueError(f'bad code at bit {p} block {blocks}: {bits[p:p + 16]}')
    return nwords, q, rle, blocks

if __name__ == '__main__':
    disc, lba = sys.argv[1], sys.argv[2]
    fr = int(lba.split(':')[1]) if ':' in lba else None
    data, fno, (w, h) = frame_bytes(disc, int(lba.split(':')[0]), fr)
    nwords, q, rle, blocks = decode(data, (w // 16) * (h // 16) * 6)
    print(f'frame {fno} {w}x{h} q={q} header_words={nwords} decoded halfwords={len(rle)} blocks={blocks} EOBs={rle.count(0xFE00)}')
    if len(sys.argv) > 3:
        got = list(struct.unpack(f'<{len(open(sys.argv[3], "rb").read()) // 2}H', open(sys.argv[3], 'rb').read()))
        print(f'runtime RLE: {len(got)} halfwords, EOBs={got.count(0xFE00)}')
        for i, (a, b) in enumerate(zip(rle, got)):
            if a != b:
                print(f'first mismatch at halfword {i} (block ~{rle[:i].count(0xFE00)}): expected {rle[max(0,i-4):i+6]} got {got[max(0,i-4):i+6]}'); break
        else: print('runtime RLE matches the disc decode over', min(len(rle), len(got)), 'halfwords')
