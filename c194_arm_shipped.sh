#!/bin/bash
# c194 THE FE04-MATCH NEVER-ARMED ARM + THE R1104 CAMERA FIX + THE DEST-ALIGNMENT
# RECEIPT - R1295, ONE targeted behavior change + cameras. THE c193 RUN
# EXECUTED COMPLETE (tree 928f393d applied clean, the full camera set live,
# 120s run, all gates green) and its receipts SETTLE the Jos hypothesis pair:
# (1) THE SCHEDULER TRACE IS COMPLETE: the delivery path is NOT cold (a
# [schdd] WIN at seq=677 delivered a cmd-06 response); 40 SET prints = the
# game ACTIVELY issuing commands throughout; the terminal wedge posture
# receipted with EVERY gate term by the post-ladder [schdd]: cmd=01
# GetStat-poll, FE1C=6, FDF8=0 NEVER ARMED, FE04=109123 (file#17 LBA,
# stamped by the game own ftab reader), seek parked at 0, resp=0/0, A22C=0,
# sched=1, seqs advancing 976-1006 - the game re-requesting data the
# machinery never arms. NOT a stale frozen sched: the seq advanced through
# 30+ new SETs. THE MISSING TRANSITION = THE ARM for the FE04 request LBA.
# (2) THE STATE-SETUP QUESTION ANSWERED with real cells: STATE 1 INSTALLED
# IN THE AFFECTED ERA (g_CurGameState(18088)=1, state-1 gdesc fields real,
# hasOverlay=1) - so per the Jos window rule the scheduler trace is the
# thread to pursue, and the earliest demonstrated broken dependency in the
# movie era is the never-armed re-request.
# (3) RETRACTION (my camera bug): R1104 v0 passed NINE args for THIRTEEN
# format slots - the active-rec fn/mem/heapstart/ov fields read UNPASSED
# VARARGS = HOST GARBAGE (the run-varying values 82E7FF90/000007FD/
# 88FEE1E0). THE INVALID-ACTIVE-STATE-RECORD EVIDENCE IS WITHDRAWN. What
# remains real from the first window: g_CurGameState(18088)=0 (a real cell
# read) and the AbortOnGameFault code=130 abort at the first resident entry.
# R1104 IS FIXED in this patch: the slots now read the REAL record cells
# gdesc[g_CurGameState] at 1808C+cur*16.
# (4) THE 8-BYTE DELTA ARITHMETIC EXPLAINED from source (necessary per Jos):
# R495 re-shelve writes payload = file[8:] -> dest+0, so 14352 = 14360 - 8
# = the native header skip, BY DESIGN, same layout as the working heal for
# other files. CONFIRMING THE REQUIRED BYTES REACH THE INTENDED DESTINATION
# (the closing half): the new [reshtail] receipt prints dest[0:8] vs
# file[0:8] (header) vs file[8:16] (payload start) at every carry - dest ==
# payload-start = native layout CONFIRMED (benign); dest == header =
# misalignment (a different fix named).
# THE FIX (R1295, per the Jos rule - earliest demonstrated broken dependency
# in the affected era): the c62-era R496 never-armed arm matches file-table
# members against cd_seek_lba (the PARKED position, 0) instead of FE04 (the
# queued request LBA 109123) - this exact class. THE WIDEN: at the
# PROVEN-HOT site (the end of cd_sched_poll_release, receipted hot by the
# schdd fires), when the blocked posture holds (sched=1, pend=0, cmd=01,
# FDF8=0, seek<150, fe1c 6 or 10, FE04 a file-table LBA in the band), look
# the FE04 LBA up in the game own table (0x800100A5) and arm FDF8 with the
# member size exactly like a fresh announce - the established rescue
# machinery then serves it. GUARD RAILS: one arm per LBA (never re-arm the
# same request), band LBAs only (>100000, <300000), sane sizes (8..0x100000).
# REVERT criterion per the c174 lesson: the fire must lead to GUEST-SIDE
# consumption (FDF8 drains below the armed size, FE1C moves, new LBAs) -
# fire with zero consumption = revert next cycle. NOTHING FORCED: FE1C is
# never set, sched never cleared - the arm only arms data the game itself
# requested (FE04 stamped by its own ftab reader).
# PASS = receipts only: the [armfe] fire + the consumption chain (FDF8
# drain below the armed size, fldsec/fetch movement at the new LBA, FE1C
# transitions, state-table advance), plus the [reshtail] alignment answer
# and the fixed R1104 real-cell prints. Base gate 928f393d (the tree the
# c193 cycle ran), patch sha 3c487c97, post-apply d6e3d013, backup and
# restores read .bak1295. Bootstrap: fetch, SHA-256 gate, syntax gate,
# provenance copy, execute.
cd "$HOME/Downloads/xenolift" || exit 1

echo "===PRE194=== identity, tree drift gate (R1291v4 baseline 928f393d - the tree the c193 cycle receipted and ran)"
T=$(shasum -a 256 runtime/runtime.c | cut -d" " -f1)
echo "TREE_SHA=$T"
BASE="928f393dd2545952b02a73dc9cd3e8c6da88e3004b5a85320146085f9872abf2"
if [ "$T" != "$BASE" ]; then
  echo "DRIFT-FAILED: tree is not the receipted R1291v4 baseline 928f393d (the c193 run tree) - nothing run"
  exit 0
fi
T=$(shasum -a 256 runtime/runtime.c | cut -d" " -f1)
if [ "$T" != "$BASE" ]; then
  echo "RESTORE-VERIFY-FAILED - nothing run"
  exit 0
fi
echo "BASELINE_VERIFIED"
LC_ALL=C grep -a -o "runtime build R[0-9]*" xenogears_boot | head -1

echo "===EXTRACT193=== JOS READ-ONLY EXTRACTION from the PRESERVED c192 log (before the fresh run overwrites it)"
if [ -f run.log.c192 ]; then PLOG=run.log.c192; elif [ -f run.log ]; then PLOG=run.log; else PLOG=""; fi
if [ -n "$PLOG" ]; then
  echo "--- (1) schdw/schdd receipts in the preserved c192 log (expected 0 - the v1 tree had no seq instrumentation)"
  grep -c "schdw" "$PLOG"; grep -c "schdd" "$PLOG"
  echo "--- (2) the earliest fn_80019ACC(130) context window (the latch-clear game-mode entry from 80031DC8)"
  grep -n "fn_80019ACC(130)" "$PLOG" | head -4
  L=$(grep -n "fn_80019ACC(130)" "$PLOG" | head -1 | cut -d: -f1)
  if [ -n "$L" ]; then sed -n "$((L-12)),$((L+28))p" "$PLOG"; else echo "NO 130-CALL in preserved log"; fi
  echo "--- the latch-cell receipts in that era"
  grep -n "latch" "$PLOG" | head -8
  echo "--- (3) file#18: the 14360 request vs 14352 re-shelve pair"
  grep -n "READ ISSUED fn_80029690(file#=18" "$PLOG" | head -4
  grep -n "file#=18 base" "$PLOG" | head -4
  grep -n "carry-v3: full re-shelve" "$PLOG" | head -4
  echo "--- the R495 re-shelve size arithmetic: the FULL source region (the exact 8-byte drop, read-only)"
  grep -n "R495" runtime/runtime.c | head -8
  L495=$(grep -n "R495: FULL RE-SHELVE" runtime/runtime.c | head -1 | cut -d: -f1)
  if [ -n "$L495" ]; then sed -n "$((L495)),$((L495+64))p" runtime/runtime.c; else echo "R495 REGION NOT FOUND"; fi
  echo "--- the SECOND 130-call window (does the movie-era call also abort?)"
  L2=$(grep -n "fn_80019ACC(130)" "$PLOG" | sed -n 2p | cut -d: -f1)
  if [ -n "$L2" ]; then sed -n "$((L2-12)),$((L2+28))p" "$PLOG"; else echo "NO SECOND 130-CALL"; fi
  grep -n "R489 carry PROMOTE" runtime/runtime.c | head -6
else
  echo "NO PRESERVED LOG - extraction skipped"
fi
echo "===PATCH194=== fetch, verify, apply the R1295 FE04-match arm + camera-fix patch - marker + post-apply sha gates, FAIL EXPLICIT"
curl -sSL -m 30 -o /tmp/r1295_arm.diff "https://base44.app/api/apps/6aa26c7ce0ac9a5ee05d2b95/files/mp/public/6aa26c7ce0ac9a5ee05d2b95/f1c8b41a2_r1295_arm.diff"
echo "CURL_RC=$?"
P=$(shasum -a 256 /tmp/r1295_arm.diff | cut -d" " -f1)
echo "PATCH_SHA=$P"
if [ "$P" != "3c487c9794b3e580f0c49fd97ec8bbee3be44e1578019f420f52cac3acd0fa8e" ]; then
  echo "PATCH-VALID-FAILED: sha mismatch - nothing applied, nothing run"
  exit 0
fi
M1=$(grep -c "R1295" /tmp/r1295_arm.diff)
M2=$(grep -c "FE04-MATCH ARM" /tmp/r1295_arm.diff)
M3=$(grep -c "reshtail" /tmp/r1295_arm.diff)
M4=$(grep -c "REAL cells" /tmp/r1295_arm.diff)
M5=$(grep -c "armfe" /tmp/r1295_arm.diff)
M6=$(grep -c "R1296" /tmp/r1295_arm.diff)
echo "PATCH_MARKERS R1295=$M1 arm_fe04=$M2 reshtail=$M3 realcells=$M4 armfe=$M5 R1296=$M6"
if [ "$M1" != "3" ] || [ "$M2" != "1" ] || [ "$M3" != "1" ] || [ "$M4" != "1" ] || [ "$M5" != "1" ] || [ "$M6" != "1" ]; then
  echo "MARKER-FAILED: expected R1295=3 arm_fe04=1 reshtail=1 realcells=1 armfe=1 R1296=1 - nothing applied"
  exit 0
fi
cp -p runtime/runtime.c runtime/runtime.c.bak1295
if ! patch -p0 --dry-run runtime/runtime.c < /tmp/r1295_arm.diff; then
  echo "DRYRUN-FAILED: patch does not apply cleanly - nothing changed"
  exit 0
fi
if ! patch -p0 runtime/runtime.c < /tmp/r1295_arm.diff; then
  cp -p runtime/runtime.c.bak1295 runtime/runtime.c
  echo "APPLY-FAILED: restored backup, nothing run"
  exit 0
fi
N=$(shasum -a 256 runtime/runtime.c | cut -d" " -f1)
echo "NEW_SHA=$N"
if [ "$N" != "d6e3d01384d8057f0bc8053aeb6ac0caea71d1881e8a4e8a6e68a78e5860222b" ]; then
  cp -p runtime/runtime.c.bak1295 runtime/runtime.c
  echo "POST-APPLY-FAILED: patched tree sha mismatch (expected d6e3d013) - restored backup, nothing run"
  exit 0
fi
echo "PATCHED TREE VERIFIED (sandbox-parsed, sha-gated)"

echo "===RUN194=== the 120s receipt run - alive-guarded captures, live-tail correlation"
RUN_BUDGET_S=120 ./run.sh > /tmp/run194.txt 2>&1 &
RUNPID=$!
echo "LAUNCH-WALL $(date +%s)"
sleep 6
if ! kill -0 $RUNPID 2>/dev/null; then
  echo "RUN-DIED-EARLY: compile or launch failed - no captures, no stale artifacts"
  head -8 /tmp/run194.txt
  wait $RUNPID
  echo "RUNSH_RC=$?"
  echo "===END194==="
  exit 0
fi
LC_ALL=C grep -a -o "runtime build R[0-9]*" xenogears_boot | head -1
LV_B="vram_live.bin"
LV_M="vram_live.meta"
SNAP=$(mktemp -d /tmp/xl194.XXXXXX)
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

echo "===SHOTS194=== render with error retention, verify, preserve"
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

echo "===STORM194=== THE GOVERNOR VERDICT - the storm must stay tamed (6.6MB class last run)"
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
echo "===FETCH194=== the fetch trace"
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
echo "===PROV194=== provenance"
LC_ALL=C grep -a -o "runtime build R[0-9]*" run.log | head -1
wc -l run.log
cp -p run.log run.log.c194
shasum -a 256 run.log run.log.c194 runtime/runtime.c
echo "===PNG194=== THE IMAGE TRANSFER - small renders, sha-verified, budget-bounded, LAST so the census always lands"
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

echo "===END194==="
