#!/bin/bash
# c180 FIX CYCLE - R1282 zrfF LEGACY-FETCH CONSUMER DOOR - delivered as a FILE
# per the standing Jos protocol (the paste channel corrupts pasted code).
# The c179 harvest verdict: the terminal wedge is LegacyCdSectorFetch
# (fn 0x80042AA8) polling status bit 0x40 with the drive idle - the fetch
# PsyQ-table command sequence never engages the read machinery, so the 0x40
# bit (computed from cd_read_active && data-in-FIFO) can never set. The
# wedge posture is receipted by FOUR independent cameras (R967 STUCK x4,
# mvdoor-near x6, alarmguard x6, fetchcam #332): act=0, pend=0, cmd=01,
# seek=0, FE04=0, FDF8=2048 (the post-archive directory re-read, one sector
# wanted, already armed), held 50s+ to the fuse with the game ALIVE.
# R1282 doors the case 0x1F801800 status read (the exact register the fetch
# polls, 14.4M+ polls receipted - the hottest spin-reached site), gated on
# that exact posture with 65536-poll stuck confirmation, and serves the
# wanted sector (cd_data_load) + arms cd_read_active so the fetch's own
# DMA drains it - the c139-141 secserve composite, no INT forge, no guest
# dispatch. PASS = fetch consumes, FDF8 drives to 0, forward execution
# past 80042AA8. REVERT if the fetch consumes but the game does not advance.
set -u
cd "$HOME/Downloads/xenolift" || exit 1

echo "===PRE180=== identity and TREE DRIFT GATE"
T=$(shasum -a 256 runtime/runtime.c | cut -d" " -f1)
echo "TREE_SHA=$T"
if [ "$T" != "05f05543cdd68fe1648129a24acc92d225d022c1477891cbd1a074c7845935c5" ]; then
  echo "DRIFT-FAILED: runtime/runtime.c sha does not match the c179 receipted baseline - nothing applied, nothing run"
  exit 0
fi
LC_ALL=C grep -a -o "runtime build R[0-9]*" xenogears_boot | head -1

echo "===PATCH180=== fetch, verify, apply the R1282 patch - marker gates, FAIL EXPLICIT"
curl -sSL -m 30 -o /tmp/r1282_zrfF.diff "https://base44.app/api/apps/6aa26c7ce0ac9a5ee05d2b95/files/mp/public/6aa26c7ce0ac9a5ee05d2b95/7b8b8c34a_r1282_zrfF.diff"
echo "CURL_RC=$?"
P=$(shasum -a 256 /tmp/r1282_zrfF.diff | cut -d" " -f1)
echo "PATCH_SHA=$P"
if [ "$P" != "d0027866e7b975c37cf90e68039a6f2c5b20998278f17fcb0c9bf4b659fb8812" ]; then
  echo "PATCH-VALID-FAILED: sha mismatch - expected d0027866 - nothing applied, nothing run"
  exit 0
fi
M1=$(grep -c "zrfF" /tmp/r1282_zrfF.diff)
M2=$(grep -c "R1282" /tmp/r1282_zrfF.diff)
echo "PATCH_MARKERS zrfF=$M1 R1282=$M2"
if [ "$M1" != "3" ] || [ "$M2" != "4" ]; then
  echo "MARKER-FAILED: expected zrfF=3 R1282=4 - nothing applied"
  exit 0
fi
cp -p runtime/runtime.c runtime/runtime.c.bak1282
echo "BACKUP_SHA=$(shasum -a 256 runtime/runtime.c.bak1282 | cut -d" " -f1)"
if ! patch -p0 --dry-run runtime/runtime.c < /tmp/r1282_zrfF.diff; then
  echo "DRYRUN-FAILED: patch does not apply cleanly - nothing changed"
  exit 0
fi
if ! patch -p0 runtime/runtime.c < /tmp/r1282_zrfF.diff; then
  cp -p runtime/runtime.c.bak1282 runtime/runtime.c
  echo "APPLY-FAILED: restored backup, nothing run"
  exit 0
fi
echo "NEW_SHA=$(shasum -a 256 runtime/runtime.c | cut -d" " -f1)"
A1=$(grep -c "zrfF" runtime/runtime.c)
A2=$(grep -c "runtime build R1282" runtime/runtime.c)
A3=$(grep -c "runtime build R1281" runtime/runtime.c)
echo "APPLIED_MARKERS zrfF=$A1 banner1282=$A2 banner1281=$A3"
if [ "$A1" != "3" ] || [ "$A2" != "1" ] || [ "$A3" != "0" ]; then
  cp -p runtime/runtime.c.bak1282 runtime/runtime.c
  echo "POST-APPLY-FAILED: markers wrong - restored backup, nothing run"
  exit 0
fi

echo "===RUN180=== the 120s verification run - launch clock, wall-relative captures, live-tail correlation"
RUN_BUDGET_S=120 ./run.sh > /tmp/run180.txt 2>&1 &
RUNPID=$!
echo "LAUNCH-WALL $(date +%s)"
grep -a -o "runtime build R[0-9]*" xenogears_boot | head -1
LV_B="vram_live.bin"
LV_M="vram_live.meta"
SNAP=$(mktemp -d /tmp/xl180.XXXXXX)
if [ -z "$SNAP" ]; then echo "SNAPDIR-FAILED - aborting captures"; else echo "SNAPDIR=$SNAP"; fi
mkdir -p "$SNAP/w50" "$SNAP/w65" "$SNAP/w80" "$SNAP/w95"

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

sleep 50; grab "$SNAP/w50" "w50"
sleep 15; grab "$SNAP/w65" "w65"
sleep 15; grab "$SNAP/w80" "w80"
sleep 15; grab "$SNAP/w95" "w95"
wait $RUNPID
echo "RUNSH_RC=$?"
head -3 run.log
tail -12 /tmp/run180.txt

echo "===SHOTS180=== render with error retention, verify, preserve"
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

echo "===ZRFF180=== THE DOOR - fires, consumption, forward execution"
grep -c "zrfF" run.log
grep -n "zrfF" run.log | head -12
echo "===WEDGE180=== the wedge family after the fix"
grep -c "STUCK" run.log
grep -n "STUCK" run.log | head -6
grep -c "alarmguard" run.log
echo "===FETCH180=== the fetch trace - entries, LBA-0 serve, drain"
grep -n "fetchcam" run.log | tail -10
grep -n "sector LBA 0 " run.log | head -6
grep -n "fldsec" run.log | tail -8
echo "===FILE180=== the file chain - carry, epochs, archive sync"
grep -n "defib6" run.log | tail -8
grep -n "boot main entered" run.log
grep -n "newmod" run.log | tail -6
grep -n "asyctx" run.log | tail -6
echo "===SCENE180=== the scene-init census - state machine, GPU, input"
grep -n "statetbl" run.log | tail -6
grep -n -E "gpufin|gpucls" run.log | tail -4
grep -c "gpucmd" run.log
grep -c "padrdw" run.log
grep -n "nonblank" run.log | tail -6
grep -c "mvloop" run.log
grep -n "mvloop" run.log | tail -3
echo "===SCHED180=== the scheduled-flag observations"
grep -n "cdw02" run.log | tail -6
grep -c "pendclr" run.log
echo "===WALL180=== the wall census"
grep -c "NULL-trap" run.log
grep -c "AbortOnGameFault" run.log
echo "===PROV180=== provenance"
LC_ALL=C grep -a -o "runtime build R[0-9]*" run.log | head -1
wc -l run.log
cp -p run.log run.log.c180
shasum -a 256 run.log run.log.c180 runtime/runtime.c
echo "===PNG180=== THE IMAGE TRANSFER - small renders, sha-verified, budget-bounded, LAST so the census always lands"
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

echo "===END180==="
