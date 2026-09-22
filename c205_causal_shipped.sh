#!/bin/bash
# c205 THE MEASUREMENT-CORRECTED BUILD (R1305+R1306+R1307) - Jos c204
# claim-tightening accepted (a shipped build is an experiment until the
# runtime digest shows destination bytes and request completion; the
# 8-byte difference is a candidate cause until restoring the bytes
# removes the failure under comparable conditions) AND the c205
# measurement corrections accepted: (w50) the w50 capture holds the
# previous run preserved tail + a stale 03:03 VRAM file - EXCLUDED from
# progress comparisons; (duplication) seq 35 receipts at two line
# numbers with identical t+era and repeated re-shelve receipts - tag
# counts are NOT reliable counts of deliveries, rescues, or restarts
# until the duplication question is resolved (pipeline double-write vs
# execution repeat - the LOGDUP205 section decides from the raw
# stream); (banner) the unchanged R1291 banner is inconclusive - R1307
# adds a compile-time-stamped provenance line (source-tree sha gated
# pre-run -> compile timestamp -> R1196 executed-binary sha); (exit)
# RUNSH_RC=0 is the wrapper result, not proof of a clean guest exit -
# FAULTX205 extracts this run first fault and final exit from the raw
# stream. THE CENTRAL QUESTION (Jos): which exact branch keeps
# execution looping now that FE1C has cleared? R1306 answers with the
# WAIT-BRANCH CAMERA at LegacyCdDataWait (0x8004293C) return: the
# ACTUAL return value + the exit-condition cells (FDFC/FE1C) + the
# request cells + the d3 family (the R1098 exit-path decode: it reads
# LW(LW(0x800567B4)) & 0x01000000) + the caller, in the same
# invocation, first 8 + every value change + 1/65536 - passives only.
# NO acknowledgment rescue: there is no outstanding scheduled response
# in the displayed late wait (schdd silent, sched=0) - the receipts
# decide the next fix. R1305 (the causal test on the 8-byte delta, kept
# from the pre-correction build): the R495 re-shelve arithmetic is
# source-found (rem = s_ovl_size - 8 with src = 8 treats the ftab size
# as header+payload, but the game request counts the PAYPLY: FDF8=14360
# receipted at READ ISSUED, the drain counts 14360 down to 0) - the fix
# restores the full table size and the TAIL-CONTENT RECEIPT shows the
# last 8 payload bytes of dest against the file own source bytes
# (TAIL DELIVERED vs TAIL MISMATCH, shown not assumed); the digest
# carries all seven causality discriminators. IF the re-request cadence
# stops AND the waiter concludes, the truncation is a proven cause; IF
# the failure persists with the tail restored, the receipts name the
# next candidate and the fix is reverted next cycle. Status per Jos
# wording: loading, decompression, module installation, controller
# polling, and several response paths demonstrated; first interactive
# scene and sustained gameplay unproven; the number of remaining
# blockers unknown. Base gate ecaab954 (the c204-run tree, receipted by
# the c204 NEW_SHA), patch sha 738f24ae (sandbox-verified: apply clean,
# parse clean, ZERO -Wformat warnings), post-apply f21f91d1, backup and
# restores read .bak1305. Bootstrap: fetch, SHA-256 gate, syntax gate,
# provenance copy, execute.

cd "$HOME/Downloads/xenolift" || exit 1

echo "===PRE205=== identity, tree drift gate (the c204-run tree ecaab954 - receipted by the c204 cycle own NEW_SHA print)"
T=$(shasum -a 256 runtime/runtime.c | cut -d" " -f1)
echo "TREE_SHA=$T"
BASE="ecaab95435b9ec1b1a57e56c06b74e867e6daebab68d48f75e46805c1f348d9b"
if [ "$T" != "$BASE" ]; then
  echo "DRIFT-FAILED: tree is not the c201-run tree 271b6bbf - nothing run, nothing applied"
  exit 0
fi
echo "BASELINE_VERIFIED"

echo "===PATCH205=== fetch, verify, apply the R1305+R1306+R1307 measurement-corrected patch - marker (artifact-generated, line-count semantics) + post-apply sha gates, FAIL EXPLICIT"
curl -sSL -m 30 -o /tmp/r1305_reshelve.diff "https://base44.app/api/apps/6aa26c7ce0ac9a5ee05d2b95/files/mp/public/6aa26c7ce0ac9a5ee05d2b95/453034b60_r1305_reshelve.diff"
echo "CURL_RC=$?"
P=$(shasum -a 256 /tmp/r1305_reshelve.diff | cut -d" " -f1)
echo "PATCH_SHA=$P"
if [ "$P" != "738f24aeab30a97c0b992fd2fdf70f01d5605cf28caa4222e5be3188b7f587fe" ]; then
  echo "PATCH-FAILED: patch sha mismatch - expected 738f24ae - nothing applied"
  exit 0
fi
M1=$(grep -c "R1305" /tmp/r1305_reshelve.diff)
M2=$(grep -c "R1306" /tmp/r1305_reshelve.diff)
M3=$(grep -c "R1307" /tmp/r1305_reshelve.diff)
M4=$(grep -c "reshtail2" /tmp/r1305_reshelve.diff)
M5=$(grep -c "TAIL DELIVERED" /tmp/r1305_reshelve.diff)
M6=$(grep -c "rem = s_ovl_size" /tmp/r1305_reshelve.diff)
M7=$(grep -c "bldprov" /tmp/r1305_reshelve.diff)
M8=$(grep -c "waitbr" /tmp/r1305_reshelve.diff)
echo "PATCH_MARKERS R1305=$M1 R1306=$M2 R1307=$M3 reshtail2=$M4 tail=$M5 remfix=$M6 bldprov=$M7 waitbr=$M8"
if [ "$M1" != "4" ] || [ "$M2" != "3" ] || [ "$M3" != "3" ] || [ "$M4" != "1" ] || [ "$M5" != "1" ] || [ "$M6" != "2" ] || [ "$M7" != "1" ] || [ "$M8" != "1" ]; then
  echo "MARKER-FAILED: expected R1305=4 R1306=3 R1307=3 reshtail2=1 tail=1 remfix=2 bldprov=1 waitbr=1 - nothing applied"
  exit 0
fi
cp -p runtime/runtime.c runtime/runtime.c.bak1305
if ! patch -p0 --dry-run runtime/runtime.c < /tmp/r1305_reshelve.diff; then
  echo "DRYRUN-FAILED: patch does not apply clean - nothing changed"
  exit 0
fi
if ! patch -p0 runtime/runtime.c < /tmp/r1305_reshelve.diff; then
  cp -p runtime/runtime.c.bak1305 runtime/runtime.c
  echo "APPLY-FAILED: restored backup - nothing run"
  exit 0
fi
N=$(shasum -a 256 runtime/runtime.c | cut -d" " -f1)
echo "NEW_SHA=$N"
if [ "$N" != "f21f91d17999f9b73b25f2f88affdff55952ae9ad80e7cd8c4a124691fc474da" ]; then
  echo "POST-APPLY-FAILED: patched tree sha mismatch (expected f21f91d1) - restored backup, nothing run"
  cp -p runtime/runtime.c.bak1305 runtime/runtime.c
  exit 0
fi
echo "PATCHED TREE VERIFIED (sandbox-parsed, sha-gated)"

echo "===PRESERVE205=== PRESERVE the existing run.log BEFORE the fresh run overwrites it (it holds the c204 receipts - the zero-blocked protocol run) - FAIL EXPLICIT"
TS=$(date +%Y%m%d_%H%M%S)
SNAP="runlog_preserve_c205_$TS"
if [ -f run.log ]; then
  mkdir -p "$SNAP"
  if ! cp -p run.log "$SNAP/run.log"; then echo "PRESERVE-FAILED: run.log copy failed - nothing run"; exit 0; fi
  if [ -f run.log.d ]; then cp -p run.log.d "$SNAP/run.log.d" 2>/dev/null || echo "run.log.d copy failed (non-fatal, noted)"; fi
  echo "PRESERVED: $SNAP/run.log sha=$(shasum -a 256 "$SNAP/run.log" | cut -c1-16) size=$(wc -c < "$SNAP/run.log") ts=$TS"
  echo "--- WHICH ERA IS THE PRESERVED LOG? (the c200 marker census - if the prior c200 run executed, its receipts are HERE)"
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
RUN_BUDGET_S=120 ./run.sh > /tmp/run205.txt 2>&1 &
RUNPID=$!
echo "LAUNCH-WALL $(date +%s)"
sleep 6
if ! kill -0 $RUNPID 2>/dev/null; then
  echo "RUN-DIED-EARLY: compile or launch failed - no captures, no stale artifacts"
  head -8 /tmp/run205.txt
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
tail -12 /tmp/run205.txt

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

echo "--- W50 EXCLUSION (Jos c205): the w50 capture holds the PREVIOUS run preserved tail + a stale 03:03 VRAM file - EXCLUDED from progress comparisons; w65/w80/w95 are this run only"
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
echo "===PROVX205=== Jos step 1: BUILD PROVENANCE - connect the gated source sha to the executed binary (the unchanged R1291 banner is inconclusive)"
echo "--- the compile-time-stamped provenance line (fresh timestamp = fresh compile of the R1305/R1306/R1307 source; unchanged across runs = STALE binary)"
grep -n "bldprov" run.log | head -4
echo "--- the executed-binary sha receipts (R1196) + the launch wall"
grep -n "executed-binary" run.log | head -4
grep -n "LAUNCH-WALL" /tmp/run205.txt | head -2
echo "===LOGDUP205=== Jos step 2: THE DUPLICATION QUESTION - logging pipeline duplicates output vs execution repeats (until resolved, tag counts are NOT reliable counts of deliveries, rescues, or restarts)"
echo "--- the three streams, sizes + sha (identical sha = same content, the pipeline may concatenate)"
wc -c run.log.raw run.log run.log.d 2>/dev/null
shasum -a 256 run.log.raw run.log run.log.d 2>/dev/null
echo "--- THE SEQ-35 DUPLICATION SPECIFICALLY (receipted at two line numbers with identical t+era in c204): count occurrences in EACH stream"
for f in run.log.raw run.log run.log.d; do echo "$f: $(grep -c "command 0x06 -> INT3 scheduled (event delivery) (n=35 seq=35" "$f" 2>/dev/null)"; done
echo "--- the exact-duplicate census (lines appearing more than once, top 12 by duplicate count)"
sort run.log.raw 2>/dev/null | uniq -c | sort -rn | awk "\$1 > 1" | head -12
echo "--- do the duplicated blocks sit ADJACENT (pipeline double-write) or FAR APART (execution repeat/second era)? line numbers of every seq=35 occurrence in run.log.raw"
grep -n "seq=35 t=17896" run.log.raw 2>/dev/null | head -6
grep -n "R495 carry-v3" run.log.raw 2>/dev/null | head -6
echo "===FAULTX205=== Jos step 4: THE FIRST FAULT AND FINAL EXIT of THIS run (the truncated digest does not show them; RUNSH_RC=0 is the wrapper result, NOT proof of a clean guest exit)"
echo "--- the first fault lines in the raw stream (segvdie/exithv/faultctx/segvrec/crashkit, first 6, line-numbered)"
grep -n -m 6 "segvdie\|exithv\|faultctx\|segvrec\|crashkit" run.log.raw 2>/dev/null | head -6
echo "--- the rungasp exit-status receipt (the guest exit door)"
grep -n "rungasp" run.log.raw 2>/dev/null | tail -4
echo "--- the final 30 lines of the raw stream (the era the run actually ended in)"
tail -30 run.log.raw 2>/dev/null
echo "===WAITBR205=== Jos step 3: THE WAIT-BRANCH RECEIPTS (LegacyCdDataWait actual return + caller branch operands in the same invocation - if ret==0 with FDFC==0+FE1C==0, the pre-movie-polling label is MISIDENTIFYING the stall)"
grep -c "waitbr" run.log
grep -n "waitbr" run.log | head -12
echo "--- the CHANGED-return moments (a value change is the decisive transition)"
grep -n "waitbr" run.log | tail -6
echo "===CHAIN205=== THE CAUSAL TEST ON THE 8-BYTE DELTA (Jos c204: the truncation becomes a proven cause only if restoring the missing bytes removes the failure under comparable conditions) - this run receipts the tail delivery AND the failure discriminators"
echo "--- THE REPAIRED-ARM DELIVERIES (R612 endgame release prints; watch cmd=02 at fe1c=10 - the R1304 class)"
grep -n "R612 endgame release" run.log | tail -16
echo "--- DISCRIMINATOR 1: THE TAIL-CONTENT RECEIPTS (destination bytes SHOWN - the last 8 payload bytes the -8u left stale)"
grep -c "reshtail2" run.log
grep -n "reshtail2" run.log | head -6
echo "--- DISCRIMINATOR 2: THE RE-SHELVE SIZE (must print the full table size now: 14360 for member 18, not 14352)"
grep -n "R495 carry-v3" run.log | head -4
echo "--- DISCRIMINATOR 3: THE FE04=109158 RE-REQUEST CADENCE (4 stamps in c204 = the module asking for its missing tail; the fix must stop the re-asks IF the truncation was the cause)"
grep -c "FE04=0x0001AA66" run.log
grep -n "READ ISSUED fn_80029690(file#=18" run.log | head -6
echo "--- DISCRIMINATOR 4: THE MOVIE ERA (mdec-writes=0 in every prior run; >0 = the movie play actually started)"
grep -n "mdec" run.log | head -8
grep -n "spu-writes.*mdec-writes" run.log | tail -3
echo "--- DISCRIMINATOR 5: THE WAITER COMPLETION (the pre-movie poll exit - full validation needs the waiter to CONCLUDE, not just delivery+consumption)"
grep -n "mvloop" run.log | tail -6
echo "--- DISCRIMINATOR 6: RESTARTS/ABORTS UNDER COMPARABLE CONDITIONS (2 bootmain + 1 abort-130 in c204; the fix must reduce these IF truncation was the cause)"
grep -c "bootmain\] boot main entered" run.log
grep -n "fn_80019ACC(130)" run.log | head -4
echo "--- DISCRIMINATOR 7: THE MOVIE FILE COMPLETION (the 8 sectors at 109158-109166 and the dest region)"
grep -n "R473 stalled-load COMPLETED\|file lba 109158" run.log | head -8
echo "--- THE DIRECTORY-READ PROGRESS (sector consumption rate - the c204 native run consumed LBA 0/1 at t=1s)"
grep -n "fldsec" run.log | tail -12
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
