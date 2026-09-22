#!/bin/bash
# c308_retire_mvdoor.sh - R1339: RETIRE the movie-door delivery
# (observe-only). The c307 receipts convicted it: it fired within
# ~1-2s of the game's OWN f15 arm (FE04->108995, FDF8->92180,
# F0C 0x0E->0x0F at fn 801CCD20/28), delivered 46 sectors from
# the STALE cd_seek_lba=108933 to the STALE dst FE08=800A9994
# (wrong file, wrong buffer), then ZEROED FDF8/FE04/FE1C and set
# transfer-DONE - the forged-completion class (R1179: the game
# must finish its own read). The game's queue accounting
# (ArchiveQueuedReadReadyCallback) never sees the raw memcpy:
# no INT1s, no queue advance, no callback - 17 mount refires.
# The normal path is proven alive (file#14 READ ISSUED 3x; the
# c350-era f15 read completed).
# THIS CYCLE: (1) preserve the pre tree; (2) R1339 - make the
# streak gate unreachable + add the observe-only [mvdoor-retired]
# print at streak==2 (cells intact); (3) parse gate (restore on
# fail); (4) 120s run under XENOLIFT_FIRSTFAULT_STOP=1; (5) full
# census: the retired-door receipts, READ ISSUED (the file#15
# watch!), mount refire count, cmdtl, fld2sig tail, faults,
# state, visuals, run tail.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C308-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="82853e3bc9c2b5be37c893f608f4f57b46123a2c9ff829c47a03e589a9b5dccd"
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1338b tree 82853e3b - refusing, nothing done"; exit 0; fi
echo "BASELINE_VERIFIED (the R1338b tree)"
TS=$(date +%Y%m%d_%H%M%S)
mkdir -p "patch_c308_$TS"
cp -p "$SRC" "patch_c308_$TS/runtime.c.pre"
echo "PRESERVED: patch_c308_$TS/runtime.c.pre"
python3 - <<'PYEOF'
data = open("runtime/runtime.c", "rb").read()
lines = data.split(b"\n")
anchor = b"if (r887_streak >= 2u) {"
hits = [i for i, l in enumerate(lines) if anchor in l]
print("ANCHOR count=%d (must be 1)" % len(hits))
if len(hits) != 1:
    print("PATCH-FAILED - anchor count wrong - nothing written, no run")
    raise SystemExit(0)
i = hits[0]
line = lines[i]
indent = line[:len(line) - len(line.lstrip())]
obs = (indent + b"if (r887_streak == 2u) { /* R1339 (c308) observe-only: print at the first hold, then no delivery */\n" +
       indent + b"    static int r1339_n;\n" +
       indent + b"    if (r1339_n++ < 8u) r861_out(\"[mvdoor-retired] R1339 armed-idle hold observed (owes=%08X seek_lba=%u cmd=%02X FE04=%08X FE08=%08X) - delivery RETIRED per c307 conviction; the game's own ReadN path owns the request\\n\", r879_fdf8, cd_seek_lba, cd_last_cmd, xenolift_mem_read32(0x8004FE04u), xenolift_mem_read32(0x8004FE08u));\n" +
       indent + b"}")
retired = (indent + b"if (r887_streak >= 2000000000u) { /* R1339 (c308): RETIRED - c307 convicted the delivery: it fired within ~1-2s of the game's OWN f15 arm (FE04->108995 FDF8->92180 F0C 0x0E->0x0F at fn 801CCD20/28), delivered 46 sectors from the STALE cd_seek_lba=108933 to the STALE dst FE08=800A9994, then zeroed FDF8/FE04/FE1C and set transfer-DONE - forged-completion class (R1179: the game must finish its own read). The normal path works (file#14 READ ISSUED 3x; the c350-era f15 read completed). Was: if (r887_streak >= 2u) */")
pre_checks = [(b"R1339", 0), (b"[mvdoor-retired]", 0), (b"2000000000u", 0), (b"r887_streak == 2u", 0)]
for tok, want in pre_checks:
    c = data.count(tok)
    print("PRE %s count=%d (must be %d)" % (tok.decode(), c, want))
    if c != want:
        print("PATCH-FAILED - pre-token wrong - nothing written, no run")
        raise SystemExit(0)
lines[i] = obs + b"\n" + retired
post = b"\n".join(lines)
checks = [(b"R1339", 3), (b"[mvdoor-retired]", 1), (b"2000000000u", 1), (b"r887_streak == 2u", 1),
          (b"if (r887_streak >= 2u) {", 0), (b"if (r887_streak >= 2000000000u) {", 1),
          (b"mvdoor-retired] R1339 armed-idle", 1)]
for tok, want in checks:
    c = post.count(tok)
    print("POST %s count=%d (must be %d)" % (tok.decode(), c, want))
    if c != want:
        print("PATCH-FAILED - post-token wrong - nothing written, no run")
        raise SystemExit(0)
open("runtime/runtime.c", "wb").write(post)
print("PATCH-APPLIED (R1339 retire, observe-only)")
PYEOF
SS2=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "NEW_SHA=$SS2"
clang -fsyntax-only -std=gnu99 "$SRC" 2>/tmp/c308_parse.txt; PRC=$?
echo "PARSE_RC=$PRC"
if [ "$PRC" != "0" ]; then echo "PARSE-FAILED - reverting"; head -5 /tmp/c308_parse.txt; cp -p "patch_c308_$TS/runtime.c.pre" "$SRC"; exit 0; fi
echo "PARSE-OK"
echo "===RUN308=== the R1339 retire build, 120s budget, first-fault stop"
XENOLIFT_FIRSTFAULT_STOP=1 RUN_BUDGET_S=120 bash run.sh > /tmp/run_full_c308.txt 2>&1; RRC=$?
echo "RUN_RC=$RRC"
WDIR="witness_c308_$TS"; mkdir -p "$WDIR"
for f in run.log run.log.d; do [ -f "$f" ] && cp -p "$f" "$WDIR/$f"; done
cp -p /tmp/run_full_c308.txt "$WDIR/run_full.txt"
echo "WITNESS=$WDIR"
LOG="run.log"; [ -s "$LOG" ] || LOG="run.log.d"
echo "===RETIRE308=== the observe-only receipts (armed-idle holds, cells intact)"
grep -n "mvdoor-retired" "$LOG" | head -10
echo "--- any legacy door fires (must be ZERO R879/R892):"
grep -c "R879 MOVIE-DOOR\|R892 ARCHIVE-TRANSFER-DONE" "$LOG"
echo "===F15WATCH308=== the game's own f15 read (the success verdict)"
grep -n "file#=15\|file#15" "$LOG" | head -8
grep -n "READ ISSUED" "$LOG"
echo "===MOUNT308=== mount lifecycle census"
grep -c "mount-success refire" "$LOG"
grep -n "mount-success" "$LOG" | head -4
echo "===FAULT308=== fault census"
grep -c "computed-garbage" "$LOG"
FF=$(grep -n "computed-garbage address" "$LOG" | head -1 | cut -d: -f1)
echo "FIRST_FAULT_LINE=$FF"
if [ -n "$FF" ]; then awk -v s="$((FF-6))" -v e="$((FF+6))" 'NR>=s && NR<=e' "$LOG"; fi
echo "===SPIN308=== the wedge posture now (mvloop tail + f14pump + schdd)"
grep -n "f14pump" "$LOG" | tail -4
grep -n "schdd" "$LOG" | tail -6
grep -n "mvdoor-near" "$LOG" | tail -4
echo "===VIS308=== visuals"
grep -n "nonblank" "$LOG" | tail -4
grep -n "gpufin" "$LOG" | tail -2
echo "--- run tail:"
tail -8 /tmp/run_full_c308.txt
grep -n "rungasp" "$LOG" | tail -2
echo "===C308DONE=== R1339 retire run complete - the normal-path verdict comes from these receipts"
