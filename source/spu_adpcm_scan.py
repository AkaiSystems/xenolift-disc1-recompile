#!/usr/bin/env python3
"""SPU RAM ADPCM sample-header scanner (R141).

Scans spu_ram.bin (512KB SPU RAM snapshot) for PS1 SPU-ADPCM block
structure. Each block is 16 bytes:
  [0]  shift (bits 0-3, valid 0-12), filter (bits 4-6, valid 0-4)
  [1]  flags: bit0 loop-end, bit1 loop-repeat, bit2 loop-start;
       bits 3-7 must be 0 (invalid => not ADPCM)
  [2-15] 7 sample bytes (14 nibbles)

Usage: spu_adpcm_scan.py spu_ram.bin [max_report]
"""
import sys

def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "spu_ram.bin"
    maxrep = int(sys.argv[2]) if len(sys.argv) > 2 else 16
    data = open(path, "rb").read()
    n = len(data) // 16
    valid = [False] * n
    for i in range(n):
        b0, b1 = data[i*16], data[i*16+1]
        filt = (b0 >> 4) & 7
        shift = b0 & 0xF
        if filt <= 4 and (b1 & 0xF8) == 0 and shift <= 12:
            if not (b0 == 0 and b1 == 0):  # all-zero words = empty RAM
                valid[i] = True
    # contiguous runs (sample streams)
    runs = []
    i = 0
    while i < n:
        if valid[i]:
            j = i
            while j + 1 < n and valid[j+1]:
                j += 1
            runs.append((i, j))
            i = j + 1
        else:
            i += 1
    vtot = sum(1 for v in valid if v)
    print(f"[adpcm] scanned {n} 16-byte blocks; {vtot} ADPCM-valid; {len(runs)} contiguous streams")
    # loop-flag stats
    lstart = lend = 0
    for i in range(n):
        if valid[i]:
            b1 = data[i*16+1]
            if b1 & 4: lstart += 1
            if b1 & 1: lend += 1
    print(f"[adpcm] loop-start flags: {lstart}, loop-end flags: {lend}")
    shown = 0
    for (a, b) in runs:
        if shown >= maxrep: break
        blocks = b - a + 1
        b0, b1 = data[a*16], data[a*16+1]
        print(f"[adpcm] stream @0x{a*16:05X} len {blocks} blk ({blocks*16}B) "
              f"hdr shift={b0&0xF} filt={(b0>>4)&7} flags={b1&7}")
        shown += 1
    if not runs:
        print("[adpcm] no ADPCM streams (sound bank not yet loaded in RAM?)")
    # known region check: the driver's null-sample mute loop
    m = data[0x1000:0x1010]
    if m == bytes([0x07]) * 16:
        print("[adpcm] null-sample mute loop confirmed @0x1000 (driver init, 1-block silent loop)")

if __name__ == "__main__":
    main()
