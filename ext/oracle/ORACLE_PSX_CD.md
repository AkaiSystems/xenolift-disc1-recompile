# PSX CD-ROM — verified oracle semantics (psxrecomp cdrom.c)

Source: `psxrecomp_cdrom.c` (full copy in this folder) from OpokXeno/psxrecomp —
the hardware-accurate runtime that runs Xenogears (SLUS-006.64) through the
opening PLAYABLY. These are the semantics our HLE CD layer must honor.
Retrieved 2026-09-12 (Jos directive: study/learn/test/verify vs the recomp oracle).

## Status register bits (index 0x1F801800 idx0 read)
```
ERROR 0x01 | MOTOR 0x02 | SEEKERR 0x04 | IDERROR 0x08
SHELL 0x10 | READ 0x20 | SEEK 0x40 | PLAY 0x80
```

## Command phases (each command: response_clear() FIRST, then push + IRQ)
- **GetStat (0x01)**: 1 byte = stat (MOTOR set if disc). INT3 ack.
- **SetLoc (0x02)**: 3 BCD MSF params → store seek target; tracks "far seek"
  (>16 sectors delta). INT3 ack w/ stat.
- **ReadN (0x06)**: INT3 ack + status, THEN stream: first sector after
  `initial_read_delay_cycles()`, then per-sector: `read_sector_at(current MSF)`
  → sector buffer → response = stat (READ bit set) → **INT1 DATA_READY** →
  kernel drains data FIFO (DMA) → MSF advances → repeat. Stream continues
  until Pause/Stop/Seek changes drive state.
- **Stop (0x08)**: INT3 ack (pre-stop status) → pending INT2 COMPLETE after
  spin-down delay, status with MOTOR cleared.
- **Pause (0x09)**: INT3 ack → pending INT2 COMPLETE after delay, READ bit
  cleared. Drive-state change CANCELS any pended notification (Beetle AIP
  behavior: Play/Read/Pause/Stop/Seek all cancel pending).
- **MotorOn (0x07)**: INT3 → pending INT2 w/ MOTOR set. If already spinning:
  INT5 + error 0x20.
- **GetTN (0x13)**: TOC answer, INT3.
- **Init (0x0A)**: ack → pending INT2.

## THE ORACLE LESSONS (bugs they hit that we must not repeat)
1. **Pending-deadline must be ABSOLUTE**: "do not push due_cyc forward while
   the response FIFO is busy (old relative freeze under/over-counted mid-slice
   acks and **forked Pause→Seek→ReadN**)". Ack gates only *presentation*.
   ⇒ If a pending INT2 (Pause/Stop complete) waits for the FIFO to clear and
   the kernel leaves responses unconsumed, the completion NEVER lands and the
   kernel never advances to SetLoc/ReadN. Our park states show resp_n=3
   unconsumed — AUDIT our pending-arm logic for this exact trap.
2. **Two-phase Stop/MotorOn**: games that stop the drive on scene change then
   wait for completion IRQ hang forever if the second INT never fires.
3. **Drive-state change cancels pended notifications** (start_read_stream
   clears pending dataready; Play/Read/Pause/Stop/Seek alike).
4. **ReadN delivers from the SEEK position set by SetLoc** — the read position
   lives in the DRIVE (seek_min/sec/sect), not in the kernel. When the kernel
   re-arms a new file, it MUST go SetLoc(new MSF) → ReadN. A correct drive
   honors the LATEST SetLoc.
5. **Missing-command default = INT5 error w/ no code** broke Tsumu Light's
   retry loop — every command the game issues needs its real phase shape.

## Mapping to our wedge (movie→field, file 14 @ LBA 108933)
Native chain on hardware: movie ends → driver Pause/Stop → INT2 complete →
SetLoc(108933 MSF) → ReadN → INT3 → INT1/sector → kernel data handler walks
FE04++/FDF8-=2048 → 62 sectors → file done → field module unpack.
Our wedge: the SetLoc/ReadN for 108933 never issues (arm never fires) — the
ladder re-arms the STALE stream because our zrf/cdf keeps the drive "busy"
serving 108605 forever. R359 seed v2 (FE04/FDF8 cells + read_active/data_loaded
wake) engages the delivery rail directly; the oracle confirms the INT1-push
per-sector model is exactly how data reaches the kernel, so the rail shape is
right. If R359 stalls, audit against lesson 1 (pending vs unconsumed FIFO).

## VERIFIED: end-of-file read semantics (agent check, cycle 111)

- **Multi-request read boundary & zero-length requests (Q1)**:
  - The drive does NOT deliver INT1 DATA_READY for zero-length or position-only requests (`SetLoc`, lines 1837–1851, returns INT3 ACK only).
  - Data-ready INT1 signals are pushed exclusively by `deliver_read_sector()` during active sector streaming (lines 1636–1646).
  - The game's finalize path issues `Pause` (0x09, lines 1916–1929), expecting an immediate INT3 ACK, followed by an **INT2 COMPLETE** from `process_pending()` (lines 2265–2270) with `CDSTAT_READ` (0x20) cleared and `CDSTAT_MOTOR` (0x02) set (status = 0x02).

- **Absolute deadlines & ack-gated presentation (Q2)**:
  - **CONFIRMED**: `pending.due_cyc` is initialized to `psx_cycle_count + latency` in `pending_arm()` (lines 653–659).
  - In `process_pending()` (lines 2225–2230):
    ```c
    /* Absolute drive deadline: due_cyc advances with guest time regardless of
     * slice quantum or irq_flag. Ack only gates *presentation* — do not push
     * due_cyc forward while the response FIFO is busy (old relative freeze
     * under/over-counted mid-slice acks and forked Pause->Seek->ReadN). */
    if (psx_cycle_count < pending.due_cyc) return;
    if (irq_flag != 0) return;
    ```
  - `due_cyc` is an absolute timestamp on the guest timeline (lines 626–629); an active `irq_flag != 0` delays IRQ presentation without pushing `due_cyc` forward.

- **Cadence & completion signals (Q3)**:
  - The oracle produces exactly one INT1 DATA_READY per streamed sector in `deliver_read_sector()` (lines 1636–1646, `s_dataready_fires++`), matching the game consumer callback cadence (1 call per sector).
  - The drive has no concept of file length; `ReadN` streams indefinitely until interrupted by `Pause`/`Stop`/`Seek`. No extra completion signal or INT5 error is generated at EOF. Finalize completion (INT2) comes solely from the subsequent `Pause`/`Stop` command.
