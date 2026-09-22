#!/bin/bash
# c409_heapanatomy.sh - READ-ONLY CENSUS. NO run, NO patch.
# The c408 verdict: the TRUE DEATH is the OLD c80/c283
# heap family at the deepest-ever point - the archive
# linker (via CD_sync, r31=80041BB0) was handed a GARBAGE
# RECORD ([lnkcam] #3 a0=FFFFFFFF; [heapinit] #7
# start=0xFFFFFFFC = the c80 next=0->cursor=-8 decode),
# the LZSS core (EPC 80032EB4) faulted on garbage r4,
# 3 computed-garbage recoveries, then all declined.
# Per the c353 discipline: stop at fault #1 and name the
# WRITER of the bad heap node before any patch. THIS PASS
# extracts: (1) the full [heapinit] timeline - was the
# region initializer ever run for the handed record; (2)
# all [lnkcam] entries - were #1/#2 valid, #3 garbage;
# (3) the five [segvrec] recovery sites; (4) the crashkit
# dump excerpts; (5) the [drvptr-heal] receipts - is the
# runtime's heal papering over a missing init; (6) the
# fault#1 context (the 80 receipts before it). R1377
# follows from these receipts only.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C409-FAILED: xenolift dir missing"; exit 1; }
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
echo "===HEAPINIT409=== the full heap-init timeline (region initializers: ever run for the handed record?)"
grep -n "heapinit" "$LOG" | head -20
echo "===LNKCAM409=== all archive-linker entries (valid vs garbage headers)"
grep -n "lnkcam" "$LOG" | head -10
echo "===SEGVDIE409=== the five recovery sites (sigsafe receipts)"
grep -n "segvrec" "$LOG" | head -10
echo "===FAULT1CTX409=== the 80 receipts before fault #1 (line 31085)"
S=$((31085-80)); [ $S -lt 1 ] && S=1
awk -v s="$S" -v e=31085 'NR>=s && NR<=e { print NR": "$0 }' "$LOG" | grep -v "asciiart\|lzss-fence\|mvloop\]" | head -40
echo "===CRASHKIT409=== the crashkit dumps (fault context, heap/record state)"
grep -n "crashkit\]" "$LOG" | head -10
CKL=$(grep -n "crashkit\] R777 poison-HALT" "$LOG" | head -1 | cut -d: -f1)
if [ -n "$CKL" ]; then
  awk -v s="$CKL" -v e="$((CKL+40))" 'NR>=s && NR<=e { print NR": "$0 }' "$LOG" | grep -v "asciiart" | head -30
fi
echo "===DRVHEAL409=== the runtime pointer-heal receipts (papering a missing init?)"
grep -n "drvptr-heal" "$LOG" | head -12
echo "===HEAPCALL409=== the MoveHeapAllocation / heap-walk receipts near the fault era"
grep -n "heapalloc\|MoveHeap\|ReleaseHeap\|heapwalk\|heapmap" "$LOG" | awk -F: '$1>=30000' | head -12
echo "===B2X409=== the exit-door fault-walk receipts"
grep -n "b2x\]\|exitdiag" "$LOG" | awk -F: '$1>=30900' | head -14
echo "===HLELZ409=== the LZSS HLE decode story in the render era (did native decodes run before the fault?)"
grep -n "lzss-x\] EXIT\|hle-lzss\|lzss-t\]" "$LOG" | awk -F: '$1>=28000' | head -12
echo "===C409DONE=== the fault#1 anatomy is receipted - R1377 follows from these receipts only"
