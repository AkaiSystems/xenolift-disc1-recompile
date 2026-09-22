# Xenolift Boot Handler Decode (Second Pass) — HANDLER_MAP.md

**Target Binary:** PS-EXE `SLUS_006.64` (Xenogears USA Disc 1)  
**Deliverable Path:** `xenolift/hle/qa/HANDLER_MAP.md`  
**Date:** 2026-09-11  

---

## 1. Overview & Architecture

The Xenogears kernel boot handler manages module selection, memory (BSS) clearing, module installation via CD-ROM archive reads, stack resets, and module execution. 

During early boot, `boot_main` (0x80019578) initializes hardware subsystems, selects Module Index 6 (file 18, LBA 109158), and transfers control to the boot handler launcher `fn_80019ACC` (0x80019ACC).

When an enqueued archive read fails to start or complete (e.g. CD DMA driver stalled), the overlay region at `0x800737EC` remains unpopulated (all zeros). Upon jumping to `0x800737EC`, the CPU immediately returns to `0x80019C0C`, re-entering `fn_80019ACC` every ~0.18 seconds (~5.5 Hz). Each re-entry re-enqueues the archive read and wipes the stack, creating an infinite restart loop.

---

## 2. Task 1: Restart Condition Decode

### 2.1 State Compare & Branch Logic

The restart condition is controlled by a **state compare on a module descriptor table cell**, combined with an **unconditional return-trigger loop** upon module execution return. It is **NOT a timer or counter timeout**.

#### Module Descriptor Array Structure
- **Table Base Address:** `0x8001808C`
- **Active Module Index Cell:** `0x80018088` (stored as integer index $k$, e.g., $k = 6$ for Module 6)
- **Descriptor Address Calculation:** $\text{s1} = \text{0x8001808C} + (k \times 16)$

Each 16-byte descriptor entry contains:
- `+0` (`0(s1)`): Module Entry Point VA (e.g., `0x800737EC` for Module 6)
- `+4` (`4(s1)`): BSS Start VA (e.g., `0x80076F38` for Module 6)
- `+8` (`8(s1)`): BSS End VA (e.g., `0x80077454` for Module 6)
- `+12` (`12(s1)`): Module Install Required Flag (`1` = BSS clear + archive load required; `0` = skip install)

#### Annotated Disassembly (0x80019B48 – 0x80019C10)

```mips
; --- Module State Check ---
0x80019B4C: 8E22000C  lw   v0, 12(s1)         ; v0 = s1->install_required_flag (12(s1))
0x80019B50: 00000000  nop                     ; Load delay slot
0x80019B54: 1040001E  beq  v0, zero, 0x80019BD0 ; If flag == 0: skip BSS clear & install, jump to 0x80019BD0
0x80019B58: 00000000  nop                     ; Branch delay slot

; --- BSS Clearance & Module Install (when 12(s1) != 0) ---
0x80019B5C: 8E240004  lw   a0, 4(s1)          ; a0 = BSS Start VA
0x80019B60: 8E250008  lw   a1, 8(s1)          ; a1 = BSS End VA
0x80019B64: 0C006558  jal  0x80019560         ; Call bzero region (clears BSS from 4(s1) to 8(s1))
0x80019B68: 00000000  nop
0x80019B6C: 3C048002  lui  a0, 0x8002
0x80019B70: 8C848088  lw   a0, -32632(a0)     ; a0 = lw 0x80018088 (Module Index = 6)
0x80019B74: 0C006673  jal  0x800199CC         ; Call fn_800199CC (Module Installer: enqueues file 18 read)
0x80019B78: 00000000  nop

; --- Subsystem Re-initializations ---
0x80019B7C: 00002021  addu a0, zero, zero
0x80019B80: 0C00A298  jal  0x80028A60
0x80019B84: 00408021  addu s0, v0, zero
0x80019B88: 3C058002  lui  a1, 0x8002
0x80019B8C: 8CA58084  lw   a1, -32636(a1)     ; a1 = lw 0x80018084
0x80019B90: 0C00CBAD  jal  0x80032EB4
0x80019B94: 02002021  addu a0, s0, zero
0x80019B98: 0C011174  jal  0x800445D0
0x80019BA0: 0C012D53  jal  0x8004B54C
0x80019BA8: 0C010135  jal  0x800404D4
0x80019BB0: 0C011174  jal  0x800445D0
0x80019BB8: 0C012D53  jal  0x8004B54C
0x80019BC0: 0C010115  jal  0x80040454
0x80019BC8: 0C010139  jal  0x800404E4
0x80019BCC: 00000000  nop

; --- Stack Reset Routine Call ---
0x80019BD0: 0C006552  jal  0x80019548         ; Call fn_80019548 (Resets sp=0x80200000, returns to 0x80019BD8)
0x80019BD4: 00000000  nop                     ; Branch delay slot

; --- Post-Stack-Reset Continuation ---
0x80019BD8: 8E240008  lw   a0, 8(s1)          ; Return target from fn_80019548
0x80019BDC: 0C00C6C4  jal  0x80031B10
0x80019BE0: 24840004  addiu a0, a0, 4
0x80019BE4: 0C00C68C  jal  0x80031A30
0x80019BEC: 0C00D76C  jal  0x80035DB0
0x80019BF4: 0C00665B  jal  0x8001996C         ; Call fn_8001996C(0)
0x80019BF8: 00002021  addu a0, zero, zero

; --- Module Entry Jump & Loop Target ---
0x80019BFC: 8E220000  lw   v0, 0(s1)          ; v0 = s1->entry_point (0x800737EC for Module 6)
0x80019C00: 00000000  nop
0x80019C04: 0040F809  jalr ra, v0             ; Transfer control to Module 6 entry point (ra = 0x80019C0C)
0x80019C08: 00000000  nop                     ; Delay slot
0x80019C0C: 0C0066B3  jal  0x80019ACC         ; RE-ENTRY: If module returns, re-invoke fn_80019ACC(0)!
0x80019C10: 00002021  addu a0, zero, zero
```

### 2.2 Stack Reset Analysis (`fn_80019548`)

```mips
0x80019548: 3C1D8020  lui  sp, 0x8020         ; sp = 0x80200000 (Top of PS1 Kernel Stack)
0x8001954C: 03A0F021  addu fp, sp, zero       ; fp = 0x80200000
0x80019550: 3C1C8006  lui  gp, 0x8006
0x80019554: 279C9170  addiu gp, gp, -28304    ; gp = 0x80059170
0x80019558: 03E00008  jr   ra                 ; Return to caller (ra = 0x80019BD8)
0x8001955C: 00000000  nop
```

`fn_80019548` is a stack-clearing reset function. Calling `jal 0x80019548` at `0x80019BD0` sets `ra = 0x80019BD8`, resets `sp` to `0x80200000`, and returns to `0x80019BD8`.

---

## 3. Task 2: Post-Enqueue Wait Mechanism Decode

### 3.1 Disassembly Forward from `fn_800295D8` Return (`0x80019A6C`)

The module installer launcher `fn_800199CC` handles archive file lookup and CD read enqueuing.

```mips
0x80019A64: 8E040000  lw   a0, 0(s0)          ; a0 = File ID 18 (from Module File Table at 0x8004EAB8)
0x80019A68: 00003021  addu a2, zero, zero     ; a2 = 0
0x80019A6C: 0C00A576  jal  0x800295D8         ; Enqueue archive CD read for File 18 (LBA 109158)
0x80019A70: 00003821  addu a3, zero, zero     ; a3 = 0
0x80019A74: 080066A2  j    0x80019A88         ; Jump past error handler
0x80019A78: 00000000  nop                     ; Delay slot
0x80019A7C: 2402FFFF  addiu v0, zero, -1      ; Error handler (bypassed when buffer alloc succeeds)
0x80019A80: 3C018006  lui  at, 0x8006
0x80019A84: AC2292C0  sw   v0, -27968(at)
0x80019A88: 0C00C6ED  jal  0x80031BB4         ; Resource cleanup
0x80019A8C: 02202021  addu a0, s1, zero
0x80019A90: 8FA40010  lw   a0, 16(sp)
0x80019A94: 8FA50014  lw   a1, 20(sp)
0x80019A98: 0C00A11C  jal  0x80028470
0x80019AA0: 0C00C6EA  jal  0x80031BA8
0x80019AA4: 02402021  addu a0, s2, zero
0x80019AA8: 3C028006  lui  v0, 0x8006
0x80019AAC: 8C4292BC  lw   v0, -27272(v0)     ; v0 = lw 0x800692BC (allocated buffer VA)
0x80019AB0: 8FBF0024  lw   ra, 36(sp)
0x80019AB4: 8FB20020  lw   s2, 32(sp)
0x80019AB8: 8FB1001C  lw   s1, 28(sp)
0x80019ABC: 8FB00018  lw   s0, 24(sp)
0x80019AC0: 27BD0028  addiu sp, sp, 40
0x80019AC4: 03E00008  jr   ra                 ; RETURN IMMEDIATELY to caller fn_80019ACC
0x80019AC8: 00000000  nop
```

### 3.2 Wait Mechanism & Tolerated Duration

- **Poll Loop:** **NONE**.
- **Wait Function:** **NONE**.
- **Timer / Counter:** **NONE**.
- **Execution Nature:** Completely **non-blocking and asynchronous**. `fn_800199CC` enqueues the CD read and returns immediately to `fn_80019ACC`.
- **Tolerated Read Delay:** **0 CPU cycles (Instant)** within the installer itself. The kernel expects the CD DMA transfer to complete either in the background during the brief subsystem cleanup calls (`0x80019B7C` – `0x80019BCC`) or assumes the module entry point at `0x800737EC` will handle waiting for its own assets.

If the CD driver fails to dispatch/complete the read before `jalr ra, v0` executes `0x800737EC`, control enters unpopulated zeroed RAM, returning instantly to `0x80019C0C` and triggering the ~0.18s re-entry loop.

---

## 4. Task 3: Success Path & Verification Target

### 4.1 Success Path Execution Flow

Upon successful completion of the File 18 archive read (LBA 109158):

1. **CD DMA Population:** The CD driver populates RAM at `0x800737EC` with valid executable overlay code for Module 6.
2. **Control Transfer:** `0x80019C04: jalr ra, v0` executes with `v0 = 0x800737EC` and `ra = 0x80019C0C`.
3. **Module Main Execution:** Execution enters Module 6's entry point (`0x800737EC`) and **does NOT return** to `0x80019C0C`.
4. **Loop Termination:** `fn_80019ACC` is no longer re-entered, stopping the ~0.18s stack-reset and CD queue-wipe loop.

### 4.2 Three Recommended Verification Hooks

To confirm post-fix progress in future builds/digests, monitor the following function entry points:

| Hook # | Function VA | Name / Description | Pre-Fix Behavior | Post-Fix Success Target |
|---|---|---|---|---|
| **Hook 1** | `0x80019ACC` | `fn_80019ACC` (Boot Handler Launcher) | Re-entered continuously every ~0.18s (~5.5 Hz). | Called **once** during boot; no continuous re-entry. |
| **Hook 2** | `0x800295D8` | `fn_800295D8` (Archive CD Read Enqueue) | Called continuously with `a0 = 18`, repeatedly wiping the CD queue. | Called **once** for File 18; subsequent calls stop once module loads. |
| **Hook 3** | `0x800737EC` | Module 6 Entry Point (`0(s1)`) | Entered while RAM is zeros; returns immediately to `0x80019C0C`. | Entered with valid overlay code; PC remains inside `0x800737EC` module code without returning to `0x80019C0C`. |

---

## 5. Summary Table of Key VAs and Memory Cells

| Category | Virtual Address | Identifier / Rationale |
|---|---|---|
| Active Module Index Cell | `0x80018088` | Holds current module index $k$ (e.g. 6). |
| Module Descriptor Array | `0x8001808C` | Array of 16-byte struct descriptors ($16 \times k$). |
| Module 6 Entry Point | `0x800737EC` | Field `0(s1)` for $k=6$. |
| Module 6 BSS Range | `0x80076F38` – `0x80077454` | Fields `4(s1)` and `8(s1)` for $k=6$. |
| Module 6 Install Flag | `12(s1)` = `1` | Field `12(s1)` checked at `0x80019B4C`. |
| Stack Reset Routine | `0x80019548` | `fn_80019548` (sets `sp = 0x80200000`, `jr ra`). |
| Module Install Launcher | `0x800199CC` | `fn_800199CC` (enqueues File 18 read). |
| Archive Read Enqueue | `0x800295D8` | `fn_800295D8` (File 18 / LBA 109158). |
| Re-Entry Return Target | `0x80019C0C` | `jal 0x80019ACC` (Re-invokes boot handler if module returns). |
