#!/bin/bash
# c241_cmd02_ladder.sh - READ-ONLY: no patch, no compile, no run.
# THE c240 VERDICT: the state-1 module IS RUNNING (STATE-1 CB ENTER #1
# t=7s), the mount handshake completed, the game stamped the f15
# request (FE04=108995 FDF8=92180 F0C=15), the drive ARMED for it
# (pumpcam act=1 seek=108995 data=2060/0 pend=0, cdst arm1=0) - but the
# cmd-02 Setloc scheduled response blocks at fe1c=0 (the guest pops the
# staged bytes, yet per the c180/R613 lesson the answer alone is never
# the gate: no release branch matched, no INT flag, no event bit, the
# kernel waiter never returns, READ ISSUED file#15 never fires). The
# existing cmd-02 gate expects fe1c=1 (line ~2620 comment, seq-139
# era). THE FAILING TERM IS NAMED. THIS CYCLE extracts the actual
# release-ladder code (lines ~2400-2660, above the c240 dump window),
# the cmd-02 response staging, and the full schdw clear-site roster, so
# the c242 widen is byte-exact against the real branch.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C241-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
LOG="run.log"
EXPECT="846085f908bb039278c9f852c44a3a001a961dfbebab5ad702dccb7dd808ecc7"
if [ ! -s "$SRC" ]; then echo "C241-FAILED: runtime/runtime.c missing"; exit 1; fi
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the c238 tree 846085f9 - refusing a foreign tree"; exit 0; fi
echo "BASELINE_VERIFIED (the c238 R1321 tree)"
P="src_probe_c241_$(date +%Y%m%d_%H%M%S)"
if ! (mkdir -p "$P" && cp -p "$SRC" "$P/runtime.c.probe"); then echo "C241-FAILED: preserve failed"; exit 1; fi
echo "PRESERVED: $P/runtime.c.probe sha=$SS"

echo "===LADDER241=== the full release ladder above the c240 window (lines 2400-2660)"
sed -n '2400,2660p' "$SRC"

echo "===CMD02241=== the cmd-02 response staging (where the 3-byte Setloc answer is built)"
grep -n "cd_last_cmd == 0x02u\|cmd == 0x02u" "$SRC" | head -12

echo "===CLEAR241=== the schdw clear-site roster (every release site line ID)"
grep -n "schdw\] R1291 CLEAR site" "$SRC" | head -14

echo "===A22C241=== the A22C=C8C50004 provenance (taint or composed?)"
grep -n "A22C=C8C5\|C8C50004" "$LOG" | head -4
grep -n "0x8006A22C" "$SRC" | head -8

echo "===C241DONE=== ladder extraction complete - c242 widens the cmd-02 gate by the receipted fe1c=0 term"
