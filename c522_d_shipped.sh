#!/bin/bash
# c522_census.sh - READ-ONLY SOURCE CENSUS of the CD
# serve machinery, NO RUN, NO BUILD, NO PATCH. THE c521
# VERDICTS: (A) THE CAPTURE DECODES THE MODULE WINDOW -
# the base 0x8006F000 is ALL ZEROS (the module's own
# section never installed), 0x47EC holds ce53ebd4 (the
# exact c495 live-module bytes at the confirmed mismatch
# site), 0x8E88 holds REAL coordinator code (27bdffc8
# 3c038001 8c630000 2402ffff, matching the R1005
# retarget) - the interpreter ran genuine code, called
# the linker on zeroed state (a0=NULL), walked into the
# data-like bytes at 0x1348, and honestly stopped. (B)
# THE STALLED READN'S CHAIN IS RECEIPTED: era 1's same
# request (FE04->108861, FDF8=23744) DELIVERED because
# the drive was BEHIND (seek 108821 vs expected 108861)
# and the FIFO re-anchor fired ('sector LBA 108861
# loaded into data FIFO' -> DATA HANDLER -> cd-dma ->
# FE04 advanced to 108862); the park era's drive is
# ALREADY AT 108861 - no mismatch, no re-anchor, no
# sector load, no INT1 arm (arm1=0), no A22C set - and
# the park loop (LegacyCdDataWait at 800286CC polling
# A22C, NOT the data register) never triggers the serve
# machinery. THE R1341 stalecd discard (pending=3->0)
# cleaned the stack just before, but the ReadN came
# after. THE SUSPICION (the R1151 range-condition lesson
# class, NOT yet proven): the serve path may only fire
# on the drive-behind mismatch, silently missing the
# drive-at-seek case. THIS CENSUS receipts the source:
# (1) the FIFO re-anchor (its exact conditions); (2)
# the secserve composite (cd_data_load + read_active=1 -
# what triggers a sector load); (3) the R1341 stalecd
# discard (what exactly it clears); (4) the A22C
# (0x8005A22C) writers (who sets the data-arrived
# flag); (5) the data-ready INT1 arm site (its
# conditions after a ReadN); (6) the ReadN INT3
# consume/arm path. Fail-closed, tee'd to
# /tmp/c522_receipts.txt. Pure-ASCII output.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C522-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c522_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="05535414f7c77fd05cb4bcfeaf91fdbd239baf7e4c9d7c48b529bbaf658d1233"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the c519 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the c519 tree with the landed post-conversion collector pass)"
if [ ! -s "$SRC" ]; then echo "GATE-FAILED: runtime.c missing"; exit 0; fi
echo "===REANCHOR=== the FIFO re-anchor source (its exact conditions)"
R1=$(grep -n -F -e "FIFO re-anchor" "$SRC" | head -1 | cut -d: -f1)
echo "the re-anchor print at line $R1:"
if [ -n "$R1" ]; then _S0=$((R1-60)); [ "$_S0" -lt 1 ] && _S0=1; sed -n "${_S0},$((R1+40))p" "$SRC"; fi
echo "===SECSERVE=== the secserve composite (what triggers a sector load)"
S1=$(grep -n -F -e "secserve" "$SRC" | head -1 | cut -d: -f1)
echo "the first secserve reference at line $S1 (all refs: $(grep -c -F -e "secserve" "$SRC" | tr -d " ")):"
grep -n -F -e "secserve" "$SRC" | head -6
if [ -n "$S1" ]; then _S0=$((S1-50)); [ "$_S0" -lt 1 ] && _S0=1; sed -n "${_S0},$((S1+50))p" "$SRC"; fi
echo "===STALECD=== the R1341 stalecd discard (what exactly it clears)"
T1=$(grep -n -F -e "stale CD state discarded" "$SRC" | head -1 | cut -d: -f1)
echo "the stalecd print at line $T1:"
if [ -n "$T1" ]; then _S0=$((T1-55)); [ "$_S0" -lt 1 ] && _S0=1; sed -n "${_S0},$((T1+35))p" "$SRC"; fi
echo "===A22CW=== the A22C (0x8005A22C) writers (who sets the data-arrived flag)"
grep -n -e "8005A22C" -e "0x5A22C" "$SRC" | head -10
A1=$(grep -n -e "8005A22C" -e "0x5A22C" "$SRC" | head -1 | cut -d: -f1)
if [ -n "$A1" ]; then echo "--- the context of the first writer (line $A1):"; _S0=$((A1-30)); [ "$_S0" -lt 1 ] && _S0=1; sed -n "${_S0},$((A1+30))p" "$SRC"; fi
echo "===ARM1SRC=== the data-ready INT1 arm site (its conditions after a ReadN)"
M1=$(grep -n -F -e "data-ready INT1 armed" "$SRC" | head -1 | cut -d: -f1)
echo "the INT1 arm print at line $M1:"
if [ -n "$M1" ]; then _S0=$((M1-55)); [ "$_S0" -lt 1 ] && _S0=1; sed -n "${_S0},$((M1+25))p" "$SRC"; fi
echo "===READN3=== the ReadN INT3 consume/arm path"
N1=$(grep -n -F -e "ReadN INT3 consumed" "$SRC" | head -1 | cut -d: -f1)
echo "the ReadN INT3 print at line $N1:"
if [ -n "$N1" ]; then _S0=$((N1-40)); [ "$_S0" -lt 1 ] && _S0=1; sed -n "${_S0},$((N1+30))p" "$SRC"; fi
echo "===C522DONE=== the serve machinery's conditions are receipted in source - the c523 fix follows from these receipts only - digest is pure ASCII"
