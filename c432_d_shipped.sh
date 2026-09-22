#!/bin/bash
# c432_lba9.sh - READ-ONLY CENSUS. NO run, NO patch.
# The c431 receipts: R1378 applied (tree 6c916b3f),
# deepest run ever, no guest crash, exit 137 =
# fuse/watchdog SIGKILL. The door never fired
# (correctly: no buffered sector at the park). NEW
# PARK: pre-movie poll at seek=9 cmd=09 FDF8=0x800
# owed A22C=3 - the owed-but-never-issued class.
# OPEN: who wrote FE04=9 and FDF8=0x800? A genuine
# 2048-byte read at the license/system area, or the
# FE04 truncation family (R972 class)? Is a ReadN
# pending behind the Pause? THIS PASS: (1) the FE04
# walk to 00000009 (writers + first occurrence);
# (2) the FDF8 writes to 00000800; (3) the A22C=3
# writers; (4) the cmdtl + pendclr ladder after #55
# (line 30719); (5) the scheduler's tail-era view
# (schdd); (6) the mod6 DRIVE-STATE tail; (7) the
# movie-door receipts; (8) the frc 803-poll evidence
# (why the R1378 door stays silent). Receipts only.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C432-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="6c916b3fc08cc29c92247a12aaea6cd4f294e9c395164490e737ab690b782737"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1378 tree - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1378 tree)"
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
echo "===FE04WALK432=== who wrote FE04=00000009"
grep -n -e "FE04" "$LOG" | grep -e "00000009" | head -12
echo "--- first FE04->9 transition:"
grep -n -e "req.*FE04" "$LOG" | grep -e "-> 00000009" | head -3
grep -n -e "FE04.*->00000009" "$LOG" | head -3
echo "===FDF8W432=== who wrote FDF8=00000800"
grep -n -e "FDF8" "$LOG" | grep -e "00000800" | head -10
echo "===A22CW432=== the A22C=3 evidence"
grep -n -e "A22C" "$LOG" | grep -e "00000003" | head -10
echo "===CMDTAIL432=== the ladder after #55 + pendclr tail era"
grep -n -e "cmdtl" "$LOG" | awk -F: '$1 > 30719' | head -8
grep -n -e "pendclr" "$LOG" | awk -F: '$1 > 30700' | head -10
echo "===SCHDD432=== scheduler decisions tail era"
grep -n -e "schdd" "$LOG" | awk -F: '$1 > 30700' | head -10
echo "===MOD6_432=== the DRIVE-STATE receipts tail"
grep -n -e "DRIVE-STATE" "$LOG" | tail -6
echo "===MVDOOR432=== the movie-door receipts"
grep -n -e "mvdoor" "$LOG" | head -8
grep -c -e "mvdoor" "$LOG"
echo "===FRC432=== the 803-poll counter evidence (why the door stays silent)"
grep -n -e "frc" "$LOG" | tail -4
echo "===REQLIFE432=== the request identity: servelog/fldsec tail"
grep -n -e "servelog" "$LOG" | awk -F: '$1 > 30700' | head -6
grep -n -e "fldsec" "$LOG" | awk -F: '$1 > 30700' | head -6
echo "===C432DONE=== the LBA-9 request identity is receipted - the next repair follows from these receipts only"
