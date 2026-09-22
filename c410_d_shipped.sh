#!/bin/bash
# c410_soundheap.sh - READ-ONLY CENSUS. NO run, NO patch.
# The c409 verdict: fault#1 = the c217b/c283 SOUND-HEAP
# disease - g_SoundHeapHead 0x80059410 = NULL at fault
# (R966, chain broken), the free-sentinel mask 0x00200000
# consumed as the LZSS source, during the f15 expansion
# era. Per the c80 rule: NO speculative seeding - name
# the intended writer and why it did not run. THIS PASS
# extracts: (1) every receipt mentioning 59410 (was it
# EVER non-null this run? who reads it?); (2) the
# sound-module init story (SPU init receipts, sound
# members, the boot-era vs render-era); (3) the 80019524
# wipe chain (does it clear 59410?); (4) the consumer
# chain fns (8004B748/80047178/80046C58/8004B8BC - any
# symbol/label receipts); (5) the [chain] heap-walk family
# at fault time; (6) the frclash record-page repurposing
# start + extent. R1377 follows from these receipts only.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C410-FAILED: xenolift dir missing"; exit 1; }
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
echo "===HEAPHEAD410=== every 59410 receipt (was it EVER non-null? who reads/writes it?)"
grep -n "59410\|SoundHeap\|sound-heap" "$LOG" | head -25
echo "===SOUND410=== the sound-module init story (did the sound init ever run?)"
grep -n "spu\]\|sound module\|spumod\|SpuInit\|sndinit" "$LOG" | head -15
echo "===WIPE410=== the 80019524 wipe chain (does it clear 59410? what does it wipe?)"
grep -n "wipe\|hooks zeroed\|zeroed" "$LOG" | head -12
grep -n "80019524" "$LOG" | head -8
echo "===READER410=== the consumer chain fns at fault time (any symbol/label receipts)"
grep -n "8004B748\|80047178\|80046C58\|8004B8BC\|80046D28" "$LOG" | head -16
echo "===CHAIN410=== the MoveHeapAllocation family timeline (boot era vs render era)"
grep -n "chain\] MoveHeap" "$LOG" | head -6
grep -n "chain\] MoveHeap" "$LOG" | tail -6
echo "===FRCLASH410=== the record-page repurposing (when did it start? how far?)"
FC=$(grep -c "frclash\]" "$LOG" || true)
echo "frclash total: $FC"
FL=$(grep -n "frclash\]" "$LOG" | head -1 | cut -d: -f1)
echo "first frclash at line: $FL"
if [ -n "$FL" ]; then
  S=$((FL-6)); [ $S -lt 1 ] && S=1
  awk -v s="$S" -v e="$((FL+6))" 'NR>=s && NR<=e { print NR": "$0 }' "$LOG"
fi
echo "===F15410=== the f15 expansion era (which members installed, when)"
grep -n "f15\|F15" "$LOG" | grep -v "frclash\|instw" | head -12
echo "===EPOCH410=== the epoch + fault census (the state snapshot)"
grep -c "bootentry\] R710" "$LOG" || true
echo "computed-garbage $(grep -c "computed-garbage" "$LOG" || true)"
echo "===TAIL410=== the last 12 receipts (non-asciiart)"
awk -v s=$((TL-40)) -v e="$TL" 'NR>=s && NR<=e { print NR": "$0 }' "$LOG" | grep -v "asciiart\|lzss-fence" | head -14
echo "===C410DONE=== the sound-heap writer/reader census is receipted - R1377 follows from these receipts only"
