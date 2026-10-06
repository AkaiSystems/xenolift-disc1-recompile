#!/usr/bin/env python3
"""Contact sheet PNG of R1683 frame dumps (frame_NNNN_<w>x<h>.rgb): n distinct frames sampled evenly, 4 per row.
usage: rgbsheet.py <frame_dir> <out.png> [n=12] [crop_h=224]"""
import glob, os, re, struct, sys, zlib
d, outp = sys.argv[1], sys.argv[2]
n = int(sys.argv[3]) if len(sys.argv) > 3 else 12
ch = int(sys.argv[4]) if len(sys.argv) > 4 else 224
fs = sorted(glob.glob(os.path.join(d, 'frame_*_*x*.rgb')))
w, h = map(int, re.search(r'_(\d+)x(\d+)\.rgb$', fs[0]).groups()); h = min(h, ch)
frames, prev = [], None
for f in fs:
    b = open(f, 'rb').read()[:w * h * 3]
    if len(b) == w * h * 3 and b != prev and any(b[::97]): frames.append(b)
    prev = b
pick = [frames[i * (len(frames) - 1) // max(1, n - 1)] for i in range(min(n, len(frames)))]
cols = 4; rows = (len(pick) + cols - 1) // cols; G = 4
W, H = cols * w + (cols + 1) * G, rows * h + (rows + 1) * G
img = bytearray(W * H * 3)
for k, b in enumerate(pick):
    ox, oy = G + (k % cols) * (w + G), G + (k // cols) * (h + G)
    for y in range(h):
        o = ((oy + y) * W + ox) * 3; img[o:o + w * 3] = b[y * w * 3:(y + 1) * w * 3]
raw = b''.join(b'\0' + bytes(img[y * W * 3:(y + 1) * W * 3]) for y in range(H))
def chunk(t, p): return struct.pack('>I', len(p)) + t + p + struct.pack('>I', zlib.crc32(t + p) & 0xffffffff)
open(outp, 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', W, H, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw, 6)) + chunk(b'IEND', b''))
print(f'{len(fs)} dumps, {len(frames)} distinct non-black, sheet of {len(pick)} -> {outp}')
