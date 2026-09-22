# PRE-FLIGHT AUDIT: dirack / zrf0 Family Audit Report

> **CRITICAL BUGS FOUND — ACTION REQUIRED BEFORE SHIPPING**
> 
> 1. **BUG #1 (DEAD CODE / GUARD CONTRADICTION - R527 `[dirack3]`):**
>    - **File & Lines:** `xenolift/runtime/runtime.c` line 4488 (nested inside outer block at line 4392).
>    - **Issue:** R527 (`[dirack3]`) is placed inside the outer block `if (cd_seek_lba >= 108900u || (fld3_era && cd_pending == 0u))` (line 4392). R527's own inner guard requires `cd_seek_lba < 150u` (directory scan era). During the post-mount directory scan (`cd_seek_lba < 150`), `fld3_era` is 0 (set only when `seek >= 108995` at line 4250), so the line 4392 outer `if` evaluates to `FALSE` and **completely skips the block containing R527**. When `seek >= 108900` or `fld3_era == 1`, outer line 4392 is `TRUE` but inner line 4498 (`cd_seek_lba < 150u`) is `FALSE`. **Result: R527 CAN NEVER FIRE UNDER ANY CIRCUMSTANCES.**
> 
> 2. **BUG #2 (DIGEST INVISIBILITY / LESSON L1 & N+2 VIOLATION - `zrf0`):**
>    - **File & Lines:** `xenolift/run.sh` line 349 (`=ZRF=`) and line 451 (`=FLD=`), compared to `xenolift/runtime/runtime.c` lines 9359 & 9364.
>    - **Issue:** `runtime.c` logs `zrf0` fires with tag `[zrf0]`. `run.sh` filters logs using `grep "\[zrf\]"`. The regex `\[zrf\]` requires literal `]` immediately following `zrf`. Because `[zrf0]` has a `0` before `]`, `grep "\[zrf\]"` produces **0 matches**. **Result: `zrf0` log lines are completely dropped from the digest**, violating Lesson L1 and Lesson N+2 (probe output without digest section).
> 
> 3. **DEFECT #3 (STRUCTURAL NESTING DEFECT - R529 `[dirack4]`):**
>    - **File & Lines:** `xenolift/runtime/runtime.c` lines 4354–4388.
>    - **Issue:** The `else` block of R526 (`dirack2`) at line 4354 is missing a closing brace before R529 (`dirack4`). R529 is accidentally nested inside R526's `else` clause.

---

## Pre-Flight Check Matrix

| Check | Description | R521 (R525) | R526 (`dirack2`) | R527 (`dirack3`) | zrf0 (R511/515/528) |
|---|---|---|---|---|---|
| **(a)** | MMIO-read guest dispatch? (L2) | **PASS** (in `on_alarm`) | **PASS** (in `on_alarm`) | **PASS** (in `on_alarm`) | **PASS** (in `xenolift_trace`, not `cd_read`) |
| **(b)** | Digest section + line budget? (L1/N+2) | **PASS** (`=DIRACK=`) | **PASS** (`=DIRACK=`) | **PASS** (`=DIRACK=`) | **FAIL (BUG #2)** (`run.sh` greps `[zrf]`, not `[zrf0]`) |
| **(c)** | Sensible fire budget cap? | **PASS** (12 fires) | **PASS** (24 fires) | **PASS** (12 fires) | **PASS** (40 fires) |
| **(d)** | Era-gating blindness at handoffs? | **PASS** (`seek < 150`) | **PASS** (`seek < 150`) | **FAIL (BUG #1)** (Blocked by outer `fld3_era` gate) | **PASS** (disarms when `seek >= 150`) |
| **(e)** | Flutter-arm pattern safe? | **PASS** (2-tick arm) | **PASS** (2-tick arm) | **PASS** (2-tick arm) | **PASS** (R528 widened fe1c 0/6/7/10/11) |
| **(f)** | Cover both FE20 3+4 substates? | **N/A** (Phase 10) | **N/A** (Phase 0) | **N/A** (Phase 0) | **N/A** (Watches `fe1c0` set) |
| **(g)** | Exclude boot era (`seek >= 150`)? | **PASS** (`seek < 150`) | **PASS** (`seek < 150`) | **PASS** (`seek < 150` inner) | **PASS** (`seek < 150`) |

---

## Detailed Check Analysis per Item

### 1. `[dirack]` R521 & R525 Doorbell
- **Location:** `xenolift/runtime/runtime.c` lines 4301–4331.
- **Code Audit:**
  - **(a) Context:** Placed in `on_alarm(int sig)` (60Hz timer interrupt). Writes only to C runtime state (`cd_resp[0..2]`, `cd_resp_n=3`, `cd_resp_pos=0`, `cd_pending=1`). Zero `xenolift_dispatch()` calls. **PASS**.
  - **(b) Digest:** Tag `[dirack]` is caught by `=DIRACK=` section in `run.sh` line 453 (`grep "dirack" run.log.d | head -16`). **PASS**.
  - **(c) Fire Cap:** Capped at `da_fires < 12u`. **PASS**.
  - **(d) Era Gating:** Gated on `0 < cd_seek_lba < 150u` (directory scan era). **PASS**.
  - **(e) Flutter Arm:** Uses `da_armed` 2-tick arming, disarming on `fe1c_da != 10u`. **PASS**.
  - **(f) Substates:** Checks `fe1c == 10u` (phase 10 empty-ack poll). **PASS**.
  - **(g) Boot Exclusion:** Requires `cd_seek_lba < 150u` and `cd_seek_lba > 0u`. **PASS**.

### 2. `[dirack2]` R526
- **Location:** `xenolift/runtime/runtime.c` lines 4338–4356.
- **Code Audit:**
  - **(a) Context:** Placed in `on_alarm`. Cell-writes only (`cd_resp`, `cd_pending=1`). **PASS**.
  - **(b) Digest:** Tag `[dirack2]` caught by `grep "dirack"` in `=DIRACK=` section. **PASS**.
  - **(c) Fire Cap:** Capped at `d9_fires < 24u`. **PASS**.
  - **(d) Era Gating:** Scoped to `0 < cd_seek_lba < 150u`. **PASS**.
  - **(e) Flutter Arm:** Uses `d9_armed` 2-tick arming. **PASS**.
  - **(f) Substates:** Checks `fe1c == 0u` and `cd_last_cmd == 0x09u` (ReadS). **PASS**.
  - **(g) Boot Exclusion:** Requires `cd_seek_lba < 150u`. **PASS**.
  - *Note on Defect #3:* The `else` block on line 4354 lacks a closing brace before R529 (`dirack4`), nesting R529 inside R526's `else` branch.

### 3. `[dirack3]` R527 — **CRITICAL BUG LOCATION**
- **Location:** `xenolift/runtime/runtime.c` lines 4488–4515.
- **Code Audit:**
  - **(a) Context:** Placed in `on_alarm`. Cell-writes only (`cd_resp[0]=0x02`, `cd_resp_n=1`, `cd_pending=1`). **PASS**.
  - **(b) Digest:** Tag `[dirack3]` matches `grep "dirack"`. **PASS**.
  - **(c) Fire Cap:** Capped at `d1_fires < 12u`. **PASS**.
  - **(d) Era Gating:** **FAIL (BUG #1)**. R527 is enclosed inside outer `if (cd_seek_lba >= 108900u || (fld3_era && cd_pending == 0u))` at line 4392. During the post-mount directory scan (`seek = 1`), `fld3_era` is 0 (set only at `seek >= 108995`). Line 4392 evaluates to `FALSE`, skipping R527 entirely. Conversely, when `seek >= 108900`, line 4392 is `TRUE`, but R527's inner guard `cd_seek_lba < 150u` evaluates to `FALSE`. R527 can NEVER execute.
  - **(e) Flutter Arm:** Uses `d1_armed` 2-tick arming. **PASS**.
  - **(f) Substates:** Checks `fe1c == 0u` and `cmd == 0x01u` (GetStat). **PASS**.
  - **(g) Boot Exclusion:** Inner guard specifies `seek < 150u`. **PASS**.

### 4. zrf0 Wedge (R511 / R515 / R528) — **DIGEST BUG LOCATION**
- **Location:** `xenolift/runtime/runtime.c` lines 9333–9372.
- **Code Audit:**
  - **(a) Context:** Placed in `xenolift_trace` (line 9333). Synchronously calls `cd_force_deliver_int1("zrf0")` at line 9363 (which dispatches guest MIPS code via `xenolift_dispatch`). Not in MMIO-read (`cd_read`), but runs inside trace context. **PASS**.
  - **(b) Digest:** **FAIL (BUG #2)**. Logs with `[zrf0]`, but `run.sh` lines 349 & 451 grep for `\[zrf\]`. `grep "\[zrf\]"` requires `]` immediately after `f`. `[zrf0]` does not match, rendering all `zrf0` output invisible in the digest.
  - **(c) Fire Cap:** Capped at `zrf0_fires < 40u`. **PASS**.
  - **(d) Era Gating:** Scoped to `cd_seek_lba < 150u`. Disarms when `seek >= 150u`. **PASS**.
  - **(e) Flutter Arm:** R528 widened the qualifying substate mask to `(fe1c0 == 0u || fe1c0 == 6u || fe1c0 == 7u || fe1c0 == 10u || fe1c0 == 11u)`, preventing arm resets during 0<->6 field ring flutter. **PASS**.
  - **(f) Substates:** Watches `fe1c0` set and `fdf80 == 0u` with `cd_data_n >= 2048u`. **PASS**.
  - **(g) Boot Exclusion:** Gated on `cd_seek_lba < 150u`. **PASS**.

---

## Recommended Remediation

1. **Fix R527 Placement (Bug #1):**
   Move the `[dirack3]` R527 block out from inside `if (cd_seek_lba >= 108900u || (fld3_era && cd_pending == 0u))` (line 4392) and place it alongside R521 and R526 in the directory scan section of `on_alarm` (~line 4390).

2. **Fix `run.sh` Grep Pattern (Bug #2):**
   Update `run.sh` line 349 and line 451 from:
   ```bash
   grep "\[zrf\]"
   ```
   to:
   ```bash
   grep -E "\[zrf0?\]"
   ```
   or widen the tag in `runtime.c` to `[zrf]` / `[zrf0]`.

3. **Fix R526/R529 Block Nesting (Defect #3):**
   Add the missing closing brace `}` on line 4356 after `if (!(fe1c_d9 == 0u && cd_last_cmd == 0x09u)) d9_armed = 0;` so R529 (`dirack4`) stands as an independent block rather than inside R526's `else` clause.
