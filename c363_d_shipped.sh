#!/bin/bash
# c363_post7census.sh - READ-ONLY census of the R1364
# witness. NO patch, NO run. The c362 receipts: the ladder
# advanced past #5 for the first time (ReadN issued, the game
# moved to the F15 asset read at seek=108995 natively), and
# the exit class changed 0 -> 99 (kit/exitdiag door) both
# boots ~51s. THIS PASS: the post-#7 era, the exit-99 door's
# invocation receipts, the fldfrz2 postures, the GPU census.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C363-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="b6874d751e5c7e653f4052ea352ad3cc526c9dd1d50d2e173163169aaf54e92d"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1364 tree - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1364 tree)"
WD="witness_c362_20260917_142426"
LOG="$WD/run.log"
[ -s "$LOG" ] || LOG="$WD/run.log.d"
if [ ! -s "$LOG" ]; then echo "WITNESS-MISSING: the c362 witness is not on disk"; exit 0; fi
echo "WITNESS_LINECOUNT=$(wc -l < "$LOG" | tr -d ' ') lines"
echo "===F15SECT363=== the sectors at the f15 read (LBA 108995+) - did data serve?"
grep -c "sector LBA 1089" "$LOG"
grep -n "sector LBA 10899" "$LOG" | head -8
grep -n "sector LBA 10899" "$LOG" | tail -4
echo "===F15TAB363=== the f15 file-table walk (file#15/16 requests?)"
grep -n "ftab" "$LOG" | awk -F: '$1>=9500' | head -8
echo "===POST7363=== the era after #7 (boot 1, lines 9721-10242): the story between the GetStat and the exit door"
awk -F: '$1>=9721 && $1<=10242' "$LOG" | grep -n "cmdtl\|pendclr\|response consumed\|fd-tick\|wgen\|wpair\|wserve\|wopflag\|wconv\|chg. FE1C\|sector LBA\|ftab\|trail\|fldfrz\|parkcam\|actchg" | head -24
echo "===EXITDOOR363=== the exit-99 story: the last 40 receipts before each exit"
grep -n "rungasp" "$LOG"
EL=$(grep -n "rungasp" "$LOG" | head -1 | cut -d: -f1)
echo "--- boot1 last-40 before line $EL ---"
awk -v s="$((EL-40))" -v e="$EL" 'NR>=s && NR<=e' "$LOG"
EL2=$(grep -n "rungasp" "$LOG" | tail -1 | cut -d: -f1)
echo "--- boot2 last-40 before line $EL2 ---"
awk -v s="$((EL2-40))" -v e="$EL2" 'NR>=s && NR<=e' "$LOG"
echo "===DOORTAG363=== the exitdiag/kit door receipts"
grep -n "exitdiag\|EXITDIAG\|kit door\|_exit" "$LOG" | head -10
echo "===FLDFRZ363=== the freeze postures (when/where)"
grep -n "fldfrz2" "$LOG" | head -10
echo "===GPU363=== the GPU census"
grep -n "gpufin" "$LOG" | head -4
grep -n "screen. R69" "$LOG" | tail -4
echo "===A22C363=== the CD-data-arrived flag story after the serve"
grep -n "chg.*A22C\|A22C" "$LOG" | awk -F: '$1>=9531 && $1<=10242' | head -8
echo "===C363DONE=== the post-#7 + exit-door story is receipted"
