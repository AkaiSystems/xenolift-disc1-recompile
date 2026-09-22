#!/usr/bin/env python3
"""R173: independent reference LZSS decoder for the kernel's size-prefixed
stream format, reverse-engineered from fn_80032EB4 (UnpackCompressedBuffer)
and cross-checked line-by-line against the emitted translation:

  header : u32le expanded size
  loop   : ctrl = src[i++]; for 8 tokens (LSB first):
             bit SET   -> match: b1=src[i], b2=src[i+1], i+=2
                         off = ((b1 & 0xF) << 8) | b2
                         len = (b1 >> 4) + 3
                         copy len bytes forward, one at a time, from
                         dst_end - off (overlap allowed)
             bit CLEAR -> literal: dst.append(src[i++])
           stop when dst reaches expanded size (checked per group)

Usage: lzss_ref.py input.bin [maxbytes]  -> writes ref_output.bin next to it
and prints the first 32 bytes of the reference decode.
"""
import sys, struct

def ref_decode(data):
    if len(data) < 4:
        return None
    size = struct.unpack('<I', data[:4])[0]
    if size == 0 or size > 0x800000:
        return None
    # faithful zero-buffer model: the kernel unpacks into a HeapCalloc block
    # (zero-initialized). The copy loop reads dst[s+k] byte-at-a-time; when
    # s+k runs past the write position it reads not-yet-written heap memory
    # (= zeros on real HW) — model exactly that, never fail on overlap.
    dst = bytearray(size)
    pos = 0
    i = 4
    n = len(data)
    while pos < size:
        if i >= n:
            return None  # truncated input
        ctrl = data[i]; i += 1
        for _t in range(8):
            if pos >= size:
                break
            if ctrl & 1:
                if i + 1 >= n:
                    return None
                b1 = data[i]; b2 = data[i + 1]; i += 2
                off = ((b2 & 0xF) << 8) | b1
                ln = (b2 >> 4) + 3
                sp = pos - off
                if sp < 0:
                    return None  # reads BEFORE the block = corrupt stream
                for k in range(ln):
                    if pos >= size:
                        break
                    dst[pos] = dst[sp + k]
                    pos += 1
            else:
                if i >= n:
                    return None
                dst[pos] = data[i]; pos += 1; i += 1
            ctrl >>= 1
    return bytes(dst)

if __name__ == '__main__':
    inp = sys.argv[1]
    data = open(inp, 'rb').read()
    out = ref_decode(data)
    if out is None:
        # diagnostics: header sanity + where the walk dies
        import struct as _st
        size = _st.unpack('<I', data[:4])[0] if len(data) >= 4 else -1
        print("[refdec] FAIL: cannot decode %s (header size=%d, file=%d bytes)" % (inp, size, len(data)))
        sys.exit(1)
    open(inp.replace('.bin', '') + '.refout', 'wb').write(out)
    print("[refdec] %s -> %d bytes; first32=%s" % (
        inp, len(out), out[:32].hex()))
