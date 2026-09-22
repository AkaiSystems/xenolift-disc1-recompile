#!/bin/bash
# c526_census.sh - READ-ONLY CENSUS of the member-6 dest=1
# fault, NO RUN, NO BUILD, NO PATCH. THE c525 VERDICTS:
# (A) THE ENDING: the LZSS core 80032EB4 ran WILD with a
# garbage return (r31=0000000A), overwriting the entire CD
# state (archive base 80010004 -> 800CE5E1, FDF8/FE04/FE1C
# garbage) + the libetc queue cells - the c335 runaway
# class; then fault-walk restart #2, the R844 boot-loop
# bypass forced the coordinator door 80077E88, and the
# R1393/R1394 interpreter honestly stopped on an undefined
# op at 80077E9C (w=E1000300) - capture preserved, exit
# 99. (B) THE ROOT, receipted: [newmod] fn_800295D8
# member=6 dest=00000001 - the game's own module loader
# passed dest=0x1 for member 6 (member 5 got the healthy
# 800AA6B0); the R896 sync-door DECLINED the delivery on
# it ('seek LBA 108884 known (size 2660) but FE08 dst
# invalid (00001001) - no sync delivery'); the countdown
# completed anyway (2660->612->0) with the sectors landing
# at garbage dests (0x00000001/0x00000801) - the delivery
# machinery was READY, the REQUEST was malformed, and the
# garbage dest fed the decompressor its runaway. (C) The
# 108861 park never occurred this trajectory; R1381 stays
# armed; the screen stayed blank (vram_nonzero=0/8192).
# THE OPEN QUESTION: WHO computed member 6's dest as 0x1 -
# the allocation or table lookup in the loader chain
# (r31=800197B4), and what the healthy members' dest
# progression looks like. THIS CENSUS: (1) the member-6
# window + the full newmod/ovlread dest progression; (2)
# the caller state BEFORE the member-6 request (who ran,
# what allocated); (3) the allocation ([hand]) receipts
# around the request; (4) the LZSS arm chain (the last
# armed op before the runaway) + the FIRST wild write;
# (5) the sync-door decline family; (6) the trajectory
# census (boot eras, module installs, GPU). Fail-closed,
# tee'd to /tmp/c526_receipts.txt. Pure-ASCII output.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C526-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c526_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="d1c3d3912462c72ac7a811d8ce177c18b56166a6aa4825049cc3b686330b6384"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the c524 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the c524 tree with the landed R1381 park-release request)"
LOG="run.log"
if [ ! -s "$LOG" ]; then echo "GATE-FAILED: no run.log"; exit 0; fi
echo "LOG=run.log ($(wc -l < "$LOG" | tr -d " ") lines)"
echo "===MEMB6=== the member-6 request + the dest progression"
echo "--- all the newmod/ovlread receipts (the dest progression across members):"
grep -n -e "\[newmod\]" -e "ovlread" "$LOG" | head -16
echo "--- the member-6 window (30400-30470):"
sed -n "30400,30470p" "$LOG"
echo "===CALLER=== the caller state BEFORE the member-6 request"
echo "--- the 60 lines before line 30436 (who ran, what allocated):"
sed -n "30376,30436p" "$LOG"
echo "===HANDS=== the allocation receipts around the request"
echo "--- the [hand] allocation receipts in the 29000-30440 range:"
grep -n -e "\[hand\]" "$LOG" | awk -F: '$1 >= 29000 && $1 <= 30440' | head -16
echo "--- the [stress] read-order receipts (tail):"
grep -n -e "read-order" "$LOG" | tail -6
echo "===LZSSARM=== the arm chain + the FIRST wild write"
echo "--- the [fencelife]/[lzss-fence] receipts (the last armed ops):"
grep -n -e "fencelife" -e "lzss-fence" "$LOG" | tail -8
echo "--- the FIRST receipts with the garbage r31=0000000A (the runaway's first observed wild call):"
grep -n -e "r31=0000000A" "$LOG" | head -6
echo "--- the unpackw receipts (all):"
grep -n -e "unpackw" "$LOG" | head -8
echo "===SDOOR=== the sync-door decline family"
grep -n -e "sdoor" "$LOG" | head -12
echo "===TRAJ=== the trajectory census"
echo "--- the fault-walk restarts + boot eras:"
grep -n -e "fwrestart" "$LOG" | tail -6
echo "--- the module install receipts:"
grep -n -e "MODULE 6 ENTRY" "$LOG" | head -4
echo "--- the screen witnesses (all vram_nonzero):"
grep -n -e "vram_nonzero" "$LOG" | head -6
echo "===C526DONE=== the member-6 dest question is receipted - the c527 decision (the dest writer fix or the next first fault) follows from these receipts only - digest is pure ASCII"
