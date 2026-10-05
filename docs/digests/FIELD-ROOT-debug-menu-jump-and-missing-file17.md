# Field crash: our "field" is a debug-menu jump, and file 17 is never loaded

Every run that reaches the field faults at t≈12s on a computed address 0x04B0004A.
It is the same fault in all 4 runs that got there (R1544q, R1526bq, R1549q, R1552q) and has the same cause.
That cause is not in the CD layer. It shows that "field reached" has been measuring a developer
shortcut, not the game's real flow.

## The fault

- The host backtrace puts the fault inside the R1394 interpreter (`r1394_dispatch_guard` →
  `xenolift_mem_read16`). `pc=0x8001C96C` in the receipt is only the last call-out
  (TimerWorkListUpdate), not the faulting code. The R1552 task-list camera stayed silent, which
  confirms the task lists are not involved.
- The faulting instruction is the field module's per-actor loop at **0x80076358**:
  `lw v1,0(s3)` with s3 = 0x801E8670, then `lhu v0,74(v1)`.
- [0x801E8670] = 0x04B00000. That is disc LBA 108954 at +0x7F0: a leftover byte of file 14's
  compressed staging buffer (0x801DD680..0x801FBEF8), DMA'd during the normal field-module load.
- The field also calls code at 0x801E72CC, 0x801E7378, 0x801E738C, 0x801E742C, 0x801E7D14,
  0x801E7FD4, 0x801E8030 and 0x801E8330. In our runs nothing is ever loaded there.

## Real-console ground truth

The owner's DuckStation resume states were read-only inputs. They are zstd frame 2 of the
`.sav`; RAM was located by majority vote of SLUS code probes, and 65,526/65,536 EXE words match.

| Save | Moment | 0x801C5000 window |
|---|---|---|
| SLUS-00664 (Disc 1) | opening movie (state 6, FE46=1) | movie player at 0x801D3000; 0x801E72CC.. zero |
| SLUS-00669 (Disc 2) | inside a field (FieldMain prologue at 0x80077E88, field header at 0x8006FAF0) | **main-archive file 17** resident |

On a real console in a field:
- File 17 (LBA 109123, 70,944 B LZSS → 153,864 B) sits at **0x801C5000..0x801EA908**.
  It matches the disc file on 38,463 of 38,466 words.
- It is held in an allocated heap block (header at 0x801C4FF8 = {801F34A8, 8101E6FE}).
- It covers every field call target above, the main EXE's 0x801C62A8..0x801CE024 calls, and
  0x801E8670.

## Why it is missing: the Kernel Menu shortcut

- Our runs go state 6 → 0 → 1 within one second.
- State 0 is `KernelMenuMain` (0x8001A4B4), the developers' stage-select menu. Up/Down move the
  cursor; Circle (pressed bit 0x20 at 0x8005948C) calls 0x8001996C(cursor+1).
- Runtime heal **R371 "MENU VIRTUAL PLAYER"** presses Confirm on cursor 0 = Field.
- The real flow is different. GameBootstrap's tail (0x80019888..0x80019930) sets the after-movie
  state byte 0x8004FE46 = 1 and requests state 6. On finishing, the movie module (file 18)
  requests state [FE46] at 0x80073BA4.
- We only reach state 0 because the movie state ends with an error.
- Field setup (0x800799D4) loads file `([0x800ADB64] & 0x7F) + 5` into the 0x801C5000 window with
  a queued read (0x80029AFC). The field's own init (0x800705E4) resets that selector to 0xFF at
  0x80070890; later field code and script commands (0x800937xx) set real values. The debug jump
  never provides that context, so file 17 is never requested.
- The Disc 2 save holds selector 2. Disc 2's archive numbering differs; on Disc 1 the module was
  identified by content as file 17.

## Shipped this cycle (bcc1fdd, already pushed)

- **R1549:** the lost-register kick is scoped to its own file.
- **R1550/R1550b:** no forced file copier on a live ring stream.
- **R1551/R1551b:** a test run can no longer rewrite the next build's inputs
  (`stage2_region.bin` / `overlay_fault.bin`). R704 promotion is opt-in via `STAGE2_PROMOTE=1`,
  and runtime dumps via `XENOLIFT_STAGE2_CAPTURE=1`.
- **R1552:** task/actor camera.

These remain correct. They removed real memory overruns and a build nondeterminism. They do not
fix this fault.

## What this changes

- Field-era results since R1519 were measured on the debug path. They are still useful for CD
  and heap mechanics, but not as "game progress".
- The next target is the movie state (6). It must finish and hand off through FE46 the way the
  game intends. Strengthening the menu auto-press is the wrong direction.
- With the complete movie player compiled, the player does run on our side: MDEC reset and the
  set_iqtab DMA0 upload are receipted. It then waits on a stream that never starts.
