# R1553 — CAMERA proposal: `[mvcam]` movie state 6 → stream start → FE46 handoff (ONE camera, no behaviour)

**Lane:** Programming · Nasir (Grok executor)
**Tree pin:** `xenolift-clean` @ `1c3f79b` (DIRECTOR FIELD-ROOT reframe), runtime.c sha256 `c26a850dac3d0d2c29bb772c24677041a7aea4867bb3644b1d84522efcb472c3`
**Parent digest:** `docs/digests/FIELD-ROOT-debug-menu-jump-and-missing-file17.md`
**GO lane:** movie state 6 finishes and hands off via FE46. Camera first, then ONE behavioural land.
**Scope of this doc:** plan only. No runtime change in this commit. Land the camera only after DIRECTOR ACKs this plan.
**Numbering:** R1553 (highest on tip is R1552).

## 1. Root reframe (what we are proving)

- Since R1519, "field reached" has meant the Kernel Menu shortcut: movie (st6) → R371 MENU VIRTUAL PLAYER presses Confirm on cursor 0 → `CommitGameStateTransition(1)`. That path never sets the field file selector (`[0x800ADB64]`), so file 17 never loads. The t≈12s fault at `0x80076358` follows from that.
- Real Disc 1: GameBootstrap's tail (`0x80019888..0x80019930`) sets `FE46=1` and requests state 6. The movie module (file 18, loaded at `0x8006FAF0`) plays the opening STR, then requests state `[FE46]` (≈`0x80073BA4`).
- We reach state 0 only because the movie state ends with an error. Cell meanings, from the Noah reference `ext/noah/noah_movie.cpp` (Ghidra-named):
  `FE44`=movieType (`0xFF` → **movie debug-menu path → setGameMode(0)**), `FE45`=movieNumber, `FE46`=movieReturnMode, `FE47`=movieFadeParam.
  Two different misses therefore lead to "state 0", and the camera must tell them apart.
- The complete movie player runs on our side (MDEC reset + set_iqtab DMA0 receipted by R1547 `[mdecdma]`), then waits on a stream that never starts.

### Call chain (from `source/hle/RECOMP_MOVIE_OVERLAY.csv` / `RECOMP_MOVIE_STRLIB.csv`)

```
MovieModuleEntry 0x800737EC
  0x80073B00 selects scripted vs debug menu (FE44)
  0x80073B84 -> MovieLaunchScriptedMovie 0x800763BC -> MovieRunPlayback 0x80076488
      MovieStrLibraryInitialize 0x801D3538 (rings) ; MovieStrDecDctReset 0x801D4534 / PutEnv 0x801D45F8  <- MDEC reset + iqtab DMA0 (SEEN)
      MovieStrStartPlayback 0x801D37CC -> MovieStrStartCdStream 0x801D41AC
          -> MovieStrStartCdRead2 0x801D586C : Setmode (0x0E) + ReadS (0x1B); CdReadyCallback(0x801D5900) when mode&0x100
      per INT1: libcd pump -> CD_cbready [0x800564AC] = MovieStrCdDataCallback 0x801D5900 -> MovieStrCdInterrupt 0x801D5D54
          -> frame complete -> MovieStrCdDataReadyCallback 0x801D5A04
      loop: MovieStrUpdatePlayback 0x801D3F7C -> AcquireNextFrame 0x801D3B00 (GetNextFrame 0x801D5C70) -> DecodeNextFrame 0x801D3D54 (DMA0/DMA1)
      end: MovieStrStopPlayback 0x801D4318 ; MovieStrLibraryShutdown 0x801D43B0
  0x80073B94 ReleaseHeapBlock (ret 0x80073B9C, R304 finale heal site)
  ≈0x80073BA4 CommitGameStateTransition([FE46])      <- the handoff we want
```

### Code-read predictions at the pin (to be proven, not acted on)

1. **ReadS 0x1B never starts the drive.** `cd_cmd()` serve branch L2444 handles `0x06 || 0x09` only (0x09 is the R163-era mislabel for ReadS; it is Pause). `0x1B` does not set `cd_read_active`. The INT3→INT1 ack pair at L2579–2583 arms INT1 only for `cd_last_cmd == 0x06`. The motor-on list at L2285 omits 0x1B. The only 0x1B handling is the field-band (108995..109041) stream-live and R1314 ledger. Prediction: after the movie's ReadS the guest gets an INT3 ack and **zero INT1** ⇒ `MovieStrCdInterrupt` never runs.
2. **Setmode is log-only.** L2435–2443 prints the mode (with wrong bit labels: per psx-spx 0x20 = 2340-byte sectors, 0x40 = XA-ADPCM, 0x08 = XA filter) but stores nothing. `cd_data_load()` always serves 12 synthetic bytes (BCD MSF + mode 2 + **zeroed subheader**) + 2048 user bytes (L1767–1790). This is a second-order risk for STR assembly once INT1 flows.
3. **FE04 re-anchor yank.** `cd_data_load()` R105 (L1716–1740) snaps the served LBA to the archive cell `FE04` whenever `!cd_stream_live`. In the movie era `FE04` is the archive layer's last value (e.g. 109166), not the STR file. This is a third-order risk: sectors could come from the wrong file.

The camera decides which of these (or none) is the live miss before any fix.

## 2. The camera: R1553 `[mvcam]` (observation only)

**Zero behaviour.** No guest writes, no FE1C/FDF8/FE04/pend/INT changes, and no touch of R371/R800/R304. Guest cells are read **only via `memcpy` from `xenolift_mem`**; there is **no `xenolift_mem_read32`** anywhere in the camera, and nothing is on the `0x1F801800` status-poll path. Era-gated and capped.

### Era

`mv_era` opens at `0x8001996C` with `a0==6` (state-6 request), or at the first `0x800737EC` / `0x801D3538` entry if that request was missed. It closes at the next `0x8001996C` entry with `a0 != 6`. One era is recorded per run (the opening movie); later eras only bump a count.

### Hook sites (all real function entries outside the R1394 module window, so they fire whether the movie module is compiled or interpreted)

| # | Site | Where in runtime.c | Records |
|---|------|-------------------|---------|
| H1 | `xenolift_trace()` R1500 `switch (a)` (~L17080): add `case`s | function-entry hot path, cheap switch | `0x8001996C`: a0, r31, FE44..FE47 (memcpy 4 B @`0x4FE44`), `[0x800592C0]`. `0x80019EF8` GameHandleError: a0, r31. `0x80040FCC` CdReadyCallback: a0 (expect `0x801D5900`). Movie-lib entry counters: `801D3538 801D37CC 801D41AC 801D586C(a0,a1,a2) 801D5900 801D5D54 801D5A04 801D5C70 801D3B00 801D3D54 801D3F7C 801D4318(r31) 801D43B0 801D4534 801D45F8` |
| H2 | top of `cd_cmd()` (L1930), era-gated | per command write (not the status poll) | ring[16] of `{cmd, p0..p2, cd_seek_lba, cd_read_active, cd_pending, cd_scheduled}` (host statics only). Counters: n(0x0E) + last Setmode byte, n(0x02) + last Setloc LBA, n(0x1B), n(0x06), n(0x09). Also a whole-run n(0x1B) **outside** the movie era, to scope the eventual fix. |
| H3 | `cd_data_load()` after `cd_data_n = 2060` (L1790), era-gated | per served sector | n_served_in_era. First 8 serves print `LBA`, last Setloc LBA, `cd_data[0..11]`, first user word `cd_data[12..15]` LE (**STR video = `0x80010160`**). |
| H4 | existing R1547 `[mdecdma]` counters | unchanged | read the m0/m1 totals into the dump (hoist the two statics to file scope; no new DMA code) |

### Dumps (tag `[mvcam] R1553`)

- `[mvcam] R1553 OPEN` (once): t, a0, r31, FE44..47, stage-2 image fingerprint = non-zero word count over `0x801D3000..+135168` and the first word at `0x801D586C` / `0x801D5D54` / `0x801D5900` (memcpy). A zero fingerprint means the stream code is not resident, so any later silence is a build/image issue, not a CD issue.
- `[mvcam] R1553 STALL` (cap 3): movie-lib start seen (`801D37CC`), era still open, and **no new `801D5D54` entry and no new era serve for ≥3 s wall**. It is checked in `xenolift_trace` on a `(++tick & 0xFFFF)==0` cadence (spin-reached; `on_alarm` is not, C97 lesson). It prints all counters, the cmd ring, driver statics (`cd_last_cmd`, `cd_read_active`, `cd_pending`, `cd_scheduled`, `cd_arm_int1_pending`, `cd_motor_on`, `cd_seek_lba`, `cd_stream_live`), `CD_cbready`/`CD_cbsync` (memcpy `0x564AC`/`0x564A8`), FE04/FDF8/FE1C (memcpy) and FE44..47.
- `[mvcam] R1553 CLOSE` (once): the same summary, plus the closing commit's `a0`, `r31`, FE44..47, and the verdict letter computed in-runtime (table below), so QA can grep one line.

Cost: one switch with ~20 cases on the existing R1500 switch, one masked tick, and two era-gated counters in CD paths. All prints are capped; total < 40 lines/run.

## 3. What PASS/FAIL of the camera means (decision table → the ONE next land)

The verdict comes from the `CLOSE` line, or from the last `STALL` if the era never closes.

| Verdict | Receipt shape | Meaning | Next (ONE) behavioural candidate |
|---|---|---|---|
| **V0 MISS** | no `OPEN`, or fingerprint 0 | camera or build miss (stream code not resident) | fix the run config (see §4), no FIX |
| **V1 FE44-DEBUG** | OPEN FE44=`FF`; no `801D586C`; CLOSE a0=0 with r31 inside the movie module | movie took its **debug-menu path**: movieType never set or was wiped | trace FE44's writer between GameBootstrap and 0x800737EC (pristine-restore / heal overwrite) |
| **V2 EARLY-ABORT** | `80019EF8` or a commit from outside the movie module before `801D586C` | movie aborts before streaming | name the abort code/site, then fix that one site |
| **V3 STREAM-NEVER-STARTS (drive)** | `801D586C` seen, cmd ring shows `0E`,`02`,`1B`; **n_served_in_era after 1B == 0**; `801D5D54`==0; STALL shows `last_cmd=1B read_active=0` | **prediction 1**: our drive model ignores ReadS | **R1554**: treat 0x1B as a read in the serve branch (L2444) + the INT3→INT1 ack pair (L2580) + motor-on, per psx-spx. Scope it to cases the camera proves (movie era / CD_cbready==0x801D5900) if 0x1B appears elsewhere |
| **V4 SERVED, NO CALLBACK** | serves > 0, `801D5900`==0, CD_cbready ≠ `0x801D5900` | ready-callback slot wiped or never installed (R1137/R506-class overwrite), or a forced porter steals INT1 | restore the game's own CD_cbready install only |
| **V5 REJECTED SECTORS** | `801D5D54` > 0, `801D5A04`==0; first user word ≠ `80010160`, or served LBA ≠ Setloc LBA | framing or LBA miss (**prediction 2 or 3**: Setmode 0x20 not modeled / FE04 yank) | if LBA ≠ Setloc → scope the R105 re-anchor off in the movie era; else model the Setmode size bit. Pick one, by evidence |
| **V6 DECODE STALL** | `801D5A04` > 0, `801D3D54` > 0, DMA0 stuck at the iqtab-only count or DMA1==0 | stream fine, MDEC lane stalls | MDEC/HLE lane (separate GO) |
| **V7 HANDOFF WRONG** | `801D4318`/`801D43B0` seen, CLOSE r31 ≈`0x80073BAC` but a0 ≠ FE46-at-OPEN, or a0==0 | movie finished; FE46 clobbered between OPEN and CLOSE | find the FE46 writer |
| **PASS** | CLOSE a0==1 from r31≈`0x80073BAC`, FE46=1, `801D5A04` > 0 | the real handoff works; state 1 entered via the game's flow | grade progress from here (file 17 should load) |

Rules: one verdict → at most one behavioural land → Mac raw. No batching V3+V5 even if both show; V3 goes first because V5 cannot be seen until INT1 flows.

## 4. Run config for the camera trials (Mac raw is the grade)

- **Build A, default pinned image** (R1551: partial stage-2, 8250 nz words): n ≥ 3, 60 s. Expect the movie to leave in <1 s. The camera names **why**: V0 fingerprint, V1, or V2.
- **Build B, complete movie-player stage-2 image** (the R1549q promotion; per R1551 that build "sat in the movie state"): n ≥ 3, 60 s, made via the opt-in `STAGE2_PROMOTE=1` path from the Mac's `stage2_field.bin`, then restored to the pinned image afterwards (R1551 reproducibility kept). Expect V3/V4/V5. *The Mac owner must confirm the complete image artifact exists; the camera's OPEN fingerprint verifies which image ran.*
- **R371 / menu:** untouched, not strengthened. The camera era closes at the first commit out of state 6. Anything after a `commit(0)` is the debug path and is **excluded from progress grading**. (An opt-in R371-off env switch is possible later, but it is not part of this land: one change at a time.)
- R1521 stays FLAGGED; no FE1C clears; no R885; R1549–R1552 untouched.

## 5. Land shape when GO'd (camera only)

- `source/runtime/runtime.c` only: H1 cases + H2/H3 era-gated counters + hoisted R1547 counters + OPEN/STALL/CLOSE printer, all tagged `/* R1553 [mvcam] camera only */`.
- Grep check before push: `rg -n "R1553" source/runtime/runtime.c | rg "mem_read32|mem_write|write32\("` must return empty.
- Report: tip SHA, runtime sha256, and the two Mac run configs.

## Ask

ACK the R1553 `[mvcam]` plan. On DIRECTOR GO, land the camera only, Mac n≥3 × (A, B). Nasir grades V0–V7 → propose ONE behavioural land (predicted R1554 = ReadS 0x1B drive serve, only if V3 is receipted).
