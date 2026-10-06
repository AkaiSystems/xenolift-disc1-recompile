#!/usr/bin/env python3
"""Write a QuickTime .mov (Photo-JPEG video track) from a folder of same-size JPEGs with per-frame durations.
No external encoder needed; QuickTime/AVFoundation plays Photo-JPEG natively.
usage: jpgs2mov.py <jpg_dir> <timing.json> <out.mov>
timing.json: {"refresh_hz": 60, "durations": [n0, n1, ...]} (durations in display refreshes, one per frame)"""
import glob, json, os, struct, sys

def box(kind, payload):
    return struct.pack('>I', 8 + len(payload)) + kind + payload

def full(kind, version, flags, payload):
    return box(kind, struct.pack('>I', (version << 24) | flags) + payload)

def jpeg_size(data):
    i = 2
    while i < len(data):
        if data[i] != 0xFF: i += 1; continue
        m = data[i + 1]
        if m in (0xC0, 0xC1, 0xC2):
            h, w = struct.unpack('>HH', data[i + 5:i + 9]); return w, h
        i += 2 + struct.unpack('>H', data[i + 2:i + 4])[0]
    raise ValueError('no SOF')

def main():
    jdir, tpath, out = sys.argv[1:4]
    t = json.load(open(tpath)); hz = t.get('refresh_hz', 60); durs = t['durations']
    files = sorted(glob.glob(os.path.join(jdir, '*.jpg')))
    assert len(files) == len(durs), (len(files), len(durs))
    frames = [open(f, 'rb').read() for f in files]
    w, h = jpeg_size(frames[0])
    total = sum(durs)
    matrix = struct.pack('>9I', 0x10000, 0, 0, 0, 0x10000, 0, 0, 0, 0x40000000)
    ftyp = box(b'ftyp', b'qt  ' + struct.pack('>I', 0x200) + b'qt  ')
    mdat_payload = b''.join(frames)
    mdat = box(b'mdat', mdat_payload)
    data_off = len(ftyp) + 8
    mvhd = full(b'mvhd', 0, 0, struct.pack('>IIII', 0, 0, hz, total) + struct.pack('>IH', 0x10000, 0x100) + b'\0' * 10 + matrix + b'\0' * 24 + struct.pack('>I', 2))
    tkhd = full(b'tkhd', 0, 0xF, struct.pack('>IIIII', 0, 0, 1, 0, total) + b'\0' * 8 + struct.pack('>hhhh', 0, 0, 0, 0) + matrix + struct.pack('>II', w << 16, h << 16))
    mdhd = full(b'mdhd', 0, 0, struct.pack('>IIII', 0, 0, hz, total) + struct.pack('>HH', 0, 0))
    hdlr_m = full(b'hdlr', 0, 0, b'mhlr' + b'vide' + b'appl' + struct.pack('>II', 0, 0) + bytes([12]) + b'VideoHandler')
    vmhd = full(b'vmhd', 0, 1, struct.pack('>HHHH', 0x40, 0x8000, 0x8000, 0x8000))
    hdlr_d = full(b'hdlr', 0, 0, b'dhlr' + b'alis' + b'appl' + struct.pack('>II', 0, 0) + bytes([11]) + b'DataHandler')
    dref = full(b'dref', 0, 0, struct.pack('>I', 1) + full(b'alis', 0, 1, b''))
    dinf = box(b'dinf', dref)
    name = b'Photo - JPEG'
    desc = (b'\0' * 6 + struct.pack('>H', 1) + struct.pack('>HH', 0, 0) + b'appl' + struct.pack('>II', 0, 0x200)
            + struct.pack('>HH', w, h) + struct.pack('>II', 72 << 16, 72 << 16) + struct.pack('>I', 0) + struct.pack('>H', 1)
            + bytes([len(name)]) + name + b'\0' * (31 - len(name)) + struct.pack('>hh', 24, -1))
    stsd = full(b'stsd', 0, 0, struct.pack('>I', 1) + box(b'jpeg', desc))
    # merge equal consecutive durations
    runs = []
    for d in durs:
        if runs and runs[-1][1] == d: runs[-1][0] += 1
        else: runs.append([1, d])
    stts = full(b'stts', 0, 0, struct.pack('>I', len(runs)) + b''.join(struct.pack('>II', c, d) for c, d in runs))
    stsc = full(b'stsc', 0, 0, struct.pack('>I', 1) + struct.pack('>III', 1, len(frames), 1))
    stsz = full(b'stsz', 0, 0, struct.pack('>II', 0, len(frames)) + b''.join(struct.pack('>I', len(f)) for f in frames))
    stco = full(b'stco', 0, 0, struct.pack('>II', 1, data_off))
    stss = full(b'stss', 0, 0, struct.pack('>I', len(frames)) + b''.join(struct.pack('>I', i + 1) for i in range(len(frames))))
    stbl = box(b'stbl', stsd + stts + stss + stsc + stsz + stco)
    minf = box(b'minf', vmhd + hdlr_d + dinf + stbl)
    mdia = box(b'mdia', mdhd + hdlr_m + minf)
    trak = box(b'trak', tkhd + mdia)
    moov = box(b'moov', mvhd + trak)
    with open(out, 'wb') as f:
        f.write(ftyp); f.write(mdat); f.write(moov)
    print(f'{len(frames)} frames {w}x{h}, {total / hz:.2f}s, {os.path.getsize(out) // (1024 * 1024)} MB -> {out}')

main()
