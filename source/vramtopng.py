#!/usr/bin/env python3
"""R125: render PS1 VRAM capture -> vram.png (full) + screen.png (display crop)."""
import zlib, struct


def png(path, w, h, rows):
    raw = b''.join(b'\x00' + row for row in rows)

    def chunk(t, d):
        c = zlib.crc32(t + d) & 0xFFFFFFFF
        return struct.pack('>I', len(d)) + t + d + struct.pack('>I', c)

    hdr = struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)
    with open(path, 'wb') as f:
        f.write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', hdr)
                + chunk(b'IDAT', zlib.compress(raw, 6)) + chunk(b'IEND', b''))


vram = open('vram.bin', 'rb').read()
metas = open('vram.meta').read().split()
dx, dy, dw, dh = (int(x) for x in metas[:4])
dw = max(16, min(1024 - dx, dw))
dh = max(16, min(512 - dy, dh))


def px(i):
    p = struct.unpack_from('<H', vram, i * 2)[0]
    r5 = p & 0x1F
    g5 = (p >> 5) & 0x1F
    b5 = (p >> 10) & 0x1F
    r8 = (r5 << 3) | (r5 >> 2)
    g8 = (g5 << 3) | (g5 >> 2)
    b8 = (b5 << 3) | (b5 >> 2)
    return bytes((r8, g8, b8))


png('vram.png', 1024, 512,
    [b''.join(px(y * 1024 + x) for x in range(1024)) for y in range(512)])
png('screen.png', dw, dh,
    [b''.join(px((dy + y) * 1024 + dx + x) for x in range(dw)) for y in range(dh)])
print('vram.png (1024x512) + screen.png (%dx%d @ %d,%d) written' % (dw, dh, dx, dy))
