#!/bin/bash
# c193v3 THE COMPLETE JOS v4 CAMERA SET, PLACEMENT CORRECTED, BASE GATE
# FIXED - R1291v4+WIN+THROTTLE (the v16 tree), cameras only, NO behavior
# change. v16 COMPLETES the last two Jos refinements on top of the
# placement-corrected v15: the [schdd] WIN RECEIPT (which invocation
# delivered, with the SAME sequence ID - the adjacent [cd] R6xx print
# names the winning branch) and the GATE-CHANGE THROTTLE (blocked
# decisions print on FIRST occurrence + on ANY GATE VALUE CHANGE,
# labeled GATE-CHANGE + 1-per-4096 identical repeats, so the decisive
# transition survives the log budget). THE FIRST
# c193 CYCLE FAILED ITS OWN DRIFT GATE (receipted): the fetched script still
# demanded the R1290 baseline while the patch builds on the R1291 tree the
# Mac runs - the outer SHA verified the script identity but not its
# baseline condition. NOTHING ran, no state change, no revert: this reship
# follows the Jos four-step order: (1) the patch is the v12->v15 DELTA
# against the preserved 57c45fda source, sandbox-verified to apply cleanly;
# (2) the baseline comparison and failure message carry the full R1291 hash
# 57c45fda; (3) the applied tree hashes 084b4ac4 exactly (verified on a
# temp copy); (4) script SHA + bootstrap regenerated. JOS c193 CORRECTIONS,
# ALL IN THE PATCH: (a) PLACEMENT - the [schdd] blocked receipt now sits
# AFTER ALL RELEASE BRANCHES DECLINE (a genuine post-ladder observation; a
# top-of-ladder print observes entry state - a different thing); (b)
# [movsite] - an UNCONDITIONAL A22C site-entry counter (first 8 + 1/65536,
# cap ~24 lines): zero [movq] hits does NOT prove A22C untouched - entries
# present + 0 movq hits = the GATE DECLINED; zero entries = the site ran
# COLD; (c) RESTRAINT - the 8-BYTE DELTA (14360 requested vs 14352
# re-shelved) REMAINS OPEN: a re-shelve receipt does not establish a
# complete correct 14360-byte destination; the member-18 ftab entry line +
# the R495 size arithmetic decide it (the read-only EXTRACT section prints
# both); (d) the 0x82 call at 80031DC8 is the latch-clear NORMAL
# resident-loop entry, not by itself a validation failure (Jos retraction
# accepted; the dispatch-era window still extracts its context). c193
# ESTABLISHES WHAT HAPPENED - it cannot yet guarantee a c194 gameplay fix.
# (prior c193v2 THE SEQUENCE-ID + DELIVERY-DECISION RECEIPTS + THE JOS READ-ONLY
# EXTRACTION - R1291v3, cameras only, NO behavior change, NO new doors.
# THE FIRST c193 CYCLE FAILED ITS OWN DRIFT GATE (receipted): my base gate
# still demanded the R1290 tree while the patch builds on the R1291 tree
# the Mac runs (57c45fda - the gate receipted the tree itself); NOTHING
# ran, no state change, FAIL EXPLICIT as designed. THIS reship fixes the
# gate AND adds Jos three-step read-only extraction BEFORE the fresh run:
# (1) VERIFY the [schdw]/[schdd] instrumentation status in the PRESERVED
# c192 log (expected ZERO receipts - the c192 run used the v1 movq patch;
# the v14 instrumentation ships HERE, so absence in c192 is the artifact,
# not absence of the wedge); (2) EXTRACT the context around the earliest
# fn_80019ACC(130) from 80031DC8 - the c187 decode: L_80031DA8 reads the
# latch gp+0x1C0, latch==0 -> r4=0x82 -> fn_80019ACC = THE GAME RESIDENT
# MAIN LOOP entered in its NORMAL game mode - Jos question: does the
# movie stall start only AFTER this pass, i.e. is the stall downstream of
# a failure INSIDE the resident loop pass; (3) CORRELATE file#18: the
# 14360-byte FDF8 at issue vs the 14352-byte R495 re-shelve - the 8-byte
# difference gets an explicit source-level receipt (the R495 size
# arithmetic printed from the SHIPPED tree), not an assumption. JOS
# VERDICT ADOPTED: the scheduler stall is real but may be DOWNSTREAM of
# the earlier failure; establish why the error dispatch happens before
# deciding that releasing a scheduled response unlocks gameplay. THE c192
# VERDICT, receipted: (1) THE DEST QUESTION IS ANSWERED - DEST-HELD: the
# defib6 R495 carry-v3 receipted "full re-shelve 14352B -> 0x801EF300
# (file lba 109158, whole-file native layout)" - the movie module buffer
# HOLDS file#18 data; the FE1C=10 wait is the movie PLAY protocol, not a
# delivery fault. (2) The movq camera at the A22C site fired ZERO - the
# c174 lesson one level deeper: the movie era does NOT touch A22C (the
# pump ran 77K+ rounds through the wedge; pumpcam/mvloop/[chg] FE1C are
# the hot receipts) - camera site cold, not posture absent. (3) The
# wedge recurred IDENTICALLY: seek=3, FE04=0x1AA66, FDF8=0, act=0,
# pend=0, stale sched=1, FE1C=10, A22C=5, GetStat polls; the game own
# timeout cleared it ~40s late, then FE1C oscillated 0<->9 (the R1209
# queued-wait class with FE04!=0) and the boot restarted (Module-6
# validation spike, 7 dispatcher calls). JOS c192 SPEC IMPLEMENTED: every
# scheduled response gets a SEQUENCE ID printed on SET (seq + wall
# timestamp + command), on CLEAR (all 11 cd_scheduled clear sites, first
# -eval: seq, timestamp, AND resp pos/n = runtime-delivered vs
# guest-popped acknowledgment - a CLEAR may establish only the former),
# and at THE DELIVERY DECISION (new [schdd] camera at the top of the
# release gate ladder: when a response remains scheduled after all gates
# evaluate, it prints every gate term - cmd, fe1c, FDF8, FE04, seek,
# FDFC, FE08, resp, A22C - first 8 calls then 1/4096; ABSENT schdd while
# SET prints continue = the delivery path itself ran cold = a different
# missing transition). PASS = receipts only: the seq chain SET ->
# (schdd blocked-with-terms) -> CLEAR/none, deciding Jos queued-never
# -started vs completed-flag-never-cleared for the c194 lasting fix.
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

echo "===PRE193=== identity, tree drift gate (R1291 baseline 57c45fda - the tree the c192 cycle receipted)"
T=$(shasum -a 256 runtime/runtime.c | cut -d" " -f1)
echo "TREE_SHA=$T"
BASE="57c45fdaa475c7d75576b91a197febe0af42743c24c02584a7569921e435425c"
if [ "$T" != "$BASE" ]; then
  echo "DRIFT-FAILED: tree is not the receipted R1291 baseline 57c45fda - nothing run"
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
echo "===PATCH193=== fetch, verify, apply the R1291v3 sequence-id patch - marker + post-apply sha gates, FAIL EXPLICIT"
curl -sSL -m 30 -o /tmp/r1291_movq.diff "https://base44.app/api/apps/6aa26c7ce0ac9a5ee05d2b95/files/mp/public/6aa26c7ce0ac9a5ee05d2b95/1a702d708_r1294_full.diff"
echo "CURL_RC=$?"
P=$(shasum -a 256 /tmp/r1291_movq.diff | cut -d" " -f1)
echo "PATCH_SHA=$P"
if [ "$P" != "3c1acf09aec0bcb9b7551280ef1a41c7fe5b90a984cfd76b97988ef28dee1693" ]; then
  echo "PATCH-VALID-FAILED: sha mismatch - nothing applied, nothing run"
  exit 0
fi
M1=$(grep -c "R1291v4" /tmp/r1291_movq.diff)
M2=$(grep -c "R1294" /tmp/r1291_movq.diff)
M3=$(grep -c "schdd" /tmp/r1291_movq.diff)
M4=$(grep -c "schdw" /tmp/r1291_movq.diff)
M5=$(grep -c "CLEAR site" /tmp/r1291_movq.diff)
M6=$(grep -c "movsite" /tmp/r1291_movq.diff)
M7=$(grep -c "delivery WIN" /tmp/r1291_movq.diff)
M8=$(grep -c "GATE-CHANGE" /tmp/r1291_movq.diff)
echo "PATCH_MARKERS R1291v4=$M1 R1294=$M2 schdd=$M3 schdw=$M4 CLEAR_site=$M5 movsite=$M6 WIN=$M7 GATE-CHANGE=$M8"
if [ "$M1" != "3" ] || [ "$M2" != "3" ] || [ "$M3" != "13" ] || [ "$M4" != "12" ] || [ "$M5" != "11" ] || [ "$M6" != "4" ] || [ "$M7" != "1" ] || [ "$M8" != "2" ]; then
  echo "MARKER-FAILED: expected R1291v4=3 R1294=3 schdd=13 schdw=12 CLEAR_site=11 movsite=4 WIN=1 GATE-CHANGE=2 - nothing applied"
  exit 0
fi
cp -p runtime/runtime.c runtime/runtime.c.bak1291
if ! patch -p0 --dry-run runtime/runtime.c < /tmp/r1291_movq.diff; then
  echo "DRYRUN-FAILED: patch does not apply cleanly - nothing changed"
  exit 0
fi
if ! patch -p0 runtime/runtime.c < /tmp/r1291_movq.diff; then
  cp -p runtime/runtime.c.bak1291 runtime/runtime.c
  echo "APPLY-FAILED: restored backup, nothing run"
  exit 0
fi
N=$(shasum -a 256 runtime/runtime.c | cut -d" " -f1)
echo "NEW_SHA=$N"
if [ "$N" != "928f393dd2545952b02a73dc9cd3e8c6da88e3004b5a85320146085f9872abf2" ]; then
  cp -p runtime/runtime.c.bak1291 runtime/runtime.c
  echo "POST-APPLY-FAILED: patched tree sha mismatch (expected 928f393d) - restored backup, nothing run"
  exit 0
fi
echo "PATCHED TREE VERIFIED (sandbox-parsed, sha-gated)"

echo "===RUN193=== the 120s receipt run - alive-guarded captures, live-tail correlation"
RUN_BUDGET_S=120 ./run.sh > /tmp/run193.txt 2>&1 &
RUNPID=$!
echo "LAUNCH-WALL $(date +%s)"
sleep 6
if ! kill -0 $RUNPID 2>/dev/null; then
  echo "RUN-DIED-EARLY: compile or launch failed - no captures, no stale artifacts"
  head -8 /tmp/run193.txt
  wait $RUNPID
  echo "RUNSH_RC=$?"
  echo "===END193==="
  exit 0
fi
LC_ALL=C grep -a -o "runtime build R[0-9]*" xenogears_boot | head -1
LV_B="vram_live.bin"
LV_M="vram_live.meta"
SNAP=$(mktemp -d /tmp/xl193.XXXXXX)
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
tail -12 /tmp/run193.txt

echo "===SHOTS193=== render with error retention, verify, preserve"
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

echo "===STORM193=== THE GOVERNOR VERDICT - the storm must stay tamed (6.6MB class last run)"
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
echo "===SCHDD193=== THE DELIVERY-DECISION RECEIPTS - the seq chain names the missing transition"
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
echo "===MOVQ193=== the A22C-site movq camera (its receipt count now interpretable via the movsite census)"
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
echo "===FETCH193=== the fetch trace"
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
echo "===PROV193=== provenance"
LC_ALL=C grep -a -o "runtime build R[0-9]*" run.log | head -1
wc -l run.log
cp -p run.log run.log.c193
shasum -a 256 run.log run.log.c193 runtime/runtime.c
echo "===PNG193=== THE IMAGE TRANSFER - small renders, sha-verified, budget-bounded, LAST so the census always lands"
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

echo "===END193==="
