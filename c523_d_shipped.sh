#!/bin/bash
# c523_census.sh - READ-ONLY SOURCE CENSUS of the scheduled-
# command release machinery + its park-era hook sites, NO
# RUN, NO BUILD, NO PATCH. THE c522 VERDICT: the serve chain
# is REGISTER-POLL-DRIVEN - the R96 INT1 arm fires only when
# the guest pops the response FIFO at 1801, and the response
# for a SCHEDULED command is built only by the deferred
# release (g_r918_poll_requested), which is set only by
# 1800/1802 register reads. THE PARK'S LOOP (LegacyCdDataWait
# at 800286CC) POLLS MEMORY CELLS - 439M A22C reads, ZERO
# CD-register reads - so the lazy-INT chain starves while the
# guest waits for exactly its product. THE RECEIPTS SHOW THE
# MACHINERY ALIVE IN THE PARK: the fd-collector tick FIRED
# (r31=0x80028A74, the park's own caller) and the pollkick
# serviced 9 times - both proven-safe service points with
# nothing pending. THE ONE MISSING STEP: the scheduled
# ReadN's response never became pending (sched=1, pend=0,
# act=0, arm1=0 forever). THE FIX SHAPE (for c524, NOT this
# census): at a proven park-era service point, when
# cd_scheduled && !cd_pending && !cd_read_active, request the
# EXISTING deferred release (g_r918_poll_requested=1, the
# R918/R923 pattern - no host frame, no direct call) so the
# boundary release builds the INT3, the EXISTING conversion
# family (R471 drain + R1380 collector) delivers it, and the
# GUEST driver code sets A22C. THIS CENSUS receipts: (1) the
# R1196 pollkick site (where it lives, its context); (2)
# cd_sched_poll_release (its definition body - what it does
# for a scheduled command); (3) where command writes set
# cd_scheduled=1 (the issue path); (4) the fd-collector tick
# site (what triggers it - proven alive in the park); (5)
# how a scheduled command's response gets built (the answer
# builder the release calls); (6) the g_r918_poll_requested
# drain site (where the release actually runs). Fail-closed,
# tee'd to /tmp/c523_receipts.txt. Pure-ASCII output.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C523-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c523_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="05535414f7c77fd05cb4bcfeaf91fdbd239baf7e4c9d7c48b529bbaf658d1233"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the c519 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the c519 tree with the landed post-conversion collector pass)"
if [ ! -s "$SRC" ]; then echo "GATE-FAILED: runtime.c missing"; exit 0; fi
echo "===POLKICK=== the R1196 pollkick site (where it lives, its context)"
P1=$(grep -n -F -e "[pollkick]" "$SRC" | head -1 | cut -d: -f1)
echo "the pollkick print at line $P1 (all refs: $(grep -c -F -e "pollkick" "$SRC" | tr -d " ")):"
grep -n -F -e "pollkick" "$SRC" | head -6
if [ -n "$P1" ]; then _S0=$((P1-40)); [ "$_S0" -lt 1 ] && _S0=1; sed -n "${_S0},$((P1+20))p" "$SRC"; fi
echo "===SCHEDREL=== cd_sched_poll_release (its definition body - what it does for a scheduled command)"
echo "all refs:"
grep -n -e "cd_sched_poll_release" "$SRC" | head -10
D1=$(grep -n -e "static.*cd_sched_poll_release" "$SRC" | head -1 | cut -d: -f1)
echo "the definition at line $D1:"
if [ -n "$D1" ]; then _S0=$((D1-10)); [ "$_S0" -lt 1 ] && _S0=1; sed -n "${_S0},$((D1+90))p" "$SRC"; fi
echo "===CMDSCHED=== where command writes set cd_scheduled=1 (the issue path)"
grep -n -e "cd_scheduled = 1" -e "cd_scheduled=1" "$SRC" | head -8
C1=$(grep -n -e "cd_scheduled = 1" -e "cd_scheduled=1" "$SRC" | head -1 | cut -d: -f1)
if [ -n "$C1" ]; then echo "--- the context of the first scheduler-set (line $C1):"; _S0=$((C1-25)); [ "$_S0" -lt 1 ] && _S0=1; sed -n "${_S0},$((C1+25))p" "$SRC"; fi
echo "===FDTICK=== the fd-collector tick site (what triggers it - proven alive in the park)"
F1=$(grep -n -F -e "fd-collector tick" "$SRC" | head -1 | cut -d: -f1)
echo "the fd-collector tick print at line $F1:"
if [ -n "$F1" ]; then _S0=$((F1-45)); [ "$_S0" -lt 1 ] && _S0=1; sed -n "${_S0},$((F1+25))p" "$SRC"; fi
echo "===RSPBUILD=== how a scheduled command's response gets built (the answer builder)"
B1=$(grep -n -F -e "re-primed response FIFO" "$SRC" | head -1 | cut -d: -f1)
echo "the re-prime print at line $B1 (all re-prime refs: $(grep -c -F -e "re-primed" "$SRC" | tr -d " ")):"
if [ -n "$B1" ]; then _S0=$((B1-30)); [ "$_S0" -lt 1 ] && _S0=1; sed -n "${_S0},$((B1+30))p" "$SRC"; fi
echo "===R918DRAIN=== the g_r918_poll_requested drain site (where the release actually runs)"
echo "all refs:"
grep -n -e "g_r918_poll_requested" "$SRC" | head -12
G1=$(grep -n -e "g_r918_poll_requested" "$SRC" | grep -v -e "= 1" -e "=1" | head -1 | cut -d: -f1)
echo "the drain/consume site at line $G1:"
if [ -n "$G1" ]; then _S0=$((G1-25)); [ "$_S0" -lt 1 ] && _S0=1; sed -n "${_S0},$((G1+45))p" "$SRC"; fi
echo "===C523DONE=== the release machinery and its park-era hook sites are receipted in source - the c524 fix follows from these receipts only - digest is pure ASCII"
