#!/bin/bash
# c412_relaysrc.sh - READ-ONLY CENSUS. NO run, NO patch.
# The c411 verdict: the game ITSELF called exit(0) at
# t=121s (clean, atexit-clean-return, state F0C=12) -
# then OUR RELAY (R722 exe restore, R1216 hygiene,
# bootmain re-entry) re-booted WITHOUT the cold-init
# chain: SoundInitialize never re-ran, 59410 stayed 0,
# and the re-boot spiraled into the null-sound-heap TRUE
# DEATH. R1377 = complete the relay cold boot. Per the
# c200 lesson: NEVER patch against an unreceipted API.
# THIS PASS extracts: (1) the relay source - the R722/
# R1216/R718/R719 sites and the EXACT dispatch call the
# relay uses to re-enter bootmain (R1377's template);
# (2) the sndinit hook source (R966/R1012 sites, the
# gate at 957C, SoundInitialize's own fn address);
# (3) the [fl] free-list camera source (does the CAMERA
# compute that terminator size, or is it the game's?);
# (4) the state-18 exit context (what the game was doing
# at exit: cur_fn 80036760's role, F0C=12 meaning, the
# exit call site). NO behavior change - receipts only.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C412-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="f92a451cacc252da4b9e13ea00bc2ebbc8ae8c83716753023fd7f8e631115484"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1376 tree - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1376 tree)"
echo "===RELAYSRC412=== the relay machinery source (R722/R1216/R718/R719 + the dispatch call)"
grep -n "R722\|R1216\|R718\|R719" "$SRC" | head -14
RL=$(grep -n "R1216 re-entry hygiene" "$SRC" | head -1 | cut -d: -f1)
if [ -n "$RL" ]; then
  echo "--- the hygiene site context (line $RL, -30/+40):"
  awk -v s=$((RL-30)) -v e=$((RL+40)) 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
fi
EXL=$(grep -n "R718/R719 exit() OVERRIDE" "$SRC" | head -1 | cut -d: -f1)
if [ -n "$EXL" ]; then
  echo "--- the exit-override site (line $EXL, -20/+40):"
  awk -v s=$((EXL-20)) -v e=$((EXL+40)) 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
fi
echo "===DISPATCH412=== the dispatch API the runtime uses (how a guest fn is invoked)"
grep -n "xenolift_dispatch\|dispatch_guest\|guest_call" "$SRC" | head -10
echo "===SNDINITSRC412=== the sndinit hook source (the fn address + the 957C gate)"
SL=$(grep -n "SoundInitialize ENTRY: gate" "$SRC" | head -1 | cut -d: -f1)
if [ -n "$SL" ]; then
  echo "--- the R1012 entry hook (line $SL, -35/+20):"
  awk -v s=$((SL-35)) -v e=$((SL+20)) 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
fi
SL2=$(grep -n "R966 %s entry #%u" "$SRC" | head -1 | cut -d: -f1)
if [ -n "$SL2" ]; then
  echo "--- the R966 entry hook (line $SL2, -20/+12):"
  awk -v s=$((SL2-20)) -v e=$((SL2+12)) 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
fi
echo "===FLCAM412=== the [fl] free-list camera (who computes the terminator size?)"
FL=$(grep -n "terminator" "$SRC" | head -3)
echo "$FL"
FLN=$(echo "$FL" | head -1 | cut -d: -f1)
if [ -n "$FLN" ]; then
  awk -v s=$((FLN-30)) -v e=$((FLN+8)) 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
fi
echo "===EXITCTX412=== the state-18 exit context (what was the game doing at exit?)"
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
awk -v s=30700 -v e=30810 'NR>=s && NR<=e { print NR": "$0 }' "$LOG" | grep -v "asciiart\|frclash\|fbw\|mangleguard" | head -30
echo "===C412DONE=== the relay source + dispatch API are receipted - R1377 follows from these receipts only"
