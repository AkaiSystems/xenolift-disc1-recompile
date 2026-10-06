#!/usr/bin/env python3
"""Render a raw 1024x512 VRAM dump (2 bytes/px) to PNG.
usage: vram2png.py <vram.bin> <out.png> [full|24 x y w h]
full = whole VRAM as 15-bit; 24 = the rect (x,y in halfwords, w,h in pixels) decoded as packed 24-bit."""
import struct, sys, zlib
def png(path, w, h, rows):
    raw = b''.join(b'\x00' + bytes(r) for r in rows)
    def chunk(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    open(path, 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
                           + chunk(b'IDAT', zlib.compress(raw, 6)) + chunk(b'IEND', b''))
v = open(sys.argv[1], 'rb').read(); mode = sys.argv[3] if len(sys.argv) > 3 else 'full'
if mode == 'full':
    rows = []
    for y in range(512):
        r = bytearray()
        for x in range(1024):
            p = v[(y * 1024 + x) * 2] | v[(y * 1024 + x) * 2 + 1] << 8
            r += bytes(((p & 31) << 3, ((p >> 5) & 31) << 3, ((p >> 10) & 31) << 3))
        rows.append(r)
    png(sys.argv[2], 1024, 512, rows)
else:
    x0, y0, w, h = map(int, sys.argv[4:8]); rows = []
    for y in range(y0, y0 + h):
        b = v[(y * 1024 + x0) * 2:(y * 1024 + x0) * 2 + w * 3]
        rows.append(bytearray(b))
    png(sys.argv[2], w, h, rows)
print('wrote', sys.argv[2])
