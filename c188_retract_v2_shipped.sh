#!/bin/bash
# c188 RESHIP v2 - R1288 the R502 RETRACTION, the first-fault fix, ONE targeted change.
# v1 tripped MY OWN marker gate at the Mac (latchfix=3 vs my expected 2): I
# pre-verified with an anchored grep (removed-lines only) while the script runs
# plain grep -c (context lines too). The PATCH is UNCHANGED - the Mac sha-verified
# d8dca137 identical - nothing applied, tree intact at R1287. The c135 rule
# extended: compute every gate expectation with the script EXACT command.
# The c184 run: R1284 PASSED IN FULL - zrfB fired at fe1c=1, the
# system-band walk advanced LBA 0->1->3, STATE 0->1 (coordinator
# entered normally, overlay loaded), member 14 installed, game table
# installed, file#18 re-issued natively, retry spike 43->16, the
# screen painted 100 PERCENT (all four regions, first time ever),
# and the pad receipt flipped: ReadControllerButtons entry #245760,
# btn=BFFF START-HELD - the game SEES our injected press.
# THE NEW FIRST-BREAK (pumpcam x3 + mvloop x3 + ftab): file#14 read
# ARMED BUT IDLE - seek=108997, FDF8=125304 armed (game stamped BOTH
# cells), cmd 01 GetStat, act=0, pend=0, data=0/0 - the game polls
# status bit 0x40 which can never set while the drive is idle.
# zrfF is the right composite, wrong band (seek<150 FE04=0 FDF8==2048).
# THE c187 DECODE SETTLED IT: the idxw trail (5 writes, ALL by fn 80019984
# in EARLY boot: 0->96, ->0, ->16, ->0 - the set-dispatch-clear protocol
# around REAL fn_80019ACC(0) calls with idx 6 and 1; ZERO writes in the loop
# era) + the STATIC branch decode (disc1.c L_80031DA8: latch==0 -> r4=0x82;
# fn_80019ACC; latch!=0 -> fn_80031F58, a 4-line iterator advance) + the
# decompilation NAMES fn_80019ACC: RunResidentGameLoop___game_core. THE
# 130-CALL IS THE GAME RESIDENT MAIN LOOP - ITS NORMAL ENTRY WITH MODE ARG
# 0x82, TAKEN EXACTLY WHEN THE LATCH IS CLEAR. R502 (c68-era) HAD THE
# PROTOCOL INVERTED: at every 0x82 call it forced the latch to 1 (next pass
# takes the iterator branch, not the game) AND rewrote the game argument
# 0x82 -> 0 (arg 0 = early-boot dispatch mode reading idx_work, which is 0 -
# THE RESIDENT LOOP NEVER RAN IN ITS OWN MODE). THE 47964-CALL 400/SEC LOOP
# IS R502 MANUFACTURING AN ERROR PASS EVERY ITERATION. R1288: R502 FULLY
# RETRACTED - the block is now a PASSIVE CAMERA ([rlgl], 64+1/4096 cadence,
# touches NOTHING: no arm, no arg rewrite). The game own protocol restored
# exactly. PASS: the rerun loop DIES (fn_80019ACC(130) cadence collapses to
# game-natural), the resident loop runs in mode 0x82, and whatever it blocks
# on next is the NEXT first fault - one at a time. If the game arms its own
# latch and takes a real fault path, the receipts SHOW it: fix that data
# fault, never the protocol. All R1287 cameras stay. zrfG/zrfF parked.
# This script gates on tree sha b23f6552 (the Mac current R1285
# tree), backs up, fetches+applies the sandbox-parsed R1286 camera
# patch with post-apply SHA gate, runs 120s alive-guarded, censuses,
# PNG last. FIXES a latent restore-path bug carried since c183: the
# backup file suffix was stale (never bumped past the c183 cycle)
# while both restore paths read a DIFFERENT, never-created suffix -
# a restore would have failed silently. All three now use the
# current-cycle backup name consistently.
set -u
cd "$HOME/Downloads/xenolift" || exit 1

echo "===PRE188=== identity, tree drift gate (R1287 baseline)"
T=$(shasum -a 256 runtime/runtime.c | cut -d" " -f1)
echo "TREE_SHA=$T"
BASE="e1823d2368edf7e65811ef6a2845671c20a88fc55cd09d92a8d93d621b36a5c5"
if [ "$T" != "$BASE" ]; then
  echo "DRIFT-FAILED: tree is not the receipted R1287 baseline e1823d23 - nothing run"
  exit 0
fi
T=$(shasum -a 256 runtime/runtime.c | cut -d" " -f1)
if [ "$T" != "$BASE" ]; then
  echo "RESTORE-VERIFY-FAILED - nothing run"
  exit 0
fi
echo "BASELINE_VERIFIED"
LC_ALL=C grep -a -o "runtime build R[0-9]*" xenogears_boot | head -1

echo "===PATCH188=== fetch, verify, apply the R1288 retraction patch - marker + post-apply sha gates, FAIL EXPLICIT"
curl -sSL -m 30 -o /tmp/r1288_retract.diff "https://base44.app/api/apps/6aa26c7ce0ac9a5ee05d2b95/files/mp/public/6aa26c7ce0ac9a5ee05d2b95/888f9bbbd_r1288_retract.diff"
echo "CURL_RC=$?"
P=$(shasum -a 256 /tmp/r1288_retract.diff | cut -d" " -f1)
echo "PATCH_SHA=$P"
if [ "$P" != "d8dca13752242c593976e909ced0c06a7742aa3d3ddd7355bf4eef99b9746126" ]; then
  echo "PATCH-VALID-FAILED: sha mismatch - nothing applied, nothing run"
  exit 0
fi
M1=$(grep -c "R1288" /tmp/r1288_retract.diff)
M2=$(grep -c "rlgl" /tmp/r1288_retract.diff)
M3=$(grep -c "latchfix" /tmp/r1288_retract.diff)
M4=$(grep -c "RunResidentGameLoop" /tmp/r1288_retract.diff)
echo "PATCH_MARKERS R1288=$M1 rlgl=$M2 latchfix=$M3 RunResidentGameLoop=$M4"
if [ "$M1" != "3" ] || [ "$M2" != "2" ] || [ "$M3" != "3" ] || [ "$M4" -lt "2" ]; then
  echo "MARKER-FAILED: expected R1288=3 rlgl=2 latchfix=3 RRG>=2 - nothing applied"
  exit 0
fi
cp -p runtime/runtime.c runtime/runtime.c.bak1288
if ! patch -p0 --dry-run runtime/runtime.c < /tmp/r1288_retract.diff; then
  echo "DRYRUN-FAILED: patch does not apply cleanly - nothing changed"
  exit 0
fi
if ! patch -p0 runtime/runtime.c < /tmp/r1288_retract.diff; then
  cp -p runtime/runtime.c.bak1288 runtime/runtime.c
  echo "APPLY-FAILED: restored backup, nothing run"
  exit 0
fi
N=$(shasum -a 256 runtime/runtime.c | cut -d" " -f1)
echo "NEW_SHA=$N"
if [ "$N" != "06092ff20d7f02516df3e895938eea5553b3459c9fd763500470f4800a4bdb13" ]; then
  cp -p runtime/runtime.c.bak1288 runtime/runtime.c
  echo "POST-APPLY-FAILED: patched tree sha mismatch (expected 06092ff2) - restored backup, nothing run"
  exit 0
fi
echo "PATCHED TREE VERIFIED (sandbox-parsed, sha-gated)"

echo "===RUN188=== the 120s receipt run - alive-guarded captures, live-tail correlation"
RUN_BUDGET_S=120 ./run.sh > /tmp/run188.txt 2>&1 &
RUNPID=$!
echo "LAUNCH-WALL $(date +%s)"
sleep 6
if ! kill -0 $RUNPID 2>/dev/null; then
  echo "RUN-DIED-EARLY: compile or launch failed - no captures, no stale artifacts"
  head -8 /tmp/run188.txt
  wait $RUNPID
  echo "RUNSH_RC=$?"
  echo "===END188==="
  exit 0
fi
LC_ALL=C grep -a -o "runtime build R[0-9]*" xenogears_boot | head -1
LV_B="vram_live.bin"
LV_M="vram_live.meta"
SNAP=$(mktemp -d /tmp/xl188.XXXXXX)
if [ -z "$SNAP" ]; then echo "SNAPDIR-FAILED - aborting captures"; else echo "SNAPDIR=$SNAP"; fi
mkdir -p "$SNAP/w50" "$SNAP/w65" "$SNAP/w80" "$SNAP/w95"

waitalive() {
  E=$(( $(date +%s) + $1 ))
  while [ "$(date +%s)" -lt "$E" ]; do
    kill -0 $RUNPID 2>/dev/null || return 1
    sleep 2
  done
  kill -0 $RUNPID 2>/dev/null || return 1
  return 0
}

grab() {
  D="$1"; OFF="$2"
  echo "CAPTURE-$OFF $(date +%s)"
  tail -n 3 run.log 2>&1
  ls -la "$LV_B" "$LV_M" 2>&1
  rm -f "$D/dump.bin" "$D/crop.txt" "$D/wit.bin" "$D/wit.txt" "$D/INVALID"
  TRY=1
  while [ "$TRY" -le 3 ]; do
    if ! cp -p "$LV_B" "$D/dump.bin"; then echo "attempt-$OFF-$TRY: dump copy FAILED - attempt invalidated"; TRY=$((TRY+1)); continue; fi
    if ! cp -p "$LV_M" "$D/crop.txt"; then echo "attempt-$OFF-$TRY: crop copy FAILED - attempt invalidated"; TRY=$((TRY+1)); continue; fi
    sleep 0.3
    if ! cp -p "$LV_B" "$D/wit.bin"; then echo "attempt-$OFF-$TRY: witness dump copy FAILED - attempt invalidated"; TRY=$((TRY+1)); continue; fi
    if ! cp -p "$LV_M" "$D/wit.txt"; then echo "attempt-$OFF-$TRY: witness crop copy FAILED - attempt invalidated"; TRY=$((TRY+1)); continue; fi
    B1=$(shasum -a 256 "$D/dump.bin" | cut -d" " -f1)
    B2=$(shasum -a 256 "$D/wit.bin" | cut -d" " -f1)
    M1=$(shasum -a 256 "$D/crop.txt" | cut -d" " -f1)
    M2=$(shasum -a 256 "$D/wit.txt" | cut -d" " -f1)
    SZ1=$(wc -c < "$D/dump.bin" | tr -d " ")
    SZ2=$(wc -c < "$D/wit.bin" | tr -d " ")
    if [ "$B1" = "$B2" ] && [ "$M1" = "$M2" ] && [ "$SZ1" = "1048576" ] && [ "$SZ2" = "1048576" ]; then
      echo "consistency-$OFF: dump and crop UNCHANGED across witness window, sizes exact - PAIR CONSISTENT try=$TRY"
      return 0
    fi
    echo "consistency-$OFF: attempt $TRY failed - dump_same=$([ "$B1" = "$B2" ] && echo yes || echo no) crop_same=$([ "$M1" = "$M2" ] && echo yes || echo no) sz=$SZ1/$SZ2 - retrying with full verification"
    TRY=$((TRY+1))
  done
  echo "consistency-$OFF: FAILED after 3 verified attempts - CAPTURE INVALIDATED (no render, no transfer)"
  touch "$D/INVALID"
  return 1
}

ALIVE=1
waitalive 44 && grab "$SNAP/w50" "w50" || { ALIVE=0; echo "w50 SKIPPED - run ended early"; touch "$SNAP/w50/INVALID"; }
if [ "$ALIVE" = "1" ]; then waitalive 15 && grab "$SNAP/w65" "w65" || { ALIVE=0; echo "w65 SKIPPED - run ended early"; touch "$SNAP/w65/INVALID"; }; fi
if [ "$ALIVE" = "1" ]; then waitalive 15 && grab "$SNAP/w80" "w80" || { ALIVE=0; echo "w80 SKIPPED - run ended early"; touch "$SNAP/w80/INVALID"; }; fi
if [ "$ALIVE" = "1" ]; then waitalive 15 && grab "$SNAP/w95" "w95" || { ALIVE=0; echo "w95 SKIPPED - run ended early"; touch "$SNAP/w95/INVALID"; }; fi
wait $RUNPID
echo "RUNSH_RC=$?"
head -3 run.log
tail -12 /tmp/run188.txt

echo "===SHOTS188=== render with error retention, verify, preserve"
for W in w50 w65 w80 w95; do
  D="$SNAP/$W"
  rm -f "$D/vram.bin" "$D/vram.meta" "$D/screen.png" "$D/vram.png" "$D/render.txt"
  if [ -f "$D/INVALID" ]; then echo "render-$W SKIPPED - capture invalidated"; continue; fi
  cp -p "$D/dump.bin" "$D/vram.bin"
  cp -p "$D/crop.txt" "$D/vram.meta"
  (cd "$D" && python3 "$HOME/Downloads/xenolift/vramtopng.py" > render.txt 2>&1)
  if [ -f "$D/screen.png" ]; then echo "render-$W OK"; head -4 "$D/render.txt"; else echo "render-$W FAILED"; cat "$D/render.txt"; fi
done
python3 - "$SNAP" <<'PYEOF'
import os, struct, sys
snap = sys.argv[1]
for tag in ["w50", "w65", "w80", "w95"]:
    d = os.path.join(snap, tag)
    if os.path.exists(os.path.join(d, "INVALID")):
        print("[shot%s] INVALID - capture failed consistency, excluded from all evidence" % tag)
        continue
    try:
        v = open(os.path.join(d, "dump.bin"), "rb").read()
        m = open(os.path.join(d, "crop.txt")).read().split()
        dx, dy, dw, dh = (int(x) for x in m[:4])
        ok = len(v) == 1048576 and 0 <= dx <= 1023 and 0 <= dy <= 511 and dw >= 16 and dh >= 16
        nz = 0
        for i in range(0, len(v) // 2):
            if struct.unpack_from("<H", v, i * 2)[0]:
                nz += 1
        print("[shot%s] %s disp %ux%u@(%u,%u) vram_nz=%d/%d raw=%dB" % (tag, "VERIFIED" if ok else "BAD", dw, dh, dx, dy, nz, len(v) // 2, len(v)))
    except Exception as e:
        print("[shot%s] ERR %s" % (tag, e))
PYEOF
for W in w50 w65 w80 w95; do
  D="$SNAP/$W"
  if [ -f "$D/screen.png" ]; then cp -p "$D/screen.png" "shot_$W.png"; cp -p "$D/dump.bin" "shot_$W.raw.bin"; cp -p "$D/crop.txt" "shot_$W.cfg.txt"; fi
done
ls -la shot_w50.png shot_w65.png shot_w80.png shot_w95.png screen.png 2>&1
shasum -a 256 shot_w50.png shot_w65.png shot_w80.png shot_w95.png 2>&1

echo "===STORM188=== THE GOVERNOR VERDICT - the storm must stay tamed (9.7MB class last run)"
grep -c "tagcap" run.log
echo "--- the per-tag crossover notices"
grep -n "tagcap" run.log | head -12
wc -c run.log.raw run.log.d run.log 2>/dev/null
if [ -f run.log.raw ]; then
  echo "--- top 24 tags by BYTES in the full raw stream"
  LC_ALL=C awk "{t=substr(\$0,1,index(\$0,\"]\")); b[t]+=length(\$0)+1} END {for (k in b) printf \"%12d %s\", b[k], k}" run.log.raw | sort -rn | head -24
  echo "--- top 24 tags by LINES in the full raw stream"
  LC_ALL=C grep -o "^\[[a-z0-9-]*\]" run.log.raw | sort | uniq -c | sort -rn | head -24
else
  echo "run.log.raw ABSENT - census run.log instead"
  LC_ALL=C awk "{t=substr(\$0,1,index(\$0,\"]\")); b[t]+=length(\$0)+1} END {for (k in b) printf \"%12d %s\", b[k], k}" run.log | sort -rn | head -24
fi
echo "===RLGL188=== THE RESIDENT LOOP, NATIVE AT LAST - R502 retracted, passive camera"
grep -c "rlgl" run.log
grep -n "rlgl" run.log | head -24
echo "--- THE RETRACTION VERDICT: R502 prints must be GONE (0 = the heal is out)"
grep -c "latchfix" run.log
grep -c "latchw" run.log
echo "--- THE RERUN-LOOP CADAENCE: fn_80019ACC(130) calls, first 16 + count"
grep -c "fn_80019ACC(130)" run.log
grep -n "fn_80019ACC(130)" run.log | head -16
echo "--- the game own latch protocol now (watcher): arms and clears, no runtime forcing"
grep -c "latchhw" run.log
grep -n "latchhw" run.log | head -24
echo "--- the real dispatches (idx 1+ with idx_work set)"
grep -n "idx_work=96\|idx_work=16\|idx=1 \|idx=6 " run.log | head -16
echo "===IDXW188=== the step-walker trail - who writes idx_work now"
grep -c "idxw" run.log
grep -n "idxw" run.log | head -12
grep -c "logbudget" run.log
echo "===ZRFG188=== the parked file-band guard"
grep -c "zrfG" run.log
echo "===ZRFB188=== the widened zrfB door - prior-era fires"
grep -c "zrfB.*fire #" run.log
echo "===DECL188=== the decline receipts"
grep -c "defib-decline" run.log
echo "===DRV188=== the R967 DRV lines"
grep -n "DRV act" run.log | head -6
echo "===ZRFF188=== the zrfF system-band guard"
grep -c "zrfF" run.log
echo "===WEDGE188=== the wedge family"
grep -c "STUCK" run.log
grep -n "STUCK" run.log | head -6
grep -c "alarmguard" run.log
echo "===FETCH188=== the fetch trace"
grep -n "fetchcam" run.log | tail -10
grep -n "sector LBA 0 " run.log | head -6
grep -n "fldsec" run.log | tail -8
echo "===FILE188=== the file chain - carry, epochs, archive sync"
grep -n "defib6" run.log | tail -8
grep -n "boot main entered" run.log
grep -n "newmod" run.log | tail -6
grep -n "asyctx" run.log | tail -6
echo "===ADV188=== THE ADVANCE CENSUS - states, dispatcher, pad, screen"
grep -n "fn_80019ACC" run.log | tail -6
grep -c "fn_80019ACC" run.log
grep -n "statetbl" run.log | tail -4
echo "===SCENE188=== the scene census - state machine, GPU, input"
grep -n "statetbl" run.log | tail -6
grep -n -E "gpufin|gpucls" run.log | tail -4
grep -c "gpucmd" run.log
grep -c "padrdw" run.log
grep -n "nonblank" run.log | tail -6
grep -c "mvloop" run.log
grep -n "mvloop" run.log | tail -3
echo "===ALARM188=== the alarm-deferral + FE1C/FE04 writer trails"
grep -c "alarmguard" run.log
grep -n "alarmguard" run.log | tail -4
echo "--- Module-6 validation spike:"
grep -c "fn_80019ACC" run.log
grep -n "fn_80019ACC" run.log | tail -4
echo "--- FE04 writer trail near the wedge:"
grep -n "0x8004FE04" run.log | tail -12
echo "--- FE1C writer trail:"
grep -n "chg. FE1C" run.log | tail -8
echo "--- cdw02 tail:"
grep -n "cdw02" run.log | tail -6
grep -c "pendclr" run.log
echo "===WALL188=== the wall census"
grep -c "NULL-trap" run.log
grep -c "AbortOnGameFault" run.log
echo "===PROV188=== provenance"
LC_ALL=C grep -a -o "runtime build R[0-9]*" run.log | head -1
wc -l run.log
cp -p run.log run.log.c188
shasum -a 256 run.log run.log.c188 runtime/runtime.c
echo "===PNG188=== THE IMAGE TRANSFER - small renders, sha-verified, budget-bounded, LAST so the census always lands"
python3 - "$SNAP" <<'PYEOF'
import base64, hashlib, os, struct, sys, zlib
snap = sys.argv[1]

def wpng(path, w, h, rows):
    raw = b"".join(b"\x00" + r for r in rows)
    def chunk(t, d):
        c = zlib.crc32(t + d) & 0xFFFFFFFF
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", c)
    hdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", hdr) + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))

def small(src_bin, src_meta, out, OW=112, OH=105):
    v = open(src_bin, "rb").read()
    m = open(src_meta).read().split()
    dx, dy, dw, dh = (int(x) for x in m[:4])
    rows = []
    for oy in range(OH):
        row = bytearray()
        for ox in range(OW):
            sx = min(1023, dx + (dw * ox) // OW)
            sy = min(511, dy + (dh * oy) // OH)
            p = struct.unpack_from("<H", v, (sy * 1024 + sx) * 2)[0]
            row += bytes(((p & 31) * 8, ((p >> 5) & 31) * 8, ((p >> 10) & 31) * 8))
        rows.append(bytes(row))
    wpng(out, OW, OH, rows)

items = []
for tag in ["w50", "w65", "w80", "w95"]:
    d = os.path.join(snap, tag)
    if os.path.exists(os.path.join(d, "INVALID")):
        print("[png-%s] SKIPPED - capture invalidated" % tag)
        continue
    out = os.path.join(d, "small.png")
    try:
        small(os.path.join(d, "dump.bin"), os.path.join(d, "crop.txt"), out)
        items.append((tag, out))
    except Exception as e:
        print("[png-%s] RENDER-ERR %s" % (tag, e))
try:
    small("vram.bin", "vram.meta", os.path.join(snap, "final_small.png"))
    items.append(("wfinal", os.path.join(snap, "final_small.png")))
except Exception as e:
    print("[png-wfinal] RENDER-ERR %s" % e)

BUDGET = 24000
total = 0
for tag, path in items:
    data = open(path, "rb").read()
    h = hashlib.sha256(data).hexdigest()
    b = base64.b64encode(data).decode()
    if total + len(b) > BUDGET:
        print("[png-%s] SKIPPED - transfer budget %d exceeded - sha256=%s bytes=%d (file preserved in tree)" % (tag, BUDGET, h, len(data)))
        continue
    total += len(b)
    print("[png-%s] sha256=%s bytes=%d b64=%d" % (tag, h, len(data), len(b)))
    print("[b64-%s-begin]" % tag)
    for i in range(0, len(b), 100):
        print(b[i:i+100])
    print("[b64-%s-end]" % tag)
print("[png-transfer] total_b64=%d budget=%d images=%d" % (total, BUDGET, len(items)))
PYEOF

echo "===END188==="
