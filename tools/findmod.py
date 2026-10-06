#!/usr/bin/env python3
"""Find which disc-1 table entry (raw or LZSS) contains the bytes of a RAM image window.
usage: findmod.py <ram.bin> <addr_hex> [len]"""
import struct, sys, os
sys.path.insert(0, os.path.dirname(__file__))
import fitmod as FM
ram = open(sys.argv[1], 'rb').read(); addr = int(sys.argv[2], 16); L = int(sys.argv[3]) if len(sys.argv) > 3 else 64
probe = ram[addr & 0x1FFFFF:(addr & 0x1FFFFF) + L]
seen = set()
for n in range(0, 1500):
    lba, sz = FM.ftab(n)
    if lba < 150 or lba > 330000 or sz < 64 or sz > 0x300000 or (lba, sz) in seen: continue
    seen.add((lba, sz)); raw = FM.rd(lba, sz)
    for kind, img in (('raw', raw), ('lzss', FM.unlzss(raw + b'\0' * 2048))):
        if not img: continue
        k = img.find(probe)
        if k >= 0: print(f'entry {n} ({kind}) LBA {lba} size {sz} -> {len(img)} B: probe at +0x{k:X} => load base {addr - k:08X}')
