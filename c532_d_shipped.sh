#!/bin/bash
# c532_census.sh - READ-ONLY CENSUS of the interpreter
# class-3 stop, NO RUN, NO BUILD, NO PATCH. THE c531
# VERDICT: the zrfF command-byte widen LANDED cleanly
# (window 3524..3594, exactly 1 sub, gates green, tree
# 663fc0ef) and the c528 fixes hold (heapclr x3, member-6
# dests real x3, r31=0A zero) - but the trajectory SWUNG
# (the receipted nondeterminism): the fetch-wedge class
# NEVER occurred (zero zrfF, zero R967 STUCK), so the
# widen stands ARMED as a guard, untested by this run.
# THE NEW TERMINAL STATE, receipted: the boot looped twice
# with no era handoff, the R844 bypass forced the
# field-coordinator door 0x80077E88, the R1394 guard found
# the live module != the emit-era ref and INTERPRETED it
# (never the wrong translation), and the interpreter ran
# the live code until CONTROL LEFT THE WINDOW WITHOUT A
# JUMP at pc=0x80090000 - the honest class-3 stop, capture
# preserved (ovlstop_capture.bin 135168 bytes), exit 99 as
# designed. THE OPEN QUESTIONS: (1) what is the
# interpreter WINDOW definition (the capture is 135168
# bytes from 0x80077E88 = 0x80077E88..0x80098E88, and
# pc=0x80090000 is INSIDE that range - so the window the
# stop names must be something else: the module's declared
# extent?); (2) what did control fall into at 0x80090000
# (the capture holds the bytes); (3) what broke the two
# boots (the stompcam -1 fill class at fn 80033B34?).
# THIS CENSUS: (1) the R1394 interpreter source (the
# window bounds, the class-3 condition, any step/last-pc
# camera); (2) ALL the ovl-family receipts this run; (3)
# the capture boundary analysis (a python hexdump around
# the stop pc + the module head words); (4) the boot-loop
# context (the restarts + the bypass + the stomp family);
# (5) the fetch-class receipts (confirm the swing).
# Fail-closed, tee'd to /tmp/c532_receipts.txt.
# Pure-ASCII output.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C532-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c532_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="663fc0efdb3620943ad1940e1d0892847805dcaab1508fec91f4f0ef6eaae7b7"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the c531 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the c531 tree with the landed zrfF command-byte widen)"
LOG="run.log"
if [ ! -s "$LOG" ]; then echo "GATE-FAILED: no run.log"; exit 0; fi
echo "LOG=run.log ($(wc -l < "$LOG" | tr -d " ") lines)"
echo "===INTSRC532=== the R1394 interpreter source: the window definition + the class-3 stop"
grep -n -e "R1394" "$SRC" | head -16
S1=$(grep -n -F -e "CONTROL OUTSIDE WINDOW" "$SRC" | head -1 | cut -d: -f1)
echo "--- the class-3 stop site (line $S1) with context:"
if [ -n "$S1" ]; then
  _S0=$((S1-40)); [ "$_S0" -lt 1 ] && _S0=1
  sed -n "${_S0},$((S1+12))p" "$SRC"
fi
echo "--- the interpreter window bounds (grep the window/extent terms):"
grep -n -e "ovl_lo" -e "ovl_hi" -e "0x21000" -e "135168" "$SRC" | head -12
echo "===OVLLOG532=== all the ovl-family receipts this run"
grep -n -e "\[ovlint\]" -e "\[ovlstop\]" -e "\[ovlstop\]" -e "\[bypassrec\]" "$LOG" | head -20
echo "===CAP532=== the capture boundary analysis (what did control fall into at 0x80090000?)"
ls -la ovlstop_capture.bin 2>/dev/null || echo "(no capture file)"
python3 - <<'PYEOF'
import struct
BASE = 0x80077E88
STOP = 0x80090000
import os
if not os.path.exists("ovlstop_capture.bin"):
    print("(capture absent - section skipped)")
else:
    d = open("ovlstop_capture.bin","rb").read()
    print("capture size: %d bytes (window %08X..%08X)" % (len(d), BASE, BASE+len(d)))
    off = STOP - BASE
    print("stop pc offset: %d (0x%X) - %s the capture" % (off, off, "INSIDE" if 0 <= off < len(d) else "OUTSIDE"))
    print("--- the module head (first 16 words at 80077E88):")
    for i in range(0, min(64,len(d)), 4):
        w = struct.unpack_from("<I", d, i)[0]
        print("  %08X: %08X" % (BASE+i, w))
    if 0 <= off < len(d):
        print("--- 12 words BEFORE the stop pc:")
        lo = max(0, off-48)
        for i in range(lo, off, 4):
            w = struct.unpack_from("<I", d, i)[0]
            print("  %08X: %08X" % (BASE+i, w))
        print("--- 16 words AT/AFTER the stop pc:")
        for i in range(off, min(len(d),off+64), 4):
            w = struct.unpack_from("<I", d, i)[0]
            print("  %08X: %08X" % (BASE+i, w))
    else:
        print("the fall-through left the capture entirely - the stop pc is past the window end")
    nz = sum(1 for b in d if b)
    print("capture nonzero bytes: %d / %d" % (nz, len(d)))
PYEOF
echo "===BOOT532=== the boot-loop context (what broke the two boots?)"
grep -n -e "fwrestart" -e "bypassrec" "$LOG" | head -12
echo "--- the stomp family receipts (the -1 fill class):"
grep -n -e "stompcam" -e "wdrop" "$LOG" | head -12
echo "--- the last newmod progression (which members installed this era?):"
grep -n -e "\[newmod\]" "$LOG" | tail -6
echo "--- the context before the LAST fwrestart:"
FR=$(grep -n -e "fwrestart" "$LOG" | tail -1 | cut -d: -f1)
if [ -n "$FR" ]; then
  _F0=$((FR-14)); [ "$_F0" -lt 1 ] && _F0=1
  sed -n "${_F0},$((FR+2))p" "$LOG"
fi
echo "===WEDGE532=== the fetch-class receipts (confirm the swing - the class never occurred?)"
grep -c -e "\[zrfF\]" "$LOG" | tr -d " " | sed "s/^/zrfF receipts: /"
grep -c -e "R967 STUCK" "$LOG" | tr -d " " | sed "s/^/R967 STUCK receipts: /"
grep -c -e "fldfrz2" "$LOG" | tr -d " " | sed "s/^/fldfrz2 receipts: /"
grep -c -e "LegacyCdSectorFetch" "$LOG" | tr -d " " | sed "s/^/LegacyCdSectorFetch receipts: /"
echo "===C532DONE=== the interpreter window + the capture boundary are receipted - the c533 decision (the window-definition fix or the fall-through decode) follows from these receipts only - digest is pure ASCII"
