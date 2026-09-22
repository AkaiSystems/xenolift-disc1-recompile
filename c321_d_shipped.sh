#!/bin/bash
# c321_frontguard_probe.sh - READ-ONLY probe: the frontguard
# receipts across all eras + the R494 guard terms + the trail
# cycles (pass-era vs tail).
# THE c320 VERDICT: the force delivery woke the game's event
# machinery but the tail game is cycling the ARCHIVE-QUEUE
# WALKER (getintr never in the trail), and R494 frontguard
# REVERTED two ctl-word writes to frontier records right before
# the Setloc - prime suspect: the guard's validity class is
# wrong for this write class.
# THIS CYCLE: (1) sha gate; (2) ALL frontguard receipts in the
# c319 witness log, line-numbered (which eras); (3) the R494
# guard block code (terms + validity class); (4) all [trail]
# receipts (pass-era cycles vs the tail cycle, getintr
# presence); (5) the pass-era frontier write receipts
# (bandhist/frontguard around the passes).
set -u
cd "$HOME/Downloads/xenolift" || { echo "C321-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="687b335e2bd29812e99394aef378f7ca8eea545ab6d29a647a034a89a9bf588d"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1348 tree 687b335e - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1348 tree)"
W=$(ls -1d witness_c319_* 2>/dev/null | tail -1)
echo "WITNESS_DIR=$W"
LOG="$W/run.log"
if [ ! -s "$LOG" ]; then LOG="$W/run.log.d"; fi
if [ ! -s "$LOG" ]; then LOG="run.log"; fi
if [ ! -s "$LOG" ]; then LOG="run.log.d"; fi
echo "LOG=$LOG"
echo "===FG321=== ALL frontguard receipts (which eras?)"
grep -c "frontguard" "$LOG"
grep -n "frontguard" "$LOG" | head -20
echo "===ERA321=== era anchors: the passes and the tail"
grep -n "cmdtl\] R533 #5 cmd 02->06\|wserve\]\|rungasp\|R806 process exit" "$LOG" | head -12
echo "===GUARD321=== the R494 guard block code"
python3 - <<'PYEOF'
lines = open("runtime/runtime.c", "rb").read().split(b"\n")
h = [i for i, l in enumerate(lines) if b"R494" in l and b"frontguard" in l.lower() or (b"R494" in l and b"REVERT" in l)]
h = sorted(set(h))
print("R494 hits: %d" % len(h))
if h:
    i = h[0]
    for j in range(max(0, i - 40), min(len(lines), i + 26)):
        print("%d: %s" % (j + 1, lines[j].decode("ascii", "replace")))
PYEOF
echo "===TRAIL321=== the trail receipts (pass-era vs tail cycles)"
grep -n "\[trail\]" "$LOG" | head -20
echo "===GETINTR321=== getintr/cooptick/evt receipts across eras"
grep -c "cooptick\|cooperative tick" "$LOG"
grep -n "cooperative tick" "$LOG" | head -10
echo "===PASSFG321=== frontier writes in the PASS eras (before line 24000)"
awk 'NR<24000 && /frontguard/ {print NR": "$0}' "$LOG" | head -10
grep -n "bandhist.*108933\|bandhist.*lba=1089" "$LOG" | head -8
echo "===C321DONE=== probe complete - the frontguard verdict comes from these receipts"
