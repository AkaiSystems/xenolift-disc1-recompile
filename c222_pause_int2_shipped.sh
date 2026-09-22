#!/bin/bash
# c222_pause_int2.sh - THE PAUSE-COMPLETION PATCH (R1317), the c219/c221
# decided fix. ONE targeted change at the ONE ack-pair site: cmd 09 PAUSE
# no longer rides the ReadN INT1 data-pair (the R163-era ReadS grouping);
# it takes the PROVEN INT2 second-response path (the R124 block) alongside
# Init/Seek/Stop/GetID - the exact transition the runtime's own receipts
# declare ("idle pause - INT3 then INT2 expected").
# GATES: baseline sha -> anchor-count==1 (both edits) -> exact marker
# counts -> parse gate (pre vs post, restore on break) -> run.sh build +
# 120s receipt run. PASS receipts: "Pause complete: INT2" armed +
# pendclr INT2 cmd=09 + new commands after pauses + the t=30s chain
# advancing. REVERT (next cycle, never mid-run): restore
# patch_c222_*/runtime.c.pre if the game parks post-pause.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C222-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
R="runtime/runtime.c"
[ -s "$R" ] || { echo "C222-FAILED: runtime.c missing"; exit 1; }
SS=$(shasum -a 256 "$R" | cut -d" " -f1)
echo "SRC_SHA_BEFORE=$SS"
if [ "$SS" != "cdfa6b41dacf69db720ed5faec83d0fa477c865082c6accc989845c51038a45c" ]; then echo "GATE-FAILED: not the cdfa6b41 baseline - nothing patched"; exit 0; fi
echo "BASELINE_VERIFIED"
P="patch_c222_$(date +%Y%m%d_%H%M%S)"
if ! (mkdir -p "$P" && cp -p "$R" "$P/runtime.c.pre"); then echo "C222-FAILED: preserve failed"; exit 1; fi
echo "PRESERVED: $P/runtime.c.pre sha=$(shasum -a 256 "$P/runtime.c.pre" | cut -d" " -f1)"
if [ -s run.log ]; then cp -p run.log "$P/run.log.pre"; echo "RUNLOG_PRESERVED sha=$(shasum -a 256 "$P/run.log.pre" | cut -d" " -f1)"; fi

echo "===PATCH222=== the R1317 split (python, binary-safe, FAIL EXPLICIT)"
python3 - <<'PYEOF'
import hashlib, sys
data = open("runtime/runtime.c","rb").read()
a1 = b"(cd_last_cmd == 0x06u || cd_last_cmd == 0x09u)) {\n                /* this ack pair concludes a ReadN's INT3"
c1 = data.count(a1)
print("ANCHOR1 count=%d (must be 1)" % c1)
if c1 != 1: sys.exit(1)
r1 = b"cd_last_cmd == 0x06u) { /* R1317 (c222): PAUSE (09) no longer rides the ReadN INT1 ack-pair - Jos PSX-SPX corrected model; the R163-era ReadS grouping retired */\n                /* this ack pair concludes a ReadN's INT3"
data = data.replace(a1, r1, 1)
a2 = b"cd_last_cmd == 0x1Au)) {"
c2 = data.count(a2)
print("ANCHOR2 count=%d (must be 1)" % c2)
if c2 != 1: sys.exit(1)
r2 = b"cd_last_cmd == 0x1Au\n                    || cd_last_cmd == 0x09u)) { /* R1317 (c222): PAUSE second-response INT2 restored - the R163 removal retracted; Pause ENDS reading per PSX-SPX */"
data = data.replace(a2, r2, 1)
for pat, want, name in [
    (a1, 0, "old-ackpair-gone"),
    (b"|| cd_last_cmd == 0x09u)) {", 1, "new-route"),
    (b"R1317", 2, "marker"),
    (b"Pause complete: INT2 (drive stopped) armed", 1, "pause-print"),
]:
    got = data.count(pat)
    print("MARKER %s want=%d got=%d %s" % (name, want, got, "OK" if got == want else "FAIL"))
    if got != want: sys.exit(1)
open("runtime/runtime.c","wb").write(data)
print("NEW_SHA=" + hashlib.sha256(data).hexdigest())
PYEOF
PYRC=$?
if [ "$PYRC" -ne 0 ]; then
  cp -p "$P/runtime.c.pre" "$R"
  echo "PATCH-FAILED - baseline RESTORED, nothing run"; exit 0
fi
echo "PATCH-APPLIED sha=$(shasum -a 256 "$R" | cut -d" " -f1)"

echo "===PARSE222=== the c182 parse gate (pre vs post; restore on break)"
CC_BIN=""
for c in cc clang gcc; do command -v "$c" >/dev/null 2>&1 && { CC_BIN="$c"; break; }; done
echo "CC_BIN=$CC_BIN"
PRE_RC=99; POST_RC=99
if [ -n "$CC_BIN" ]; then
  "$CC_BIN" -fsyntax-only -std=gnu99 -I runtime "$P/runtime.c.pre" >/dev/null 2>/tmp/c222_pre.txt; PRE_RC=$?
  "$CC_BIN" -fsyntax-only -std=gnu99 -I runtime "$R" >/dev/null 2>/tmp/c222_post.txt; POST_RC=$?
  echo "PARSE pre_rc=$PRE_RC post_rc=$POST_RC"
  head -6 /tmp/c222_post.txt
fi
if [ "$PRE_RC" -eq 0 ] && [ "$POST_RC" -ne 0 ]; then
  cp -p "$P/runtime.c.pre" "$R"; echo "PARSE-BREAK - baseline RESTORED, nothing run"; exit 0
fi
if [ "$PRE_RC" -ne 0 ]; then echo "PARSE-CHECK UNUSABLE (baseline also errors) - deferring to the run.sh build gate"; fi

echo "===RUN222=== the 120s receipt run (run.sh builds + runs; build fail = no run)"
RUN_BUDGET_S=120 ./run.sh > /tmp/run_full_c222.txt 2>&1
echo "RUNSH_RC=$?"
head -20 /tmp/run_full_c222.txt
tail -6 /tmp/run_full_c222.txt
if [ -s run.log ]; then
  cp -p run.log "$P/run.log.post"
  echo "RUNLOG_POST_PRESERVED sha=$(shasum -a 256 "$P/run.log.post" | cut -d" " -f1) size=$(wc -c < "$P/run.log.post" | tr -d " ")"
fi

echo "===PAUSE222=== the Pause INT2 receipts (the c222 PASS evidence)"
if [ -s run.log ]; then
  echo "pause_int2_armed=$(grep -c "Pause complete: INT2" run.log)"
  grep -n "Pause complete: INT2" run.log | head -12
  echo "pause_int2_cleared_cmd09=$(grep "pending INT2" run.log | grep -c "cmd=09")"
  grep -n "pending INT2" run.log | grep "cmd=09" | head -12
  echo "--- every INT2 pendclr:"
  grep -n "pending INT2" run.log | head -12

  echo "===XFER222=== the R1314 pause lines this run"
  grep -n "R1314" run.log | head -12

  echo "===NEWSET222=== the command flow (did the game keep issuing after pauses?)"
  echo "int3_scheduled_total=$(grep -c "INT3 scheduled" run.log)"
  grep "command 0x" run.log | tail -10

  echo "===ABRT222=== the first-fault chain outcome"
  echo "abort130_count=$(grep -c "AbortOnGameFault" run.log)"
  grep -n "AbortOnGameFault\|faultctx\|segvdie" run.log | head -8
  echo "lzss_poison_src=$(grep -c "DEADFA11" run.log)"
  grep -n "unpack-fix" run.log | head -8

  echo "===STATE222=== the state/cur census"
  grep -n "statetbl" run.log | head -4
  grep -o "cur=0x[0-9A-F]*" run.log | sort | uniq -c | sort -rn | head -6
  echo "boot_reentries=$(grep -c "bootmain" run.log) fwrestart=$(grep -c "fwrestart" run.log)"

  echo "===EXIT222=== the exit door + build provenance"
  grep -n "rungasp" run.log | tail -3
  grep -n "bldprov" run.log | head -2

  echo "===SCREEN222=== the visual witnesses"
  grep -n "\[screen\]" run.log | tail -4
else
  echo "NO-RUNLOG - the run did not produce a log (build or launch failure) - see run_full head/tail above"
fi
echo "===C222DONE=== patch cycle complete - verdict from these receipts; REVERT = restore $P/runtime.c.pre"
