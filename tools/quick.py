#!/usr/bin/env python3
"""One-shot summary of a quick run. usage: quick.py <trial.raw>"""
import re, sys
s = open(sys.argv[1], errors='replace').read()
st = re.findall(r'R670 DISPATCHER entry #\d+ @t=(\d+)s: req=([0-9A-F]+)', s)
print('states:', ' '.join(f'{t}s:{int(x,16)}' for t, x in st) or '-')
cnt = lambda p: len(re.findall(p, s))
print('abort=%d faults=%d R807=%d interpStop=%d r1521=%d r1526=%d r1527=%d R1384=%d' % (
    cnt(r'AbortOnGameFault code'), cnt(r'\[faultregs\] fault#'), cnt(r'R807 unresolved-jump'),
    cnt(r'R1394 UNSUPPORTED|interpreter FAIL'), cnt(r'\[r1521\]'), cnt(r'\[r1526\]'), cnt(r'\[r1527\]'), cnt(r'\[f15arm\] R1384')))
for m in re.findall(r'AbortOnGameFault code=\d+ caller=0x[0-9A-F]+', s)[:2]: print('  ', m)
for m in re.findall(r'\[ovlint\] R1394 UNSUPPORTED[^\n]*', s)[:2]: print('  ', m[:150])
co = re.findall(r'\[callout\] R1523 #(\d+) -> ([0-9A-F]{8}) from ([0-9A-F]{8}) a0=([0-9A-F]{8}) a1=([0-9A-F]{8})[^\n]*entry=([0-9A-F]{8})', s)
print('callouts=%d' % len(co), 'last:', ' | '.join(f'#{n}->{t} a0={a0} ({e})' for n, t, f, a0, a1, e in co[-5:]))
g = re.findall(r'\[gpu\] R694 live: gp0_words=(\d+) blits=(\d+) other=(\d+) dma2_sends=(\d+)', s)
if g: print('gpu: gp0_words=%s blits=%s dma2_sends=%s' % (g[-1][0], g[-1][1], g[-1][3]))
lb = [int(x) for x in re.findall(r'\[fldsec\] #\d+ LBA (\d+) consumed', s)]
print('maxLBA consumed:', max(lb) if lb else '-', '| f15 sectors (108995-109040) seen in DMA:',
      len({int(a, 16) & 0xFFFFF for m, n, a in re.findall(r'\[f15\] #\d+ \+\d+ms DMA ([0-9A-F]{8}) ([0-9A-F]{8}) ([0-9A-F]{8})', s) if int(n, 16) == 2048 and 108995 <= (int(a, 16) & 0xFFFFF) <= 109040}))
tc = re.findall(r'\[termcam\] #\d+ (t=\d+s seek=\d+ FE04=\d+ FDF8=\d+)[^\n]*?cmd=(\w+) act=(\d) ld=(\d) pend=(\d)[^\n]*fn=([0-9A-F]{8})', s)
for t in tc[-2:]: print('termcam:', t[0], 'cmd=%s act=%s ld=%s pend=%s fn=%s' % t[1:])
