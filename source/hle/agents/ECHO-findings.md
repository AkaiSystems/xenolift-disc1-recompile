# ECHO FINDINGS: FIELD-ERA PAD CONTRACT & DISCOVERY PROBE PLAN
**Agent:** ECHO (Input & Player Agency Specialist) | **Target:** Field Era Walking Contract & Keymap
**Status:** Research & Spec Deliverable (Zero Runtime Changes)

---

## 1. INVENTORY OF MENU-ERA INPUT MECHANISM (`runtime.c`)

- **SIO MMIO Port Accesses:** SIO joypad registers at `0x1F801040`–`0x1F801054` (`0x1F801044` DATA). The menu-era frame census (`[mpad]`) proved **0 SIO accesses per menu frame**—the menu relies entirely on kernel RAM buffer abstractions rather than direct HW polling.
- **Controller Buffers (InitPAD):** `InitPAD` (`fn_8003632C`) sets RAM pad buffers `g_pad_buf1` / `g_pad_buf2` at `0x800625FC` & `0x8006261E`. These 8-byte structures hold active-low button states at bytes +2/+3 (`0xFFFF` = all released).
- **Kernel Pad Cells:** Cells `0x800773AC` (prev) & `0x800773B4` (cur) hold 8-byte pad frame structures (active-low; bit `0x40` in byte 3 = X button).
- **Menu UI & Cursor State:**
  - Cursor position: uint16 cell `0x8005F2D8` (`0` = Field, `1` = Battle, etc.).
  - Menu input cell: `0x8006948C` (read via `LHU` in handler `fn_8001A34C`). Bit `0x0020` = Confirm (Circle/X, active-high).
- **Virtual Player Mechanism (`runtime.c`):**
  - **Cadence:** Frame-driven by `fn_80036718` (`FontVPrintf` header draw with `r5 == 0x800182C0`).
  - **Injection:** After 2 menu frames, sets `0x8006948C = 0x0020` (Confirm), `0x80028088 = 1` (Requested State = Field), and writes active-low X bit (`0xBF`) into InitPAD buffers (`0x800625FC`) and kernel cells (`0x800773AC`/`0x800773B4`).
  - **Transition Handoff:** Virtual player invokes `MountGameStateModule(1)` (`fn_800199CC`) at frame 2 to execute state transition directly. Released after 12 menu frames.

---

## 2. FIELD-ERA PAD SPECIFICATION & DISCOVERY ARCHITECTURE

- **Hardware Pad Mechanics:** PS1 pad state is polled over SIO (`0x1F801040`–`0x1F80104F`) in digital mode (`0x41`). Returns 2 active-low bytes: Byte 0 (Select, L3, R3, Start, Up, Right, Down, Left), Byte 1 (L2, R2, L1, R1, Triangle, Circle, X, Square).
- **EXE vs. Field Module Separation:** The boot EXE (`SLUS_006.64`) uses kernel pad drivers. The field engine resides in dynamic module 2 (`File 14 / 0x0E`), loaded at `0x801D9724` and decompressed to `0x801D3000`. Its input polling routine is embedded inside field module code.
- **UNKNOWN Address Principle:** The exact RAM cell address(es) polled by the field module are **UNKNOWN until field code executes**. The probe plan below is engineered to **DISCOVER** them during the first field frames.
- **Discovery Strategy:**
  1. Watch SIO MMIO reads (`0x1F801044`) during field coordinator callback `0x80077E88` (`RunFieldCoordinator`) to verify whether field code polls hardware SIO directly or reads a RAM cell.
  2. Census candidate RAM cells (`0x800625FC`, `0x800773AC`, `0x8006948C`, and newly written BSS locations in `0x801D3000`–`0x801FFFFF`) on every field frame to locate the active pad-state cell and bit polarity.

---

## 3. FIELD WALKING CONTRACT & KEYMAP SPECIFICATION

### A. Discovery Probe Plan (First Cycle After Field Render)
1. **Probe 1 (`[siofld]` SIO Census):** Intercept SIO reads/writes (`0x1F801040`–`0x1F801054`) while `g_field_era == 1`.
   - *Runtime Hook:* Inside `io_special_write`/`io_special_read`, log caller `r31` + port when active in field era. Cap: 24 lines.
   - *Digest:* `grep '\[siofld\]' xenolift.log | head -n 30`
2. **Probe 2 (`[padfld]` RAM Cell Census):** Hook phase callback `a == 0x80077E88u` (`RunFieldCoordinator`).
   - *Runtime Hook:* On entry/exit of `0x80077E88` for the first 30 field frames, log `r4`–`r7`, caller `r31`, and snapshot non-zero button values in `0x800625FC`, `0x800773B4`, `0x8006948C`, and field BSS pointers. Cap: 30 lines.
   - *Digest:* `grep '\[padfld\]' xenolift.log | head -n 35`

### B. Keymap Design (Host Keyboard -> PS1 Digital Pad Bits)
Once field pad cell is discovered, map host keys to PS1 digital pad bit positions:

| Host Key | Jos Action | PS1 Pad Button | SIO Bit (Active-Low) | Standard RAM Bit |
|---|---|---|---|---|
| `W` / `Up` | Walk Up | D-Pad UP | Byte 0, Bit 4 (`0x0010`) | `0x0010` |
| `S` / `Down` | Walk Down | D-Pad DOWN | Byte 0, Bit 6 (`0x0040`) | `0x0040` |
| `A` / `Left` | Walk Left | D-Pad LEFT | Byte 0, Bit 7 (`0x0080`) | `0x0080` |
| `D` / `Right` | Walk Right | D-Pad RIGHT | Byte 0, Bit 5 (`0x0020`) | `0x0020` |
| `Space` / `Enter` / `Z` | Talk / Inspect | Confirm (Cross/Circle) | Byte 1, Bit 6 (`0x4000`) | `0x0020` / `0x0040` |
| `Esc` / `X` | Cancel / Menu | Cancel (Triangle/Square) | Byte 1, Bit 4 (`0x1000`) | `0x0010` / `0x0080` |
| `Shift` / `C` | Run | Run (R1 / L1) | Byte 1, Bit 3 (`0x0800`) | `0x0800` |

### C. Walking Injection Mechanism
1. Maintain host state word `uint16_t g_host_pad_state` (0 = released, 1 = pressed per key).
2. Inside `0x80077E88` (`RunFieldCoordinator`) entry hook: translate `g_host_pad_state` to target polarity and write directly to the discovered field pad cell(s) each frame.
