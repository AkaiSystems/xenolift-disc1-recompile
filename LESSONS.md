# XENOLIFT LESSONS — MISTAKE LEDGER
Durable record of every mistake class (mostly the agent's own), so nothing is done twice.
Every new ship: audit the diff against this ledger BEFORE the directive. Every new lesson: append here + save to agent memory.

## PRE-FLIGHT CHECK (run before every ship)
- [ ] New probes/assists have ALL THREE: runtime code + run.sh digest section + era-sized line budget
- [ ] New assist does NOT dispatch guest code from MMIO-read context (cell-writes only)
- [ ] Compile: -Werror=implicit-function-declaration (Mac clang parity)
- [ ] Banner bumped exactly once; one package per turn; zip contents verified before directive
- [ ] Zip build: os.walk('xenolift') from WORKSPACE ROOT (not inside the folder)
- [ ] Detector signatures cover ALL observed variants (check the miss-logs, don't assume one value)
- [ ] Sandbox log shows zero unexpected [sp-fix]/[hand-fix] lines

## LESSONS

### L1. Probe without a digest section (hit 3x — R341/earlier)
Symptom: probe runs on the Mac but is INVISIBLE in the digest — run.sh had no grep section for it; or the probe's 24-line cap was exhausted in an earlier era before the interesting era arrived.
Fix/prevention: every new fprintf ships as a triple — runtime code + run.sh section + line budget sized for the era where it matters (240 not 24 for long runs). Check the triple in the pre-flight.

### L2. Guest dispatch from MMIO-read context (R350 — first hung run)
Symptom: cycle 99 killed at 240s, no park, partial evidence. cd_force_deliver_int1 (synchronous guest handler chain) called from the timer-2 read handler → the dispatched chain loops forever internally → even the watchdog park deadlocks.
Fix: retirement assists do CELL-WRITES ONLY (FE1C→1, counters++, cd_pending=1) and leave the INT pending — the proven fd-tick collector delivers it on its own safe cadence (R351 validated: fired clean, no hang).
Prevention: no xenolift_dispatch() or any guest-code call from a register-read handler in the field era.

### L3. Re-fire design + recursion-friendly context = runaway (R350 design flaw)
Symptom: a counter that increments per MMIO read also counts nested reads made by the code our own fire dispatched — re-fire thresholds can be met inside recursion.
Fix: one-shot per stale-address (re-arm only on state/address change), caps on total fires.

### L4. Era-gated probes go blind at era handoffs (R343 feseed, R327 rdcomp)
Symptom: probes/assists gated on g_movie_live never fire in the field era — exactly when needed; gate change to (movie||field) was a no-op because g_movie_live never drops.
Fix: gate on STATE (signature), not era. Diagnose era problems with state signatures + explicit era flags. Verify the rail is hot (a sibling assist firing on the same rail proves it) before blaming a gate.

### L5. Detector signature drift (R337 — wedge moved substates)
Symptom: machine parked at FE1C=7/FE20=3 after serving state 6 — detector watched only 7/4 → zero assists fired.
Fix: detectors cover every OBSERVED variant (FE20 3 OR 4) and log their signature misses so drift is visible next digest.

### L6. sp-scrubber false positive stripped the legit kernel stack top (R233 — boot destroyed)
Symptom: 0x80200000 shares bit 21 with the poison family; mask had no round-value/low-bits guard → kernel stack stripped → RAM-base underflow → dead cycle.
Fix: strip ONLY on out-of-RAM values with nonzero low-21 bits AND in-RAM stripped result; verify zero [sp-fix] lines in the sandbox log before shipping.

### L7. Silent compiler forgiveness (R230 — dead cycle)
Symptom: sandbox gcc silently forgave an implicit printf (missing include) → Mac compile failed → run.sh fell back to a stale binary → wasted bridge cycle.
Fix: all ship builds compile with -Werror=implicit-function-declaration.

### L8. Banner collisions / double ships / truncated-turn races (cycles 15-16)
Fix: banner bumped exactly once per ship; ONE package per turn; verify zip contents (banner + fixes present) BEFORE posting the directive; a second upload in the same turn races and the bridge may run the older one.

### L9. Zip-build cwd gotcha (hit 2x)
Fix: the zipfile os.walk('xenolift') MUST run from the workspace root, never inside the folder — otherwise the zip silently has 0 entries.

### L10. Grep tokens in the startup banner poison their own output (R145)
Symptom: banner contained literal digest tokens → one digest reprinted the banner 4x.
Fix: banner = one-line build ID + pointer to PROJECT_LOG.md.

### L11. Ship-gate checks must test structure, not character windows
Symptom: gate checked for a substring inside a 900-char window; the code moved past the window → false FAIL, wasted verification churn (R350 gate).
Fix: assert on the presence of the real code strings/conditions, sized generously, or parse structurally.

### L12. Memory entries are 1000-char capped
Fix: split long lessons into multiple save_memory calls; the durable full text lives HERE.

## VALIDATED PATTERNS (the good stuff, keep using)
- Cell-effect synthesis: decode the guest handler (modsrc window), then perform EXACTLY its happy-path cell writes + async INT (R327/R349/R351 line of assists; fn_8002A894 decoded = byte-for-byte match with the synthesized effects).
- The fd-tick handler-pair collector is the safe universal delivery mechanism.
- One-paste diagnostic digest + =FLD= era-sliced views for era-transition bugs.
- Park-diffing across cycles: when the park r31/cells CHANGE, the frontier moved — read the new park before theorizing.

## L13 — Park-path placement bug (cycle 102, R353)
- **Symptom:** batch-list printer compiled in, ran nowhere — digest =TAIL= showed no [park] batch lines.
- **Cause:** the runtime has MULTIPLE park dump contexts; I inserted the printer into a cold one (~line 872) instead of the watchdog halt park (~line 3330) that the digest actually prints.
- **Fix:** moved to the watchdog park, after the player-state (R301) block.
- **PRE-FLIGHT CHECK:** when instrumenting a park/crash dump, grep WHICH park function the digest section reads from and insert THERE; verify placement relative to a known-printing line (e.g. "player state (R301") before shipping.

## L14 — Hung runs must still yield evidence (cycle 104, R355)
- **Symptom:** R355 wedged the run pre-park; bridge killed at 240s with a one-line stub digest — zero evidence, a whole cycle burned blind.
- **Cause:** run.sh's digest stages only run after the guest process exits; a runtime that never parks blocks the entire digest, and a log storm makes even partial greps too slow.
- **Fix (R356):** (a) hard run fuse — background `sleep 210; kill -9` on the guest PID so run.sh ALWAYS regains control; (b) log guard tightened 60MB→20MB threshold, 5+30MB keep → 2+2MB keep so storm logs digest in seconds.
- **PRE-FLIGHT CHECK:** every future hang-prone assist ships with the fuse active; a killed run must still produce =TAIL= park-or-partial evidence. If a runtime change can wedge, the evidence path must be proven first.

## L15 — Unbounded per-access loggers kill the watchdog (cycle 105, R355/R356)
- **Symptom:** 20MB+ log in <30s, ZERO [wd] watchdog lines, no park; fuse saved evidence.
- **Cause:** kernel WaitForCdData tight-loop on 0x1F801800-03; the [dev] always-log printed every access. The storm's fprintf collided with the SIGALRM park path (signal-unsafe fprintf) → watchdog never fired → fuse kill.
- **Fix:** every per-access logger ships with a cap (first N + sparse tail). [dev] capped at 24 + every 50000th.
- **PRE-FLIGHT CHECK:** grep any fprintf inside a per-read/per-write/per-tick path → must have an explicit cap or sparse stride. A "log everything" probe is a wedge amplifier.

## L16 — Oracle verification rule (Jos directive, 2026-09-12)
- "Look to the previous recompilation build for answers... study learn test and verify when issues arise."
- The OpokXeno/psxrecomp runtime (cdrom.c) runs Xenogears PLAYABLY = the CD/hardware oracle. Distilled semantics live in docs/oracle/ORACLE_PSX_CD.md; full source ships at docs/oracle/psxrecomp_cdrom.c.
- ORACLE TRAP #1 (they hit it too): pending command completions must use ABSOLUTE deadlines — ack gates only presentation. A pending INT2 that waits for the response FIFO to clear NEVER lands when the kernel leaves responses unconsumed (our parks show resp_n=3 unconsumed!). Audit any pending-arm logic against this.
- PRE-FLIGHT: before shipping CD-drive semantics, check the behavior against the oracle doc.

## 14. Bridge autopilot directive deadlock (2026-09-12, cycles 112-119)
- **Symptom:** bridge v7 ran the stale R361 build 8+ cycles straight, ignoring the R364 directive posted in reply to each digest (one 5s empty cycle too).
- **Cause:** v7's directive pickup is gated on game-state change between cycles; state cannot change until the new package runs → chicken-and-egg. Directives posted mid-identical-state loop sit unread.
- **Fix:** relaunch the bridge (fresh instance reads the chat at startup and takes the latest directive): `pkill -f xenolift-bridge; sleep 2; caffeinate -i ~/Downloads/xenolift-bridge7.sh 500`
- **Prevention check:** if 2+ consecutive digests show the SAME banner after a new ship, stop shipping and request relaunch — more packages can't help; the pickup loop is wedged.

## 15. Starving the directive poller (2026-09-12, cycle 120)
- **Symptom:** bridge digests labeled "no-directive retry" — the bridge polls each cycle for a directive block and found none.
- **Cause:** my "going quiet" replies contained only the relaunch command, dropping the ===XENOLIFT-DIRECTIVE=== block. The poller reads the latest agent message; no block = no package pickup, even if the bridge WOULD take it.
- **Fix:** EVERY digest reply carries the full directive block, no matter how short the rest of the message is. "Quiet mode" = minimal prose, NEVER minimal directive.
- **Prevention check:** before sending any reply to a bridge digest, confirm the directive block is present and well-formed (package_url + block fields).

## 16. Truncated-upload wedge (2026-09-12, cycles 112-121 root cause)
- **Symptom:** bridge ran stale R361 for 9+ cycles despite directives; both package uploads at the URL were exactly 38,810,931 bytes while the local zip was 64,029,739 — the upload path truncates large files deterministically (~37MB cap), leaving a headless zip (no central directory).
- **Diagnosis that cracked it:** curl the directive's package_url and open it with python zipfile — "not a zip file" + identical truncated byte count across two different uploads = server-side truncation, not a bridge bug. The bridge's silent fallback to the old tree after failed extraction made it look like a state-gate.
- **Fix:** strip stale *.log files (65 logs, 448MB uncompressed ballast) from the ship zip — slim package 64MB→9.1MB, uploads intact, md5 verified end-to-end.
- **Prevention check:** EVERY directive ship = (1) build zip excluding *.log, (2) upload, (3) re-download from the URL and zipfile-verify + md5-match BEFORE posting the directive. Never post a directive for an unverified URL.

## 17. Ship-zip ballast + foreign-arch clobber (2026-09-12, cycle 122)
- **Symptom:** cycle 122 (first slim-package run) wasted 8s healing: "cargo: rebuild (binary is FOREIGN-ARCH — clobbered by an unzip; healing)" + "compile cache from a different host - wiping".
- **Cause:** the ship zip included the sandbox's target/release/xenolift binary (wrong architecture for the Mac) and the sandbox .cache/*.o objects — extraction clobbered the Mac's good binary and host-local compile cache on every ship.
- **Fix:** ship zips EXCLUDE *.log, target/, .cache, and diagnostic output .bin dumps (spu_ram/vram/stage2_region/overlay). Ship only sources + run.sh + hle/ + LESSONS.md + REMASTER docs.
- **Prevention check:** before zipping, list the biggest 10 entries — if any is target/, .cache/, or a *.log, the filter is broken.

## 18. Park must be self-guarded (2026-09-12, cycle 122)
- **Symptom:** R364 run parked normally at 196s but the cycle died with ZERO evidence — bridge killed everything at 240s ("hung run; partial evidence"). No park lines in the digest at all.
- **Cause:** a park printer wedged INSIDE the SIGALRM handler (first fresh-emit + fresh-binary park). Nothing can interrupt code inside a signal handler — no alarm, no rescue — so the guest hung forever and run.sh never completed.
- **Fix (R365):** park backstop — g_in_park latch set at park start, 8s backstop alarm, on_alarm re-entry while latched = print "[park] STAGE-HANG at stage N" + _exit(77). Stage counter (1=HALT-print 2=registers 3=post-register 4=park-tables 5=gpu+freelist 6=backtrace) names the wedged printer in the digest even on a forced exit.
- **Prevention check:** any future code added to on_alarm's park path MUST (a) set a stage marker before it, (b) be bounded — no unbounded walks, no malloc-heavy libc calls (backtrace_symbols is a known hazard).

## 19. Digest greps on the raw storm log (2026-09-12, cycles 122-123)
- **Symptom:** two consecutive cycles: guest ran and parked PERFECTLY (195-196s), then the cycle died at the 240s bridge kill with an EMPTY digest ("hung run; partial evidence") - the R365 park backstop proved the runtime innocent (run stage completed normally, no exit-77).
- **Cause:** the fresh-emit guest (new disc1.c + new binary) runs deeper and storms the log to GB scale; the digest phase has ~105 greps that read run.log DIRECTLY, bypassing the R252 logcap (which only built run.log.d) - each raw grep re-scans the whole multi-GB file, stalling the digest 40s+ into the bridge's 240s kill.
- **Fix (R366 storm-swap):** after the logcap builds the capped copy, `mv run.log run.log.storm; cp run.log.d run.log` - every subsequent grep (raw or .d) hits a <=4MB file; the raw storm log is preserved renamed for forensics.
- **Prevention check:** any new digest section added to run.sh may grep run.log freely NOW, but if a future change ever bypasses the storm-swap (e.g., a new pre-logcap grep), the stall returns. Keep ALL digest greps AFTER the logcap block.

## 20. Title era reached; probe budget + line caps (2026-09-12, cycle 124)
- **MILESTONE:** the intro finished NATIVELY; the kernel restarted itself into state-0 (title/menu phase, cb=0x8001A4B4), loaded a new 16212-byte module to 0x801EF558, and completed the file-18 read to the last byte. New park site: inside fn_80036BE8, with the GPU submitting 4.48 MILLION 8x8 textured rects — the title render loop.
- **Bugs found in my own tooling:** (a) the R228 [gpu] rect probe had a every-500th sampler = ~9k lines on the title loop — the storm class again; every probe needs a HARD cap, sampling is not a cap. (b) byte-based logcap (head -c/tail -c) glued seam lines mid-line and corrupted digest diagnosis — line-aligned caps (sed/tail -n) only. (c) the lzss-inpast decode hook fired on the PARK PRINTER's own host-side memory reads — park diagnostics must never trigger guest-code hooks (guard with g_in_park).
- **Prevention check:** any new fprintf probe = hard lifetime cap, no samplers; any log cap = line-aligned; any hook that fires on mem reads must check g_in_park.

## 21. Unclosed comment = dead cycle (2026-09-12, cycle 125)
- **Symptom:** cycle 125 burned in 6s: hle_gpu.c compile error "expected expression" at line 389 — the R367 rect-cap edit injected a /* comment and NEVER CLOSED IT, swallowing 60 lines of code. run.sh correctly refused to run a stale binary.
- **Root cause:** my python edit placed a long explanatory comment inline inside an if-condition; and my pre-ship check compiled ONLY runtime.c, not hle_gpu.c.
- **Fix (R368):** comment closed, moved above the if. PRE-FLIGHT CHECK NOW MANDATORY: gcc -fsyntax-only -Werror=implicit-function-declaration on EVERY .c in the tree (runtime/*.c + hle/*.c) before zipping — not just the file I edited, ALL of them.
- **Prevention check:** inline comment edits must start AND close on the same edit; the pre-ship scan is a loop over all sources, no exceptions.

## 22. C comment in python = blind cycle (2026-09-12, cycle 126)
- **Symptom:** =MODSRC= printed only "[modsrc] extraction failed" - the exact disassembly of the new title-era park site was lost. Cause: the R367 window edit put a /* */ C-style comment into PYTHON code (SyntaxError) AND the heredoc ran with 2>/dev/null, so the traceback was invisible.
- **Fix (R369):** comment converted to python # syntax; stderr suppression removed (failures must be loud); windows retargeted to BOTH observed park sites (L_80036BE8 + L_80036708).
- **Prevention check:** pre-flight now syntax-checks the REAL extracted heredoc (python3 compile on the actual bytes between python3-<<'XEOF' and XEOF, not a sed/awk extraction that can silently yield an empty file - verify the checker itself: it must print the line count). Comment markers must match the language of the file being edited.

## Lesson 9 — wrong-byte press (R374, caught cycle 134)
**Symptom:** kernel-cell button press "landed" (cells showed our values) but the menu ignored it for 3 cycles.
**Cause:** the kernel button snapshots (0x800773AC/B4) are 8-byte PAD FRAMES (header/ID at +0, buttons at +2..+4), not bare button bytes — the R374 press wrote byte +0 (the ID header). Worse: the REAL menu input handler (fn_8001A344/34C, found only after widening the census cap) reads a DIFFERENT cell pair entirely (0x800694A4/8C, active-HIGH bits — pressed = bit SET, opposite of the active-low InitPAD buffers).
**Fix:** decode the actual reader before choosing the write target; press the exact cells the reader loads, with the reader's own bit polarity.
**Prevention check:** before any "press X" fix, name the exact LW/LHU instruction + cell + bit polarity from a decoded window — never reuse a cell/bit from a different reader.

## Lesson 10 — Too-short pulse lands between reads (2026-09-12)
- Symptom: R378 single-frame X pulse at the menu cells fired (log: armed+released) but cursor stayed 0 — the write window fell entirely between two of the menu's per-frame input reads.
- Fix: R379 holds button writes across >= 3 menu frames so at least one input read cycle sees them.
- Prevention check: any injected button press must outlast the target reader's poll period — never a 1-frame hold when the reader runs once per frame and the arm/release points sit at the same cadence.

## Lesson 11 — Section header inserted inside an existing echo string (R380, caught cycle 138)
- Symptom: [minput] probe ran on the Mac but the digest showed an empty "=minput=" with no probe lines — the 4th occurrence of the probe-without-visible-digest bug class.
- Cause: run.sh section was added by blind text-replace of '=MPAD=' with '=MPAD=\n=minput=' — which landed INSIDE the echo string ("echo \"=MPAD=\n=minput=\""), producing a header with NO grep of its own.
- Fix: each digest section must be its own line pair: echo "=X="; grep "pattern" run.log | head N. R381 repaired =MPAD= and added a real =MINPUT= section; smoke-tested with a synthetic run.log.
- Prevention check: after ANY run.sh edit, run the section audit (every echo "=..." line must have its grep/producer on the same or next line) AND smoke-test new sections with synthetic log lines BEFORE zipping.

## Lesson 12 (2026-09-12, cycles 137-140): the translate-branch GHOST
**Symptom:** decoded logic says X must happen; camera shows the exact precondition met
11 frames straight; nothing happens. Frozen register fingerprint at every dispatch
(r4=0x74 forever). The decoded function dispatches, but its body never ran past the
first block.
**Root cause class:** block-split emit — conditional branches must hop to the NEXT
translated block via dispatch; when that hop is missing/mis-targeted, execution
silently dies at the branch. All downstream blocks become ghosts.
**Fix that worked:** bypass the dead blocks at the dispatch hook — execute the decoded
block's action ourselves (channel D: dispatch the real commit fn with the right args).
**Prevention:** when a decoded window CONTRADICTS observed behavior, do not re-argue
the decode — probe the block dispatches (BLOCK-RANGE probe) and check body-liveness
(a unique call inside the body). Trust cameras over code.

## Lesson 24 (2026-09-12, cycle 154): tail-capped shared sections evict probe evidence
- Symptom: R396's poll-release fired during boot (regressing the flow: no file-18, no title, no menu — stalled at dir-2 file-3) but NO "[cd] INT3 delivered" lines appeared in the digest; the CD5 grep is tail -24 and 21 later "data-ready INT1 armed" lines evicted them. Evidence was eaten, diagnosis nearly missed.
- Fix: (1) R397 gates the release to the exact field-read-wait park signature (FE1C==2 && cmd==06 && FE04==seek && FDF8!=0) so it can never perturb boot/movie flows; (2) new probe lines get their OWN digest section with HEAD-kept grep (=CD6= head -24).
- Prevention check: every new probe's digest placement must be audited — if it shares a section, later-era spam WILL evict it; use a dedicated head-kept section for early-era probes.
- Second lesson: an ungated "harmless" delivery assist is never harmless — gate every era-specific assist to the park signature it was built from.

## Lesson 32 — once-per-run probe latch = era-blind map (c158-159)
Date: 2026-09-12 (R400/R401)
Symptom: The field-poll "map" logged exactly one line (boot-era 803-idx1) and
went permanently blind afterward: the fpm_seen latch was ONCE PER COMBO PER
RUN, so the field wait polling the same combo logged nothing. Two cycles of
"the map says 803-idx1" were actually only the boot window.
Fix: R402 delivers at the FE1C RAM-poll hook (the true wait vehicle) — the
map is moot.
Prevention check: any "first occurrence" probe latch must reset when the
watched INSTANCE ends (here: when the release clears cd_scheduled), or the
probe goes blind after the first era. Ask: does this latch survive an era
boundary?

## Lesson 33 — hook-probe sig helper reading its own watched cells = recursion bomb
Date: 2026-09-13 (R403 crash, cycle 161, 2s in)
Symptom: SIGBUS (sig 10) at xenolift_mem_read32+792 — R403's field-data camera
probes watched reads of FE04/FDF8/FE1C/578A6, but fld_data_sig() itself reads
FE04/FDF8 through the same central hook: probe -> sig -> read -> probe ->
... unbounded -> stack guard page. The R402 hook had its own guard
(g_r402_in_hook) but the shared helper did not.
Fix: R404 — re-entry guard at the ROOT (inside fld_data_sig): nested calls
return 0.
Prevention check: ANY probe placed inside xenolift_mem_read32 whose gate
helper also calls xenolift_mem_read32 MUST have a re-entry guard in the
helper (not just at one call site). Ask: does this helper read any cell the
probe watches?

## Lesson N+1 (2026-09-13, c170→c171): never gate a working flow on an unverified theory mid-breakthrough
- Symptom: c170 the field pump flowed through the guest's per-batch reset (6 sectors → counter resets to start → next batch); I read the reset as a "wasteful double-bell restart" and added a pair-latch (R413) preventing the arm from re-firing at the same (seek, FDF8) state. c171: pump flowed 6 sectors then froze solid at the reset state — the latch blocked the batch-protocol re-arm.
- Fix: R414 reverted the latch entirely. The "restart pass" was the guest's NORMAL batch window protocol (FE04 stepper advances 6 then resets at fn 800415B4).
- Prevention check: before "optimizing" any working flow, verify the behavior is actually a defect (does hardware/the game re-enter this state by design?) — evidence first, gate second. If a flow just achieved its first breakthrough, do NOT touch it in the same cycle.

## Lesson N+2 (2026-09-13, c181): probe output without a digest section — 4th occurrence of the class
- Symptom: R423 added hc watcher k74 on cell 0x80069394, but run.sh's =EMW= section still grepped only "[hook] 0x80050594" — the k74 lines ran on the Mac but were invisible in the digest.
- Fix: R424 widened the EMW grep to cover both cells.
- Prevention check: when adding an hc watcher CELL, update the digest grep to cover that cell's address IN THE SAME SHIP. The runtime-code + digest-section + budget triple applies per CELL, not per watcher array.

## Lesson 34 (R435, cycle 192): SIGN-EXTENSION PHANTOM CELL — 10 cycles lost
- SYMPTOM: font-ctx install store "never executed" despite photographed
  straight-line C, proven-executed endpoints, sound hooks. Tripwires in the
  block DID fire (midw @t=1s r31=800377C0) but the cell stayed silent.
- ROOT CAUSE: the emitted store is SW(r1 + (int16_t)0x9394, r16) with
  r1=0x80060000. 0x9394 >= 0x8000 => the MIPS 16-bit offset SIGN-EXTENDS
  NEGATIVE (-0x6C6C). TRUE GUEST ADDRESS = 0x80059394, NOT 0x80069394.
  Every hook for ~10 cycles (ctxw/ctxb/EMW/fault-kit ctx read) watched the
  phantom 0x80069394, which only the runtime's t=0 BSS clear ever touches.
- FIX: R435 repointed all 24+1 probe sites to 0x80059394.
- PREVENTION CHECK (PRE-FLIGHT): whenever wiring a probe from an emitted
  line "SW(rX + (int16_t)0xNNNN, ...)", COMPUTE the address WITH the
  sign extension — offsets >= 0x8000 are negative. Never wire a probe to
  an address read off a C line without recomputing it from the base reg
  and the SIGNED offset. This is the MIPS immediate rule (psx-spx ISA).

## Lesson 35 (2026-09-13, 03:41): SILENT-STREAK BRIDGE = STALE LAB LOOKING DEAD
- SYMPTOM: agent ships sat unclaimed; Jos's terminal showed "same crashes"
  for an hour; no digests arrived; relaunches "fixed" it each time.
- CAUSE: bridge v7's autopilot gate silently re-ran the SAME directive
  (same package URL) for up to 25 identical-result cycles WITHOUT posting
  or checking for newer directives. Plus: every manual relaunch killed the
  in-flight cycle — the "restart churn" was us, compounding the silence.
- FIX: bridge v8 — fresh-directive GET check EVERY cycle; streak cap 25->2
  then heartbeat post; new-URL cycles never suppressed; never parks.
- PREVENTION CHECK: any autopilot/suppression feature MUST (a) re-check for
  new directives at least every cycle, (b) cap silence at ~10 minutes,
  (c) never suppress the first run of a NEW package.

## Lesson 36 (2026-09-13, R436/R437): PROBE BLIND SPOTS — BUDGET + ERA GATES
- SYMPTOM: btw (budget 8) exhausted at t=1s = blind to fault-era writes;
  frclash gate t>=5s left the t=1-5s corruption window unwatched. The
  stomper walked through the gap between two "working" probes.
- FIX: R439 btw budget 24 + fault-era =BTW2= tail; frclash gate 5s->2s.
- PREVENTION CHECK: for every watch, state WHERE the watched event happens
  in the run timeline and size budget + gate so the event's era is covered
  with margin. A probe whose budget dies before its era is a hole, not a
  probe.

## Lesson 37 (2026-09-13, R437): DMA MEMCPY IS A STORE-WATCHER SIDE DOOR
- SYMPTOM: font record provably corrupted; CPU-store watchers all silent.
- CAUSE: CD-DMA staging writes guest RAM via direct memcpy
  (memcpy(xenolift_mem + dst, ...)) — bypasses mem_write32/16/8 hooks, so
  EVERY address-watcher is blind to it. 36 direct-writer sites exist in
  runtime.c; the big data mover is the cd staging memcpy.
- FIX: R439 DMA-intersection guard at the staging memcpy (logs any sector
  copy intersecting the watched page).
- PREVENTION CHECK: when an address-watcher reads "silent" but the watched
  memory provably changed, audit the DIRECT writers (memcpy/overlay maps/
  HLE native writes) before concluding "nobody wrote it".

## Lesson 38 (2026-09-13, c188): SANDBOX disc1.c IS A DIFFERENT BUILD FROM THE MAC'S
- SYMPTOM: my sandbox disc1.c put L_8003782C at line 95060; the Mac's
  photographic window showed it at 96640 — different code between proven-
  executed labels. Static analysis from the sandbox copy was VOID.
- FIX: MODSRC windows (the digest's window mechanism) photograph the Mac's
  ACTUAL emitted file — the only ground truth for control flow.
- PREVENTION CHECK: for fine-grained control-flow conclusions (which branch
  skipped a store, etc), ALWAYS request a MODSRC window of the target label
  on the Mac's file; never reason from the sandbox copy.

## Lesson 39 (2026-09-13, 03:46): AGENT MARATHON TURNS STALL THE LAB
- SYMPTOM: Jos: "you're not picking up cycle... issue is on your end."
- CAUSE: the bridge's digest POST waits (up to 30 min) for the agent reply
  carrying the next directive — every minute I spend mid-turn is a minute
  the Mac idles. Marathon disasm dives inside a digest turn = lab stall.
- FIX: fast acknowledgment + ONE tight ship per digest; deep static analysis
  only when the lab is NOT waiting (between directives), or via MODSRC
  window requests that ship with the next package.
- PREVENTION CHECK: if a digest turn exceeds ~3 tool calls before its
  ship, stop, ship the probe that settles the open question, and defer
  the deep dive.


## Lesson 40 — 2026-09-13 (R441, cycles c197-c199): carve result vs advance argument
- **Symptom:** R441 "double-book fix" redirected fn_80031C58 takes inside the record span. It fired, but the stomp got WORSE (frclash refired deeper: 0x801EF334, LBA 108980; record still garbage at fault time).
- **Root cause:** fn_80031C58's a0 is the advance's node-ARGUMENT (normal bookkeeping on the block just carved), NOT a new carve result. [descw] proved the heap carves DOWNWARD (result = freeptr − size − 8); the original staging region [0x801D0BD8, 0x801EF558) ended exactly at the record base — correct layout. The redirect pushed staging +0x3F5C into the record span.
- **True root of the record stomp:** the linear sector fill's last sector(s) overshoot the staging region top by ~0x180-0x680 bytes into the record's first bytes.
- **Fix (R442):** revert the redirect; DMASHIELD — DMA fills intersecting the record span clip at the span edges, intersecting bytes diverted to a shadow buffer.
- **Prevention check:** before gating a fix on a function argument, PROVE the argument's role (result vs node pointer) from the full call math. The [descw] descriptor-lifecycle probe alone would have settled it — ship the proof probe BEFORE the fix, not alongside it.
- **Also:** NEVER overwrite LESSONS.md with a summary — APPEND only (this entry itself had to be rescued from the R441 zip after a clobber; full ledger is authoritative).

## Lesson 41 (2026-09-13, c30/R466 defib2): transcribe the photo EXACTLY when keying a rescue
- Symptom: [defib2] never fired even though the park photo matched its target posture exactly.
- Cause 1: my silence-clock reset included `|| cd_data_n != 0` — but the chronic stall state HAS data_n=2060 staged forever, so the timer reset every pass and never reached 5s.
- Cause 2: fire gate demanded sched==0 && act==0; the photo shows act stays 1 through the stall.
- Fix (R467): clock resets ONLY on real deliveries; gate uses only the photographed markers (staged data + no bell + ring owes bytes).
- Prevention: when writing a detector/rescue gate from a photo of the stall, use ONLY fields the photo shows; never add "cleanliness" conditions the photo contradicts, and never let the reset condition include the stall's own chronic marker.

## Lesson 48 (2026-09-13, c39 — R474 dead cycle)
**Symptom:** run died at 1s; guest never reached disc load; digest counters all zero.
**Cause:** extended the [chg] cell-watcher to 9 cells (added 0x77448) but left BOTH arrays declared [8] while looping i<9. The 9th initializer is silently DISCARDED by the compiler (excess-initializer is a warning, hidden by -w), and `snap[i]=cur[i]` at i=8 wrote one byte PAST the static snapshot array into adjacent static state — on every recompiled function entry.
**Fix:** R475 — `snap[9]`, `cur[9]`, loop i<9.
**Prevention check (ADD TO ZIP VERIFICATION):** any edit that changes a loop bound or initializer list MUST verify the DECLARED array size matches BOTH the initializer count and the loop bound — grep the declaration, not just the loop. -Werror=implicit only catches implicit decls; -w hides the excess-initializer warning.

## Lesson 42 (2026-09-13, c58 / R492): "hdr -> dest-8" theory DISPROVEN — dest-8 is the game's heap machinery
- Symptom: after the R491 heal shelved file 3, the heap walker fn_80031C58 crashed reading address 0x20736473 = the "wds " magic we wrote at dest-8 (0x8007EBE8) as a next-pointer.
- Fix: carry AND heal write payload -> dest only; dest-8 is never touched. Native bank-1 (file 2) proves the real delivery never writes there.
- Prevention check: any runtime that writes near a delivery destination must FIRST verify the destination-adjacent cells aren't owned by a live game structure (watch/walk them before writing). Exact-match lba directories also fail mid-file — use RANGE matches.

## Lesson 53 (2026-09-13, c82/c83): array size vs initializer count — the dead-watcher ghost RETURNS
- Symptom: FDF8 write watcher (R513) and 0x59F08 watcher (R507) printed ZERO lines for a whole run; verdict "no native length-writer exists" was drawn from that silence.
- Cause: hc_addr initializer grew to 78 elements while the declaration said [76] — GCC warns "excess elements" and silently DROPS the tail (the two newest watchers). Same class as the R423 bound-vs-array bug.
- Fix: declared size must be >= initializer element count; VERIFY THE COUNT programmatically before shipping (grep-count elements), not just the loop bound.
- Prevention check: any probe added to a fixed-size table = count elements + declaration in the zip-verify step.

## Lesson 54 (2026-09-13, c83): resize-together, FIFTH occurrence — companion arrays
- Symptom: R515 run crashed at 31s (vs 220s stable) with mangled kernel cells (0x03xxxxxx MSB corruption), irq-chain poison, glyph-submit fault. Classic memory-corruption digest.
- Cause: grew hc_addr[76]→[78] and loop→78, but hc_prev/hc_seen/hc_n stayed [75] — watcher sweeps OOB-wrote indices 75..77 into adjacent statics. The comment AT THAT LINE documented occurrences 1-3; occurrence 4 was the R513 element-count miss. Fix is not enough — add a COMPILE-TIME static-assert tripwire so the build fails loudly on the next mismatch.
- Prevention check: when touching any fixed-size parallel-array table, grep EVERY array sharing its index, and add typedef char guard[x ? 1 : -1] on sizes.

## Lesson 41 (c111, R542): SKIPPED THE COMPILE GATE ON A PATCH PASS
- Symptom: Mac compile failed (undeclared `fdf8w` in fldbell2 block) — 33s dead cycle; hardening correctly refused stale binary.
- Root cause: patch pass ran content asserts + zip checks but NO gcc -fsyntax-only; a scope-foreign variable name sailed through.
- Fix: fdf8w now declared locally in the block; banner bumped R543.
- Prevention (PRE-FLIGHT): EVERY patch pass ends with gcc -fsyntax-only -Werror=implicit-function-declaration BEFORE zip+upload. No exceptions, even for "one-line" changes.

## Lesson 44 (c114, R545): APPENDED DIGEST SECTION AFTER A '#' COMMENT — SWALLOWED
- Symptom: =FLDBELL4= section absent from digest (fldbell4 probe blind — couldn't tell if it fired).
- Root cause: appended "; echo ..." to a run.sh line that already ended with "# comment" — everything after # is a comment.
- Prevention: every new digest section gets its OWN echo line, never an append to an existing commented line.

## Lesson 46 (c313, R739): computed jump targets need the KSEG0 base
- Symptom: R738 helper-dump probe ran, found the entry's jal, printed NOTHING — the digest showed R726's 64-word dump and R729's scan but no R738 line.
- Cause: the probe computed the j/jal target as (imm<<2) = 0x76858 WITHOUT OR'ing the 0x80000000 KSEG0 base; the range guard (tgt >= 0x80010000) rejected it and the probe broke silently.
- Fix: target = 0x80000000 | ((w & 0x03FFFFFF) << 2). MIPS j/jal targets are 26-bit shifted, combined with the upper bits of the current PC.
- Prevention: any probe that computes a jump target MUST apply the memory-region base before range guards — and a probe that "finds" nothing should say so explicitly (silent-empty = invisible probe).

## Lesson 47 (c315, R740): scratchpad is a live hardware region, not dead storage
- Symptom: after the stale-translation cure (EMIT_REFRESH), the REAL translated field module's math helper executed fully then tail-called `jr r7` with r7=0x1F8000B0 (scratchpad). The entry had first copied sp[0..0x14] -> sp[0xA0..0xB2], i.e. the scratchpad head is expected to hold a small CODE STUB the kernel parks there on real hardware.
- Cause: our emulator models the scratchpad as passive storage initialized to zero, and no guest code ever writes it — the stub-writer is part of what our HLE layers replace (vblank/BIOS syscall family prime suspect).
- Rule: scratchpad (0x1F800000-0x1F800FFF) is a live region the kernel maintains; any module that jumps into it needs its writer modeled. Never treat untranslated-region reads of scratchpad as "probably zero is fine".
- Probes: [spstub] dumps head+copied blocks at fault; [spstub] write-watch names any writer.

## Lesson 48 (c316, R741): probe-invisibility #5 — grep section is part of the probe
- Symptom: R740's [spstub] fault-dump and scratchpad write-watch RAN on the Mac (fault target 0x1F8000B0 is in range) but produced ZERO digest lines — run.sh had no grep token for "[spstub]". The 5th occurrence of the class Lesson 27 (R342) named.
- Fix: spstub added to the =WILDCTX= grep; budget 30→40. ALSO: silent-empty probes are ambiguous — the write-watch now reports a TOTAL at the fault ("write-watch: N scratchpad writes since boot") so "no writers" is stated, never silent.
- Prevention (repeat, hardened): a probe is THREE parts — runtime code + run.sh grep section + era-sized budget — and the pre-flight check greps BOTH files before zip. A probe that can legitimately print nothing must print a summary line saying so.

## Lesson 49 (c317, R742): zip verification must COMPILE, not substring-match
- Symptom: R741 shipped with [spstub] fault-block referencing spw_total, but the
  counter was declared function-local (inside xenolift_mem_write32) - invisible
  to the fault block. Mac compile refused the binary (gate held, zero bad runs)
  = one dead cycle. My zip "verification" checked the SUBSTRING 'spw_total' in
  runtime.c (true! the print sites contained it) instead of compiling.
- Fix: declaration hoisted to file scope (R742).
- Prevention: (1) package verification step = extract runtime.c from the zip and
  cc -fsyntax-only -Werror=implicit-function-declaration it BEFORE the directive;
  (2) any variable used across two functions is declared at file scope - if the
  splice names it in one function, grep that it is NOT local;
  (3) never let a substring check stand in for a semantic check.

## Lesson 50 (c318, R743): decode with the ISA, watch every store width
- Symptom A: local binary scan for lui-0x1F80 found ZERO hits in the exe though the
  translated source clearly contained two — my mask (w & 0xFFE00000) == 0x3C001F80
  included the REGISTER bits and excluded the immediate: lui is (w>>26)==0x0F &&
  (w&0xFFFF)==imm. Decode with the ISA field layout, never a made-up mask.
- Symptom B: the scratchpad write-watch saw nothing at the field fault while the
  entry demonstrably copies 14 halfwords to sp[0xA0..0xB6] — the watch lived in
  mem_write32 ONLY; the copies are SH (halfword) stores. Watch ALL store widths
  (sw/sh/sb) for any region watch. (Probe-invisibility family, 6th member.)
- Root-cause reframe: the scratchpad stub is NOT kernel-written. The field entry
  copies the stub template from a RAM TABLE at 0x800AA3F0 (inside disc file#4's
  loaded image 0x800A49E8..0x800AA6C8) into sp[0xA0..], then tail-calls sp+0xB0.
  psx-spx confirms the scratchpad is free fast RAM (BIOS parks nothing there).
- Fix: R743 dumps the stub (direct storage reads — mem_read32 routes 0x1F80xxxx
  through the hw-register intercept and killed c318's dump), watches sh stores,
  and photographs the template table. Next: execute scratchpad stubs natively
  in the R680 path (mini fetch-decode-execute), like lzss-hle.

## Lesson 51 (c319, R744): digests cut tails — evidence rides at the top
- Symptom: R743's template-table photo (20 words) + scratchpad head dump RAN
  on the Mac but never reached the digest — digestcap keeps head-26KB/tail-10KB
  and the spstub block sat past the cut (the mid-line garble "head[0..0x20]:[crash]"
  shows the cut landed INSIDE the dump).
- Fix: dedicated =SPSTUB= grep section printed FIRST in the digest (before
  =HEAPFIX=), budget 40; new [fcb16] probe rides it.
- VERDICT on c319 evidence (settles the stub theory): the tail-jump target
  sp[0xB0] holds EAB80478/000000F0 — coordinate DATA, not code. The "stub"
  was never a stub: the entry copies 3 coordinate records (14 halfwords) from
  a template table @0x800AA3F0 into sp[0xA0..0xB6], the helper transforms
  them, and jr r7 into the data means the RECORD SELECTION was already wrong
  upstream: the entry picks its record via [r16+0x50] and r16 ARRIVED AS ZERO
  (read of [0x50] = kernel garbage area). The real bug = r16 at the field-cb
  dispatch, set by the caller chain (crashkit now names it: RunKernelMenu ->
  fn_80019BFC trampoline -> cb). R744 photographs r16/r17/index/table at the
  cb's own door.

## Lesson 52 (c320, R745): r16=0 at the field-cb door — bypass-clause fix
- CONFIRMED by the [fcb16] photo (digest top): the field coordinator entry
  (0x80077E88) is dispatched with r16=00000000. It reads its record index from
  [r16+0x50] (kernel garbage area), its table pick collapses, and the helper
  tail-jumps to sp+0xB0 which holds coordinate data -> unresolved jump.
- Seven cycles on the scratchpad wall (c313-c320) = the wall is OLD; per Jos's
  day-4 plan the BYPASS clause engages: stop native-entry archaeology, fix in
  the translated build we own.
- Fix: [fcbfix] heals r16 at the cb door to 0x800596E0 — the kernel dispatch
  loop's OWN live value for this era (descw2 receipts #2-7: r16=0x800596E0 /
  0x80059658 family = the state structs). Loud log + the [fcb16] truth probe
  stays on the healed value; next cycle's cells photo verifies the index math.
- If the healed struct proves wrong, the same photo names the correct struct —
  the heal is one line, re-targetable in one cycle.

## Lesson 53 (c321, R746): the r16 heal WORKED — wall down, retarget splinter
- VERDICT c321: [fcbfix] healed r16 and the field-state walk COMPLETED —
  the run went 204s (10x the old 16-25s), field cb entered AND returned,
  kernel did its console-faithful 3-boot dance, and the game loaded content
  never reached before (file#3 155KB in boot 2, first-ever file#17/#18
  lookups, stepper members 10/11). Deepest disc state ever.
- One recoverable splinter: 0x800596E0's +0x50 cell = 0x808C8C63 (misaligned
  garbage — wrong struct layout), so the entry computed a wild r4 and faulted
  ONCE at the field door; the fault-recovery routing (kernel exception exit
  0x800578DC, recovery 1/16) caught it and the walk ABSORBED it and continued.
- R746: retarget the heal to 0x800592B8 = the field's OWN queue-node struct
  (regs2: node(18090)=800592B8 — the kernel's literal field descriptor;
  its cells are the mount-family: 92BC latch, 92C0 cur, 92C8, 92D0, 92E8).
- Meta-lesson: when a heal works but faults, DON'T revert — RE-TARGET with the
  next-best-evidence candidate and keep the camera on. The photo of the wrong
  struct's cells is what names the right struct.

## Lesson 54 (c322, R747): tripwire honored — the bypass is AT THE DISPATCH
- c322 verdict: R746's retarget (0x800592B8) gave index 0 = the SAME broken
  record = the original fatal sp-jump crash returned (run died 16s; c321's
  204s came from R745's EARLY crash being absorbed by the game's own
  exception-exit recovery — the walk restarted healthily). Neither heal made
  the field ENTER; 10 cycles on the wall = tripwire.
- DAY-4 BYPASS (Jos's clause) executed to its end: stop fixing the entry's
  un-translatable tail; complete the CB AT THE DISPATCH. R747 = idempotent
  post-emit patch (R224 precedent) splicing an early clean `return` at the
  top of fn_80077E88 in the EMITTED disc1.c + #include <stdio.h> (header
  lacks it — -Werror would kill implicit fprintf).
- The kernel dispatcher sees the field cb "run and return" every frame; the
  state walk continues past state-1 (next states: 0x8001B6C4, 0x80070CFC,
  0x80088E90, 0x8001C634, movie 0x800737EC) = NEW TERRITORY.
- Meta: when a fix-class experiment regresses (R746 < R745), don't oscillate
  between candidates — count the wall and switch STRATEGY per the tripwire.
  Probe line = [fcbdone] R747, digest =SPSTUB= section.

## Lesson 55 (c323, R748): escape layers kill nested-heredoc code splices
- SYMPTOM: R747's inline splice inside run.sh's python-inside-quoted-heredoc
  turned the C string escape into a REAL newline mid-literal -> disc1.c:6693
  "expected expression" + cascading "expected '}'" — and the idempotent gate
  would have kept the broken text in the cached disc1.c FOREVER.
- ROOT CAUSE: two escaping layers (outer python writing run.sh, inner python
  in the heredoc) — each layer halves backslash escapes; the C payload needs
  the raw two-char sequence backslash-n to survive both. Verified twice: the
  bug reproduced in my own data-file writer (write_file's JSON content did
  the same halving).
- FIX (R748): (1) code payloads for splices live in a PLAIN DATA FILE
  (patches/r748_ins.c) read verbatim at patch time — ZERO escape layers;
  (2) the patch REPAIRS first: removes the known broken block (marker
  '{ /* R747 field cb completion bypass' .. 'return; }') then re-applies
  clean; (3) end-to-end simulation in the sandbox (mock broken disc1.c ->
  repair -> apply -> compile) BEFORE shipping. All verified green.
- PRE-FLIGHT CHECK (new): any run.sh heredoc that WRITES C code must source
  its payload from a data file and prove it compiles in the sandbox.

## Lesson 56 (c324, R749): unconditional bypasses break boot contracts
- SYMPTOM: R748's instant-return at fn_80077E88 fired on the cb's FIRST
  dispatch (t=0, all state cells 0) - that call is boot INITIALIZATION (the
  real body parks module setup). Skipping it unwound main at 2s: zero ticks,
  zero reads, "main-returned-region" exit.
- RULE: a callback that runs in MULTIPLE eras has a per-era CONTRACT. Never
  bypass blindly - gate on era state (here: cur(92C0)>=1 or idx(FAEC)>=1 =
  the field-committed era where the sp-jump crash lives). The boot-init call
  must run the real body exactly as before.
- R749: gated bypass; R748 repair-removal included in the splice (surgery
  pattern from R748 reused). Sim (mock -> repair -> apply -> compile) green
  before ship.

## Lesson 57 (c325, R750): splice anchors must target DEFINITIONS, not names
- BUG (2 cycles lost to it): R748/R749 anchored on 'static void
  xenolift_fn_80077E88(void)' - the emitted disc1.c contains that string
  TWICE (forward DECLARATION near top + real DEFINITION later). find() hit
  the declaration; the gate landed in an UNRELATED function's body (first '{'
  after it). The real fn ran ungated -> the sp-jump crash returned exactly
  as before (c325 receipts: sh-writes + wildctx + crashkit all at t=15s,
  no [fcbdone]).
- CORRECTED INTERPRETATION of c324: the boot unwind was NOT a field-cb init
  contract - the R748 unconditional gate landed in the wrong function and
  early-returned IT at t=0 (its [fcbdone] print fired from there). Lesson
  56's era-gating stays (it is principled), but its evidence story was wrong.
- FIX (R750): (1) remove stale blocks by EXACT TEXT (read the ins data file
  and replace) - robust regardless of where the old block landed; (2) insert
  at the DEFINITION: scan ALL occurrences of the signature, pick the one
  whose next non-space char is '{'; (3) post-insert VERIFICATION in the
  splice itself (gate text must be adjacent to the definition, before XTRACE);
  (4) sim must include BOTH declaration and definition - a definitionless
  mock cannot catch anchor-class bugs (my R748/R749 sims passed while the
  real file failed).
- PRE-FLIGHT RULE (extends 55): splices into generated code verify against a
  mock containing the file's REAL structural features (declarations AND
  definitions), and the splice self-verifies position at apply time.

## Lesson 58 (c326-c327, R751): alive runs drown the digest - cap ALWAYS
- SYMPTOM: two consecutive cycles posted EMPTY digests ("--- digest ---"
  then nothing). Build clean (R750 splice self-verified), run ALIVE 165-166s
  past the old 15s crash point - the field-era run writes a log far bigger
  than any crash-era run, and the digest block (105+ greps, some on the raw
  log) could not finish inside the bridge's cycle deadline. No [digestcap]
  line appeared = the block died mid-assembly (the R735 cap step never ran).
- FIX (R751): the >20MB-conditional storm-swap is now UNCONDITIONAL: head
  16k + tail 16k lines into run.log.d, swap in as run.log (raw kept as
  run.log.raw), and the digest announces its own start + both sizes
  ("[digest] R751 log raw XB -> capped YB"). Every grep then reads a small
  file. ALSO: milestone-watch runs must budget for the digest (RUN_BUDGET
  150s, not 205s) so assembly starts with runway left.
- RULE: every log-producing probe family needs a digest-side counterpart
  that assumes the WORST case (alive-and-spamming), not the crash case.

## Lesson 59 (c328, R752): idempotent patches must also be NO-CHURN
- SYMPTOM: every cycle burned 74s recompiling disc1.c even though emit was
  cached - the R750 splice exact-REMOVED its own block then re-applied it,
  rewriting disc1.c every cycle. With a 153s alive run, compile+run = 227s
  left only 13s for the digest -> the bridge's 240s watchdog killed it
  ("hung run") and c328 posted only the watchdog line.
- FIX (R752): presence check FIRST - if the gate is present and healthy,
  touch NOTHING (compile cache stays valid; build drops to ~5s). Removal +
  apply only run when the gate is actually absent. Sim: apply-then-rerun
  leaves the file byte-identical.
- RULE: idempotent != no-churn. Any patch that rewrites a cached artifact on
  every run invalidates the very cache it depends on. Presence-check-first
  is the pattern for ALL future post-emit splices. Plus: digest budget =
  watchdog_deadline - build - run; pick RUN_BUDGET_S so the digest keeps
  >=60s of runway (this cycle: 90s run).

## Lesson 60 (c331, R753): the game's CD state block is 0x8004FE00, not 0x80059FE00
- FACT (from the emitted code + exitdiag source): the archive/CD state cells
  (FDE4/FDE8/FDF8/FDFC/FE04/FE08/FE14/FE1C/FE20/FE34) live at 0x8004Fxxx.
  The emitter's "lui 0x8005 + lw disp" patterns resolve there because the
  int16 displacements (0xFDF8..0xFE34) are SIGN-EXTENDED negative. F0C/F10
  are a separate block at 0x80059Fxx. My first watcher draft read 80059FExx
  (caught pre-ship by cross-checking exitdiag's actual cell arguments).
- RULE: when naming a cell from an abbreviated receipt (FE20=3 etc.), ALWAYS
  resolve the full address from the probe that printed it before writing a
  new probe that reads it.
- c330/c331 evidence pattern: FE04 (field file index) 17->25 advanced in 90s,
  then held at 25 across a 180s AND a 200s run - budget bumps are exhausted;
  the next diagnosis must be era photographs (R753 file25w watcher, =FILE25W=).

## Lesson 61 (c332, R754): hook probes to the era's own cadence, not a guessed one
- R753's field-file watcher sat in park_tick and NEVER FIRED - even though
  the same digest showed restart steps firing every 2s through the whole
  marathon. The guest in the file-walk era is actively STEPPING (fn
  0x80019BD0 entries), not parked - park_tick doesn't run there. (The [wd]
  t= lines come from the SIGALRM watchdog, a different cadence source.)
- GOOD NEWS same cycle: file 25 was NOT a wall - the walk reached file 27
  (FE04=0x1B at exit, F10 crept 0x250200->0x270200). ~10-20s/file pace
  holds; budget remains the binding constraint until the table ends.
- RULE: before adding a watcher, ask WHERE THE ERA'S TIME COMES FROM - pick
  a hook that provably fires in that era (receipts in the same digest), not
  one that fired in a previous era. Era-gated probes go blind at era
  handoffs (Lesson bank: era-gated probes go blind) - the corollary is:
  cadence probes die at era changes too.

## Lesson 62 (c333, R755): FE04 is polymorphic + the stale-stack race is alive
- FE04 (0x8004FE04) holds the CURRENT LBA during sector loads (e.g.
  0x1A9F1=109041) and reads as a small file-index ONLY in the exit posture
  (17/25/27 in c330-332 exitdiags). A watcher gated on fe04 in [17,400)
  NEVER fires mid-run - gate on cd_seek_lba >= 109123 (file-17+ LBA range)
  for the marathon era instead.
- c333: the stale-stack race fault RETURNED (guest jumped through
  0x13B88422; R696 found the target sitting in stack cell 0x801FFF70,
  "writer trace next" from c311). Three clean cycles then one bad spin =
  probabilistic race, not deterministic. R755 ships the writer trace:
  nonzero writes to the band 0x801FFF40-0x801FFF80 log writer_fn.
- RULE: when a fault disappears for cycles and returns, DO NOT assume the
  fix that preceded the clean runs cured it - a race with p<1 looks cured.
  Cures are proven by MECHANISM (writer named + healed), not by absence.

## Lesson 63 (c333/c334, R756): the stale-stack race is a STACK COLLISION; walk depth is race-decided
- MECHANISM NAMED (R755 writer trace, c334 receipts): fn 8004D208 (task-table
  family) writes counter+hash pairs into stack-top cells 0x801FFF70/74 while
  fns 80046EFC/80045E44 push RETURN ADDRESSES into the same cells. Bad
  interleave -> the guest "returns" to a task hash (c333: 0x13B88422 found in
  0x801FFF70). Real-HW fidelity note: both writers are guest code; the
  collision depends on interleave TIMING, which our event injection influences.
- c334: no fault fired, but the walk LANDED IN THE STALE-MOVIE FALLBACK (exit
  FE04=14, FE1C=0x0B - c291-era path) after c330=25/c332=27. The mount handoff
  is race-decided: same package, three different landing depths. Variance,
  not a package regression - verify against receipt families before blaming a
  probe (reads-done 38 vs 60 = era evidence).
- R756: scrub-at-fault - when the garbage target matches a value in the
  0x801FFF40-80 band, zero the band before the kernel-exception routing so a
  retry reads clean cells. (Cheap, race-only blast radius: the band holds
  dead-frame values at fault time.)

## Lesson 64 (c335, R757): a bypass that saves a phase becomes the wall of the next phase
- c330-335 arc: the R750 gated bypass let the kernel walk complete (files
  25-27, three 200s runs = CEILING CONFIRMED, walk-complete posture). But
  the bypass made the field cb a NO-OP forever -> the field module's real
  body (init, drawing lists, render) never runs -> DMA2 still zero ->
  screen still black. The fix that unblocked the walk is now the blocker
  of the field. Phase-gated fixes must be RE-EVALUATED when their phase
  ends - a "walk phase" bypass needs a "run phase" contract.
- R757: bypass #1-8 (install window), real-entry #9+ (stage2 installed
  t~15s; R745/R746 heals armed; fault recovery budget 16 = the net).
  Receipts: [fcbdone] walk phase, [cbreal] real-entry era.
- Splice hygiene: exact-text removes fail on whitespace drift (c335) -
  marker + brace-scan removal instead. And: disc1.c changes cost a full
  75s recompile - the cycle budget must shrink to fit the watchdog
  (RUN_BUDGET_S=140 with recompile, 200 on no-churn cycles).

## Lesson 65 (c336, R758): splice fragments must be brace-balanced AND removal must know the block's balance
- c336 DEAD CYCLE (my miss): the R757 gate shipped MISSING ITS FINAL '}' -
  the block swallowed the rest of fn_80077E88 and every definition after it
  ("function definition is not allowed here" x3). My fragment syntax test
  used a wrapper whose own braces accidentally balanced it - eyeball AND a
  bad test passed a broken fragment.
- SECOND bug caught by sandbox sim before shipping: brace-scan REMOVAL of an
  UNBALANCED block cuts one '}' short (the bad block stole a close from the
  function; removal must return it - 3-brace scan for the net+1 R757 block).
- RULES: (1) every splice fragment asserts count('{')==count('}') in the
  build script BEFORE apply; (2) removal of a known-unbalanced block scans
  depth-aware (N+1 closes for a net+N block); (3) fragment tests must be
  self-contained wrappers that FAIL on imbalance (no accidental balance).
- Also: a bad block protected by the no-churn marker check poisons every
  future cycle - marker bumps (R757->R758) force removal+reapply of the
  fixed text.

## Lesson 66 (c337, R759): the scratchpad stub is written by the field cb itself — execute it, don't halt on it
- c337 RECEIPTS (the real-entry era ran!): [cbreal] #9, [fcbfix] r16 heal
  held, and — the sprint's biggest evidence — fn_80077E88 ITSELF installs
  the scratchpad stub (sh writes sp[0xA0..0xB4]: 140A 000C 2401 451B 0478
  00F0 115C 82FF EAB8). The months of "all-zero scratchpad" were OUR
  artifact: the R750-era bypass never let the stub-writing code run.
- The tail-jump to 0x1F8000B0 then hit the static-translation void: no
  compiled function exists at scratchpad addresses (dynamic code!), so
  xenolift_unknown hard-halted the run at 63s (halt_report).
- R759: bounded scratchpad executor in xenolift_unknown (64 instrs,
  delay-slot aware, GTE via hle_gte regfile, loud UNSUPPORTED receipts,
  service-as-return so the run SURVIVES either way). Static translation
  NEEDS a dynamic-code escape hatch: "binary in, C out" can't pre-translate
  runtime-written code - the runtime must execute it in place (this is a
  xenolift-product lesson, not just a game lesson).

## Lesson 67 (c338, R760): the crashkit names OUR probe, not the guest — read the line number
- c315-c338 (23 cycles!): every "jump into SCRATCHPAD" fault showed
  "[crash] resolved xenolift_unknown (runtime.c:12917)" — and we read it as
  "guest jumped into the static-translation void." NO: line 12917 WAS the
  R743 head-dump loop reading xenolift_mem + RAM_SIZE + 0x1F800000 =
  ~522MB OUT OF BOUNDS = host SIGSEGV inside our own probe. The guest's
  stub-jump was being handled (dump + would-be service); our probe killed
  the host before any service/executor/halt could run.
- RULES: (1) crashkit "resolved <fn> (file.c:LINE)" = read THAT line in the
  shipped source before theorizing about guest semantics; a probe at the
  crash line is the FIRST suspect, not the guest. (2) Scratchpad probe reads
  use PHYSICAL offsets (addr - 0x1F800000); every memcpy pattern
  "xenolift_mem + XENOLIFT_RAM_SIZE + <virtual>" is a latent host crash.
  (3) Pre-flight grep for the pattern in any code touching 0x1F80xxxx.
- R760: head-dump fixed (+off -> +(off-0x1F800000u)); R759 executor gains
  a pc-left-scratchpad guard (JR/J out of the 1KB window = service-as-return
  with receipt, never an OOB fetch).

## Lesson 68 (c339, R761): opcode tables get verified against the ISA doc, not memory — and the stub names itself
- c339 receipts (the executor RUNS, run survives full window, 2 restarts):
  [spexec] ENTER -> UNSUPPORTED op=58 word=EAB80478 on instr 1. Op 58 = SWC2
  ("store GTE reg 24 to 0x478(r21)") - I had LWC2/SWC2 labels BACKWARDS
  (shipped 48/50; actual: 48=LWC1(FPU), 50=LWC2(load->GTE), 58=SWC2
  (store<-GTE)). Lesson: opcode cases are copied FROM the ISA reference
  (psx-spx / MIPS-I table), never from memory; label every case with its
  numeric opcode in a comment.
- psx-spx verified (memory map): scratchpad = 1KB at 1F800000-1F8003FF, NO
  mirrors; 1F800400-1F80FFFF = bus-error gap; "scratchpad probably Data
  only, NOT code" - a guest jump INTO scratchpad is itself suspicious; the
  stub may be DATA read as code (r7 might be clobbered). Keep executing
  (service + receipts) - the trace IS the evidence.
- The stub (sp[0xA0..0xB4] = 115C140A 0000000C 82FF2401 0000451B EAB80478
  000000F0): first executed word = SWC2 store, next = 0x000000F0 (SPECIAL
  funct 0x30 = TGE-class) - decode pending; the executor's per-instr
  receipts now give TRAILBLAZER a full execution trace.
- NEXT NAMED WALL (visible in c339): after the stub service, the module
  crashes on a computed jump to 0x5 (c295 class) with the source region
  801D2D2C-801D2DAC ALL ZEROS - the module reads a pointer from an
  uninstalled region below its base. TRAILBLAZER's decode: what should
  fill 801D2D2C+ (module-adjacent table).

## Lesson 69 (c340, R762): the receipt-as-disasm — decode the guest's words FROM the probes we already ship
- c340: the entry's own code was already photographed by the coordb/R738
  probes (descriptor block @0x80077E88: 8E020050 3C04800A 2484A3F0 00021303
  000218C0 00642021 AE020054 84830016). Decoded OFFLINE from the digest:
  LW r2,[r16+0x50]; r4=0x800AA3F0; SLL 12; SLL 3 -> bank = 0x800AA3F0 +
  (index<<15) - a 32KB DATA BANK per index, not a 7-word record table.
- Lesson: BEFORE theorizing semantics, decode the photographed words at the
  fault/probe sites - the digest IS a disasm oracle when read as opcodes.
- c340 mechanism: nobody writes the node's +0x50 bank index (writers touch
  +0x08..+0x30 only) -> entry reads bank 0 -> wrong-record constants ->
  the transform helper computes deterministic garbage jump (0x6022D11C,
  IDENTICAL in c318 and c340 = input-deterministic, not state-dependent).
- R762: bank-1 trial fill ([r16+0x50] 0->1 at the cb door, loud [fcbidx]
  receipt) + bank-0..3 head dumps per cycle (identify content class without
  one-cycle-per-bank trials). SUCCESS CRITERIA next cycle: [spstub] sh
  constants CHANGE (bank 1 record) and/or helper target becomes RAM-valid.

## Lesson 70 (c341, R763): kill dead theories FAST with a cheap photo; the oracle search pays
- c341: the R762 bank trial + bank heads answered in ONE cycle what would
  have taken 3-4 one-bank-per-cycle trials: banks 1-3 at 0x800AA3F0+(N<<15)
  are ALL ZEROS - bank 0 is the ONLY populated bank. The "wrong record /
  wrong bank" theory is DEAD: the entry already reads the only real data.
  (Also: the fill to [r16+0x50]=1 did NOT change the copied constants -
  the entry re-derives or re-zeroes the index cell, OR r16 at body time
  differs; either way the index is not the lever.)
- The remaining live suspect: the module INSTANCE region 0x801D2D2C-
  0x801D2DAC (below stage-2 module base 0x801D3000) is ALL ZEROS - the ctx
  the helper reads before computing its garbage jump (c338: 0x1F8000B0,
  c340: 0x6022D11C, c341: 0x5 - target varies with era state, not bank).
- ORACLE FOUND: yaz0r/Noah = WORKING Xenogears decomp (field+kernel
  reimplemented, functional); ladysilverberg/xenogears-decomp = matching
  decomp for SLUS_006.64 (OUR EXACT BINARY - function names at our exact
  addresses); OpokXeno/xenogears-recomp docs = binary-format contracts.
  Next decode pass: read NoahLib/field + matching-decomp symbol names for
  fn_80077E88 + module init before writing more assists.
- R763 cameras: [instw] instance-region write watch (all writes incl.
  zeros - zeroing IS init), [modfn] module vtable dispatch watch
  (0x80072800-0x80073500, 0x80078000-0x80078200). Question answered next
  cycle: does module init EVER run?

## Lesson 71 (c342, R764): the tripwire + the service pattern — results-first bypass of a broken transform
- c342 camera verdict: ZERO [instw] (nothing ever writes the module instance
  region 0x801D2D2C-0x801D2DAC) and ZERO [modfn] dispatches in the whole
  203s run - the module constructor NEVER runs because the field cb dies at
  its transform helper's computed-garbage jump before reaching the vtable
  calls. ~30 cycles on this wall = far past the 10-cycle tripwire.
- THE BYPASS MECHANISM (from the emitter, verified in src/emitter.rs):
  unknown-target tail jumps translate to DISPATCH(a) = "do {
  xenolift_dispatch(a); return; } while(0)" - if the dispatcher RETURNS, the
  translated function returns to its caller. So a computed-garbage jump can
  be SERVICED AS A CLEAN RETURN: return from xenolift_io_fault (module-range
  cur_fn + module-range r31 guard) and the helper unwinds to the field cb
  entry, which continues to its next step - the same service pattern that
  worked for scratchpad jumps (spexec).
- WHEN TO USE: era-driven walls whose fix requires unverifiable state
  archaeology + a deadline = service the broken step (keep the walk moving)
  rather than perfecting it. Loud receipts + caps keep it diagnosable.
- R764: service capped 24, [fhelp] receipts. Success criteria: [modfn]
  lights up (module methods finally dispatch), [instw] writers appear, DMA2
  sends > 0, screen census moves. If the walk then faults ELSEWHERE (outside
  module range), the receipt names the next wall honestly.

## Lesson 72 (c343, R765): receipts must be CAP-PROOF; never let a diagnostic exit steal the window
- c343: the R764 service receipts ([fhelp]) vanished into the digest cap's
  eaten middle (head 26KB + tail 10KB of a 1.6MB log) - the service MIGHT
  have fired but the evidence is gone. RULE: every service/fix ships with a
  COUNTER SUMMARY printed at exit ([fhelpsum]) that survives any cap, plus
  guard-fail context lines ([fhelpmiss]) so a mismatch is diagnosable.
- c343 regression: the defensive handler at 0x800392EC fault-walked at t=42s
  and its exit(0) KILLED THE RUN 157s early (43s vs 200s budget). A diag-
  nostic exit must never steal exploration window: R765 converts fault-walk
  exits to capped guest restarts (churn anchor re-dispatches the boot entry,
  4 max) - the kernel's own crash pattern on real HW is a shell restart.
- Also c343: epoch-1 boot arrived at t=33s vs t=61s in c341/342 - the R764
  service DID change the flow (epoch-0's helper-class fault ended the epoch
  ~28s earlier), consistent with the service firing in the eaten middle.

## Lesson 73 (c345, R766): cache-masked regressions — post-emit patches must be SELF-CONTAINED
- c345: EMIT_REFRESH=1 forced the first fresh emit in ~20 cycles - the whole
  field module translated (135168B @0x8006F000, 31775 nonzero words; R682
  proof shows REAL code at the coordinator entry: 8E020050 3C04800A ...).
  But the build FAILED: the R758 bypass patch calls fprintf/stderr and a
  fresh disc1.c never declares stdio - the old cached disc1.c had it from an
  earlier patch era and MASKED the dependency.
- RULE: post-emit patches must be self-contained (declare their own deps);
  whenever an emit-cache path is bypassed for the first time in N cycles,
  EXPECT the cache to have masked a dependency - budget for one fix cycle.
- R766: idempotent stdio-ensure before any patch lands + write-back guard
  on the no-churn path (a modification must persist even when the patch
  itself is a no-op).

## Lesson 74 (c346, R767): services must be wired into EVERY fault router
- c346: with the module fully translated, [fhelpsum] still showed services=0
  misses=0 — because the 0x5 garbage jump faults at the stage-2 crash-site
  (cur_fn 0x801D2D6C) and routes through xenolift_unknown, a DIFFERENT fault
  router than xenolift_io_fault where the R764 service lives. Two routers,
  one service = the service never sees the fault.
- RULE: a fault-path service must be installed in EVERY router that can
  deliver its fault class (io_fault, unknown-jump handler, sp-jump handler),
  or - simpler - enumerate the routers and put the service at each entry.
- R767: clean-return service added to xenolift_unknown covering all three
  module contexts (window-0, stage-2, and the instance band below stage-2
  base where cur_fn observed), with [fhelpmiss] context lines for r31-range
  faults whose cur_fn sits outside the windows.

## Lesson 75 (c347, R768): zero-state modules emit garbage SEQUENCES — service the sequence, fingerprint the missing init
- c347: the R767 service fired for the 0x5 jump (first clean pass of the
  broken transform in project history), and the walk's VERY NEXT step
  computed a jump to 0. A module whose instance/working memory was never
  initialized doesn't fail ONCE - each successive step computes a new
  garbage target from the same zeros.
- STRATEGY: service the whole sequence (word==0 included, module-window
  guarded - no legit code jumps to 0 from inside a module), and treat each
  receipt's (target, cur_fn) as a FINGERPRINT of one cell the missing
  constructor init should have set. The receipt chain = TRAILBLAZER's
  decode list for the real fix.
- Proof receipts matter: without [fhelp] the sequence would have been
  invisible (each fault previously ended the era in a restart).

## Lesson 76 (c348, R769): cache keys must hash ALL inputs — and halt doors must not steal the window
- c348: the module-helper service fired natively for the first time
  ([fhelp] cur_fn=0x80076858 = the TRANSLATED helper, target 0x6022D11C
  computed from zero state, serviced twice) - capture-compile pipeline now
  works end-to-end. Follow-up: the emit cache hashed ONLY the Rust tool, so
  the capture files (pipeline INPUTS) could change silently with no fresh
  emit. PRODUCT RULE: a cache key must include every input it protects.
- c346-348: the halt-scan exit (break/coproc/unknown fault doors) killed
  the run at t=71s each cycle - 130s of the 200s budget gone. R769: halt
  doors get the same capped churn-anchor restart as the fault-walk door
  (cap 4 shared, dumps preserved; the budget-park path is a separate
  graceful door and does not route through halt_report).

## Lesson 77 (c349, R770): restarts inherit state - a guest restart is only as clean as the memory it re-enters
- c349: the halt-door restarts WORKED mechanically (3 conversions fired)
  but burned all 4 caps in one second - boot entries #3-#6 all at t=43s
  with garbage r16, each dying instantly. Root cause: the churn anchor
  re-entered boot on crash-corrupted memory. The fault-walk restarts that
  DID survive (c346-349 boot #2, 8+ seconds of exploration) only worked
  because the R722/R724 pristine-image relay restored the exe image
  first - invisible hygiene riding along on a different path.
- RULE: any new guest-restart path must ship the full state hygiene the
  proven paths use (pristine image restore + resume-key clear), not just
  the longjmp. Adjacent mechanisms that "happen to run" on another path
  are not part of your path.

## Lesson 78 (c350, R771): the console reboots on ITS OWN alarms too - exit doors need kind-aware restart policy
- c350: R770's hygiene worked (halt-door restart restored the image; the
  restarted boot #4 ran 30 SECONDS of real walk, F0C 3->5->7, new disc reads
  LBA 3/108865/0 - deepest epoch-1 exploration on record). But the run
  still ended at 78s: the kernel's WATCHDOG-ALARM exit reached the atexit
  door with the walk flags zeroed (fresh-boot state), so the R692 restart
  condition (92C0/FAEC field-work check) never fired.
- RULE: enumerate the exit KINDS and give each door a restart policy
  matched to what the console would do. The kernel's own alarm reboot is
  a SHELL RESTART on hardware - not a process death.

## Lesson 79 (c351, R772): fault-routers that re-enter guest code can recurse silently - guard re-entry, hygiene every door
- c351: the field install COMPLETED at t=19s (fastest on record, R651 DONE
  posture) and the alarm-restart fired - but the run died at 23s with NO
  exit receipt. Root cause: the crashkit routes computed-garbage faults to
  the guest kernel exception handler (0x80032EB4) as GUEST CODE; the
  handler runs on broken state, faults again, re-enters the crashkit, and
  the recursion silently consumed the thread stack. Silent death = no
  receipt = invisible failure mode.
- RULES: (1) any fault router that dispatches guest code needs a re-entry
  guard - second entry falls through to the restart conversion. (2) EVERY
  restart door ships the full hygiene (image+key); the crashkit's R765 door
  had been running bare (Lesson 77's rule applies to all doors, not just
  the new ones).

## Lesson 80 (c352, R773): serviced faults must leave decode material too
- c352: the module's OWN init code ran natively for the first time
  (0x800739A0: writes its config cells 0x80077120-2C8, calls helper
  0x800439E0) then computed jump 0x8009A2F8 past module bounds - serviced
  cleanly, but the service gave only target+cur_fn: NO code dump, NO regs.
  The crashkit's wildcode dump fires only on UNSERVICED faults - so the
  more the services work, the BLINDER the decode gets.
- RULE: every fault disposition (halt, restart, service) ships the same
  decode material: regs + fault-site code + caller code.
- ALSO c352: the self-healing window is COMPLETE - full 202s run, fault-
  walk restart with image hygiene, alarm restart, halt-door restart, all
  clean; fldsec explored LBA 239320 + file#18->0x801EFC94 +
  file#14->0x801D0BD8 (new destinations) = deepest disc reach ever.
- Lesson 81 (Sep 14, c353): the R771 alarm-restart guard required epoch>=1, but the fault-walk restart door never increments xenolift_boot_epoch - post-restart alarm exits read epoch=0 and the run died at 39s. NEVER condition a restart door on a counter that other restart doors do not maintain. Fixed R774: alarm condition keys on g_exit_why only.- Lesson 82 (Sep 14, c354-c357): MY OWN ZIP REGRESSION caused 4 stale bridge cycles - the r774/r774b/r775 packages were built with a plain os.walk (NO exclusions) and shipped 75MB (459MB uncompressed: r1/r2/r3/clean.log ~20MB each, disc1.c copies, .cache). The bridge download silently failed on size and kept re-running the last GOOD package (R773, 2.8MB). Every working ship in project history used the exclusion walk (skip .zip/.iso/.o/.md5/.bin/.log, disc1.c/disc1_fresh.c, boot binaries, .cache/target/__pycache__, >3MB files). RULE: ship zip MUST be <3MB; verify size BEFORE upload; a stale banner for 2+ cycles = CHECK PACKAGE SIZE FIRST, not the bridge.
- Lesson 83 (Sep 14, c362): TWO self-inflicted digest killers in R778: (1) my new =DIR2=/=BANKW=/=FTAB2= sections grepped the RAW run.log (GB-scale) instead of the capped run.log.d - rare-match greps scan the entire raw log and stall the assembly past the bridge timeout (3rd empty digest). RULE: digest sections grep run.log.d ONLY; raw-log greps need head-early-exit AND common matches to be safe. (2) The emit fault-capture fold gate (>1000 nonzero words) accepted a PRE-EXPANSION capture (coordinator entry zeroed) - the R682 proof line WARNED but the damage shipped (blank coordinator compiled into disc1.c). FIXED R779: emit REJECTS zero-coordinator captures (keeps pre-menu mapping); a warning receipt without a guard is not a fix.
- Lesson 84 (Sep 14, c364): EMPTY DIGESTS = CYCLE-TIME problem, not log-size: every empty digest (c359/360/362/364) was a 241-242s cycle, every full digest was sub-220s — the bridge window is ~240s and the digest POST dies past it. Cause: the R769 capture-md5 emit gate churned a fresh emit + 77-110s recompile EVERY cycle (era data inside captures varies per run). Fix R781: emit gate keys on each capture's NONZERO-WORD COUNT (the module-code signature: 31775/32450 stable across same-era runs) — stable era = cached emit = 4s cycles; genuine capture shift = auto fresh emit. RULE: pipeline gates hash what MATTERS (code signatures), not raw bytes; and cycle total must stay under the bridge window (~240s) or the digest is lost.
- Lesson 85 (Sep 14, c366): POISON-BEATS-BLANK class: the R779 capture guard checked only for BLANK (zero) coordinators, so the c365 ASCII formatter's TEXT spray (0x30303030x4) passed as 'live code' and got folded into disc1.c — the entire module translation became ASCII, the guest hung, watchdog killed the cycle at 240s with NO digest. TWO-LAYER FIX (R783): (1) emit-side: coordinator poison predicates — coord_text (>=12 nonzero bytes all printable ASCII) + coord_same (4 identical words); BASE capture allows zeros (module installs later, R681 premise), fault captures require real code; (2) capture-side: the runtime NEVER overwrites a good capture with a poisoned window ([ovlfault]/[fldcap] refuse text/same/zero, [ovl] base refuses text only). RULE: validate captured data like untrusted input — a snapshot is a claim, check it against a code-shape predicate before treating it as code.
- Lesson 86 (Sep 14, c369): FINGERPRINT > SHAPE for capture validation: every shape predicate (zeros R779, ASCII/text R783, 4-identical R783) was beaten by a mixed-garbage capture (14217 nonzero words, coordinator EBE10222/543DAE66/3FFCCCE1/B142E144) — the smoking gun: the RUN's fault jump targets matched the folded snapshot words EXACTLY. The real coordinator prologue is STABLE MODULE CODE (8E020050 3C04800A — every healthy era + the runtime fldreloc expansion agree). R786: both the emit fold gate AND the runtime capture writes demand the exact known-good prologue; anything else = wrong-moment capture, never folded, never overwrites a good capture. RULE: when a known-good reference exists, validate against IT — 'not obviously bad' is an open-ended treadmill of poison classes.
- Lesson 87 (Sep 14, c372): STABILITY-GATE ALL CAPTURE FEEDS: window-0 was fingerprint-gated (R786) but stage2_region.bin promoted UNCONDITIONALLY every run - era-noise drift (1-4% nonzero variance per run: 32050/32450/33791 words) changed the emit signature EVERY cycle, forcing perpetual fresh emits; c372's compile alone hit 232s and the digest died before the run started (banner no-runlog, zero evidence). R789 two-part fix: (1) promotion gate - only re-promote stage2 on >20% nonzero drift (genuine era jump); small drift keeps the compile cache valid; (2) DYNAMIC window cap - run budget = what REMAINS of the ~200s bridge window after compile (20s digest margin); if <=10s remain, skip the run and preserve the build digest. RULE: every capture feed needs a stability policy (fingerprint or drift gate) AND time budgets must be computed from REMAINING time, not flat defaults.
- Lesson 88 (Sep 14, c374): GATE EVERY CAPTURE FEED, NOT JUST THE ONE THAT BIT: R789 gated stage2 promotion but the BASE overlay capture (overlay_region.bin, written every run at boot-main entry #2) still drifted ~1% per run (31753 -> 32072 nonzero words) -> fresh emit AGAIN (233s compile, R789 dynamic cap correctly skipped the run and preserved the digest - the safety net worked). R791: same >20% drift gate applied to the base-capture write; missing/blank file still rewrites; poison gate (R783) still applies on top. RULE: when adding a stability gate, ENUMERATE ALL capture/probe feeds that sign the emit signature or budget - fix the CLASS in one pass (fingerprint-gated fault capture, drift-gated stage2 + base overlay = the complete fold feed set).
- Lesson 89 (Sep 14, c376): A FINGERPRINT GATE IS NOT A STABILITY GATE: the fault capture passed the R786 coordinator-prologue fingerprint every cycle, yet its content BEYOND the prologue drifted 0.04%/run (31775 -> 31763 nonzero words) - the whole file signs the emit signature, so a partially-gated feed still churns. Lesson 88's 'complete set' claim was wrong at the file level. R793: drift gate (>20%, missing-file rewrite) on BOTH overlay_fault.bin write sites (R681 fault-moment capture, R686 relocation re-capture), stacked ON TOP of the prologue fingerprint. RULE: for each capture FILE, enumerate every WRITER and gate the file's full content, not just the trusted region; fingerprint = authenticity, drift = stability - both needed per feed.
- Lesson 90 (Sep 14, c377): A NEGATIVE SCAN MUST ENUMERATE THE MECHANISM: the R792 misalign scan assumed the module calls were DIRECT jal instructions - 0 hits \proved\ misalignment; c377's receipts (caller r31=0x801D3008 with no matching jal word) show the calls are INDIRECT (jalr through registers). The scan was a valid hypothesis test, but its negative only rules out the DIRECT mechanism. RULE: before drawing conclusions from a probe negative, list every mechanism that could produce the observation (direct jal / jalr / jr-through-table / stale r31) and probe the next one; when the target is known but the source is not, instrument the universal chokepoint (the entry hook already records the arrival path - use the existing trail instead of inventing a new mechanism).
- Lesson 91 (Sep 14, c380): DERIVE GATE RANGES FROM THE OBSERVED FAMILY, NOT A GUESS: the R796 LZSS-family gate ceiling (0x40000) was invented from f15 (0x2C0C6); file16's header 0x00053F80 printed gate=no even though it is plainly the SAME family as f14 (0x0003FAFE) / f15 (0x0002C0C6) — the ceiling was too low by inspection bias. RANGE FIX: family header = 0x00XXXXXX where size-bits = expanded byte count, plausible band 0x0800-0x80000; ceilings must list the observed members before judging. RULE: before writing a numeric gate, enumerate every known member of the class and set the range from data. SECOND: verify the tool-call actually landed (a python SyntaxError in the same block as a file write ABORTS the write silently — the R797 probe missed its first insert and only banner/gate landed; zip content verification caught it).
- Lesson 92 (Sep 14, c382): A FIX THAT CHANGES THE TRAJECTORY CHANGES THE LOG VOLUME - RE-AUDIT PIPELINE COSTS AFTER BEHAVIOR CHANGES: the file17 band fill (R797) made the interpreter walk REAL code instead of faulting through zeros - the run log volume exploded (no more fault exits; continuous walking) and the digest block's size probe (wc -c on the RAW log - a FULL sequential read) alone blew the 240s bridge deadline: cycle killed, digest LOST, one full cycle of built-band evidence burned. RULE: after any change that plausibly alters loop/trajectory behavior, audit every pipeline stage's WORST-CASE cost on the NEW input (file-size probes must be stat, not read; unbounded reads on logs must be pre-trimmed); 'digest always generates' is a postcondition to TEST per trajectory, not an invariant to assume.
- Lesson 93 (Sep 14, c385/c386): ROTATING RECURSION ESCAPES SAME-FN BOUNCE GUARDS: the guest print-helper trio (800409E4->800409EC->80040A4C) recursed WITHOUT returning - the R323 churn bounce only catches the 0x8002A600-B400 family, and R320 only forces halt on same-fn churn, so a 3-fn rotation cycle grew the host C stack ~14M dispatches deep until the 2048MB thread stack hit its guard page -> host SIGSEGV at host_pc -> PROCESS DEATH (no park, no digest tail). RULE: recursion guards must be STRUCTURE-AGNOSTIC - a pure depth measurement (any fn entered deeper than N) catches every rotation, same-fn cycle, and tail-call chain in one check; per-family and per-pattern detectors each leave a hole the next variant walks through. SECOND: the process-death class (no [wd], no exit receipt, tiny raw log) is now diagnosable in one cycle via =CRASH2=/=LASTLOG= (c385 burned diagnosis on the cut middle).
- Lesson 94 (Sep 14, c385/386/388): WILD GUEST POINTERS MUST NOT KILL THE HOST - EMULATE THE CONSOLE'S BUS EXCEPTION: the process-death class was NEVER stack overflow (R803 depth guard stayed silent) - it is the guest dereferencing CORRUPTED POINTER CELLS (c388: cell 0x80068934 held a wild value; the getter fn_8004B8BC's LHU through it indexed the host array far OOB -> host SIGSEGV -> death). A real PS1 has no segfault: a wild deref raises a BUS EXCEPTION and the kernel handler at 0x800578DC RECOVERS. R804 converts host SIGSEGV/SIGBUS into the hardware-faithful path: print receipts, longjmp to the churn anchor (setjmp at the guest thread base), which restores the pristine exe image and re-dispatches boot entry - capped at 8 recoveries, handler-reentry guarded. RULE: translated code without a bus can turn any guest data corruption into process death - the recovery path must exist BEFORE the corruption is understood.
- Lesson 95 (Sep 14, c389): A RECOVERY PATH MUST LIVE IN THE HANDLER THAT ACTUALLY FIRES: R804 put the SIGSEGV recovery in xenolift_exitdiag_sig — but the crash-KIT handler (segv_handler) owns SIGSEGV, so the kit printed its dump and _exit(99)'d while the recovery code never executed (=SEGvREC= empty, run burned at 31s). Verify handler OWNERSHIP before installing recovery logic: signal(SIG...) installed later wins; the crashkit's sigaction shadows main's signal() calls. The recovery now lives inside segv_handler itself, after the dump, using the kit's async-safe printer (no fprintf in signal context — only the crashkit crash_puts/crash_puth). c389's fault class: NULL method-table cell (0x800568C8=0; boot trampolines' jalr at host_pc=0) = catch-and-recover on hardware.
- Lesson 96 (Sep 14, c391): THE LAST DEATH DOOR WAS OUR OWN HALT: rungasp named it - exit 134 = SIGABRT from xenolift's own 'HALT: unknown instruction / unresolved indirect jump' (the R680 field-committed restart didn't apply; fallthrough killed the process). On hardware a garbage-target jump is a CPU EXCEPTION, not a shutdown - every fatal path in the runtime must route to the recovery anchor (pristine-image restore + boot re-dispatch) BEFORE halting. R807 converts the halt fallthrough: receipt [jumprec] + longjmp, cap 8. SECOND: the rungasp wait-status camera (R806) diagnosed in ONE cycle what 3 cycles of crash-kit forensics could not - a cheap host-side fact (exit status) beat deep in-process instrumentation. THIRD: c391 also showed real progress under the crashes: a GPU drawing list was SENT (dma2 from 8005A238), pad polling went ACTIVE ([bpad] StartPAD), and the c389 null cell (0x800568C8) held a healthy 16-method table this run - transient corruption family.

## Lesson 90 (Sep 14, c411): duplicate-anchor section insertion
- Symptom: R825 shipped [fldfrz2] camera code but =FLDFRZ2= never appeared in the digest; banner said R825.
- Cause: run.sh contains TWO digest blocks (a stale/duplicate block ~line-36K with old tags, and the live tail block). A string-anchored `replace(old2, ...+old2)` hit the FIRST `echo "=FLDFRZ="` (dead block). The zip check only verified the tag existed anywhere in the file -> false pass.
- Fix: anchor digest-section insertions on the FULL unique echo+grep line from the LIVE tail block (verify count==1 before replacing); verify in-zip that the new line sits between known live neighbors (=DASHFIX= and =FLDFRZ=).
- Prevention: pre-flight check for every new section = full-line anchor + neighbor-order assertion in the zip verification.

## Lesson 91 (Sep 14, c416): disposition clobbers — assert on a heartbeat, don't hunt
- Symptom: c416 deep abort died at 31s (exit 134) with NO handler receipt — SIGABRT was SIG_DFL at delivery, but c415 proved the handler+recovery works. Someone re-arms only in some trajectories.
- Hunt exhausted every candidate (translated code: no sigaction/signal/abort/raise at all; run.sh: only kill -9; runtime: single install at main; no SIG_DFL anywhere).
- Fix: stop hunting — assert. The existing 1s host-cadence watchdog (R825) now re-installs all crash dispositions every tick and receipts a detected SIGABRT clobber with its t=. Exposure shrinks whole-run → <1s, and the receipt timing identifies the re-arming era/door next cycle.
- Prevention: when a flag/disposition hunt exhausts all candidates, move the fix onto an existing host-cadence heartbeat with a clobber receipt — mechanical over forensic when the search space is unbounded.

## Lesson 92 (Sep 14, c419): receipts print only the truth — place them after recovery branches
- Symptom: the R832 "NO-RECOVERY real death" receipt fired in c419 while the run RECOVERED and lived to the fuse — the print sat before the R824 recovery branch, so it fired on every signal, recovered or not.
- Rule: a state receipt must print only the outcome that actually happened. Death-reason receipts go AFTER every recovery branch has declined; when a condition is checked in two places, precompute it once so print and branch cannot drift apart.
- Prevention: when adding a diagnostic receipt, ask "can any path print this and then NOT die/recover?" — if yes, move the print.

## Lesson 93 (Sep 14, c421): one package per turn — a second upload under the same banner is indistinguishable at run time
- Symptom: c421 ran the FIRST R835 package (no =F5DUMP= section, no FE48 heal) even though the later, complete package was uploaded minutes after; both share banner R835, so the digest cannot prove which ran until a missing section gives it away.
- Rule: NEVER upload a second package under the same banner in the same turn. If more work lands after an upload, bump the banner (R835b/R836) or fold the work into the next cycle's package.
- Prevention: pre-flight check now includes "one zip file uploaded this turn, banner unique among this turn's uploads."

### Lesson 94 (c431, R843): printf format/arg parity — the uncatchable canary
- SYMPTOM: .ips chain `__stack_chk_fail <- __xvprintf <- vfprintf_l` + "stack buffer overflow" = a stack canary trip INSIDE libsystem's own print machinery. Our R840 `__stack_chk_fail` override only binds for OUR translation units — libc-internal canaries die silently, no receipt.
- ROOT CAUSE: a receipt with MORE format conversions than arguments (`[reloc] a0/a2/count/w[0..3]` = 7 convs, 6 args). On arm64 the extra va_arg read walks past the argument list into the print machinery's frame — smashing its canary mid-print.
- FIX: R843 — every conversion gets exactly one argument; count= now prints r[7].
- PREVENTION CHECK: before shipping, audit EVERY fprintf/snprintf with a format/arg counter that JOINS adjacent string literals (split-literal formats mislead naive counters) and verify parity per call; any needs>got = blocker. Caveat learned same day: audit scripts have their own bugs — a direct targeted recount of any flagged line is the confirming instrument.
- NOTE: the c427 canary catch (our TU, cur_fn=80041B24) is a DIFFERENT smash site (host-side buffer overrun caught+recovered). Two distinct stack-smash classes exist; this lesson covers the libc-internal print class.

### Lesson 95 (c432, R844): the backup plan — force the era jump, stop re-feeding the boot door
- DECISION (Jos, 16:37, c432): "Let's go with back up plan now. This obviously is not working" — the 09:00-17:00 recompilation window closed early; the boot-manager coaxing era is over.
- EVIDENCE BASE: 40+ cycles of the fault-walk loop at 0x80019524 — entries #1-#8 walked, abandoned, restarted; boot epoch never advances; no era handoff ever fires.
- R844 BYPASS: at the churn anchor, after >=4 fault-walk restarts with pend==0x80019524, stamp the proven R814 proceed posture (FAEC=1, 92C0=-1, 92BC=1, 92D0=0, 9330=1, 9320->0x800592B8) and dispatch the REAL field-coordinator door 0x80077E88 directly (R681 mapping / R748 fcbdone / R758 emit bypass — all proven at that door). Cap 4 bypasses/run; anchor stays live for crash-kit recovery.
- RULE GOING FORWARD: the bypass is the primary path now; native boot-loop fixes resume only if the bypass proves the coordinator needs more state than the stamps provide (then the stamps tell us WHICH cells the coordinator checked).

### Lesson 96 (c433, R845): a working bypass must also convert parked time into progress
- RESULT (c433): R844 door-force FIRED and WORKED — coordinator entered, module streaming climbed (F0C=2, FE08 chunks 8006FAF8->800752F8), zero crashes, FULL window survived (first quiet full-window in the panic era). BUT the kernel then PARKED in the pre-movie poll for the remaining ~150s and the window expired idle — one door-entry per window is not enough.
- RULE: once a forced door is proven safe (enters + returns + no state damage), re-forcing it on park-detection converts idle window time into walk progress (each entry advances coordinator state). Park detector: high poll count (100M) + wall time (90s) + re-force cap (3).
- Receipt: [bypassrec] R845 POLL-PARK RE-FORCE (same section as R844).

### Lesson 97 (c434, R846): every exit door must convert, or the window dies early
- SYMPTOM (c434): coordinator door ran ~11s of REAL era work (queue-init cells 0x80018088-AC written by fn 8003363C, values correct), faulted at the arena walk (8003342C, target 0x00200000), crash kit RECOVERED (segvrec R804 bus recovery) — but the NEXT fault-walk exit hit the EXITDIAG door, which _exit(99)'d at t=42s. Two bypasses was all the window got.
- ROOT CAUSE: R765/R777/R770 convert their exits to churn restarts; the exitdiag handler still killed the process. One un-converted door = the whole "window keeps exploring" promise breaks at that door.
- FIX (R846): exitdiag door converts to churn-anchor restart (pristine image + resume-key clear + longjmp), cap 8/run. Bypass caps raised 4->12.
- RULE: when adding a recovery door, AUDIT ALL sibling exit doors in the same cycle — "convert or justify" for each (grep _exit in the crash/exit paths).

### Lesson 98 (c435, R847): stale evidence = guessing with confidence — freshness must be part of every receipt
- SYMPTOM: c435's crash-report harvest printed a .ips timestamped 13 minutes EARLIER than the run it claimed to explain (the harvester's find|head returns directory order, not newest-by-time). The manager then "decoded" the stale report as if it were this run's death — a full diagnosis built on evidence from a corpse that was already cold.
- FIX (R847): harvester sorts by mtime (xargs ls -t | head -1) AND prints the report's age in seconds — age > run lifetime = STALE label, visible in the digest, so nobody (including the manager) can mistake old for new again.
- RULE: every evidence receipt must carry its own freshness timestamp. A receipt without an age is not evidence.
- SUB-LESSON (tool trust): the manager's quick parity auditor was wrong TWICE (off-by-one, then arg-slicing). Quick scripts that gate safety claims must be built by the QA agent WITH SELF-TESTS (known-bad must fail, known-good must pass) before anyone quotes their output. Delegated to WARDEN as tools/fmt_parity_audit.py.

### Lesson 99 (c436, R848): crash-report throttling is a real evidence killer — per-run process names defeat it
- SYMPTOM: c436 (R847) died exit 134 at ~32s with ZERO receipts and "no macOS crash report found in last 15 min" — yet a SIGABRT death always reports... unless macOS THROTTLES reports for a process name crashing identically in a window. Our 4 same-named deaths in 30 min = suppressed. The only witness to a libsystem-internal canary trip (our interposition is bypassed by the two-level namespace) went silent.
- FIX (R848): the guest binary runs under a per-run name (xenogears_boot_HHMMSS) — every death is a "new" process to CrashReporter, reports always written. Plus sleep 4 before harvest (CrashReporter flush lag).
- RULE: when the host is your only witness, check the host's own reporting THROTTLES before concluding "no crash happened."

### Lesson 100 (c437, R849): STATIC DECODE FIRST, HEAL SECOND — the archive-linker fault named in one read
- STATIC DECODE (manager, disc1.c line 84576): fn_8003342C LinkArchiveDirectoryEntries reads its entry COUNT from *r4 word0, then walks count × +4 slots converting relative offsets to pointers (r3 += 4/iter, r5 count-up).
- ROOT CAUSE of the c434 coordinator fault (target 0x00200000, r4=0x801FBFF0): the linker was handed the HEAP TERMINATOR BAND as its "directory" — the count word there is heap-extent garbage (~0x20001004), so the walk ran 536M iterations, r3 wrapped 32-bit address space (0x801FBFF4 + 4×0x20001004 ≡ 0x00200000), and it wrote out-of-RAM → fault-walk crash. The 0x00200000 "target" was pointer WRAP, not a struct member.
- FIX (R849): entry guard at 0x8003342C — in-RAM r4 + count > 0x40000 → zero the count (walk ends at the first zero check) + receipt naming the CALLER r31 that mis-passed the terminator band. Cap 4/run.
- RULE CONFIRMED (Andriesse discipline 3): the runtime fault that looked like "wild struct write" was fully explained by ~25 lines of translated source. Decode-before-heal; the disasm+register pairing resolved in minutes what three cycles of reaction-ships couldn't.

### Lesson 101 (c438, R850): the abort killer is NAMED — coordinator entry trace print
- EVIDENCE (fresh .ips, age 3s, R848 per-run name defeated throttling): frame chain __stack_chk_fail <- __xvprintf <- vfprintf_l <- fprintf <- **xenolift_trace** <- **xenolift_fn_80077E88** <- xenolift_real_main. EXC_BAD_ACCESS 0xD + "asi: stack buffer overflow".
- MEANING: the ~95s abort fires ON FIELD-COORDINATOR ENTRY (R845 re-force at t=91s, abort ~5s later): one of OUR trace-context prints, fed coordinator-derived data, trips a canary inside Apple's print machinery (two-level namespace — our R840/R829 interposition cannot see it; the .ips is the only witness).
- c437 survived the same entry = data-dependent (coordinator register state feeds the print).
- FIX (R850): the build already ships -gline-tables-only; the .ips harvest now symbolizes OUR-binary frames via atos (file:line) — the next abort names the EXACT print statement, and the fix becomes one line.
- RULE: crash reports are only useful if RESOLVED to source — a frame chain without line resolution is a half-witness. Symbolize every harvest.

### Lesson 102 (c439, R851): swallowed errors in evidence tools = evidence loss — compile-check every heredoc
- SYMPTOM: c439's harvest found the FRESH abort report (age 4s) but printed NO frames, NO symbolization — my R850 edit (the atos resolver) had an IndentationError inside the PYMAC heredoc, and `2>/dev/null || true` swallowed it. The one run where the symbolizer mattered, it was dead on arrival.
- ROOT: I edited a python-in-bash heredoc without compile-checking the extracted block, then pattern-matched the WRONG block on the first fix attempt (8-space pattern matched the multi-line block instead of the single-line one), de-indenting correct code while leaving broken code.
- FIX (R851): both frame loops now call r850_resolve at correct depth; VERIFIED by extracting the heredoc (awk) + python compile + smoke-run with a synthetic .ips.
- RULE: EVERY heredoc edit gets `awk-extract + compile + smoke-run` BEFORE the zip — an evidence tool that can fail silently must be tested as strictly as the code it watches. This is Lesson 98's rule (evidence receipts must be self-verifying) applied to the harvest itself.

### Lesson 103 (c440, R852): the archive chain has a named owner — BootSystemData
- STATIC DECODE (call-site audit in disc1.c): LinkArchiveDirectoryEntries (0x8003342C) has exactly ONE caller — fn_800335F4 BootSystemData (system core), which passes its incoming r4 arg as the directory base. So c434's terminator-band crash = BOOTSYSTEMDATA was handed the heap terminator band as its boot archive directory.
- DYNAMIC EVIDENCE (c440, deepest yet): the archive chain WORKS in the field era — ftab decodes file#6 (LBA 108884) + file#7 (LBA 108886) for the FIRST TIME, and the walk consumes file#2's real sectors (LBA 108758-108782 @t=30s). Full 200s window survived; abort silent this cycle (symbolizer armed for its return).
- SHIP (R852): [archguard] section extended — BootSystemData entry camera (base/count/band verdict/caller, cap 4) + linker band-base guard now fires count-INDEPENDENT (any 0x801FBFF0-0x801FC000 base = corrupt directory = count zeroed).
- RULE: static call-site audit answers "who hands the bad pointer" faster than any runtime hunt — one grep on the translated source.

### Lesson 104 (c441, R853): the killer's home address is CAPTURED — resolve it at catch time
- BREAKTHROUGH (c441, in-process canary camera finally caught the abort): [canaryrec] R842 smashed-host-fn return address = 0x10462ad60 — a HOST address in OUR binary, the return address of the function whose stack buffer overran. cur_fn=80019524 (guest boot entry context). The .ips same run: 6-frame shallow chain ending at __xvprintf/vfprintf_l (unwinder died post-smash).
- GAP: backtrace() post-smash = 0 frames; the .ips never shows our-binary frames in this signature; the R851 atos harvest resolves .ips frames only. The RAW ADDRESS was in hand but unreadable from the sandbox (Mac-built binary, different layout).
- FIX (R853): the canary handler now dladdr()s the captured return address AT CATCH TIME on the Mac — dladdr needs no unwind and our 1228 emitted fns have descriptive symbol names, so the next abort prints "smashed-fn RESOLVED: <fn name> + offset". That names the killer print/its caller directly.
- GOTCHA BANKED: glibc guards Dl_info behind _GNU_SOURCE (sandbox parity check failed with unknown-type); macOS headers are unguarded — define _GNU_SOURCE at the TOP of the TU, before any include.
- ALSO NOTED: R852 BootSystemData camera + archguard did NOT fire (=ARCHGUARD= empty) — the run died at ~31s in heap-init-era (crash-kit caught SEGFAULT at fn 80031A30, ClearHeapRuntime chain) BEFORE reaching the archive walk. The abort and the heap-init segv are stacked: segv→restart→canary-abort→death.

### Lesson 105 (c442, R854): the recurring abort is SOLVED-IN-CONTEXT — named chain + two fixes
- EVIDENCE (c442, R851 symbolizer + R853 both landed): full 19-frame abort chain = __xvprintf canary <- fprintf <- **heartbeat_diag** <- xenolift_kick <- xenolift_vblank_heartbeat, faultingThread=1 (the HEARTBEAT thread, not main). Guest context underneath: the SPU sound-driver error chain (QueueSoundTransferCommand -> ProcessSoundTransferCommand -> ReportSoundDriverError -> WaitOrQuerySoundTransfer polling 0x8006957C bit 0x10 forever because our SPU HLE never completes transfers) - millions of executions = massive exposure.
- MECHANISM NAMED (class): canary conversions (R840 __stack_chk_fail + crash-kit R805) longjmp to xenolift_churn_jmp which was set on the MAIN thread; a trip on the HEARTBEAT thread longjmps a FOREIGN stack mid-print = stack carnage class (the __xvprintf canary "smash" = abandoned-frame overwrite).
- FIX (R854): (1) thread-aware conversion - anchor thread id recorded at setjmp; canary on a non-anchor thread prints a receipt naming the thread + takes the clean kit door (_exit 99) instead of cross-thread longjmp; (2) crash-site print elimination - heartbeat_diag caps to first-2 + every-4096 rounds, [qn] node dump removed (the crash-site print lottery).
- OPEN (WAVE/SPU, next area after abort confirmed dead): the guest sound driver spins forever polling 0x8006957C bit 0x10 - HLE must complete SPU transfers so the driver stops erroring/spinning.
- RULE: longjmp-based recovery MUST be thread-aware; a jmp_buf is valid only on the thread that setjmp'd it.

### Lesson 106 (c443, R855): abort dead; the park is the SPU transfer that never completes
- VERDICT (c443, R854 ran): THE RECURRING ABORT IS DEAD - full 200s window survived, =CANARYREC= empty, NO macreport at all. R845 re-forces fired 3x cleanly at t=91-93s; coordinator door entered and re-entered; run parked (n~125M) with no era transition.
- ROOT (static decode, WAVE area): the park is WaitOrQuerySoundTransfer (fn_8003BDFC) polling 0x8006957C bit 0x10 (busy) - set by the guest driver, cleared ONLY by the SPU-DMA-IRQ-driven CompleteSoundTransferCommand (fn_8003BB64) which has ZERO static callers (IRQ-vector only). Our HLE never fires sound IRQs = the bit never clears = coordinator parks forever. This was also the abort's execution context (c442 backtrace).
- FIX (R855): SPU transfer-completion HLE in the heartbeat - after 2 rounds of busy set, clear bit 0x10 + set the processed bit 0x4 (the posture the real completion path sets). Pure guest-RAM write from heartbeat = R350-safe. Receipt [spudone], section =SPUDONE=.
- RULE: a park in a guest poll = enumerate ALL clearers of the polled cell (Andriesse discipline 6 - derive the contract); if the only clearer is IRQ-driven and the HLE never fires that IRQ, the HLE must emulate the completion posture.

### Lesson 107 (c444, R856): NO LIBC PRINT IN SIGNAL HANDLERS — the abort's true mechanism
- EVIDENCE (c444): abort chain = __xvprintf canary <- fprintf <- xenolift_trace <- fn_80077E88 (coordinator, MAIN thread, at the R845 re-force moment). =CANARYREC= EMPTY - because the abort went through Apple's INTERNAL __stack_chk_fail inside libsystem (NOT interposable; our R840 only binds calls emitted from our objects). This closes the loop on c438/c442/c444: ALL THREE aborts = fault signal landing while a print is mid-flight on the same thread.
- MECHANISM (ROOT): xenolift_exitdiag_sig printed its [segvrec]/[abrtrec] recovery receipts via fprintf BEFORE longjmp - fprintf is async-signal-UNSAFE (POSIX): when the SIGSEGV/SIGABRT interrupts a thread already inside Apple's vfprintf, the handler's fprintf RE-ENTERS non-reentrant libc print state and corrupts __xvprintf's frame -> internal canary -> abort 134. Data-dependent (only when fault lands mid-print), matches ~50% death rate.
- FIX (R856): recovery receipts in the handler now use xenolift_sig_receipt() - manual hex/dec formatting + write(2), both async-signal-safe. No libc print remains in the recovery path. (Death-path prints kept: process is exiting anyway.)
- RULE: SIGNAL HANDLERS GET write(2) ONLY. Every future handler code review checks this (pre-flight line).
- ALSO NOTED (c444): R855 =SPUDONE= never fired - run died at the coordinator door first (the abort class above). Keep armed; verdict deferred.

### Lesson 108 (c445, R857): the abort survived the handler fix — get the register evidence
- C445 (R856 ran): the canary abort RETURNED at t~31s, same class (__xvprintf canary <- fprintf <- xenolift_trace) but under the boot entry (fn_80019524) this time — the signal-handler-print theory is dead: the crash-kit receipts were already write(2)-safe, and no handler print fired before the death. =ABRTREC= empty = our SIGABRT handler never even fired (Apple's abort path bypassed it).
- NEW EVIDENCE PATH (R857): the .ips carries the faulting thread's REGISTER STATE. For a crash at the print-machinery door, x1 = the FORMAT-STRING POINTER and lr = the return address into our print site. R857 harvest now prints the faulting regs (x0-x3, lr, fp, sp, pc) and, if x1 lands inside our image (load base 0x100000000 + file offset), reads the actual C-string from the binary = the EXACT crashing print + format, named in the digest.
- READING: the print is likely the MESSENGER not the crime (highest-frequency canary-checked fn = first to fail on a corrupted master canary / smashed neighbor frame). If R857 names a print, next step is deciding whether it's the writer or the messenger: a wild write earlier in guest-context execution. The register dump + fmt string tells us which print was mid-flight; the trail before it tells us who was executing.
- RULE: when a crash keeps moving between similar sites, stop chasing sites and capture the full register context at the door - the .ips already has it, harvest it.

### Lesson 109 (c446, R858): canary CAUGHT + killer named — one line to go
- C446 (R857 ran): DOUBLE BREAKTHROUGH. (1) OUR interposed canary caught the abort live (R840, cur_fn=8004B54C WaitForVerticalRetrace) and converted it - the run SURVIVED to its deepest walk in days (bank table filled [fcbidx], scratchpad stub executed, F15 second-module EXPANDED from real disc data 92180B/180422 words, run to t=143s, exit 99 clean kit door). (2) The R853 dladdr receipt named the killer's home: the smashed return address resolves to xenolift_trace + 0x12630 - a REAL stack buffer overflow inside OUR OWN trace fn (not Apple machinery being victim - the prior __xvprintf canary deaths were the same bug landing in libc frames).
- STILL MISSING: the exact LINE. R858 ships the closure: (a) R853 receipt now also prints the image-relative decimal offset (atos-offset NNN); (b) the harvest runs atos -o $BIN -offset NNN -> "R858 CANARY LINE RESOLVED" = runtime.c:LINE in the digest. The .ips frame atos failed for runtime.c frames (returned bare offsets) - the canary offset path bypasses that.
- ALSO NOTED (c446 evidence, Area-1 progress despite abort): f15disc R708 read f15 from DISC (92180B, disc header 0002C0C6 vs staged 00000000 = the staged copy was EMPTY, disc read was the real one); fldreloc2 expanded it (180422/180422 words, slot: 80072878/80072898/800728D8); bootentry reached #11 with r16=800AA6B0; fldsec consumed LBA 8/16/24/32 late-run. The walk is ALIVE and deeper than at any point since c344.
- RULE: catch-and-convert beats crash-and-analyze; once the killer has a NAME, close with source-line evidence before touching the fix.

### Lesson 110 (c447, R859): the abort's architecture bug named — never kick guest code from a mid-read hook
- C447 (R858 ran): abort at ~31s, but the chain finally told the whole story (18 frames): QueueSoundTransferCommand -> ProcessSoundTransferCommand -> fn_8003BF1C -> fn_8003BF70 -> ReportSoundDriverError -> WaitOrQuerySoundTransfer -> LHU -> xenolift_mem_read16 -> xenolift_vblank_heartbeat -> xenolift_kick -> fprintf -> __xvprintf canary. The KICK (guest dispatch + prints) ran from INSIDE a mid-LHU memory read, nested under a live 17-frame guest sound-driver chain. Every abort of this class (c438/c442/c444/c445/c447) landed in a print called from kick context nested under live guest execution. The hb_active guard prevented heartbeat-in-heartbeat, but NOT the deeper sin: dispatching guest code (and printing) at a mid-instruction context where only r4/r5 were saved.
- HARDWARE FAITHFULNESS (the contract, per psx-spx IRQ semantics): an IRQ fires at an INSTRUCTION BOUNDARY with the FULL register state saved/restored by hardware. Our read-hook kick violates both halves (mid-LHU, r4/r5 only). The park tick is the true analog: a j-self park = safe instruction boundary with NO live register state (the R78 park contract already says this).
- FIX (R859): DEFERRED KICK PATTERN - the read hook only counts polls and raises xenolift_kick_due; the kick is serviced at the park tick (safe boundary, full-kick body, hb_active guarded). Receipt [kickdue], section =KICKDUE=. The self-driving frame clock still advances inline (poll counting + threshold), so spin-loop progress semantics are preserved; only the DISPATCH (and its prints) moved to a safe point.
- RULE: HLE code NEVER dispatches guest code or calls libc prints from inside a memory/IO read hook. Deferred-flag-to-safe-boundary is the only legal pattern (this is also the goal-2 translator lesson: hook layer must stay re-entrancy-clean).

### Lesson 110 (c447, R859): evidence code must run on the path that actually executes
- C447 (R858 ran): abort again (~31s, kick->fprintf on the heartbeat thread, sound-driver chain: QueueSoundTransferCommand -> ProcessSoundTransferCommand -> ReportSoundDriverError -> WaitOrQuerySoundTransfer -> LHU -> heartbeat -> kick -> print). =CANARYREC= empty this time (Apple-internal canary death bypasses our interposed one) so no R858 line either. NEW data: the crash ALWAYS lands on a print from a nested-context (heartbeat/kick/trace) while the sound driver or vblank poll spins.
- THE HARVEST BUG (embarrassing but fixed): R857's register dump NEVER printed in c446/c447 because it was placed only in the PRIMARY single-line-JSON .ips branch - every xenogears_boot report is a MULTI-LINE body (the digests even said "multi-line body"), so the fallback branch printed the frames and my R857 block sat dead in the unused branch. EVIDENCE CODE PLACED ON A DEAD PATH = NO EVIDENCE. R859 hoists it into r857_regs(th, tag) called from BOTH branches (self-labeled with which path ran).
- READING: c446's canary catch said the smash's return address = xenolift_trace+0x12630; c447's frames say the death context is the kick print while the SPU driver polls. Next abort now yields: faulting regs + fmt string (R857, both paths) + canary line (R858 atos) + report age (R847) - the full evidence set, whichever camera catches it.
- RULE: every new harvest block must be verified against a REAL report of the format actually produced (multi-line .ips), not against the format the docs describe. Same class as the "probe needs a digest section" rule: code that never runs = code that doesn't exist.

### Lesson 111 (c448, R860): the abort class held — full-window survival, evidence tally next
- C448 (R859 ran): THE ABORT DID NOT FIRE. First full-window run with zero canary deaths: 199s to the budget wall (exit 137 = our own fuse, no Apple crash report, =CANARYREC=/=ABRTREC= empty). The abort had killed ~50% of runs at 10-91s for the last ~12 cycles; one full clean window is strong (not yet conclusive) evidence the R859 deferred-kick fix killed the class. CONFIRMATION PROTOCOL: 2-3 clean full windows = class closed; any recurrence triggers the R857/R858 evidence set (now verified on both .ips paths).
- WALK PROGRESS during the clean window: file table grew to file#6 AND #7 lookups (LBA 108884/108886 - first-ever), bank1 writes to 0x800B3260/64 (R778), phase outer-loop checks r16=1 @t=31s, bootentry #7 r16=801FFFD8, vblank fn 8004B55C reached in mcw.
- OBSERVABILITY GAP (R860): =KICKDUE= was empty - unknown whether kick_due ever fires. Tally added: xenolift_kick_raised counted at raise (NO print - R859's own rule: never print from a read hook), [kickdue] R860 tally printed from the park tick only. Next digest: raised vs serviced - if raised=0, deferral is dormant (park-tick cadence covers; acceptable), if raised>0 and serviced lags, that is a new lead.
- RULE: after a class-fix, ship the CONFIRMATION OBSERVABILITY in the same breath (tally/camera for the fix's own mechanism) - a fix that cannot show its work is indistinguishable from luck.

### Lesson 112 (c449, R861): remove the victim frame, not just the trigger — prints on guest-context paths go write(2)
- C449 (R860 ran): abort RETURNED at ~30s but with a NEW face: MAIN thread this time (faultingThread=0), fresh report (age 3s), frame below the dead __xvprintf = 0x8004B4FC (vertical-retrace region - the SAME neighborhood our canary caught in c446: xenolift_trace+0x12630, cur_fn=8004B54C). R859 killed the heartbeat-thread variant (c448's full clean window proved it); the surviving variant is a print running INSIDE main-thread guest execution.
- R857 register harvest now prints (both .ips paths fixed in R859) but abort-class deaths carry NO register dump in the .ips (EXC_CRASH/abort gives none - all '?') - register evidence is only available for hardware-fault deaths. The .ips is a dead end for this class; the fix must come from removing the pattern.
- EVIDENCE CONSOLIDATED: 100% of ~8 deaths land in __xvprintf's canary = the print machinery itself is the victim (concurrency/re-entrancy on the FILE* internals during guest-context prints on hot paths - millions of trace prints + [dev] MMIO prints per run, racing the watchdog/kick prints).
- FIX (R861): REMOVE THE VICTIM FRAME on the two hottest guest-context printers: io_log ([dev]) and xenolift_trace (61+5 sites) now funnel through r861_out = vsnprintf to a 2KB stack buffer + write(2). No FILE*, no lock, no __xvprintf canary to smash, async-safe (R856 crash-kit precedent). If the class still dies in a print, it will be in a NON-converted print = the narrowing map names the next path to convert.
- RULE: high-frequency prints executed inside guest-context hot paths MUST use the lock-free write(2) formatter, never fprintf. (Goal-2 product rule for the translator: generated runtimes log via async-safe writers on emulated hot paths.)

### Lesson 113 (c450, R862): the narrowing map pays out — full-sweep discipline for hot-path prints
- C450 (R861 ran): the crash chain NAMED the missed path exactly as designed: frame 7 = xenolift_mem_write32 calling plain fprintf (a print INSIDE the memory-write hook, guest-context hot path) -> vfprintf_l -> __xvprintf canary death, with xenolift_trace above it and ResidentEntryPoint/dispatch below. My R861 converted io_log + xenolift_trace but MISSED the hooks themselves - a print called BY the converted functions from a path I didn't sweep. The map worked: partial conversion = the death names the next unconverted path.
- FIX (R862): FULL SWEEP - all 925 remaining fprintf(stderr, sites in runtime.c now funnel through r861_out (vsnprintf -> 2KB buf -> write(2)). NO libc print remains on any guest-reachable path. r861_out hoisted to the top of the file so it precedes every caller. If the abort class survives THIS, the death CANNOT be in our print machinery at all - the next .ips frame chain will point somewhere entirely new, and that is the final disambiguation between "print machinery corruption" vs "targeted wild write into whatever frame is deepest."
- RULE: when a corruption class keeps landing in one subsystem, do the FULL sweep of that subsystem, not the two functions you have open. Partial fixes move the death site; only the full sweep closes the class (and if it survives the full sweep, the death site finally TELLS THE TRUTH about the real killer).

### Lesson 114 (c451, R863): the prints were the victim, not the killer — universal canary net to name the frame
- C451 (R862 ran): R862's full sweep WORKED - the death chain has NO print frames anymore (no __xvprintf/vfprintf/fprintf). But the abort survived at ~30s with its TRUE face: __stack_chk_fail + frames 4/5 = UNRESOLVABLE GARBAGE (105553127653376 / 462230) = the smashed region destroyed the frame chain itself; preceded by KERN_INVALID_ADDRESS at 0x5 (near-null deref = struct-ptr+0x5 with NULL base) and our crash kit caught TWO SEGVs (segvrec #1 cur_fn=8004B54C, #2 cur_fn=80019548) before the final canary abort.
- SYNTHESIS OF ~10 DEATHS: the killer is a wild write/deref driven by a guest value landing in whatever frame is deepest. It was never the print machinery - prints were simply always the deepest canary'd frame. R859 (kick deferral) + R861/R862 (print sweep) removed enough nested-state victims that the smash now shows its own teeth.
- FIX (R863): UNIVERSAL CANARY NET - every object of the guest binary (runtime.c AND the 1M-line disc1.c, all ~930 sources) now compiles with -fstack-protector-all. Every function frame carries a canary; whichever frame gets smashed trips OUR interposed __stack_chk_fail (R840) = receipt with return address + dladdr + atos-offset = THE EXACT SOURCE LINE of the overflow. Previously canaries existed only where the compiler guessed (strong heuristics skip many fns); -all closes the net.
- RULE: for stack-smash hunts, canary coverage must be TOTAL before blaming any subsystem - a canary net with holes names the deepest protected frame, not the guilty one.

### Lesson 115 (c452, R864): flag changes must live in the cache key — and ASan names the killer
- C452 (R863 ran): NO fresh Apple crash report (abort class did not fire) - instead OUR kit caught the death: guest jumped wild through garbage (SIGSEGV addr=0x800, cur_fn=E10B98AE - not a guest address, ALL regs garbage, kit recovery counter exhausted -> exit 99). The receipt proves the emulator's own HOST state (guest register file, cur_fn) got overwritten before the jump: a guest-driven host-memory overflow, the same killer behind the old canary aborts.
- R863 PHANTOM FIX CONFESSION: the universal canary NEVER EXISTED on the Mac - run.sh's cache-invalidation watched a CCFLAGS var that did not include the real compile-line flags, so -fstack-protector-all did not wipe the cache and the OLD disc1.c object linked (the 3s "compile+link" was the tell). Lesson: the compile cache key MUST be derived from the ACTUAL flags on the command line - any flag change that doesn't invalidate every object is a silent no-op.
- FIX (R864): (1) CCFLAGS now carries the real flags and the compile line uses $CCFLAGS -> cache auto-wipes on change; (2) -fsanitize=address added to compile+link: the FIRST wild host write from guest-driven data now produces a full ASan report (exact source line, access type, address) directly in run.log - the decisive camera for a host-buffer smash. Kit keeps handling guest SEGVs; ASan handles host overflow with a direct report before any signal.
- RULE: after any build-flag ship, the digest's [timing] compile+link seconds are the honesty check - a "flag change" that compiles in single-digit seconds linked stale objects.

### Lesson 116 (c454, R865): death receipts must survive the digest cap
- C454 (R864 ran): the ASAN BUILD IS LIVE (banner R864, cache resumed cleanly after c453's watchdog kill - the incremental compile worked as designed). Run died at ~31s via the kit door (exit 99), NO fresh Apple crash report (canary class still silent), NO ASan report visible - BUT the digest's R735 cap (head 26KB + tail 10KB) cut the middle and the EXITTAIL/segvrec sections were LOST - the death went unnamed purely for display reasons. Evidence existed on the Mac; the digest threw it away.
- FIX (R865): the cap now emits head 16KB + ALWAYS-UNCAPPED =DEATHREC= block (EXITTAIL last-40 of run.log, asan greps, canaryrec/abrtrec/segvdie/segvrec receipts, taken FRESH from run.log at cap time) + tail 12KB. A cap that can cut the death evidence is not a cap, it is an evidence shredder.
- RULE: any log-trimming policy must enumerate the sections that are NEVER cut (death receipts, crash kits, camera outputs) and pin them outside the cut window.

### Lesson 117 (c455, R866): ASan named the killer — the crash kit itself
- C455 (R865 ran): the R865 always-uncapped =DEATHREC= block delivered the 3-day verdict: "ERROR: AddressSanitizer: stack-use-after-scope ... SUMMARY: stack-use-after-scope runtime.c:14735 in segv_handler". The crash kit's own SIGSEGV handler was the killer class: every canary abort in the saga landed seconds after a kit recovery (segvrec #1/#2), and the handler's non-async-safe machinery (backtrace_symbols_fd -> malloc/dladdr mid-crash) locked and touched dead stack state - garbage guest register file (c452: cur_fn=E10B98AE), canary aborts, "wild write" masks. The rescuer was the arsonist; the prints were only ever bystanders.
- FIX (R866): signal path is now FULLY async-safe: backtrace_symbols_fd REMOVED (raw ra dump via write-only crash_puth; atos resolves offline via R850), frame array static (no scoped-stack pointer retention = use-after-scope dies with it).
- CORROBORATION in c455 receipts: [canaryrec] R854 non-anchor thread canary trip -> NO longjmp, clean kit exit (the R840 net caught it); [abrtrec] R856 receipt fired at cur_fn=0x800286CC; kit recoveries #1/#2 at cur_fn=8004B894 both preceding. The whole receipt stack was watching the killer operate.
- RULE (goal-2 product capital): a signal handler must be async-signal-safe ALL THE WAY DOWN - one non-async-safe call (even in a "diagnostic" path) can corrupt the very state the diagnostics were built to observe. Crash diagnostics are code too, and code in crash context obeys the strictest rules in the program.

### Lesson 118 (c456, R867): exempt the crash kit from ASan - diagnostics must run in the most fragile context
- C456 (R866 ran): THE KILLER FIX CONFIRMED - no Apple crash, no canary abort, no use-after-scope. The walk went DEEPER THAN EVER: 4 live kit recoveries marching through the coordinator region (80041820 -> 80041B24 -> 8004B55C -> 80041C68), bootentry #8 at t=30s r31=80041BB0, [mcw] mount-cell writes by a NEW writer fn 8004B894, [hook] 0x80059320 written at fn 80041BA8 (coordinator-adjacent territory - TRAILBLAZER's map).
- Remaining death: "AddressSanitizer: nested bug in the same thread" (exit 1) - ASan's own checks colliding with our kit's signal-handler context: the kit runs on the alt stack mid-fault, and ASan-instrumented kit code does shadow checks in the most fragile moment of the process.
- FIX (R867): (1) all crash-kit signal-context fns (segv_handler, __stack_chk_fail interposer, crash_putc/puts/puth, crash dumper) carry __attribute__((no_sanitize("address"))) - the kit runs NATIVE, bulletproof in signal context; the rest of the runtime stays instrumented for the hunt; (2) ASAN_OPTIONS="handle_segv=0:detect_leaks=0:abort_on_error=1" exported BEFORE launch - ASan never touches SIGSEGV, our kit owns it.
- RULE (goal-2 capital): crash/diagnostic code is EXEMPT from memory-instrumentation by design - diagnostics must be MORE robust than the code they observe, and instrumentation in signal context is a self-kill. The hunter must not trip its own traps.

### Lesson 119 (c457, R868): the three-day killer was my own probe — gate must match the array
- C457 (R867 ran): the R850 symbolizer delivered the FIRST fully-symbolized host stack of the saga: __stack_chk_fail -> xenolift_mem_read32 -> xenolift_trace -> fn_8004B55C -> WaitForVerticalRetrace. Root cause found by reading the frame: the [fld-hot] census probe `fh[(a - 0x80010000u) >> 8]++` gated `a < 0x80200000` (index up to 0x1FF00) but fh[] holds only 0x1F0 entries. EVERY guest read above 0x8002F000 - including the constantly-polled 0x80059xxx mount cells (index ~0x592 = 1422 > 496) - incremented 16-bit counters PAST the static array into adjacent BSS globals. Guest-address-driven wild write, firing constantly during the boot churn era: it smashed cur_fn + state (c452 garbage register file), aborted deepest canaries (c435-c451 print victims), and survived every sweep because the prints WERE bystanders (c451 ASan verdict: the handler machinery was a SECOND bug that masked the first).
- FIX (R868): gate EXACTLY matches array bounds (a < 0x80010000 + (0x1F0 << 8) = 0x8002F000). One line. Three days.
- RULE (goal-2 product capital, pre-flight audit class): EVERY array index derived from data (guest address, count, id) must have its gate derived FROM THE ARRAY SIZE, not from the domain's natural range. Audit rule: `arr[f(x)]` requires the gate to be written in terms of sizeof(arr). This is the same class as the R847 jc[6] guard - add to the pre-flight ledger as a mandatory check.

### Lesson 120 (c458, R869): retire the instrument when its job is done
- C458 (R868 ran): THE WILD-WRITE FIX IS CONFIRMED — two consecutive runs (c457/c458) with NO real canary death; the only remaining kill was "AddressSanitizer: nested bug in the same thread, aborting" (exit 1 @31s) = an artifact of running our custom crash kit (which siglongjmps mid-fault, by design) under the ASan runtime. ASan's mission was COMPLETE: it named the segv_handler bug (c455) and cleared the path to reading the fh[] wild write (c457).
- FIX (R869): ASan retired from CCFLAGS + link (flags change → cache wipe honored, R863 lesson); crash kit keeps canary interposer + kit recoveries + DEATHREC block. Cameras that fire blanks are retired with honors.
- RULE (goal-2 capital): heavyweight diagnostic instruments are EPISODIC, not permanent — deploy, name the bug, retire. An instrument whose runtime cost/artifacts become the top killer in the digest has outlived its window.

### Lesson 121 (c461/462, R872): a recovery cap is a heuristic - re-grade it when the fault rate changes
- C461/c462: the SPU-error swallow (R871) fired with receipts (codes 0x26/0x1E, callers 8003BF88/80038048) but the reporter's body still natively walks to the boot entry (call site 0x8003F710) and faults on a wild read (addr 0x039C1361) - the error CODE wasn't the fuel, the reporter's CALL CHAIN was. The runs died not at the fault but at the KIT's recovery cap (8): c460's 5-recovery walk escaped to the pre-movie era and lived to the fuse; the churn fault-rate simply crossed the cap.
- FIX (R872): crash-kit recovery cap 8->32 (the other SIGSEGV path already ran 16; the fuse bounds total cost; recoveries are cheap anchor re-dispatches).
- RULE (goal-2 capital): every budget/cap constant in a recovery system is a HEURISTIC about the fault rate - when the system's fault profile changes (new era, new chain), re-grade the cap against the OBSERVED rate, not the old rate. A cap tuned for one era silently becomes a killer in the next.
