#!/bin/bash
# c220_pause_completion_probe.sh - READ-ONLY source probe. No patch, no
# compile, no run. Extracts the exact code regions the c221 patch will
# touch: the working Stop-complete/0A-Pause-complete INT2 arming (the
# mechanism to mirror), the R1314/adv599 corrected-model blocks, the 09
# INT3 scheduling site, and the lad2 force-restore - so the pause
# completion patch is byte-exact against the true Mac source.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C220-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
echo "===PRE220=== identity gate"
R=runtime/runtime.c
if [ ! -s "$R" ]; then echo "C220-FAILED: runtime/runtime.c missing"; exit 1; fi
TS=$(shasum -a 256 "$R" | cut -d" " -f1)
echo "TREE_SHA=$TS"
if [ "$TS" != "cdfa6b41dacf69db720ed5faec83d0fa477c865082c6accc989845c51038a45c" ]; then echo "GATE-FAILED: runtime.c is not the cdfa6b41 baseline - nothing else runs"; exit 0; fi
echo "BASELINE_VERIFIED"
echo "runtime_c_size=$(wc -c < "$R" | tr -d " ") lines=$(wc -l < "$R" | tr -d " ")"
P="source_probe_c220_$(date +%Y%m%d_%H%M%S)"
if ! (mkdir -p "$P" && cp -p "$R" "$P/runtime.c.probe"); then echo "C220-FAILED: preserve copy failed"; exit 1; fi
echo "PRESERVED: $P/runtime.c.probe sha=$(shasum -a 256 "$P/runtime.c.probe" | cut -d" " -f1)"

win() { # $1=label $2=pattern $3=head-count $4=before $5=after
  echo "=== $1 ==="
  L=$(grep -n "$2" "$R" | head -"$3" | cut -d: -f1)
  if [ -z "$L" ]; then echo "NO-MATCH in runtime.c for: $2"; return; fi
  for n in $L; do
    echo "--- anchor line $n:"
    sed -n "$((n-$4)),$((n+$5))p" "$R"
  done
}

win "A_PAUSE" "Pause complete" 2 25 35
win "B_STOP" "Stop complete" 2 25 35
win "C_XFER_RETIRE" "STREAM retire (PAUSE" 2 15 40
win "C_XFER_IDLE" "idle pause" 2 15 40
win "D_INT3_SCHED" "INT3 scheduled" 3 12 30
win "E_LAD2_RESTORE" "restored pending state" 2 20 30
win "F_ADV599" "needle no longer advances on Pause" 2 20 30
win "G_CMD09_SCHED" "command 0x09 -> INT3" 2 15 35

echo "===H_TUMAP=== tag-to-file map (which TU owns each receipt tag)"
grep -rln "Pause complete\|Stop complete\|idle pause\|restored pending state" runtime/ 2>/dev/null | head -10

echo "===C220DONE=== source probe complete - c221 builds the byte-exact pause-completion patch from these anchors"
