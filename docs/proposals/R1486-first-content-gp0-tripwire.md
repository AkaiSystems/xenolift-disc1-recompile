# R1486 — First-content GP0 tripwire (camera-only) — LANDED

**Lane:** Nasir / Programming · DIRECTOR GREENLIGHT  
**Tree pin:** `xenolift-clean` tip including `9e76fe6` (R1481 [r96gate] RESTORE)  
**Status:** LANDED — camera only; no behavioural change  
**Depends on:** GPU work remains deferred until a non-fill primitive appears

## Intent

Today the GPU HLE is healthy (16/16 unit tests) but the game has never
submitted a drawing primitive. R939 census: `fill=1 copy=0 rect=0 line=0 poly=0`.
`vram_writes` is always a multiple of 184320 = one GP0(02) 384×480 black
fill. `dma2_sends` ticking 1→3 is the render loop spinning, not content.

When load finally advances far enough, we want the **exact first non-fill
GP0** captured — opcode/class/words — rather than discovered later from a
census.

## Landed camera

- **Site:** `source/hle/hle_gpu.c` → `exec_cmd_buf()` (R939 class dispatch).
  This is the HLE GP0 submit path dual-fed from runtime (port `0x1F801810`
  and both DMA2 list walkers via `gpu_gp0_write`).
- **Fill vs non-fill predicate (same as R939):** fill = GP0 opcode `0x02`
  (FillVram). Non-fill = anything else that reaches `exec_cmd_buf`
  (copy `0x80`, poly `0x20–0x3F`, line `0x40–0x5F`, rect `0x60–0x7F`, other).
  NOP / ClearCache / IRQ / env (`0xE0–0xFF`) / A0 DataToVRAM never reach
  this path as drawing headers, so they cannot false-fire.
- **Fire:** static once-flag `g_r1486_fired`; first non-fill only.
- **Print:** one line tagged `[r1486]` with cmd/class/word-count/w0–w3.
- **Behaviour:** **camera only** — does not change whether the command
  executes. No R885 / Pause / FE1C / R96 / alarmguard / [xcam]/[fldfrz] touch.

## Pass / revert bars

| | Bar |
|---|---|
| **Pass** | Tag appears in `run.log.raw` on the first non-fill GP0; binary contains `[r1486]` (`strings`); fill-only runs stay silent |
| **Revert** | False fires on fill-rect; log storm; any behavioural mutation |

## HOLDs

Same as R1485: no R885 touch, no FE1C OR, no dual-land into Pause lane
(Claude owns `fn_0x80042090`), HOLD [xcam]/[fldfrz] guest twin, one FIX
at a time. R1485+ behavioural ports remain HOLD.

## Relationship to GPU work

This tripwire is the **legitimate GPU-adjacent** work now. Full GPU
emulation tuning stays deferred until this camera proves the game is
exercising non-fill content.
