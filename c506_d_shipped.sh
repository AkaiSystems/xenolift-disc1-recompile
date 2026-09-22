#!/bin/bash
# c506_extract.sh - READ-ONLY LIFECYCLE TRACE, NO RUN, NO
# BUILD, NO PATCH. The c505 census verdict: the live module
# window is NOT code (the words around the entry decode to
# nonsense opcodes; the emit ref at the same offset is a
# perfect boot-era prologue), and lzss #4 receipts the
# cause one step earlier: the module-6 unpack ran from
# src=0x801EF300 with first16 = ALL ZEROS - file#18's load
# destination held NO bytes at unpack time. The gdesc
# table, the dispatch chain, the guard, and the interpreter
# all executed correctly on garbage-in. THE QUESTION: who
# zeroed 0x801EF300 between the file#18 read (FDF8=14360,
# READ ISSUED dst=0x801EF300) and the unpack - or did the
# bytes ever land? SUSPECTS (receipted classes): the
# reshtail 8-byte truncation (14352 vs 14360), the stomp
# fill class (-1 writes across walk/archive cells), or a
# heap release wiping the buffer (0x801EF300 may sit in a
# heap region; ReleaseAllHeapBlocks is a known zeroer).
# THIS TRACE receipts: (1) every log line naming 801EF300;
# (2) every cd-dma delivery into the buffer; (3) the
# read-completion -> unpack timeline (the key families,
# line-numbered); (4) the reshtail receipts; (5) the stomp
# + heap-release receipts; (6) the heap map that would
# claim 0x801EF300. Fail-closed, tee'd to
# /tmp/c506_receipts.txt. Pure-ASCII output.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C506-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c506_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="13aab535963b12c3ff0515d0c2892e8d7625327afa09a3569ae1f2d7b3e1c5d4"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the c504 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the c504 tree with the landed interpreter)"
LOG="run.log"
if [ ! -s "$LOG" ]; then LOG="run.log.d"; fi
echo "LOG=$LOG ($(wc -l < "$LOG" | tr -d " ") lines)"
echo "===BUF506=== every receipt naming 801EF300 (the buffer lifecycle)"
grep -n -F -e "801EF300" "$LOG" | head -40
echo "--- the broader 801EF range mentions (adjacent cells):"
grep -n -F -e "801EF" "$LOG" | grep -v -F -e "801EF300" | head -12
echo "===DMA506=== cd-dma deliveries into the buffer"
grep -n -e "cd-dma" "$LOG" | grep -F -e "801EF300" | head -16
echo "--- the file#18 read family (READ ISSUED + completion):"
grep -n -e "READ ISSUED" "$LOG" | head -6
grep -n -e "reshtail" "$LOG" | head -12
echo "===TL506=== the read-completion -> unpack timeline (key families)"
RI=$(grep -n -e "READ ISSUED" "$LOG" | head -1 | cut -d: -f1)
LZ=$(grep -n -e "\[lzss\] #4" "$LOG" | head -1 | cut -d: -f1)
echo "READ ISSUED at line $RI; lzss #4 at line $LZ"
if [ -n "$RI" ] && [ -n "$LZ" ] && [ "$LZ" -gt "$RI" ]; then
  awk -v A="$RI" -v B="$LZ" 'NR>=A && NR<=B && ($0 ~ /cd-dma/ || $0 ~ /reshtail/ || $0 ~ /stompcam/ || $0 ~ /finstamp/ || $0 ~ /fldsec/ || $0 ~ /pendclr/ || $0 ~ /heaprel/ || $0 ~ /ReleaseAllHeapBlocks/ || $0 ~ /archw/ || $0 ~ /wipe/ || $0 ~ /memset/ || $0 ~ /lzss/) { print NR": "$0 }' "$LOG" | head -60
else
  echo "(READ ISSUED and lzss #4 not in order in this log; printing the raw window around lzss #4:)"
  awk -v B="$LZ" 'NR>=B-40 && NR<=B+2 { print NR": "$0 }' "$LOG" | head -44
fi
echo "===WIPE506=== the stomp + heap-release receipts (the zeroer candidates)"
grep -n -e "stompcam" "$LOG" | head -16
echo "--- the heap release family:"
grep -n -e "ReleaseAllHeapBlocks" -e "heaprel" -e "HeapRelease" -e "ReleaseHeapBlock" "$LOG" | head -16
echo "===HEAP506=== the heap map: does a heap region claim 0x801EF300?"
grep -n -e "59320" "$LOG" | head -8
grep -n -e "heapstart" -e "heap start" -e "8006FAEC" -e "80077454" "$LOG" | head -12
echo "--- allocation receipts near the 801E-801F band:"
grep -n -e "alloc" "$LOG" | grep -e "801E" -e "801F" | head -12
echo "===C506DONE=== the buffer's zero-er is receipted: landed-then-wiped vs never-landed - the c507 fix follows from these receipts only - digest is pure ASCII"
