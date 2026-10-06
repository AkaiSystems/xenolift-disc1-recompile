#!/usr/bin/env python3
"""Per-trial progress: dispatcher state sequence (R670), MainLoop, faults, restarts. usage: statescore.py <dir>..."""
import re,sys,glob
for d in sys.argv[1:]:
    print('==',d); T=dict(n=0,ml=0,field=0,restart=0,faults=0)
    for f in sorted(glob.glob(d+'/trial_*.raw')):
        s=open(f,errors='replace').read()
        bc=re.findall(r'\[bootcam\] R1501 t=(\d+)s (.*)',s)
        kv=dict((k,(int(a),int(b))) for k,a,b in re.findall(r'(\w+)=(\d+)@(\d+)',bc[-1][1])) if bc else {}
        ml=kv.get('MainLoop',(0,0))
        seq=[(int(t),int(st,16)) for t,st in re.findall(r'R670 DISPATCHER entry #\d+ @t=(\d+)s: req=([0-9A-F]+)',s)]
        rs=s.count('fault-walk EXIT converted to guest restart'); fl=len(re.findall(r'\[faultregs\] fault#',s))
        last=max((x for x in re.findall(r'\[fldsec\] #\d+ LBA (\d+) consumed @t=(\d+)s',s)), key=lambda z:int(z[1]), default=None)
        print(f"  {f.split('/')[-1]}: MainLoop={ml[0]}@{ml[1]}s states={' '.join(f'{t}s:{st}' for t,st in seq) or '-'} faultRestarts={rs} faults={fl} lastConsumed={'LBA %s @%ss'%last if last else '-'}")
        T['n']+=1; T['ml']+=ml[0]>0; T['field']+=any(st==1 for _,st in seq); T['restart']+=rs; T['faults']+=fl
    print('  TOTAL',T)
