#!/bin/bash
# c327_tickpresence_probe.sh - READ-ONLY probe (NO patch, NO
# run): does the tick body run post-serve in the c326 witness?
# THE c326 VERDICT: the serve refilled the conversion budget
# (wconv 25421) but zero conversion receipts fired post-serve.
# Candidates: (a) the tick body does not run post-serve; (b)
# it runs but prints are governor-suppressed while the handler
# pair fails to consume. THIS CYCLE: (1) sha gate; (2) the
# wait-loop tick line numbers (any post-25421?); (3) the last
# conversion receipt; (4) the raw window 25415-25485; (5) the
# r861_out governor mechanics; (6) the mv-conv block location.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C327-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="6be94374b28c9f81a005522c546e39fe50dc17307e35d34481e9ed52837e1e36"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1350 tree 6be94374 - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1350 tree)"
W=$(ls -1d witness_c326_* 2>/dev/null | tail -1)
echo "WITNESS_DIR=$W"
LOG="$W/run.log"; [ -s "$LOG" ] || LOG="$W/run.log.d"
echo "LOG=$LOG"
echo "===TICK327=== wait-loop tick presence: count + last lines (any post-25421?)"
grep -c "wait-loop tick" "$LOG"
grep -n "wait-loop tick" "$LOG" | tail -8
echo "===CONV327=== the last conversion receipts"
grep -c "converting stuck" "$LOG"
grep -n "converting stuck" "$LOG" | tail -6
echo "===WINDOW327=== the raw window 25415-25485 (the [cd] channel post-serve)"
awk 'NR>=25415 && NR<=25485 {print NR": "$0}' "$LOG"
echo "===GOV327=== the r861_out governor mechanics"
grep -n "governor\|4096u\|% 4096" "$SRC" | head -10
python3 - <<'PYEOF'
lines = open("runtime/runtime.c", "rb").read().split(b"\n")
h = [i for i, l in enumerate(lines) if b"r861_out" in l and (b"#define" in l or b"void r861_out" in l or b"r861_out(const" in l)]
print("r861_out def/deffo hits: %d" % len(h))
for i in h[:2]:
    for j in range(max(0, i - 10), min(len(lines), i + 30)):
        print("%d: %s" % (j + 1, lines[j].decode("ascii", "replace")))
    print("----")
PYEOF
echo "===MVCONV327=== the mv-conv block location"
grep -n "mv-conv" "$SRC" | head -6
echo "===CDCOUNT327=== the [cd] tag receipts post-serve (what does the channel show)"
awk 'NR>25421 && /\[cd\]/ {print NR": "$0}' "$LOG" | head -12
awk 'NR>25421 && /\[cd\]/ {n++} END {print "total [cd] lines post-serve:", n+0}' "$LOG"
echo "===C327DONE=== probe complete - the tick-presence verdict is receipted"
