#!/usr/bin/env python3
"""File-15 progress per trial, from ungoverned [f15] receipts (R1520) + dispatcher states (R670).
usage: f15score.py <dir>...   (one line per trial + totals)"""
import re, sys, glob
DMA = re.compile(r'\[f15\] #\d+ \+(\d+)ms DMA ([0-9A-F]{8}) ([0-9A-F]{8}) ([0-9A-F]{8})')
FRC = re.compile(r'\[f15\] #\d+ \+(\d+)ms FORCE \S+ \S+ \S+ (\S+)')
for d in sys.argv[1:]:
    print('==', d); T = dict(n=0, field=0, armed=0, f15sec=0, f15done=0, beyond=0, r1466b=0, decl=0)
    for f in sorted(glob.glob(d + '/trial_*.raw')):
        s = open(f, errors='replace').read()
        seq = [(int(t), int(st, 16)) for t, st in re.findall(r'R670 DISPATCHER entry #\d+ @t=(\d+)s: req=([0-9A-F]+)', s)]
        armed = '[f15] R1520 ARMED' in s
        lbas = sorted({int(l, 16) for _, dst, n, l in DMA.findall(s) if int(n, 16) == 2048})
        f15 = [l for l in lbas if 108995 <= l <= 109040]
        beyond = [l for l in lbas if l > 109040]
        heals = {}
        for _, why in FRC.findall(s): heals[why] = heals.get(why, 0) + 1
        decl = s.count('[r1521] R1466B DECLINED')
        fld = re.findall(r'\[fldsec\] #\d+ LBA (\d+) consumed @t=(\d+)s', s)
        last = max(fld, key=lambda z: int(z[1])) if fld else None
        print(f"  {f.split('/')[-1]}: states={' '.join(f'{t}s:{st}' for t, st in seq) or '-'} f15armed={int(armed)} "
              f"f15 sectors={len(f15)}/46 maxLBA={max(f15) if f15 else '-'} beyond109040={len(beyond)} "
              f"forces={heals} r1521decl={decl} lastConsumed={'LBA %s@%ss' % last if last else '-'}")
        T['n'] += 1; T['field'] += any(st == 1 for _, st in seq); T['armed'] += armed
        T['f15sec'] += len(f15); T['f15done'] += (len(f15) >= 46); T['beyond'] += bool(beyond)
        T['r1466b'] += heals.get('r1466b-v4-heal', 0); T['decl'] += decl
    print('  TOTAL', T)
