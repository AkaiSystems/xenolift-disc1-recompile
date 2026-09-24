# CAMERA proposal: R1479 `[r96cam]` INT1 re-arm ↔ FIFO drain ↔ 578A6 clear (ONE next step)

**Author lane:** Programming · Nasir (grade for DIRECTOR)
**Tree pin:** `xenolift-clean` @ `fd15d64` (runtime sha256 `6ad5d8a72e8c54f7dcc87d68fbef473c44f42b13e4ec65d137b1a8ba664e28e5`)
**Digest:** `docs/digests/RETRACTION-the-rate-was-a-window-artifact.md`
**reapply_OR_forbidden:** YES
**Verdict ask:** APPROVE camera-only — no behavior change this cycle

## Why (proven vs hypothesized)

**Proven (3443s run + freeze dossier):**
- Multi-minute hard stops dominate wall time (967s + 1185s = 97.3% of ~2212s observation).
- During stops: guest hot-spins (`r32` → 604M+), `1F801803` sticky INT1 (=1), FIFO staged `loaded=1 pos=0/2060`, `FE1C=0`.
- Guest takes the interrupt path (`fn_800415B4_getintr` sees data-ready) but does **not** advance `cd_data_pos`.
- Stops end via R1283/R473 defib rescue, not guest drain.

**Hypothesized (UNTESTED — this camera):**
- R96 (`0x1F801801` full response drain, `cd_resp_pos == cd_resp_n`, cmd 06/09 + `cd_read_active`) re-arms INT1 (`cd_pending=1`, `g_cd_irq_force=1`) every response consume.
- Same path zeroes `0x800578A6`, clearing the R722D/R1296B announce flag those sites just set.
- Together that could form an INT1 re-arm / announce-clear loop that keeps the guest in getintr without entering the data-FIFO drain (`0x1F801802` bank0 / DMA).

Do **not** write a fix for R96 until this camera correlates fire ↔ consume ↔ 578A6.

## What (camera only)

**Placement A — R96 fire site** (`source/runtime/runtime.c` ~L5030, inside
`if ((cd_last_cmd == 0x06u || cd_last_cmd == 0x09u) && cd_read_active)` after
`cd_pending = 1` / before or after the existing `[cd] data-ready INT1 armed` line):

```c
/* R1479 camera: correlate R96 re-arm with FIFO/announce posture. Cap 64. */
{
    static uint32_t r1479_n;
    uint16_t f578 = 0;
    memcpy(&f578, xenolift_mem + (0x800578A6u & 0x1FFFFFFFu), 2);
    if (r1479_n < 64u
        && cd_seek_lba >= 108700u && cd_seek_lba < 300000u) {
        r1479_n++;
        r861_out("[r96cam] R1479 FIRE #%u: seek=%u cmd=%02X act=%d pend=%u "
                 "data=%u/%u loaded=%d FDF8=%u FE1C=%u A22C=%u flag578A6=%u "
                 "(pre-clear path)\n",
                 r1479_n, cd_seek_lba, (unsigned)cd_last_cmd,
                 cd_read_active ? 1 : 0, (unsigned)cd_pending,
                 (unsigned)cd_data_pos, (unsigned)cd_data_n,
                 cd_data_loaded ? 1 : 0,
                 xenolift_mem_read32(0x8004FDF8u),
                 xenolift_mem_read32(0x8004FE1Cu),
                 xenolift_mem_read32(0x8006A22Cu),
                 (unsigned)f578);
    }
}
```

**Placement B — 578A6 clear site** (same block, ~L4905–4907, the
`memcpy(...578A6..., &zero, 2)` + `[cd] response consumed` line): same band/
cap, tag `[r96cam] CLEAR`, print `flag578A6 before→0` + `data_pos/n` + seek.

**Placement C — FIFO drain progress** (`case 0x1F801802` bank0 when
`cd_data_pos` advances, or first byte of a staged sector): tag `[r96cam] DRAIN`,
cap 64 in field band, print `pos before→after` / `n` / seek / FDF8.

**Optional D — freeze hold sample** (on_alarm or existing freeze-dossier seam):
once per 30s while `loaded && pos==0 && FDF8>0` in field band, tag
`[r96cam] STUCK`, print last FIRE/CLEAR/DRAIN counters (static tallies).

Log tags: `[r96cam] FIRE` · `[r96cam] CLEAR` · `[r96cam] DRAIN` · `[r96cam] STUCK`

## Gates (camera print only — no behavior)

- Field/file band: `seek ∈ [108700, 300000)` (or existing `[108700,109400]∪[120000,121000]` if DIRECTOR wants narrower)
- Cap 64 per tag (STUCK: 1/30s, cap 8)
- Zero writes beyond existing R96 path; camera must not touch pend/force/578A6/FDF8/FE1C

## Decision rule after one ≥1500s run (external killer)

| Receipt shape | Decision |
|---------------|----------|
| FIRE floods during multi-minute stop; DRAIN==0; CLEAR zeroes 578A6 while pos stays 0 | **R96 loop is real** → next cycle propose a *minimal* R96 gate change (camera-proven term only). Not this cycle. |
| FIRE rare / absent during stop; DRAIN still 0 | R96 is **not** the stop mechanism → do not touch R96; open a different hypothesis next. |
| DRAIN advances but FDF8/seek still freeze | Drain happens; failure is elsewhere (announce / waiter / DMA dest) — do not blame R96 re-arm. |

## Pass / fail (run bar — same as retraction)

Over a run **≥1500s** (external `sleep N; pkill -9`, do not trust in-tree fuse):

- **PASS (for the *eventual* fix, not this camera):** `[mscycle]` gap distribution has **no gaps >100s** (the 967s/1185s class disappears).
- **This camera's success:** FIRE/CLEAR/DRAIN/STUCK receipts name whether R96↔578A6 correlates with undrained FIFO. Camera cannot claim the gap bar alone.

Field past ~120634 remains unmet; do not use ~1.00 LBA/s as a bar.

## NON-goals (HARD)

- No FE1C OR / widen (`reapply_OR_forbidden=YES`)
- No new stillness / armstart
- No opcode-0x16
- Do **not** revive fldbatch / R1476 doorbell this cycle
- No R96 behavior change until camera decision rule fires
- No keep/kill of R1477 until R1478 `[hbcam]` outcome is in hand (orthogonal; see grade)

## R1478 keep/kill rule (parallel observation, not this step)

If `[hbcam] R1478` shows `calls==0` OR (`past_hb>0` but R1477term never true while era holds) OR R1477 still 0 fires with terms all true → **remove R1477** (`#if 0` or delete). If `[fldaccel]` fires and `[mscycle]` long gaps remain → R1477 is on the wrong rail → remove. Only keep if fires **and** >100s gaps shrink (unlikely given prior 0-fire binary verify).

## Landed sites (camera only — this commit)

Followed this proposal on tip `fd15d64`. Instrumentation only; R1476 doorbell stays `#if 0`; live `[fldbatch]` K=8 left untouched (HOLD = no revive/expand); R1477 left in place (kill waits on R1478 Mac).

| Tag | Site | Approx lines |
|-----|------|--------------|
| tallies | file-scope near `cd_data_pos` | L1668–1670 |
| CLEAR | response-consume `0x800578A6` zero (before memcpy) | L4909–4931 |
| FIRE | R96 INT1 re-arm after `g_cd_irq_force=1` | L5064–5083 |
| DRAIN | `0x1F801802` bank0 first-byte / sector-complete edges | L5111–5130 |
| STUCK | `on_alarm` depth==0, 30s, staged-empty | L12588–12612 |

CLEAR soft-gate (cap-preserving): field band **and** (`flag578A6!=0` **or** cmd 06/09 with `cd_read_active`) so GetStat noise does not exhaust the 64-cap before a multi-minute stop.

