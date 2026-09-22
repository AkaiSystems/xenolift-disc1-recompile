#!/bin/bash
# c394_lba16.sh - READ-ONLY CENSUS. NO run, NO patch. The
# c393b verdict: R1369 landed, the pre-movie spin EXITED,
# and the game produced the deepest run ever - file#18 with
# a length armed, the STR stream serving 33 sectors, the
# GPU at 8.8M gp0 words / 75,252 drawing-list DMA sends, and
# THE FIRST REAL VRAM CONTENT EVER DRAWN (regions A/B=4480
# nonzero, park window 93% nonzero). The NEW BLOCKER: the
# 80036xxx movie-player family polls a SYSTEM-AREA READ -
# LBA 16 (the ISO9660 PVD, the CDFS remount), FDF8=2048
# ARMED, FE04=16, sched=1, pend=0, FE1C=6 - one serve away.
# THIS PASS: the LBA-16 request anatomy (who formed it, who
# declines it), FE08/FDFC at the new posture, the VRAM
# content census (WHAT is drawn), and the 80036xxx family
# receipts - the exact anatomy for the R1370 PVD serve.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C394-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="e918ef8605b0c80533c4aa06356fa0fdb6c034fd9fe9e24517a1d1200d09394a"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1369 tree - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1369 tree)"
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
if [ ! -s "$LOG" ]; then echo "TREE-ROOT-LOG-MISSING"; exit 0; fi
echo "AUTHORITATIVE LOG = $LOG ($(wc -l < "$LOG" | tr -d ' ') lines)"
echo "===LBA16FORM394=== the LBA-16 request formation (Setloc 16 / the CDFS remount)"
grep -n "Setloc BCD.*-> LBA 16\|seek=16 \|FE04=00000010\|00000010 " "$LOG" | grep -v "mvloop\|fldfrz2\|parkcam\|waitbr" | head -16
echo "===LBA16WIN394=== the LBA-16 request window (the ladder + serve decisions around it)"
grep -n "cmdtl\] R533" "$LOG" | awk -F: '$1>=29800 && $1<=31200' | head -20
echo "===DECLINE394=== the serve decisions at the LBA-16 posture (who declines)"
grep -n "fld2arm\|sgdecline\|would-arm\|decline\|DECLINE" "$LOG" | awk -F: '$1>=29900 && $1<=32001' | head -14
echo "===FE08NEW394=== the dest/FDFC cells at the new posture (the data-watcher prints)"
grep -n "bp\] DATA HANDLER\|fetchcam" "$LOG" | awk -F: '$1>=29900 && $1<=32001' | head -10
echo "===SMX394=== the 80036xxx family receipts (the movie-player era)"
grep -n "800366F0\|80036C94\|80036CA4\|800370DC\|800317E0\|80046560" "$LOG" | grep -v "mvloop" | head -10
echo "===MDEC394=== the MDEC receipts (movie decode engaged?)"
grep -n "mdec\|MDEC" "$LOG" | head -10
echo "===VRAM394=== the VRAM content census (WHAT is drawn?)"
grep -n "R693 snap\|R736 band\|R695 regions" "$LOG" | tail -8
grep -n "gpucls\] R939 cmd census" "$LOG" | tail -3
echo "===SECT16394=== any sector serves at LBA 16 / the system area"
grep -n "sector LBA 16 \|LBA 16 loaded\|sector LBA 0 \|sector LBA 1 \|sector LBA 2 " "$LOG" | head -8
echo "===BLITS394=== the blit census (10 blits - what did they draw?)"
grep -n "blit\]" "$LOG" | tail -8
echo "===SETMODE394=== the Setmode story (0xA0 = the movie posture)"
grep -n "Setmode" "$LOG" | tail -6
echo "===C394DONE=== the LBA-16 anatomy is receipted"
