# Mac verify cycle 1 — finish cadence start

Goal: prove the pinned tree on Mac. **Not** a new FE1C widen.

## Pins
- Branch: `xenolift-clean`
- `source/runtime/runtime.c` SHA-256 (comment-sync): `a6d3279bf56d3d8aab13c35aa08515286fe6dd4db6f79421b6ddbd074940a4ce`
- Behavioral c1252 identity (pre-comment): `096f27debdcdfb5ff92dc4f82e20a705d7dfe0c205d7758899bbbf970d00e36e`
- Gate already: `FE1C == 6u || FE1C == 0u` — **do not re-patch**

## PASS (Hiroshi / Akitoshi)
1. Bridge `HANDSHAKE last_completed=c1252`
2. `[pausestart] R1467A` near seek ~120634
3. Seek advances past 120634
4. Field continues under 120s budget
5. No new HALT; armstart/defib6/VRAM not worse than c1252 when probed

## If stuck (no pausestart)
Investigate in order: wrong door class → 2M-confirm thrash → binary≠SHA → other armstart gate → post-fire non-consumption.  
**Not** another `6||0` OR.

## Mac steps
```bash
# 1) Align tree (pick one)
#    A) work from GitHub clean tree:
#       cd ~/path/to/xenolift-disc1-recompile && git fetch && git checkout xenolift-clean && git pull
#       cd source
#    B) or keep ~/Downloads/xenolift but FORCE runtime.c to match pin above

shasum -a 256 runtime/runtime.c   # must be a6d3279b… if using post-comment tree
# or 096f27de… if still on pure c1252 bytes (also OK for behavior; note which)

# 2) Bridge reset
pkill -TERM -f '[b]ridge-v1-api.py' 2>/dev/null || true
sleep 1
# from directory that contains bridge-v1-api.py (source/ on clean branch)
exec /usr/bin/python3 bridge-v1-api.py
# require visible: HANDSHAKE BASELINE last_completed=c1252

# 3) Budgets
echo 120 > xenolift_budget.txt
export RUN_BUDGET_S=120

# 4) Run
./run.sh
# capture full digest; paste to DIRECTOR / Hiroshi
```

## Digest (3 sentences)
1) grade + c1252 handshake + SHA + binary match  
2) pausestart / seek advance / field continue (FE1C observational)  
3) next: promote / thrash-or-door-class branch / **reapply_OR_forbidden=YES**
