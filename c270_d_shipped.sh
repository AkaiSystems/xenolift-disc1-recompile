#!/bin/bash
# c270_gate_srcdump.sh - READ-ONLY source dump: the byte-exact gates
# for the f15 decision. THE c269 FAIL-EXPLICIT catch: the one-token
# anchor 108900u appears 26x - patch refused, tree SAFE at 513eb593,
# no run. THE ACCIDENTAL GOLD from the occurrence dump: (1) the true
# mvdoor band is the two-term: cd_seek_lba >= 108700u && cd_seek_lba
# <= 108900u (offset 60305, unique); (2) THE TREE ALREADY CONTAINS
# TWO PURPOSE-BUILT f15 FEEDERS that both decline at this wedge: the
# ring feeder (f15_lba=108997u, R591 family, batch needs ~45 ring
# sectors) and the FULL-DISC-STREAM feeder (lba 108995..109040,
# the FULL f15 stream straight from the disc, 46 sectors, into the
# consumer). WHY THEY DECLINE is now the cheapest decisive receipt.
# THIS CYCLE dumps (no patch, no compile, no run): the R887 mvdoor
# gate block; the FE48(5F) term + every 8005FE48 occurrence; both
# f15 feeder gate blocks; the defib6 gate; AND greps the CURRENT
# run.log for each dumped block's own receipt tags (did the feeders
# evaluate and decline, or never run?).
set -u
cd "$HOME/Downloads/xenolift" || { echo "C270-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
LOG="run.log"
EXPECT="513eb593ec5fcf407a08f0b4072c6670a52c963a61af38e4a2564cbb573ffbd4"
if [ ! -s "$SRC" ]; then echo "C270-FAILED: runtime/runtime.c missing"; exit 1; fi
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1329 tree 513eb593 - refusing a foreign tree"; exit 0; fi
echo "BASELINE_VERIFIED (the R1329 tree, unchanged by the c269 refusal)"
if [ -s "$LOG" ]; then echo "LOG_SHA=$(shasum -a 256 "$LOG" | cut -d" " -f1)"; else echo "LOG_SHA=none (no run.log present)"; fi

dumpblock() {
  NAME="$1"; PAT="$2"; BEFORE="$3"; AFTER="$4"
  L=$(grep -n "$PAT" "$SRC" | head -1 | cut -d: -f1)
  echo "=== $NAME (anchor line $L)==="
  if [ -n "$L" ] && [ "$L" -gt 0 ] 2>/dev/null; then
    S=$((L-BEFORE)); [ "$S" -lt 1 ] && S=1
    E=$((L+AFTER))
    sed -n "${S},${E}p" "$SRC"
    echo "--- tags in this block, and their count in run.log:"
    for T in $(sed -n "${S},${E}p" "$SRC" | grep -o "\[[a-z0-9]*\]" | sort -u | head -6); do
      echo "  tag $T : run.log lines = $(grep -c -F "$T" "$LOG" 2>/dev/null || echo 0)"
    done
  else
    echo "ANCHOR NOT FOUND"
  fi
}

dumpblock "MDOOR270 the R887 mvdoor gate" "cd_seek_lba >= 108700u && cd_seek_lba <= 108900u" 40 14
dumpblock "F15RING270 the ring feeder gate" "f15_lba = 108997u" 40 26
dumpblock "F15FULL270 the full-stream feeder gate" "lba = 108995u; lba <= 109040u" 46 22
dumpblock "DEFIB270 the defib6 gate" "defib6" 8 26
echo "=== FE48T270 every 8005FE48 occurrence in the tree ==="
grep -n "8005FE48" "$SRC" | head -12
echo "=== FE48LOG270 the FE48(5F) writers in run.log (any hook/chg receipts) ==="
grep -n "8005FE48\|FE48(5F)" "$LOG" 2>/dev/null | head -8
echo "=== C270DONE=== gate source dump complete - the f15 door decision is made from these receipts"
