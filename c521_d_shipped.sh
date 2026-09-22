#!/bin/bash
# c521_census.sh - READ-ONLY CENSUS of the new park + the
# preserved capture, NO RUN, NO BUILD, NO PATCH. THE c520
# VERDICT: THE R1380 FIX WORKED - the delivery engine ran
# natively at scale (cbcall #191-#200, cd-dma LBA
# 108849-108860 with the full 12+2048-byte protocol, FDF8
# countdown 44528 -> 1520 -> 0 - a multi-sector read
# completing natively), the unpack-on-zeros family is GONE
# (zero receipts), 42 postconv scans / 25 h4 in-context
# dispatches. THE NEW ENDING (receipted): the next request
# (LBA 108861, FDF8 0 -> 23744 armed at line 31881,
# cur_fn=80028740) issues its ReadN (last_cmd=06) but NO
# sector lands for it (cd-dma tail ends at 108860) and NO
# response pend exists (pend=0, sched=1, A22C=0) - the
# pre-movie poll parks (29M+ polls, t=21s), R845 re-forces
# the coordinator door 80077E88, the R1393/R1394 guard
# correctly finds the live module is NOT the emit-era ref,
# INTERPRETS it, the module calls its linker 8003342C with
# a NULL header (lnkcam a0=00000000 OUT-OF-RAM), then hits
# an undefined SPECIAL (fn 0x32) at pc=80070348 - the
# explicit unsupported-overlay stop, capture preserved
# (ovlstop_capture.bin 135168 bytes = 0x21000 = the module
# window 0x8006F000-0x80090000). TWO CLEAN QUESTIONS:
# (1) what happened to the ReadN response at 108861 - the
# chain from the arm (31881) into the park: the cmd issue,
# the rspop/pends, the collector inputs; (2) what the
# captured module bytes say at the stop site (offset
# 0x1348 = 80070348) and the old mismatch site (0x47EC) -
# real module code or garbage. THIS CENSUS: (1) the 108861
# request trace; (2) the log window from the arm into the
# park (31881-31960); (3) the cmd/rspop/pend state around
# it; (4) the collector inputs in the park era; (5) the
# postconv scans' line numbers + slots (did the pass run
# during the park); (6) the capture: sha256 + od dumps at
# the prologue, 0x1348, 0x47EC, 0x8E88 (the coordinator
# entry); (7) the park servicing stats (pollkick/hkick).
# Fail-closed, tee'd to /tmp/c521_receipts.txt.
# Pure-ASCII output.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C521-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c521_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="05535414f7c77fd05cb4bcfeaf91fdbd239baf7e4c9d7c48b529bbaf658d1233"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the c519 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the c519 tree with the landed post-conversion collector pass)"
LOG="run.log"
if [ ! -s "$LOG" ]; then echo "GATE-FAILED: no run.log"; exit 0; fi
echo "LOG=run.log ($(wc -l < "$LOG" | tr -d " ") lines)"
echo "--- the window base receipt (the R1393 module window constant in the tree):"
grep -n -e "0x8006F000" "$SRC" | head -4
echo "===SEEK861=== the LBA 108861 request trace (the unserviced ReadN)"
grep -n -e "108861" -e "0001A93D" "$LOG" | head -24
echo "--- the tail of it:"
grep -n -e "108861" -e "0001A93D" "$LOG" | tail -12
echo "===ARMTAIL=== the log window from the arm into the park (the transition itself)"
sed -n "31878,31962p" "$LOG"
echo "===CMDRSP=== the cmd/rspop/pend state around the arm"
echo "--- the cmdtl ladder tail (the last command transitions):"
grep -n -e "cmdtl" "$LOG" | tail -10
echo "--- the rspop receipts after line 31500 (any response pops in the park era):"
grep -n -e "rspop" "$LOG" | awk -F: '$1 > 31500' | head -12
echo "--- the pendclr receipts after line 31500:"
grep -n -e "pendclr" "$LOG" | awk -F: '$1 > 31500' | head -8
echo "===CDCOL521=== the collector inputs in the park era (the R1361 tail)"
grep -n -e "cdcol" "$LOG" | tail -8
echo "===POSTCONV521=== the postconv scans' line numbers + slots (did the pass run during the park?)"
grep -n -e "post-conversion collector scan" "$LOG" | tail -8
echo "===OVLDUMP=== the preserved capture (the module window at the stop)"
CAP="ovlstop_capture.bin"
if [ ! -s "$CAP" ]; then echo "GATE: no ovlstop_capture.bin"; else
  echo "size: $(wc -c < "$CAP" | tr -d " ") sha256: $(shasum -a 256 "$CAP" | cut -d" " -f1)"
  echo "--- the module prologue (offset 0, 64 bytes):"
  od -A x -t x1 -j 0 -N 64 "$CAP"
  echo "--- offset 0x1348 = pc 80070348 (the undefined SPECIAL site, 80070340-8007035F):"
  od -A x -t x1 -j 4928 -N 32 "$CAP"
  echo "--- as 32-bit words at 80070348:"
  od -A x -t x4 -j 4936 -N 16 "$CAP"
  echo "--- offset 0x47EC = 800737EC (the old idchk mismatch site):"
  od -A x -t x4 -j 18412 -N 32 "$CAP"
  echo "--- offset 0x8E88 = 80077E88 (the coordinator entry, the interp target):"
  od -A x -t x4 -j 36488 -N 32 "$CAP"
fi
echo "===PARKSVC=== the park servicing stats (pollkick/hkick tails)"
grep -n -e "pollkick" "$LOG" | tail -4
grep -n -e "hkick" "$LOG" | tail -4
echo "===C521DONE=== the unserviced-ReadN chain and the captured module bytes are receipted - the c522 decision follows from these receipts only - digest is pure ASCII"
