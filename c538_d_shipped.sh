#!/bin/bash
# c538_census.sh - READ-ONLY CENSUS: the uncapped command
# trails + the fallback re-read's unnamed writers, NO RUN,
# NO BUILD, NO PATCH. THE c537 DECODE (three corrections):
# (1) READ 1 OF FILE#2 COMPLETED - the FDF8 trail is a
# continuous healthy countdown (61680 -> 22000 receipted
# at print #999, still counting) and the R1360 Pause
# receipt at 30335 shows FDF8=0 - read 1 FINISHED; the
# c535/c536 'stalled mid-file' reading is RETRACTED (the
# sgdecline context was mid-read-1, delivery continued).
# (2) THE FINAL ERA IS THE MOVIE CHAIN + FALLBACK: file#18
# member 1 read active (30197 frc: seek=109158 FDF8=14360
# data_loaded=1), member 2 attempt at LBA 109166 (Setloc
# 30003, cmdtl #21-#23, FDF8=88604 - nonzero, odd), then
# cmd 06->09 PAUSE with R1360 clearing read_active
# (30334-30335), then Setloc 00:00:00 (R1262-clamped to
# LBA 0), then Setloc 24:12:04 -> 108754 (30836) - the
# fallback re-seeking the archive - then the drive IDLES
# (30848 stalecd-near: read_active=0 seek=108754
# seekmism=0) and the stuck posture forms (act=1 cmd=06
# sched=1 FDF8=61680 re-armed, loaded=0, 60+s, A22C=0).
# (3) THE CMD=06 IN THE STUCK ERA HAS NO CMDTL TRANSITION
# RECEIPT - the cmdtl camera is UNCAPPED (26 prints, last
# at 30587 = cmd 0x0a), so the 06 was written by a path
# that camera does NOT watch. UNNAMED: who wrote cmd=06,
# who set act=1 after 30848, who re-armed FDF8=61680 (the
# finstamp trail went dark at its #999 PRINT CAP, not at
# the event), who set FDFC(4F)=1 (no write receipt
# exists), the member-2 FDF8=88604 provenance, whether
# the member-2 sequence is the c481 never-arms class.
# ALSO: the c537 head-caps (head-6/head-8 on cmdtl/Setloc)
# truncated the decisive tails - THIS census re-runs them
# UNCAPPED. SECTIONS: (1) RUNID538 the executable identity
# (Jos provenance requirement); (2) CMDTAIL538 the FULL
# cmdtl + Setloc + command-family trails (no caps); (3)
# REARM538 the second FDF8=61680 arm writers; (4) M2CHAIN
# the member-2 (109166) chain + the Pause window; (5)
# ACT538 the act/read_active setters 30840-31020; (6)
# CMDCELL the cmd=06 writer + the scheduler receipts; (7)
# FDFCW the FDFC(4F) writer + source watch; (8) POLICY the
# print-policy source checks (the finstamp/fetchcam caps)
# that make the silences interpretable. Read-only,
# fail-closed, tee'd to /tmp/c538_receipts.txt.
# Pure-ASCII output.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C538-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
exec > >(tee /tmp/c538_receipts.txt) 2>&1
SRC="runtime/runtime.c"
EXPECT="cc637bfb05891064a87390bd8918bf7a1742c45f458a2796bcece5cab02b1602"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: not the c534 tree - refusing"; exit 0; fi
echo "TREE_VERIFIED (the c534 tree with the landed R1396 empty-door guard)"
LOG="run.log"
if [ ! -s "$LOG" ]; then echo "GATE-FAILED: no run.log"; exit 0; fi
echo "LOG=run.log ($(wc -l < "$LOG" | tr -d " ") lines)"
echo "===RUNID538=== (1) the executable identity (which binary generated this log)"
ls -la xenogears_boot_040456 2>/dev/null || echo "executable not in tree root - searching:"
find . -maxdepth 3 -name "xenogears_boot*" -not -path "./duckstation/*" 2>/dev/null | head -4
shasum -a 256 xenogears_boot_040456 2>/dev/null | cut -d" " -f1 | sed "s/^/EXE_SHA256=/"
head -6 "$LOG"
grep -n -e "rungasp" "$LOG" | tail -2
echo "===CMDTAIL538=== (2) the FULL command trails (uncapped - the c537 head-6 truncated these)"
echo "--- the FULL cmdtl ladder (all prints):"
grep -n -e "cmdtl" "$LOG" | tail -24
echo "--- ALL Setloc receipts after 30000 (uncapped):"
grep -n -e "Setloc" "$LOG" | awk -F: '$1 > 30000'
echo "--- the command-family receipts 30836-31120 (clamps, assists, steppers):"
grep -n -e "R1262" -e "FIELD-SEEK" -e "stepper" -e "cdw02" -e "R1360" "$LOG" | awk -F: '$1 >= 30836 && $1 <= 31120' | head -24
echo "===REARM538=== (3) the second FDF8=61680 arm (who re-armed after read 1 completed)"
grep -n -e "INSTALLRESET" "$LOG" | head -8
grep -n -e "FDF8 ARM" "$LOG" | awk -F: '$1 > 24000'
echo "--- the member-identity lookups after 30000 (which member the fallback requests):"
grep -n -e "stab" -e "ftab" "$LOG" | awk -F: '$1 > 30000' | head -10
echo "===M2CHAIN538=== (4) the member-2 (109166) chain + the Pause window"
grep -n -e "109166" -e "aa6e" "$LOG" | head -18
echo "--- the Pause window (30320-30395, line-numbered):"
awk 'NR>=30320 && NR<=30395 {print NR": "$0}' "$LOG" | head -28
echo "===ACT538=== (5) the act/read_active setters 30840-31020 (who set act=1 after the 30848 idle)"
grep -n -e "read_active" -e "stalecd" -e "frc" -e "R1360" "$LOG" | awk -F: '$1 >= 30840 && $1 <= 31020' | head -20
echo "===CMDCELL538=== (6) who wrote cmd=06 after 30587 (the no-transition write) + the scheduler trail"
grep -n -e "last_cmd" "$LOG" | awk -F: '$1 > 30587' | head -16
echo "--- the scheduled-read receipts after 30836 (the sgarm/fsent trail):"
grep -n -e "fsent" -e "sgdecline" -e "sgarm" "$LOG" | awk -F: '$1 > 30836' | head -12
echo "===FDFCW538=== (7) who set FDFC(4F)=1 (no write receipt exists yet)"
grep -n -e "8004FDFC" "$LOG" | grep -v -e "wedgespin" | head -12
echo "--- does ANY runtime camera watch writes to 0x8004FDFC (source check):"
grep -n -e "0x8004FDFC" "$SRC" | head -8
echo "===POLICY538=== (8) the print-policy source checks (the silences must be interpretable)"
echo "--- the finstamp budget (why the FDF8 trail went dark at #999):"
grep -n -e "r1248_n" "$SRC" | head -5
echo "--- the fetchcam budget (the #400 last print):"
grep -n -e "r1247_n" "$SRC" | head -5
echo "--- the fdw ARM budget (R1299):"
grep -n -e "r1299_n" "$SRC" | head -5
echo "===C538DONE=== the uncapped trails + the unnamed writers + the print policies are receipted - the c539 fix follows from these receipts only - digest is pure ASCII"
