# Xenolift CD-ROM & File-System Emulation Audit (`CD_AUDIT.md`)

**Project:** Xenolift PS1 Recompilation — Xenogears SLUS-006.64  
**Date:** September 12, 2026  
**Scope:** Complete Virtual CD Drive & File-System Emulation Audit (excluding known frame-5 batch issue)  
**Primary References:** `xenolift/runtime/runtime.c`, `disc1.c`, `research_cd_spec.md`, `psx-spx` (`cdromdrive.txt`, `cdrominternal.txt`)

---

## 1. Executive Summary & Audit Context

The Xenolift HLE runtime (`xenolift/runtime/runtime.c`, ~3.9k lines) emulates the PS1 CD-ROM controller (`0x1F801800–0x1F801803`), sector data FIFO, and IRQ delivery. Currently, the intro movie renders frames 1–4 then wedges. Execution logs show 195s runs dominated by recurring HLE interventions:
- **`[cd] spin-conv / fd-tick: converting stuck INT1 via handler pair`**
- **`[cd] TOC-RESTORE: full N-byte answer restored`**
- **`[cd] re-primed response FIFO (status 0x02, last_cmd=0x13)`**
- **`[lad2] restored pending state N for cmd 0xXX — dispatching`**
- **`[zrf] zero-length read: manufactured first sector`**
- **`[seek7] state-7 wedge @movie batch boundary: assist FIRED`**

These mechanisms are temporary workarounds that mask fundamental divergences between our HLE model and real PS1 CD-ROM hardware. This audit identifies every workaround, traces it to its root cause in the CD model, details the hardware-faithful fix, and ranks the fixes by impact on (a) movie completion, (b) field module loading (21MB files), and (c) long-run system stability.

---

## 2. Task 1: Audit of the INT1-Stuck & Workaround Pattern

### 2.1 Mapping HLE Workarounds to Real Hardware Behavior

| Workaround Tag / Location in `runtime.c` | HLE Workaround Mechanism | Real PSX Hardware Behavior | Upstream CD Model Bug in `runtime.c` |
|---|---|---|---|
| **`spin-conv` / `fd-tick` / `cd_force_deliver_int1`**<br>`runtime.c:2170, 2413, 6081, 7163` | Forcibly invokes guest IRQ handler pair (`0x800409E4`, `0x80040A4C`) + collector (`0x800415B4`) when `cd_pending != 0` during wait spins. | CD controller raises CPU HW IRQ line (`INT1` DataReady / `INT2` Complete / `INT3` Ack); CPU hardware interrupt vector executes guest IRQ handler asynchronously. | HLE uses lazy event delivery tied to function entry probes (`0x8004B894`). Guest wait loops polling `HSTS` (`0x1F801800`) or RAM flag (`0x800578A6`) do not trigger asynchronous IRQs, trapping `INT1` in `cd_pending`. |
| **`re-primed response FIFO`**<br>`runtime.c:625–644` | On `HSTS` (`0x1F801800`) read, if `cd_resp_pos >= cd_resp_n`, re-fills `cd_resp[0] = 0x02` or replays `cd_last_full` multi-byte answer. | `HSTS` bit 5 (`RSLRRDY`) reflects non-empty Result FIFO (`head != tail`). Status reads are strictly non-destructive/side-effect-free. | The response buffer was modeled as a single scalar buffer rather than a FIFO queue. Passive status reads modified `cd_resp` state, and `GetStat` polls destroyed un-popped multi-byte answers. |
| **`TOC-RESTORE` / `cd_restore_pend` / `cd_pend_ans`**<br>`runtime.c:272, 7217–7226` | Saves multi-byte answers (`GetTN` 0x13 -> 3B `02 01 01`, `GetTD` 0x14 -> 3B, `Getloc` 0x10/11 -> 8B, `GetID` 0x1A -> 8B) and restores them to `cd_resp` before forced IRQ delivery. | Multi-byte answers are pushed sequentially into the 16-byte Response FIFO by the HC05 controller upon command ACK (`INT3`) and remain queued until popped from `0x1F801801`. | `cd_cmd` immediately overwrites `cd_resp` on every command write. Intervening `GetStat` (0x01) polls from the guest thread overwrite `cd_resp` with 1 byte before the IRQ handler pops the 3-byte answer. |
| **`[lad2]` Ladder State Restore**<br>`runtime.c:699–796` | Rewrites CDFS request phase cell `0x8004FE1C` back to expected target state (e.g. 11 for `GetTN`) and dispatches `h2` (`0x8002A68C`) when `0x1F801801` is popped. | Hardware IRQ delivers within microseconds of command ACK, executing the handler before the main thread file-queue stepper can overwrite `0x8004FE1C`. | Execution latency gap in HLE between command issue, response pop, and IRQ execution allows main-thread state machines to corrupt `0x8004FE1C`. |
| **`spin-kick` / At-Target Kick**<br>`runtime.c:653–676, 2271–2305, 6003–6014` | Steps request stepper `h2` (`0x8002A68C`) when guest polls `GetStat` with formed target LBA in `0x8004FE04` and idle drive. | When a new LBA is issued to `0x8004FE04`, the driver writes `Setloc` + `ReadN` to MMIO, which triggers hardware command ACK (`INT3`) and sector `INT1`. | Virtual drive becomes idle (`cd_read_active = 0`) without raising an IRQ or setting slot bits, leaving `h2` un-awakened. |
| **`[zrf]` Zero-Length Read Assist**<br>`runtime.c:6143–6164` | Manufactures a first sector load (`cd_data_load()`) and force-delivers `INT1` when `FDF8 == 0` during movie playback. | `ReadN` delivers sectors continuously. Guest callback `HandleCdReadyCompletion` (`0x8002B084`) calculates `remaining -= 0x800` and finalizes request. | Sector loading in `runtime.c` was gated on `FDF8 != 0`, preventing 0-byte header reads or CDFS streaming requests from ever loading sectors or firing callbacks. |
| **`fd-retire` Stale Request Retirement**<br>`runtime.c:6088–6123` | Clears `0x8004FE1C` and `0x8004FE04` to 0 when a zero-length request sits idle for 2+ ticks without movie live. | Zero-length archive FAT entries complete instantly when processed by CDFS driver. | HLE failed to signal instant completion for empty archive members, causing pre-wait loops in `PollArchiveTransfer` (`0x800286CC`) to stall. |

---

## 3. Task 2: Response-FIFO Re-priming & Lazy Delivery Stomps

### 3.1 Trace Analysis & Hardware Specification
The HLE `[rspop]` traces show commands such as `0x13 GetTN` generating a 3-byte response `02 01 01` (`stat, first_track, last_track`). However, before the guest IRQ handler reads port `0x1F801801`, the response gets truncated to a single status byte `02`.

#### Hardware Specification (psx-spx `cdromdrive.txt` & `cdrominternal.txt`):
1. **FIFO Depth & Structure:** The CD-ROM controller contains a 16-byte Result/Response FIFO.
2. **Push Mechanism:** When a command is processed by the HC05 microcontroller, return bytes (1 to 8 bytes) are pushed sequentially into the Result FIFO, and `INT3` (or `INT2`/`INT1`) is raised.
3. **Pop Mechanism:** Reading MMIO port `0x1F801801` (Bank 1 `RESULT`) pops one byte from the head of the FIFO.
4. **Status Flags:** Bit 5 (`RSLRRDY`) of `HSTS` (`0x1F801800` Read) is `1` whenever `fifo_count > 0` and `0` when empty.
5. **Read Neutrality:** Reading `0x1F801800` is purely non-destructive and MUST NOT alter FIFO head/tail pointers or payload bytes.

### 3.2 Mechanism of Truncation in `runtime.c`
In `runtime.c`, the response mechanism was implemented with three structural flaws:
1. **In-Place Buffer Overwrite in `cd_cmd`:** Calling `cd_cmd(cmd)` executes:
   ```c
   cd_resp_n = 0; cd_resp_pos = 0;
   cd_resp[cd_resp_n++] = stat0;
   ```
   When `GetTN` (0x13) is issued, `cd_resp` receives 3 bytes (`02 01 01`). Because HLE IRQ delivery is lazy, control returns to the guest thread before the IRQ handler runs. The guest thread calls `CdAsyncGetStatus` (sending `0x01 GetStat`). `cd_cmd(0x01)` runs, resets `cd_resp_n = 1`, and overwrites `cd_resp` with single byte `02`. The 3-byte TOC answer is destroyed before it can be read.
2. **State-Modifying Status Reads in `cd_read`:** `cd_read(0x1F801800)` checks `if (cd_resp_pos >= cd_resp_n)` and re-primes `cd_resp` with a 1-byte status, introducing destructive side-effects into passive status register polling.
3. **Truncated TOC Consequences:** When the guest IRQ handler finally reads `0x1F801801`, it reads 1 byte instead of 3. Bit 5 (`RSLRRDY`) drops to 0 immediately. The guest CDFS driver sees a malformed TOC and enters an infinite retry loop (`GetTN` -> `GetStat` -> `GetTN`).

### 3.3 Minimal PSX-Faithful Fix
To eliminate response truncation and re-priming entirely:
1. **16-Byte Ring Buffer FIFO:** Replace `cd_resp[16]` and `cd_resp_pos`/`cd_resp_n` with a formal FIFO:
   ```c
   static uint8_t cd_fifo[16];
   static uint8_t cd_fifo_head = 0, cd_fifo_tail = 0, cd_fifo_count = 0;
   ```
2. **Non-Destructive Status Read (`0x1F801800`):**
   ```c
   // Bit 5 (0x20) = RSLRRDY: Result FIFO not empty
   return (cd_index & 3u) | 0x04u | (cd_fifo_count > 0 ? 0x20u : 0u) | (cd_data_available ? 0x40u : 0u);
   ```
3. **Synchronous IRQ Dispatch on Command Write:** Execute the guest IRQ handler pair immediately inside `cd_cmd` or `cd_write(0x1F801801)` upon command issuance, ensuring the response is consumed before the guest main thread can issue a subsequent `GetStat` poll.

---

## 4. Task 3: Complete Workaround Audit & Impact Ranking Table

The table below catalogs every HLE workaround in `runtime.c`, its underlying root cause, the hardware-faithful fix, associated risk, and ranked impact priority for:
- **(a) Movie completion** (intro FMV frames 1–4 wedge)
- **(b) Field module loading** (21MB overlay and asset file loading)
- **(c) Long-run stability** (multi-hour deterministic execution)

### 4.1 Master Audit Table

| # | Workaround Tag / Location | Root Cause in CD Model | Hardware-Faithful Fix | Risk | Impact Priority |
|---|---|---|---|---|---|
| **1** | **`TOC-RESTORE` / `cd_pend_ans`**<br>(`runtime.c:272, 7217`) | `cd_cmd` overwrites `cd_resp` in-place when intermediate `GetStat` (0x01) polls occur before the guest IRQ handler pops multi-byte answers (`GetTN` 3B, `Getloc` 8B, `GetID` 8B). | Implement a 16-byte ring-buffer FIFO (`cd_fifo[16]`) where command answers append to `fifo_tail` and reads pop from `fifo_head`. | **Low.** Standard PSX HW behavior; eliminates TOC truncation. | **HIGH (Movie & Field)**<br>Required for CDFS verification and file FAT lookup. |
| **2** | **`re-primed response FIFO`**<br>(`runtime.c:625–644`) | Status register reads (`0x1F801800`) re-fill `cd_resp` on empty reads to prevent guest polling deadlocks, making status reads non-const and destructive. | Remove re-priming logic; return bit 5 (`0x20`) as `cd_fifo_count > 0 ? 0x20 : 0`. Keep FIFO purely push/pop driven. | **Medium.** Requires IRQ delivery to be reliable so FIFO never starves legitimate waiters. | **HIGH (Stability)**<br>Eliminates infinite GetStat poll treadmills. |
| **3** | **`spin-conv` / `fd-tick INT1 conversion`**<br>(`runtime.c:2170, 2413, 6081`) | Lazy IRQ delivery attached to function entry probes fails to trigger CPU IRQ exceptions when guest code enters leaf polling loops on `HSTS` or RAM cells. | Synchronously execute the guest IRQ handler pair (`0x800409E4`/`0x80040A4C`) upon command completion and sector DMA arming before returning to guest thread. | **Medium.** Must maintain correct register save/restore (`r[0..31]`, `hi`, `lo`) during IRQ execution. | **HIGH (Movie)**<br>Unblocks sector consumption in FMV slice loop. |
| **4** | **`[zrf]` Zero-Length Read Assist**<br>(`runtime.c:6143–6164`) | `cd_data_load()` and `INT1` generation were gated on `FDF8 != 0` (remaining bytes), suppressing sector loads for 0-byte header reads and FMV streaming requests. | Decouple sector data loading from `FDF8`; trigger sector reads and `INT1` generation strictly based on `ReadN`/`ReadS` command state. | **Low.** Aligns sector FIFO delivery directly with hardware `ReadN` state. | **HIGH (Movie)**<br>Directly addresses the frame 1–4 movie wedge. |
| **5** | **`[lad2]` State Restore**<br>(`runtime.c:699–796`) | HLE execution delay between command issue, response pop, and IRQ execution allows guest main-thread file stepper to overwrite request phase cell `0x8004FE1C`. | Deliver `INT3` / `INT1` synchronously within `cd_cmd` / sector read before guest thread re-enters main file queue stepper loop. | **Medium.** Requires exact state tracking for `FE1C` phase transitions. | **MEDIUM (Field)**<br>Ensures CDFS state machine advances across multi-file loads. |
| **6** | **`spin-kick` / At-Target Kick**<br>(`runtime.c:653, 2271, 6003`) | Virtual drive transitions to idle (`cd_read_active = 0`) without setting slot bits or firing IRQs when target LBA `0x8004FE04` is set, leaving `h2` unawakened. | Ensure `Setloc` (0x02) and `ReadN` (0x06) command writes automatically awaken `h2` via standard `INT3` ack delivery. | **Low.** Standard driver command flow. | **MEDIUM (Field)**<br>Prevents file queue stalls when requesting contiguous sectors. |
| **7** | **`fd-retire` Stale Request Retirement**<br>(`runtime.c:6088–6123`) | HLE model did not report instant completion for zero-length FAT entries, leaving stale request markers in `0x8004FE1C`/`0x8004FE04`. | Complete zero-length archive requests immediately in the CDFS FAT lookup handler without queuing CD-ROM hardware reads. | **Low.** Pure high-level CDFS logic fix. | **LOW (Stability)**<br>Prevents rare pre-wait loop stalls. |

---

## 5. Register & Cell Level Reference Summary

### 5.1 Hardware MMIO Registers (`0x1F801800–0x1F801803`)
- `0x1F801800` (Read): **Host Status Register `HSTS`**
  - Bit 5 (`0x20`): `RSLRRDY` — Result FIFO Read Ready (1 = 1+ bytes in `RESULT`).
  - Bit 6 (`0x40`): `DRQSTS` — Data FIFO Request (1 = Sector data ready in `RDDATA`).
  - Bit 7 (`0x80`): `BUSYSTS` — HC05 Controller Busy.
- `0x1F801801` (Write Bank 0 / Read Bank 1): **`COMMAND` / `RESULT`**
  - Write: Issue opcode (`0x01 GetStat`, `0x02 Setloc`, `0x06 ReadN`, `0x08 Stop`, `0x09 Pause/ReadS`, `0x0E Setmode`, `0x13 GetTN`, `0x14 GetTD`, `0x10 GetlocL`, `0x11 GetlocP`, `0x1A GetID`).
  - Read: Pop 1 byte from Response FIFO head.
- `0x1F801802` (Read Bank 0..3 / Write Bank 1): **`RDDATA` / `HINTMSK`**
  - Read: Pop 1 byte/word from 2048/2340-byte sector Data FIFO.
- `0x1F801803` (Read/Write Bank 1): **`HINTSTS` / `HCLRCTL`**
  - Read: Interrupt status bits (1 = `INT1` DataReady, 2 = `INT2` Complete, 3 = `INT3` Ack).
  - Write: Acknowledge interrupt (write `0x07` or `0x1F` to clear).

### 5.2 Guest Kernel RAM Cells
- `0x8004FE04`: Requested/Target LBA (CDFS active request target).
- `0x8004FDF8`: Bytes remaining in active sector transfer (`FDF8`).
- `0x8004FE1C`: Per-request phase counter / CDFS async wait cell (`FE1C`).
- `0x800578A6`: Device operation pending flag (1 = pending, 0 = idle).
- `0x800564A8`: Pointer to request stepper handler `h2` (`0x8002A68C`).
- `0x800564AC`: Pointer to sector reader handler `h4` (`0x8002B084`).
- `0x800409E4` & `0x80040A4C`: Registered CD IRQ handler pair.
- `0x800415B4`: Collector scan function (`fn_800415B4`).

---
