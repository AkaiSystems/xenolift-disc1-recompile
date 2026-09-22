#!/bin/bash
# c205 THE MOVIE-ERA EVIDENCE CYCLE (cameras only, no behavior arm).
# THE c204 VERDICTS (receipted): the R1304 read-ack arm NEVER NEEDED TO
# FIRE - for the first time in the project the run recorded ZERO
# blocked-with-terms responses (schdd count 0): the game executed its
# ENTIRE CD protocol natively - directory reads at LBAs 0-3 served and
# consumed at native speed (fetchcam #155-162, dests 801F83xx-801F9Bxx),
# the archive chain armed and drained, and the response ladder stayed
# silent because every wait was answered by the normal path. THE
# TERMINAL POSTURE MOVED PAST the directory re-read to the pre-movie
# wait itself: the drive sits AT the movie position (seek=109158/
# 109166), FDF8=0, FE1C=0, FDFC=0, act=0, data FIFO empty, A22C=5 held
# static - every spin-exit term met EXCEPT the LegacyCdDataWait ret -
# and mdec-writes=0 (the movie decoder has NEVER run in any era). THE
# DECISIVE NEW RECEIPT: the alarm-deferral at the movie loader
# (alarmguard: on_alarm deferred - anchor mid-guest-step, cur_fn=800357C0)
# - the c179 class: the serve/arrival event the movie waiter needs is
# QUEUED but its drain defers to a dispatch boundary the pre-movie spin
# NEVER YIELDS. Meanwhile defib6 re-shelved the movie file (14352B vs
# the game ftab 14360 - the reshtail dest-alignment receipt settles
# benign header-skip vs true truncation, read at preservation) and the
# game RE-REQUESTED the movie read 4x (FE04=109158 re-stamps). THIS
# CYCLE: no arm - the starvation fix must be designed from the receipts
# (which boundary CAN the drain run at without a forged dispatch, the
# R1179 c369 discipline holds). The script extracts the full movie-era
# terms from the CURRENT run.log BEFORE the fresh run (alarm trail,
# reshtail verdict, re-request windows, act timeline, A22C writers),
# preserves it, then runs the fresh 120s receipt run with the standing
# decisive-chain digest. The receipts decide the c206 fix. Base gate
# ecaab954 (the c202-run tree). Bootstrap: fetch, SHA-256 gate, syntax
# gate, provenance copy, execute.

cd "$HOME/Downloads/xenolift" || exit 1

echo "===PRE205=== identity, tree drift gate (the c202-run tree ecaab954 - the R1304 post-apply tree, receipted by cycle 204 own NEW_SHA print)"
T=$(shasum -a 256 runtime/runtime.c | cut -d" " -f1)
echo "TREE_SHA=$T"
CUR="ecaab95435b9ec1b1a57e56c06b74e867e6daebab68d48f75e46805c1f348d9b"
if [ "$T" != "$CUR" ]; then
  echo "DRIFT-FAILED: tree is not the c202-run tree ecaab954 - nothing run, nothing applied"
  exit 0
fi
echo "TREE-VERIFIED: the R1304 read-ack build is in place (its class did not recur in c204 - zero blocked receipts, the arm stayed 0-fire by design)"
LC_ALL=C grep -a -o "runtime build R[0-9]*" xenogears_boot | head -1

echo "===PRESERVE205=== PRESERVE the existing run.log BEFORE the fresh run overwrites it (it may hold the prior c200-run receipts) - FAIL EXPLICIT"
TS=$(date +%Y%m%d_%H%M%S)
SNAP="runlog_preserve_c205_$TS"
if [ -f run.log ]; then
  mkdir -p "$SNAP"
  if ! cp -p run.log "$SNAP/run.log"; then echo "PRESERVE-FAILED: run.log copy failed - nothing run"; exit 0; fi
  if [ -f run.log.d ]; then cp -p run.log.d "$SNAP/run.log.d" 2>/dev/null || echo "run.log.d copy failed (non-fatal, noted)"; fi
  echo "PRESERVED: $SNAP/run.log sha=$(shasum -a 256 "$SNAP/run.log" | cut -c1-16) size=$(wc -c < "$SNAP/run.log") ts=$TS"
  echo "--- THE MOVIE-ERA TERMS (the c204 receipts that name the next transition - read BEFORE the fresh run)"
echo "--- (1) THE ALARM-DEFERRAL TRAIL (the serve event starved mid-guest-step - the c179/c204 class: every line, which loader fn, how long)"
if [ -f run.log ]; then grep -n "alarmguard" run.log | tail -16; fi
echo "--- (2) THE RESHTAIL DEST-ALIGNMENT RECEIPT (settles benign header-skip vs true truncation - the 8-byte delta verdict)"
if [ -f run.log ]; then grep -n "reshtail" run.log | head -6; fi
echo "--- (3) THE MOVIE RE-REQUEST WINDOWS (each FE04=109158 re-stamp with its drive/act/fe1c context, 4 receipted in c204)"
if [ -f run.log ]; then grep -n "FE04=109158\|FE04=0001AA66" run.log | head -12; fi
echo "--- (4) THE MOVIE-READ ISSUE + THE DRIVE RESPONSE (READ ISSUED file#=18 followed by act/seek/fdw entries - did the drive EVER engage for it)"
if [ -f run.log ]; then grep -n "READ ISSUED fn_80029690(file#=18" run.log | head -6; fi
if [ -f run.log ]; then grep -n "actchg" run.log | grep -i "109158\|1AA66" | head -8; fi
echo "--- (5) MDEC (the movie decoder - writes stay 0 until the pre-movie wait concludes)"
if [ -f run.log ]; then grep -n "mdec" run.log | tail -4; fi
echo "--- (6) THE A22C WRITER TRAIL (the CD-data-arrived flag: who wrote 5, who clears it - the LegacyCdDataWait ret source)"
if [ -f run.log ]; then grep -n "0x8006A22C\|A22C site entry" run.log | tail -12; fi
echo "--- WHICH ERA IS THE PRESERVED LOG? (the c204 marker census)"
  echo "preserved bootmain entries: $(grep -c "bootmain\] boot main entered" "$SNAP/run.log" || true)"
  echo "preserved era-stamped lines: $(grep -c "era=" "$SNAP/run.log" || true)"
  echo "preserved R612 releases: $(grep -c "R612 endgame release" "$SNAP/run.log" || true)"
  echo "preserved rspop01 pops: $(grep -c "rspop01" "$SNAP/run.log" || true)"
  echo "preserved rspop13 pops: $(grep -c "rspop13" "$SNAP/run.log" || true)"
  echo "preserved R1300 door fires (must be 0 post-retirement): $(grep -c "R1300 movie-wait" "$SNAP/run.log" || true)"
  echo "preserved schdd blocked: $(grep -c "delivery decision BLOCKED" "$SNAP/run.log" || true)"
  echo "preserved schdd WIN: $(grep -c "delivery WIN" "$SNAP/run.log" || true)"
  echo "preserved mdec: $(grep -c "mdec" "$SNAP/run.log" || true)"
  echo "preserved tail (last 6 lines, the era the log ended in):"
  tail -6 "$SNAP/run.log"
else
  echo "NO EXISTING run.log - the prior cycle-202 digest was drift-failed BEFORE any run, nothing to preserve"
fi
echo "===FMTGATE205=== diagnostic-correctness build gate (Jos #1): -Wformat must be SILENT - diagnostics are implementation"
CC=$(command -v clang || command -v gcc)
if [ -z "$CC" ]; then echo "FMT-FAILED: no C compiler found - nothing run"; exit 0; fi
"$CC" -fsyntax-only -Wformat -Werror=format runtime/runtime.c 2>/tmp/fmt205.txt
FRC=$?
if [ "$FRC" != "0" ]; then echo "FMT-FAILED: format warnings present (rc=$FRC) - diagnostics are part of the implementation - nothing run"; head -8 /tmp/fmt205.txt; exit 0; fi
echo "FMT-GATE-PASSED: zero -Wformat warnings on the patched tree"

echo "===RUN205=== the 120s receipt run - alive-guarded captures, live-tail correlation"
RUN_BUDGET_S=120 ./run.sh > /tmp/run194.txt 2>&1 &
RUNPID=$!
echo "LAUNCH-WALL $(date +%s)"
sleep 6
if ! kill -0 $RUNPID 2>/dev/null; then
  echo "RUN-DIED-EARLY: compile or launch failed - no captures, no stale artifacts"
  head -8 /tmp/run194.txt
  wait $RUNPID
  echo "RUNSH_RC=$?"
  echo "===END205==="
  exit 0
fi
LC_ALL=C grep -a -o "runtime build R[0-9]*" xenogears_boot | head -1
LV_B="vram_live.bin"
LV_M="vram_live.meta"
SNAP=$(mktemp -d /tmp/xl200.XXXXXX)
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
tail -12 /tmp/run194.txt

echo "===SHOTS200=== render with error retention, verify, preserve"
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

echo "===STORM205=== THE GOVERNOR VERDICT - the storm must stay tamed (6.6MB class last run)"
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
echo "===SCHDD194=== THE DELIVERY-DECISION RECEIPTS - the seq chain names the missing transition"
grep -c "schdd" run.log
grep -n "schdd" run.log | head -24
echo "--- THE SEQ CHAIN: SET prints (command -> scheduled, seq-stamped)"
grep -c "INT3 scheduled (event delivery)" run.log
grep -n "INT3 scheduled (event delivery)" run.log | tail -12
echo "--- THE CLEAR SIDE: all 11 sites, first-eval, seq + t + resp ack state"
grep -c "schdw" run.log
grep -n "schdw" run.log | head -24
echo "--- THE c192 DEST ANSWER (defib6 R495 re-shelve receipts - dest-HELD)"
grep -n "carry-v3: full re-shelve" run.log | head -4
echo "--- THE [movsite] A22C SITE-ENTRY CENSUS: entries present + 0 movq = gate declined; no entries = site cold (Jos: zero movq hits does not prove A22C untouched)"
grep -c "movsite" run.log
grep -n "movsite" run.log | head -12
echo "--- THE [schdd] WIN CENSUS (delivery followed by another SET = healthy; the adjacent [cd] R6xx names the branch)"
grep -c "delivery WIN" run.log
grep -n "delivery WIN" run.log | head -8
echo "===DELIV194=== the A22C-site movq camera (its receipt count now interpretable via the movsite census)"
echo "--- the FE04=109158 re-stamp count (the game re-request cadence)"
grep -c "0001AA66 at fn 0x800288EC" run.log
grep -n "0004FE04: .* -> 0001AA66" run.log | head -8
echo "--- the movie module installs + dest (receipted)"
grep -n "member=18" run.log | head -4
echo "--- defib6 file#18 completion + shelved state"
grep -n "defib6" run.log | head -8
echo "--- the late-era FE1C advance (the game own timeout that finally moved it)"
grep -n "chg\] FE1C 000A->0000\|chg\] FE1C .*->0009" run.log | head -6
echo "===ZRFG2193=== THE FILE-BAND SERVE - fires if the file#14 posture recurs"
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
echo "===ZRFG193=== the parked file-band guard"
grep -c "zrfG" run.log
echo "===ZRFB193=== the widened zrfB door - prior-era fires"
grep -c "zrfB.*fire #" run.log
echo "===DECL193=== the decline receipts"
grep -c "defib-decline" run.log
echo "===DRV193=== the R967 DRV lines"
grep -n "DRV act" run.log | head -6
echo "===ZRFF193=== the zrfF system-band guard"
grep -c "zrfF" run.log
echo "===WEDGE193=== the wedge family"
grep -c "STUCK" run.log
grep -n "STUCK" run.log | head -6
grep -c "alarmguard" run.log
echo "===FETCH205=== the fetch trace"
grep -n "fetchcam" run.log | tail -10
grep -n "sector LBA 0 " run.log | head -6
grep -n "fldsec" run.log | tail -8
echo "===FILE193=== the file chain - carry, epochs, archive sync"
grep -n "defib6" run.log | tail -8
grep -n "boot main entered" run.log
grep -n "newmod" run.log | tail -6
grep -n "asyctx" run.log | tail -6
echo "===ADV193=== THE ADVANCE CENSUS - states, dispatcher, pad, screen"
grep -n "fn_80019ACC" run.log | tail -6
grep -c "fn_80019ACC" run.log
grep -n "statetbl" run.log | tail -4
echo "===SCENE193=== the scene census - state machine, GPU, input"
grep -n "statetbl" run.log | tail -6
grep -n -E "gpufin|gpucls" run.log | tail -4
grep -c "gpucmd" run.log
grep -c "padrdw" run.log
grep -n "nonblank" run.log | tail -6
grep -c "mvloop" run.log
grep -n "mvloop" run.log | tail -3
echo "===ALARM193=== the alarm-deferral + FE1C/FE04 writer trails"
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
echo "===WALL193=== the wall census"
grep -c "NULL-trap" run.log
grep -c "AbortOnGameFault" run.log
echo "===CHAIN205=== THE DECISIVE CHAIN (c204 verdict: the CD response layer is VALIDATED end-to-end - zero blocked receipts, the game ran its own protocol natively; the remaining demonstrated blocker is the MOVIE-ERA serve event: the pre-movie poll at the movie position with all exit terms met except the LegacyCdDataWait ret, mdec-writes=0, and the alarm-deferral receipt starving the serve event mid-guest-step - this run receipts those terms)"
echo "--- THE REPAIRED-ARM DELIVERIES (R612 endgame release prints, era-stamped)"
grep -n "R612 endgame release" run.log | tail -12
echo "--- THE CLEAR SITES (era + seq + resp popped/armed - the retire bookkeeping)"
grep -n "CLEAR site L2378\|CLEAR site L2333" run.log | tail -8
echo "--- THE GETSTAT POP RECEIPTS (rspop01 - guest consumed the byte)"
grep -c "rspop01" run.log
grep -n "rspop01" run.log | head -16
echo "--- THE GETTN POP RECEIPTS (rspop13 - all 3 TOC bytes consumed + FE1C after)"
grep -c "rspop13" run.log
grep -n "rspop13" run.log | head -16
echo "--- FE1C AFTER the GetTN pops (the directory-wait exit receipts)"
grep -n "chg\] FE1C" run.log | tail -16
echo "--- THE SPIN STATE (mvloop tail - which wait now?)"
grep -n "mvloop" run.log | tail -4
echo "--- THE MOVIE ERA (mdec receipts)"
grep -c "mdec" run.log
grep -n "mdec" run.log | head -8
echo "--- IF DELIVERY SUCCEEDS BUT PROGRESS STALLS: distinguish remaining blocker (new blocked posture w/ terms) from incorrect delivery"
grep -n "schdd\] R1291 delivery decision BLOCKED" run.log | tail -10
echo "--- THE R1298 ARMSTART DOOR VERDICT (stays 0-fire unless its never-started class recurs)"
grep -n "armstart\|R1298 fire" run.log | head -6
echo "===RESCUE205=== THE RESCUE CENSUS (Jos #5: which older recovery patches fired - retirement decisions come from these receipts)"
for tag in defib5 defib6 zrfB zrfG armstart starter-heal heapheal bankheal wdsheal lzss-heal; do
  echo "$tag fires: $(grep -c "\[$tag\]" run.log)"
done
echo "--- R1300 door retired this cycle: its release prints must be ABSENT (0 fires = clean retirement)"
echo "R1300 fires: $(grep -c "R1300 movie-wait" run.log)"
echo "===ERA205=== THE ERA CENSUS (requests tracked across their full lifetime, era-stamped)"
grep -n "bootmain\] boot main entered" run.log | head -8
echo "era-stamped lines: $(grep -c "era=" run.log)"
echo "===FDW200=== THE FDF8 ARM WRITER TRAIL (the 92180 arm names itself: writer fn + requested LBA + dest + drive posture at arm)"
grep -c "fdw" run.log
grep -n "fdw" run.log | head -24
echo "===ACTCHG199=== THE ACTIVE-TRANSFER TRANSITION TRAIL (0->1 = starts issued; 1->0 = loss-or-shutdown sites)"
grep -c "actchg" run.log
grep -n "actchg" run.log | head -40
echo "===FREEZEDOSS199=== THE FREEZE DOSSIER (FE04 vs seek identities, announce snapshot, done-bytes, serve ring - receipts decide)"
grep -c "freezedoss" run.log
grep -n "freezedoss" run.log | head -12
echo "--- THE FULL [cd] COMMAND TIMELINE (seq + wall t)"
grep -n "INT3 scheduled" run.log | tail -24
echo "--- THE defib-decline CENSUS"
grep -c "defib-decline" run.log
grep -n "defib-decline" run.log | head -12
echo "===REPAIR199=== THE R1301 GATE-REPAIR VERDICT (the repaired r611_end must now deliver through the EXISTING R612 machinery - one delivery per scheduled seq)"
echo "--- THE R612 ENDGAME RELEASES (cmd=01 stat=02 fe1c=7 - the repaired gate delivering)"
grep -c "R612 endgame release" run.log
grep -n "R612 endgame release" run.log | head -16
echo "--- THE R613 EVENT POSTS (slotbits bit2 - the existing seek-complete leg)"
grep -c "R613 event post" run.log
echo "--- THE schdd WIN CENSUS (delivery followed by another SET = healthy)"
grep -c "delivery WIN" run.log
grep -n "delivery WIN" run.log | head -8
echo "--- THE DECISIVE CHAIN: deliveries -> guest ack (resp popped) -> wait exit (FE1C off 7) -> next scene (new LBAs, SETs, mdec)"
grep -n "chg\] FE1C" run.log | tail -16
grep -n "INT3 scheduled" run.log | tail -16
grep -n "armstart" run.log | head -6
grep -n "R1298 fire" run.log | head -4
echo "--- IF DELIVERED BUT STILL PARKED: the remaining-blocker receipts (schdd blocked, all terms)"
grep -n "delivery decision BLOCKED" run.log | head -8
echo "--- CONSUMPTION: fldsec at the new LBA (the request own sectors consumed)"
grep -n "fldsec" run.log | tail -12
echo "--- CONSUMPTION: FDF8 movement at the wedge (armed 92180 must drain)"
grep -n "fld2sig" run.log | tail -6
grep -n "pumpcam" run.log | tail -6
echo "--- CONSUMPTION: FE1C movement (the chg writer trail, tail)"
grep -n "chg\] FE1C" run.log | tail -10
echo "--- THE SPIN EXIT: mvloop receipts (the FDFC=0 + ret=0 + FE1C=0 exit)"
grep -c "mvloop" run.log
grep -n "mvloop" run.log | tail -4
echo "--- THE STATE TABLE (real cells) + GPU FINAL"
grep -n "statetbl" run.log | tail -6
grep -n "gpufin" run.log | tail -3
echo "===PROV205=== provenance"
LC_ALL=C grep -a -o "runtime build R[0-9]*" run.log | head -1
wc -l run.log
cp -p run.log run.log.c205
shasum -a 256 run.log run.log.c205 runtime/runtime.c
echo "===PNG200=== THE IMAGE TRANSFER - small renders, sha-verified, budget-bounded, LAST so the census always lands"
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

echo "===END205==="
