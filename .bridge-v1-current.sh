set -u
export LC_ALL=C
cd ~/Downloads/xenolift || { echo C1252-FAILED-no-workdir; exit 0; }

echo "=== C1252: FIX R1470B - revert regressive immediate ladder rescue; census dead-drive gates ==="
PRE_SHA=$(shasum -a 256 runtime/runtime.c | cut -d' ' -f1)
echo "PRE_SHA=$PRE_SHA"
if ps ax | grep -q "[x]enogears_boot"; then echo C1252-REFUSED-LIVE-GAME; exit 0; fi
if [ "$PRE_SHA" != "7edf37a898d40f9c33b51c8b928927a6bf0a2bc77b64aba179d6a16357c6c365" ]; then echo C1252-REFUSED-UNKNOWN-TREE; exit 0; fi

cp runtime/runtime.c runtime/runtime.c.bak_c1252
python3 - <<'PYEOF'
p='runtime/runtime.c'
s=open(p).read()
old='} else if (((cd_seek_lba >= 108884u && cd_seek_lba <= 109160u) || (xl_wall() - r472_chg) >= 1) /* R477/R1470A: immediate in receipted file ladder; retain 1s elsewhere.'
new='} else if ((xl_wall() - r472_chg) >= 1 /* R477/R1470B: reverted immediate ladder rescue after c1251 regression; receipted 1s guard restored.'
marker='R1470B: reverted immediate ladder rescue'
old_n=s.count(old); marker_pre=s.count(marker)
print('PRE_COUNTS old_gate=%d marker=%d r472_chg=%d defib6_tag=%d' %
      (old_n,marker_pre,s.count('r472_chg'),s.count('[defib6] R473 stalled-load COMPLETED')))
assert old_n==1, 'OLD_GATE_NOT_UNIQUE_%d' % old_n
assert marker_pre==0, 'MARKER_PREEXISTS_%d' % marker_pre
assert s.count('[defib6] R473 stalled-load COMPLETED')==1, 'DEFIB6_TAG_NOT_UNIQUE'
out=s.replace(old,new,1)
print('POST_COUNTS old_gate=%d marker=%d r472_chg=%d defib6_tag=%d' %
      (out.count(old),out.count(marker),out.count('r472_chg'),out.count('[defib6] R473 stalled-load COMPLETED')))
assert out.count(old)==old_n-1, 'OLD_GATE_POST_COUNT'
assert out.count(marker)==marker_pre+new.count(marker), 'MARKER_POST_COUNT'
assert out.count('r472_chg')==s.count('r472_chg'), 'IDENTIFIER_COUNT_CHANGED'
assert out.count('{')-s.count('{')==new.count('{')-old.count('{'), 'OPEN_BRACE_DELTA'
assert out.count('}')-s.count('}')==new.count('}')-old.count('}'), 'CLOSE_BRACE_DELTA'
assert out.count('(')-s.count('(')==new.count('(')-old.count('('), 'OPEN_PAREN_DELTA'
assert out.count(')')-s.count(')')==new.count(')')-old.count(')'), 'CLOSE_PAREN_DELTA'
assert out.count('(')-s.count('(')==out.count(')')-s.count(')'), 'PAREN_DELTA_UNBALANCED'
open(p,'w').write(out)
print('SPLICE_OK R1470B receipted 1s guard restored')
PYEOF
if [ $? -ne 0 ]; then cp runtime/runtime.c.bak_c1252 runtime/runtime.c; echo C1252-SPLICE-FAILED-REVERTED; exit 0; fi
POST_SHA=$(shasum -a 256 runtime/runtime.c | cut -d' ' -f1)
echo "POST_SHA=$POST_SHA"
if [ "$POST_SHA" = "$PRE_SHA" ]; then cp runtime/runtime.c.bak_c1252 runtime/runtime.c; echo C1252-REFUSED-NO-TREE-CHANGE; exit 0; fi

echo 120 > xenolift_budget.txt
export RUN_BUDGET_S=120
sync
echo "BUDGET_FILE=$(cat xenolift_budget.txt) RUN_BUDGET_S=$RUN_BUDGET_S"
SECONDS=0
bash ./run.sh > /tmp/c1252_run_stdout.txt 2>&1
RC=$?
echo "RUN rc=$RC SECONDS=$SECONDS"

echo '=R1470B_SOURCE'
grep -n 'R1470B' runtime/runtime.c || true
echo '=DEFIB6_COUNT'
grep -a -c '\[defib6\] R473 stalled-load COMPLETED' run.log || true
grep -a '\[defib6\] R473 stalled-load COMPLETED' run.log | tail -12 || true
echo '=DEAD_DRIVE_POSTURES'
grep -a 'kickterms\|schclr21506\|f5cam\|armstart\|armdec\|zlheal2\|fstrfd\|R1453' run.log | tail -40 || true
echo '=DEEP_OR_LATER'
grep -a '1091[0-6][0-9]\|1206[0-9][0-9]\|2393[0-9][0-9]\|2503[0-9][0-9]\|2508[0-9][0-9]\|\[lzsscam\]\|\[mvpost2\]' run.log | tail -30 || true
echo '=TARGET_GATE_SOURCE_WINDOWS'
python3 - <<'PYEOF'
p='runtime/runtime.c'
lines=open(p).read().splitlines()
tags=('armstart','armdec','zlheal2','fstrfd','R1453')
seen=[]
for i,line in enumerate(lines):
    if any(tag in line for tag in tags):
        lo=max(0,i-5); hi=min(len(lines),i+8)
        key=(lo,hi)
        if key in seen: continue
        seen.append(key)
        print('--- WINDOW %d:%d TAGLINE=%d ---' % (lo+1,hi,i+1))
        for n in range(lo,hi): print('%d:%s' % (n+1,lines[n]))
        if len(seen)>=8: break
PYEOF
echo '=EXIT'
grep -a 'HALT\|erars\|words_exec\|main-return\|watchdog-alarm\|process exit status\|segvdie' run.log | tail -20 || true
echo "=== C1252 DONE ==="
