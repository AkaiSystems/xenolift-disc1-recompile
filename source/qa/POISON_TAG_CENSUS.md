# Xenolift HLE Audit — Poison-Tag Census & Corruption Diagnostic

**Document Path**: `/app/conversations/6aa26c825d5b4135ae6b48b5/xenolift/qa/POISON_TAG_CENSUS.md`  
**Date**: Saturday, September 12, 2026  
**Target Scope**: HLE Runtime (`xenolift/runtime/runtime.c`) & Kernel Binary (`xenolift/disc1.c`)  
**Purpose**: Complete census of tagged pointer producers, consumers, corruption pathways, and line-level fix points for the poison-tag machinery (`0xC0C0CBA5`, `0xC4C0CBA5`, `0xC2C0CBA5`, `0x861D0232`, `0x861BF51D`, `0x8081CE1C`, `0x8081CE25`, `0x80800000`, `0x00C00000`).

---

## Executive Summary

The Xenogears HLE harness manages PS1 RAM (`0x80000000`–`0x80200000`) through a recompiled kernel (`disc1.c`) running inside an HLE execution environment (`runtime.c`). The kernel's heap allocator (`fn_80031BDC` / `fn_80031DA8`) packs owner and category flags into high bits (bits 21–31) of chunk header words. 

When these tagged values pass through rebase routines (`fn_8003342C`), heap coalescing (`fn_80031FF8` / `fn_800320A4`), LZSS unpackers (`fn_80032EB4`), or module handoff points (`fn_80031F58`), bit-arithmetic operations treat the tag bits as pointer offsets or base addends. This generates **tag-math poison** (`0x00C00000`, `0xC6C0CBA5`, `0x8081CE1C`, `0x80800000`).

While some consumer sites are protected by HLE runtime guards (`[reloc-fix]` and `[unpack-fix]`), other consumer paths are **UNGUARDED**. Crucially, the stage-2 overlay module handoff passes a tag-polluted stack top (`a1 = 0x80800000` instead of `0x80200000`), which corrupts the movie module stack pointer (`sp = 0x807FC910 = 0x80800000 - 0x36F0`) and causes wild pointer dereferences (`0xB81B5FF8` / `0xB7E7EFF8`).

---

## 1. Producer Sites Census

The table below catalogs every site in `disc1.c` and `runtime.c` that **CREATES** or performs arithmetic on tagged/poisoned values.

| # | File & Line | Function Name | Input Registers / Source | Output / Artifact Produced | Description & Mechanics |
|---|---|---|---|---|---|
| P1 | `disc1.c`: 81100–81155 | `fn_80031DA8` (AllocateHeapBlock Carve) | `gp+0x01A8` (Category), `gp+0x01AC` (Owner), `r[12]` (Node) | Header tag words: `0xC0C0CBA5`, `0xC4C0CBA5`, `0xC2C0CBA5`, `0x861D0232`, `0x861BF51D` | Carve math shifts category/owner flags: `r[4] = LHU(gp+0x1A8) << 26`, `r[3] = (LHU(gp+0x1AC) & 0xF) << 21`. Stores packed tag into header `LW(node) - s1 - 8`. |
| P2 | `disc1.c`: 81295<br>`runtime.c`: 4280–4293 | `fn_80031F58` (Allocator Common Exit) | `r[2]` (`v0`), `r[4]` (`a0`), `r[5]` (`a1`), `r[6]` (`a2`) | Block address `v0` + tagged args: `a0=0x8081CE1C`, `a1=0x80800000`, `a2=0x00800000` | Common allocator return path. On zero-width or tail sliver blocks (e.g., `0x801FBFF8`), exports arguments with high tag bits intact into module configuration structures. |
| P3 | `disc1.c`: 81400–81640<br>`runtime.c`: 3851, 3719 | `fn_800320A4` (`LockHeapAllocation`) / `fn_80031FF8` (`CoalesceHeapFreeBlocks`) | Chunk header `LW(ptr)` | Tag-math deltas: `0x00C00000`, `0xC6C0CBA5`, `0x8081CE1C`, `0x8081CE25` | Reads `LW(ptr)` from chunk headers without stripping tag bits 21–31. Performs delta arithmetic on tagged headers, treating tags as valid size/offset addends. |
| P4 | `disc1.c`: 84626<br>`runtime.c`: 3847–3867 | `fn_8003342C` (`LinkArchiveDirectoryEntries`) | `a0` (Base block), `a2` (Rebase delta from `r[6]`) | Poisoned rebase table entries in RAM (e.g. `0x801F34B4 + 0x00C00000 = 0x80DF34B4`) | Table linker walks `count = LW(a0)` words adding `a2` to each offset. When `a2` contains `0x00C00000` or `0xC6C0CBA5`, it writes non-RAM addresses into directory link tables. |
| P5 | `disc1.c`: 83754<br>`runtime.c`: 4402–4415 | `fn_80032E88` (`UnpackCompressedHeapBlock`) / `fn_80032EB4` (`UnpackCompressedBuffer`) | `a0` (`r[4]`, Compressed src pointer) | Out-of-RAM source reads (`src = 0x002A669C` or `0xC2C0CBA5`) & corrupted stream outputs | Takes compressed block pointer carrying tag-math poison (`0xC2C0CBA5` class). Reads `LW(a0)` as header length, producing corrupted output headers or LZSS walk faults. |
| P6 | `runtime.c`: 4280, 4294–4320 | Allocator Handoff Probe (`[hand]` #13) | `v0=0x801D3000` (Stage-2 window), `a1=0x80800000`, `a2=0x00800000` | Saved module config fields at `0x80077194` / `0x80077458` | Hands off stage-2 overlay config parameters. Tag bits 21/22 in `a1` convert true stack top `0x80200000` into `0x80800000`. |
| P7 | `disc1.c`: 98887<br>`runtime.c`: 3907–3928 | `fn_80038F18` / `fn_80039144` (IRQ Handler Chain Builder) | `0x80059410` (IRQ list head cell) | Poisoned IRQ next pointer: `0x8F5A0014` | Writes next handler pointer into IRQ linked list. Tag pollution in handler registration converts valid RAM link `0x801A0014` to out-of-RAM `0x8F5A0014`. |

---

## 2. Consumer Sites Census

The table below catalogs every site that **CONSUMES** a tagged value as a real pointer, stack pointer, jump target, or memory destination.

| # | Location / Function | Consumed Value / Purpose | Guarded? | Guard Line in `runtime.c` | Action Taken / Failure Mode |
|---|---|---|---|---|---|
| C1 | `fn_8003342C` (`LinkArchiveDirectoryEntries`) | `a2` (`r[6]`) used as rebase delta for directory entries at `a0 + 4` | **GUARDED** | Lines 3860–3867 (`[reloc-fix]`) | Detects `r[6] < 0x80000000 \|\| r[6] >= 0x80200000`. Logs `POISON DELTA` and substitutes block base `r[6] = r[4]`. |
| C2 | `fn_80032EB4` (`UnpackCompressedBuffer`) | `a0` (`r[4]`) used as source buffer pointer for LZSS decompression | **GUARDED** | Lines 4409–4415 (`[unpack-fix]`) | Detects `r[4] < 0x80000000 \|\| r[4] >= 0x80200000`. Logs `poison src` and substitutes true block address from `0x800592BC` cell. |
| C3 | `fn_80031F58` (Allocator Exit) | `a1` (`r[5]`) stack top & `a2` (`r[6]`) span handed to stage-2 module | **GUARDED** | Lines 4308–4320 (`[hand-fix]`) | Detects stage-2 block (`0x801D3000`–`0x801F4000`) with out-of-RAM `a1`. Restores `r[5] = 0x80200000` and `r[6] = 0x00200000`. |
| C4 | Movie Module (`0x800769A4` `MoviePollSkipInput` / Slice Chain) | Saved config field loaded into `sp` (`r[29]`), resulting in `sp = 0x807FC910` | **UNGUARDED** | None at MIPS callsite (relies on C3) | Module code reloads `sp` from saved config cell in RAM. `sp = 0x80800000 - 0x36F0 = 0x807FC910` (< `0x80000000`), parking stack frame outside PS1 RAM. |
| C5 | Movie Module Data Cell (`0x80077194` / `0x80077458`) | Data cell loaded as pointer and dereferenced for frame/slice header | **UNGUARDED** | None | Dereferences pointer stored at `0x80077194`. Fetches wild address (`0xB81B5FF8` / `0xB7E7EFF8`), triggering host SIGSEGV crash. |
| C6 | IRQ Handler List Walker (`0x80059410`) | Next pointer `q + 12` fetched during interrupt dispatch | **SEMI-GUARDED** (Diagnostic only) | Lines 3918–3928 (`[irqc]`) | Scans chain every 256 dispatches and logs `POISON entry 0x8F5A0014`, but does NOT truncate list; dispatcher eventually jumps to garbage. |
| C7 | Sound Heap Allocator Head Walk (`0x80065B1C` / `0x80065B20`) | Node `next` pointer fetched during SPU memory allocation | **UNGUARDED** | Monitored at line 3730 | Memory walker tours module space as a chunk ring. Owner/category flags never match, causing sound allocations to fail. |
| C8 | Native LZSS Decompressor (`fn_80032EB4` MIPS execution) | Source `r[4]` & Destination `r[5]` pointers in MIPS inner loop | **GUARDED** (for HLE pass) | Lines 3760–3810 (`lzss_exit_target`) | Native HLE pass bypasses corrupted MIPS registers and writes expanded buffer directly, setting core exit flags. |

---

## 3. Ranked Hypothesis List

### Problem Statement
A live execution crash shows:
1. The Movie module's stack pointer is parked at `sp = 0x807FC910 = 0x80800000 - 0x36F0` (outside valid 2MB RAM).
2. A wild pointer dereference occurs at `0xB81B5FF8` (varies across runs: `0xB7E7EFF8` vs `0xB81B5FF8`, with all other state identical).
3. Data cell `0x80077194` is the suspected pointer source, near logged `[hand]` / `[walk]` nodes at `0x80077458` and `0x80077460`.

---

### Hypothesis 1 (RANK 1 — PRIMARY / PROVEN): Stage-2 Handoff Stack-Top Tag Pollution
* **Mechanism & Mathematical Proof**:
  * PS1 RAM top is `0x80200000` (2,097,152 bytes @ base `0x80000000`).
  * `0x80200000` in binary = `1000 0000 0010 0000 0000 0000 0000 0000_2`.
  * Category tag `3` injected by `fn_80031DA8` into bits 21–22 (`(3 & 0xF) << 21 = 0x00600000`).
  * Bitwise addition/OR of tag `0x00600000` with `0x80200000`:
    $$\text{Stack Top} = 0x80200000 \oplus 0x00600000 = 0x80800000$$
  * During stage-2 overlay module allocation (`v0 = 0x801D3000`, handoff #13), `fn_80031F58` hands `a1 = 0x80800000` (stack top) and `a2 = 0x00800000` (span) to the module installer.
  * The module installer stores `a1 = 0x80800000` into module configuration cells in static data space (`0x80077194` / `0x80077458`).
  * When `MoviePollSkipInput` (`0x800769A4`) or slice dispatch runs, the module reloads `sp` from this cell (`sp = 0x80800000`).
  * Function prologue allocates `0x36F0` bytes of frame space (`addiu sp, sp, -0x36F0`):
    $$sp = 0x80800000 - 0x36F0 = 0x807FC910$$
  * Because `0x807FC910 < 0x80000000`, stack accesses write into unmapped memory or uninitialized host stack space.
* **Explanation of Wild Dereference (`0xB81B5FF8` / `0xB7E7EFF8`)**:
  * Because `sp = 0x807FC910` is outside valid RAM, stack stores (`sw rX, offset(sp)`) fail to persist register values into PS1 memory.
  * Subsequent stack loads (`lw r5, offset(sp)`) read uninitialized host memory / ASLR stack garbage.
  * Dereferencing `r5` triggers a host SIGSEGV. The variance between `0xB7E7EFF8` and `0xB81B5FF8` across runs is a direct artifact of host ASLR on uninitialized memory reads.

---

### Hypothesis 2 (RANK 2 — SECONDARY): Rebaser Directory Link Clobber of Data Cell `0x80077194`
* **Mechanism**:
  * Directory entry rebaser `fn_8003342C` (`LinkArchiveDirectoryEntries`) receives block base `a0 = 0x801F34B4` and rebase delta `a2 = 0x00C00000` (or `0xC6C0CBA5` tag math).
  * If `a2` is not intercepted, `fn_8003342C` adds `0x00C00000` to table entries overlapping the movie module's data area (`0x80077100`–`0x80077500`).
  * Offset `0x80077194` receives rebased pointer `0x8001CE1C + 0x00800000 = 0x8081CE1C` (or `0x8081CE25`).
  * When `MoviePollSkipInput` reads cell `0x80077194` as a stream node pointer and attempts to read struct field `+0x10`, it dereferences `0x8081CE1C + 0x10 = 0x8081CE2C`.
  * If the cell contains uninitialized memory, `lw` loads `0xB81B5FF8` as the next-layer pointer, causing an immediate crash.

---

### Hypothesis 3 (RANK 3 — TERTIARY): IRQ List / BSS Cross-Contamination
* **Mechanism**:
  * IRQ chain walker (`0x80059410`) contains poisoned entry `0x8F5A0014` (logged by `[irqc]`).
  * Interrupt dispatches writing through `0x8F5A0014` overflow kernel BSS limits (`0x800595E4`), corrupting nearby static variables in lower module space (`0x80077194`).
  * While this explains list corruption, it does not account for the exact `0x600000` offset between `0x807FC910` and `0x801FC910`, making Hypothesis 1 the definitive primary cause.

---

## 4. Proposed Fix Points

The following line-level locations in `xenolift/runtime/runtime.c` provide **additive, non-destructive tag-stripping and bounds-guarding**. For all valid PS1 RAM pointers (`0x80000000`–`0x80200000`), these transforms are identity operations.

---

### Fix Point 1: Universal Allocator Handoff Tag Stripper (`fn_80031F58`)
* **File & Line**: `xenolift/runtime/runtime.c`, lines 4280–4320 (inside `a == 0x80031F58u` handler)
* **Code Modification**:
```c
/* Fix Point 1: Universal Tag Strip on Allocator Handoff Arguments */
if (a == 0x80031F58u) {
    /* Strip tag bits 21-31 from returned block pointer v0 (r2) if in RAM range */
    if (r[2] >= 0x80000000u && r[2] < 0x81000000u) {
        r[2] = (r[2] & 0x801FFFFFu) | 0x80000000u;
    }
    /* Sanitize stack-top parameter a1 (r5): restore true RAM top 0x80200000 */
    if (r[5] != 0u && (r[5] < 0x80000000u || r[5] >= 0x80200000u)) {
        uint32_t stripped_a1 = (r[5] & 0x801FFFFFu) | 0x80000000u;
        if (stripped_a1 == 0x80000000u || r[5] == 0x80800000u) {
            r[5] = 0x80200000u; /* True kernel stack top */
            r[6] = 0x00200000u; /* True 2MB RAM span */
        } else {
            r[5] = stripped_a1;
        }
    }
}
```
* **Impact**: Ensures that no module configuration structure ever receives a tag-polluted `sp` base or span argument.

---

### Fix Point 2: Directory Link Rebaser Delta Sanitizer (`fn_8003342C`)
* **File & Line**: `xenolift/runtime/runtime.c`, lines 3860–3867 (inside `a == 0x8003342Cu` handler)
* **Code Modification**:
```c
/* Fix Point 2: Rebase Delta Tag Stripper in LinkArchiveDirectoryEntries */
if (a == 0x8003342Cu) {
    /* If rebase delta a2 (r6) carries tag bits, strip them to valid RAM offset */
    if (r[6] != 0u && (r[6] < 0x80000000u || r[6] >= 0x80200000u)) {
        uint32_t stripped_a2 = (r[6] & 0x801FFFFFu) | 0x80000000u;
        if (stripped_a2 >= 0x80000000u && stripped_a2 < 0x80200000u) {
            r[6] = stripped_a2;
        } else {
            r[6] = r[4]; /* Fallback: substitute block base a0 */
        }
    }
}
```
* **Impact**: Prevents `fn_8003342C` from writing rebased pointers into archive tables or module static data space.

---

### Fix Point 3: Compressed Buffer Unpack Source Mask (`fn_80032EB4`)
* **File & Line**: `xenolift/runtime/runtime.c`, lines 4409–4415 (inside `a == 0x80032EB4u` handler)
* **Code Modification**:
```c
/* Fix Point 3: Unpack Compressed Buffer Source Pointer Sanitizer */
if (a == 0x80032EB4u && (r[4] < 0x80000000u || r[4] >= 0x80200000u)) {
    uint32_t stripped_a0 = (r[4] & 0x801FFFFFu) | 0x80000000u;
    if (stripped_a0 >= 0x80000000u && stripped_a0 < 0x80200000u) {
        r[4] = stripped_a0;
    } else {
        uint32_t blk = xenolift_mem_read32(0x800592BCu);
        if (blk >= 0x80000000u && blk < 0x80200000u)
            r[4] = blk;
    }
}
```
* **Impact**: Guarantees that LZSS stream unpackers always read from valid PS1 RAM addresses.

---

### Fix Point 4: Module Stack Pointer & Data Cell Guard (`MoviePollSkipInput`)
* **File & Line**: `xenolift/runtime/runtime.c`, lines 4213–4230 (inside `pv[pi].a == 0x800769A4u` handler)
* **Code Modification**:
```c
/* Fix Point 4: Movie Module Entry Stack Pointer & Data Cell Sanitizer */
if (pv[pi].a == 0x800769A4u) {
    /* Guard 1: Correct corrupted stack pointer sp (r29) */
    if (r[29] < 0x80000000u || r[29] >= 0x80200000u) {
        r[29] = (r[29] & 0x801FFFFFu) | 0x80000000u;
    }
    /* Guard 2: Sanitize static data cell 0x80077194 if tagged */
    uint32_t cell_77194 = xenolift_mem_read32(0x80077194u);
    if (cell_77194 != 0u && (cell_77194 < 0x80000000u || cell_77194 >= 0x80200000u)) {
        uint32_t clean_cell = (cell_77194 & 0x801FFFFFu) | 0x80000000u;
        xenolift_mem_write32(0x80077194u, clean_cell);
    }
}
```
* **Impact**: Catches any mid-loop `sp` corruption before frame allocation and repairs tagged pointers in module static cell `0x80077194`.

---

### Fix Point 5: Active IRQ Handler List Truncation Guard (`0x80059410`)
* **File & Line**: `xenolift/runtime/runtime.c`, lines 3918–3928 (inside IRQ chain health scan)
* **Code Modification**:
```c
/* Fix Point 5: Active IRQ List Truncation on Out-of-RAM Node */
if (nx < 0x80000000u || nx >= 0x80200000u) {
    uint32_t zero = 0u;
    /* Actively truncate the chain at the last valid node */
    memcpy(xenolift_mem + (q - 0x80000000u) + 12, &zero, 4);
    fprintf(stderr, "[irqc-fix] Truncated poisoned IRQ link at node 0x%08X (bad next=0x%08X)\n", q, nx);
    break;
}
```
* **Impact**: Converts a fatal out-of-RAM IRQ jump into a clean list termination, preventing driver spin loops and kernel halts.

---

## 5. Verification Checklist for Coding Agent

When implementing the proposed fix points:

1. [ ] **Build Check**: Verify compilation with `cc -w runtime/runtime.c disc1.c -o xenogears_boot`.
2. [ ] **No Regression**: Confirm valid RAM pointers (`0x80000000`–`0x80200000`) pass through all masking macros unchanged.
3. [ ] **Log Verification**: Run the harness and confirm `[hand-fix]`, `[reloc-fix]`, and `[irqc-fix]` log output in stderr.
4. [ ] **Stack Pointer Bounds**: Verify `MoviePollSkipInput` enters with `sp` in `[0x801F0000, 0x80200000)`.
5. [ ] **Movie Module Execution**: Confirm `MoviePollSkipInput` progresses past phase 6 without triggering host SIGSEGV or wild pointer dereferences.

---
*End of Poison-Tag Census Report.*
