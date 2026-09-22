#!/bin/bash
# c184 FIX CYCLE - R1284, the ONE-TERM zrfB widen (sgarm precedent).
# The c183 run: the decline cameras came back EMPTY - the c182 file#2
# tail wedge never recurred. Instead the BEST RUN EVER: the game is
# ALIVE in a live menu/render loop - 2.7 BILLION vram writes, 8.6M
# rects, double-buffer display flipping, 27 percent of VRAM filled,
# the pad polled, 215 mvloop prints across many loop sites, four
# epochs, wall dead. THE STICK, receipted twice: the CD wait posture
# seek=0 cmd 09 FDF8=0 pend=0 A22C=3 sched=1 FE1C=1 frozen w50-fuse,
# and the [chg] trail FE1C 0006->0001 at fn 0x80040FCC. zrfB (the door
# that served this exact seek=0 family in c175) is in-tree but silent:
# its FE1C ladder (0/6/7/10/11) never covered state 1. R1284 adds
# fe1cA==1u to the ladder - ONE receipted term, nothing else changes.
# PASS = zrfB fires at fe1c=1, FDF8 2048->0, the menu advances (new
# request, new state-table activity, new screen content, or the
# fn_80019ACC retry spike stops). REVERT if fires with no advance.
# This script gates on tree sha 5e6652eb (the Mac current R1283 tree),
# backs up, fetches+applies the sandbox-parsed R1284 patch with post-
# apply SHA gate, runs 120s alive-guarded, censuses, PNG last.
set -u
cd "$HOME/Downloads/xenolift" || exit 1

echo "===PRE184=== identity, tree drift gate (R1283 baseline)"
T=$(shasum -a 256 runtime/runtime.c | cut -d" " -f1)
echo "TREE_SHA=$T"
BASE="5e6652eb109642de461b652a08cbe971763ab458dfa697ccf380ee86a0e6553b"
if [ "$T" != "$BASE" ]; then
  echo "DRIFT-FAILED: tree is not the receipted R1283 baseline 5e6652eb - nothing run"
  exit 0
fi
T=$(shasum -a 256 runtime/runtime.c | cut -d" " -f1)
if [ "$T" != "$BASE" ]; then
  echo "RESTORE-VERIFY-FAILED - nothing run"
  exit 0
fi
echo "BASELINE_VERIFIED"
LC_ALL=C grep -a -o "runtime build R[0-9]*" xenogears_boot | head -1

echo "===PATCH184=== fetch, verify, apply the R1284 one-term patch - marker + post-apply sha gates, FAIL EXPLICIT"
curl -sSL -m 30 -o /tmp/r1284_zrfb_fe1c1.diff "https://base44.app/api/apps/6aa26c7ce0ac9a5ee05d2b95/files/mp/public/6aa26c7ce0ac9a5ee05d2b95/7f8ec9051_r1284_zrfb_fe1c1.diff"
echo "CURL_RC=$?"
P=$(shasum -a 256 /tmp/r1284_zrfb_fe1c1.diff | cut -d" " -f1)
echo "PATCH_SHA=$P"
if [ "$P" != "391fbcf96fbf23f7173633a598a7a4b5159c69e40d53285d9307b348aac8879b" ]; then
  echo "PATCH-VALID-FAILED: sha mismatch - nothing applied, nothing run"
  exit 0
fi
M1=$(grep -c "R1284" /tmp/r1284_zrfb_fe1c1.diff)
M2=$(grep -c "fe1cA == 1u" /tmp/r1284_zrfb_fe1c1.diff)
echo "PATCH_MARKERS R1284=$M1 ladder1=$M2"
if [ "$M1" != "2" ] || [ "$M2" != "1" ]; then
  echo "MARKER-FAILED: expected R1284=2 ladder1=1 - nothing applied"
  exit 0
fi
cp -p runtime/runtime.c runtime/runtime.c.bak1282
if ! patch -p0 --dry-run runtime/runtime.c < /tmp/r1284_zrfb_fe1c1.diff; then
  echo "DRYRUN-FAILED: patch does not apply cleanly - nothing changed"
  exit 0
fi
if ! patch -p0 runtime/runtime.c < /tmp/r1284_zrfb_fe1c1.diff; then
  cp -p runtime/runtime.c.bak1284 runtime/runtime.c
  echo "APPLY-FAILED: restored backup, nothing run"
  exit 0
fi
N=$(shasum -a 256 runtime/runtime.c | cut -d" " -f1)
echo "NEW_SHA=$N"
if [ "$N" != "a2d268c3ae1fcbb1312b632354da258b5870b2ffe53228b0864fe2d495c861cb" ]; then
  cp -p runtime/runtime.c.bak1284 runtime/runtime.c
  echo "POST-APPLY-FAILED: patched tree sha mismatch (expected a2d268c3) - restored backup, nothing run"
  exit 0
fi
echo "PATCHED TREE VERIFIED (sandbox-parsed, sha-gated)"

echo "===RUN184=== the 120s verification run - alive-guarded captures, live-tail correlation"
RUN_BUDGET_S=120 ./run.sh > /tmp/run184.txt 2>&1 &
RUNPID=$!
echo "LAUNCH-WALL $(date +%s)"
sleep 6
if ! kill -0 $RUNPID 2>/dev/null; then
  echo "RUN-DIED-EARLY: compile or launch failed - no captures, no stale artifacts"
  head -8 /tmp/run184.txt
  wait $RUNPID
  echo "RUNSH_RC=$?"
  echo "===END184==="
  exit 0
fi
LC_ALL=C grep -a -o "runtime build R[0-9]*" xenogears_boot | head -1
LV_B="vram_live.bin"
LV_M="vram_live.meta"
SNAP=$(mktemp -d /tmp/xl184.XXXXXX)
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
tail -12 /tmp/run184.txt

echo "===SHOTS184=== render with error retention, verify, preserve"
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

echo "===ZRFB184=== THE WIDENED DOOR - fires at the fe1c=1 posture, consumption, advance"
grep -c "zrfB.*fire #" run.log
grep -n "zrfB" run.log | head -16
echo "===DECL184=== the decline receipts - still watching the file-band freeze"
grep -c "defib-decline" run.log
echo "===DRV184=== the R967 DRV lines"
grep -n "DRV act" run.log | head -6
echo "===ZRFF184=== the parked zrfF guard"
grep -c "zrfF" run.log
echo "===WEDGE184=== the wedge family"
grep -c "STUCK" run.log
grep -n "STUCK" run.log | head -6
grep -c "alarmguard" run.log
echo "===FETCH184=== the fetch trace"
grep -n "fetchcam" run.log | tail -10
grep -n "sector LBA 0 " run.log | head -6
grep -n "fldsec" run.log | tail -8
echo "===FILE184=== the file chain - carry, epochs, archive sync"
grep -n "defib6" run.log | tail -8
grep -n "boot main entered" run.log
grep -n "newmod" run.log | tail -6
grep -n "asyctx" run.log | tail -6
echo "===ADV184=== THE ADVANCE CENSUS - did the menu move"
grep -n "fn_80019ACC" run.log | tail -6
grep -c "fn_80019ACC" run.log
grep -n "statetbl" run.log | tail -4
echo "===SCENE184=== the scene census - state machine, GPU, input"
grep -n "statetbl" run.log | tail -6
grep -n -E "gpufin|gpucls" run.log | tail -4
grep -c "gpucmd" run.log
grep -c "padrdw" run.log
grep -n "nonblank" run.log | tail -6
grep -c "mvloop" run.log
grep -n "mvloop" run.log | tail -3
echo "===ALARM184=== the alarm-deferral + FE1C/FE04 writer trails"
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
echo "===WALL184=== the wall census"
grep -c "NULL-trap" run.log
grep -c "AbortOnGameFault" run.log
echo "===PROV184=== provenance"
LC_ALL=C grep -a -o "runtime build R[0-9]*" run.log | head -1
wc -l run.log
cp -p run.log run.log.c184
shasum -a 256 run.log run.log.c184 runtime/runtime.c
echo "===PNG184=== THE IMAGE TRANSFER - small renders, sha-verified, budget-bounded, LAST so the census always lands"
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

echo "===END184==="
