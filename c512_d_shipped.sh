#!/bin/bash
# c512_extract.sh - READ-ONLY SLOT-SELECTION CENSUS, NO
# RUN, NO BUILD, NO PATCH. The c511 receipts: R1378 THE
# GENERAL DATA-READY DOOR exists for exactly this posture
# (sector buffered, read active, nothing armed) but is
# gated off for the file#18 request by cd_pending!=0
# (pend=3: a re-stacked level-3 response from the game's
# own Pause->Setloc->ReadN re-issue loop) and
# cd_scheduled!=0 - as are R408 (sched=0, FDF8>100000) and
# R453 (pend=0, FDF8==0). The healthy eras deliver via the
# GUEST's own event chain (pair dispatch posting slot bits
# 0x80056788 + flag 0x800578A6 - the on-hardware mechanism
# per the R879 comment). The broken window adds POISON
# ENTRIES to the CD-sync chunk family: [cdcsync] r2=
# 00000000 ('r2<0x80000000 = the poison-entry receipt')
# interleaved with valid r2=80018EB0 shapes. And the
# collector's h4 cell 0x800564AC is read through a RUNTIME
# HELPER: xenolift_cdcb_slot(0x800564ACu), 5 emitted call
# sites. THE QUESTION: what does the wait-loop check to
# pick slot=4 vs slot=2, what does the poison r2 do to the
# guest chain, and can the door arm safely in this
# posture? THIS CENSUS receipts: (1) xenolift_cdcb_slot's
# body + every runtime use; (2) the wait-loop's
# slot-selection print site (the 'collector slot=' logic);
# (3) the poison-entry camera branch (the cdcsync r2
# class); (4) the R1378 door's full fire block (the
# remainder cut off at c511). Fail-closed, tee'd to
# /tmp/c512_receipts.txt. Pure-ASCII output.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C512-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c512_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="13aab535963b12c3ff0515d0c2892e8d7625327afa09a3569ae1f2d7b3e1c5d4"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the c504 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the c504 tree with the landed interpreter)"
D="disc1.c"
for F in "$D" "$SRC"; do
  if [ ! -s "$F" ]; then echo "GATE-FAILED: $F missing/empty"; exit 0; fi
done
echo "===SLOTFN512=== xenolift_cdcb_slot's body + every runtime use"
S1=$(grep -n -e "cdcb_slot" "$SRC" | head -1 | cut -d: -f1)
grep -n -e "cdcb_slot" "$SRC" | head -12
if [ -n "$S1" ]; then sed -n "$((S1-4)),$((S1+50))p" "$SRC"; fi
echo "===WL512=== the wait-loop slot-selection logic (the 'collector slot=' print site)"
W1=$(grep -n -F -e "collector slot=" "$SRC" | head -1 | cut -d: -f1)
echo "the print site at line $W1:"
if [ -n "$W1" ]; then sed -n "$((W1-60)),$((W1+12))p" "$SRC"; fi
echo "===POISON512=== the poison-entry camera branch (the cdcsync r2 class)"
P1=$(grep -n -F -e "poison-entry" "$SRC" | head -1 | cut -d: -f1)
echo "the camera at line $P1:"
if [ -n "$P1" ]; then sed -n "$((P1-30)),$((P1+30))p" "$SRC"; fi
echo "===DOOR512=== the R1378 door's full fire block (the remainder)"
R1=$(grep -n -F -e "site 8: the general door" "$SRC" | head -1 | cut -d: -f1)
if [ -n "$R1" ]; then sed -n "$((R1-2)),$((R1+40))p" "$SRC"; else echo "(marker not found; grepping r1378)"; grep -n -e "r1378" "$SRC" | head -10; fi
echo "===C512DONE=== the slot selection + poison class + door remainder are receipted - the c513 fix design follows from these receipts only - digest is pure ASCII"
