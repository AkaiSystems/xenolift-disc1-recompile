#!/bin/bash
# c349_revert.sh - REVERT R1359 (the c348 receipts: the cmd-09
# read_active clear broke the boot - exit 99 x2, zero cmdtl
# ladder, 156 sectors vs 349, empty screen). Restore the
# pristine R1358 tree, verify by witness, and extract the
# death chain from the c348 witness for the record.
# R1360 (next cycle) reships the clear ERA-GATED on
# cd_seek_lba >= 108933u (every boot 09 sits below it).
set -u
cd "$HOME/Downloads/xenolift" || { echo "C349-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT_BAD="488666614c299d784c89a70077060ba7318b1cb5e7f836b4686e6a439f103f5f"
EXPECT_GOOD="37a3790a5e6d5e2daebddc6cb9dc67d6bc264bcdff459198f487b30803d5b92a"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT_BAD" ]; then
  if [ "$SS" = "$EXPECT_GOOD" ]; then echo "ALREADY-REVERTED (the R1358 tree) - nothing to restore"; else
  echo "GATE-FAILED: runtime.c is neither the R1359 regression nor the R1358 baseline - refusing, nothing done"; exit 0; fi
else
  PRE="patch_c348_20260917_132533/runtime.c.pre"
  if [ ! -f "$PRE" ]; then echo "REVERT-FAILED: the preserved pre file is missing - nothing done"; exit 0; fi
  PSHA=$(shasum -a 256 "$PRE" | cut -d" " -f1)
  echo "PRE_SHA=$PSHA"
  if [ "$PSHA" != "$EXPECT_GOOD" ]; then echo "REVERT-FAILED: the preserved pre file is not the R1358 baseline - nothing done"; exit 0; fi
  cp -p "$PRE" "$SRC"
  S2=$(shasum -a 256 "$SRC" | cut -d" " -f1)
  echo "RESTORED_SHA=$S2"
  if [ "$S2" != "$EXPECT_GOOD" ]; then echo "REVERT-FAILED: restore did not land the R1358 baseline"; exit 0; fi
  echo "REVERTED (the pristine R1358 tree restored)"
fi
clang -fsyntax-only -std=gnu99 "$SRC" 2>/dev/null; PRC=$?
echo "PARSE_RC=$PRC"
if [ "$PRC" != "0" ]; then echo "PARSE-FAILED - the reverted tree does not parse"; exit 0; fi
echo "PARSE-OK"
TS=$(date +%Y%m%d_%H%M%S)
echo "===RUN349=== the reverted R1358 build, 90s budget, first-fault stop"
XENOLIFT_FIRSTFAULT_STOP=1 RUN_BUDGET_S=90 bash run.sh > /tmp/run_full_c349.txt 2>&1; RRC=$?
echo "RUN_RC=$RRC"
WDIR="witness_c349_$TS"; mkdir -p "$WDIR"
for f in run.log run.log.d; do [ -f "$f" ] && cp -p "$f" "$WDIR/$f"; done
cp -p /tmp/run_full_c349.txt "$WDIR/run_full.txt"
echo "WITNESS=$WDIR"
LOG="run.log"; [ -s "$LOG" ] || LOG="run.log.d"
echo "===RESTORECHK349=== restoration evidence (the R1358 receipts must be back)"
grep -n "cmdtl" "$LOG" | tail -6
grep -c "sector LBA" "$LOG"
grep -n "f15 request stamped" "$LOG" | tail -2
grep -n "wgen.*pass complete" "$LOG" | tail -2
echo "===FAULT349=== fault census"
grep -c "computed-garbage" "$LOG"
echo "===VIS349=== run tail + gpu census"
grep -n "rungasp" "$LOG" | tail -2
grep -n "gpufin\|gp0_words" "$LOG" | tail -2
grep -n "nonblank" "$LOG" | tail -3
echo "===DEATHCHAIN349=== the c348 death chain (for the record)"
OLDDIR="witness_c348_20260917_132533"
OLOG="$OLDDIR/run.log"
[ -s "$OLOG" ] || OLOG="$OLDDIR/run.log.d"
if [ -s "$OLOG" ]; then
  DL=$(grep -n "rungasp" "$OLOG" | head -1 | cut -d: -f1)
  echo "FIRST_EXIT99_LINE=$DL"
  if [ -n "$DL" ]; then
    S=$((DL-14)); E=$((DL+2))
    awk -v s="$S" -v e="$E" 'NR>=s && NR<=e' "$OLOG"
  fi
  echo "--- the R1359 fire context (line 5524, before/after) ---"
  awk 'NR>=5517 && NR<=5533' "$OLOG"
  echo "--- the abort/exitdiag receipts in the c348 log ---"
  grep -n "exitdiag\|abort" "$OLOG" | head -8
else
  echo "C348-WITNESS-MISSING (death-chain extraction skipped)"
fi
echo "===C349DONE=== revert complete - restoration verified by these receipts"
