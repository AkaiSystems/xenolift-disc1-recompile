#!/bin/bash
# Serialized boot protocol. NOTHING else runs during a trial (trap 3).
# usage: boot_protocol.sh <out_dir> [n_trials=6] [budget_s=150] [stop_pattern]
# stop_pattern (grep -E): end the run STOP_GRACE s (default 6) after it first appears in run.log.raw
# Two sessions share ~/Downloads/xenolift (one build dir, one run.log.raw): every batch takes the
# lock dir trials/.trial.lock first and waits while another batch holds it.
OUT="$1"; N="${2:-6}"; B="${3:-150}"; SP="$4"; SG="${STOP_GRACE:-6}"
[ -z "$OUT" ] && { echo "usage: $0 <out_dir> [n] [budget_s]"; exit 1; }
LOCK="$HOME/Desktop/xenolift-session/trials/.trial.lock"
until mkdir "$LOCK" 2>/dev/null; do
  if [ -f "$LOCK/pid" ] && ! kill -0 "$(cat "$LOCK/pid")" 2>/dev/null; then rm -rf "$LOCK"; continue; fi  # stale lock
  sleep 5
done
echo $$ > "$LOCK/pid"; echo "$OUT" > "$LOCK/owner"
trap 'rm -rf "$LOCK"' EXIT
mkdir -p "$OUT"; rm -f "$OUT"/*.raw "$OUT"/progress
mkdir -p /tmp/jtwatch
cd ~/Downloads/xenolift || exit 1
for n in $(seq 1 "$N"); do
  pkill -9 -f xenogears_boot 2>/dev/null
  sleep 2
  CAP=$(( B + 80 )); [ "$CAP" -gt "${HARD_CAP:-60}" ] && CAP="${HARD_CAP:-60}"   # hard wall cap per trial (user: stall identified within 90 s)
  ( sleep $CAP; pkill -9 -f xenogears_boot 2>/dev/null ) &   # external killer: the in-tree fuse does not bound runs (trap 2)
  K=$!
  W=""
  if [ -n "$SP" ]; then   # early stop: watch this run's log (newer than the marker) for the pattern
    touch /tmp/jtwatch/.start_marker
    ( until [ run.log.raw -nt /tmp/jtwatch/.start_marker ] && grep -qE "$SP" run.log.raw 2>/dev/null; do sleep 1; done
      sleep "$SG"; echo "early stop: /$SP/ seen" >> "$OUT/progress"; pkill -9 -f xenogears_boot 2>/dev/null ) &
    W=$!
  fi
  RUN_BUDGET_S=$B bash run.sh > "$OUT/trial_$n.stdout" 2>&1
  kill $K 2>/dev/null; [ -n "$W" ] && kill $W 2>/dev/null
  cp run.log.raw "$OUT/trial_$n.raw" 2>/dev/null                    # always the raw log (trap 1)
  echo "trial $n done $(date +%H:%M:%S)" >> "$OUT/progress"
done
echo ALLDONE >> "$OUT/progress"
