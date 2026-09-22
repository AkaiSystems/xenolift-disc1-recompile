#!/bin/bash
# c256_menu_player.sh (v2 of c255) - THE R1326 MENU-ERA VIRTUAL PLAYER
# (one insert,
# v2 CORRECTION (marker gate caught it, nothing written, tree intact
# 98c55c83): patch content UNCHANGED - one marker EXPECTATION was
# wrong: 0x8003569Cu appears 3x in the EXISTING tree (the R811 camera
# plus two other references; my insert adds none), so want=1 was the
# c135-class arithmetic error. Corrected to want=3, confirmed by the
# c255 digest itself (got=3). All other markers passed (R1326=3,
# padvpx=2, press-word=2, release-word=1, r811n=1).
# runtime.c). THE c254 RECEIPTS: the R809 injector is keyed to the dead
# era (fires only inside the mvloop pre-movie spin, mv_n % 524288 - a
# path this era never runs; zero padstart receipts in 190s) AND it
# writes PLAYER 0's buffer (0x800625FC) while the game polls PLAYER 1
# (ReadControllerButtons player(r4)=1 buf=8006261E, btn=BFFF, 28K+
# entries, choice(4F2D8)=0 held forever). THE FIX: inject at the LIVE
# polling posture - inside the R811 site (a==0x8003569C) - into the
# SAME buffer the game reads (0x800625FC + (r[4]&1)*34), PRESERVING
# the game-set status/ID bytes: press = clear START bit3 (btn 0xFFF7),
# re-assert through a ~1s hold, release = restore 0xFFFF. Re-arms per
# boot epoch (the R693 machinery). PASS = the press receipted + the
# menu choice/released cells MOVE (the first press->response proof).
# REVERT = restore the preserved runtime.c.pre.
set -u
cd "$HOME/Downloads/xenolift" || { echo "C255-FAILED: xenolift dir missing"; exit 1; }
export LC_ALL=C
SRC="runtime/runtime.c"
EXPECT="98c55c8305de9ed239d0e4ba428213b8fc5168adc57ef238a213c01c7bf96243"
if [ ! -s "$SRC" ]; then echo "C255-FAILED: runtime/runtime.c missing"; exit 1; fi
SS=$(shasum -a 256 "$SRC" | cut -d" " -f1)
echo "SRC_SHA_BEFORE=$SS"
if [ "$SS" != "$EXPECT" ]; then echo "GATE-FAILED: runtime.c is not the R1325 tree 98c55c83 - refusing a foreign tree"; exit 0; fi
echo "BASELINE_VERIFIED (the R1325 tree)"
P="patch_c255_$(date +%Y%m%d_%H%M%S)"
if ! (mkdir -p "$P" && cp -p "$SRC" "$P/runtime.c.pre"); then echo "C255-FAILED: preserve failed"; exit 1; fi
echo "PRESERVED: $P/runtime.c.pre sha=$SS"

echo "===PATCH255=== the R1326 menu-era virtual player (python, binary-safe, FAIL EXPLICIT)"
python3 - <<'PYEOF' || { echo "PATCH-FAILED - nothing written, no run"; exit 1; }
import hashlib, sys
data = open("runtime/runtime.c","rb").read()
if b"R1326" in data:
    print("IDEMPOTENT-SKIP: R1326 already present - no edit made"); sys.exit(0)

a = b"        static int r811n;\n"
n = data.count(a)
print("R1326 anchor count=%d (must be 1)" % n)
if n != 1: sys.exit(1)

ins = (b"        /* R1326 (c255): THE MENU-ERA VIRTUAL PLAYER. The c252/c253\n"
 + b"         * receipts: the game polls ReadControllerButtons player=1 at\n"
 + b"         * buf=8006261E (btn=BFFF, no presses, 28K+ entries) while the\n"
 + b"         * R809 injector sits keyed to the OLD mvloop path (mv_n\n"
 + b"         * multiples of 524288) which this era never runs - zero padstart\n"
 + b"         * receipts in 190s, choice(4F2D8)=0 held forever. THE FIX:\n"
 + b"         * inject HERE, at the live polling posture, into the SAME\n"
 + b"         * buffer the game reads (0x800625FC + (r[4]&1)*34), PRESERVING\n"
 + b"         * the game-set status/ID bytes: press = clear START bit3 (btn\n"
 + b"         * 0xFFF7), re-assert through a ~1s hold (the game may refresh\n"
 + b"         * the pad), release = restore 0xFFFF. Re-arms per boot epoch\n"
 + b"         * (the R693 machinery). PASS = the press receipted + the menu\n"
 + b"         * choice/released cells MOVE. */\n"
 + b"        {\n"
 + b"            static uint32_t r1326_epoch = 0xFFFFFFFFu;\n"
 + b"            static int r1326_phase; /* 0=armed, 1=pressing, 2=done */\n"
 + b"            static time_t r1326_t0;\n"
 + b"            uint32_t vbuf = 0x800625FCu + (r[4] & 1u) * 34u;\n"
 + b"            if (r1326_epoch != xenolift_boot_epoch) {\n"
 + b"                r1326_epoch = xenolift_boot_epoch; r1326_phase = 0;\n"
 + b"            }\n"
 + b"            if (r1326_phase == 0\n"
 + b"                && (xl_wall() - g_boot_wall_t0) > 5) {\n"
 + b"                r1326_phase = 1; r1326_t0 = xl_wall();\n"
 + b"                { uint32_t cur = xenolift_mem_read32(vbuf);\n"
 + b"                  xenolift_mem_write32(vbuf, (cur & 0xFFFFu) | (0xFFF7u << 16));\n"
 + b"                  r861_out(\"[padvpx] R1326 virtual-player START PRESSED into polled buf %08X (%08X -> %08X) @t=%lds - the menu has its player\\n\",\n"
 + b"                          vbuf, cur, xenolift_mem_read32(vbuf), (long)(xl_wall() - g_boot_wall_t0)); }\n"
 + b"            } else if (r1326_phase == 1) {\n"
 + b"                xenolift_mem_write32(vbuf, (xenolift_mem_read32(vbuf) & 0xFFFFu) | (0xFFF7u << 16));\n"
 + b"                if ((xl_wall() - r1326_t0) >= 1) {\n"
 + b"                    r1326_phase = 2;\n"
 + b"                    xenolift_mem_write32(vbuf, (xenolift_mem_read32(vbuf) & 0xFFFFu) | (0xFFFFu << 16));\n"
 + b"                    r861_out(\"[padvpx] R1326 virtual-player START RELEASED (buf %08X -> %08X) @t=%lds\\n\",\n"
 + b"                            vbuf, xenolift_mem_read32(vbuf), (long)(xl_wall() - g_boot_wall_t0));\n"
 + b"                }\n"
 + b"            }\n"
 + b"        }\n")

data = data.replace(a, ins + a, 1)

checks = [("R1326", data.count(b"R1326"), 3),
          ("padvpx-tag", data.count(b"[padvpx]"), 2),
          ("press-word", data.count(b"(0xFFF7u << 16)"), 2),
          ("release-word", data.count(b"(0xFFFFu << 16)"), 1),
          ("r811n-anchor", data.count(b"static int r811n;"), 1),
          ("padrd-site", data.count(b"0x8003569Cu"), 3)]
ok = True
for name, got, want in checks:
    print("MARKER %s want=%d got=%d %s" % (name, want, got, "OK" if got == want else "FAIL"))
    if got != want: ok = False
if not ok: sys.exit(1)
open("runtime/runtime.c","wb").write(data)
print("NEW_SHA=%s" % hashlib.sha256(data).hexdigest())
PYEOF
echo "PATCH-APPLIED sha=$(shasum -a 256 "$SRC" | cut -d" " -f1)"

echo "===PARSE255=== the syntax gate (pre vs post; restore on break)"
clang -fsyntax-only -std=gnu99 "$SRC" > /tmp/parse_c255_pre.txt 2>&1
PRE_RC=$?
clang -fsyntax-only -std=gnu99 "$SRC" > /tmp/parse_c255_post.txt 2>&1
POST_RC=$?
echo "PARSE pre_rc=$PRE_RC post_rc=$POST_RC"
head -4 /tmp/parse_c255_post.txt
if [ "$PRE_RC" -eq 0 ] && [ "$POST_RC" -ne 0 ]; then
  cp -p "$P/runtime.c.pre" "$SRC"; echo "PARSE-BREAK - baseline RESTORED, nothing run"; exit 1
fi
echo "PARSE OK"

echo "===RUN255=== the 150s receipt run"
RUN_BUDGET_S=150 ./run.sh > /tmp/run_full_c255.txt 2>&1
echo "RUNSH_RC=$?"
head -4 /tmp/run_full_c255.txt
if [ -s run.log ]; then cp -p run.log "$P/run.log.post"; echo "RUNLOG_POST sha=$(shasum -a 256 "$P/run.log.post" | cut -d" " -f1) size=$(wc -c < "$P/run.log.post" | tr -d " ")"; fi

echo "===PADVPX255=== the virtual-player receipts (press + release fired?)"
grep -n "padvpx\]" run.log 2>/dev/null | head -8

echo "===PADRD255=== what the game then read (btn census)"
grep -o "btn=[0-9A-F]*" run.log 2>/dev/null | sort | uniq -c | head -8
echo "--- player census:"
grep -o "player(r4)=[0-9]*" run.log 2>/dev/null | sort | uniq -c | head -4

echo "===MENU255=== THE RESPONSE: did the menu cells move?"
grep -n "menuchain\]" run.log 2>/dev/null | head -12
echo "--- the choice/released cell history:"
grep -o "choice(4F2D8)=[0-9A-F]*" run.log 2>/dev/null | sort | uniq -c | head -8
grep -o "released(8005948C)=[0-9A-F]*" run.log 2>/dev/null | sort | uniq -c | head -8
echo "--- the old padstart (mvloop-keyed) census:"
grep -c "padstart\] R809" run.log 2>/dev/null

echo "===STATE255=== the state + guard census"
echo "bootmain=$(grep -c bootmain run.log 2>/dev/null) traps=$(grep -c "NULL-trap #" run.log 2>/dev/null) abort131=$(grep -c "code=131" run.log 2>/dev/null)"
grep -n "arenaseed\]" run.log 2>/dev/null | head -4
grep -n "active state" run.log 2>/dev/null | tail -5

echo "===SCREEN255=== the scene census"
grep -n "nonblank" run.log 2>/dev/null | tail -3
grep -n "gpufin" run.log 2>/dev/null | tail -1
grep -n "rungasp" run.log 2>/dev/null | tail -1

echo "===C255DONE=== menu-player cycle complete - verdict from these receipts; REVERT = restore $P/runtime.c.pre"
