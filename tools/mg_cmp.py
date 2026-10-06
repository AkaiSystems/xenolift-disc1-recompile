#!/usr/bin/env python3
"""Compare mangleguard A/B trials. usage: mg_cmp.py <trial_dir | trial_N.raw>...  (a dir reads <dir>/trial_1.raw + .stdout)
Per trial: retire mask, executed binary, last @t, R670 dispatcher sequence (req@t), R709 restart steps,
exit status, and the final [mgcensus] totals (dropped when ACTIVE, would-drop when RETIRED)."""
import re, sys, os

def one(d):
    if d.endswith('.raw'):
        raw = d; so = d[:-4] + '.stdout'; d = os.path.dirname(d) + '/' + os.path.basename(d)[:-4].replace('trial_', 't')
    else:
        raw = os.path.join(d, 'trial_1.raw'); so = os.path.join(d, 'trial_1.stdout')
    if not os.path.exists(raw): return None
    txt = open(raw, errors='replace').read()
    sotxt = open(so, errors='replace').read() if os.path.exists(so) else ''
    m = re.search(r'\[mgg\] XENOLIFT_MG_RETIRE=(\d+)', txt)
    b = re.search(r'executed-binary (\S+) sha256=([0-9a-f]{10})', sotxt)
    ts = [int(x) for x in re.findall(r'@t=(\d+)s', txt)]
    disp = re.findall(r'R670 DISPATCHER entry #\d+ @t=(\d+)s: req=([0-9A-F]+)', txt)
    rst = re.findall(r'\[restart\] R709 epoch=\d+ t=(\d+)s', txt)
    ex = re.search(r'\[rungasp\] R806 process exit status=(\d+)', txt)
    cen = {}
    for g, tot, mode in re.findall(r'\[mgcensus\] \S+ @t=\d+s (\S+) total=(\d+) spill=\d+ inloop=\d(?: (\S+))?', txt):
        cen[g] = (int(tot), mode or 'ACTIVE')
    return dict(dir='/'.join(d.rstrip('/').split('/')[-2:]) if d.count('/') and re.search(r'/t\d+$', d) else os.path.basename(d.rstrip('/')), mask=m.group(1) if m else '?',
                bin='%s:%s' % (b.group(1)[-6:], b.group(2)) if b else '?', tmax=max(ts) if ts else -1,
                disp=' '.join('%d@%s' % (int(r, 16), t) for t, r in disp), restarts=len(rst),
                exit=ex.group(1) if ex else '?',
                census=' '.join('%s=%d%s' % (g, n, '*' if md.startswith('RETIRED') else '') for g, (n, md) in sorted(cen.items())))

rows = [r for r in (one(d) for d in sys.argv[1:]) if r]
for r in rows:
    print('%-10s mask=%-2s bin=%-18s tmax=%-4d exit=%-4s restarts=%d disp=[%s]  census: %s' % (
        r['dir'], r['mask'], r['bin'], r['tmax'], r['exit'], r['restarts'], r['disp'], r['census']))
print('(census: * = RETIRED, count is would-drop; otherwise dropped)')
