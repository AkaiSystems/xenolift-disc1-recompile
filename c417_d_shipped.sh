#!/bin/bash
# c417_cellcontracts.sh - READ-ONLY CENSUS. NO run, NO
# patch. The c416 verdict: the final spin's caller holds
# because (a) FE48=1 - NO guest-store receipt ever set it,
# the last known setter is OUR OWN R896-era sync-delivery
# (host-side), and NO clear path exists; (b) A22C=4 - the
# increments were RUNTIME-path writes (the R1280-era
# serve) and the GAME's own writer site (R1291) DECLINED;
# (c) the waitbr contract's three exit conditions all hold
# -> 'the caller branch is the stall'; (d) file#18's read
# completed cleanly (FDF8 wrapped to 0 at the game's own
# consumer) - the command ladder is exonerated. THIS PASS
# names the caller's polled contract from SOURCE + LOG:
# (1) every RUNTIME writer of 0x8004FE48 (the R896-era
# code + any clear path) with context; (2) every RUNTIME
# writer of 0x8006A22C (the R1280-era serve, the
# tblw-cited line 130407 region) with context; (3) the
# symbol names for both cells (symbol_addrs / decomp
# map); (4) the R1291 gate's decline condition (the
# source that declines the movq); (5) the R325 timeline
# cells' identity + any transitions in the log; (6) the
# waitbr R1306 receipts in the FINAL-SPIN era (after line
# 31373). NO behavior change - receipts only. R1378
# follows from these receipts only.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C417-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="6759e34359fdf33df2e78cfaf2c144194da718412f3d42cb022b12e87470a8bb"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1377 tree - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1377 tree)"
echo "===FE48SRC417=== every runtime writer of FE48 (the R896-era code + any clear path)"
grep -n "0x8004FE48" "$SRC" | head -12
FE=$(grep -n "0x8004FE48" "$SRC" | head -1 | cut -d: -f1)
if [ -n "$FE" ]; then
  echo "--- first FE48 site context (line $FE, -12/+15):"
  awk -v s=$((FE-12)) -v e=$((FE+15)) 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
fi
echo "===A22CSRC417=== every runtime writer of A22C (the R1280-era serve)"
grep -n "0x8006A22C" "$SRC" | head -12
A2=$(grep -n "0x8006A22C" "$SRC" | head -1 | cut -d: -f1)
if [ -n "$A2" ]; then
  echo "--- first A22C site context (line $A2, -12/+15):"
  awk -v s=$((A2-12)) -v e=$((A2+15)) 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
fi
echo "--- the tblw-cited line 130407 region (the runtime-path store mechanism):"
awk -v s=130395 -v e=130420 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
echo "===SYMS417=== the symbol names for both cells"
grep -rn "8004FE48\|8006A22C" symbol_addrs.txt decomp/ 2>/dev/null | head -8
grep -rn "FE48\|A22C" docs/*.md 2>/dev/null | head -6
echo "===R1291GATE417=== the A22C-site gate's decline condition (the source that declines the movq)"
R1=$(grep -n "R1291" "$SRC" | head -1 | cut -d: -f1)
if [ -n "$R1" ]; then
  awk -v s=$((R1-5)) -v e=$((R1+45)) 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
else
  echo "R1291 not found in runtime.c"
fi
echo "===R325CELLS417=== the timeline cells' identity + transitions"
grep -n "R325" "$SRC" | head -4
R3=$(grep -n "cntdn(77014)\|0x80057014" "$SRC" | head -1 | cut -d: -f1)
echo "runtime site for the 77014 cell: $R3"
echo "--- log transitions for the three timeline cells:"
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
grep -n "77014\|77448\|76F04" "$LOG" | grep -v "halt\]" | head -8
echo "===WAITBR417=== the waitbr receipts in the final-spin era (after line 31373)"
grep -n "waitbr" "$LOG" | awk -F: '$1 > 31373' | head -8
echo "===MOVPOLL417=== what does the movie-prep caller read? the loop-id fns' known readers"
grep -n "0x8004FE48" "$SRC" | wc -l
echo "===C417DONE=== the cell contracts are receipted - R1378 follows from these receipts only"
