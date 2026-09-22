#!/bin/bash
# c191 THE FILE-BAND A22C-SITE SERVE - R1290 (zrfG2), ONE targeted
# change: the zrfG composite (c184-approved, in-tree at the cold status
# site, 0 fires) moved to the HOT A22C site (zrfB fired 8x there this run).
# THE c190 VERDICT: 0x0D answered (11 pops, FE1C advanced, no fix needed);
# STATE 1 REACHED AND HELD (g_CurGameState=1, coordinator active, overlay
# loaded); SCREEN PAINTED 100 PERCENT; member 14 installed; and the game
# wedged ALIVE in state 1 at the file#14 armed-idle posture: seek=108997,
# FDF8=125304 armed, FE04=0x1A985 == seek (the game own LBA stamp, R350
# provenance), cmd 01, act=0, pend=0, A22C=4, data=0/0, w50->fuse.
# zrfG2: same-poll cd_data_load + cd_read_active=1 so 0x40 computes true
# on THIS poll, no INT forge, no dispatch, 65536-poll stuck confirm,
# budget 12, partition guard cd_data_n<2048. PASS per the c184 criteria:
# the fire serves the sector, the game drain consumes FDF8 below 125304,
# forward execution (new LBA, state activity, screen change). REVERT if
# fire with zero consumption. Follow-on: defib6 (band covers 108997) may
# take over once act=1 - let the receipts decide.
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

echo "===PRE191=== identity, tree drift gate (R1289 baseline)"
T=$(shasum -a 256 runtime/runtime.c | cut -d" " -f1)
echo "TREE_SHA=$T"
BASE="71b7f98e357d0ee9362517f44af357319c45b8b45ae3e1397ccee7da2cca308c"
if [ "$T" != "$BASE" ]; then
  echo "DRIFT-FAILED: tree is not the receipted R1289 baseline 71b7f98e - nothing run"
  exit 0
fi
T=$(shasum -a 256 runtime/runtime.c | cut -d" " -f1)
if [ "$T" != "$BASE" ]; then
  echo "RESTORE-VERIFY-FAILED - nothing run"
  exit 0
fi
echo "BASELINE_VERIFIED"
LC_ALL=C grep -a -o "runtime build R[0-9]*" xenogears_boot | head -1

echo "===PATCH191=== fetch, verify, apply the R1290 file-band serve patch - marker + post-apply sha gates, FAIL EXPLICIT"
curl -sSL -m 30 -o /tmp/r1290_zrfg2.diff "https://base44.app/api/apps/6aa26c7ce0ac9a5ee05d2b95/files/mp/public/6aa26c7ce0ac9a5ee05d2b95/893822eaf_r1290_zrfg2.diff"
echo "CURL_RC=$?"
P=$(shasum -a 256 /tmp/r1290_zrfg2.diff | cut -d" " -f1)
echo "PATCH_SHA=$P"
if [ "$P" != "1e3c834f17eb88ddb7aab10d070a6dac58894615bd0b60c9813f723f9260cc27" ]; then
  echo "PATCH-VALID-FAILED: sha mismatch - nothing applied, nothing run"
  exit 0
fi
M1=$(grep -c "R1290" /tmp/r1290_zrfg2.diff)
M2=$(grep -c "zrfG2" /tmp/r1290_zrfg2.diff)
M3=$(grep -c "A22C-site" /tmp/r1290_zrfg2.diff)
M4=$(grep -c "file-band" /tmp/r1290_zrfg2.diff)
echo "PATCH_MARKERS R1290=$M1 zrfG2=$M2 A22C-site=$M3 file-band=$M4"
if [ "$M1" != "3" ] || [ "$M2" != "4" ] || [ "$M3" != "3" ] || [ "$M4" != "3" ]; then
  echo "MARKER-FAILED: expected R1290=3 zrfG2=4 A22C-site=3 file-band=3 - nothing applied"
  exit 0
fi
cp -p runtime/runtime.c runtime/runtime.c.bak1290
if ! patch -p0 --dry-run runtime/runtime.c < /tmp/r1290_zrfg2.diff; then
  echo "DRYRUN-FAILED: patch does not apply cleanly - nothing changed"
  exit 0
fi
if ! patch -p0 runtime/runtime.c < /tmp/r1290_zrfg2.diff; then
  cp -p runtime/runtime.c.bak1290 runtime/runtime.c
  echo "APPLY-FAILED: restored backup, nothing run"
  exit 0
fi
N=$(shasum -a 256 runtime/runtime.c | cut -d" " -f1)
echo "NEW_SHA=$N"
if [ "$N" != "6e57555af37e17bd87820613cd5aa14bc410b0237f89945958eb29e5494f5235" ]; then
  cp -p runtime/runtime.c.bak1290 runtime/runtime.c
  echo "POST-APPLY-FAILED: patched tree sha mismatch (expected 6e57555a) - restored backup, nothing run"
  exit 0
fi
echo "PATCHED TREE VERIFIED (sandbox-parsed, sha-gated)"

echo "===RUN191=== the 120s receipt run - alive-guarded captures, live-tail correlation"
RUN_BUDGET_S=120 ./run.sh > /tmp/run191.txt 2>&1 &
RUNPID=$!
echo "LAUNCH-WALL $(date +%s)"
sleep 6
if ! kill -0 $RUNPID 2>/dev/null; then
  echo "RUN-DIED-EARLY: compile or launch failed - no captures, no stale artifacts"
  head -8 /tmp/run191.txt
  wait $RUNPID
  echo "RUNSH_RC=$?"
  echo "===END191==="
  exit 0
fi
LC_ALL=C grep -a -o "runtime build R[0-9]*" xenogears_boot | head -1
LV_B="vram_live.bin"
LV_M="vram_live.meta"
SNAP=$(mktemp -d /tmp/xl191.XXXXXX)
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
tail -12 /tmp/run191.txt

echo "===SHOTS191=== render with error retention, verify, preserve"
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

echo "===STORM191=== THE GOVERNOR VERDICT - the storm must stay tamed (7.2MB class last run)"
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
echo "===ZRFG2191=== THE FILE-BAND SERVE VERDICT - fires, drain, forward execution"
grep -c "zrfG2" run.log
grep -n "zrfG2" run.log | head -16
echo "--- the drain receipts: FDF8 movement below 125304 (fld2sig + pumpcam tails)"
grep -n "fld2sig" run.log | tail -8
grep -n "pumpcam" run.log | tail -8
echo "--- forward execution: new LBAs, fetch entries, state table, screen"
grep -n "fetchcam" run.log | tail -8
grep -n "statetbl" run.log | tail -6
grep -c "nonblank=100" run.log
echo "--- the zrfG status-site sibling (must stay 0 if A22C-site fires)"
grep -c "zrfG\] R1285" run.log
echo "--- defib follow-on (band 108754-109400 may take over after act=1)"
grep -n "defib" run.log | tail -6
echo "===CMD0D191=== THE 0x0D CAMERAS STAY - arrivals, pops (c190 verdict: pops prove the game advances)"
echo "--- [cmd0d] arrivals (full drive state at issue time)"
grep -c "cmd0d" run.log
grep -n "cmd0d" run.log | head -16
echo "--- [rspop0d] pops (if the game pops the ack, 0x0D is a READ command)"
grep -c "rspop0d" run.log
grep -n "rspop0d" run.log | head -16
echo "--- THE VERDICT PAIR: rspop lines interleaved with cmd0d, line-numbered"
grep -n "cmd0d\|rspop0d" run.log | head -32
echo "--- the FE1C movement after the 0x0D era (the [chg] writer trail, tail)"
grep -n "chg\] FE1C" run.log | tail -12
echo "===RLGL190=== THE RETRACTION MUST HOLD - loop dead, latch protocol game-driven"
grep -c "rlgl" run.log
grep -c "latchfix" run.log
grep -c "latchw" run.log
grep -c "fn_80019ACC(130)" run.log
grep -c "latchhw" run.log
grep -n "idx_work=96\|idx_work=16" run.log | head -8
grep -c "idxw" run.log
grep -n "idxw" run.log | head -12
grep -c "logbudget" run.log
echo "===ZRFG191=== the parked file-band guard"
grep -c "zrfG" run.log
echo "===ZRFB191=== the widened zrfB door - prior-era fires"
grep -c "zrfB.*fire #" run.log
echo "===DECL191=== the decline receipts"
grep -c "defib-decline" run.log
echo "===DRV191=== the R967 DRV lines"
grep -n "DRV act" run.log | head -6
echo "===ZRFF191=== the zrfF system-band guard"
grep -c "zrfF" run.log
echo "===WEDGE191=== the wedge family"
grep -c "STUCK" run.log
grep -n "STUCK" run.log | head -6
grep -c "alarmguard" run.log
echo "===FETCH191=== the fetch trace"
grep -n "fetchcam" run.log | tail -10
grep -n "sector LBA 0 " run.log | head -6
grep -n "fldsec" run.log | tail -8
echo "===FILE191=== the file chain - carry, epochs, archive sync"
grep -n "defib6" run.log | tail -8
grep -n "boot main entered" run.log
grep -n "newmod" run.log | tail -6
grep -n "asyctx" run.log | tail -6
echo "===ADV191=== THE ADVANCE CENSUS - states, dispatcher, pad, screen"
grep -n "fn_80019ACC" run.log | tail -6
grep -c "fn_80019ACC" run.log
grep -n "statetbl" run.log | tail -4
echo "===SCENE191=== the scene census - state machine, GPU, input"
grep -n "statetbl" run.log | tail -6
grep -n -E "gpufin|gpucls" run.log | tail -4
grep -c "gpucmd" run.log
grep -c "padrdw" run.log
grep -n "nonblank" run.log | tail -6
grep -c "mvloop" run.log
grep -n "mvloop" run.log | tail -3
echo "===ALARM191=== the alarm-deferral + FE1C/FE04 writer trails"
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
echo "===WALL191=== the wall census"
grep -c "NULL-trap" run.log
grep -c "AbortOnGameFault" run.log
echo "===PROV191=== provenance"
LC_ALL=C grep -a -o "runtime build R[0-9]*" run.log | head -1
wc -l run.log
cp -p run.log run.log.c191
shasum -a 256 run.log run.log.c191 runtime/runtime.c
echo "===PNG191=== THE IMAGE TRANSFER - small renders, sha-verified, budget-bounded, LAST so the census always lands"
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

echo "===END191==="
