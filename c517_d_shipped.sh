#!/bin/bash
# c517_extract.sh - READ-ONLY FIX-SITE SOURCE CENSUS, NO
# RUN, NO BUILD, NO PATCH. The c516 era-anchored receipts
# NAMED THE BREAK (Jos's frame): the sequence
# post -> collect -> select -> consume first breaks at
# COLLECTION. Receipted: the same store (fn 0x80041B24,
# sw_line 128995) posts the data bit in both eras; the
# broken window's word held 0x102 (the healthy shape,
# receipted 10612+10621/10622) - but the post lands while
# the game is in its re-issue path, and the game's next
# Setloc issue (10625) runs fn 8004247C's clearing (10627,
# cell0 02->00) which ERASES the event word before any
# collector scan; the next scan (10652) returns slot=2
# only. Healthy: post (8062) -> scan (8065, slot=4) ->
# h4 -> FILE-CB -> DMA -> FDF8 countdown, in-wait-loop.
# The out-of-context root: the fd-tick's 'converting
# stuck INT1 (pending=3) via handler pair' rescue runs
# the pair from WATCHER context - the post lands, the
# game's own next command clears it before its scan
# cadence. THE FIX (R112 precedent class: dispatch so the
# scan finds a real event): after the conversion's pair
# returns, run ONE collector scan in the same context and
# dispatch h4 if the data bit is present - narrow,
# receipted, fire-capped, r1179-checked, NO pend-gate
# changes. THIS CENSUS receipts the exact source: (1) the
# fd-tick conversion site (its conditions + the pair
# dispatch + what follows); (2) the defib5 stacked-pending
# drain; (3) the wait-loop collector's dispatch loop (the
# scan code the fix must mirror); (4) the h4/fallback
# dispatch code (what dispatches 0x8002B084 + the
# read-struct fetch). Fail-closed, tee'd to
# /tmp/c517_receipts.txt. Pure-ASCII output.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C517-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c517_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="13aab535963b12c3ff0515d0c2892e8d7625327afa09a3569ae1f2d7b3e1c5d4"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the c504 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the c504 tree with the landed interpreter)"
if [ ! -s "$SRC" ]; then echo "GATE-FAILED: runtime.c missing"; exit 0; fi
echo "===CONVERT517=== the fd-tick conversion site (the stuck-INT1 handler pair)"
C1=$(grep -n -F -e "converting stuck INT1" "$SRC" | head -1 | cut -d: -f1)
echo "the conversion print at line $C1:"
if [ -n "$C1" ]; then sed -n "$((C1-70)),$((C1+60))p" "$SRC"; fi
echo "===DEFIB517=== the stacked-pending drain (defib5)"
D1=$(grep -n -F -e "stacked-pending drain pass" "$SRC" | head -1 | cut -d: -f1)
echo "the drain print at line $D1:"
if [ -n "$D1" ]; then sed -n "$((D1-50)),$((D1+40))p" "$SRC"; fi
echo "===COLLOOP517=== the wait-loop collector's dispatch loop (the scan the fix mirrors)"
W1=$(grep -n -F -e "wait-loop event: collector slot=" "$SRC" | head -1 | cut -d: -f1)
echo "the collector print at line $W1:"
if [ -n "$W1" ]; then sed -n "$((W1-40)),$((W1+80))p" "$SRC"; fi
echo "===H4DISP517=== the h4 dispatch code (the FILE-CB path + read-struct fetch)"
H2=$(grep -n -F -e "dispatch h4" "$SRC" | head -2 | tail -1 | cut -d: -f1)
echo "the h4 dispatch at line $H2:"
if [ -n "$H2" ]; then sed -n "$((H2-30)),$((H2+70))p" "$SRC"; fi
echo "===C517DONE=== the conversion site + collector loop + h4 dispatch are receipted - the c518 patch follows from this source only - digest is pure ASCII"
