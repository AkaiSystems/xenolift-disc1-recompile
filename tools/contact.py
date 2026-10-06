#!/usr/bin/env python3
"""Contact sheet of VRAM snapshots: renders each snapshot's display rect (24-bit when the file
name carries _d24, else 15-bit) and tiles them, 4 per row, labelled by time in the file name.
usage: contact.py <out.png> <vram_*.bin>..."""
import re, struct, sys, zlib
def rect(path):
    v = open(path, 'rb').read()
    m = re.search(r'_(\d+)x(\d+)_at(\d+)_(\d+)(?:_d(\d+))?', path)
    w, h, x0, y0, d = int(m[1]), int(m[2]), int(m[3]), int(m[4]), int(m[5] or 15)
    w, h = min(w, 320), min(h, 240)
    px = []
    for y in range(y0, y0 + h):
        row = bytearray()
        if d == 24:
            o = (y * 1024 + x0) * 2; row += v[o:o + w * 3]
        else:
            for x in range(x0, x0 + w):
                p = v[(y * 1024 + x) * 2] | v[(y * 1024 + x) * 2 + 1] << 8
                row += bytes(((p & 31) << 3, ((p >> 5) & 31) << 3, ((p >> 10) & 31) << 3))
        row += bytes(320 * 3 - len(row)); px.append(row)
    while len(px) < 240: px.append(bytearray(320 * 3))
    return px
files = sys.argv[2:]; cols = 4; rows = (len(files) + cols - 1) // cols
W, H = cols * 324, rows * 244
img = [bytearray(W * 3) for _ in range(H)]
for i, f in enumerate(files):
    r = rect(f); ox, oy = (i % cols) * 324 + 2, (i // cols) * 244 + 2
    for y in range(240): img[oy + y][ox * 3:(ox + 320) * 3] = r[y]
raw = b''.join(b'\x00' + bytes(r) for r in img)
def ch(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
open(sys.argv[1], 'wb').write(b'\x89PNG\r\n\x1a\n' + ch(b'IHDR', struct.pack('>IIBBBBB', W, H, 8, 2, 0, 0, 0)) + ch(b'IDAT', zlib.compress(raw, 6)) + ch(b'IEND', b''))
print('wrote', sys.argv[1], len(files), 'frames:', ' '.join(re.search(r'vram_t(\d+)', f)[1] for f in files))
