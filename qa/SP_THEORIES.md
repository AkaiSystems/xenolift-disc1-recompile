# Stack-Pointer Relocation Mystery (0x807FC910 / 0x80800000-class)

## 1. Emulator Stack Pointer Modeling & Probe Investigation in `runtime/runtime.c`
- **Register Modeling:** MIPS GPRs are modeled in `runtime.c` as a global array `uint32_t r[32];` where `$sp` corresponds to `r[29]`.
- **Kernel Dispatch Site (`0x80019BFC`–`0x80019C04`):** Kernel dispatches into Module 6 entry point `0x800737EC` (`MovieModuleEntry`) via `lw v0, 0(s1)` followed by `jalr ra, v0` (with return address `ra = 0x80019C0C`).
- **`[postres]` Probe (`0x80019BD8`):** Fires right before the dispatch stretch. Records `r[31]` (ra), `r[29]` (sp), `r[17]` (s1 descriptor), `desc` struct words, `cur` (`0x800592C0`), and `res` (`0x800592BC`). At `[postres]`, `sp = 0x80200000` (top of PS1 2MB RAM).
- **`[hand]` Probe (`0x80031F58`):** Logs allocator handoff returns (`v0`, `a0`, `a1`, `a2`, `s0`, `s1`, `s5`, `gp1C0`). Prior digests (entries #12/#13) show tagged pointers like `0x8081CE1C`/`0x80800000` returned during module/heap allocations.
- **Crash State:** Execution reaches `MoviePollSkipInput` (`0x800769A4`), called via `MovieRunPlayback` (`0x800767C0`), where `[faultregs]` logs `r[29] = 0x807FC910` (`0x80800000 - 0x36F0`). This indicates that between dispatch at `0x800737EC` and `0x800769A4`, `sp` was relocated to `0x80800000` before subtracting `0x36F0` across local function stack frames.

## 2. Candidate Relocation Mechanisms (Ranked by Likelihood)

### Rank 1: Candidate (a) — Module Header / Data Cell Stack Load
- **Mechanism:** Module prologue or init code at `0x800737EC` loads its initial stack pointer from its header or parameter structure (e.g. `lw sp, offset(a1)` where `a1 = 0x80077194` or `lw sp, offset(s1)`). Because the HLE premap/header cell was either unpopulated (left at zero/default) or injected with a heap poison tag (`0x80800000` tag class from allocator tag math), `sp` is loaded with `0x80800000`. Frame allocations (`addiu sp, sp, -0x36F0`) then yield `sp = 0x807FC910`.

### Rank 2: Candidate (b) — Kernel Handoff Argument Register Relocation
- **Mechanism:** The kernel passes a handoff argument in `a0` or `a1` during dispatch at `0x80019C04` that carries a `0x80800000`-class tagged pointer (matching `[hand]` #12/#13 entries `0x8081CE1C`/`0x80800000`). The module prologue executes `move sp, a0` or `addiu sp, a1, 0` to set up its private execution stack, inheriting the tagged pointer directly into `r[29]`.

### Rank 3: Candidate (c) — Recompiler Emitter Instruction Mistranslation
- **Mechanism:** The static recompiler (`xenolift/src/emitter.rs`) mistranslates an instruction writing `r[29]` (e.g., `Addiu`, `Lui`, `Lw`, or stack restore). For example, sign-extension of a 16-bit negative immediate, bitwise mask corruption on `lui sp, 0x8020` emitting `0x80800000`, or a restore-instruction mistranslation (a recurring bug class in prior builds) corrupts `sp`.

## 3. Confirmation & Decisive Evidence for Next Bridge Digest

### Candidate (a) Evidence
- **CONFIRM:** Code dump or disassembly at `0x800737EC` shows `lw sp, imm(r5)` (or `lw sp, imm(s1)`), and inspecting memory at that source address (e.g., in `r5 = 0x80077194` data dump) reveals `0x80800000` (or `0x8081CE1C`).
- **KILL:** Disassembly at `0x800737EC` shows `sp` is set directly from a register (`move sp, a0`) or immediate constant without loading from memory, or the memory cell at the target offset contains a valid RAM address (`0x801FC000`–`0x80200000`).

### Candidate (b) Evidence
- **CONFIRM:** Disassembly at `0x800737EC` shows `move sp, a0` (or `a1`), and the `[gdisp]` / `[hand]` probe entry at `0x80019BFC` shows `a0` or `a1` holding `0x80800000` (or `0x8081CE1C`) at the `jalr` dispatch site.
- **KILL:** `[gdisp]` logs show `a0` and `a1` at dispatch time are valid RAM addresses (e.g. `0x80077194`, `0x8006FAF0`), or module entry code does not copy argument registers into `sp`.

### Candidate (c) Evidence
- **CONFIRM:** Generated `disc1.c` code for function `0x800737EC` contains `r[29] = 0x80800000;` or a flawed sign-extension expression, whereas MIPS disassembly of `SLUS_006.64`/`movie.bin` shows `lui sp, 0x8020` or standard frame math (`addiu sp, sp, -N`).
- **KILL:** Emitted C in `disc1.c` matches the raw MIPS disassembly 1:1, and MIPS disassembly itself contains the `0x8080` constant or memory load sequence.

## 4. Proposed HLE-Side Additive Fix
The recommended HLE-side fix is additive in `runtime.c`: at `MountGameStateModule` / dispatch entry (`0x80019BFC` or `0x80019C04`), populate the module header / parameter block at `r5` (`0x80077194` / descriptor cell) with the valid RAM stack-top constant `0x801FC000` (or `0x801FFFF0`) before `jalr` executes, or strip high tag bits on handoff args (`r[4] &= 0x1FFFFFFF; r[5] &= 0x1FFFFFFF;`). This guarantees that when `MovieModuleEntry` initializes its stack pointer from its header cell or handoff registers, `sp` is bound to real PS1 RAM (`0x80000000`–`0x801FFFFF`) rather than the unpopulated/poisoned `0x80800000` region.
