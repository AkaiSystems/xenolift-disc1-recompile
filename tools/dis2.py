#!/usr/bin/env python3
"""Disassemble the stage-2 movie player image (~/Downloads/xenolift/stage2_region.bin at 0x801D3000).
usage: dis2.py <start_hex> <end_hex>"""
import struct, sys, os
sys.path.insert(0, os.path.dirname(__file__))
import dis as D
img = open(os.path.expanduser('~/Downloads/xenolift/stage2_region.bin'), 'rb').read(); base = 0x801D3000
def w(a):
    if base <= a < base + len(img): return struct.unpack_from('<I', img, a - base)[0]
    exe = D.w if hasattr(D, '_orig') else None
    return 0
D.w = w
lo, hi = int(sys.argv[1], 16), int(sys.argv[2], 16)
for a in range(lo, hi, 4): print('%08X %08X %s' % (a, w(a), D.dis(a)))
