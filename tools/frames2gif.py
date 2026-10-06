#!/usr/bin/env python3
"""Turn R1630 movie frame dumps (frame_NNNN_<w>x<h>.rgb, raw 24-bit RGB) into an animated GIF.
Pure Python (no PIL/ffmpeg): fixed R3G3B2 palette, LZW, consecutive duplicate frames merged.
usage: frames2gif.py <frame_dir> <out.gif> [fps=15] [crop_h=224]"""
import glob, os, re, struct, sys

def lzw(indices, min_size=8):
    clear, eoi = 1 << min_size, (1 << min_size) + 1
    out, bits, nbits = bytearray(), 0, 0
    size = min_size + 1
    def emit(code):
        nonlocal bits, nbits
        bits |= code << nbits; nbits += size
        while nbits >= 8:
            out.append(bits & 0xFF); bits >>= 8; nbits -= 8
    table = {bytes([i]): i for i in range(clear)}
    nxt = eoi + 1
    emit(clear)
    w = b''
    for c in indices:
        wc = w + bytes([c])
        if wc in table:
            w = wc; continue
        emit(table[w])
        if nxt < 4096:
            table[wc] = nxt; nxt += 1
            if nxt > (1 << size) and size < 12: size += 1
        else:
            emit(clear); table = {bytes([i]): i for i in range(clear)}; nxt = eoi + 1; size = min_size + 1
        w = bytes([c])
    if w: emit(table[w])
    emit(eoi)
    if nbits: out.append(bits & 0xFF)
    blocks = bytearray()
    for i in range(0, len(out), 255):
        chunk = out[i:i + 255]; blocks.append(len(chunk)); blocks += chunk
    blocks.append(0)
    return bytes(blocks)

def main():
    d, outp = sys.argv[1], sys.argv[2]
    fps = float(sys.argv[3]) if len(sys.argv) > 3 else 15.0
    crop_h = int(sys.argv[4]) if len(sys.argv) > 4 else 224
    files = sorted(glob.glob(os.path.join(d, 'frame_*_*x*.rgb')))
    if not files: sys.exit('no frames')
    w, h = map(int, re.search(r'_(\d+)x(\d+)\.rgb$', files[0]).groups())
    h = min(h, crop_h)
    pal = bytearray()
    for i in range(256):
        r, g, b = (i >> 5) & 7, (i >> 2) & 7, i & 3
        pal += bytes((r * 255 // 7, g * 255 // 7, b * 255 // 3))
    lut = bytes(range(256))
    frames, last, dup = [], None, []
    for fp in files:
        raw = open(fp, 'rb').read()[:w * h * 3]
        if len(raw) < w * h * 3: continue
        if raw == last: dup[-1] += 1; continue
        last = raw; frames.append(raw); dup.append(1)
    # each dump is one display refresh (fps per dump, 60 for the runtime's flips); accumulate real time so rounding doesn't drift
    g = bytearray(b'GIF89a') + struct.pack('<HHBBB', w, h, 0xF7, 0, 0) + pal
    g += b'\x21\xFF\x0BNETSCAPE2.0\x03\x01\x00\x00\x00'  # loop forever
    t_acc = 0.0; t_emitted = 0
    for raw, n in zip(frames, dup):
        t_acc += n * 100.0 / fps; d = max(2, int(round(t_acc)) - t_emitted); t_emitted += d
        idx = bytes(((raw[i] >> 5) << 5) | ((raw[i + 1] >> 5) << 2) | (raw[i + 2] >> 6) for i in range(0, len(raw), 3))
        g += b'\x21\xF9\x04\x00' + struct.pack('<H', d) + b'\x00\x00'
        g += b'\x2C' + struct.pack('<HHHHB', 0, 0, w, h, 0) + b'\x08' + lzw(idx)
    g += b'\x3B'
    open(outp, 'wb').write(g)
    print(f'{len(files)} dumps -> {len(frames)} distinct frames, {w}x{h}, {len(g)//1024} KB -> {outp}')

main()
