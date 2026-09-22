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
