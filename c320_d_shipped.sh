#!/bin/bash
# c320_force_probe.sh - READ-ONLY probe of cd_force_deliver_int1
# (NO patch, NO run) + forensic re-read of the c319 witness log.
# THE c319 VERDICT: the R1348 call FIRED post-serve but the
# delivery did not complete (pend=3, fe1c=1 unchanged; no
# pendclr, no FE1C walk, no ReadN). Candidates: (a) the R1181
# guards refused, (b) the R898 defer ran to a never-coming
# dispatch boundary, (c) delivered but the handler pair did not
# advance. THIS CYCLE: (1) sha gate; (2) dump the full function
# definition + guard block + receipt tags; (3) dump the proven
# call sites; (4) re-read the c319 witness log: the window after
# [wforce], plus why-string/forge/defer/deliver greps.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C320-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="687b335e2bd29812e99394aef378f7ca8eea545ab6d29a647a034a89a9bf588d"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1348 tree 687b335e - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1348 tree)"
echo "===DEF320=== the cd_force_deliver_int1 definition (guards + tags)"
python3 - <<'PYEOF'
lines = open("runtime/runtime.c", "rb").read().split(b"\n")
h = [i for i, l in enumerate(lines) if b"static void cd_force_deliver_int1(const char *why)" in l and b";" not in l]
print("DEF hits: %d" % len(h))
if h:
    i = h[0]
    # dump until the closing brace at col 0 after the opening
    j = i
    while j < len(lines) and lines[j].strip() != b"{":
        j += 1
    depth = 0; end = j
    for k in range(j, min(len(lines), j + 200)):
        depth += lines[k].count(b"{") - lines[k].count(b"}")
        if k > j and depth <= 0:
            end = k
            break
    for n in range(i, min(end + 2, i + 130)):
        print("%d: %s" % (n + 1, lines[n].decode("ascii", "replace")))
PYEOF
echo "===CALLS320=== the cd_force_deliver_int1 call sites (proven callers)"
python3 - <<'PYEOF'
lines = open("runtime/runtime.c", "rb").read().split(b"\n")
h = [i for i, l in enumerate(lines) if b"cd_force_deliver_int1(" in l and b"static void" not in l]
print("call sites: %d" % len(h))
for i in h[:6]:
    for j in range(max(0, i - 8), min(len(lines), i + 4)):
        print("%d: %s" % (j + 1, lines[j].decode("ascii", "replace")))
    print("----")
PYEOF
echo "===LOG320=== the c319 witness log: the post-call window + tag greps"
LOG="run.log"; [ -s "$LOG" ] || LOG="run.log.d"
W=$(ls -1d witness_c319_* 2>/dev/null | tail -1)
echo "WITNESS_DIR=$W"
if [ -n "$W" ] && [ -s "$W/run.log" ]; then LOG="$W/run.log"; fi
grep -n "wforce" "$LOG" | head -4
WF=$(grep -n "wforce" "$LOG" | head -1 | cut -d: -f1)
echo "WF_LINE=$WF"
if [ -n "$WF" ]; then
  echo "--- the 130-line window after [wforce] ---"
  awk -v s="$WF" -v e="$((WF+130))" 'NR>=s && NR<=e {print NR": "$0}' "$LOG" | head -140
fi
echo "--- why-string / guard-tag greps (whole log) ---"
grep -n "R1348 watcher SetLoc serve" "$LOG" | head -6
grep -in "forge\|defer\|R1181\|R898" "$LOG" | tail -24
grep -n "deliver" "$LOG" | tail -16
echo "===C320DONE=== probe complete - the refusing term of the direct delivery is receipted or the window names it"
