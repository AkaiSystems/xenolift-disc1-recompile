#!/bin/bash
# c221_ackpair_probe.sh - READ-ONLY source probe. No patch, no compile, no run.
# Extracts the EXACT code at every INT1/INT2 arm site and every last_cmd 0x06
# grouping, so the c222 patch (split cmd 09 from the 06 ReadN pairing at the
# ack-pair arm -> arm the Pause-complete INT2) is authored byte-exact.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C221-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
R="runtime/runtime.c"
if [ ! -s "$R" ]; then echo "C221-FAILED: runtime/runtime.c missing"; exit 1; fi
SS=$(shasum -a 256 "$R" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "cdfa6b41dacf69db720ed5faec83d0fa477c865082c6accc989845c51038a45c" ]; then echo "GATE-FAILED: runtime.c is not the cdfa6b41 baseline - nothing else extracted"; exit 0; fi
echo "BASELINE_VERIFIED"
P="source_probe_c221_$(date +%Y%m%d_%H%M%S)"
if ! (mkdir -p "$P" && cp -p "$R" "$P/runtime.c.probe"); then echo "C221-FAILED: preserve copy failed"; exit 1; fi
echo "PRESERVED: $P/runtime.c.probe sha=$(shasum -a 256 "$P/runtime.c.probe" | cut -d" " -f1)"

echo "===INT2ARMS=== every INT2 completion arm site"
grep -n "cd_pending = 2" "$R" | head -24
i=0
for n in $(grep -n "cd_pending = 2" "$R" | head -6 | cut -d: -f1); do
  i=$((i+1)); echo "--- INT2 arm #$i at line $n (entry context above it):"
  A=$((n-40)); [ "$A" -lt 1 ] && A=1
  sed -n "${A},$((n+6))p" "$R"
done

echo "===INT1ARMS=== every INT1 data arm site"
grep -n "cd_arm_int1_pending = 1" "$R" | head -24
i=0
for n in $(grep -n "cd_arm_int1_pending = 1" "$R" | head -5 | cut -d: -f1); do
  i=$((i+1)); echo "--- INT1 arm #$i at line $n (entry context above it):"
  A=$((n-35)); [ "$A" -lt 1 ] && A=1
  sed -n "${A},$((n+6))p" "$R"
done

echo "===06GRP=== every last_cmd 0x06 grouping (the old-model 06/09 ack-pair)"
grep -n "last_cmd == 0x06" "$R" | head -24
i=0
for n in $(grep -n "last_cmd == 0x06" "$R" | head -5 | cut -d: -f1); do
  i=$((i+1)); echo "--- 06-grouping #$i at line $n:"
  A=$((n-25)); [ "$A" -lt 1 ] && A=1
  sed -n "${A},$((n+25))p" "$R"
done

echo "===ACKCTX=== ack-pair comment sites (the R955 pointer)"
grep -n "at ack time\|ack-pair\|ackpair" "$R" | head -12

echo "===C221DONE=== probe complete - c222 authors the byte-exact 09-INT2 split"
