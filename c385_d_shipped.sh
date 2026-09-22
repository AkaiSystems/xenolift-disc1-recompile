#!/bin/bash
# c385_f14story.sh - READ-ONLY CENSUS of the FRESH c384 log.
# NO run, NO patch. The c384 milestone: the game reached
# FILE#14'S READ NATIVELY (READ ISSUED file#=14 dst=801DD680
# FE04=108933 FDF8=125304 at line 11042, twice) - but the
# R1366 carry never fired (rescue-path only, the native serve
# bypasses it), the HLE decode FAILED (prod=-1) at 12768,
# 300 lzss-runaway, and the boot cycled. THE CENSUS GAP: no
# grep covered LBA 1089xx - unknown whether the sectors
# served. THIS PASS: the complete file#14 story from the
# existing log.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C385-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="52566422c865ec549026ce84b82e19a568b61b0cdd1e78984656a5b55cc437f2"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1367 tree - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1367 tree)"
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
if [ ! -s "$LOG" ]; then echo "TREE-ROOT-LOG-MISSING"; exit 0; fi
echo "AUTHORITATIVE LOG = $LOG ($(wc -l < "$LOG" | tr -d ' ') lines)"
echo "===F14SECT385=== did file#14's sectors serve? (LBA 108933-108994)"
grep -n "sector LBA 1089" "$LOG" | head -12
echo "count: $(grep -c "sector LBA 1089" "$LOG" || true)"
grep -n "LBA 108933" "$LOG" | head -10
echo "===F14DRAIN385=== the 125304 drain story"
grep -n "125304\|0001E978\|0x1E978" "$LOG" | head -14
echo "===F14UNPACK385=== the unpack camera entries (a0/a1 near the file-14 dest)"
grep -n "unpackw\]" "$LOG" | head -14
echo "===LZCAM385=== the core-entry camera (in[0] = the buffer's first word)"
grep -n "lzsscam\]" "$LOG" | head -14
echo "===DECODEFAIL385=== the decode-FAILED context (20 lines around 12768)"
awk 'NR>=12750 && NR<=12790 { print NR": "$0 }' "$LOG"
echo "===RUNAWAY385=== the runaway receipts (first 4 + the frontier)"
grep -n "lzss-runaway" "$LOG" | head -4
echo "===CARRY385=== the carry/rescue family (any fire at the file-14 era?)"
grep -n "carry-v3\|R489\|PROMOTE\|defib6" "$LOG" | head -10
echo "===EPOCH385=== the boot epoch count (how many bootmain entries?)"
grep -n "bootentry\]\|bootmain\|d2door\] R1235 era reset" "$LOG" | head -10
echo "===F14WINDOW385=== the 40 lines after the first file#14 READ ISSUE (11042)"
awk 'NR>=11042 && NR<=11082 { print NR": "$0 }' "$LOG"
echo "===F18FENCE385=== the op#10 fence storm (src=801EF300 = file#18's dest) - when did it arm?"
grep -n "fencelife\|lzss_armed\|fence.*armed\|op#10" "$LOG" | head -6
echo "===C385DONE=== the file#14 story is receipted"
