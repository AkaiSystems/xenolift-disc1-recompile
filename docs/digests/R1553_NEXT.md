# R1553 NEXT — `[mvcam]` movie state 6 → ReadS stream → FE46 handoff camera landed (camera only, Mac grade)

**Plan:** `docs/proposals/R1553-movie-fe46-stream-camera.md` @ `c70bee2` (DIRECTOR GO: camera only).
**Lane:** Programming · Nasir (Grok executor). **One land. Zero behaviour. No R1554 until Mac grades this camera.**
**Parent digest:** `docs/digests/FIELD-ROOT-debug-menu-jump-and-missing-file17.md` (`1c3f79b`).

## What landed (`source/runtime/runtime.c` only)

| Hook | Site | Records |
|---|---|---|
| H1 | `r1553_trace(a)` called from `xenolift_trace()` right before the R1500 `switch (a)` (own switch; the R1500 switch already owns `0x8001996C`/`0x800737EC`, so duplicate `case` labels were not possible) | `0x8001996C` era open (a0==6) / close (a0!=6) with a0, r31, FE44..47; `0x800737EC` / `0x801D3538` fallback open; `0x80019EF8` GameHandleError a0/r31 (+ count before `801D586C`); `0x80040FCC` CdReadyCallback a0; movie-lib entry counters `3538 37CC 41AC 586C(a0..a2) 5900 5D54 5A04 5C70 3B00 3D54 3F7C 4318(r31) 43B0 4534 45F8` (era only) |
| H2 | first line of `cd_cmd()` (command-register write, **not** the `0x1F801800` status poll) | era ring[16] `{cmd, p0..p2, n_params, seek, read_active, pending, scheduled}` (host statics); counters n0E + last mode byte, n02 + last Setloc LBA, n1B, n06, n09; whole-run `n1B_outside` |
| H3 | `cd_data_load()` right after `cd_data_n = 2060` | era serves, serves after the first era ReadS (`post1B`), first 8 serves printed: lba, last Setloc, 12-byte header, first user word (`80010160` = STR video) |
| H4 | R1547 `[mdecdma]` DMA0/DMA1 counters hoisted to file scope (`g_r1547_m0/m1`), same counting and prints | DMA0/DMA1 deltas over the era |

Guest cells (FE44..47, FE04, FDF8, FE1C, `CD_cbready 0x800564AC`, `CD_cbsync 0x800564A8`, `0x800592C0`, stage-2 fingerprint) are read **only by `memcpy` from `xenolift_mem`**. No `xenolift_mem_read32`, no guest writes, no FE1C/FDF8/FE04/pend/act/INT change, no R371/R800/R304 touch, nothing on `case 0x1F801800`. Grep gate: `rg -n "R1553" source/runtime/runtime.c | rg "mem_read32|mem_write|write32\("` → empty.

### Receipt lines (tag `[mvcam] R1553`, all capped, < 40 lines/run)

- `OPEN` (once): t, via (`commit(6)` / `MovieEntry737EC` / `StrLibInit3538`), a0, r31, FE44..47 (type num ret fade), mounted `592C0`, stage-2 fingerprint `nz=N/33792` + first words at `586C/5D54/5900`, DMA totals, `n1B_outside`.
- `FP @StrLibInit` (once): the stage-2 fingerprint taken again at the first era `801D3538` (the movie module can land after the commit).
- `SERVE #k` (≤ 8), `ERR #k` (≤ 4).
- `STALL` (≤ 3): StartPlayback (`37CC`) seen, era open, no new `5D54` entry and no new era serve for ≥ 3 s. `STALL(pre-StartPlayback)` (once): era open ≥ 5 s and `37CC` never entered. Each one is 3 lines: counters+verdict / CD driver statics + guest cells / cmd ring.
- `BEAT #k` (≤ 6): every 10 s while the era is open, one line with the provisional verdict, because a 60 s run may not reach `CLOSE` if the movie really plays.
- `CLOSE` (once): a0, r31 (`movie handoff` ≈ `0x80073BAC` / `movie module` / `outside movie`), FE44..47 at open vs close, then the same 3-line dump with the **final verdict**.

Checks are spin-reached (`(++tick & 0xFFFF)==0` inside `xenolift_trace`), not `on_alarm` (C97).

## Mac protocol (Mac raw is the grade; do not invent results)

Grep: `grep "\[mvcam\] R1553" run.log.raw` (one run = one block). Keep the `[mdecdma] R1547` lines.

**Build A: pinned default image** (no `STAGE2_PROMOTE`). n ≥ 3, `RUN_BUDGET_S=60`.
- Expect: the movie leaves state 6 in < 1 s. The camera names why: V0 (stream code not resident), V1, or V2.
- Note: stage-2 functions only XTRACE if they were emitted from the image. With the partial image the `801D…` counters can read 0 while other code runs there. Read the OPEN / FP fingerprint before trusting a 0 counter.

**Build B: complete movie-player stage-2** (the R1549q promotion that "sat in the movie state", per R1551). n ≥ 3, `RUN_BUDGET_S=60`.
1. `cp source/stage2_region.bin /tmp/stage2_region.pinned.bin` (back up the pinned image).
2. Make sure `source/stage2_field.bin` is the complete movie-player capture (≈ 23185 nz words per R1551; the partial image is ≈ 8–11k). **The Mac owner must confirm that this artifact exists.**
3. Run once with `STAGE2_PROMOTE=1 ./run.sh` so it promotes `stage2_field.bin` → `stage2_region.bin` (the R789 drift and R1324 vtable gates must pass; check for the `stage2: … promoted` line). Then do the n ≥ 3 × 60 s trials on the promoted build.
4. **Restore:** `cp /tmp/stage2_region.pinned.bin source/stage2_region.bin` and rebuild (R1551 reproducibility: a test run must never silently change the next build).
- The OPEN/FP `nz=` value proves which image ran. Expect V3 / V4 / V5.

Optional (not required by the GO): one Build B run at `RUN_BUDGET_S=180`, so a really playing movie can reach `CLOSE` (PASS/V7 can only be graded at CLOSE).

**R371 / menu:** untouched, not strengthened. The era closes at the first commit out of state 6. Anything after a `commit(0)` (Kernel Menu → R371 auto-Confirm → "field") is the debug path and is **excluded from progress grading**. Field state 1 reached via R371 does NOT count.

## Verdicts (computed in runtime; final one on `CLOSE`, else the last `STALL` / `BEAT`)

| Verdict | Receipt shape | Meaning | Next ONE candidate (separate GO) |
|---|---|---|---|
| **V0** | no OPEN, or OPEN fp `nz=0` and `3538` never entered | camera/build miss: stream code not resident | fix the run config (Build B), no FIX |
| **V1** | FE44=`FF`, `586C`=0, CLOSE a0=0 with r31 in the movie module | movie took its debug-menu path (movieType unset/wiped) | trace FE44's writer between GameBootstrap and `0x800737EC` |
| **V2** | `586C`=0 and (GameHandleError pre-586C, or a commit out of state 6) | movie aborts before streaming | name the abort code/site (ERR a0/r31), fix that one site |
| **V3** | `586C`>0, ring has `0E`,`02`,`1B`, `post1B`=0, `5D54`=0, STALL `last_cmd=1B read_active=0` | **prediction 1**: our drive model ignores ReadS (0x1B) | **R1554 ReadS-as-read**: 0x1B in the serve branch + INT3→INT1 ack pair + motor-on, scoped to what the camera proves (`n1B_outside` tells whether 0x1B appears outside the movie era) |
| **V4** | `post1B`>0, `5900`=0, `CD_cbready`≠`801D5900` | ready-callback slot wiped / never installed, or INT1 stolen | restore the game's own CD_cbready install only |
| **V5** | `5D54`>0, `5A04`=0; SERVE user0≠`80010160` or lba≠setloc | framing or LBA miss (Setmode 0x20 not modeled / R105 FE04 yank) | lba≠setloc → scope R105 re-anchor off in the movie era; else model the Setmode size bit. Pick one, by evidence |
| **V6** | `5A04`>0, `3D54`>0, DMA1 +0 or DMA0 ≤ +2 (iqtab only) | stream fine, MDEC lane stalls | MDEC/HLE lane (separate GO) |
| **V7** | `4318`/`43B0` seen, CLOSE r31≈`80073BAC`, a0≠FE46-at-OPEN or a0=0 | movie finished; FE46 clobbered | find the FE46 writer |
| **PASS** | CLOSE a0=1 from r31≈`80073BAC`, FE46=1 at OPEN, `5A04`>0 | the real handoff works; state 1 entered through the game's own flow | grade progress from here (file 17 should load) |
| `PLAYING` / `UNCL` | provisional only (era open with frames assembling / no row matched) | read the counters by hand | — |

Rules: one verdict → at most one behavioural land → Mac raw. No batching of V3+V5, even if both show; V3 goes first because V5 cannot be seen until INT1 flows.

## REVERT (camera)

- Any behaviour delta vs `1c3f79b`/`c70bee2` at the same config (the camera must be inert: same trajectory, same timing class).
- Print storm (> 40 `[mvcam]` lines/run) or logcap drowning.
- Crash attributable to the camera.

## HOLDs

No R1554 until Mac grades this camera. R1521 stays FLAGGED. Do not clear FE1C. R371 untouched. No R885. One FIX at a time.
