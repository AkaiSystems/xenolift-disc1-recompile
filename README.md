# xenolift

Static recompiler for Xenogears (PS1, SLUS_006.64): MIPS R3000A binary → portable C.

## Pipeline

    disc dump (BIN/CUE)
      └─ SLUS_006.64 (PS-X EXE) ── text at 0x80010000, 2MB RAM at 0x80000000
           └─ xenolift decode (MIPS I, LE words)
                └─ emitter.rs → out.c (flat register file, explicit control flow)
                     └─ cc/clang → PC validation build first, then target SDKs

## Phase roadmap

1. **Phase 1 (done)** — EXE loader, MIPS I decoder, delay-slot-correct C emitter,
   KSEG0 memory aliasing, r[0] elision, COP stubs.
2. **Phase 2** — function discovery (walk `jal` targets from entry 0x80010000 +
   vtable `jr` dispatch), promote `r[]` to SSA locals, per-function C output.
3. **Phase 3** — GTE (COP2) software math: map RTPS/NCDS/NCCT etc. to float
   matrix/vector wrappers; keep fixed-point at the boundary only.
4. **Phase 4** — peripheral HLE: GPU command buffers → modern renderer,
   PSY-Q SPU/ADPCM → SDL3 audio ring buffers, CD-ROM sectors → file I/O.

## Build

    cargo build --release
    ./target/release/xenolift SLUS_006.64 out.c

Requires a disc dump you legally own.

## Target platforms

The emitted C is platform-neutral C17. Validate on PC (x86-64) first —
it's the only target you can iterate on freely. Switch requires a licensed
Nintendo SDK (or devkitPro for homebrew); PS5 requires a licensed Sony SDK.
