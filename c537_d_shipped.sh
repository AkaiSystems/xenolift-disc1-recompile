#!/bin/bash
# c537_census.sh - READ-ONLY BRANCH-DISCRIMINATING CENSUS of
# the file#2 second-read hang, NO RUN, NO BUILD, NO PATCH.
# THE c536 VERDICT (Jos framework): the FIRST file#2 read
# was HEALTHY end-to-end (sectors 108768/108769 fetched and
# delivered, FDF8 counting 33008->30960, the DATA HANDLER
# entered, INT1 flagged) - the mid-file stall read of c535
# is RETRACTED (the sgdecline context shows the read
# actively progressing). THE BREAK IS AT THE READ-1 ->
# READ-2 BOUNDARY: the re-armed request (FDF8 back to the
# full 61680, FE04=0x1A8D2 = the RAW directory-entry value
# while the ftab decoder prints LBA=108754, seek=108754,
# act=1) NEVER FETCHED SECTOR 1 - zero fetchcam after #396,
# zero cd-dma, loaded=0 pos=0/0 for 60+s (R967 STUCK 1-6)
# while FDFC(4F)=1 (a DataReady flag at the controller
# cell with an EMPTY FIFO - notification without arrival)
# and the game cells never move (FDFC(5F)=0, A22C=0 with
# 825 guest reads and zero sets per R1197, FE1C=02).
# BRANCHES NOT YET DISTINGUISHED: A (the re-arm never
# issued a new Setloc/ReadN - last_cmd=06 may be STALE
# from read 1, act=1 possibly never cleared) vs B (issued
# but the fetch path declined). THE PENDING-INT3 THREAD
# (Jos serialization reference): a penddossier at the
# read-1 era shows type=INT3 site=6 cmd=06 seek=108754
# clears=7 - whether it was EVER acknowledged across the
# boundary is OPEN; a later response can wait on it.
# THIS CENSUS RECEIPTS: (1) the FDF8 write trail 26000+
# (read 1 completion -> the re-arm moment -> frozen, with
# writer fns); (2) the command-issue receipts in the final
# era + THE SEQUENTIAL COUNTERS (fetchcam/cd-dma numbers
# are sequential, so their silence after the boundary is
# DECISIVE if the numbering never resumes); (3) the
# read_active (act) provenance - who set act=1 and whether
# it ever returned to 0 between the reads; (4) the
# pend/ack lifecycle across the boundary (penddossier +
# pendclr + interrupt-acknowledged); (5) the FDFC(4F)=1
# writer; (6) the FE04/FE08 writers (raw-vs-decoded LBA +
# the 8006FAF8-allocated vs 80076AF8-delivered destination
# question). Fail-closed, tee'd to /tmp/c537_receipts.txt.
# Pure-ASCII output.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C537-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c537_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="cc637bfb05891064a87390bd8918bf7a1742c45f458a2796bcece5cab02b1602"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the c534 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the c534 tree with the landed R1396 empty-door guard)"
LOG="run.log"
if [ ! -s "$LOG" ]; then echo "GATE-FAILED: no run.log"; exit 0; fi
echo "LOG=run.log ($(wc -l < "$LOG" | tr -d " ") lines)"
echo "===FDF8TRAIL537=== the FDF8 write trail in the final era (read 1 completion -> re-arm -> frozen)"
grep -n -e "ea=8004FDF8" "$LOG" | awk -F: '$1 > 26000' | head -30
echo "--- the last FDF8-related writes of the run:"
grep -n -e "ea=8004FDF8" "$LOG" | tail -3
grep -n -e "FDF8 ARM" "$LOG" | tail -4
echo "===CMD537=== the command-issue receipts in the final era + the sequential counters"
grep -n -e "Setloc" "$LOG" | awk -F: '$1 > 30000' | head -8
grep -n -e "cdw02" "$LOG" | tail -4
grep -n -e "cmdtl" "$LOG" | awk -F: '$1 > 30000' | head -6
grep -n -e "fsent" "$LOG" | awk -F: '$1 > 30000' | head -6
echo "--- the sequential counters (silence after these numbers is decisive):"
grep -n -e "fetch entry #" "$LOG" | tail -2
grep -n -e "cd-dma" "$LOG" | tail -2
grep -n -e "INT1" "$LOG" | awk -F: '$1 > 30000' | head -6
grep -n -e "skipgate" "$LOG" | awk -F: '$1 > 30000' | head -6
grep -n -e "interrupt acknowledged" "$LOG" | awk -F: '$1 > 30000' | tail -4
echo "===ACT537=== the read_active provenance (who set act=1, the idle windows)"
grep -n -e "read_act" "$LOG" | awk -F: '$1 > 30000' | head -10
grep -n -e "read_active" "$LOG" | awk -F: '$1 > 30000' | head -6
echo "===PEND537=== the pend/ack lifecycle across the read boundary"
grep -n -e "penddossier" "$LOG" | awk -F: '$1 > 26000' | head -8
grep -n -e "pendclr" "$LOG" | awk -F: '$1 > 26000' | head -8
echo "===FDFC537=== the FDFC(4F)=1 provenance (the DataReady flag with an empty FIFO)"
grep -n -e "8004FDFC" "$LOG" | awk -F: '$1 > 26000' | head -10
grep -n -e "FDFC(4F)" "$LOG" | head -4
grep -n -e "8005FDFC" "$LOG" | head -4
echo "===FE04537=== the FE04/FE08 writers in the final era (raw-vs-decoded LBA + the destination question)"
grep -n -e "ea=8004FE04" "$LOG" | awk -F: '$1 > 26000' | head -12
grep -n -e "80076AF8" "$LOG" | head -6
grep -n -e "8006FAF8" "$LOG" | awk -F: '$1 > 26000' | head -8
echo "===C537DONE=== the branch-discriminating receipts are in - the A-vs-B verdict and the c538 fix follow from these receipts only - digest is pure ASCII"
