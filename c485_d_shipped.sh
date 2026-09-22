#!/bin/bash
# c485_extract.sh - READ-ONLY CENSUS, NO RUN, NO BUILD,
# NO PATCH. The c483b verdict: the movie stream is
# HEALTHY (protocol-identical to boot; the Pause and
# FDF8=0 are normal stream steps). THE REAL FAULT:
# line 30040 [wildctx] R680 UNRESOLVED JUMP to
# 0x8009A2F8 - the movie module's own code
# (cur_fn=0x800739A0, +0x1B4 past its 800737EC entry)
# called into an UNEMITTED region with args = the
# 8009A2E0 4-word table. The init broke, the wait
# timed out, and the movie phase itself requested the
# menu fallback. RECEIPTS: (1) WILD485: every R680
# unresolved-jump receipt (all eras); (2) REGION485:
# is 0x8009A000-0x8009B000 emitted at all; (3) MOD6FN:
# the module-6 fn at 800739A0 - what builds the args;
# (4) MOMENT485: the raw fallback+entry+wild-jump
# moment (30000-30050); (5) FE20W485: the FE20 era-cell
# story. Fail-closed, tee'd to /tmp/c485_receipts.txt.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C485-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c485_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="d86f3deb57aed5b0921ab3a82867dea3a1e1d9960028e360bed8d9bdc90d45f8"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the R1387 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the R1387 tree)"
LOG="run.log"
if [ ! -s "$LOG" ]; then LOG="run.log.d"; fi
if [ ! -s "$LOG" ]; then echo "GATE-FAILED: no preserved run log"; exit 0; fi
echo "LOG=$LOG ($(wc -l < "$LOG" | tr -d " ") lines)"
D="disc1.c"
if [ ! -f "$D" ]; then echo "GATE-FAILED: disc1.c not found"; exit 0; fi
echo "===WILD485=== every R680 unresolved-jump receipt (all eras)"
grep -c -e "wildctx" "$LOG" | tr -d " " | sed "s/^/wildctx count: /"
grep -n -e "wildctx" "$LOG" | head -10
echo "--- the R680 camera in the runtime (what happens on unresolved):"
grep -n -e "R680" "$SRC" | head -6
echo "===REGION485=== is 0x8009A000-0x8009B000 emitted at all"
echo "--- function markers in the 0x8009A range (disc1.c):"
grep -c -e "0x8009A" "$D" | tr -d " " | sed "s/^/0x8009A refs: /"
grep -n -e "---------- 0x8009A" "$D" | head -8
echo "--- what emitted range covers 8009xxxx (nearest markers below 0x8009A2E0):"
grep -n -e "---------- 0x80099" -e "---------- 0x80098" -e "---------- 0x80097" "$D" | head -6
echo "--- the 8009A2E0 table refs in the emitted source:"
grep -n -e "8009A2E0" -e "8009A2F8" "$D" | head -8
echo "===MOD6FN485=== the module-6 fn at 800739A0 (what builds the 8009A2E0 args)"
LN=$(grep -n -e "0x800739A0 (function)" "$D" | head -1 | cut -d: -f1)
echo "marker at line $LN"
if [ -n "$LN" ]; then sed -n "${LN},$((LN+55))p" "$D" | head -57; else echo "(no 800739A0 marker - searching 800739xx labels:)"; grep -n -e "L_800739" "$D" | head -8; fi
echo "===MOMENT485=== the raw fallback+entry+wild-jump moment (log 29990-30050)"
awk 'NR>=29990 && NR<=30050 { print NR": "$0 }' "$LOG"
echo "===FE20W485=== the FE20 era-cell story (who set 3 vs 4)"
grep -n -e "0x8004FE20" "$LOG" | head -10
echo "--- the FE20 chg receipts:"
grep -n -e "FE20 " "$LOG" | head -6
echo "===C485DONE=== the wild-jump story + module-6 fn + the moment are in - the fix design follows from these only"
