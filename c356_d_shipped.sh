#!/bin/bash
# c356_watchercode.sh - READ-ONLY extraction of the R1347
# watcher's branch code. NO patch, NO run. The c355 receipts:
# the watcher discards the file#14 re-request's LIVE Setloc ack
# as stale ([stalecd] fires at the freeze posture and DRAINS
# the pending) while the serve branch is never reached. THIS
# CYCLE: dump the stale-vs-serve discriminator verbatim -
# the branch code around the stalecd discard, stalecd-near,
# and wserve sites in the CURRENT runtime.c.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C356-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="ea90a9a404cdb7666eb50af50d92f38c14684bee9feb350291283d9704fc82c5"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1362 tree - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1362 tree)"
echo "===STALECD356=== the stale-discard branch (plus/minus 35 lines)"
LA=$(grep -n "stalecd. R1347 watcher-side stale discard" "$SRC" | head -1 | cut -d: -f1)
echo "STALECD_LINE=$LA"
if [ -n "$LA" ]; then
  S=$((LA-35)); [ $S -lt 1 ] && S=1
  E=$((LA+35))
  awk -v s="$S" -v e="$E" -v m="$LA" 'NR>=s && NR<=e { printf "%d%s\n", NR, (NR==m ? " <<<DISCARD-PRINT" : ""), $0 }' "$SRC"
else
  echo "STALECD SITE NOT FOUND"
fi
echo "===STALECDNEAR356=== the stalecd-near site (plus/minus 20 lines)"
LB=$(grep -n "stalecd-near" "$SRC" | head -1 | cut -d: -f1)
echo "STALECDNEAR_LINE=$LB"
if [ -n "$LB" ]; then
  S=$((LB-20)); [ $S -lt 1 ] && S=1
  E=$((LB+20))
  awk -v s="$S" -v e="$E" -v m="$LB" 'NR>=s && NR<=e { printf "%d%s\n", NR, (NR==m ? " <<<NEAR-PRINT" : ""), $0 }' "$SRC"
else
  echo "STALECDNEAR SITE NOT FOUND"
fi
echo "===WSERVE356=== the serve branch (plus/minus 25 lines)"
LC2=$(grep -n "wserve. R1347 watcher-side SetLoc serve" "$SRC" | head -1 | cut -d: -f1)
echo "WSERVE_LINE=$LC2"
if [ -n "$LC2" ]; then
  S=$((LC2-25)); [ $S -lt 1 ] && S=1
  E=$((LC2+25))
  awk -v s="$S" -v e="$E" -v m="$LC2" 'NR>=s && NR<=e { printf "%d%s\n", NR, (NR==m ? "<<<SERVE-PRINT" : ""), $0 }' "$SRC"
else
  echo "WSERVE SITE NOT FOUND"
fi
echo "===STALEVOCAB356=== every line mentioning stale in the watcher region"
grep -n "stale" "$SRC" | head -20
echo "===WENTRY356=== the R1362 camera placement (context, plus/minus 6)"
LW=$(grep -n "wentry. R1362 serve-site reached" "$SRC" | head -1 | cut -d: -f1)
echo "WENTRY_LINE=$LW"
if [ -n "$LW" ]; then
  S=$((LW-6)); [ $S -lt 1 ] && S=1
  E=$((LW+6))
  awk 'NR>=s && NR<=e { printf "%d %s\n", NR, $0 }' s="$S" e="$E" "$SRC"
fi
echo "===C356DONE=== the watcher discriminator is extracted - the fix designs from these lines"
