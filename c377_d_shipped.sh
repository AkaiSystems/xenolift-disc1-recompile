#!/bin/bash
# c377_freshread.sh - READ-ONLY. NO patch, NO run. The c376
# lesson: the digest read the STALE c368 witness snapshot -
# run.sh's fresh output lands in the TREE-ROOT run.log. The
# R1366 whole-member patch is LANDED (tree = the R1366 tree,
# parse OK, run executed the full window). THIS PASS: read
# the FRESH tree-root run.log and receipt the real R1366
# story - did the whole-member carry fire, did the HLE gate
# engage (expanded=260862), did the guest exit clean, did
# the install chain proceed, what is the fault census and
# exit status.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C377-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="13bc3bafa00d1cb05ddb1496adb335b94c3a49658a5206c2f4f74bd2d7b6c104"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then
  echo "TREE-NOTE: runtime.c is not the R1366 tree (patched c376 tree expected). The fresh-run census below may be from a different tree. Proceeding read-only."
else
  echo "BASELINE_VERIFIED (the R1366 tree, patched c376)"
fi
echo "===FRESHLOG377=== the tree-root log freshness"
date
ls -la run.log run.log.d 2>/dev/null
ls -la /tmp/run_full_c376.txt 2>/dev/null || echo "run_full_c376.txt absent"
echo "===RUNFULL377=== the c376 console capture (build + launch tail)"
tail -30 /tmp/run_full_c376.txt 2>/dev/null || echo "no console capture"
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
if [ ! -s "$LOG" ]; then echo "TREE-ROOT-LOG-MISSING"; exit 0; fi
echo "AUTHORITATIVE LOG = $LOG ($(wc -l < "$LOG" | tr -d ' ') lines)"
echo "===R1366RECEIPTS377=== the whole-member fires"
grep -n "R1366" "$LOG" | head -8
echo "===REHT377=== the alignment receipts (dest==header expected now)"
grep -n "reshtail" "$LOG" | head -8
echo "===PROMOTE377=== the carry promote tail"
grep -n "carry PROMOTE\|R495 carry-v3\|R473 stalled-load COMPLETED" "$LOG" | tail -8
echo "===LZHLE377=== the HLE decode receipts (file-14 = src 801DD680, expanded 260862)"
grep -n "lzss-hle" "$LOG" | head -14
echo "===LZEX377=== the guest exit shapes"
grep -n "lzss-x" "$LOG" | head -14
echo "===R1320w377=== the zero-write era (dest[0:4] zeroed after decode)"
grep -n "R1320\|zero-read armed" "$LOG" | tail -6
echo "===UNPACK377=== the unpack entries"
grep -n "unpackw\] R1001" "$LOG" | tail -8
echo "===LZCAM377=== the core entry camera (file-14 posture)"
grep -n "lzsscam\] R1251 core entry" "$LOG" | tail -6
echo "===FLDSTATE377=== the state story"
grep -n "statetbl\] R1104\|coordw\] R1000\|bankheal\|pFnMain" "$LOG" | tail -12
echo "===CMDTL377=== the ladder tail"
grep -n "cmdtl\]" "$LOG" | tail -10
echo "===FAULTS377=== the fault census (fresh log)"
echo "computed-garbage $(grep -c "computed-garbage" "$LOG" || true)"
echo "firstfault $(grep -c "firstfault\] R1172 BEGIN" "$LOG" || true)"
echo "lzss-runaway $(grep -c "lzss-runaway" "$LOG" || true)"
echo "segvdie $(grep -c "segvdie" "$LOG" || true)"
echo "===VIS377=== the exit + gpu story (fresh log)"
grep -n "rungasp" "$LOG" | tail -4
grep -n "gpufin\|gp0_words" "$LOG" | tail -4
grep -n "screen\] R693 snap" "$LOG" | tail -3
echo "===SECTORS377=== the file-14 sector serve"
grep -n "sector LBA 108933" "$LOG" | head -4
echo "===BOOT377=== the boot era receipts (fresh-run confirmation)"
grep -n "bootmain\] boot main entered\|epoch=" "$LOG" | head -6
echo "===C377DONE=== the fresh R1366 story is receipted"
