#!/bin/bash
# c411_trigger.sh - READ-ONLY CENSUS. NO run, NO patch.
# The c410 verdict: TWO DEFECTS. (A) PRIMARY - the
# epoch-3 trigger fault that ENDED the ~113s render era
# (~line 30900, not one of the 3 computed-garbage faults;
# lead: park ring reqF15=A0000000 at 30780) -
# UNIDENTIFIED. (B) the fault-recovery restart path
# (epochs 3-8, b2x re-entry) re-wipes the sound-heap head
# and never re-runs SoundInitialize -> the null-chain
# death spiral. Per c353: stop at the FIRST failure - name
# (A). THIS PASS extracts: (1) the 120 receipts before the
# epoch-3 bootentry (line 30909) - the trigger fault; (2)
# the park/reqF15 garbage story; (3) the b2x/R1216/R692
# recovery machinery receipts; (4) the sndinit/R966/R1012
# hook sites in runtime.c + symbol_addrs for the
# SoundInitialize fn address (for repair B); (5) whether
# epochs 4-8 share one recovery path. R1377 follows from
# these receipts only.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C411-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="f92a451cacc252da4b9e13ea00bc2ebbc8ae8c83716753023fd7f8e631115484"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1376 tree - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1376 tree)"
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
if [ ! -s "$LOG" ]; then echo "LOG-MISSING: cannot census"; exit 0; fi
TL=$(wc -l < "$LOG" | tr -d ' ')
echo "AUTHORITATIVE LOG = $LOG ($TL lines)"
echo "===TRIGGER411=== the 120 receipts before the epoch-3 bootentry (line 30909) - THE PRIMARY FAULT"
awk -v s=30790 -v e=30909 'NR>=s && NR<=e { print NR": "$0 }' "$LOG" | grep -v "asciiart" | head -60
echo "===REQF15411=== the reqF15 garbage story (the A0000000 lead)"
grep -n "reqF15\|park\] fsm ring" "$LOG" | head -8
echo "===RESTARTPATH411=== the b2x/R1216/R692 recovery machinery (where repair B would hook)"
grep -n "b2x\]\|R1216\|R692 door\|re-entry hygiene" "$LOG" | head -12
echo "===SNDADDR411=== the SoundInitialize fn address (repair B's target)"
grep -n "SoundInitialize\|SoundHeapInitialize" runtime/symbol_addrs.txt 2>/dev/null | head -6
grep -rn "SoundInitialize\|SoundHeapInitialize" runtime/*.txt runtime/*.json 2>/dev/null | grep -v "\.md" | head -8
echo "--- the R966/R1012 camera hook sites in runtime.c:"
grep -n "sndinit\|SoundInitialize entry\|SoundHeapInitialize CALLED" "$SRC" | head -8
echo "===EPOCHS411=== do epochs 4-8 share one recovery path? (bootentry r31 census)"
grep -n "bootentry\] R710" "$LOG" | tail -6
echo "===BOOTWIPE411=== does every bootentry at 80019524 wipe 59410? (the wipe-vs-init ledger)"
grep -n "shhead\] R1334\|irqc\] 0x80059410" "$LOG" | head -12
echo "===FAULTS411=== the census"
grep -c "bootentry\] R710" "$LOG" || true
echo "computed-garbage $(grep -c "computed-garbage" "$LOG" || true)"
echo "===TAIL411=== last 10 receipts (non-asciiart)"
awk -v s=$((TL-30)) -v e="$TL" 'NR>=s && NR<=e { print NR": "$0 }' "$LOG" | grep -v "asciiart\|lzss-fence" | head -12
echo "===C411DONE=== the epoch-3 trigger + repair-B machinery are receipted - R1377 follows from these receipts only"
