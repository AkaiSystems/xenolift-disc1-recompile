#!/bin/bash
# xenolift standardized run pipeline (R91+)
# Disc path CONFIRMED 2026-09-10 by Jos (ls -la verified, 718738272 bytes):
# the doubled "Xenogears (USA) (Disc 1)" folder nesting is real — no glob.
BIN="${XG_DISC_BIN:-$HOME/Desktop/PS7Z/PS1Games/Xenogears (USA) (Disc 1)/Xenogears (USA) (Disc 1)/Xenogears (USA) (Disc 1).bin}"

# R1236 (c80): receipt the resolved disc path; warn loudly if absent.
echo "[disc] R1236 disc path resolved: $BIN"
if [ ! -f "$BIN" ]; then echo "[disc] WARNING: disc image NOT FOUND at resolved path - set XG_DISC_BIN to your disc image; file reads will fail"; fi
# R1235 (c79): disc image path is CONFIGURABLE - export XG_DISC_BIN=/path/to/disc.bin
# to run against a disc image anywhere; the default stays the original Mac path.
if [ -f "$BIN" ]; then echo "[disc] BIN=$BIN (found)"; else echo "[disc] BIN=$BIN (NOT FOUND - export XG_DISC_BIN to point at the disc image, else the runtime runs disc-less and CD data reads fail)"; fi
export PATH="$HOME/.cargo/bin:$PATH"
cd "$(dirname "$0")"
# R541 [liftctl]: seed the live patch panel from env (jdBasic posture)
if [ -n "$LIFTCTL_CMDS" ]; then
  printf '%s\n' $LIFTCTL_CMDS | tr ';' '\n' > liftctl
fi

echo "--- build ---"
# R151 FAST PIPELINE: emit only when the Rust tool changed (binary md5),
# compile only changed sources (.cache/*.o), link only when needed.
# Cuts an unchanged cycle from ~60s of rebuild to ~3s. Cache files
# (disc1.c/.cache/.emit.md5) are never packaged, so they survive
# package updates and re-detect exactly what changed.
T0=$(date +%s); TS=$T0
echo "run.sh build R1024"
stage(){ local now=$(date +%s); echo "[timing] $1: $((now-TS))s (cycle total: $((now-T0))s)"; TS=$now; }
md5q(){ if command -v md5 >/dev/null 2>&1; then md5 -q "$1" 2>/dev/null; else md5sum "$1" 2>/dev/null | cut -d" " -f1; fi; }
# R233 CARGO MD5 GATE (Jos speed ask): unzip -o stamps fresh mtimes on every
# file, so cargo rebuilt the IDENTICAL Rust tool every cycle (~7s of the 8s).
# Hash the SOURCE CONTENT; skip the rebuild when it is unchanged.
SRC_HASH=$( (cat Cargo.toml; find src -name '*.rs' -type f | sort | xargs cat) 2>/dev/null | md5 2>/dev/null)
[ -z "$SRC_HASH" ] && SRC_HASH=$( (cat Cargo.toml; find src -name '*.rs' -type f | sort | xargs cat) 2>/dev/null | md5sum 2>/dev/null | cut -d" " -f1)
# R236: the md5 gate alone is NOT enough — cycle-22 shipped a foreign-arch
# target/ tree that CLOBBERED the native tool binary, then the gate skipped
# the rebuild that would have healed it = dead cycle. The skip now ALSO
# requires the binary to be a NATIVE executable: on Darwin, an ELF magic
# header (a foreign binary) forces a rebuild; a missing/garbage binary forces
# a rebuild. The gate can never strand a broken tool again.
CARGO_SKIP=1
# R251 EXEC-FIRST HEALTH GATE: run the tool before deciding anything.
# rc 126 (cannot execute) / 127 (not found) = foreign-arch or corrupt
# binary = force the rebuild regardless of the md5 gate.
TOOLRC=0
if [ -x target/release/xenolift ]; then
  ./target/release/xenolift >/tmp/xl_tool_out.txt 2>&1 </dev/null
  TOOLRC=$?
  TOOLOUT=$(head -c 200 /tmp/xl_tool_out.txt | tr '\n' ' ')
  echo "tool health: exec rc=$TOOLRC magic=$(LC_ALL=C head -c 4 target/release/xenolift 2>/dev/null | LC_ALL=C od -An -tx1 | tr -d ' \n') out=[$TOOLOUT]"
  # R253 POSITIVE PROOF: a healthy tool prints its own usage line. Anything
  # else (silence, "cannot execute", "Bad CPU type") = rebuild. Exit-code
  # heuristics alone were ambiguous on macOS bash (R252 cycle-1).
  if ! grep -q "usage: xenolift" /tmp/xl_tool_out.txt 2>/dev/null; then TOOLRC=126; fi
fi
if [ "$TOOLRC" -eq 126 ] || [ "$TOOLRC" -eq 127 ]; then
  CARGO_SKIP=0
  echo "cargo: rebuild (tool does not execute rc=$TOOLRC — foreign/corrupt binary)"
fi
if [ ! -x target/release/xenolift ]; then
  CARGO_SKIP=0
  echo "cargo: rebuild (binary missing)"
elif [ "$(uname)" = "Darwin" ] && [ -f target/release/xenolift ] && LC_ALL=C head -c 4 target/release/xenolift | LC_ALL=C grep -q 'ELF'; then
  CARGO_SKIP=0
  echo "cargo: rebuild (binary is FOREIGN-ARCH — clobbered by an unzip; healing)"
fi
if [ "$CARGO_SKIP" = "1" ] && [ -f .cargo.md5 ] && [ "$(cat .cargo.md5)" = "$SRC_HASH" ]; then
  echo "cargo: SKIPPED (Rust source content unchanged — md5 gate)"
else
  # R239: the old `cargo ... | tail -3 || exit 1` tested TAIL's exit code —
  # cargo failures were silently swallowed (pipe class, same as the cc loop).
  cargo build --release > .cargo_out.txt 2>&1
  CRC=$?
  tail -3 .cargo_out.txt
  if [ "$CRC" -ne 0 ]; then
    echo "FATAL: cargo build failed (rc=$CRC) — see .cargo_out.txt above"
    exit 1
  fi
  echo "$SRC_HASH" > .cargo.md5
fi
# R239 exec-smoke: if a fresh emit is ever needed, the tool MUST execute.
# 126 = cannot execute (foreign arch / broken), 127 = not found.
./target/release/xenolift >/dev/null 2>&1 </dev/null
TRC=$?
if [ "$TRC" -eq 126 ] || [ "$TRC" -eq 127 ]; then
  echo "FATAL: emitter tool will not execute (rc=$TRC) — fresh emits impossible; heal required"
  exit 1
fi
stage "cargo build"
NEWHASH=$(md5q target/release/xenolift)
# R703: fold the overlay fault-capture into the emit cache key - a NEW capture
# (real field-module contents at the wild-jump moment) must force a fresh emit
# so the translator maps it over the pre-install zeros (R681 pipeline live).
# R735: EMIT_REFRESH=1 in the directive block forces a fresh emit remotely
# (the .force file can't be touched from the agent side); default = pinned.
# R769: capture files are PIPELINE INPUTS - fold their md5s into the emit
# cache key ALWAYS (product-correct gate; c344-347 proved the Rust-tool-only
# hash stalls the whole capture-compile feature for ~20 cycles). Identical
# capture content = same hash = cached emit = 1s cycles; changed content =
# automatic fresh emit. EMIT_REFRESH=1 remains as a harmless override.
# R781 CODE-SIGNATURE GATE: raw capture md5s churn EVERY run (era data
# inside the window varies per run: 77-110s recompiles each cycle pushed
# cycle totals to ~242s = past the bridge's ~240s window = EMPTY digests
# c359/360/362/364; full digests only landed on sub-240s cycles). The
# module CODE is stable across same-era runs (nonzero-word counts:
# 31775/32450 three cycles straight) - the churn is staging data, not
# code. Key the gate on each capture's NONZERO-WORD COUNT (the same
# metric the emit prints): stable era = cached emit = 4s cycles; a
# genuinely different capture (new install state, new era) = count
# changes = automatic fresh emit. EMIT_REFRESH=1 remains the override.
for _cap in overlay_fault.bin stage2_region.bin overlay_region.bin; do
  [ -f "$_cap" ] && NEWHASH="$NEWHASH$_cap:nz$(python3 -c "
import sys
d=open('$_cap','rb').read()
n=0
for i in range(0,len(d)-3,4):
    if d[i]|d[i+1]|d[i+2]|d[i+3]: n+=1
print(n)")"
done
# R1020: the gate now accepts EITHER the last-emit hash (.emit.md5) OR the
# post-run hash (.run.md5 stamped at cycle end). c135/c136 receipts: the
# bridge re-unzips the package every cycle; a stale .emit.md5 shipped inside
# the zip (old-format md5) overwrote the Mac's hash each cycle -> guaranteed
# mismatch -> fresh emit -> 146s compile -> run deferred, forever. The
# .run.md5 alternate handles run-duration capture churn (a 24s deferred run
# and an 83s full run die in different states). Genuinely new captures
# (new era, EMIT_REFRESH=1) still trigger fresh emit.
# R1022: the R1020 rewrite accidentally dropped the EMIT_REFRESH=1 force
# (c139 receipt: directive carried EMIT_REFRESH=1, gate still printed
# SKIPPED; comments promised the override the code no longer read - my own
# comment/code mismatch, same class as R1010). Restored: EMIT_REFRESH=1
# always takes the fresh-emit path, hash gates apply only otherwise.
if [ "${EMIT_REFRESH:-0}" != "1" ] && [ -f disc1.c ] && [ -f .emit.md5 ] && { [ "$(cat .emit.md5)" = "$NEWHASH" ] || { [ -f .run.md5 ] && [ "$(cat .run.md5)" = "$NEWHASH" ]; }; }; then
  if [ "$(cat .emit.md5)" = "$NEWHASH" ]; then GHIT=emit; else GHIT=run; fi
  echo "emit: SKIPPED (capture hash stable — matched $GHIT hash; R1020 gate)"
else
  EMIT_TRIES=0
  while true; do
    ./target/release/xenolift SLUS_006.64 disc1.c > emit.log 2>&1 || { tail -5 emit.log; exit 1; }
    # R586 emit self-heal: c154 (and c52 before it) shipped a disc1.c whose
    # guest-image payload was missing ("SLUS EXE LOAD LINE MISSING") — flaky
    # emit raced the .emit.md5 cache gate, boot died in 1s with zeroed guest
    # regs (SIGSEGV at boot entry). Verify the payload marker before trusting
    # the cache; on a bad emit, wipe and retry (max 3).
    if grep -q 'xenolift_region' disc1.c 2>/dev/null && [ $(wc -c < disc1.c) -gt 100000 ]; then
      break
    fi
    EMIT_TRIES=$((EMIT_TRIES+1))
    if [ $EMIT_TRIES -ge 3 ]; then echo "emit: FAIL (no payload after 3 tries)"; tail -5 emit.log; exit 1; fi
    echo "emit: payload missing (try $EMIT_TRIES) - wiping disc1.c + .emit.md5, re-emitting"
    rm -f disc1.c .emit.md5 emit.log
    sleep 1
  done
  printf '%s' "$NEWHASH" > .emit.md5
  echo "emit: DONE (fresh, payload verified)"
  EMIT_FRESH=1
fi

# R224: idempotent post-emit patch: fn_80019548 tail jr-ra honors r[31] dynamically
# (the emitter mistranslated the tail `jr ra` as a fallthrough call into boot main,
#  which hard-restarts the boot every dispatcher pass; only the cold-boot stub case
#  r31==0x80019578 legitimately continues into GameBootstrap)
python3 - <<'XEOF'
s = open('disc1.c').read()
bad = "L_80019558:;\n{\nL_8001955C:;\n/* nop */\nxenolift_fn_80019578_GameBootstrap___Initializes_graphics_input_storage_archives_audio_and_core_resources_before_entering_the_initial_game_state_();\nreturn;\n}\n}"
fix = "L_80019558:;\n{\nL_8001955C:;\n/* nop */\n/* R224 fallthrough-jr-ra guard */\nif (r[31] == 0x80019578u)\n    xenolift_fn_80019578_GameBootstrap___Initializes_graphics_input_storage_archives_audio_and_core_resources_before_entering_the_initial_game_state_();\nreturn;\n}\n}"
if bad in s:
    s = s.replace(bad, fix, 1)
    open('disc1.c','w').write(s)
    print('[emit] R224 fallthrough-jr-ra guard APPLIED')
elif 'R224 fallthrough-jr-ra guard' in s:
    print('[emit] R224 guard already present')
else:
    print('[emit] R224 guard ANCHOR MISSING (emitter output changed) — check manually')
XEOF

# R873: idempotent post-emit patch: ReportSoundDriverError body stub.
# The reporter's emitted body walks the kernel error-dispatch chain and
# jal @0x8003F710 re-dispatches boot entry 0x80019524 -> deterministic
# computed-wild-read fault (c461-463, 32 recoveries never converged).
# Our HLE SPU produces no real transfer errors: the whole body is fuel.
# XTRACE (the [spuerr] receipt) fires first, then the gate returns - the
# caller continues at its own label (clean C return semantics).
python3 - <<'XEOF'
s = open('disc1.c').read()
bad = "XTRACE(0x8003F6B0);\nL_8003F6B0:;"
fix = "XTRACE(0x8003F6B0);\n/* R873 spuerr body stub: HLE SPU errors are artifacts; kill the error-dispatch chain before it re-dispatches the boot entry */\n{ extern int xenolift_spuerr_stub(void); if (xenolift_spuerr_stub()) return; }\nL_8003F6B0:;"
if 'R873 spuerr body stub' in s:
    print('[emit] R873 spuerr body stub already present')
elif bad in s:
    s = s.replace(bad, fix, 1)
    open('disc1.c','w').write(s)
    print('[emit] R873 spuerr body stub APPLIED')
else:
    print('[emit] R873 ANCHOR MISSING (emitter output changed) - check manually')
XEOF

# R902: idempotent post-emit patch: heap-walk terminator guard (fn_80031C58).
# The static decode (disc1.c:80787) proved the walk's advance is
# r[10] = next - 8, and the c496/c498/c499 deterministic install fault is
# the walk standing on next==0 -> 0xFFFFFFF8 -> garbage size math -> split
# handler -> kit fault, 12x/run. Hardware never produces an unlinked
# chain (heap init links the terminator); our heap's last node has
# next=0. GUARD: when next==0, stand on the ARMED heap terminator
# 0x801FBFF8 instead of -8; the walk then reads its 0x00200000 flags
# and takes the clean DA8 end-of-list path (proven healthy in [bankw]).
python3 - <<'XEOF'
s = open('disc1.c').read()
bad = "L_80031C98:;\nr[10] = r[4] + (int32_t)(int16_t)0xFFF8;"
fix = "L_80031C98:;\n/* R902 heap-walk terminator guard: next==0 -> stand on the armed terminator 0x801FBFF8 (flags 0x00200000 -> clean DA8 end) instead of -8 */\nr[10] = (r[4] == 0u) ? 0x801FBFF8u : (r[4] + (int32_t)(int16_t)0xFFF8);"
if 'R902 heap-walk terminator guard' in s:
    print('[emit] R902 walk terminator guard already present')
elif bad in s:
    s = s.replace(bad, fix, 1)
    open('disc1.c','w').write(s)
    print('[emit] R902 walk terminator guard APPLIED')
else:
    print('[emit] R902 ANCHOR MISSING (emitter output changed) - check manually')
XEOF

# R903: idempotent post-emit patch: widen the heap-walk terminator guard to
# EVERY advance site. The emitter duplicated the r[10] = next - 8 pattern at
# THREE sites in the allocator family (fn before 80031C58, fn_80031C58
# itself, and fn_80031CD8 the split handler). R902 guarded only the
# L_80031C98 copy (unique-label anchor); the split-path walk
# (31C58 -> 31D54 -> 31D88 -> 31D9C) runs its own copy and still
# produced r10=0xFFFFFFF8 (cycle 501 receipts). Guard ALL remaining
# copies: next==0 -> stand on the armed terminator 0x801FBFF8.
python3 - <<'XEOF'
s = open('disc1.c').read()
bad = "r[10] = r[4] + (int32_t)(int16_t)0xFFF8;"
guarded = "r[10] = (r[4] == 0u) ? 0x801FBFF8u : (r[4] + (int32_t)(int16_t)0xFFF8); /* R903 widened terminator guard */"
n = s.count(bad)
if n > 0:
    s = s.replace(bad, guarded)
    open('disc1.c','w').write(s)
    print('[emit] R903 widened terminator guard APPLIED to %d remaining advance sites' % n)
elif 'R903 widened terminator guard' in s:
    print('[emit] R903 widened guard already present')
else:
    print('[emit] R903: all advance sites already guarded by R902 - nothing to do')
XEOF

# R904: idempotent post-emit patch: exact-fit allocator next==0 guard (fn_80031DA8).
# R902/R903 killed the -8 advance class (walk now reaches the DA8 terminator
# handler - proven cycle 2 of bridge-v8: backtrace ends 80031DA8, r10=0).
# ONE LAYER DEEPER (decode disc1.c:81039): DA8 exact-fit body computes
# new header pos = LW(r12) - want - 8. r12 = the selected block (0x800B06FC,
# bank-region node) whose next is ZERO (unlinked - the table-collision
# family) -> pos = 0 - 0x19CC = 0xFFFFE634 -> header SWs land off the end
# of RAM -> deterministic kit fault. Hardware never sees an unlinked
# next here (heap init links all blocks). GUARD per the machine's own
# convention (armed terminator w0 = rectguard cap = heap-top): when the
# selected node's next is 0, use the heap-top 0x801FC000.
python3 - <<'XEOF'
s = open('disc1.c').read()
bad = "L_80031E00:;\nr[3] = LW(r[12] + (int32_t)(int16_t)0x0000);"
fix = "L_80031E00:;\n/* R904 exact-fit next==0 guard: unlinked node's next means heap-top 0x801FC000 (rectguard cap / armed terminator w0 convention) */\nr[3] = LW(r[12] + (int32_t)(int16_t)0x0000); if (r[3] == 0u) r[3] = 0x801FC000u;"
if 'R904 exact-fit next==0 guard' in s:
    print('[emit] R904 exact-fit guard already present')
elif bad in s:
    s = s.replace(bad, fix, 1)
    open('disc1.c','w').write(s)
    print('[emit] R904 exact-fit next==0 guard APPLIED')
else:
    print('[emit] R904 ANCHOR MISSING (emitter output changed) - check manually')
XEOF

# R1202: idempotent post-emit patch: null-block early return in
# fn_80039144 (SoundHeapFree). c500 spinpc receipts (host backtrace
# captured INSIDE the wedge, symbolized vs the same-run binary):
#   park_tick -> xenolift_kick -> fn_8003BB6C (notifier) ->
#   fn_80038B54 (teardown body) -> SoundHeapFree -> read32
# The 80s wedge: teardown #2 re-enters after teardown #1 already freed
# the heap block and zeroed the hblock cell (0x800595A4), so
# SoundHeapFree(0) walks from the NULL block and dereferences its
# header at [0+0xC] billions of times (frozen gate counter, frozen
# cur_fn, alarm drain deferred forever - recursive pump starvation
# receipts). free-of-NULL is a no-op: guard the body, receipt it, return.
python3 - <<'XEOF'
s = open('disc1.c').read()
anchor_text = "XTRACE(0x80039144);\nL_80039144:;"
guard = "XTRACE(0x80039144);\nL_80039144:;\nif (r[4] == 0u) { static int r1202_n; if (r1202_n < 4u) { r1202_n++; xenolift_receipt(\"[sndfree] R1202 null-block free guarded (#%d): SoundHeapFree(0) skipped - free-of-NULL no-op (c500 spinpc)\\n\", r1202_n); } return; } /* R1202 null-block free guard */"
if 'R1202 null-block free guard' in s:
    print('[emit] R1202 null-block free guard already present')
elif anchor_text in s:
    s = s.replace(anchor_text, guard, 1)
    open('disc1.c','w').write(s)
    print('[emit] R1202 null-block free guard APPLIED')
else:
    print('[emit] R1202 ANCHOR MISSING (emitter output changed) - check manually')
XEOF


# R321/R322/R323 SM-CHURN post-emit patch: the CD state-machine family
# (0x8002A600-0x8002B400) churns ~5M hops/sec and never returns - unbounded
# host C recursion. R321/R322 tried a dispatcher-level trampoline in disc1.c;
# cycle-71 proved it is BYPASSED (states also hop via DIRECT emitted calls).
# R323 moves the whole mechanism into runtime.c (xenolift_trace = universal
# XTRACE entry hook + a never-dying anchor at the guest thread base), so the
# disc1.c trampoline is REMOVED: restore pristine xenolift_dispatch.
python3 - <<'XEOF'
s = open('disc1.c').read()
anchor = 'void xenolift_dispatch(uint32_t pc)' + chr(10) + '{' + chr(10)
if 'R322 SM-TRAMPOLINE' in s or 'R321 SM-TRAMPOLINE' in s:
    i = s.find('SM-TRAMPOLINE')
    start = s.rfind('#include', 0, i)
    start = s.rfind(chr(10), 0, start) + 1
    end = s.find('    if (pc == 0xA0u || pc == 0xB0u || pc == 0xC0u) {', i)
    assert end > start, 'R323: trampoline span not found'
    s = s[:start] + anchor + s[end:]
    open('disc1.c','w').write(s)
    print('[emit] R323 PRISTINE DISPATCH RESTORED (R321/R322 trampoline removed)')
elif anchor in s:
    print('[emit] R323 dispatch already pristine')
else:
    print('[emit] R323 ANCHOR MISSING (dispatch fn not found) - check manually')
XEOF

# R1394 (c504): re-apply the dispatch-guard splice post-emit (idempotent; the disc1.c dispatcher guard)
python3 r1394_postemit_guard.py

# splices hit the forward DECLARATION (gate landed in the wrong function).
# c328: remove-then-reapply churned disc1.c every cycle = full 74s recompile
# = starved digest vs the 240s watchdog. R752: if the gate is present and
# healthy, touch NOTHING (compile cache stays valid); else remove stale text
# and apply at the DEFINITION (next non-space char after signature is '{'),
# with self-verification.
python3 - <<'XEOF'
s = open('disc1.c').read()
# R766 CACHE-MASKED REGRESSION FIX (c345): the fresh emit (EMIT_REFRESH) proved
# the R758 bypass patch depends on fprintf/stderr, but a freshly emitted
# disc1.c never declares stdio - the OLD cached disc1.c had it from an earlier
# patch era and masked the dependency for ~20 cycles. Post-emit patches MUST
# be self-contained: ensure stdio is included BEFORE any patch lands.
if '#include <stdio.h>' not in s:
    s = '#include <stdio.h>\n' + s
    print('[emit] R766 stdio include ensured (fresh emit had no stdio; post-emit patches are self-contained)')
# R1153 (b8-c337): xenolift_receipt declared in xenolift_runtime.h now, but
# a FRESH emit may not include the header at all - ensure it does (the
# R1108/R1052 patch family calls xenolift_receipt; c337 FATAL was the
# undeclared call at disc1.c:24469 on the first fresh emit in ~20 cycles).
if '#include "xenolift_runtime.h"' not in s:
    s = '#include "xenolift_runtime.h"\n' + s
    print('[emit] R1153 runtime header include ensured (fresh emit had no runtime.h; patch calls need it)')
# R1154 (b8-c338): FRESH-EMIT STRING-LITERAL REPAIR. c337 fresh emit applied
# the R1115 chaincam patch carrying a RAW newline inside the C string literal
# (python \n landed unescaped in the file) -> disc1.c:131903 "expected
# expression" FATAL, zero runs, and the emit gate keeps the broken file every
# cycle until repaired in place. The cached emit masked this for ~20 cycles
# (R766 class). Idempotent: if the raw-newline form exists, replace with the
# valid single-line form (C-escaped \n); source fixed above so fresh emits
# are clean too.
if 'r16=%08X\n", n, r[29], r[31], r[16]); } }' in s:
    s = s.replace('r16=%08X\n", n, r[29], r[31], r[16]); } }',
                  'r16=%08X\\n", n, r[29], r[31], r[16]); } }')
    print('[emit] R1154 R1115 string-literal repaired (raw newline -> C-escaped; c338 FATAL class closed)')
# R1155 (b8-c339): SECOND FORM of the same class - c339 receipts: the fresh
# emit applied the R1115 patch from a template whose fix swallowed the CLOSING
# QUOTE (file shows %08X\n, n - backslash-n then comma, string never
# terminated -> expected-expression at the same line). Fix both directions:
# this form (missing quote) and the raw-newline form above stay repairable
# in place; the source template is fixed this cycle and verified by local
# compile of the applied patch.
if 'r16=%08X\\n, n, r[29], r[31], r[16]); } }' in s:
    s = s.replace('r16=%08X\\n, n, r[29], r[31], r[16]); } }',
                  'r16=%08X\\n", n, r[29], r[31], r[16]); } }')
    print('[emit] R1155 R1115 closing-quote repaired (backslash-n form; c339 FATAL class closed)')
if 'R758 GATED field-cb bypass' in s:
    print('[emit] R752 no-churn: R758 gated bypass present and healthy - disc1.c untouched (compile cache stays valid)')
    if s != open('disc1.c').read():
        open('disc1.c', 'w').write(s)  # R766: stdio-ensure change persists even on the no-churn path
else:
    # R758: marker-based removal of the old R750 gate AND the UNBALANCED
    # R757 block (c336: R757 shipped missing its final '}' - brace-scan
    # removal of both restores balance; lesson: splice fragments are
    # brace-balanced programmatically before shipping).
    ist = s.find('{ /* R757 GATED field-cb completion bypass')
    if ist >= 0:
        iret = s.find('return;', ist)
        ib1 = s.find('}', iret)
        ib2 = s.find('}', ib1 + 1)
        ib3 = s.find('}', ib2 + 1)
        # bad R757 is net +1 (shipped missing its final '}') - the cut must
        # return the stolen close to the function: three '}' after 'return;'.
        if iret > 0 and ib3 > ib2 > ib1:
            s = s[:ist] + s[ib3 + 1:]
            open('disc1.c','w').write(s)
            print('[emit] R758 removed UNBALANCED R757 block (marker + 3-brace scan, balance returned)')
            s = open('disc1.c').read()
        else:
            print('[emit] R758 WARNING: R757 marker found but braces unresolved - NOT removed')
    ist = s.find('{ /* R750 GATED field-cb completion bypass')
    if ist >= 0:
        iret = s.find('return;', ist)
        ib1 = s.find('}', iret)
        ib2 = s.find('}', ib1 + 1)
        if iret > 0 and ib2 > ib1:
            s = s[:ist] + s[ib2 + 1:]
            open('disc1.c','w').write(s)
            print('[emit] R757 removed stale R750 gate block (marker + brace-scan)')
            s = open('disc1.c').read()
        else:
            print('[emit] R757 WARNING: R750 marker found but braces unresolved - NOT removed')
    for pf in ('patches/r749_ins.c',):
        try:
            old = open(pf).read()
            if old in s:
                s = s.replace(old, '', 1)
                open('disc1.c','w').write(s)
                print('[emit] R750 removed stale block from ' + pf + ' (exact text)')
                s = open('disc1.c').read()
        except FileNotFoundError:
            pass
    for marker in ('R748 field cb completion bypass', 'R747 field cb completion bypass'):
        istart = s.find('{ /* ' + marker)
        if istart >= 0:
            iend = s.find('return; }', istart)
            if iend >= 0:
                s = s[:istart] + s[iend + len('return; }'):]
                open('disc1.c','w').write(s)
                print('[emit] R750 removed legacy ' + marker + ' block')
                s = open('disc1.c').read()
    anchor = 'static void xenolift_fn_80077E88(void)'
    defn = -1
    i = -1
    while True:
        i = s.find(anchor, i + 1)
        if i < 0:
            break
        j = i + len(anchor)
        while j < len(s) and s[j] in ' \t\n\r':
            j += 1
        if j < len(s) and s[j] == '{':
            defn = i
            break
    # R1021a: the hard assert (c137 traceback) fired when a STALE disc1.c
    # was re-shipped inside the zip and re-unzipped over the Mac's patched
    # copy - the R758 marker vanished and the definition anchor (old-era
    # emitter naming) didn't exist. The package no longer ships disc1.c, but
    # the patcher degrades honestly anyway: no definition -> warn + skip
    # (the fresh emit next cycle re-anchors it), never a bare traceback.
    if defn < 0:
        print('[emit] R758 SKIP: fn_80077E88 definition not found in this disc1.c (stale/artifact copy?) - gate NOT applied; fresh emit re-anchors')
    else:
        brace = s.find('{', defn)
        ins = open('patches/r750_ins.c').read()
        s = s[:brace+1] + ins + s[brace+1:]
        open('disc1.c','w').write(s)
        chk = open('disc1.c').read()
        k = chk.find('R758 GATED field-cb bypass')
        assert chk.find('xenolift_fn_80077E88(void)', max(0,k-400), k) > 0, 'R758 VERIFY: gate not adjacent to definition'
        print('[emit] R758 GATED BYPASS APPLIED at fn_80077E88 DEFINITION (definition-anchored, verified adjacent - REAL-ENTRY era #9+)')
XEOF

grep "overlay" emit.log
grep "reference ingest\|symbol map" emit.log | head -3
grep "symbol map file\|seams:" emit.log | head -3
tail -3 emit.log
stage "emit"
# R924 (b8-c29, manager - PLACEMENT FIX): c29 proved the R923 patcher sat inside
# the emit stage - the cached-emit path SKIPS it, so the guard never applied
# ("emit: SKIPPED" -> no R923 receipt). Moved here: runs EVERY cycle against
# the cached disc1.c, idempotent; when it patches, the -nt compile cache
# invalidates disc1.c only (one recompile), then the cache stays warm.
# R923 (b8-c28/29, manager - THE TRANSLATED-BUILD BYPASS, Jos directive
# "pivot like a detour on the map"): the heap walk fn_80031C58 reads its
# cursor $t2 (r[10]) WITHOUT setting it - it inherits from the caller, and
# the kernel's dispatcher (0x8001979C) calls it repeatedly with a null arg
# ([adv] fn_80031C58 a0=0x00000000 loop in every digest). When the cursor
# is null/wild the first LW(r[10]+4) is the fault that restarts the console
# forever. We OWN this translated function now (phase-3 native overlays):
# guard the head - invalid cursor = clean return = walk ends, kernel sees
# an empty result and proceeds instead of fault-looping.
python3 - <<'XEOF'
s = open('disc1.c').read()
patch = "XTRACE(0x80031C58);\nL_80031C58:;\n/* R923 cursor-validity guard (translated-build bypass): t2 cursor is inherited from the caller; the dispatcher passes a0=0 ([adv] loop) and a null/wild cursor faults the walk forever. Invalid cursor = clean return. */\nif (r[10] < 0x80010000u || r[10] >= 0x80200000u) { return; }\nr[2] = LW(r[10] + (int32_t)(int16_t)0x0004);"
plain = "XTRACE(0x80031C58);\nL_80031C58:;\nr[2] = LW(r[10] + (int32_t)(int16_t)0x0004);"
if 'R923 cursor-validity guard' in s:
    print('[emit] R923 walk cursor guard already present')
elif plain in s:
    s = s.replace(plain, patch, 1)
    open('disc1.c','w').write(s)
    print('[emit] R923 walk cursor guard APPLIED at fn_80031C58 head (a0=0 call loop ends clean)')
else:
    print('[emit] R923 ANCHOR MISSING (emitter output changed) - check manually')
XEOF

# R925 (b8-c31, manager/ATLAS - LZSS RUNAWAY TERMINATED AT SOURCE, the
# translated-build bypass): the decompressor's own decomp name says it
# "accepts neither a compressed input extent nor a destination capacity" -
# on real hardware streams are well-formed; ours aren't yet, so the input
# cursor wraps to 0xFFFFFFFC and spins 200K+ ops per cycle burning the run
# budget (c31 EXITTAIL). We OWN this function in disc1.c: add the missing
# bounds check - an op-count abort at the group head. Legit members are
# <=64KB expanded = <=8K groups; 3M-group cap = 500x headroom. Clean
# return, no host frame, no runaway treadmill.
python3 - <<'XEOF'
s = open('disc1.c').read()
head_plain = "XTRACE(0x80032EB4);\nL_80032EB4:;\n"
head_fix = ("XTRACE(0x80032EB4);\nL_80032EB4:;\n"
"/* R925 op-count abort (translated-build bypass): original code has no input-extent or dst-capacity check (by design, per its decomp name); garbage input wraps the cursor to 0xFFFFFFFC and spins 200K+ ops. Legit members never touch 0x80200000+; R926 overrun-signature abort (4096). */\n"
"g_lzss_overrun_reads = 0; /* R926: per-call reset of the overrun signature counter */\n"
)
grp_plain = "L_80032EC4:;\nr[24] = LBU(r[4] + (int32_t)(int16_t)0x0000);\n"
grp_fix = ("L_80032EC4:;\nr[24] = LBU(r[4] + (int32_t)(int16_t)0x0000);\n"
"if (g_lzss_overrun_reads > 4096u) { g_lzss_abort_fired++; return; } /* R925/R926/R927 runaway abort: overrun-read signature + telemetry counter */\n")
if 'g_lzss_overrun_reads > 4096u' in s:
    print('[emit] R925 lzss op-count abort already present (R1011: marker now keyed to the guard CODE text - R1010 checked a string that never matched the emitted comment form R925/R926/R927, my own marker-mismatch repeat of the original bug; the guard code substring g_lzss_overrun_reads > 4096u is form-independent)')
elif head_plain in s and grp_plain in s:
    s = s.replace(head_plain, head_fix, 1)
    s = s.replace(grp_plain, grp_fix, 1)
    open('disc1.c','w').write(s)
    print('[emit] R925 lzss op-count abort APPLIED at UnpackCompressedBuffer (head reset + group cap 3M)')
else:
    print('[emit] R925 ANCHOR MISSING (emitter output changed) - check manually')
XEOF

# R926 (b8-c32, manager - RUNAWAY ABORT MADE SIGNATURE-BASED): c32 proved
# the R925 3M-group cap never fires inside a 51s budget (the treadmill is
# ~200K ops total). New mechanism: runtime.c counts OVERRUN reads (>=
# 0x80200000, the exact runaway signature) in g_lzss_overrun_reads (extern
# via xenolift_runtime.h); the translated loop aborts when it sees >4096
# since entry (per-call reset) - garbage streams die in milliseconds, zero
# false-positive risk (legit streams never touch 0x80200000+). This block
# converts the cached disc1.c from the R925 op-count form; fresh emits emit
# the new form directly (R925 block updated in place).
python3 - <<'XEOF'
s = open('disc1.c').read()
old_head = "static uint32_t r925_ops = 0;\nr925_ops = 0;"
new_head = "g_lzss_overrun_reads = 0; /* R926: per-call reset of the overrun signature counter */"
old_loop = "if (++r925_ops > 3000000u) { return; } /* R925 runaway abort */"
new_loop = "if (g_lzss_overrun_reads > 4096u) { g_lzss_abort_fired++; return; } /* R925/R926/R927 runaway abort: overrun-read signature + telemetry counter */"
if 'g_lzss_overrun_reads > 4096u' in s:
    print('[emit] R926 signature-based abort already present (R1011 code-keyed marker)')
elif old_head in s and old_loop in s:
    s = s.replace(old_head, new_head, 1)
    s = s.replace(old_loop, new_loop, 1)
    open('disc1.c','w').write(s)
    print('[emit] R926 CONVERTED cached R925 abort -> overrun-signature abort (shared counter, 4096 cap)')
else:
    print('[emit] R926 ANCHOR MISSING (emitter output changed) - check manually')
XEOF

# R927 (b8-c33, manager - RUNAWAY OWNER CAMERA + ABORT TELEMETRY): the
# R926 signature abort applied and compiled but the c33 treadmill ran the
# IDENTICAL op sequence to c32 - the guard never fired, so the runaway
# loop does not pass the guarded group head (leading theory: the spin is
# NOT in translated fn_80032EB4 but in bios-gate interpreter land).
# STOP THEORIZING - INSTRUMENT: (1) every [lzss-runaway] receipt now
# names cur_fn (the guest function owning the spin, via xenolift_trace)
# and the abort count; (2) the translated abort increments
# g_lzss_abort_fired so the receipt PROVES whether the guard fires.
python3 - <<'XEOF'
s = open('disc1.c').read()
old_loop = "if (g_lzss_overrun_reads > 4096u) { return; } /* R925/R926 runaway abort: fires on the runtime overrun-read signature, not a blind op count */"
new_loop = "if (g_lzss_overrun_reads > 4096u) { g_lzss_abort_fired++; return; } /* R925/R926/R927 runaway abort: overrun-read signature + telemetry counter */"
if 'R925/R926/R927 runaway abort' in s:
    print('[emit] R927 telemetry already present')
elif old_loop in s:
    s = s.replace(old_loop, new_loop, 1)
    open('disc1.c','w').write(s)
    print('[emit] R927 abort TELEMETRY added to converted guard (abort count now provable)')
else:
    print('[emit] R927 ANCHOR MISSING (emitter output changed) - check manually')
XEOF

# R928 (b8-c34, manager/TRAILBLAZER lane - HEAP-CONSOLIDATE RUNAWAY: THE
# SOURCE-TRUE FIX): the R927 camera NAMED the treadmill owner: cur_fn=
# 80031FF8 (HeapConsolidate), aborts=0 - the spin was NEVER the LZSS
# decompressor; lzss_armed was stale from an earlier decompress. Decoded
# vs decomp memory.c: the walk hops pCurrent = pNext - 8 and exits ONLY
# on userTag==HEAP_USER_END (flags 0x00200000); pNext=0 -> flags read at
# 0-4 = 0xFFFFFFFC = the exact runaway frontier. FIX = the contract's own
# exit: any pNext outside the heap band (0x801F0000..0x80200000) jumps to
# the REAL end-exit label (clears g_HeapNeedsConsolidation + returns,
# exactly like finding the END sentinel - no half-baked plain return).
# Three hops guarded: inner merge read (32040), inner hop (3205C), outer
# hop (32084).
python3 - <<'XEOF'
s = open('disc1.c').read()
GB = "if (r[3] < 0x801F0000u || r[3] >= 0x80200000u) { goto %s; } /* R928: pNext out of heap band - take the real END exit per decomp memory.c */\n"
a1 = "L_8003203C:;\n/* nop */\nL_80032040:;\nr[2] = LW(r[3] + (int32_t)(int16_t)0xFFFC);"
f1 = "L_8003203C:;\n" + (GB % "L_8003207C") + "/* nop */\nL_80032040:;\nr[2] = LW(r[3] + (int32_t)(int16_t)0xFFFC);"
a2 = "L_80032080:;\n/* nop */\nL_80032084:;\nr[2] = LW(r[3] + (int32_t)(int16_t)0xFFFC);"
f2 = "L_80032080:;\n" + (GB % "L_80032098") + "/* nop */\nL_80032084:;\nr[2] = LW(r[3] + (int32_t)(int16_t)0xFFFC);"
a3 = "L_80032058:;\nr[4] = r[4] & r[6];\nL_8003205C:;\nr[3] = LW(r[3] + (int32_t)(int16_t)0xFFF8);"
f3 = "L_80032058:;\nr[4] = r[4] & r[6];\n" + (GB % "L_8003207C") + "L_8003205C:;\nr[3] = LW(r[3] + (int32_t)(int16_t)0xFFF8);"
if 'R928: pNext out of heap band' in s:
    print('[emit] R928 heap-band guards already present')
elif a1 in s and a2 in s and a3 in s:
    s = s.replace(a1, f1, 1)
    s = s.replace(a2, f2, 1)
    s = s.replace(a3, f3, 1)
    open('disc1.c','w').write(s)
    print('[emit] R928 HeapConsolidate band guards APPLIED (3 hops -> real END exit)')
else:
    print('[emit] R928 ANCHOR MISSING (emitter output changed) - check manually')
XEOF

# R929 (b8-c35, manager - VSYNC RECURSION CAP, the c35 stack-exhaustion
# killer): the c35 crash trail = translated recursion Vsync(8004B54C) <->
# CheckCallback(8004B894) (decomp: Vsync/CheckCallback, PsyQ libcd;
# c467's 80041C68<->8004B894 is this same class evolved) - each guest
# iteration = one HOST C stack frame until exhaustion; the kit's SIGSEGV
# recovery re-dispatched and the second pass died via __stack_chk_fail in
# vfprintf on the dead stack (exit 134). Every loop pass goes through
# Vsync (trail alternates 80041BA8/8004B54C), so cap NESTING there: >16
# live Vsync frames = recursion; the cap returns the CONTRACT value
# (r2 = live vblank counter @0x80057844, per decomp set_alarm's
# Vsync(-1)+0x3C0 usage) so the unwinding sees a sane count. Fires are
# counted in g_vsync_cap_fires (header extern, printed at exitdiag).
python3 - <<'XEOF'
s = open('disc1.c').read()
head = "XTRACE(0x8004B54C);\nL_8004B54C:;"
head_fix = "XTRACE(0x8004B54C);\nstatic uint32_t r929_nest = 0;\nif (++r929_nest > 16u) { r929_nest--; g_vsync_cap_fires++; r[2] = LW(0x80057844u); return; } /* R929: Vsync<->CheckCallback recursion cap (c35 host stack exhaustion); contract return = live vblank counter per set_alarm's Vsync(-1) usage */\nL_8004B54C:;"
tail = "xenolift_fn_8004B55C(); /* fallthrough */\nreturn;"
tail_fix = "xenolift_fn_8004B55C(); /* fallthrough */\nr929_nest--; /* R929 */\nreturn;"
if 'R929: Vsync<->CheckCallback recursion cap' in s:
    print('[emit] R929 Vsync recursion cap already present')
elif head in s and s.count(tail) == 1:
    s = s.replace(head, head_fix, 1)
    s = s.replace(tail, tail_fix, 1)
    open('disc1.c','w').write(s)
    print('[emit] R929 Vsync recursion cap APPLIED (nest cap 16, contract return, telemetry)')
else:
    print('[emit] R929 ANCHOR MISSING (emitter output changed) - check manually')
XEOF

# R933 (b8-c39, seam guard - CD CALLBACK SLOT GAR->NULL HEAL): the libcd
# event pump calls guest fn pointers from slots 0x800564AC (ready-cb) and
# 0x800564A8 (data-cb) at 10 emitted read sites (all base r2=0x80050000).
# c39: garbage in the slot -> wild host-side target 0x0C789675 -> SIGSEGV
# -> 11 recoveries -> torn-stack abort 134. Heal garbage to the libcd
# pre-registration value (NULL = pump skips the call) via the runtime
# helper xenolift_cdcb_slot(); real registrations pass through untouched.
python3 - <<'XEOF'
s = open('disc1.c').read()
n1 = s.count('LW(r[2] + (int32_t)(int16_t)0x64AC)')
n2 = s.count('LW(r[2] + (int32_t)(int16_t)0x64A8)')
if 'xenolift_cdcb_slot(0x800564ACu)' in s:
    print('[emit] R933 CD callback slot heal already present')
elif n1 == 5 and n2 == 5:
    s = s.replace('LW(r[2] + (int32_t)(int16_t)0x64AC)', 'xenolift_cdcb_slot(0x800564ACu)')
    s = s.replace('LW(r[2] + (int32_t)(int16_t)0x64A8)', 'xenolift_cdcb_slot(0x800564A8u)')
    open('disc1.c','w').write(s)
    print('[emit] R933 CD callback slot heal APPLIED (10 sites -> xenolift_cdcb_slot, garbage->NULL contract)')
else:
    print('[emit] R933 ANCHOR COUNT CHANGED (64AC=%d 64A8=%d, expected 5+5) - check emitter' % (n1, n2))
XEOF

# R935 (b8-c41, fixes R934's patcher escape bug: the anchor's backslash-n
# became a REAL newline inside the run.sh text -> Python SyntaxError on the
# Mac -> the heal never applied; c41 ran identical to c40. Same seam fix,
# now with the anchor built with chr(10) so no escaping can ever break it.)
python3 - <<'XEOF'
s = open('disc1.c').read()
NL = chr(10)
anchor = NL.join(['L_80031C4C:;', 'r[4] = LW(r[28] + (int32_t)(int16_t)0x01B0);'])
healed = NL.join([
    'L_80031C4C:;',
    'r[4] = LW(r[28] + (int32_t)(int16_t)0x01B0);',
    'if (r[4] == 0u) { r[4] = xenolift_freelist_head_heal(r[28]); } /* R935: NULL band head -> 801FBFF8 END sentinel, walk terminates per HeapInit */',
])
if 'xenolift_freelist_head_heal(r[28])' in s:
    print('[emit] R935 freelist head heal already present')
elif s.count(anchor) == 1:
    s = s.replace(anchor, healed, 1)
    open('disc1.c','w').write(s)
    print('[emit] R935 freelist head heal APPLIED at L_80031C4C (NULL -> 801FBFF8 END sentinel; R934 patcher syntax bug fixed)')
else:
    print('[emit] R935 ANCHOR MISSING (L_80031C4C door changed) - count=%d' % s.count(anchor))
XEOF
# R936 (b8-c42, camera - DRAWPRIM CONTEXT): the kernel now calls DrawPrim
# (pixels door!). Crash = dispatch through GPU env method slot [env+0x3C].
# Camera call inserted at the DrawPrim body (unique L_80044B78 sequence);
# env slot values + prim head printed for the source contract next cycle.
python3 - <<'XEOF'
s = open('disc1.c').read()
NL = chr(10)
anchor = NL.join(['L_80044B78:;', 'r[16] = r[4] + r[0];'])
cam = NL.join([
    'L_80044B78:;',
    'xenolift_drawprim_cam(r[4]); /* R936: env slot + prim head context (pixels door camera) */',
    'r[16] = r[4] + r[0];',
])
if 'xenolift_drawprim_cam(r[4])' in s:
    print('[emit] R936 DrawPrim camera already present')
elif s.count(anchor) == 1:
    s = s.replace(anchor, cam, 1)
    open('disc1.c','w').write(s)
    print('[emit] R936 DrawPrim camera APPLIED at L_80044B78 (env+prim context, cap 4)')
else:
    print('[emit] R936 ANCHOR MISSING (L_80044B78) - count=%d' % s.count(anchor))
XEOF

# R1051 (b8-c207) BODY CAMERAS at translated fn entries. The camlive
# receipt closed the placement era: dispatch-hook regions executed 262144+
# times with target_matches=0 - translated-to-translated calls never route
# through runtime dispatch. These guards inject the bodycam call at the
# entry labels of the linker (ResolveArchiveEntryPointers 0x8003342C), its
# caller (0x800320A4), and the module fns (0x801D002C, 0x801D2FE8 - labels
# may be absent in older emits; the guard reports per-fn status, never
# fails the build). Cap 24 receipts inside runtime helper.
python3 - <<'XEOF'
import io
s = io.open('disc1.c', encoding='utf-8', errors='surrogateescape').read()
changed = False
for fnid in ('8003342C', '800320A4', '801D002C', '801D2FE8'):
    call = 'xenolift_bodycam(0x%su, r[4], r[5], r[6], r[7]); /* R1051 */' % fnid
    lab = 'L_%s:;' % fnid
    if call in s:
        print('[emit] R1051 bodycam %s already present' % fnid)
    elif s.count(lab) >= 1:
        s = s.replace(lab, lab + '\n' + call, 1)
        changed = True
        print('[emit] R1051 bodycam %s APPLIED at entry label' % fnid)
    else:
        print('[emit] R1051 bodycam %s ANCHOR MISSING (label count=0 - fn not in this emit)' % fnid)
if changed:
    io.open('disc1.c', 'w', encoding='utf-8', errors='surrogateescape').write(s)
# R1052 (b8-c209): extend bodycam to GUARANTEED-ENTRY fns - the coordinator
# 0x80077E88 (R758 REAL-ENTRY receipt fires every run) and module helper
# 0x80076858 (modhelp receipts in past cycles). c209 receipt: bodycam silent
# with guards present because THIS run never entered the module fns (crash
# classes wandered to the walk ping-pong + 0x80042A58). These two cameras
# prove the emit-side mechanism end-to-end on every run, independent of
# crash-site variance. NOTE: disc1.c change => one full recompile (~143s),
# budget guard may defer the run once - accepted cost.
changed2 = False
# R1057 (b8-c218): bodycam at the archive list-walk death site. c218 TRUE
# DEATH (R834/R964: all recoveries declined, sig=4) at cur_fn=0x80028AC8
# r31=0x800297A8 - the halfword list-copy loop that loads its list pointer
# from [0x8005FE30] (code @80028AAC: lw v0,0xFE30(v0) chain) and walks with
# r4=0x22732 (OUT-OF-RAM), r5=0x20736477 (module magic in an arg reg).
# Receipts needed: entry a0-a3 + the [0x8005FE30] list cell + the walk state.
for fnid in ('80028AC8',):
    marker = '/* R1057 */'
    call = ('if (r[6] == 0u) { xenolift_receipt("[archlistcam] R1057 FN %s 5FE30=%%08X FE48=%%08X FE4C=%%08X FDF8=%%08X\\n", xenolift_mem_read32(0x8005FE30u), xenolift_mem_read32(0x8005FE48u), xenolift_mem_read32(0x8005FE4Cu), xenolift_mem_read32(0x8005FDF8u)); } xenolift_bodycam(0x%su, r[4], r[5], r[6], r[7]); %s'
            % (fnid, fnid, marker))
    lab = 'L_%s:;' % fnid
    if call in s:
        print('[emit] R1057 archlistcam %s already present' % fnid)
    elif s.count(lab) >= 1:
        s = s.replace(lab, lab + '\n    ' + call, 1)
        print('[emit] R1057 archlistcam %s APPLIED at entry label' % fnid)
    else:
        print('[emit] R1057 archlistcam %s ANCHOR MISSING' % fnid)
# R1105 (b8-c283): KERNEL-MENU EXIT PUNCH - THE AREA-1 PIVOT.
# Source decode (decomp, all named): state 0 = KernelMenuMain (0x8001A4B4)
# = the "XENOGEARS Kernel MENU" (kernel_menu.c): Field/Battle/Worldmap/
# Battling/Menu/Movie, cursor 0=Field. Statetbl R1104 receipts: g_CurGameState
# (0x80018088)=0 at EVERY bootentry pass - the state machine NEVER advances
# because the exit contract is g_C1ButtonStateReleased (0x8005948C) &
# CTRL_BTN_CIRCLE (0x20, controller.h:44) -> ChangeGameState(choice+1)
# (kernel_menu.c:57) -> IsRunning=FALSE -> MainLoop(0) -> STATE-TABLE dispatch
# of FieldMain with MainLoop's full init chain. Three days of fault-churn
# (Vsync 0x8004B54C / CD_sync 0x80041B3C / CheckCallback 0x8004B894 trails)
# = the kernel menu's own render loop. THIS patch injects the CIRCLE-release
# at KernelMenuUpdate (0x8001A344) ENTRY on its 3rd call - the function reads
# the cell immediately after (same frame; controller INTs are HLE'd at Vsync/
# loop points, c224 audit), so the game's OWN transition code executes.
# Pure contract injection; source refs: kernel_menu.c:57, controller.h:44.
# R1106 (b8-c284): KERNEL-MENU CHAIN CAMERAS + FIRST-ENTRY PUNCH.
# c284 receipts: R1105 APPLIED at the label and persisted into the binary
# (write gate: R1057 changed2 carry; content-stable cc cache explains 4s
# compile) - yet menupunch SILENT = KernelMenuUpdate entered <3 times all
# run (menu loop barely executes; crash hits earlier). This cycle: (1) punch
# moved to FIRST update entry; (2) entry-count cameras at KernelMenuMain
# (0x8001A4B4) and KernelMenuInitialize (0x8001A250) receipt how deep the
# chain gets per recovery: Main>Init>Update entry counts + loop cells
# IsRunning(0x800592D0)/D_800592C8(0x800592C8)/g_CurGameState(0x80018088).
# Chain decode (kernel_menu.c:81-107): Main: Initialize(); IsRunning=1;
# D_800592C8=0; while(IsRunning||!D_800592C8){...TermPrim; FontDrawLetters;
# KernelMenuUpdate(); AddPrim; DrawSync; Vsync;...} - Update reads
# g_C1ButtonStateReleased(0x8005948C)&CIRCLE(0x20) -> ChangeGameState(choice+1).
for fnid in ('8001A4B4',):
    marker = '/* R1106m */'
    call = ('{ static unsigned n; if (n < 6u) { n++; xenolift_receipt("[menuchain] R1106 KernelMenuMain entry #%%u IsRunning(92D0)=%%08X ctx92C8=%%08X state(18088)=%%08X\\n", n, xenolift_mem_read32(0x800592D0u), xenolift_mem_read32(0x800592C8u), xenolift_mem_read32(0x80018088u)); } } %s'
            % (marker,))
    lab = 'L_%s:;' % fnid
    if call in s:
        print('[emit] R1106 menuchain %s already present' % fnid)
    elif s.count(lab) >= 1:
        s = s.replace(lab, lab + '\n    ' + call, 1)
        changed = True
        print('[emit] R1106 menuchain %s APPLIED at KernelMenuMain entry' % fnid)
    else:
        print('[emit] R1106 menuchain %s ANCHOR MISSING' % fnid)
for fnid in ('8001A250',):
    marker = '/* R1106i */'
    call = ('{ static unsigned n; if (n < 4u) { n++; xenolift_receipt("[menuchain] R1106 KernelMenuInitialize entry #%%u\\n", n); } } %s'
            % (marker,))
    lab = 'L_%s:;' % fnid
    if call in s:
        print('[emit] R1106 menuchain %s already present' % fnid)
    elif s.count(lab) >= 1:
        s = s.replace(lab, lab + '\n    ' + call, 1)
        changed = True
        print('[emit] R1106 menuchain %s APPLIED at KernelMenuInitialize entry' % fnid)
    else:
        print('[emit] R1106 menuchain %s ANCHOR MISSING' % fnid)
for fnid in ('8001A344',):
    marker = '/* R1106 */'
    call = ('{ static unsigned n; n++; if (n < 4u) { xenolift_receipt("[menuchain] R1106 KernelMenuUpdate entry #%%u choice(4F2D8)=%%08X released(8005948C)=%%08X\\n", n, xenolift_mem_read32(0x8004F2D8u), xenolift_mem_read32(0x8005948Cu)); } if (n == 1u) { uint32_t v = xenolift_mem_read32(0x8005948Cu); uint32_t nv = (v & 0xFFFF0000u) | ((v | 0x20u) & 0xFFFFu); xenolift_mem_write32(0x8005948Cu, nv); xenolift_receipt("[menupunch] R1106 CIRCLE-release -> g_C1ButtonStateReleased: %%08X -> %%08X; kernel_menu.c:57 ChangeGameState(choice+1) via game code\\n", v, nv); } } %s'
            % (marker,))
    lab = 'L_%s:;' % fnid
    if call in s:
        print('[emit] R1106 menupunch %s already present' % fnid)
    elif s.count(lab) >= 1:
        s = s.replace(lab, lab + '\n    ' + call, 1)
        changed = True
        print('[emit] R1106 menupunch %s APPLIED at KernelMenuUpdate entry (punch at n==1)' % fnid)
    else:
        print('[emit] R1106 menupunch %s ANCHOR MISSING' % fnid)
# R1111 (b8-c289): VSYNC BOOKKEEPING STORE GUARDS. c289 archhook
# receipts FINALLY name the archive-base poison frame: [hook] 0x8004FDF0:
# 80010004 -> 80090000 at fn 0x8004B54C - Vsync's frame overwrites
# g_ArchiveTable with 0x80090000 (exactly the overlay window end:
# 0x8006F000+135168=0x80090000). The emitted Vsync body (disc1.c
# fn_8004B55C) has exactly two computed-base stores:
#   L_8004B668: SW(r[1] + (int16_t)0x7848, r[2])  -> g_VsyncPrevInterruptCount
#   L_8004B678: SW(r[1] + (int16_t)0x7844, r[3])  -> g_HsyncInterruptCount
# Retail $at(=r[1]) must be 0x80050000 at both (set at L_8004B664/B674);
# if the frame ever reaches the stores with r[1] clobbered, the store
# lands at [r1+0x7848] = 0x8004FDF0 when r1=0x80047DA8 - the receipted
# poison. GUARD = block the store when r[1] != 0x80050000, receipt the
# clobbered base (names the culprit path if this guard fires). If the
# poison instead persists SILENT past these guards, the writer is a
# callback dispatched inside Vsync's frame (cur_fn attribution) and the
# next cycle names it by elimination.
vs_old1 = "SW(r[1] + (int32_t)(int16_t)0x7848, r[2]);"
vs_new1 = ("{ if (r[1] == (0x8005u << 16)) { SW(r[1] + (int32_t)(int16_t)0x7848, r[2]); } "
           "else { static unsigned n; if (n < 8u) { n++; xenolift_receipt(\"[vsyncguard] R1111 stray bookkeeping store BLOCKED @57848: r1=%%08X (want 80050000) val=%%08X\\n\", r[1], r[2]); } } }")
vs_old2 = "SW(r[1] + (int32_t)(int16_t)0x7844, r[3]);"
vs_new2 = ("{ if (r[1] == (0x8005u << 16)) { SW(r[1] + (int32_t)(int16_t)0x7844, r[3]); } "
           "else { static unsigned n; if (n < 8u) { n++; xenolift_receipt(\"[vsyncguard] R1111 stray bookkeeping store BLOCKED @57844: r1=%%08X (want 80050000) val=%%08X\\n\", r[1], r[3]); } } }")
if vs_new1 in s:
    print('[emit] R1111 vsyncguard 57848 already present')
elif s.count(vs_old1) == 1:
    s = s.replace(vs_old1, vs_new1)
    changed = True
    print('[emit] R1111 vsyncguard 57848 APPLIED')
else:
    print('[emit] R1111 vsyncguard 57848 ANCHOR count=%d' % s.count(vs_old1))
if vs_new2 in s:
    print('[emit] R1111 vsyncguard 57844 already present')
elif s.count(vs_old2) == 1:
    s = s.replace(vs_old2, vs_new2)
    changed = True
    print('[emit] R1111 vsyncguard 57844 APPLIED')
else:
    print('[emit] R1111 vsyncguard 57844 ANCHOR count=%d' % s.count(vs_old2))
# R1108 (b8-c286): PRE-DISPATCH CHAIN CAMERAS. c286 receipts: R1106 all
# APPLIED (dry-run gate worked, no traceback) yet MENUCHAIN SILENT and exit=0
# - KernelMenuMain body NEVER entered. statestamp fires at func_80019548
# (7 passes) = MainLoop runs; source decode (main_loop.c MainLoop): after
# func_80019548 come HeapRelocate(pHeapStart+4) -> HeapReset ->
# ControllerResetState -> ChangeGameState(0) -> pGameState->pFnMain().
# pFnMain never runs = the crash is in ONE of those four calls. These
# cameras receipt each entry; the LAST one to fire names the wall.
# Addresses (symbol_addrs 12/163/165/237): ChangeGameState=0x8001996C,
# HeapReset=0x80031A30, HeapRelocate=0x80031B10, ControllerResetState=
# 0x80035DB0. ChangeGameState also dumps g_CurGameState(0x80018088)
# before the store - the anti-loop handshake (menu state 0 re-armed per
# pass, source-named).
for fnid in ('80031B10', '80031A30', '80035DB0'):
    marker = '/* R1108 %s */' % fnid
    call = ('{ static unsigned n; if (n < 4u) { n++; xenolift_receipt("[chaincam] R1108 %s entry #%%u @t=NA\\n", n); } } %s'
            % (fnid, marker))
    lab = 'L_%s:;' % fnid
    if call in s:
        print('[emit] R1108 chaincam %s already present' % fnid)
    elif s.count(lab) >= 1:
        s = s.replace(lab, lab + '\n    ' + call, 1)
        changed = True
        print('[emit] R1108 chaincam %s APPLIED at entry label' % fnid)
    else:
        print('[emit] R1108 chaincam %s ANCHOR MISSING' % fnid)
for fnid in ('8001996C',):
    marker = '/* R1108 %s */' % fnid
    call = ('{ static unsigned n; if (n < 6u) { n++; xenolift_receipt("[chaincam] R1108 ChangeGameState entry #%%u arg0(18088 pre-store)=%%08X cur=%%08X\\n", n, xenolift_mem_read32(0x80018088u), r[4]); } } %s'
            % (marker,))
    lab = 'L_%s:;' % fnid
    if call in s:
        print('[emit] R1108 chaincam %s already present' % fnid)
    elif s.count(lab) >= 1:
        s = s.replace(lab, lab + '\n    ' + call, 1)
        changed = True
        print('[emit] R1108 chaincam %s APPLIED at ChangeGameState entry' % fnid)
    else:
        print('[emit] R1108 chaincam %s ANCHOR MISSING' % fnid)
# R1115 (b8-c294): CD_DATASYNC ENTRY CAMERA + the poison decode. c294
# sw_line decode (Mac disc1.c 131910, enclosing fn @131889 =
# xenolift_fn_8004293C_CD_datasync): the poison store is CD_datasync's
# own callee-save SW(sp+0x18, r16) - for it to land on 0x8004FDF0,
# sp was 0x8004FDD8 (kernel-region stack) with r16=0x80090000. This is
# a STACK COLLISION, not a poison writer: the CD callback recursion
# (datasync -> Vsync -> CheckCallback -> ...) parks the SP inside the
# kernel data region and the frame saves stomp the archive cells.
# Camera: entry count, sp, caller, r16 per entry - count growth names
# the recursion; sp receipt names the parked stack.
# R1163 (b8-c348): CHAINCAM PRINT BACKOFF. c348 receipts: the CD_datasync
# entry camera printed EVERY 16th entry (gate n&15==0) - 17 MILLION poll
# entries = ~1M lines = 137MB raw log (R751 cap receipts). Same flood class
# as the c343 fault-storm and the c346 lzss-runaway print rate (R1161's
# emit-side sibling - my camera, my miss). First 12 + 1-per-million keeps
# the recursion legibility (sp/caller per entry still receipted early)
# while capping the spin-era flood. Repair in place; template below emits
# the new gate on fresh emits.
_old_gate = 'if (n < 12u || (n & 15u) == 0u) { xenolift_receipt("[chaincam]'
_new_gate = 'if (n < 12u || (n % 1048576u) == 0u) { xenolift_receipt("[chaincam]'
if _old_gate in s:
    s = s.replace(_old_gate, _new_gate)
    changed2 = True  # R1165 (b8-c350): the pre-repair checkpoint (if changed) at the
    #  top of this block ALREADY PASSED - setting `changed` here mutated s in
    #  memory and never wrote it. c350 receipts: repair printed APPLIED yet
    #  ccache proved disc1.c hash unchanged. The post-repair checkpoint at
    #  `if changed2:` persists the file.
    print('[emit] R1163 R1115 chaincam gate backoff applied (every-16 -> 1-per-million; c348: 17M entries = 137MB log flood)')
for fnid in ('8004293C',):
    marker = '/* R1115 %s */' % fnid
    call = ('{ static unsigned n; n++; if (n < 12u || (n %% 1048576u) == 0u) { xenolift_receipt("[chaincam] R1115 CD_datasync entry #%%u sp(r29)=%%08X r31caller=%%08X r16=%%08X\\n", n, r[29], r[31], r[16]); } } %s'
            % (marker,))
    lab = 'L_%s:;' % fnid
    if call in s:
        print('[emit] R1115 chaincam %s already present' % fnid)
    elif s.count(lab) >= 1:
        s = s.replace(lab, lab + '\n    ' + call, 1)
        changed = True
        print('[emit] R1115 chaincam %s APPLIED at entry label' % fnid)
    else:
        print('[emit] R1115 chaincam %s ANCHOR MISSING' % fnid)
# R1060 (b8-c222): bodycams at the disc-data family death sites. c222 death
# chain (repeated 30x to kit exit): deepest-trail 0x800392EC (copy/clear loop
# fn) -> r31 caller 0x80039120, fault addr=0xB85BF8B0 (HOST stack address),
# r4 host-tainted (E1101870/E234D2F0/E3504D60/E46CF920 vary per recovery),
# r5=0x800B0704 SPU data region. Receipts needed: entry a0-a3 of both fns
# to find where the host-tainted pointer enters the chain.
for fnid in ('800392EC', '80039120'):
    marker = '/* R1060 */'
    call = ('xenolift_bodycam(0x%su, r[4], r[5], r[6], r[7]); %s' % (fnid, marker))
    lab = 'L_%s:;' % fnid
    if call in s:
        print('[emit] R1060 datacam %s already present' % fnid)
    elif s.count(lab) >= 1:
        s = s.replace(lab, lab + '\n    ' + call, 1)
        print('[emit] R1060 datacam %s APPLIED at entry label' % fnid)
    else:
        print('[emit] R1060 datacam %s ANCHOR MISSING' % fnid)
for fnid in ('80077E88', '80076858'):
    call = 'xenolift_bodycam(0x%su, r[4], r[5], r[6], r[7]); /* R1052 */' % fnid
    lab = 'L_%s:;' % fnid
    if call in s:
        print('[emit] R1052 bodycam %s already present' % fnid)
    elif s.count(lab) >= 1:
        s = s.replace(lab, lab + '\n' + call, 1)
        changed2 = True
        print('[emit] R1052 bodycam %s APPLIED at entry label' % fnid)
    else:
        print('[emit] R1052 bodycam %s ANCHOR MISSING (label count=0 - fn not in this emit)' % fnid)
if changed2:
    io.open('disc1.c', 'w', encoding='utf-8', errors='surrogateescape').write(s)
# R1056 (b8-c216): TAINT HEAL at module-fn entries. Receipted structure:
# c213/c214 bodycam - fns 801D002C/801D2FE8 entered with a1=0xC00D7F50
# = real RAM ptr 0x800D7F50 with bit 30 (KSEG2 seg bit 0x40000000) set.
# c215 thunkcam - caller chain (coordinator -> thunk 0x80097244 bookkeeping
# code) is real module logic; full decode of its 11-step loop is a multi-cycle
# project. This heal is MINIMAL and receipt-anchored: clear ONLY the segment
# bit at entry (KSEG2 unmapped on PSX - bit30 on a 0x8xxx RAM ptr is never a
# valid contract), receipt every heal, do NOT touch a0 (the -0x20000 delta may
# be the module's own relocation - unproven either way, leave it).
changed3 = False
for fnid in ('801D002C', '801D2FE8'):
    marker = '/* R1056 %s */' % fnid
    guard = ('if (r[5] & 0x40000000u) { xenolift_receipt("[taintheal] R1056 FN %s a1 %%08X healed\\n", r[5]); r[5] ^= 0x40000000u; } %s'
             % (fnid, marker))
    lab = 'L_%s:;' % fnid
    if marker in s:
        print('[emit] R1056 taintheal %s already present' % fnid)
    elif s.count(lab) >= 1:
        s = s.replace(lab, lab + '\n    ' + guard, 1)
        changed3 = True
        print('[emit] R1056 taintheal %s APPLIED at entry label' % fnid)
    else:
        print('[emit] R1056 taintheal %s ANCHOR MISSING' % fnid)
if changed3:
    io.open('disc1.c', 'w', encoding='utf-8', errors='surrogateescape').write(s)
XEOF

mkdir -p .cache
# R152.1 host guard: never reuse objects from another machine. A shipped
# Linux .cache broke the Mac link ("unknown file type" - 16:38 cycle 2).
THIS_HOST="$(uname -s)-$(uname -m)"
if [ -f .cache/HOST ]; then
  if [ "$(cat .cache/HOST 2>/dev/null)" != "$THIS_HOST" ]; then
    echo "compile cache from a different host - wiping (.cache/HOST mismatch)"
    rm -rf .cache && mkdir -p .cache
  fi
elif ls .cache/*.o >/dev/null 2>&1; then
  echo "compile cache has unstamped objects - wiping (foreign cache suspect)"
  rm -rf .cache && mkdir -p .cache
fi
printf '%s' "$THIS_HOST" > .cache/HOST
CCFLAGS="-O3 -fno-stack-protector" # R930: canaries fight our own longjmp recovery (torn-frame false positives; c31-33 zero recoveries = zero canaries, c35/36 11 recoveries = canary storm) - the crash kit IS the safety system
# R992 (b8-c103, WARDEN): -gline-tables-only joined the cc line but was NEVER
# in the cache sentinel - objects predating it silently link, so atos returns
# symbols with NO file:line and the exit-134 smash chain (c103: xenolift_trace
# -> time() -> unnamed libc-caller) cannot be named to a source line. Fold it
# into the sentinel: one forced recompile and every crash frame resolves.
CCSENT="$CCFLAGS -gline-tables-only"
if [ "$(cat .cache/FLAGS 2>/dev/null)" != "$CCSENT" ]; then
  echo "R864: compile flags changed (now: $CCFLAGS) -> wiping object cache (R863 lesson: flag changes MUST invalidate the cache or the old objects silently link)"
  rm -rf .cache && mkdir -p .cache
  printf '%s' "$THIS_HOST" > .cache/HOST
  printf '%s' "$CCSENT" > .cache/FLAGS
fi
NEEDLINK=0
OBJS=""
# R1114 (b8-c292): HEADER DEPENDENCY VIA CONTENT HASH, not mtime. R1113's
# -nt check was correct in principle but unzip refreshes mtimes EVERY
# cycle, so the header is always "newer" than the cache and disc1.c
# recompiled for 141s every cycle, deferring all runs (c292: run
# DEFERRED, 37s window left). Hash the header once per build; compare
# against the stamp written after a successful compile pass.
HDRM=$(md5 -q runtime/xenolift_runtime.h 2>/dev/null || md5sum runtime/xenolift_runtime.h 2>/dev/null | cut -d' ' -f1)
HDRSTAMP=$(cat .cache/HDRSTAMP 2>/dev/null || echo none)
# R1157 (b8-c341): SOURCE DEPENDENCY VIA CONTENT HASH - completing R1114.
# c341 receipts: fresh emit rewrites disc1.c EVERY cycle (deterministic,
# "payload verified", byte-identical content) but the -nt mtime check sees
# a new mtime and recompiles 1M lines for 145s, squeezing the run window to
# 26s < 60s - run DEFERRED three cycles straight (c339 FATAL, c340-341
# budget-squeeze). The deadlock: fresh-emit => 145s compile => deferred run
# => no full-budget run ever. Hash each source; identical hash + existing .o
# = skip. The emitter is deterministic (payload verified), so a stable
# capture era compiles ONCE and every later cycle gets the full run budget.
for src in disc1.c runtime/runtime.c hle/hle_gpu.c hle/hle_gte.c hle/hle_spu.c hle/hle_mdec.c hle/hle_memcard.c; do
  o=".cache/$(echo "$src" | tr '/' '_').o"
  SRCH=$(md5 -q "$src" 2>/dev/null || md5sum "$src" 2>/dev/null | cut -d' ' -f1)
  SRCSTAMPF=".cache/SRC_$(echo "$src" | tr '/' '_').md5"
  SRCSTAMP=$(cat "$SRCSTAMPF" 2>/dev/null || echo none)
  # R1113 (b8-c291): HEADER DEPENDENCY IN THE COMPILE GATE. c291 receipts:
  # the R1112 sw_line macro landed in runtime/xenolift_runtime.h but
  # every [hook] printed sw_line=0 - the gate below compares only the
  # SOURCE mtime, and disc1.c was untouched, so the cached disc1.o
  # (built with the OLD header, old inline SW) stayed linked and the
  # instrument never engaged. A shipped header must invalidate every
  # object that includes it. Fix: also recompile when the runtime
  # header is newer than the object. (Tool-capital: this is the
  # build-system lesson implemented as a gate feature, per the
  # standing recompilation-assistant directive.)
  if [ ! -f "$o" ] || [ "$SRCH" != "$SRCSTAMP" ] || [ "$HDRM" != "$HDRSTAMP" ]; then
    # R230 rule + R238: -Werror parity AND hard-fail on compile error.
    if ! cc -w $CCFLAGS -gline-tables-only -Werror=implicit-function-declaration -c "$src" -Iruntime -o "$o" 2> .cc_err.txt; then
      head -8 .cc_err.txt
      echo "FATAL: compile failed for $src — refusing to run a stale binary"
      exit 1
    fi
    printf '%s' "$SRCH" > "$SRCSTAMPF"
    NEEDLINK=1
    echo "[ccache] R1157 compile: FRESH ($src content hash changed/first build)"
  else
    echo "[ccache] R1157 compile: SKIPPED ($src content hash unchanged - cached .o reused)"
  fi
  OBJS="$OBJS $o"
done
[ -n "$HDRM" ] && printf '%s' "$HDRM" > .cache/HDRSTAMP
# R1199v3 (Jos c494) PROVENANCE PROBE - GATED behind PROV=1 (the disc1.c
# recompile alone costs ~145s; a 240s bridge watchdog cannot absorb it every
# cycle). When enabled: reuses the ACTUAL in-scope compile invocation to a
# FRESH mktemp output; hashes ONLY on cc success; RE-LINKS with the probe
# object SWAPPED IN for the cached disc1 object, comparing that binary
# against prev_run_c490/xenogears_boot_last - the IMMUTABLE, hash-verified
# copy of the reported c490 executable (Jos c494: the live prev_run copy is
# overwritten every cycle; only the frozen copy is a valid comparison target).
# DIFFERING hashes are INCONSISTENCY, not staleness.
if [ "${PROV:-0}" = "1" ]; then
PROV_TMP=$(mktemp -t prov_); rm -f "$PROV_TMP"
PROV_OK=0
if cc -w $CCFLAGS -gline-tables-only -Werror=implicit-function-declaration -c disc1.c -Iruntime -o "$PROV_TMP.o" 2> prov_err.txt; then
  PROV_OK=1
  PROVH=$(shasum -a 256 "$PROV_TMP.o" 2>/dev/null | cut -d' ' -f1)
  CACHEDH=$(shasum -a 256 .cache/disc1.c.o 2>/dev/null | cut -d' ' -f1)
  if [ -n "$PROVH" ] && [ "$PROVH" = "$CACHEDH" ]; then
    echo "[prov] R1199 disc1.c probe-object IDENTICAL to cached linked object (hdr=$HDRM flags='$CCFLAGS')"
  else
    echo "[prov] R1199 disc1.c probe-object DIFFERS (probe=$PROVH cached=$CACHEDH hdr=$HDRM flags='$CCFLAGS') - INCONSISTENCY, investigate"
  fi
else
  echo "[prov] R1199 probe compile FAILED rc=$? flags='$CCFLAGS'"; head -4 prov_err.txt
fi
PROV_EXPECT="26f7fa6fc38c2b5393e58695862e6b22ba9d8a490976b959a6abb51487ba035b"
PROV_REFOK=0
if [ "$PROV_OK" = "1" ]; then
  if [ -f prev_run_c490/xenogears_boot_last ]; then
    LASTH=$(shasum -a 256 prev_run_c490/xenogears_boot_last 2>/dev/null | cut -d' ' -f1)
    if [ "$LASTH" = "$PROV_EXPECT" ]; then
      PROV_REFOK=1
    else
      echo "[prov] R1199 FAILED: immutable c490 copy present but hash mismatch (got $LASTH expected $PROV_EXPECT) - comparison NOT RUN, no fallback to mutable prev_run/"
    fi
  else
    echo "[prov] R1199 FAILED: prev_run_c490/xenogears_boot_last UNAVAILABLE - provenance comparison NOT RUN, no fallback to mutable prev_run/"
  fi
fi
if [ "$PROV_REFOK" = "1" ]; then
  PROV_SW=""
  for x in $OBJS; do
    if [ "$x" = ".cache/disc1.c.o" ]; then PROV_SW="$PROV_SW $PROV_TMP.o"; else PROV_SW="$PROV_SW $x"; fi
  done
  PROV_BIN=$(mktemp -t provbin_); rm -f "$PROV_BIN"
  if cc -w $PROV_SW -lm -lpthread -o "$PROV_BIN" 2> prov_err.txt; then
    PROVBH=$(shasum -a 256 "$PROV_BIN" 2>/dev/null | cut -d' ' -f1)
    LASTH=$(shasum -a 256 prev_run_c490/xenogears_boot_last 2>/dev/null | cut -d' ' -f1)
    if [ -n "$PROVBH" ] && [ "$PROVBH" = "$LASTH" ]; then
      echo "[prov] R1199 swap-relink binary IDENTICAL to the immutable c490 copy prev_run_c490/xenogears_boot_last (sha=$PROVBH) - source+header->object->c490-executable chain bound"
    else
      echo "[prov] R1199 swap-relink binary DIFFERS from the immutable c490 copy (probe=$PROVBH c490=$LASTH) - INCONSISTENCY, investigate"
    fi
  else
    echo "[prov] R1199 swap-relink FAILED rc=$?"; head -4 prov_err.txt
  fi
  rm -f "$PROV_BIN"
fi
rm -f "$PROV_TMP.o"
fi
if [ ! -f xenogears_boot ] || [ "$NEEDLINK" = "1" ]; then
  if ! cc -w $OBJS -lm -lpthread -o xenogears_boot 2> .cc_err.txt; then
    head -8 .cc_err.txt
    echo "FATAL: link failed — refusing to run a stale binary"
    exit 1
  fi
  echo "link: DONE"
else
  echo "link: SKIPPED (no source changed since last build)"
fi
# R238 STALE-BINARY GUARD: the freshly-linked binary MUST contain the
# CURRENT runtime.c banner token — cycle-24's compile failure fell through
# to a stale binary that masqueraded as a fresh build in the digest.
WANT=$(grep -o 'runtime build R[0-9]*' runtime/runtime.c | head -1)
if [ -n "$WANT" ]; then
  # R239: BSD tr chokes on binary under UTF-8 locale ("Illegal byte sequence",
  # cycle-25) — LC_ALL=C grep -a is the portable binary-safe scan.
  if LC_ALL=C grep -a -q "$WANT" xenogears_boot; then
    echo "banner check: OK ($WANT in binary)"
  else
    echo "FATAL: binary banner does not match runtime.c ($WANT missing) — stale binary, abort"
    exit 1
  fi
  # R443: FIX-PRESENCE PROOF — the R442 shield ran silent while its section sat in
  # run.sh, proving a label can ship without the code executing. Grep the COMPILED
  # BINARY for the fix's log tokens so every digest proves which fixes are live.
  for tok in dmashield mangleguard ringw reqres carve2 frclash descw; do
    if LC_ALL=C grep -a -q "$tok" xenogears_boot 2>/dev/null; then
      echo "[shieldcheck] $tok PRESENT in binary"
    else
      echo "[shieldcheck] $tok MISSING from binary — STALE SOURCE, fix pipeline"
    fi
  done
fi
stage "compile+link"

# R835 [f5dump]: name + classify the file#5 territory (LBA 108873, 21984B)
{ python3 - "$BIN" <<'PYF5' > f5dump.log 2>&1 || echo "[f5dump] python unavailable" >> f5dump.log; }
import sys, struct
try:
    f = open(sys.argv[1], 'rb')
except Exception as e:
    print('[f5dump] cannot open disc image: %s' % e); sys.exit()
def rd(lba, n=1):
    f.seek(lba*2352+24); return f.read(2048*n)
pvd = rd(16)
if pvd[1:6] != b'CD001': print('[f5dump] not ISO9660 (PVD missing) - head: ' + pvd[:32].hex()); sys.exit()
def walk(elba, elen, depth, path):
    data = rd(elba, (elen+2047)//2048)
    i = 0
    while i < len(data):
        L = data[i]
        if L == 0: i = (i//2048+1)*2048; continue
        rec = data[i:i+L]; lba = struct.unpack('<I', rec[2:6])[0]; size = struct.unpack('<I', rec[10:14])[0]
        flags = rec[25]; nml = rec[32]
        name = rec[33:33+nml-2].decode('latin1') if nml > 2 else ''
        if name:
            if flags & 2:
                if depth < 6: walk(lba, size, depth+1, path + name + '/')
            else:
                nsec = (size+2047)//2048
                if lba <= 108873 < lba+nsec:
                    off = (108873-lba)*2048
                    f.seek(lba*2352+24+off); head = f.read(64)
                    pr = sum(1 for b in head if 32 <= b < 127 or b in (9,10,13))
                    print('[f5dump] file#5 territory = ISO file %s (LBA %d, %d B) - contains LBA 108873 (offset %d)' % (path+name, lba, size, off))
                    print('[f5dump]   head64: ' + head.hex())
                    print('[f5dump]   ascii census: %d/64 printable' % pr)
        i += L
try:
    walk(struct.unpack('<I', pvd[156+2:156+6])[0], struct.unpack('<I', pvd[156+10:156+14])[0], 0, '/')
except Exception as e:
    print('[f5dump] walk exception: %s' % e)
print('[f5dump] walk complete - match lines above if found; silence after this = no ISO file claims LBA 108873')
PYF5
echo "--- live viewer ---"
pkill -f xenoview.py 2>/dev/null; pkill -f xenoview_ansi.py 2>/dev/null; sleep 1
if false; then
echo "not launched" > xenoview_status
if [ -f xenoview.py ]; then
  if command -v osascript >/dev/null 2>&1; then
    if osascript -e 'tell application "Terminal" to do script "cd '"$PWD"' && python3 xenoview.py"' >/dev/null 2>&1; then
      echo "live viewer (BROWSER MODE) OPENED — a browser window shows vram_live.png, refreshes 2x/sec" > xenoview_status
    else
      echo "viewer window failed: open a tab and run: python3 xenoview.py" > xenoview_status
    fi
  else
    echo "macOS Terminal not detected: open a tab and run: python3 xenoview.py" > xenoview_status
  fi
fi
cat xenoview_status
fi

echo "--- run ---"
if [ ! -f xenogears_boot ]; then
  echo "FATAL: build produced no binary - skipping run, posting digest for diagnosis"
fi
if [ -f xenogears_boot ]; then
if [ ! -f "$BIN" ]; then
    echo "FATAL: disc .bin not found at: $BIN"
    ls -la "$HOME/Desktop/PS7Z/PS1Games/" 2>/dev/null | head -8
    exit 1
fi
rm -f dec_input_*.bin overlay_dump_*.bin *.refout
# R449 FAST-CYCLE BUDGET KNOB: default 210s full trajectory. For quick-verdict
# cycles the directive block sets RUN_BUDGET_S in this script before this point
# (e.g. RUN_BUDGET_S=60) -> runtime parks earlier, fuse tightens, report ~3x sooner.
RUN_BUDGET_S=${RUN_BUDGET_S:-210}
# R784 DIGEST-WINDOW PROTECTION (c366/367): fresh-emit cycles pay 60-110s of
# compile; a full 200s run on top pushes the cycle past the bridge's ~240s
# window and the digest dies (banner "no-runlog", zero evidence). Cap the run
# budget to 120s on fresh-emit cycles so build+run+digest always lands under
# the window. Cached-emit cycles keep the full directive budget (4s builds).
if [ "${EMIT_FRESH:-0}" = "1" ] && [ "$RUN_BUDGET_S" -gt 120 ]; then
  RUN_BUDGET_S=120
  echo "[budget] R784 fresh-emit cycle: run budget capped to ${RUN_BUDGET_S}s (digest window protection; full budget resumes on cached-emit cycles)"
fi
# R789 DYNAMIC WINDOW CAP (c372): compile time varies 3s-232s; a flat cap cannot
# protect the digest when compile alone consumes the window. Cap the run budget by
# what REMAINS of the ~200s bridge window (20s digest margin); if nothing remains,
# skip the run so the digest (build evidence) always lands.
WIN_LEFT=$(( 200 - SECONDS - 20 ))
if [ "$WIN_LEFT" -lt "$RUN_BUDGET_S" ]; then
  if [ "$WIN_LEFT" -lt 60 ]; then
    # R1009 (b8-c123) TWO-PHASE CADENCE: c123 proof - the fresh emit folded
    # genuine new stage-2 code (33079 nonzero words, coverage 86.4%) which
    # forced the 143s recompile, which squeezed the run to 34s, and the fuse
    # SIGKILLED the walk (exit 137) MID-INSTALL-CHAIN (member#7 decompress
    # verdict ok + 45440-byte overlay capture + reloc-fix all landed, then
    # the timer cut it down). Progress -> new capture -> recompile -> less
    # run time -> less progress is a doom loop for the walk. FIX: on a
    # fresh-emit cycle with a squeezed window (<60s left), DEFER the run -
    # this cycle is a BUILD PASS (the fresh translation is the deliverable);
    # the next cycle emits/compiles from cache and gets the FULL window to
    # run the walk through the install chain. Never ship a walk to a 34s
    # fuse again.
    RUN_BUDGET_S=1
    echo "[budget] R1009/R1010 BUILD PASS: compile ${SECONDS}s squeezed the window (${WIN_LEFT}s left < 60s; a sub-60s fuse cannot reach the t=63s coordinator knock and dies mid-install at ~t=58s - c123/c124 both) - run DEFERRED; next cycle gets the full budget"
  elif [ "$WIN_LEFT" -le 10 ]; then
    RUN_BUDGET_S=1
    echo "[budget] R789 compile consumed the window (${SECONDS}s elapsed) - run SKIPPED this cycle, digest preserved (fresh-emit churn fix ships next)"
  else
    RUN_BUDGET_S=$WIN_LEFT
    echo "[budget] R789 dynamic window cap: run budget ${RUN_BUDGET_S}s (compile ${SECONDS}s elapsed, digest margin 20s)"
  fi
fi
echo "$RUN_BUDGET_S" > xenolift_budget.txt
FUSE=$(( RUN_BUDGET_S + 22 ))
# R848 (c436): DEFEAT CRASH-REPORT THROTTLING - c435/c436 aborts (exit 134,
# ~31s, zero receipts) left NO fresh .ips: macOS suppresses reports for a
# process name crashing identically in a window. A per-run process name makes
# every death reportable again -> the exact faulting frame chain (16:38's
# chain was __xvprintf/__stack_chk_fail inside libsystem - our interposition
# cannot see it; the throttled report is the only honest witness left).
# R869: ASan retired (c458 verdict: hunt complete - fh wild write fixed, kit recoveries healthy; the asan runtime's nested-abort on our recovery longjmp was the only remaining 31s death)
R848_NAME="xenogears_boot_$(date +%H%M%S)"
cp -f xenogears_boot "$R848_NAME"
# R1172: preserve the EXACT executable selected above, not a directory guess.
FFDIR=""
if [ -n "${XENOLIFT_FIRSTFAULT_STOP:-}" ]; then
  FFDIR=$(mktemp -d "$PWD/firstfault.XXXXXX") || exit 1
  printf '%s\n' "$FFDIR" > firstfault.latest
  printf '%s\n' "$R848_NAME" > "$FFDIR/executable-name.txt"
  cp -p "$R848_NAME" "$FFDIR/$R848_NAME" || exit 1
  tar -czf "$FFDIR/matching-source-objects.tgz" runtime hle src Cargo.toml Cargo.lock run.sh disc1.c .cache/*.o || exit 1
  shasum -a 256 "$R848_NAME" runtime/runtime.c disc1.c run.sh > "$FFDIR/source-executable.sha256" || exit 1
  nm -n "$R848_NAME" > "$FFDIR/symbols.txt" 2> "$FFDIR/nm.stderr"
  echo "$?" > "$FFDIR/nm.status"
  if command -v dsymutil >/dev/null 2>&1; then
    dsymutil "$R848_NAME" -o "$FFDIR/$R848_NAME.dSYM" > "$FFDIR/dsymutil.log" 2>&1
    echo "$?" > "$FFDIR/dsymutil.status"
  fi
  export XENOLIFT_FIRSTFAULT_RAM="$FFDIR/guest-ram.bin"
  echo "[firstfault-capture] directory=$FFDIR executable=$R848_NAME"
fi
# R1195 (c484, Jos): UNCONDITIONAL symbol preservation. Previously the
# executable + dSYM archive happened only under XENOLIFT_FIRSTFAULT_STOP
# (a behavior-changing mode). The wedge backtrace needs the EXACT executed
# binary for stack attribution on the next cycle, BEFORE the next rebuild
# replaces xenogears_boot. Bounded: one prev_run/ slot, overwritten per run.
mkdir -p prev_run
cp -f "$R848_NAME" prev_run/xenogears_boot_last 2>/dev/null || true
shasum -a 256 "$R848_NAME" > prev_run/last.sha256 2>/dev/null || true
nm -n "$R848_NAME" > prev_run/last_symbols.txt 2>/dev/null || true
cp -f runtime/runtime.c prev_run/runtime_last.c 2>/dev/null || true  # R1200: archive the SOURCE that built this binary (Jos c497: future line numbers must resolve against the matching source, not the evolved tree)
echo "[prov] R1200 source archived: prev_run/runtime_last.c sha256=$(shasum -a 256 prev_run/runtime_last.c 2>/dev/null | cut -d' ' -f1)"
if command -v dsymutil >/dev/null 2>&1; then
  dsymutil "$R848_NAME" -o prev_run/last.dSYM > /dev/null 2>&1 || true
fi

"./$R848_NAME" SLUS_006.64 "$BIN" > run.log 2>&1 &
RUNPID=$!
( sleep $FUSE; kill -9 $RUNPID 2>/dev/null ) &
FUSEPID=$!
RUNGASP=0
wait $RUNPID 2>/dev/null
RUNGASP=$?
if [ -n "$FFDIR" ]; then
  # Copy authoritative output immediately, before digest/report postprocessing.
  cp -p run.log "$FFDIR/firstfault-full.log" || exit 1
  printf '%s\n' "$RUNGASP" > "$FFDIR/guest-exit.status"
  echo "[firstfault-capture] guest_exit=$RUNGASP full_log=$FFDIR/firstfault-full.log"
fi
kill $FUSEPID 2>/dev/null
RUNGASP_LINE="[rungasp] R806 process exit status=$RUNGASP (0=clean main-return; 99=kit/exitdiag door _exit; 9=fuse SIGKILL; 11/139=host SIGSEGV; 10/138=SIGBUS; 6=SIGABRT) - the silent-death class camera (c385-390: runs died at 10-32s with NO crash dump, NO exit receipt; the wait status names the door)"
echo "$RUNGASP_LINE"
echo "$RUNGASP_LINE" >> run.log
echo "[wedge] R1196 executed-binary $R848_NAME sha256=$(cut -d' ' -f1 prev_run/last.sha256 2>/dev/null) dSYM=$(command -v dsymutil >/dev/null 2>&1 && echo prev_run/last.dSYM || echo none)" >> run.log
echo "[fuse] run fuse cleared (R356: 210s hard kill — digest always generates)"
# R833 (c414/416/418): MAC CRASH-REPORT HARVEST - the silent SIGABRT deaths
# (exit 134) leave NO receipt anywhere in our machinery: no exitdiag, no
# wildctx, no jumprec, no segvdie - the abort bypasses every camera we own.
# But macOS itself writes a crash report with the FULL raising backtrace to
# ~/Library/Logs/DiagnosticReports for every signal death. Post-mortem: when
# the exit status is abnormal, harvest the newest xenogears_boot crash report
# from the last 15 minutes and print the termination reason + crashed-thread
# frames. Zero runtime risk - this runs AFTER the process is dead.
if [ "$RUNGASP" != "0" ] && [ "$RUNGASP" != "137" ]; then
  { # R833b: receipts go to run.log (digest greps run.log), console too via tee
  DR="$HOME/Library/Logs/DiagnosticReports"
  sleep 4 # R848b: CrashReporter flush lag - this run's death .ips may take seconds to appear
  NEWEST=$(find "$DR" -name 'xenogears_boot*' -mmin -15 2>/dev/null | xargs ls -t 2>/dev/null | head -1)
  if [ -n "$NEWEST" ]; then
    RAGE=$(( $(date +%s) - $(stat -f %m "$NEWEST" 2>/dev/null || stat -c %Y "$NEWEST" 2>/dev/null || echo 0) ))
    echo "[macreport] R833 macOS crash report harvested: $NEWEST (report age ${RAGE}s - age > run lifetime = STALE, NOT this run's death; R847 freshness fix)"
    grep -m1 '"termination"' "$NEWEST" 2>/dev/null | head -c 300; echo
    # crashed thread frames: .ips JSON - pull the first "frames" array names
    # R838: abort-specific info + exception + frames with raw fallbacks (the
    # in-process cameras die with the process; the .ips survives and names
    # the host abort site - c423: exitdiag printed then the process still
    # died 134 with no receipt = the handler returned into abort's re-raise)
    python3 - "$NEWEST" "$R848_NAME" <<'PYMAC' 2>/dev/null || true
import json, sys, re, os
def r850_resolve(img, fr):
    """R850 (c438): symbolize OUR-binary frames via atos - the c438 .ips named
    the chain fn_80077E88 -> xenolift_trace -> fprintf -> __xvprintf canary
    abort, but no source line. The binary ships -gline-tables-only; atos on
    the frame's imageOffset resolves to file:line = the exact print."""
    if 'xenogears_boot' not in str(img) or len(sys.argv) < 3: return None
    try:
        import subprocess
        io = fr.get('imageOffset')
        if io is None: return None
        out = subprocess.run(['atos','-o',sys.argv[2],'-offset',str(io)],
                             capture_output=True, text=True, timeout=10)
        s = (out.stdout or '').strip()
        return s if s else None
    except Exception:
        return None
def r857_regs(th, tag):
    """R859 (c447): register evidence for the canary-in-print abort class.
    Lives as a helper because BOTH .ips body paths need it - the original
    R857 block sat only in the primary single-line-JSON branch, but every
    xenogears_boot report so far is a MULTI-LINE body (body=None there,
    fallback branch prints the frames) so R857 never printed. c446/c447
    digests carried frames but no faulting regs - this closes that hole.
    x1 = fmt-string ptr for a crash at the print door; lr = return addr
    into our print site; read the actual C-string from the binary."""
    try:
        regs = th.get('registers') or {}
        if not regs and isinstance(th.get('threadState'), dict):
            # R993: c104's R992 thread-keys dump receipted the ips v2 layout -
            # "frames,id,instructionState,threadState,triggered" - the register
            # values live in threadState, NOT 'registers'. Read them there.
            regs = th['threadState']
        # R995 (b8-c106): the conditional dumps (R992 elif-chain) never fired
        # across c103-c106 while regs stayed all-'?' - two cycles of register
        # evidence lost to a condition I cannot validate from the receipts.
        # UNCONDITIONAL now: whenever the thread dict carries threadState or
        # instructionState (c104 keys receipt: "frames,id,instructionState,
        # threadState,triggered"), dump keys + clamped JSON. No guessing.
        import json as _j
        for _sk in ('threadState', 'instructionState'):
            _sv = th.get(_sk)
            if _sv is None:
                continue
            try: _sj = _j.dumps(_sv)
            except Exception: _sj = repr(_sv)
            print("[macreport] R995 %s (%s): %s" % (_sk, tag, _sj[:600]))
        if not regs:
            # R992: c103 printed all-'?' regs - the multi-line-body thread dict
            # carries no 'registers' key. Name what IS there + scan the raw ips
            # for a registers line so the next abort ships real values.
            print("[macreport] R992 thread keys (%s): %s" % (tag, ",".join(sorted(th.keys()))))
            for ln in lines:
                if '"registers"' in ln:
                    i0 = max(0, ln.find('"registers"') - 2)
                    print("[macreport] R992 raw registers: " + ln[i0:i0+430])
                    break
        print("[macreport] R857 faulting regs (%s): " % tag + " ".join(
            "%s=%s" % (k, regs.get(k, '?')) for k in
            ('x0','x1','x2','x3','lr','fp','sp','pc')))
        x1s = (regs.get('x1') or '?')
        try:
            x1 = int(x1s, 16) if not isinstance(x1s, int) else x1s
        except Exception:
            x1 = 0
        BIN = sys.argv[2] if len(sys.argv) > 2 else 'xenogears_boot'
        if x1 and 0x100000000 <= x1 < 0x100000000 + 0x20000000 and os.path.exists(BIN):
            off = x1 - 0x100000000
            with open(BIN, 'rb') as fb:
                fb.seek(off)
                raw = fb.read(160)
            s = raw.split(b'\x00')[0]
            if s and all(32 <= c < 127 or c in (9, 10) for c in s):
                print("[macreport] R857 CRASHING FMT STRING @0x%X: %r" % (x1, s[:150]))
            else:
                print("[macreport] R857 x1 @0x%X not a printable string (raw %r)" % (x1, raw[:24]))
    except Exception as e:
        print("[macreport] R857 reg-evidence failed (%s): %s" % (tag, e))

raw = open(sys.argv[1], encoding='utf-8', errors='replace').read()
lines = raw.splitlines()
print("[macreport] R838 ips size=%d lines=%d" % (len(raw), len(lines)))
# abort-specific info (v2 key 'asi') + exception + termination - raw key greps
for key in ('"asi"', '"exception"', '"termination"', '"bug_type"'):
    for ln in lines:
        if key in ln:
            seg = ln[max(0, ln.find(key)-40):ln.find(key)+360]
            print("[macreport] R838 %s ... %s" % (key.strip('"'), seg[:420]))
            break
# v2 body: find the dict line with threads/faultingThread
body = None
for ln in lines:
    try:
        j = json.loads(ln)
        if isinstance(j, dict) and ('threads' in j or 'faultingThread' in j):
            body = j; break
    except Exception: pass
if body:
    ft = body.get('faultingThread', 0)
    ths = body.get('threads') or []
    th = ths[ft] if 0 <= ft < len(ths) else {}
    frames = th.get('frames') or []
    imgs = body.get('usedImages') or []
    print("[macreport] R838 faultingThread=%d frames=%d" % (ft, len(frames)))
    r857_regs(th, "v2 body")
    for i, fr in enumerate(frames[:20]):
        img = '?'
        try: img = imgs[fr.get('imageIndex', 0)].get('name','?')
        except Exception: pass
        sym = fr.get('symbol') or fr.get('imageOffset') or '?'
        print("[macreport]   frame %d: %s %s" % (i, img, sym))
        res = r850_resolve(img, fr)
        if res: print("[macreport]   frame %d R850 RESOLVED: %s" % (i, res))
        if 3 <= i <= 7:  # R994: raw frame dicts for the smash region - the '?' printer hides fields it doesn't name; the dict names them
            print("[macreport] R994 frame %d raw: %s" % (i, json.dumps(fr)[:400]))
else:
    # multi-line body attempt: join everything after the metadata line
    for cut in (1, 2):
        try:
            j = json.loads("\n".join(lines[cut:]))
            if isinstance(j, dict) and ('threads' in j or 'faultingThread' in j):
                body = j; break
        except Exception: pass
    if body:
        ft = body.get('faultingThread', 0)
        ths = body.get('threads') or []
        th = ths[ft] if 0 <= ft < len(ths) else {}
        frames = th.get('frames') or []
        imgs = body.get('usedImages') or []
        print("[macreport] R838 faultingThread=%d frames=%d (multi-line body)" % (ft, len(frames)))
        r857_regs(th, "multi-line body")
        for i, fr in enumerate(frames[:20]):
            img = '?'
            try: img = imgs[fr.get('imageIndex', 0)].get('name','?')
            except Exception: pass
            sym = fr.get('symbol') or fr.get('imageOffset') or '?'
            print("[macreport]   frame %d: %s %s" % (i, img, sym))
            res = r850_resolve(img, fr)
            if res: print("[macreport]   frame %d R850 RESOLVED: %s" % (i, res))
            if 3 <= i <= 7:  # R994: raw frame dicts for the smash region - the '?' printer hides fields it doesn't name; the dict names them
                print("[macreport] R994 frame %d raw: %s" % (i, json.dumps(fr)[:400]))
    else:
        print("[macreport] R838 no JSON body found - raw fallback: first 6 lines")
        for ln in lines[:6]: print("[macreport]   raw:", ln[:400])
PYMAC
    echo "[macreport] R833 harvest done"
    # R858 (c446): the in-process canary (R840/R853) now prints the image-relative
    # decimal offset of the smashed call site; atos it against the running binary
    # = the EXACT source line of the stack buffer overflow in runtime.c.
    if [ -f run.log ]; then
        for off in $(grep -ho 'atos-offset [0-9]*' run.log run.log.d 2>/dev/null | awk '{print $2}' | sort -u | head -3); do
            echo "[macreport] R858 CANARY LINE RESOLVED (offset $off): $(atos -o "$R848_NAME" -offset "$off" 2>/dev/null || echo atos-empty)"
        done
        # R992 (b8-c103, WARDEN): the c103 smash chain left R850 with raw decimal
        # offsets (atos fell back) - now that line tables land in every object
        # (CCSENT), re-resolve EVERY R850 decimal against the binary: file:line
        # for each frame in the exit-134 chain names the exact runtime.c camera.
        for off in $(grep -ho 'R850 RESOLVED: [0-9]*$' run.log 2>/dev/null | awk '{print $3}' | sort -u | head -10); do
            echo "[macreport] R992 CRASH-CHAIN LINE (offset $off): $(atos -o "$R848_NAME" -offset "$off" 2>/dev/null || echo atos-empty)"
        done
    fi
  else
    echo "[macreport] R833 no macOS crash report found in last 15 min (find DiagnosticReports empty)"
  fi
  } 2>&1 | tee -a run.log
fi
else
  echo "run skipped (no binary)" > run.log
fi
stage "15s run"

echo "--- digest ---"
# R252 LOG-SIZE GUARD: a stuck wait loop can produce a GB-scale run.log;
# grepping that stalls the digest 220s+ (R250 cycle-1). Keep head+tail.
{ # R314: digest collected into digest.tmp, then size-capped for the platform message limit (cycles 61-62 posted a sliced fragment)
# R799 (c382): the wc -c size probe READ the whole raw log - the built-band
# walk (real code through the interpreter) logs at unprecedented volume and
# the full-file read alone blew the digest window (cycle killed at 240s, no
# digest posted). stat = size WITHOUT reading; plus pre-trim the raw to 200MB
# so no forensic read can ever stall the digest either.
LOGB=$(stat -f%z run.log 2>/dev/null || stat -c%s run.log 2>/dev/null || echo 0)
# R751 UNCONDITIONAL CAP (c326/c327: two cycles posted EMPTY digests - a 166s
# alive field-era run makes a log the digest block can't finish before the
# bridge deadline, and the >20MB-only swap never announced itself). Cap ALWAYS:
# head 16k + tail 16k lines, swap in as run.log so every direct grep is fast;
# raw log kept as run.log.raw for forensics.
mv run.log run.log.raw 2>/dev/null || true
if [ "$LOGB" -gt 200000000 ]; then
  tail -c 200000000 run.log.raw > run.log.trim 2>/dev/null && mv run.log.trim run.log.raw
  echo "[logtrim] R799 raw log pre-trimmed to last 200MB for bounded forensics" >&2
fi
sed -n '1,16000p' run.log.raw > run.log.d 2>/dev/null
echo "[logcap] R751 unconditional cap: raw log ${LOGB}B - keeping first 16k + last 16k LINES" >> run.log.d
tail -n 16000 run.log.raw >> run.log.d 2>/dev/null
echo "[logcap] end tail" >> run.log.d
grep -v "runtime build" run.log.d > run.log.d2 && mv run.log.d2 run.log.d
cp run.log.d run.log
echo "[digest] R751 log raw ${LOGB}B -> capped $(wc -c < run.log.d)B, assembling (this line visible = if digest is still empty, the block stalled, NOT the log)"
echo "=IRQW="  # R987 (b8-c98, WARDEN/MANAGER - interrupt-cell watcher DEDICATED SECTION): c98's =FONTW= head-cap can hide the 0x80068960/64 [hook] lines - the 0x20021001 writer hunt depends on them
grep -a "\[hook\] 0x80068960\|\[hook\] 0x80068964" run.log run.log.d 2>/dev/null | head -12
grep -a "irqw\]" run.log run.log.d 2>/dev/null | head -12
echo "=EMITAUDIT="  # R987: the fresh emit (c98) broke the R926 anchor and coverage jumped (85.7->90.5%, fns 3950->2999, seams 209->2) - audit what the fresh disc1.c pulls in (the crash frames showed "fprintf" attributed to real_main while our sources hold ZERO fprintf; if the fresh emit introduced one, this names it)
echo -n "[emitaudit] disc1.c printf-family call count: "; grep -c "fprintf(\| snprintf(\| sprintf(\| printf(" disc1.c 2>/dev/null
grep -n "fprintf(\| snprintf(\| sprintf(\| printf(" disc1.c 2>/dev/null | grep -v "static void xenolift_fn\|/\\*\| \* " | head -8
echo -n "[emitaudit] R926 target present: "; grep -c "UnpackCompressedBuffer" disc1.c 2>/dev/null
# R991 (b8-c102): IRQW + EMITAUDIT moved to the digest FRONT - c102's fresh-emit
# death (exit 134, unresolved frame 4) cut BOTH sections via the 16KB head cap;
# the crash-class hunt is BLIND without them. Front = always inside the head.
# Section content unchanged - pure reorder.
echo "=EXITDIAG="  # R993 (b8-c104): exit 99 (kit/exitdiag door) fired this cycle and its [exitdiag] receipts were capped out with the mid-digest =B2X= block - an unnamed death. Front placement = always in the head cap.
# R998 (b8-c110): the R997 [exithv] in-handler-fault receipt had NO digest
# section - c110 died exit-99 with =EXITDIAG= empty and NO [exithv] line
# anywhere in the digest: either a different door or the receipt fired and
# was invisible (receipts also showed concurrent-write interleaving this
# cycle - mangled segvrec counters). Surface [exithv] so the next exit-99
# names its door.
grep -a "\[exitdiag\]" run.log run.log.d 2>/dev/null | tail -14
grep -a "exithv\]" run.log run.log.d 2>/dev/null | tail -6
echo "=COORDERA="  # R1015 (b8-c129): the coordinator is now the death venue - c129's t=77s
# receipts (ovlcb entry w/ args, fldcb FIELD-PHASE #0, R640 STATE-1, mount cells,
# sound-heap block consumption via pNext hooks) pushed the primary CRITICAL crash
# receipt out of the EXITTAIL last-96 window, so the coordinator-era fault went
# UNNAMED. This section surfaces the crash-kit report head (sig/addr/cur_fn/r31 +
# code@cur_fn first line) from BOTH logs plus the coordinator receipt family, so
# the t=77s fault class gets named before any fix ships.
grep -a -A4 "crash. CRITICAL" run.log run.log.d 2>/dev/null | head -40
grep -a "ovlcb\]\|fldcb\]\|coordheal\]\|STATE-1 ENTRY\|coordb. R683 field-module base\|coordb. R683 module table" run.log run.log.d 2>/dev/null | tail -16
grep -a "coordarg\]" run.log run.log.d 2>/dev/null | tail -8
grep -a "cardgate\]\|[filewrite\]\|cardgate\]" run.log run.log.d 2>/dev/null | tail -8
echo "=SPXW="  # R1017 (b8-c131): scratchpad-content decode kit - c131 receipts: the
# module helper 0x80076858 tail-jumped to 0x1F8000B0 and the executor found a
# ZERO WORD (0 instrs serviced). Surface the sp-window write-watch (late writes
# past the R740 cap) + module-helper entry camera - what installs the window,
# what the helper expects.
grep -a "spxw\]" run.log run.log.d 2>/dev/null | tail -12
grep -a "modhelp\]" run.log run.log.d 2>/dev/null | tail -6
grep -a "spstub\] R740" run.log run.log.d 2>/dev/null | tail -6
grep -a "spexec\]" run.log run.log.d 2>/dev/null | tail -6
echo "=SNDREG="  # R1013 (b8-c127): my c127 miss - the R1012 sndinit cameras shipped with NO
# digest section, so the sound-init verdict (gate-bail vs mid-init fault vs
# not-called) stayed invisible while the run died in the 800465EC family.
# Surface [sndinit] (R1012 sound cameras) + [gpu2reg] (R1013 GPU mirror cells
# baseline vs crash values) - the two open decode lanes.
grep -a "sndinit\]" run.log run.log.d 2>/dev/null | tail -8
grep -a "gpu2reg\]" run.log run.log.d 2>/dev/null | tail -10
grep -a "sndheal\]" run.log run.log.d 2>/dev/null | tail -6
echo "=GATEMISS="
# R999 (b8-c111): unhandled BIOS gate calls - c111 proved they pass
# silently (B0 FileWrite 0x35 death, no log). The R999 runtime receipt
# names every unknown gate fn; surface it right behind EXITDIAG.
grep -a "gatemiss" run.log run.log.d 2>/dev/null | tail -12
echo "=COORDW="
# R1000 (b8-c112): coordinator-entry writer watch - c112 executed
# COMPRESSED data at 0x80077E88 (the field coordinator entry); this names
# every writer of the entry words (front placement, area-1 primary).
grep -a "coordw" run.log run.log.d 2>/dev/null | tail -20
echo "=UNPACKW="
# R1001 (b8-c114): unpack-call census - WHICH buffers does the kernel's
# UnpackCompressedBuffer actually expand (field module included or not),
# plus dispatch-time proof at the coordinator door.
grep -a "unpackw\]" run.log run.log.d 2>/dev/null | tail -16
grep -a "coordent" run.log run.log.d 2>/dev/null | tail -8
echo "=MODMISS="
# R1002 (b8-c116): window-0 module dispatches with no native code + the
# fldx expansion-gate state - the convergence failure camera.
grep -a "modmiss\]" run.log run.log.d 2>/dev/null | tail -8
grep -a "fldx\]" run.log run.log.d 2>/dev/null | tail -4
grep -a "fldreloc\]" run.log run.log.d 2>/dev/null | tail -4
grep -a "fldx2\]" run.log run.log.d 2>/dev/null | tail -6
echo "=MODEXEC="
# R1006: did the walk dispatch INTO the expanded module? coordent words + module-window XTRACE activity
grep -a "coordent\]" run.log run.log.d 2>/dev/null | tail -4
grep -a "modmiss\]" run.log run.log.d 2>/dev/null | tail -4
grep -a "modhdr\]" run.log run.log.d 2>/dev/null | tail -44
grep -a "winscan\]" run.log run.log.d 2>/dev/null | tail -8
echo "=GPULIVE="
echo "=ARCHREQ="
grep -h "mvkick\|skipgate\|cdf\]\|padstart\|cell 0x8006A22C\|cell 0x8005FDF8" run.log run.log.d 2>/dev/null | head -80
grep -h "mv-conv\|b2x\]" run.log run.log.d 2>/dev/null | head -12  # R958: pending conversions + the kernel exit() door (names the pass-death reason)  # R957: movie-era state lines only (archx + boot-cell noise cut - they ate the head budget c66)
grep -h "DATA HANDLER" run.log run.log.d 2>/dev/null | head -30  # R957: the sector stream, after the state lines  # R953: movie-era request-block writers + START presses + skipgate state
echo "=TITLEERA="
grep -h "mpad\|bootmain\|\[rcnt\|GPU LIST\|\[padrd\|menu detected" run.log run.log.d 2>/dev/null | head -30  # R952: AREA 3 chain - kernel menu frames, controller reads, boot-main continuation, DMA lists
echo "=LOGOPAINT="
grep -h "logopaint\|splashgate" run.log run.log.d 2>/dev/null | head -12  # R951: direct-paint receipt + gate
echo "=SPLASHGATE="
grep -h "splashgate\|asciiart" run.log run.log.d 2>/dev/null | head -42  # R950: splash-era door-force gate + ASCII art
echo "=SPLASHPACE="
grep -h "splashpace\|asciiart" run.log run.log.d 2>/dev/null | head -40  # R949: splash Vsync pace + ASCII framebuffer art (the logo as text)
echo "=TPAGEFIX="
grep -h "tpagefix\|envcap" run.log run.log.d 2>/dev/null | head -14  # R948: splash tpage 0xE1 re-delivery
echo "=SPLASHUP="
grep -h "splashup\|splashbuf" run.log run.log.d 2>/dev/null | head -12  # R947: the 0xA0 texture upload HLE - first pixels
echo "=LOADCAM="
grep -h "loadcam" run.log run.log.d 2>/dev/null | head -24  # R946: LoadImage=80044894 args+RECT+data - the texture upload door
echo "=ENVVT="
grep -h "envvt" run.log run.log.d 2>/dev/null | head -28  # R945: full GPU env vtable flow - the texture-upload door
echo "=FLUSH14="
grep -h "flush14" run.log run.log.d 2>/dev/null | head -20  # R944: env+14 flush HLE - the native submit door
echo "=PRIMSUB="
grep -h "primsub" run.log run.log.d 2>/dev/null | head -10  # R942: HLE prim submit at DrawPrim door - first pixels attempt
echo "=PRIMX="
grep -h "primx" run.log run.log.d 2>/dev/null | head -32  # R943: widened - head-8 cut env+14 entries (own camera-visibility bug class)  # R941: did the env submitter fns ever enter (the dead-link verdict)
echo "=GPUCLS="
grep -h "gpucls" run.log run.log.d 2>/dev/null | head -8  # R939: executed/dropped GP0 command census (pixels door)
grep -h "\[gpu\] R694" run.log run.log.d 2>/dev/null | head -4  # R938: periodic GPU live state (placed FIRST - survives digestcap on every death door)
grep -h "\[screen\] R693" run.log run.log.d 2>/dev/null | head -4  # R938: periodic VRAM census (answers did-VRAM-move even on SIGABRT deaths)
grep -h "\[screen\] R736" run.log run.log.d 2>/dev/null | head -2  # R938: 16-band census (where the paint landed)
echo "=SPSTUB="
grep "spstub\|fcb16\|fcbfix\|fcbdone\|file25w\|cbreal\|spexec\|fcbidx\|instw\|modfn\|fhelp\|fhelpmiss\|fhelpsum\|fwrestart" run.log.d run.log 2>/dev/null | head -40  # R744: scratchpad/field-cb evidence FIRST - c318/c319 photos died in digestcap tail
echo "=SPCTX="
grep "spctx\|spexec" run.log.d run.log 2>/dev/null | head -20  # R932: stub-source context at the scratchpad jump (jump caller, sp top, scratchpad dump)
echo "=CDCB="
grep "cdcb" run.log.d run.log 2>/dev/null | head -12  # R933: CD callback slot garbage-heal receipts (ready-cb 800564AC / data-cb 800564A8)
echo "=FLHEAD="
grep "flhead" run.log.d run.log 2>/dev/null | head -10  # R934: freelist head NULL->sentinel heal receipts (heap+0x1B0 door)
echo "=GPUFIN="
grep -h "gpufin" run.log.d run.log 2>/dev/null | head -8  # R937: GPU final state as death evidence (survives digestcap)
echo "=DRAWCAM="
grep "drawcam" run.log.d run.log 2>/dev/null | head -8  # R936: DrawPrim env+prim context (pixels door camera)
echo "=STKBAND="
grep "stkband\|stkfix" run.log.d | head -50  # R755 writers + R756 scrub-at-fault receipts
echo "=FILE25W="
grep "file25w" run.log.d | tail -60  # R753 field-file era watcher: FE04>=17, 2s cadence - file 25 slow-load vs wall
echo "=HEAPFIX="; grep "\[heapfix\]" run.log.d | head -16  # R441/R443 ledger fix verdicts - expect ONE redirect per boot
echo "=DMASHIELD="; grep "\[dmashield\]" run.log.d | head -24  # R442: record-page shield verdicts - expect clips ONLY on the staging-top overshoot sectors; [frclash] may still log (it fires on the same intersect) but [recdump] must stay healthy at fault time  # R441: double-book fix verdicts - expect ONE redirect on cycle 1; then [frclash] must go silent and [recdump] must stay healthy at fault time
echo "=FLDSEC="; grep "\[fldsec\]" run.log.d | head -80  # R445: per-sector delivery clock - the pump-tuning data
# R704: promote the field-era stage-2 capture for the next fresh emit (capture-compile)
if [ -f stage2_field.bin ] && [ $(stat -f%z stage2_field.bin 2>/dev/null || stat -c%s stage2_field.bin) -ge 135168 ]; then
  NZ=$(xxd -p stage2_field.bin 2>/dev/null | tr -d '0a\n' | tr -d '0' | wc -c)
  if [ "$NZ" -gt 4000 ]; then
    if [ ! -f stage2_region.bin ]; then
      cp stage2_field.bin stage2_region.bin; echo "stage2: field-era capture promoted to stage2_region.bin ($NZ nonzero hex chars) [first promotion]"
    else
      NZOLD=$(xxd -p stage2_region.bin 2>/dev/null | tr -d '0a\n' | tr -d '0' | wc -c)
      # R789 STABILITY GATE (c372): stage2 captures drift 1-4% per run (era
      # noise) - unguarded promotion changed the emit signature EVERY cycle,
      # forcing perpetual fresh emits (c372's compile alone was 232s and the
      # digest died before the run). Promote ONLY on >20% drift = genuine era
      # jump; small drift keeps disc1.c + the compile cache valid.
      DRIFT=$(( NZOLD > 0 ? (NZ - NZOLD) * 100 / NZOLD : 100 ))
      if [ "$DRIFT" -gt 20 ] || [ "$DRIFT" -lt -20 ]; then
        # R1324 VTABLE SANITY GATE (c247, the c245/c246 receipts): the
        # unguarded promotion burned STRING-ERA captures in as emit input - the
        # module walked its callback table into ASCII strings (16 skiphook
        # receipts: Mod/Stre/Paus/ Err/Wait/ing; the ovlfault R783 poison
        # guards exist for overlay_fault but the stage-2 path had NO content
        # gate, only the R789 NZ-drift gate). GATE: the capture head must hold
        # >=2 pointer-class words (0x80xxxxxx) among its first 16 words before
        # it may overwrite stage2_region.bin; a refused string/garbage era
        # KEEPS the previous capture. Persistent refusals receipt that the
        # field install never completes with real vtables - the next target.
        S2PTR=$(od -An -tx4 -N64 stage2_field.bin 2>/dev/null | tr -s ' \t' '\n' | grep -c '^80[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]$' || true)
        if [ "${S2PTR:-0}" -ge 2 ]; then
          cp stage2_field.bin stage2_region.bin; echo "stage2: field-era capture promoted to stage2_region.bin ($NZ nonzero hex chars, drift ${DRIFT}%, $S2PTR ptr-class head words)"
        else
          echo "stage2: promotion REFUSED (R1324 vtable sanity: $S2PTR ptr-class head words - string/garbage era; keeping previous capture)"
        fi
      else
        echo "stage2: promotion SKIPPED (drift ${DRIFT}% within era-noise band - compile cache preserved, R789)"
      fi
    fi
  fi
fi
echo "=BUILD="; head -1 run.log; grep "overlay" emit.log | head -4
grep -m1 "loaded SLUS" run.log || echo "[disc] SLUS EXE LOAD LINE MISSING — disc read suspect"

echo "=TIMING= cycle seconds: $SECONDS (download+unzip excluded)"
echo "=WD="; grep "\[wd\]\|\[halt\] run budget" run.log | tail -10
echo "=TICK="; echo "fd-ticks: $(grep -c "fd-collector tick" run.log) wl-ticks: $(grep -c "wait-loop tick" run.log) reads-done: $(grep -c "read complete" run.log) pairs: $(grep -c "pair dispatch" run.log) forces: $(grep -c "forced data-ready" run.log) convs-used: $(grep -c "converting stuck INT1" run.log) reprimes: $(grep -c "re-primed response FIFO" run.log) kicks: $(grep -c "fd-kick: queued request" run.log) rspops: $(grep -c "\[rspop\]" run.log)"
echo "=WHEAL="; grep "wheal" run.log run.log.d 2>/dev/null | head -8
echo "=WALKHEAD="; grep "walkhead" run.log run.log.d 2>/dev/null | head -8
echo "=WALKNODE="; grep "walknode" run.log run.log.d 2>/dev/null | head -12
echo "=WALKTERM="; grep "walkterm" run.log run.log.d 2>/dev/null | head -8
echo "=WALKSRC="; grep "walksrc" run.log run.log.d 2>/dev/null | head -8
echo "=WALKIDX="; grep "walkidx" run.log run.log.d 2>/dev/null | head -8
echo "=ASYCTX="; grep "asyctx" run.log run.log.d 2>/dev/null | head -8
echo "=BOUNDARYREL="; grep "boundaryrel" run.log run.log.d 2>/dev/null | head -8
echo "=COVERAGE="; head -5 coverage.txt 2>/dev/null
echo "=SEAMINV="; head -3 seams.txt 2>/dev/null
echo "=FLDDEC="; grep "fld-dec" run.log run.log.d 2>/dev/null | head -4
echo "=ETCBEAT="; grep "etcbeat" run.log run.log.d 2>/dev/null | head -8
echo "=SEEKDONE="; grep "seekdone" run.log run.log.d 2>/dev/null | head -8
echo "=SCREEN="
gestalt=1 grep -h "\[screen\]" run.log 2>/dev/null | head -16; grep -h "\[screen\]" run.log.d 2>/dev/null | head -6
# R986 (b8-c97, MANAGER/TOOLING - SCREEN ASCII PREVIEW): the screen sampler
# and the PNGs live on the Mac; the digest (the ONLY thing that crosses the
# bridge) has never carried the actual framebuffer - "player-visible evidence
# every cycle" was receipts-only. Render the display crop of vram.bin (the
# capture-time dump, NOT the stale sampler) as an ASCII luminance picture so
# pixels ride the text bridge. Splash-era paint (rects 32,88 256x48) becomes
# VISIBLE in-chat; black screens are receipt-backed by the raw dump itself.
echo "=SCREENASCII="
python3 - <<'XEOF' 2>/dev/null
import struct
try:
    vram = open('vram.bin','rb').read()
    m = open('vram.meta').read().split()
    dx,dy,dw,dh = (int(x) for x in m[:4])
except Exception:
    print('[ascii] no vram.bin/meta'); raise SystemExit
dw = max(16, min(1024-dx, dw)); dh = max(16, min(512-dy, dh))
COLS, ROWS = 96, 36
nz = 0; tot = 0
ramp = " .:-=+*#%@"
out = []
for ry in range(ROWS):
    line = []
    for rx in range(COLS):
        x0 = dx + rx*dw//COLS; x1 = dx + (rx+1)*dw//COLS
        y0 = dy + ry*dh//ROWS; y1 = dy + (ry+1)*dh//ROWS
        s = 0; c = 0
        for y in range(y0, max(y0+1,y1)):
            for x in range(x0, max(x0+1,x1)):
                p = struct.unpack_from('<H', vram, (y*1024+x)*2)[0]
                lum = (p & 0x1F) + ((p>>5) & 0x1F) + ((p>>10) & 0x1F)
                s += lum; c += 1
                tot += 1
                if lum: nz += 1
        v = s // c
        line.append(ramp[min(9, v*10 // 93)])
    out.append(''.join(line))
print(f'[ascii] display {dw}x{dh}@({dx},{dy}) -> {COLS}x{ROWS} cells | nonzero {nz}/{tot} = {100*nz//max(1,tot)}%')
for l in out: print(l)
XEOF
python3 vramtopng.py >/dev/null 2>&1 && echo "[ascii] vram.png + screen.png refreshed on Mac (open xenolift/screen.png to see the real image)"

echo "=FAULTCTX="; grep -a "faultctx" run.log.d 2>/dev/null | head -10  # R697: moved to FRONT (digestcap cut it late twice)
echo "=FHSITE="
grep -a "fhsite" run.log run.log.d 2>/dev/null | head -24
echo "=ASCIIW="; grep -a "asciiblast" run.log.d 2>/dev/null | head -10  # R697: text-written-where-binary-belongs writer naming
echo "=MCW="; grep -a "\[mcw\]" run.log.d 2>/dev/null | head -12  # R697: mount-mailbox writer naming (kernel polls 92C0 20x)
echo "=RECTGUARD="; grep -a "rectguard\|fldreloc" run.log.d 2>/dev/null | head -14  # R700: live terminator-node heal + writer naming
echo "=B2X="; grep -a "b2x\|b2exit\|exitdiag\]" run.log.d run.log 2>/dev/null | head -16
echo "=F15DISC="; grep -a "R712\|R713\|R714\|R715\|b2x\|b2exit\|f15disc\|fldreloc2\|bootentry\|boot2b\|boot2" run.log.d run.log 2>/dev/null | head -24
echo "=BOOT2="; grep -a "boot2\|fldreloc2" run.log.d run.log 2>/dev/null | head -12
echo "=MODTRACE="; grep -a "modtrace\|fldcap2\|stage2:\|fldreloc2" run.log.d run.log 2>/dev/null | head -22
echo "=DESKDIAL="; grep -a "deskdial\|healwalk\|rectguard" run.log.d 2>/dev/null | head -12  # R698: the dial moment + heap-chain heal
echo "=MOUNTWALK="; grep -a "R648\|R651\|R655\|R664\|R669\|R650 mount\|R660\|R692\|R693" run.log.d 2>/dev/null | head -14  # R697: the post-install walk, front-loaded (c268 lost it to the mid-cut)
echo "=LOOPW="; grep "\[loopw\]" run.log | head -20  # R677: 28088 write-watcher (exitdiag mystery cell)
echo "=DESCW2="; grep "\[descw2\]" run.log 2>/dev/null | head -20  # R689: queue-cell write watcher MOVED TO FRONT - c260 mid-digest cut blinded it (lesson c243)
echo "=PHASE="; grep "\[phase\]" run.log.d | head -24  # R673: moved to digest FRONT (after =TICK=) - c243 proved the head-48KB cut lands inside =PHASE= when it sits late; boot-era walker-exit noise now gated in runtime
# R841: F5DOOR/F5DUMP/EXITTAIL/MACREPORT moved to digest FRONT (after =PHASE=) - c424/425/426
# proved the head+tail cap eats these small high-value sections when they sit late
echo "=F5DOOR="; grep "\[f5fix\]" run.log run.log.d 2>/dev/null | head -12
echo "=F5DUMP="; grep "\[f5dump\]" f5dump.log 2>/dev/null | head -8
echo "=EXITTAIL="; echo "--- run.log last 96 ---"; tail -96 run.log 2>/dev/null
echo "=MACREPORT="; grep "\[macreport\]" run.log run.log.d 2>/dev/null | head -20
echo "=CBCALL="  # R606: moved to digest FRONT — c172/c173 head-cap cut the callback receipts twice
grep -a "cbcall\]" run.log.d | head -40
echo "=ADV599="; grep -aE "adv599\]|re-anchor|R607 load-time" run.log.d | head -20
echo "=ASSISTS="; grep -a "f15stream\]\|f15cont\]\|f14inst\]\|f14node\]" run.log.d | head -12
echo "=MNTACC-F="; grep -a "mntacc\]" run.log.d | head -24
echo "=ENDREL="; grep -a "exitdiag\|R630 tick-cadence\|R631 posture\|R633 mountresult\|R633 mountcell\|R633 stamp-skip\|R634 dragback\|R637 mountcount\|R640 STATE-1\|R639 exitflag\|R636 park window\|R632 mountlatch\|mtrans\|endgame release\|R613 event post\|walk frontier\|WRAP DETECTED\|mountlatch\|STALL WATCH\|STALL2\|ALARM STARVED\|INSTALLRESET\|paentry\|RESUMEFIX\|install-done release" run.log.d | tail -80
echo "=PARKCEN=" && grep -a "R636 park window" run.log.d | head -3; echo "=TRAIL="; grep -a "\[trail\]" run.log.d | head -40
echo "=COUNTS=" && r610release=$(grep -ac "R610 endgame release" run.log.d); echo "cbcall_total=$(grep -ac "cbcall\]" run.log.d) f15serve_total=$(grep -ac "f15stream\]" run.log.d) r607assert_total=$(grep -ac "R607 load-time" run.log.d) rsdump_total=$(grep -ac "rsdump\]" run.log.d) fdconv_total=$(grep -ac "fd-tick" run.log.d) spinconv=$(grep -ac "spin-conv" run.log.d) r612release=$(grep -ac "R612 endgame release" run.log.d) r613post=$(grep -ac "R613 event post" run.log.d) walkfrontier=$(grep -a "R617 walk frontier" run.log.d | tail -1) descw2_writes=$(grep -ac "descw2\]" run.log.d)"
echo "=CBCALL-T="  # R608: END of the callback trajectory
grep -a "cbcall\]" run.log.d | tail -30
echo "=MNTACC-T="  # R608: END of the mount-era trajectory
grep -a "mntacc\]" run.log.d | tail -24
echo "=STEPPER-T="  # R608: END of the queue walk
grep -a "stepper\]" run.log.d | tail -24
echo "=RSW-T="  # R608: END of the read-struct state
grep -a "rsdump" run.log.d | tail -12
echo "=STEPPER-F="; grep -a "stepper\]" run.log.d | head -40
echo "=L0TAB="; grep "\[l0tab\]\|\[hook\] 0x8004FDF8" run.log.d | head -48  # R513: directory-request length cells + member-1 raw entry (R514: moved to head — c81 digest cap buried it mid-report)
echo "=SMTR="; echo "-- R323 churn trampoline (bounces = recursion collapsed at thread base) --"; grep "\[smtr\]" run.log | head -12; grep "\[depth\]" run.log | tail -4; echo "-- R325 countdown timeline (skip countdown 77014 transitions) --"; grep "\[cntdn\]" run.log | head -16; echo "-- R327 assist verdict --"; grep "\[rdcomp\]" run.log; echo "-- cd-dma activity (tail = latest) --"; grep "\[cd-dma\]" run.log | tail -12; echo "-- R328 sector-fetch (tail = latest) --"; grep "\[dmaarm\]" run.log | tail -8; echo "-- R329 state-7 seek-issuer (head) --"; grep "\[sm7\]" run.log | head -6; echo "-- assist verdicts --"; grep -e "\[rdcomp\]" -e "\[seek7\]" run.log; echo "-- assist refire counts --"; echo "rdcomp=$(grep -c "\[rdcomp\]" run.log) seek7=$(grep -c "\[seek7\]" run.log) seek7x=$(grep -c "\[seek7x\]" run.log)"; echo "-- R332 counter writers (hook tail) --"; echo "-- R333 watcher: FE1C (tail) --"; grep "\[hook\] 0x8004FE1C" run.log | tail -12; echo "-- R333 watcher: counters (tail) --"; grep "\[hook\] 0x8006A4" run.log | tail -12; echo "-- R333 watcher: FE20 (tail) --"; grep "\[hook\] 0x8004FE20" run.log | tail -4; echo "-- sm7 sampled entries (tail) --"; grep "\[sm7\]" run.log | tail -8; echo "-- NEW movie-era dma (tail) --"; grep "\[cd-dma\]" run.log | tail -12; echo "=HOT="; echo "-- state-11 dispatcher (never runs? watch here) --"; grep "\[sm11\]" run.log | tail -12; echo "-- answer pops after restore --"; grep "\[rspop\]" run.log | head -24; echo "-- vsync heartbeat --"; grep "\[vsync\]" run.log | head -4; grep "\[vsync\]" run.log | tail -2; echo "-- stress ring --"; grep "\[stress\]" run.log | tail -6; echo "-- toc routing --"; grep "TOC-ROUTE\|TOC-RESTORE" run.log | tail -6; echo "-- cdf tail --"; grep "\[cdf\]" run.log | tail -6
echo "=F15W="
grep -a -E "\[hook\] 0x8004FE08|\[hook\] 0x80059F10|\[hook\] 0x80059F0C" run.log | tail -40
grep -a "f14inst" run.log | head -10
grep -a "\[hook\] 0x80059F0C" run.log | tail -12
echo "=GATEW="
echo "=MNTACC="
grep -a "f14inst\|mntacc" run.log | head -45
echo "=RSW="
grep -a "rsdump" run.log | head -14
echo "-- stuck era (tail) --"
grep -a "rsdump" run.log | tail -26
grep -a "\[hook\] 0x80064AC" run.log | head -30
echo "=BRK="; grep "\[brk\]" run.log.d | head -14
echo "=FLDBELL="; grep "\[fldbell\]" run.log.d | head -20; echo "=CBHEAL="; grep "\[cbheal\]" run.log.d | head -20; echo "=CBW="; grep "\[hook\] 0x80059F08" run.log.d | head -20; echo "=CBDMA="; grep "\[cbdma\]" run.log.d | head -20
echo "=LATCHW="; grep -E "\[latchw\]|\[latchfix\]|\[latch\]|0x80059330" run.log.d | head -24  # R502: latch cell timeline (verdict branch evidence)
echo "=BOOT="; grep "\[boot\]" run.log.d | head -10
echo "=DEC="; grep "\[dec\]" run.log.d | head -6
grep "\[dec\]" run.log.d | tail -8
echo "=REFDEC="  # R175: reference LZSS decode w/ CORRECT pairings.
# Cycle-10 lesson: overlay_dump_2 (verdict-time) = POST-INSTALL TRANSFORM, not raw
# decompress output -> that "DIVERGENCE" was apples-to-oranges. The RAW round-1
# outputs for streams 0/1 = overlay_dump_0/1 (16KB @0x801FC000, 22988B @0x801FA634),
# captured at ROUND-2 decompress entry = AFTER round-1 wrote them.
D0=6594; D1=22988
for idx in 0 1; do
  inp="dec_input_${idx}.bin"; dump="overlay_dump_${idx}.bin"
  if [ -f "$inp" ] && [ -f "$dump" ]; then
    if [ "$idx" = "0" ]; then n=$D0; else n=$D1; fi
    if python3 lzss_ref.py "$inp" >/dev/null 2>&1 && [ -f "${inp%.bin}.refout" ]; then
      if cmp -s <(head -c "$n" "${inp%.bin}.refout") <(head -c "$n" "$dump"); then
        echo "stream $idx: MATCH ($n bytes) — raw decompress output == reference"
      else
        echo "stream $idx: DIVERGENCE — first diff:"
        cmp <(head -c "$n" "${inp%.bin}.refout") <(head -c "$n" "$dump") | head -1
      fi
      echo "  ref   [0:16]: $(xxd -p -l 16 ${inp%.bin}.refout)"
      echo "  live  [0:16]: $(xxd -p -l 16 $dump)"
    else
      echo "stream $idx: reference decode FAILED"
    fi
  else
    echo "stream $idx: missing $inp or $dump"
  fi
done
# stream 2: reference decode + INFO-ONLY dump2 view (post-install transform caveat)
if [ -f dec_input_2.bin ]; then
  python3 lzss_ref.py dec_input_2.bin 2>&1 | head -1
  echo "verdict block [0:16]: $(xxd -p -l 16 overlay_dump_2.bin 2>/dev/null)"
fi
echo "=INS="; grep "\[ins\]" run.log.d | tail -20
echo "=ADV="; grep "\[adv\]" run.log.d | tail -24
echo "=OVL="; grep "\[ovl\]" run.log.d | head -4
echo "=BOOTMAIN="; grep "\[bootmain\]" run.log.d | tail -6
echo "=OVL2="; grep -E "\[ovlcb\]|\[ovlread\]" run.log.d | head -8
echo "=CD2="; grep "converting stuck" run.log.d | tail -10
echo "=CD3="; grep "re-primed\|FIELD-SEEK\|cdw02\|Setloc BCD" run.log.d | head -6
echo "=CD5="; grep "FIELD-SEEK\|FIELD-READ\|cdw02\|Setloc BCD\|mv-conv\|INT1 armed" run.log.d | tail -24
echo "=PK="; echo "=MOUNTW="; grep "mountw\]" run.log.d | head -30; echo "=MTRANS="; grep "mtrans\]" run.log.d | head -6; echo "=FLDCB="; grep "stepper\]" run.log.d | head -40; echo "=STEPPER="; grep "fldcb\]" run.log.d | head -24; echo "=STATEW="; grep -E "\[hook\] 0x800692(C0|BC|D0|C8)|\[hook\] 0x80028088|\[hook\] 0x8006FAEC" run.log.d | head -28; echo "=F15STREAM="; grep "f15stream\]" run.log.d | head -12; echo "=CBCALL-DUP="; grep "cbcall\]" run.log.d | tail -12; echo "=ADV599-DUP="; grep -E "adv599\]|re-anchor" run.log.d | tail -8; echo "=F15CONT="; grep "f15cont\]" run.log.d | tail -6; echo "=STEPPER="; grep "stepper\]" run.log.d | head -40; echo "=R598ADV="; grep "R598 ReadS" run.log.d | tail -6; echo "=F14NODE="; grep "f14node\]" run.log.d | head -4; grep "\[park\] cd:\|\[park\] cells:" run.log.d | tail -12
echo "=FLDD="; grep "fld-data" run.log.d | tail -64
echo "=FLDH="; grep "fld-hot" run.log.d | tail -16
echo "=FRC="; grep "\[frc\]\|forced data-ready INT1" run.log.d | tail -20
echo "=FLDI="; grep "fld-int1" run.log.d | tail -24
echo "=FLD2SIG="; grep "fld2sig" run.log.d | tail -50
echo "=FLDFRZ2="; grep "\[fldfrz2\]" run.log run.log.d 2>/dev/null | head -10
echo "=FLDFRZ="; grep "fldfrz\]" run.log.d | tail -12; echo "=FLDFRZ2="; grep "fldfrz2" run.log.d | tail -8  # R514: 80 lines/era starved the mid-digest sections
echo "=FLDFIN="; grep "fldfin" run.log.d | head -6
echo "=LIFTCTL="; grep "liftctl" run.log.d | head -20
echo "=FLDFIN3="; grep "fldfin3" run.log.d | head -4
echo "=FLDBELL2="; grep "fldbell2" run.log.d | head -8  # R542 end-of-read doorbell fires
echo "=FLDBELL3="; grep "fldbell3" run.log.d | head -10  # R544 self-priming doorbell fires
echo "=FLDBELL4="; grep "fldbell4" run.log.d | head -10  # R545 posture bell (own line — Lesson 44)
echo "=F14PUMP="
echo "=ACKCAM="; grep -a -E "ackcam|f14land" run.log | tail -40
grep -a "f14pump" run.log | tail -80
echo "=F15PUMP="
echo "=F15TRACE="
grep -a "f15trace" run.log | tail -40
echo "=F15T2="
grep -a "f15pump" run.log | tail -60
echo "=STREAMCB="
grep -a "streamcb\|cbtab dump" run.log | head -30
echo "=FE34FIX="; grep "fe34fix" run.log.d | head -12  # R549 copy-path unblock (own line)
echo "=DIRLOOP="; grep "dirloop" run.log.d | head -24  # R547 dir-read consumer arguments
echo "=SM10="; grep "sm10" run.log.d | head -12  # R544 state-10 handler entry receipts  # R539 whole-file driver-completion verdict
echo "=DEFIB="; grep -E "defib" run.log.d | tail -40; echo "=WDSHEAL="; grep "\[wdsheal\]" run.log.d | head -8; echo "=FRONTW="; grep -E "frontw|frontfix|frontguard" run.log.d | head -20
echo "=SKIPGATE="
grep -E "skipgate" run.log.d | head -40
echo "=STGW="; grep "\[hook\] 0x800AFC98" run.log.d | head -40
echo "=FLDPUMP="; grep "fldpump" run.log.d | tail -20
echo "=FLDR="; grep "fld-rearm" run.log.d | tail -24
echo "=CD6="; grep "INT3 delivered\|poll-release near-miss\|field-poll\|FE1C RAM-poll" run.log.d | head -40
echo "=CD4="; grep "Pause complete\|converting stuck" run.log.d | tail -10; echo "=KICK="; grep "\[cd\] fd-kick" run.log.d | tail -10; echo "=ZRF="; grep "\[zrf\]" run.log.d | head -12; echo "=STRSCAN="; grep "\[strscan\]" run.log.d | head -12; echo "=STRSEC="; grep "\[strsec\]" run.log.d | head -12; echo "=STRMAP="; grep "\[strmap\]" run.log.d | head -12; echo "=FE04W="; grep "\[hook\] 0x8004FE04" run.log.d | head -16; echo "=FE04T="; grep "\[hook\] 0x8004FE04" run.log.d | tail -16; echo "=FESEED="; grep "\[feseed\]" run.log.d | head -12; echo "=ZSR="; grep "\[zsr\]" run.log.d | head -12; echo "=PADIN="; grep "\[padin\]" run.log.d | head -8; echo "=CFGPTR="; grep -E "finfree" run.log.d | head -8; grep "\[cfgptr\]\|\[mvfin\]" run.log.d | head -32; echo "=TOCR="; grep "TOC-ROUTE" run.log.d | head -8; echo "=TOCR="; grep "TOC-RESTORE" run.log.d | head -4; echo "=H4="; grep -E "\[h4\]|TOC-RESTORE" run.log.d | head -4; echo "=SMFC="; grep "\[smfc\]" run.log.d | head -24; echo "=STRESS="; grep "\[stress\]" run.log.d | tail -6
echo "=WDSDIFF="; grep "\[wdsdiff\]" run.log.d | head -40; echo "=WDROP="; echo "=MANGLE="; grep "\[mangleguard\]" run.log.d | head -24  # R517: 0x03-mangle store drops - expect the irq-chain + kernel-cell writes dropped, recovery survives grep "\[wdrop\]" run.log.d | head -12; echo "=NEWMOD="; grep -E "\[newmod\]|\[bigread\]" run.log.d | head -12; echo "=TRAP3="; grep "\[trap3\]" run.log.d | head -12; echo "=SUB="; grep "\[sub\]" run.log.d | head -8; echo "=BATFIN="; grep "\[batfin\]" run.log.d | head -6; echo "=ABRT="; grep "\[abrt\]\|\[sndfree\]\|NULL-trap" run.log.d | head -16; echo "=FSMHIST="; grep -E "\[hook\] 0x8004FE(1C|20|38)|\[hook\] 0x80059F(24|28|2C)|\[hook\] 0x80077014" run.log.d | tail -16; 
echo "=BINCHK="; python3 - "$BIN" <<'PYX'
import sys,struct
f=open(sys.argv[1],'rb')
def sec(lba):
    f.seek(lba*2352+24); return struct.unpack('<4I', f.read(16))
for lba in (108561,108599,108605):
    w=sec(lba)
    print('[binchk] LBA %d data[0:16] %s' % (lba,' '.join('%08X'%x for x in w)))
PYX
echo "=FTAB="; grep "\[ftab\]" run.log.d | head -20
echo "=STAB="; grep "\[stab\]" run.log.d | head -40
echo "=CHAIN="; grep "\[chain\]\|\[gtab\] idx-cell\|\[mount\] MountGameState\|\[restart\]" run.log.d | head -40
echo "=ARC="; grep "\[arc\]" run.log.d | head -8
echo "=SMROUTE="; grep -E "\[sm" run.log.d | head -40; echo "[lad2] summary:"; grep -c "\[lad2\] ladder-completion" run.log.d; grep "\[lad2\] ladder-cmd response SKIPPED" run.log.d | sort | uniq -c | head -8; grep "\[lad2\] ladder-completion" run.log.d | tail -3; echo "=SLOT="; grep "\[slot\]" run.log.d | head -16; echo "[slot] tail:"; grep "\[slot\]" run.log.d | tail -8
echo "=GATE="; grep "bpad\]\|bxcep\]\|rcntc\]" run.log.d | head -20;
echo "=PARK="; grep "park\]\|rcnt\]\|pump\]" run.log.d | head -30; echo "=MOVIE="; grep "movie\]" run.log.d | head -20; echo "=MOD6="; grep "MODULE 6 ENTRY REACHED" run.log.d | head -6; echo "=PHASECB="; grep "phasecb\]" run.log.d | head -12; echo "=MVLOOP="; grep "mvloop\]" run.log.d | head -20
echo "=GSTATE="; grep "gstate\]" run.log.d | head -20
echo "=GDISP="; grep "gdisp\]\|\[gtab\]\|\[restart\]\|\[mount\]" run.log.d | head -32
echo "=GTE="; grep "\[gte\]" run.log.d | head -8
echo "=NEWREAD="; grep "\[newread\]" run.log.d | head -8
echo "=CTX="; grep "NEW CONTEXT" run.log.d | head -8
echo "=SPURAM="; grep "\[hle-spu\] ram snapshot" run.log.d | head -4; ls -la spu_ram.bin 2>/dev/null
echo "=SPUDMA="; grep "\[spu-dma\]" run.log.d | head -8
echo "=ADPCM="; python3 spu_adpcm_scan.py spu_ram.bin 2>/dev/null | head -24 || echo "scan unavailable"
echo "=HLE="; grep "\[hle" run.log.d | head -8
echo "=GPU="; grep "\[gpu\]" run.log.d | head -8; echo "prims-log-lines: $(grep -c "gpuprim\]" run.log.d) render-defers: $(grep -c "render alive" run.log.d)"; grep "gpuprim\]\|render alive" run.log.d | head -10
echo "=VIEW= live viewer status:"; cat xenoview_status 2>/dev/null || echo "not launched this run"
echo "=GPU="; grep -a "\[gpu\]\|\[dma\] GPU" run.log.d 2>/dev/null | head -14
if [ -f vram.bin ]; then python3 vramtopng.py 2>&1 | head -2; ls -la screen.png vram.png 2>/dev/null | awk '{print $NF, $5" bytes"}'; fi
echo "=STATEFREQ="; grep "0x80059340:" run.log.d | awk "{print \$5}" | sort | uniq -c | sort -rn | head -12
echo "=DISP2="; grep "\[disp2\]" run.log.d | head -4
echo "=ERR="; grep "\[err\]\|\[fatal\]" run.log.d | head -4
echo "=STACKCLOB="  # R187: dedicated section — the clobberer must never hide
grep "\[hook\] 0x801FFF" run.log.d | head -24
echo "=CELL="; grep "\[hook\]" run.log.d | head -24
 echo "=ALLOC="; echo "alloc count: $(grep -c '\[alloc\]' run.log)"; grep "\[alloc\]" run.log.d | head -10; grep "\[alloc\]" run.log | tail -6
 echo "=CLEAR="; grep "\[clear\]" run.log.d | head -16
echo "=FL="; grep "\[fl\]" run.log.d | head -16
echo "=ENQ="; grep "\[enq\]\|\[deq\]\|\[irqc\]" run.log.d | head -14
echo "=LATCH="; grep "\[latch\]\|\[pad\]" run.log.d | head -4
echo "=TOC="; grep -E "\[cd\] (GetTN|GetTD|Getloc|GetID)" run.log.d | head -12; echo "=CDF="; grep "\[cdf\]" run.log.d | head -8; grep "\[cdf\]" run.log.d | tail -4; echo "=FLOOD= (last 200KB of log, line shapes)"; tail -c 200000 run.log.d | cut -c1-40 | sed -E "s/0x[0-9A-Fa-f]+/0xN/g; s/[0-9]+/N/g" | sort | uniq -c | sort -rn | head -8; echo "=CD="; grep "\[cd\]" run.log.d | grep -v "forced data-ready\|interrupt acknowledged" | tail -28
echo "=TICK="; echo "fd-ticks: $(grep -c "fd-collector tick" run.log) wl-ticks: $(grep -c "wait-loop tick" run.log) reads-done: $(grep -c "read complete" run.log) pairs: $(grep -c "pair dispatch" run.log) forces: $(grep -c "forced data-ready" run.log) convs-used: $(grep -c "converting stuck INT1" run.log) reprimes-used: $(grep -c "re-primed response FIFO" run.log) kicks-used: $(grep -c "fd-kick: queued request" run.log)"
echo "=DMA="; grep -E "GPU LIST DMA2|GPU DMA2|MDEC-(IN|OUT) DMA" run.log.d | head -12; grep "\[dma\]\|\[cd-dma\]\|\[enqstruct\]" run.log.d | tail -16
echo "=EVT="; grep "\[evt\]" run.log.d | grep -v heartbeat | tail -24
echo "=WD="; grep "\[wd\]\|\[halt\]" run.log | tail -20
echo "=CDSTATE="; grep "\[cdstate\]" run.log
echo "=DISP="; grep "\[dispstep\]" run.log.d | head -6
echo "=LOAD="; grep "FileOpen\|\[cd\] open\|\[file\]" run.log.d | head -8
echo "=TASK="; grep "\[task\] enter" run.log.d | tail -8
echo "=BM="; grep "\[bm\]" run.log.d | head -8
echo "=HAND="; grep "\[hand" run.log.d | head -24; echo "=SPFIX="; grep "\[sp-fix\]" run.log.d | head -10
echo "=TAKE="; grep "\[take\]" run.log.d | head -12
grep "\[coal\]" run.log.d | head -12
echo "=WALK="; grep "\[walk\]" run.log.d | head -40
echo "=RELOC="
grep -E "\[reloc(-fix)?\]" run.log.d | head -16
grep -E "\[lzss(-inpast)?" run.log.d | head -30
echo "=FAULTREGS="
grep "faultregs" run.log.d | head -2
echo "=FKFD="
grep -E "fkfd|fkstg|fkstk" run.log.d | tail -8
echo "=STGZERO="
grep "stg-zero" run.log.d | head -4
echo "=FKCTX="
grep "fkctx" run.log.d | tail -4
echo "=FONTBT="; grep "\[fontbt\]" run.log.d | tail -48  # R429: budget 24->48 + TAIL (first journey proven healthy c186; last journeys decide)
echo "=FKUNLD="; grep "\[fkunld\]" run.log.d | head -8
echo "=CTXW="; grep "\[ctxw\]" run.log.d | head -8  # R430: true write-level hook on the ctx cell
echo "=CTXB="; grep "\[ctxb\]" run.log.d | head -24  # R433: byte/half writers to the ctx cell + full write context (t, r31, r16)  # R429: who calls the font-ctx unloader (fn_80037494) + cell state
echo "=MIDW="; grep "\[midw\]" run.log.d | head -8  # R434: middle-block tripwires (ctx-struct +0x47/+0x4B/+0x4C stores) - bisects the skip: fire => middle runs (skip is later); silent => skip at the 80043E20 call return (callee exit suspect)
echo "=BTW="; grep "\[btw\]" run.log.d | head -8  # R436: batch-ptr field (ctx+0x38) writers — the faulting load reads this; if nobody ever writes it, the crash reads uninit garbage
echo "=CARVE2="; grep "\[carve2\]" run.log.d | head -40
echo "=DESCW="; grep "\[descw\]" run.log.d | head -40  # R687 kept

echo "=REQSW="; grep "\[reqsw\]" run.log.d | head -24
echo "=RINGW="; grep "\[ringw\]" run.log.d | head -96  # R442: fill-ring target cell (FE08/FE0C/FE10) writers - the seed store lives here
echo "=REQRES="; grep "\[reqres\]" run.log.d | head -40  # R442: request slot cells (59F10/F14/F18) receiving in-RAM values - the carve result store  # R441: heap descriptor (free-ptr 0x8006FAF0 + flags 0x8006FAF4) writers — the missing advance-store lives here  # R440: double-book audit - node header + heap descriptor at every take inside the record span [801EF558,801F34B4)
echo "=BTW2="; grep "\[btw\]" run.log.d | tail -16  # R439: fault-era batch resets (btw budget raised 8->24)
echo "=FRCLASH="; grep "\[frclash\]" run.log.d | head -12  # R437: font-record page guard - WHO writes the record after boot (ring overlap suspect)
echo "=ROOTW="; grep "\[rootw\]" run.log.d | head -20  # R439: alloc root-node (0x801FBFF8/FC) writers - silent = carve store-back never fires = stale-root double-allocation proven
echo "=RECDUMP="; grep "\[recdump\]" run.log.d | head -10  # R438: full font-record hexdump at fault - garbage pattern names the stomper
echo "=DECHIST="; grep "\[dechist\]" run.log.d | head -16  # R438: decompression destination sequence - streams shifted one slot vs reference (heap drift suspect)
echo "=EMW="
grep -E "\[hook\] (0x80050594|0x80059394)" run.log.d | head -48
echo "=FKHBT="
echo "fault-kit blocks: $(grep -c "guest-fault host backtrace" run.log.d)"
grep -A26 "fkhbt\] fault#" run.log.d | tail -30
echo "=TAIL="; awk '/HALT/{f=1} f' run.log | head -60
echo "=DONE="
echo "=POSTRES="; grep "\[postres\]\|\[unpack\] MODULE" run.log.d | head -30
echo "=STAGE2="; grep "\[stage2\]" run.log.d | head -12; echo "=CRASH="; grep -E "\[crash\]|\[halt-scan\]" run.log.d | head -40; ls -la stage2_region.bin 2>/dev/null
echo "=PRECRASH="  # R483: the 40 log lines immediately before the host died - what was running
CL=$(grep -n "\[crash\] host_pc" run.log.d | head -1 | cut -d: -f1)
if [ -n "$CL" ] && [ "$CL" -gt 40 ]; then sed -n "$((CL-40)),$((CL-1))p" run.log.d
elif [ -n "$CL" ]; then sed -n "1,$((CL-1))p" run.log.d
else tail -40 run.log.d; fi
echo "=CRASHDUP="; true
echo "=DRVPTR="; grep "\[drvptr\]" run.log.d | head -10
echo "=CBREG="; grep "\[cbreg\]" run.log.d | head -12
echo "=ARMST="; grep "\[armst\]" run.log.d | head -8
echo "=FLDCON="; grep "\[fldcon\]" run.log.d | head -24
echo "=FLDRING="; grep "\[fldring\]" run.log.d | head -24
echo "=FLDHALT="; grep "field-stream alive" run.log.d | head -16
echo "=FLD="; awk '/FIELD ERA START/,0' run.log.d | grep -E "\[fld\]|\[arc\]|\[ftab\]|\[ovlread\]|\[newmod\]|\[stab\]|\[seed\]|\[cd-dma\]|\[dmaarm\]|\[sm6\]|\[sm11\]|\[bigread\]|\[task\] kick|\[rdcomp\]|\[seed\]|\[fldret\]|\[fldseed\]|\[arccb\]|\[arcadv\]|\[cbreg\]|\[armst\]|\[fldcon\]|\[fldring\]|\[fldhdr\]|\[fldfin\]" | head -70; echo "-- zrf summary --"; awk '/FIELD ERA START/,0' run.log.d | grep -c "\[zrf\]"; awk '/FIELD ERA START/,0' run.log.d | grep "\[zrf\]" | sort | uniq -c | sort -rn | head -6; echo "(field-era lines: $(awk '/FIELD ERA START/,0' run.log.d | wc -l) total)"
echo "=CTPX="; grep "ctxphoenix\|glyphguard" run.log.d | head -12  # R520 glyph-fault verdict zone
echo "=ZRFM="; grep "zrfm" run.log.d | head -66
echo "=CMDTL="; grep "cmdtl" run.log.d | head -84; echo "=DIRACK="; grep "dirack" run.log.d | head -16; echo "-- rspop latest --"; grep "rspop" run.log.d | tail -10  # R527 doorbell family verdicts (dirack first, boot-flood fixed via tail)
 echo "=PH2="; grep "\[ph2\]" run.log.d | head -8; echo "=MODSRC="  # R426 diet: window capped (static code, was 308 lines = 25KB)
python3 - <<'XEOF' || echo "[modsrc] extraction failed (see traceback above - R369: never suppress python stderr)"
import re
s=open('disc1.c').read()
lines=s.split('\n')
lab={}
for j,ln in enumerate(lines):
    m=re.match(r'(L_[0-9A-F]{8}):;',ln.strip())
    if m: lab.setdefault(m.group(1),j)
sites=[]
# R344: WINDOW MODE — L_8007670C (the 77014 countdown decrementer, stuck at 1 during movie era) and
# L_800769A4 (MoviePollSkipInput — the eternal poll loop) live INSIDE giant parent functions whose
# function-mode dump truncates at 420 lines BEFORE reaching these labels (cycle-92 lesson: the code
# was captured but never read). Windows start 12 lines before each label.
windows=[('L_8002A394',90),('L_8002B0AC',90),('L_8002B084',110),('L_8002B168',110),('L_8002B2E0',60),('L_8002B2F0',90),('L_8002B19C',60),('L_8002B1D4',60),('L_8002A68C',41),('L_8002AAF0',60),('L_8002AB28',60),('L_80041CA0',60),('L_80031DA8',41),('L_80019ACC',110),('L_80019B40',41),('L_80019F74',41)]  # R501: c67 decode: loop body DECODED HEALTHY - 80019B0C: r2=reqstate(0x80028088)<<4 + 0x8002808C -> ReinitializeGpu(config-ptr) (DISPENV table!), SetDrawCompletionCallback(0), SetControllerUpdateCallback(0) - the 8088 cell is a display-config selector, NOT a gate. AbortOnGameFault body: WriteHeapSnapshot + EraseVramRectangle (0x280 wide) = the game's crash screen. The fault verdict comes from the WALKER region: L_80031DC4 calls the main loop with HARDCODED r4=0x82 right after fn_80031F58 advance - need the branch that routes to 0x80031DC0 vs the other done-path fn_80031DA8. Windows: L_80031D90/L_80031DA8 = walker verdict branch region, L_80019B28/B40 = healthy loop continuation (subsystem dispatch conditions), L_80019F74 = crash-screen continuation.  # R500: c66 decode: L_80031DC4 proves r4=0x82(130) is a HARDCODED NORMAL mode arg to RunResidentGameLoop - NOT a fault verdict. Loop starts healthy, reads req-state cell 0x80028088 (=0 at park), and aborts BEFORE subsystem 0 (RunKernelMenu never ran - =PH2= empty). The abort branch = instructions right after L_80019B00's LW(0x80028088), exactly where the 41-line window diet cut us off. R500 windows step PAST the cut: L_80019B08/B10/B1C = the branch that calls AbortOnGameFault + the cell conditions; L_80019F48 = AbortOnGameFault continuation (post-heap-snapshot - where does the game park); L_8001A250 kept (menu launcher, decoded head, tail still useful).  # R499: c65 decode REWRITES the model: fn_80019ACC=RunResidentGameLoop (game core main loop, 8-subsystem table [0]=RunKernelMenu 0x8001A4B4 = DEV MENU - not a phase cb), fn_80019EF8=AbortOnGameFault itself (r4=130 code), 0x80019AF8 = loop's req-state(0x80028088) helper. The loop was ENTERED with r4=130 FROM the walker done-hook fn_80031DC8 and AbortOnGameFault(130) is the loop faithfully reporting a boot-side fault verdict. Decode the verdict: L_80031DC8 = the hook that computes/calls with the code, L_80019AE0 = loop's r4!=0 path (where abort gets invoked), L_80019F20 = AbortOnGameFault body after 0x80010000 read, L_8001A250 = LaunchKernelMenu (what the menu needs to run). Drop decoded: 19EF8/19AF8/31C80/2B084/390A0/381F4.  # R498: c64 - file 7 PRE-SHELVED (data on shelf 0x800B0704) yet phase cb 0x8001A4B4 STILL aborts(130) @0x80019AF8 with identical ctx => the cb's check is NOT data-at-dest; decode the phase trio: L_8001A4B4 = phase-0 cb (what it checks), L_80019EF8 = cb runner (args), L_80019ACC = phase engine head, L_80019AF8 = abort decision site; kept: porter L_8002B084, uploader math L_800390A0/381F4, advancer L_80031C80  # R481: c45 receipts prove carry works (files 4+5 delivered, dest math exact) yet fault BYTE-IDENTICAL to empty-buffer cycles => r17=0xDF000011 is NOT file data; it comes from the constant setup chain (8003BDBC->800404D4->800404E4->80039024->800404B4->80039044). New windows: L_80039024 = setup arming r17, L_800390C8 = uploader tail where the wild OR happens (fault at fn_80039044+275)  # R480: c44 same fault; sound heap nearly exhausted ([clear] alloc RESULT 0x8006BD00, limit 0x8006BE00) + bank1 OK bank2 fault => suspect AllocateWdsSpuMemory (fn_800381F4) failing/full for bank 2 and the 0xDF000011 r17 being an alloc-error value, not stale data; windows: L_800390A0 = faulting store tail (fn_80039044+275 backtrace site), L_800381F4 = AllocateWdsSpuMemory head; carry receipt log added so porter-carry verdict is visible  # R478 decode set: c42 fault = store to 0x8006BDD0|0x21000000 inside the WDS sound-bank upload (fn_80039044 via LoadAndRegisterWdsBank fn_80037FD8, banks parsed from file-5 buffer 0x800AA6B0) — likely my rescue faked FDF8 but the game's ring->buffer copy (walker fn_8002B168 / collector fn_8002B084) never ran, leaving stale bank data; windows decode the upload math + the copy path  # R441: advance-fn continuation (fall-through path: what the advance DOES with a used node — the missing descriptor-store is in here) + type-0 path; L_80031C58/L_80031FF8 heads fully read c199  # R440: carve-advance + carve-request photos — need the node-field semantics (which w-bit marks in-use) for the surgical record-reserve fix; L_800377F8 window fully read c191-c195 (straight-line stores confirmed)  # R432: THE LAST UNPHOTOGRAPHED GAP - c188 window covered L_80037814+ (tail: install store present, straight-line), c189 window covered L_800377C0-95024 (SB stores, straight-line) - BOTH TRUNCATED BEFORE/RESUME AFTER L_800377F8..L_80037814; the Mac's file diverged from the sandbox copy (~1590 lines) so the sandbox version of this gap (plain stores) is UNVERIFIED; if the Mac's gap holds a conditional branch (suspect: external-font-storage gate around the install store) this window catches it; stale windows removed (L_8001A34C + L_8003782C fully read)
printed=set()
total=0
for st in sites:
    if st not in lab:
        print('[modsrc]',st,'NOT in disc1.c (module window not compiled here)')
        continue
    j=lab[st]
    fs=j
    while fs>0 and not lines[fs].startswith('static void'):
        fs-=1
    if fs in printed: continue
    printed.add(fs)
    fe=j
    while fe<len(lines)-1 and not lines[fe+1].startswith('static void'):
        fe+=1
    body=[ln for ln in lines[fs:fe] if ln.strip() and 'XTRACE' not in ln and ln.strip()!='{' and ln.strip()!='}']
    if len(body)>420:
        body=body[:420]+['... TRUNCATED']
    txt='\n'.join(body)
    print('### %s (%d lines) ###'%(st,len(body)))
    print(txt)
    total+=len(txt)
    if total>26000:
        print('[modsrc] budget stop')
        break
for wst in windows:
    st,wn=wst
    if st not in lab:
        print('[modsrc]',st,'NOT in disc1.c')
        continue
    j=lab[st]
    ws=max(0,j-12); we=min(len(lines),j+wn)
    body=[ln for ln in lines[ws:we] if ln.strip() and 'XTRACE' not in ln]
    if len(body)>40:
        body=body[:40]+['... WINDOW TRUNCATED (R426 digest diet - static code, window fully shipped+read c179-c183)']
    print('### WINDOW %s (@line %d, %d lines) ###'%(st,j,len(body)))
    print('\n'.join(body))
    total+=len(body)
    if total>6000:
        print('[modsrc] budget stop')
        break
print('[modsrc] done:',len(printed),'sections,',total,'chars')
XEOF

echo "=FVP="; grep "\[fvp\]" run.log | head -6  # R375: emit/d37c greps dropped (glyph stream fully decoded)
echo "=MPAD="; grep "\[mpad\]\|\[padin\]" run.log | head -12
echo "=MINPUT="; grep "\[minput\]" run.log | head -20
echo "=RCB="; grep "\[rcb\]" run.log | head -24
echo "=SNDREBOOT="; grep -a "sndreboot" run.log run.log.d 2>/dev/null | head -6
echo "=SPGUARD="; grep -E "\[spguard\]|\[task\]|\[sp-fix\]" run.log.d | head -12
echo "=WILDCODE="; grep -a "wildcode\|wildscan\|wildhdr\|f15w0\|fldreloc2" run.log run.log.d 2>/dev/null | head -30
echo "=WILDCTX="; grep "\[wildctx\]\|RESTART\|ovlfault\|fault-capture\|coordb\|coordb2\|coordb3\|lzss-hle\|fldcap\|fldsnap\|fldfp\|spstub" run.log.d run.log 2>/dev/null | head -40  # R741: + spstub scratchpad-evidence receipts (probe-invisibility fix #5)
echo "=CRASHKIT="; grep "\[crashkit\]" run.log | tail -8; grep "\[exitdiag\]\|\[halt-scan\]\|\[fault\]\|region returned" run.log | head -20  # R679: which exit path fired; grep "\[crash\]" run.log.d | head -48  # R654: the kit writes a full dossier (CRITICAL, regs32, code@cur_fn, data@r4, backtrace) into run.log.d - c224 resolved a fault but the digest filter hid the context
# R233: resolve the host fault PC against the binary -> the exact emitted
# C file:line = the exact translated MIPS instruction that faulted.
HOST_PC=$(grep -o "host_pc=0x[0-9A-F]*" run.log.d | head -1 | cut -d= -f2)
HOST_BASE=$(grep -o "host_base=0x[0-9A-F]*" run.log.d | head -1 | cut -d= -f2)
if [ -n "$HOST_PC" ] && [ -n "$HOST_BASE" ]; then
  # R245: macOS nm prints "_xenolift_ring" (leading underscore, type column);
  # old pattern " xenolift_ring$" never matched = resolver ran SILENT.
  STATIC_BASE=$(nm xenogears_boot 2>/dev/null | grep -E '(_xenolift_ring| xenolift_ring)$' | awk '{print $1}' | head -1)
  if [ -n "$STATIC_BASE" ]; then
    python3 - "$HOST_PC" "$HOST_BASE" "$STATIC_BASE" <<'PYR'
import sys
hp, hb, sb = (int(x,16) for x in sys.argv[1:4])
slide = hb - sb
static_pc = hp - slide
print("[crash] resolved static_pc=0x%08X slide=0x%X" % (static_pc, slide))
PYR
    STATIC_PC=$(python3 -c "import sys; hp=int('$HOST_PC',16); hb=int('$HOST_BASE',16); sb=int('$STATIC_BASE',16); print('%X'%(hp-(hb-sb)))" 2>/dev/null)
    if [ -n "$STATIC_PC" ]; then
      atos -o xenogears_boot "0x$STATIC_PC" 2>/dev/null | head -2 | sed 's/^/[crash] resolved /'
    else
      echo "[crash] resolver: STATIC_PC compute failed (HOST_PC=$HOST_PC HOST_BASE=$HOST_BASE STATIC_BASE=$STATIC_BASE)"
    fi
    # R483: symbolize every host frame ra -> names OUR functions in the chain
    RLD_SZ=$(wc -c < run.log.d 2>/dev/null || echo 0)
  if [ "$RLD_SZ" -gt 4000000 ]; then echo "[crash] symbolizer skipped (run.log.d ${RLD_SZ}B - R735 digest speed guard)"; grep -o "frame #[0-9]* ra=0x[0-9A-F]*" run.log.d | head -3; fi
  if [ "$RLD_SZ" -le 4000000 ]; then grep -o "frame #[0-9]* ra=0x[0-9A-F]*" run.log.d | while read -r FL; do
      RA=$(echo "$FL" | grep -o "0x[0-9A-F]*$")
      SRA=$(python3 -c "ra=int('$RA',16); hb=int('$HOST_BASE',16); sb=int('$STATIC_BASE',16); print('%X'%(ra-(hb-sb)))" 2>/dev/null)
      if [ -n "$SRA" ]; then
        SYM=$(atos -o xenogears_boot "0x$SRA" 2>/dev/null | head -1)
        case "$SYM" in *0x*) echo "[crash] sym $FL -> (outside binary)";; *) echo "[crash] sym $FL -> $SYM";; esac
      fi
    done | head -8
  fi
  else
    echo "[crash] resolver: STATIC_BASE not found in xenogears_boot symbols"
  fi
else
  echo "[crash] resolver: host_pc/host_base missing from crash kit output"
fi
echo "=STAB2="; grep "\[stab\]" run.log.d | tail -12
echo "=FMT="; grep "\[fmtcall\]\|\[fmtouter\]" run.log.d 2>/dev/null | head -24
echo "=BADCODE="; grep "\[badcode\]" run.log.d 2>/dev/null | head -8
echo "=MODBASE="; grep "\[modbase\]" run.log.d 2>/dev/null | head -14
echo "=STAGE2P="; grep "\[stage2p\]" run.log.d 2>/dev/null | head -8
echo "=FLDX="; grep "\[fldx\]" run.log.d 2>/dev/null | head -4
echo "=OVLGATE="; grep "R791" run.log.d 2>/dev/null | head -3
echo "=MISALIGN="; grep "\[misalign\]" run.log.d 2>/dev/null | head -6
echo "=FAULTGATE="; grep "\[faultgate\]" run.log.d 2>/dev/null | head -4
echo "=JSRC="; grep "\[jsrc\]" run.log.d 2>/dev/null | head -8
echo "=WALKMAP="; grep "\[walkmap\]" run.log.d 2>/dev/null | head -14
echo "=ZBAND="; grep "\[zband\]" run.log.d 2>/dev/null | head -4
echo "=F16HDR="; grep "\[f16hdr\]" run.log.d 2>/dev/null | head -6
echo "=F17INS="; grep "\[f17ins\]" run.log.d 2>/dev/null | head -6
echo "=READALL="; grep "READ ISSUED" run.log.d 2>/dev/null | tail -24
echo "=MPAD="; grep "\[mpad\]" run.log.d 2>/dev/null | head -8
echo "=BWALK="; grep "\[bwalk\]" run.log.d 2>/dev/null | head -8
echo "=BOOTWALK="; grep -E "size-lookup|READ ISSUED|req member" run.log.d 2>/dev/null | tail -40
echo "=CRASH2="; grep -a "crash\]\|SEGFAULT\|SIGSEGV\|crashkit\|bxcep" run.log.d 2>/dev/null | head -24
echo "=LASTLOG="; tail -40 run.log.d 2>/dev/null
echo "=DEPTH="; grep "\[depthguard\]" run.log.d 2>/dev/null | head -4
echo "=SEGvREC="; grep "\[segvrec\]" run.log.d 2>/dev/null | head -12
echo "=RUNGASP="; grep "\[rungasp\]" run.log run.log.d 2>/dev/null | head -4
echo "=JUMPREC="; grep "\[jumprec\]" run.log.d 2>/dev/null | head -12
echo "=FONTW="; grep "\[hook\] 0x80069394\|\[hook\] 0x80068934\|\[hook\] 0x80068938\|\[hook\] 0x800568C8" run.log run.log.d 2>/dev/null | head -40
echo "=MVDOOR="; grep "mvdoor\|alarmguard" run.log run.log.d 2>/dev/null | head -24
echo "=PADSTART="; grep "\[padstart\]" run.log run.log.d 2>/dev/null | head -30
echo "=SIGWATCH="; grep "\[sigwatch\]" run.log run.log.d 2>/dev/null | head -8
echo "=SIOPAD="; grep "\[siopad\]" run.log run.log.d 2>/dev/null | head -40
echo "=PADRDW="; grep "\[padrd\]" run.log run.log.d 2>/dev/null | head -44
echo "=CBMOD="; grep "\[cbmod\]" run.log run.log.d 2>/dev/null | head -12
echo "=CBMOD2="; grep "\[cbmod2\]" run.log run.log.d 2>/dev/null | head -8

echo "=BYPASSREC="; grep "bypassrec" run.log run.log.d 2>/dev/null | head -8
echo "=SDOOR="; grep "sdoor" run.log run.log.d 2>/dev/null | head -8
echo "=WFDUMP="; grep "wfdump" run.log run.log.d 2>/dev/null | head -8
echo "=BANKHEAL="; grep "bankheal" run.log run.log.d 2>/dev/null | head -12
echo "=ARCHGUARD="; grep "\[archguard\]" run.log run.log.d 2>/dev/null | head -8
echo "=CANARYREC="; grep "canaryrec" run.log run.log.d 2>/dev/null | head -24
echo "=ABRTREC="; grep "\[abrtrec\]" run.log run.log.d 2>/dev/null | head -8
echo "=SEGVDIE="; grep "\[segvdie\]" run.log run.log.d 2>/dev/null | head -6
echo "=DASHFIX="; grep "\[dashfix\]" run.log run.log.d 2>/dev/null | head -12
echo "=SPUERR="; grep "\[spuerr\]" run.log run.log.d 2>/dev/null | head -12
echo "=SPUDONE="; grep "\[spudone\]" run.log run.log.d 2>/dev/null | head -12
echo "=KICKDUE="; grep "\[kickdue\]" run.log run.log.d 2>/dev/null | head -12
echo "=WEDGECAM="; grep -a "wedgespin\|pollkick\|R1195 liveness\|R1195 host backtrace\|nullbase2\|R978 pump null-base\|a22c origin\|tblw\|#0 0x\|#1 0x\|#2 0x\|#3 0x\|#4 0x" run.log run.log.d 2>/dev/null | head -72  # R1195/R1196: wedge cameras + pollkick receipts (also survives the digestcap block below)
echo "=FLDFRZ2="; grep "\[fldfrz2\]" run.log run.log.d 2>/dev/null | head -10
echo "=FLDFRZ="; grep "\[fldfrz\]" run.log run.log.d 2>/dev/null | head -8
echo "=ABORTMSG="; grep -iE "free\(\)|stack smashing|malloc|double free|corrupt|invalid pointer|assertion" run.log run.log.d 2>/dev/null | head -12
echo "=STATESTAMP="; grep "\[statestamp\]" run.log run.log.d 2>/dev/null | head -12
echo "=DEV="; grep "\[dev\]" run.log run.log.d 2>/dev/null | head -48
echo "=DIR2="; grep "\[dir2\]" run.log.d 2>/dev/null | head -36
echo "=BANKW="; grep "\[bankw\]" run.log.d 2>/dev/null | head -28
echo "=FTAB2="; grep "\[ftab\]\|\[newread\]" run.log.d 2>/dev/null | head -40
echo "=FTAB2="; grep "\[tblheal\]" run.log run.log.d 2>/dev/null | head -8
} > digest.tmp 2>&1
DGSZ=$(wc -c < digest.tmp)
if [ "$DGSZ" -lt 500 ]; then
  echo "[digestfb] digest assembly came up empty (${DGSZ}B) - R735 fallback: run.log tail"
  tail -c 24000 run.log 2>/dev/null || tail -c 24000 run.log.d 2>/dev/null
elif [ "$DGSZ" -gt 38000 ]; then
  head -c 16000 digest.tmp
  echo "[digestcap] R865: digest was ${DGSZ}B - kept head 16KB + DEATH EVIDENCE + tail 12KB (death receipts must survive the cap - c454's EXITTAIL was cut by the middle-capper and the death went unnamed)"
  echo "=WEDGECAM="; grep -a "wedgespin\|pollkick\|R1195 liveness\|R1195 host backtrace\|nullbase2\|R978 pump null-base\|a22c origin\|tblw\|#0 0x\|#1 0x\|#2 0x\|#3 0x\|#4 0x" run.log run.log.d 2>/dev/null | head -72  # R1196: wedge evidence survives the cap (Jos: "merely adding another middle section can lose the evidence again")
  echo "=DEATHREC="
  echo "--- EXITTAIL (run.log last 96) ---"; tail -96 run.log 2>/dev/null
  echo "--- asan ---"; grep -i "AddressSanitizer" run.log 2>/dev/null | head -12
  echo "--- canaryrec ---"; grep "canaryrec" run.log 2>/dev/null | head -12
  echo "--- abrtrec ---"; grep "\[abrtrec\]" run.log 2>/dev/null | head -6
  echo "--- segvdie ---"; grep "\[segvdie\]" run.log 2>/dev/null | head -6
  echo "--- segvrec ---"; grep "\[segvrec\]" run.log 2>/dev/null | head -6
  tail -c 12000 digest.tmp
else
  cat digest.tmp
fi
# v7.1: the bridge polls a completion FILE — a lingering child would keep
# nothing alive, but a wedged emulator straggler must never outlive the
# script. Reap and exit explicitly.
# R1020: stamp the post-run capture hash — next build's alternate match.
RUNHASH=""
for _cap in overlay_fault.bin stage2_region.bin overlay_region.bin; do
  [ -f "$_cap" ] && RUNHASH="$RUNHASH$_cap:nz$(python3 -c "
import sys
d=open('$_cap','rb').read()
n=0
for i in range(0,len(d)-3,4):
    if d[i]|d[i+1]|d[i+2]|d[i+3]: n+=1
print(n)")"
done
if [ -n "$RUNHASH" ]; then
  printf '%s' "$RUNHASH" > .run.md5
  echo "[emitgate] R1020 post-run capture hash stamped to .run.md5 (alternate gate match; c135/c136 infinite fresh-emit fix)"
fi
pkill -9 -x xenogears_boot 2>/dev/null
exit 0
