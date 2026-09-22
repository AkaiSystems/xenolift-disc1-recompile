#!/usr/bin/env python3
"""xenoview_ansi: legacy terminal mode (ANSI half-blocks). Prefer xenoview.py."""
import os
import struct
import sys
import time

CW, CH = 78, 26


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


def frame(vram, dx, dy, dw, dh):
    rows = []
    for cy in range(CH):
        cells = []
        sy1 = dy + (cy * 2 * dh) // (CH * 2)
        sy2 = dy + ((cy * 2 + 1) * dh) // (CH * 2)
        for cx in range(CW):
            sx = dx + (cx * dw) // CW
            r1, g1, b1 = c8(struct.unpack_from('<H', vram, (sy1 * 1024 + sx) * 2)[0])
            r2, g2, b2 = c8(struct.unpack_from('<H', vram, (sy2 * 1024 + sx) * 2)[0])
            cells.append('\x1b[38;2;%d;%d;%d;48;2;%d;%d;%dm\xE2\x96\x80'
                         % (r1, g1, b1, r2, g2, b2))
        rows.append(''.join(cells))
    return '\x1b[H' + '\n'.join(rows) + '\x1b[0m\nxenoview %dx%d @(%d,%d)' % (dw, dh, dx, dy)


def main():
    once = '--once' in sys.argv
    if os.name == 'nt':
        print('xenoview needs an ANSI terminal (macOS Terminal works).')
        return
    sys.stdout.write('\x1b[2J')
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
        sys.stdout.write(frame(vram, dx, dy, dw, dh) + '\n')
        sys.stdout.flush()
        if once:
            break
        time.sleep(0.25)


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        pass
