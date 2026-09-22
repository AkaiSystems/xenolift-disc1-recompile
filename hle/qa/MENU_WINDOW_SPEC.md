---
title: "xenolift Menu Capture Window Specification"
summary: "Technical specification for upper RAM Menu overlay capture window extension (0x801C5000-0x801E7FFF), decoding FAT files 17/18, gdesc state-5 descriptor, load mechanics, memory map overlap analysis, and emitter capture integration."
---

# xenolift Menu Capture Window Specification

**Document Version:** 1.0 (2026-09-12)  
**Target Architecture:** MIPS R3000A / PS1 Recompiler (`xenolift`, SLUS-006.64 USA Disc 1)  
**Deliverable Path:** `/app/conversations/6aa26c825d5b4135ae6b48b5/xenolift/hle/qa/MENU_WINDOW_SPEC.md`

---

## 1. FAT Decodes for Overlay Files 17 and 18

### FAT Structure & Lookup Parameters
- **FAT RAM Base Address:** `0x80010004` (stored in kernel EXE image)
- **Binary Offset in `SLUS_006.64`:** `0x800 + (0x80010004 - 0x80010000) = 0x804`
- **Entry Record Format:** 7 bytes per entry — `[3-byte LBA (Little-Endian)] [4-byte Signed Size (Little-Endian)]`
- **Directory 0x01 Gate Offset Index:** `23` (`0x17`)
- **Lookup Index Formula:** `FAT[(23 + file_id - 1) * 7]`

### Decoded Entries

| Parameter | File 17 (Menu / Module 5) | File 18 (Movie / Module 6) |
| :--- | :--- | :--- |
| **Directory / Logical File ID** | Directory `0x01`, File `17` (`0x11`) | Directory `0x01`, File `18` (`0x12`) |
| **FAT Table Entry Index** | Index `39` (Entry `40`) | Index `40` (Entry `41`) |
| **FAT Table Byte Offset** | `0x804 + (39 * 7) = 0x915` | `0x804 + (40 * 7) = 0x91C` |
| **FAT Raw Bytes (Hex)** | `43 aa 01 20 15 01 00` | `66 aa 01 18 38 00 00` |
| **Disc LBA** | **`109,123`** (`0x01AA43`) | **`109,158`** (`0x01AA66`) |
| **Stored Compressed Size** | **`70,944` bytes** (`0x00011520`) | **`14,360` bytes** (`0x00003818`) |
| **CD Sectors (2048 B/sec)** | `35` sectors (`109123`–`109157`) | `8` sectors (`109158`–`109165`) |

---

## 2. Decoded Game-State Descriptor & Unpack Mechanics

### Game-State Descriptor Table (`gdesc`)
- **Table Base Address:** `0x8001808C` (in kernel RAM)
- **Entry Size:** 16 bytes per descriptor — `[cb: uint32] [ptr: uint32] [dest: uint32] [flag: uint32]`

### State 5 (Menu) Descriptor Decoding (`0x8001808C + 5 * 16 = 0x800180DC`)
- **`cb` (Phase Callback Target):** **`0x8001C634`** (`RunResidentMenu`)
- **`ptr` (State Control Descriptor):** **`0x800592B8`**
- **`dest` (Default Buffer Cell Reference):** **`0x8006FAEC`**
- **`flag` (Dispatch Flow Flag):** **`0x00000000`** (resident state routing)

### Payload Unpack Destination & Loader Trace
- **Actual Unpack Buffer Address:** **`0x801C5000`** (Upper RAM)
- **Kernel Code Location:** Function `DispatchMenuMode` (`0x8001C1A8`) at address `0x8001C4B8`:
  - `0x8001C4B8`: `lui a1, 0x801C`
  - `0x8001C4BC`: `ori a1, a1, 0x5000` -> `a1 = 0x801C5000`
  - `0x8001C4D4`: `jal 0x800295D8` (Synchronous archive read from LBA `109123` into `0x801C5000`)
  - `0x8001C4DC`: `jal 0x80028A60` (Archive CD wait & LZSS decompression stepper)
- **Secondary Menu Resource Load:**
  - `0x8001C438`: `ori a0, zero, 0x6B9`
  - `0x8001C43C`: `lui a1, 0x801D; ori a1, a1, 0xC000` -> Archive entry `0x6B9` loaded into **`0x801DC000`**.

---

## 3. Menu Memory Map & Overlap Analysis

### Full Memory Region Layout

| Region Description | Start Address | End Address | Size (Bytes) | RAM Offset (`0x80000000`) |
| :--- | :---: | :---: | :---: | :---: |
| **Resident Kernel EXE** | `0x80010000` | `0x8005A000` | `303,104` | `0x010000` |
| **Boot Heap Arena** | `0x8006FAF8` | Freelist limit | Dynamic | `0x06FAF8` |
| **Primary Overlay Capture Window** | `0x8006F000` | `0x8008FFFF` | `138,240` (135 KB) | `0x06F000` |
| **Menu Primary Code Payload (File 17)** | **`0x801C5000`** | **`0x801D6520`** | `70,944` | `0x1C5000` |
| **Menu Secondary Data Buffer (Entry 0x6B9)** | **`0x801DC000`** | **`0x801E8000`** | `49,152` | `0x1DC000` |
| **Full Upper Menu Allocation Span** | **`0x801C5000`** | **`0x801E8000`** | **`143,360` (140 KB)** | `0x1C5000` |

### Overlap Analysis Results
- **Distance Between Primary Overlay End (`0x8008FFFF`) and Menu Start (`0x801C5000`):**
  `0x801C5000 - 0x8008FFFF - 1 = 0x136000` bytes = **1,270,272 bytes (1.24 MB)**.
- **Overlap with Primary Overlay Region (`0x8006F000`–`0x8008FFFF`):** **NONE (0 bytes)**
- **Overlap with Resident Main EXE (`0x80010000`–`0x8005A000`):** **NONE (0 bytes)**
- **Overlap with Boot Heap Arena (`0x8006FAF8`):** **NONE (0 bytes)**
- **Isolation Assessment:** The Menu payload operates in complete isolation in high PS1 RAM (at RAM byte offset 1.77 MB). It has zero collision risk with boot heap or primary overlay memory.

---

## 4. Capture Window Extension Specification

### Window 2 Emitter Specification
- **Window Name:** `MENU_UPPER_OVERLAY_WINDOW`
- **RAM Start Address:** **`0x801C5000`**
- **Alignment:** 16-byte aligned (`0x801C5000` is 0x10 and 0x1000 aligned)
- **Capture Size:** **`0x23000` bytes** (143,360 bytes / 140 KB)
- **RAM End Address:** **`0x801E7FFF`**
- **Output Binary File:** `menu_overlay_region.bin`
- **PS1 Memory Offset:** `0x1C5000` (`0x801C5000 - 0x80000000`)

### Trigger Event & Hook Point
- **Trigger Callback:** **`0x8001C634`** (`RunResidentMenu` / State 5 phase callback).
- **Trigger Condition:** Fired when state transition dispatches to game state 5 (`st == 5`) or upon entry to `0x8001C634` after LBA `109123` read completion.
- **Harness Emitter Implementation Pattern (`runtime.c`):**
  ```c
  /* Menu upper overlay region capture hook */
  if (pc == 0x8001C634u || st == 5u) {
      FILE *f = fopen("menu_overlay_region.bin", "wb");
      if (f) {
          fwrite(xenolift_mem + (0x801C5000u - 0x80000000u), 1, 0x23000u, f);
          fclose(f);
          fprintf(stderr, "[ovl] menu overlay region 0x801C5000-0x801E7FFF (140KB, Menu load @ 0x801C5000) -> menu_overlay_region.bin\n");
      }
  }
  ```

### Static Memory Map Placement in Emitted `disc1.c`
- **Static Array Declaration:**
  ```c
  static const uint8_t menu_overlay_region_init[0x23000] = { /* captured bytes */ };
  ```
- **Static Map Pre-load Placement:**
  ```c
  memcpy(xenolift_mem + (0x801C5000u - 0x80000000u), menu_overlay_region_init, 0x23000u);
  ```
- **Recompiled Function Table Mapping:** Address range `0x801C5000`–`0x801E7FFF` mapped to static jump targets in `disc1.c`.
