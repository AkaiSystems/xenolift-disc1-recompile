#!/bin/bash
# c387_kick2site.sh - READ-ONLY CENSUS. NO run, NO patch.
# The c386 anatomy: the LOST-REGISTER KICK (kick2) reset a
# HEALTHY file#14 native read at its sector-7 boundary
# (FE04 108940->108933, FDF8 ->FULL 125304, + h2 dispatch)
# while the dest cursor kept advancing - the buffer got the
# first 7 sectors repeated ~6 times, the unpack (word0=
# 0003FAFE present) failed prod=-1 past the repeat, runaway,
# Module-6 fail, boot cycle x3. The kick's premise (FE04
# must equal the request LBA) is false for an active
# multi-sector read. THIS PASS: the kick2 arm+fire site, the
# kick census, and the ack-starve chain - the exact code for
# the R1368 gate (kick2 OFF while cd_read_active==1).
set -u
cd "$HOME/Downloads/xenolift" || { echo "C387-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="52566422c865ec549026ce84b82e19a568b61b0cdd1e78984656a5b55cc437f2"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1367 tree - refusing"; exit 0; fi
echo "BASELINE_VERIFIED (the R1367 tree)"
LOG="run.log"
[ -s "$LOG" ] || LOG="run.log.d"
if [ ! -s "$LOG" ]; then echo "TREE-ROOT-LOG-MISSING"; exit 0; fi
echo "AUTHORITATIVE LOG = $LOG ($(wc -l < "$LOG" | tr -d ' ') lines)"
echo "===KICKREFS387=== every kick2/lost-register reference in runtime.c"
grep -n "kick2\|lost-register" "$SRC" | head -20
echo "===KICKFIRE387=== the kick2 fire block (+-45 around the lost-register print)"
LG=$(grep -n "lost-register kick:" "$SRC" | head -1 | cut -d: -f1)
echo "print at line $LG"
if [ -n "$LG" ]; then
  S=$((LG-45)); [ $S -lt 1 ] && S=1
  E=$((LG+25))
  awk -v s="$S" -v e="$E" 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
fi
echo "===KICKARM387=== the kick2 arm site (+-30 around kick2_armed set)"
LG2=$(grep -n "xenolift_kick2_armed = " "$SRC" | head -1 | cut -d: -f1)
echo "arm set at line $LG2"
if [ -n "$LG2" ]; then
  S=$((LG2-30)); [ $S -lt 1 ] && S=1
  E=$((LG2+15))
  awk -v s="$S" -v e="$E" 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
fi
echo "===KICKCENSUS387=== every kick fire in the fresh log (all three kinds)"
grep -n "lost-register kick:\|fd-kick\|spin-kick" "$LOG" | head -16
echo "lost-register-total $(grep -c "lost-register kick:" "$LOG" || true)"
echo "===KICK2HIST387=== the kick2 arm receipts in the log (which requests armed it?)"
grep -n "kick2_armed\|kick2 armed\|kick2_lba" "$LOG" | head -10
echo "===ACKSTARVE387=== the R561 ackcam site + the starve chain (why resp_n=0 at sector 7?)"
LG3=$(grep -n "ackcam\] R561" "$SRC" | head -1 | cut -d: -f1)
echo "ackcam print at line $LG3"
if [ -n "$LG3" ]; then
  S=$((LG3-35)); [ $S -lt 1 ] && S=1
  E=$((LG3+15))
  awk -v s="$S" -v e="$E" 'NR>=s && NR<=e { print NR": "$0 }' "$SRC"
fi
echo "===ACKHIST387=== the ack starve receipts in the log (the escalation timeline)"
grep -n "ackcam\] R561" "$LOG" | head -12
echo "===FDSC387=== the fd-tick/defib5 escalation receipts near the first kick (11360-11410)"
grep -n "fd-tick\|defib5\|INT1 re-asserted" "$LOG" | awk -F: '$1>=11355 && $1<=11410' | head -14
echo "===C387DONE=== the kick2 site is extracted"
