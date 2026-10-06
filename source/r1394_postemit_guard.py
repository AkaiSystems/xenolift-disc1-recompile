# R1394 (c504) post-emit patcher: re-apply the dispatch guard splice to a
# freshly emitted disc1.c (the R1202 pattern: idempotent, self-contained).
s = open('disc1.c').read()
anchor = 'void xenolift_dispatch(uint32_t pc)' + chr(10) + '{' + chr(10)
splice = '    if (r1394_dispatch_guard(pc)) { return; }' + chr(10)
if 'r1394_dispatch_guard' in s:
    print('[emit] R1394 dispatch guard already present')
elif anchor in s:
    s = s.replace(anchor, anchor + splice, 1)
    open('disc1.c', 'w').write(s)
    print('[emit] R1394 dispatch guard APPLIED (post-emit)')
else:
    print('[emit] R1394 ANCHOR MISSING (dispatch fn not found) - check manually')
# R1620: file-17 menu overlay (linked at 0x801C5000) - the emitter compiled this window from zero-filled
# RAM, so the kernel's direct jal 801C62A8 (menu switch 0x8001C4F0) ran NOPs that fell through into
# garbage at 0x801D0000 and wrecked sp. Each generated function in 0x801C5000..0x801D3000 now asks the
# R1610 guard first; it interprets the real code only while file 17 is resident (header words at 0x801C5000).
import re
s = open('disc1.c').read()
pat = re.compile(r'(static void xenolift_fn_(801C[5-9A-F][0-9A-F]{3}|801D[0-2][0-9A-F]{3})(?:_[A-Za-z0-9_]+)?\(void\)\n\{\nXTRACE\(0x[0-9A-F]+\);\n)')
n = 0
def rep(m):
    global n
    n += 1
    return m.group(1) + 'if (r1394_dispatch_guard(0x%su)) return; /* R1620 */\n' % m.group(2)
if '/* R1620 */' in s:
    print('[emit] R1620 file-17 window guards already present')
else:
    s = pat.sub(rep, s)
    open('disc1.c', 'w').write(s)
    print('[emit] R1620 file-17 window guards APPLIED to %d functions' % n)
