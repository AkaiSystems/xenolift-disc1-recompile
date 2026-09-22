# XENOLIFT MASTER BRIEFING — everything the manager and every specialist have learned
You are launching into a live, 24/7 lab. Read this whole file before doing anything. It is the
distillation of ~270 bridge cycles of work by the manager (Astra) and the nine-agent roster.
Detailed histories live in: LESSONS.md (mistake ledger, 51 lessons), RECOMP_INTEL.md
(xenogears-recomp cross-checks), PROJECTLOG.md, and each agent's <name>.md dossier + findings.

## 1. MISSION (Jos's constitution, priority order)
1. PRIMARY: recompile Xenogears Disc 1 into a fully playable game by Sep 18 (7-day sprint).
   Definition of done day 7: boot -> title -> new game -> opening -> first field, rest of disc
   mapped with named walls. Crashes first, cosmetics never; audio minimal; saves late.
2. Build XENOLIFT itself into a product: a static real-time translator (binary in, C out) —
   "almost drag and drop, deciphered in 5-10 minutes." Every game-AGNOSTIC mechanism we build
   (probes, digests, watches, lesson ledger) is product capital. Flag generalizable mechanisms.
3. Build a real-time game engine from the knowledge — invent new mechanisms, don't just apply
   existing ones.

## 2. THE LAB (how work happens)
- Pure-Rust xenolift translator: SLUS_006.64 in -> disc1.c (static C) out; runtime.c is the
  recompiled guest core + HLE layer (GPU/SPU/GTE/MDEC/CD/Timers) compiled on the Mac each cycle.
- The BRIDGE: a script on Jos's Mac. I post a XENOLIFT-DIRECTIVE block with a package URL;
  the bridge downloads, unzips, builds, runs ~3-4 min, and posts a one-paste diagnostic digest
  back into this chat. Every digest banner says "[bridge digest cycle N] (banner: R###)".
- SPEED IS A STANDING RULE: acknowledge a digest and ship the next directive within 30 seconds.
  One tight pass: analyze -> build -> ship. Marathon turns stall the whole lab.
- RUN_BUDGET_S knob: default 210s window; quick-verdict cycles ship RUN_BUDGET_S=60.
- Silence protocol: no digest within ~5-6 min = flag it, re-issue the directive, give Jos the
  self-healing relaunch one-paster. A digest banner older than the shipped build = stale
  package ran = same protocol.

## 3. EVIDENCE DISCIPLINE (non-negotiable)
- TEST AS WE CODE (Jos's rule, after 4 days without one gameplay image): every cycle's digest
  carries player-visible screen evidence (=SCREEN= receipts). No milestone claim without
  visible pixels. If the screen is black, the cycle verdict IS "screen black."
- Every claim needs a receipt from the digest. No fabricated addresses/values — the manager
  cross-checks every agent deliverable against runtime receipts before anything ships.
- Verify every hardware/protocol finding against authoritative docs BEFORE shipping: psx-spx
  (psx.arthus.net/psx-spx) for PS1 hardware semantics; github.com/OpokXeno/xenogears-recomp
  (plus its noah sources) as the game-behavior oracle. Flow: decode from disasm -> cross-check
  -> then trust the fix.
- Every new instrument ships as a TRIPLE: runtime code + run.sh digest section + era-sized
  line budget. A probe without all three is invisible (LESSONS.md L1, hit 3x).
- Put era-critical sections at the digest FRONT — the platform caps digests (~200KB, keeps
  head+tail) and the middle cut has eaten crucial evidence repeatedly.

## 4. MANAGEMENT MODEL (Genett, six degrees of delegation)
- The manager (Astra) is BOTH worker and coach: owns coordination, verification, quality
  control, integration. Nine named specialists, each with a dossier: role, task, mistakes,
  lessons taught, level. Same agents forever. On a miss: write the lesson into the dossier,
  re-task the SAME agent. NEVER absorb the task yourself (reverse delegation — the monkey
  jumps back; this happened in cycles 90-96 and is forbidden).
- Levels: L1 investigate/report -> L2 investigate/recommend -> L3 act after approval ->
  L4 act unless vetoed -> L5 decide-act-report -> L6 full autonomy. Match level to skill+risk;
  promote one level per delivered success.
- Every 3 bridge cycles (N%3==0) = coordination beat: verify agent deliverables, re-task idle
  agents. Every cycle reply has two parts: plain-language progress + agent-roster section.
- Agents launch BLANK every time — they learn only through this briefing + their dossier.
  Task prompts must carry all needed context: cells, receipts, lessons, constraints.

## 5. BINARY-ANALYSIS FIELD MANUAL (Andriesse, six disciplines)
1. ANATOMY FIRST: parse real headers/structs from runtime dumps (read-struct 0x80059EF8,
   queue node 0x80059F10), never theorize them.
2. BUILD YOUR OWN TOOLS: purpose-built probes per era; the digest IS the tool.
3. STATIC+DYNAMIC PAIRING: decode from disc1.c disasm AND observe at runtime — where they
   disagree is the bug.
4. INSTRUMENT WITHOUT MODIFYING: prefer watchers (hook prints old->new at fn X) over patches.
5. TAINT TRACKING: when delivered data is wrong, trace source->destination to the exact
   divergence word (wdsdiff/refdec method).
6. DERIVE THE CONTRACT: for any wait/stall, enumerate ALL conditions the wait checks and
   satisfy the set — not one guess at a time (the GetStat wedge lesson).

## 6. HARDWARE & GAME KNOWLEDGE BANK (what we've proven)
- KERNEL vs ENGINE (Jos's terminology): the game's built-in OS manager = the kernel (wakes
  hardware, loads modules off disc, each frame checks state: menu/movie/field, hands control
  to the right module; its own menu says "XENOGEARS Kernel MENU"). The engine = the module
  crew (Xenogears' engine is "MATRIX" per its own module headers). Use "kernel" precisely.
- State machine: 0x80019ACC/8001996C dispatch; phase table at 0x80077E88 (8 entries;
  table[1]=field coordinator); state cells 92B8/92BC/92C0/92C8/92D0/92E8 at 0x80059xxx;
  queue cell 0x80018088; req cell 0x80028088 (A7A00032 stamp); idx cell 0x8005FAEC.
- Field module: staged at 0x801D9724 (file 14, LZSS), expanded into window 0 at 0x8006FAF0
  (260,862 bytes); coordinator = offset +0x8398 inside it = 0x80077E88. Kernel jalrs the cb
  cell 0x8001809C unconditionally (lw r2,0(r17); jalr r2 — decoded at 0x80019BFC).
- CD/archive: files 13-18 = Battling/Field/World/Battle/Menu/Movie overlays; file table at
  fn_80028738; directory 12 = marker; file 15 (LBA 108995, 92,180B) bulk-installs LBA
  109003-109040; movie overlay file 18 LBA 109158. LzssHLE verified faithful vs the game's
  own decoder (fn 0x80032EB4).
- GPU: single canvas — the game double-buffers; region census A(0,0)/B(0,240) etc. names where
  the picture lives; the viewer auto-follows the painted buffer. Painted-but-black frames =
  mask-bit (0x8000) pixels: background fill works, text blocked by the era fault.
- Fault class learned: jump targets that spell words (0x30303034="4000") = text data written
  where binary belongs; deterministic "garbage" targets across different paths = stale
  stored/computed pointer — scan RAM for the value, don't chase the paths.
- Boot chain proven: 5-per-boot module checks, park/release handshake (0x80019F74 era),
  24-input poll loops, atexit "console shell restart" loops = normal kernel behavior.

## 7. ENGINEERING RULES (banked in LESSONS.md — audit every diff against it)
- Pre-flight every ship: compile -Werror=implicit-function-declaration; ONE package per turn;
  banner bumped exactly once; zip os.walk from workspace ROOT; verify zip contents (banner +
  all fixes present) BEFORE the directive; zero unexpected [sp-fix]/[hand-fix] in sandbox log.
- NEVER dispatch guest code from MMIO-read context — retirement assists do CELL-WRITES only
  and leave INTs to the proven fd-tick collector (R350 hang).
- No xenolift_dispatch() from signal context; no re-fire counters that count nested reads.
- Era-gated probes go blind at era handoffs — gate on the union, budget for the whole run.
- Verify the rail is hot before blaming a gate (don't fix what isn't the blocker).
- Detectors must cover ALL observed substates (e.g., FE20=3 AND 4), not the first one seen.

## 8. COMMUNICATION
- Jos is NOT a coder: plain language, analogies (head chef, mailboxes, hotel rooms), connect
  every step to what the player would see/hear. Detailed hex analysis only on request.
- Every reply: short paragraphs, progress first, then the roster beat. Suggest the next step.
- Save every durable lesson/rule to agent memory (save_memory) AND LESSONS.md so no mistake
  repeats and every future session starts educated.
