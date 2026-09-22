#!/bin/bash
# c285_lzssargs_probe.sh - READ-ONLY: receipt the LZSS ENTRY ARGS +
# CALLER for the faulting call; the last receipts the fix design
# needs.
# THE c284 VERDICT: Jos's stored-stale-pointer lifetime chain is
# DISCONFIRMED for these instances - the c283 targets were legit
# mask-table entries, and the c284 target is COMPUTED ON THE FLY
# (R696: no cell contains the target; r4=0xB8ED r5=0x589F8000,
# EPC the LZSS core, cur_fn=v_wait). The LZSS caller computes
# src/dst from a bad base during a receipted empty-sound-heap era
# (head lifecycle ACTIVE: init -> 3 valid allocs -> popped to 0 ->
# SoundInitialize re-enters -> cleared again -> fault).
# THIS PROBE: (a) every lzss receipt in the pre-fault window of the
# c284 witness (the fence printed src/dst in earlier eras - is it
# still live?); (b) the first-fault context expanded; (c) the sound
# lifecycle in the same window; (d) the fence camera's own code
# (R1276 throttle - re-arm it in c286 if silenced); (e) the
# crash-stack fn 80019BFC + dispatcher 800734E8 bodies + the
# unredacted 800357C0 def name. No patch, no compile, no run.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C285-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="ab668553a3e45945572b5c9d41f3e7fbe1726fa67e8796772c83c6a0ff9faf70"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1334 tree ab668553 - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1334 tree)"
LOG="witness_c284_20260917_084145/run.log"
if [ ! -s "$LOG" ]; then LOG="run.log"; fi
LS=$(shasum -a 256 "$LOG" | cut -d" " -f1)
ENDL=$(wc -l < "$LOG" | tr -d " ")
echo "WITNESS=$LOG sha=$LS lines=$ENDL"
win() { S=$1; [ "$S" -lt 1 ] && S=1; E=$2; [ "$E" -gt "$ENDL" ] && E="$ENDL"; awk -v s="$S" -v e="$E" 'NR>=s&&NR<=e{printf "%d:%s\n",NR,$0}NR>e{exit}' "$LOG"; }
trunc() { sed -E 's/[A-Za-z0-9_./+-]{34,}/[T]/g' | cut -c1-110; }

echo "===LZSS285=== every lzss receipt in the pre-fault window (28300-30190)"
win 28300 30190 | grep -i "lzss" | head -40
echo "--- all lzss receipts in the whole log (head 20):"
grep -n -i "lzss" "$LOG" | head -20
echo "--- the dispatcher activity near the fault (800734 family):"
win 28300 30190 | grep "800734" | head -12

echo "===FAULTWIN285=== the first-fault context expanded (30150-30196)"
win 30150 30196

echo "===SOUND285=== the sound lifecycle in the c284 run (pre-fault window + post-restart)"
win 28000 30183 | grep "sndinit\]\|\[alloc\]\|\[clear\]\|free-list\|irqc\]" | head -24
echo "--- the SoundInitialize re-entry receipts:"
grep -n "sndinit\]" "$LOG" | head -12

echo "===FENCAM285=== the lzss fence camera code (is the throttle silencing entry args?)"
L=$(grep -n "R1276" "$SRC" | head -1 | cut -d: -f1)
echo "R1276 at line $L"
if [ -n "$L" ]; then sed -n "$((L-18)),$((L+22))p" "$SRC" | trunc; fi
echo "--- the fence arg print (R1169-era):"
L2=$(grep -n "lzss-fence\|lzss_in_past" "$SRC" | head -1 | cut -d: -f1)
echo "fence code at line $L2"
if [ -n "$L2" ]; then sed -n "$((L2-12)),$((L2+20))p" "$SRC" | trunc; fi

echo "===STATIC285=== the crash-stack + dispatcher fn bodies"
DCA="./disc1.c"
echo "--- 800357C0 def name (unredacted):"
grep -n "^static void xenolift_fn_800357C0" "$DCA" | grep -v ";" | cut -c1-140
fnwindow() {
  FN="$1"; MAXL="${2:-90}"
  L=$(grep -n "^static void xenolift_fn_${FN}" "$DCA" | grep -v ";" | head -1 | cut -d: -f1)
  if [ -z "$L" ] || [ "$L" -lt 1 ] 2>/dev/null; then echo "===FN_${FN}: DEF NOT FOUND"; return; fi
  E=$(awk -v s="$L" 'NR>s && /^static void/{print NR; exit}' "$DCA")
  [ -z "$E" ] && E=$((L+MAXL+2))
  echo "===FN_${FN} (def $L .. next def $E, ${MAXL}-capped)==="
  awk -v s="$L" -v e="$((E-1))" 'NR>=s && NR<=e' "$DCA" | head -"$MAXL" | trunc
}
fnwindow 80019BFC 90
fnwindow 800734E8 70

echo "===C285DONE=== lzss-args probe complete - the c286 fix design comes from these receipts"
