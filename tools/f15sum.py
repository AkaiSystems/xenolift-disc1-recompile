#!/usr/bin/env python3
"""Summarize R1520 [f15] receipts: per trial, the ordered CMD/DMA/FORCE/FDF8 timeline, compressed.
usage: f15sum.py <trial.raw> [max_lines]"""
import re, sys, collections
f = sys.argv[1]; mx = int(sys.argv[2]) if len(sys.argv) > 2 else 400
pat = re.compile(r'\[f15\] #(\d+) \+(\d+)ms (\S+) ([0-9A-F]{8}) ([0-9A-F]{8}) ([0-9A-F]{8}) (\S+) \| seek=(\d+) FE04=(\d+) FDF8=(\d+) FE08=([0-9A-F]{8}) FE1C=(\d+) FE34=(-?\d+) pend=(\d+) sched=(\d+) act=(\d+) ld=(\d+) fifo=(\d+)/(\d+) fn=([0-9A-F]{8}) ra=([0-9A-F]{8}) d=(-?\d+)')
CMD = {0x01:'GetStat',0x02:'Setloc',0x03:'Play',0x06:'ReadN',0x07:'MotorOn',0x08:'Stop',0x09:'Pause',0x0A:'Init',0x0B:'Mute',0x0C:'Demute',0x0D:'SetFilter',0x0E:'Setmode',0x13:'GetTN',0x15:'SeekL',0x1B:'ReadS'}
ev = []
for line in open(f, errors='replace'):
    if '[f15] R1520 ARMED' in line: print(line.strip()); continue
    m = pat.search(line)
    if m: ev.append(m.groups())
print(f"{len(ev)} events")
kinds = collections.Counter(e[2] for e in ev); print('kinds:', dict(kinds))
whys = collections.Counter(e[6] for e in ev if e[2] == 'FORCE'); print('FORCE by heal:', dict(whys))
rt = collections.Counter((e[2], e[20]) for e in ev if e[2].startswith('FDF8w')); print('FDF8 writers (kind, ra):', dict(rt.most_common(8)))
prev = None; rep = 0; out = 0
for e in ev:
    n, ms, k, a1, a2, a3, why, seek, fe04, f8, fe08, fe1c, fe34, pend, sched, act, ld, fp, fn_, fnc, ra, d = e
    if k == 'CMD':
        c = int(a1, 16); desc = f"CMD {CMD.get(c, hex(c))}" + (f" ->LBA {int(a2,16)}" if c == 2 else '') + (f" ({why})" if why != '-' else '')
    elif k == 'DMA':
        desc = f"DMA {int(a2,16)}B -> {a1} (LBA {int(a3,16)})"
    elif k == 'FORCE':
        desc = f"FORCE INT1 by {why}"
    else:
        desc = f"{k} {int(a1,16)}->{int(a2,16)} line={int(a3,16)}"
    key = (desc, seek, f8, fe08)
    if key == prev: rep += 1; continue
    if rep: print(f"      ... x{rep} more"); rep = 0
    prev = key
    print(f"+{int(ms):>6}ms {desc:<44} seek={seek} FE04={fe04} FDF8={f8} FE08={fe08} FE1C={fe1c} FE34={fe34} p{pend}s{sched}a{act}l{ld} fn={fnc} ra={ra}")
    out += 1
    if out >= mx: print('... truncated'); break
if rep: print(f"      ... x{rep} more")
