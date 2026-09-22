#!/usr/bin/env python3
"""R694 xenoview: the live framebuffer as a REAL PICTURE in your browser.

The old version painted the screen with terminal color-codes (ANSI) —
on some terminal configs those print as literal letters. This version
writes a PNG image and opens a browser window that auto-refreshes.
No dependencies beyond python3 stdlib. Ctrl-C the script to stop it.

    python3 xenoview.py          (browser window, auto-refresh)
    python3 xenoview.py --ansi   (old terminal mode)
    python3 xenoview.py --once   (write one frame and exit)
"""
import os
import struct
import subprocess
import sys
import time
import zlib


def c8(p):
    r5 = p & 0x1F
    g5 = (p >> 5) & 0x1F
    b5 = (p >> 10) & 0x1F
    return ((r5 << 3) | (r5 >> 2), (g5 << 3) | (g5 >> 2), (b5 << 3) | (b5 >> 2))


def read_meta():
    try:
        with open('vram_live.meta') as f:
            dx, dy, dw, dh = (int(x) for x in f.read().split()[:4])
        return dx, dy, max(16, min(1024 - dx, dw)), max(16, min(512 - dy, dh))
    except Exception:
        return 0, 0, 320, 240


def crop_rgb(vram, dx, dy, dw, dh, scale=2):
    out = bytearray()
    for yy in range(dh):
        row = vram[(dy + yy) * 1024 * 2 + dx * 2:(dy + yy) * 1024 * 2 + (dx + dw) * 2]
        line = bytearray()
        for x in range(dw):
            r, g, b = c8(struct.unpack_from('<H', row, x * 2)[0])
            line += bytes((r, g, b)) * scale
        out += line * scale
    return dw * scale, dh * scale, bytes(out)


def write_png(path, w, h, rgb):
    def chunk(t, d):
        c = t + d
        return struct.pack('>I', len(d)) + c + struct.pack('>I', zlib.crc32(c) & 0xFFFFFFFF)
    raw = b''.join(b'\x00' + rgb[y * w * 3:(y + 1) * w * 3] for y in range(h))
    with open(path, 'wb') as f:
        f.write(b'\x89PNG\r\n\x1a\n'
                + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
                + chunk(b'IDAT', zlib.compress(raw, 6))
                + chunk(b'IEND', b''))


HTML = """<!doctype html><html><head><meta charset="utf-8"><title>xenoview</title>
<style>body{background:#111;color:#888;font-family:sans-serif;text-align:center;margin:0}
img{image-rendering:pixelated;width:100%;max-width:960px;display:block;margin:0 auto}</style>
</head><body><img id=f><p>xenoview live &mdash; auto-refresh</p>
<script>setInterval(function(){document.getElementById('f').src='vram_live.png?'+Date.now()},500)</script>
</body></html>"""


def main():
    once = '--once' in sys.argv
    ansi = '--ansi' in sys.argv
    if ansi:
        os.execv(sys.executable, [sys.executable, os.path.join(os.path.dirname(__file__) or '.', 'xenoview_ansi.py')])
    if not os.path.exists('xenoview.html'):
        with open('xenoview.html', 'w') as f:
            f.write(HTML)
    opened = False
    n = 0
    while True:
        try:
            with open('vram_live.bin', 'rb') as f:
                vram = f.read()
            if len(vram) < 1024 * 512 * 2:
                time.sleep(0.25)
                continue
        except Exception:
            time.sleep(0.25)
            continue
        dx, dy, dw, dh = read_meta()
        # R695: the game double-buffers and the display meta sometimes points at
        # the empty buffer (c266: pixels exist, display window empty). Auto-pick
        # the most non-blank of the 4 classic framebuffer regions.
        best, best_n = (dx, dy), -1
        for cx, cy in ((0, 0), (0, 240), (320, 0), (320, 240), (dx, dy)):
            n = 0
            for y in range(cy, min(cy + 240, 512), 4):
                base = y * 1024 * 2
                for x in range(cx, min(cx + 320, 1024), 4):
                    if vram[base + x * 2:base + x * 2 + 2] != b'\x00\x00':
                        n += 1
            if n > best_n:
                best, best_n = (cx, cy), n
        dx, dy = best
        dw, dh = 320, 240
        w, h, rgb = crop_rgb(vram, dx, dy, dw, dh)
        write_png('vram_live.png', w, h, rgb)
        n += 1
        if not opened and n >= 2:
            try:
                subprocess.Popen(['open', 'xenoview.html'])
                opened = True
                print('xenoview: browser window opened (vram_live.png refreshes 2x/sec)')
            except Exception as e:
                print('open failed (%s) — open vram_live.png manually' % e)
                opened = True
        if once:
            break
        time.sleep(0.5)


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        pass
