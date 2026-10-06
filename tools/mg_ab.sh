#!/bin/bash
# A/B for the mangleguard retirement (MGG): arm A = XENOLIFT_MG_RETIRE=0 (guards as shipped),
# arm B = XENOLIFT_MG_RETIRE=<mask> (default 7 = R517 + R518 w16 + R518 w8 retired). Same binary,
# env var only. Arms interleave A1 B1 A2 B2 ... Each trial is a single boot_protocol run started
# only when no other trial is running (boot_protocol pkills xenogears_boot at every trial start,
# and other sessions share ~/Downloads/xenolift). The executed-binary sha256 of every trial is
# logged to trials/<tag>.ab so pairs built from different sources can be spotted.
# usage: mg_ab.sh <tag> [pairs=2] [budget_s=120] [mask=7]
T="$HOME/Desktop/xenolift-session"
TAG="$1"; N="${2:-2}"; B="${3:-120}"; M="${4:-7}"
[ -z "$TAG" ] && { echo "usage: $0 <tag> [pairs] [budget_s] [mask]"; exit 1; }
idle() { while pgrep -f "[x]enogears_boot|[b]oot_protocol" >/dev/null; do sleep 5; done; }
for k in $(seq 1 "$N"); do
  for arm in A B; do
    m=0; [ "$arm" = B ] && m="$M"
    d="$T/trials/$TAG$arm$k"
    idle
    XENOLIFT_MG_RETIRE=$m "$T/tools/boot_protocol.sh" "$d" 1 "$B" > "$d.out" 2>&1
    sha=$(grep -o "executed-binary [^ ]* sha256=[0-9a-f]*" "$d/trial_1.stdout" 2>/dev/null | head -1)
    echo "$TAG$arm$k mask=$m $(date +%H:%M:%S) $sha" >> "$T/trials/$TAG.ab"
  done
done
echo ALLDONE >> "$T/trials/$TAG.ab"
