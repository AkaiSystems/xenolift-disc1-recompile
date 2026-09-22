# Xenogears USA (SLUS-006.64) BIOS Thunk Coverage Audit
**Project**: xenolift (PS1 Static Recompilation Harness)  
**Context**: R143 Build — Module 6 = MOVIE Overlay (entry `0x800737EC`), CD-ROM Async Diagnostic Suite  
**Date**: 2026-09-11  

## Executive Summary
This audit provides a complete BIOS thunk coverage assessment for all 37 thunk sites identified in the Xenogears USA Disc 1 kernel executable (`SLUS-006.64`). Under build R143, the kernel boot reaches Module 6 = MOVIE overlay (`0x800737EC`), which executes a CD-ROM diagnostic suite (`MovieAdvanceCdReadVerification`, `MovieQueueRandomSectorRead`). The boot main restart loop (`fn_80019ACC` error dispatcher spike) is the current progress wall.

### Audit Summary Counts
- **Total BIOS Thunks**: 37
- **HANDLED**: 12 (32.4%) — Runtime provides explicit support in `xenolift_bios_gate` or HLE handlers.
- **AT-RISK**: 5 (13.5%) — Currently unhandled (falls through to default `v0 = 0`), but directly required by Movie module diagnostic stress reads, root-counter VSync timing, pad buffer updates, or exception returns.
- **LATENT**: 20 (54.1%) — Unhandled but not yet observed executing during kernel boot or Movie diagnostic initialization (e.g. Memory Card filesystem, BIOS low-level file I/O).

---

## Complete 37 BIOS Thunk Coverage Table

| # | Vector | ID | Canonical BIOS Name | Our Address | Class | Current Runtime Status & Implementation Detail |
|---|---|---|---|---|---|---|
| 1 | A0 | 0x44 | FlushCache | 0x80040454 | **HANDLED** | `xenolift_bios_gate` A0:0x44: Nop (`r[2] = 0`), no CPU cache flush needed on x86_64 host. |
| 2 | A0 | 0x70 | _bu_init | 0x80040464 | **LATENT** | Default `v0=0`; memory card utility init. Unused by Movie overlay. |
| 3 | A0 | 0x49 | GPU_cw | 0x800471A4 | **HANDLED** | `xenolift_bios_gate` A0:0x49: Writes GP0 command word `r[4]` to `0x1F801810`. |
| 4 | A0 | 0x72 | CdRemove / remove | 0x8004BED8 | **LATENT** | Default `v0=0`; file remove utility. Unused by Movie overlay. |
| 5 | A0 | 0xAB | ReadCardDirectoryStatus | 0x8004E784 | **LATENT** | Default `v0=0`; memory card status check. Unused by Movie overlay. |
| 6 | B0 | 0x08 | OpenEvent | 0x80040474 | **HANDLED** | `xenolift_bios_gate` B0:0x08: Allocates event in `evt_tab`, returns handle `ev > 0`. |
| 7 | B0 | 0x09 | CloseEvent | 0x80040484 | **HANDLED** | `xenolift_bios_gate` B0:0x09: Frees event in `evt_tab`, returns `r[2] = 1`. |
| 8 | B0 | 0x0B | TestEvent | 0x80040494 | **HANDLED** | `xenolift_bios_gate` B0:0x0B: Returns non-blocking event fired status (`evt_tab[ev-1].fired`). |
| 9 | B0 | 0x0C | EnableEvent | 0x800404A4 | **HANDLED** | `xenolift_bios_gate` B0:0x0C: Marks `enabled = 1` in `evt_tab`, returns handle. |
| 10 | B0 | 0x0D | DisableEvent | 0x800404B4 | **HANDLED** | `xenolift_bios_gate` B0:0x0D: Marks `enabled = 0` in `evt_tab`, returns handle. |
| 11 | B0 | 0x20 | WithdrawKernelEvent | 0x800404C4 | **LATENT** | Default `v0=0`; kernel event withdraw. Unused by Movie overlay. |
| 12 | B0 | 0x32 | AcquireBiosFileHandle | 0x80040534 | **LATENT** | Default `v0=0`; low-level BIOS open. Kernel uses ISO archive layer at 0x80028xxx. |
| 13 | B0 | 0x34 | FetchBiosFileBytes | 0x80040544 | **LATENT** | Default `v0=0`; low-level BIOS read. Kernel uses internal CD slot queue. |
| 14 | B0 | 0x35 | StoreBiosFileBytes | 0x80040554 | **LATENT** | Default `v0=0`; low-level BIOS write. |
| 15 | B0 | 0x36 | ReleaseBiosFileHandle | 0x80040564 | **LATENT** | Default `v0=0`; low-level BIOS close. |
| 16 | B0 | 0x41 | FormatMemoryCard | 0x80040574 | **LATENT** | Default `v0=0`; memory card format. |
| 17 | B0 | 0x42 | FindFirstMemoryCardFile | 0x80040584 | **LATENT** | Default `v0=0`; memory card file search. |
| 18 | B0 | 0x43 | FindNextMemoryCardFile | 0x80040594 | **LATENT** | Default `v0=0`; memory card file search continuation. |
| 19 | B0 | 0x44 | ChangeCardFileName | 0x800405A4 | **LATENT** | Default `v0=0`; memory card file rename. |
| 20 | B0 | 0x45 | DeleteMemoryCardFile | 0x800405B4 | **LATENT** | Default `v0=0`; memory card file delete. |
| 21 | B0 | 0x51 | AppendKanjiGlyphPixels | 0x800405C4 | **LATENT** | Default `v0=0`; kanji glyph / card status. |
| 22 | B0 | 0x5B | SwapPadClearHandler | 0x800405D4 | **HANDLED** | `xenolift_bios_gate` B0:0x5B: Logs driver object init args (`[gate5B]`), returns `r[2] = 0`. |
| 23 | B0 | 0x12 | InitPAD | 0x80040A8C | **AT-RISK** | Unstubbed in `xenolift_bios_gate` (logged under `[task] enter`). Initializes pad buffer pair at 0x800625FC. |
| 24 | B0 | 0x13 | StartPAD | 0x80040A9C | **AT-RISK** | Unstubbed in `xenolift_bios_gate` (default `v0=0`). Starts background pad polling. |
| 25 | B0 | 0x14 | StopPAD | 0x80040AAC | **LATENT** | Default `v0=0`; stops pad driver. |
| 26 | B0 | 0x15 | EnablePAD / PAD_dr | 0x80040ABC | **LATENT** | Default `v0=0`; pad driver enable/disable. |
| 27 | B0 | 0x07 | DeliverEvent | 0x80040E18 | **HANDLED** | `xenolift_bios_gate` B0:0x07: Invokes `evt_deliver_class(r[4], r[5])` across event table. |
| 28 | B0 | 0x17 | ReturnFromException | 0x8004BEF0 | **AT-RISK** | Unstubbed in `xenolift_bios_gate` (default `v0=0`). Resumes execution after CPU exception/trap. |
| 29 | B0 | 0x18 | ClearExceptionEntry | 0x8004BF00 | **LATENT** | Default `v0=0`; resets default exception exit vector. |
| 30 | B0 | 0x19 | InstallExceptionHook | 0x8004BF10 | **AT-RISK** | Unstubbed in `xenolift_bios_gate` (default `v0=0`). Installs custom exception exit callback vector. |
| 31 | B0 | 0x0A | WaitEvent | 0x8004E564 | **HANDLED** | `xenolift_bios_gate` B0:0x0A: Checks `evt_tab`, reports delivered, consumes `fired = 0`, returns 1. |
| 32 | B0 | 0x4A | InitializeCardInterface | 0x8004E850 | **LATENT** | Default `v0=0`; memory card interface init. |
| 33 | B0 | 0x4B | ActivateCardInterface | 0x8004E860 | **LATENT** | Default `v0=0`; memory card interface enable. |
| 34 | B0 | 0x4C | DeactivateSecondCardInterface | 0x8004E870 | **LATENT** | Default `v0=0`; memory card interface disable. |
| 35 | C0 | 0x02 | SysEnqIntRP | 0x80040ACC | **HANDLED** | `xenolift_bios_gate` C0:0x02: Inserts interrupt handler struct into shadow chain, returns 0. |
| 36 | C0 | 0x03 | SysDeqIntRP | 0x80040ADC | **HANDLED** | `xenolift_bios_gate` C0:0x03: Logs interrupt handler unregistration, returns 0. |
| 37 | C0 | 0x0A | ChangeClearRCnt | 0x8004B730 | **AT-RISK** | Unstubbed in `xenolift_bios_gate` (default `v0=0`). Configures Root Counter 0/1/2 clear mode/handler. |

---

## TOP 5 THUNKS TO PREPARE (Movie-Module Lens)

### 1. C0:0x0A — ChangeClearRCnt (`0x8004B730`)
- **Category**: Root Counter Control / Timing
- **Movie-Module Hazard**: Movie overlay diagnostic verification (`MovieAdvanceCdReadVerification`) and stress-test read loops rely on Root Counter 2 (VSync clock / tick timer) for pacing and timeout checks.
- **PS1 BIOS Semantics**: `ChangeClearRCnt(rcnt, flag)` sets whether root counter `rcnt` (0=dotclock, 1=HBLANK, 2=sysclock/VSync) automatically clears to zero when it reaches target value or VSync pulse (`flag=1`: auto-clear on target; `flag=0`: continuous count). Returns previous flag mode.
- **Kernel Requirement**: Kernel BSS cells and timer loops expect `ChangeClearRCnt(2, 1)` to enable auto-clearing Root Counter 2 mode. Returning 0 without updating the MMIO counter mode flags causes timer loops polling counter targets to overshoot or freeze.
- **Recommended Action**: Add `case 0x0A:` under `case 0xC0:` in `xenolift_bios_gate`. Track auto-clear flags for RCnt 0/1/2 in runtime state, update MMIO mode registers at `0x1F801104`, `0x1F801114`, `0x1F801124`, and return the previous flag value in `r[2]`.

### 2. B0:0x17 — ReturnFromException (`0x8004BEF0`)
- **Category**: Exception & Interrupt Flow Control
- **Movie-Module Hazard**: Movie overlay diagnostic suite traps CD read errors and exception conditions. When a diagnostic routine or async verification step triggers an exception (e.g., break instruction, syscall, or CD error trap), control passes to the exception handler, which finishes with `ReturnFromException`.
- **PS1 BIOS Semantics**: Restores saved CPU Coprocessor 0 registers (Status, EPC) and returns control to the instruction following the exception trigger.
- **Kernel Requirement**: Currently unhandled in `xenolift_bios_gate` (returns `v0 = 0`), which causes exception control flow to drop through or fail to restore PC/stack frame, immediately triggering the `fn_80019ACC` error dispatcher spike and restarting the boot loop.
- **Recommended Action**: Implement `case 0x17:` under `case 0xB0:` in `xenolift_bios_gate`. Restore saved register context/EPC from the kernel exception frame (at `0x80000080` / stack frame) or dispatch back to saved `` / `EPC` to maintain recompiled execution continuity.

### 3. B0:0x19 — SetCustomExitFromException (`0x8004BF10`)
- **Category**: Exception Recovery & Vector Installation
- **Movie-Module Hazard**: Installed by diagnostic frameworks to override the default kernel exception exit vector with a custom cleanup/recovery routine. When Movie diagnostic reads fail or encounter test boundary conditions, the custom exit hook restores CD queue state.
- **PS1 BIOS Semantics**: `SetCustomExitFromException(addr)` sets the address executed when `ReturnFromException` exits. Returns the previous exit handler address.
- **Kernel Requirement**: Returning 0 without saving the handler address prevents the diagnostic suite from registering its exception recovery hook.
- **Recommended Action**: Implement `case 0x19:` under `case 0xB0:` in `xenolift_bios_gate`. Store `r[4]` (handler address) in a runtime global cell `g_custom_exception_exit` and return the old address in `r[2]`.

### 4. B0:0x13 — StartPAD (`0x80040A9C`)
- **Category**: Controller & Input Subsystem
- **Movie-Module Hazard**: Activates background SIO DMA transfers for controller pad polling. Movie module diagnostic main loop probes pad button state to check for user abort / skip inputs.
- **PS1 BIOS Semantics**: `StartPAD()` starts the BIOS controller polling timer/DMA interrupt and enables pad buffer updates into the buffer addresses provided to `InitPAD`. Returns 1.
- **Kernel Requirement**: Returning `v0 = 0` leaves pad background polling disabled, causing pad state buffers (`0x800625FC`) to remain stale, which can block diagnostic loops waiting for pad handshake completion.
- **Recommended Action**: Implement `case 0x13:` under `case 0xB0:` in `xenolift_bios_gate`. Set `g_pad_active = 1`, trigger an initial pad buffer update into `0x800625FC`, and return `r[2] = 1`.

### 5. B0:0x12 — InitPAD (`0x80040A8C`)
- **Category**: Controller Subsystem Initialization
- **Movie-Module Hazard**: Precedes `StartPAD` during subsystem boot. Binds controller memory buffers (`buf1`, `len1`, `buf2`, `len2`) for Port 1 and Port 2.
- **PS1 BIOS Semantics**: `InitPAD(buf1, len1, buf2, len2)` registers dual pad receive buffers (Xenogears registers pair at `0x800625FC` and `0x8006261E`, 34 bytes each).
- **Kernel Requirement**: Currently has a diagnostic log entry (`[task] enter 0x80040A8C`) but is unhandled in `xenolift_bios_gate` (returns `v0 = 0`).
- **Recommended Action**: Add `case 0x12:` under `case 0xB0:` in `xenolift_bios_gate`. Record buffer pointers `r[4]` (`0x800625FC`) and `r[6]` (`0x8006261E`) in runtime state, clear buffer headers to indicate connected digital controller (ID `0x41`), and return `r[2] = 1`.

---

## Subsystem Analysis: Movie-Module Specific Thunks

1. **Event System (WaitEvent / DeliverEvent / OpenEvent)**:
   - **Status**: **100% HANDLED** (7/7 thunks handled in `xenolift_bios_gate`: `OpenEvent` B0:0x08, `CloseEvent` B0:0x09, `TestEvent` B0:0x0B, `EnableEvent` B0:0x0C, `DisableEvent` B0:0x0D, `DeliverEvent` B0:0x07, `WaitEvent` B0:0x0A).
   - **Findings**: The event subsystem in `runtime.c` provides full table allocation (`evt_tab`), class delivery (`evt_deliver_class`), and non-blocking wait handling suitable for static recompiled execution.

2. **Root Counters & Timing (ChangeClearRCnt C0:0x0A)**:
   - **Status**: **UNHANDLED** (0/1 thunks handled).
   - **Findings**: Root counter clear-mode configuration is currently unhandled. Movie module stress-test VSync timing relies on Root Counter 2 auto-clear behavior.

3. **Pad Input (InitPAD B0:0x12, StartPAD B0:0x13, ChangeClearPAD B0:0x5B)**:
   - **Status**: **PARTIALLY HANDLED** (1/3 handled: `ChangeClearPAD` B0:0x5B is handled; `InitPAD` B0:0x12 and `StartPAD` B0:0x13 are unhandled).
   - **Findings**: `runtime.c` direct-writes pad cell `0x800625FC`, but BIOS level `InitPAD` and `StartPAD` calls from Movie module code return 0 without enabling active pad polling.

4. **Exception Subsystem (ReturnFromException B0:0x17, SetCustomExitFromException B0:0x19)**:
   - **Status**: **UNHANDLED** (0/2 handled).
   - **Findings**: Exception returns and custom exit vector installation are unhandled, presenting a direct risk when Movie diagnostic verification traps CD read errors.
