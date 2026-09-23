# FIX proposal: R1474 plateau cycling camera (camera-only)

**Author lane:** Programming · Nasir (draft for DIRECTOR)  
**Tree pin:** `xenolift-clean` @ `d81d5d7` (digest tip; pacing ruled out)  
**runtime.c SHA-256 @ draft base:** `f1c92b791ff0dc1f251e3fa57878b53ebc02f52c4de24f90657a82b396461748`  
**reapply_OR_forbidden:** YES  
**Behavioral change:** NONE (log-only)

---

## 1. Verdict restatement

Pacing is out. Across 120–900s budgets, organic seek stays in the **~108886–108907** band (pacing ruled out). Hiroshi: R1473 **0/8** is receipted on **120/180/600** only — do **not** claim 900s (pre-R1473 tree). Seek/FDF8/sched never hold still for 2 continuous seconds on those R1473 runs — there is continuous small-scale churn (`cmd` / `FE1C` / pump contexts) while LBA distance stays flat.

Stillness / armstart siblings (R1467A / R1472 / R1473) are the wrong next tool. Need the **smallest camera** that characterizes plateau-period cycling of:

- `cmd`
- `FE1C`
- pump-context `r31` (`0x80041CA0` fd-processor / `0x80041BB0` pump)

while seek remains flat in that band. Camera-only until Hiroshi grades.

---

## 2. Exact placement

**File:** `source/runtime/runtime.c`  
**Host seam:** `cd_read_impl` → `case 0x1F801800:` (composer / CD status read — same hot seam as R1467A / R1472 / R1473 / R1457).  
**Insert:** immediately **after** the R1473 block closing `}` (currently ~L3427), **before** the R1452 FE1C-clear block (~L3429).

Anchor markers:

```
}  /* end R1473 */

        { /* R1452 (c1060): THE COMPLETED-READ FE1C CLEAR. ...
```

→ splice R1474 between those two.

---

## 3. Full C snippet

```c
// === BEGIN R1474 CAMERA: plateau cmd/FE1C/r31 cycling (camera-only) ===
{ /* R1474 (Nasir/DIRECTOR): PLATEAU CYCLING CAMERA — ZERO BEHAVIORAL.
 * Digest pacing-definitively-ruled-out: 120s-900s same seek ceiling
 * ~108886-108907; R1473 0/8 on 120/180/600 (not 900s); churn continues.
 * HOLD stillness/armstart. Camera-only: while seek sits in the plateau
 * band, log cmd + FE1C + r31 on-change (debounced) and a 2s heartbeat
 * with cumulative pump-context counters (r31 0x80041CA0 fd-processor /
 * 0x80041BB0 pump per PROJECT_LOG / pump-invocation-rarity-lead).
 * No armstart, no stillness confirm, no FE1C OR, no pend/sched gate
 * change. reapply_OR_forbidden=YES. */
    static uint32_t r1474_prints = 0;
    static uint32_t r1474_lcmd = 0xFFFFFFFFu;
    static uint32_t r1474_lfe1c = 0xFFFFFFFFu;
    static uint32_t r1474_lr31 = 0xFFFFFFFFu;
    static uint32_t r1474_evals = 0;
    static uint32_t r1474_last_print_eval = 0;
    static uint32_t r1474_n_ca0 = 0;   /* r31 == 0x80041CA0 */
    static uint32_t r1474_n_bb0 = 0;   /* r31 == 0x80041BB0 */
    static uint32_t r1474_n_other = 0;
    static time_t r1474_last_hb = 0;
    if (cd_seek_lba >= 108880u && cd_seek_lba <= 108920u) {
        uint32_t pc_fe1c = xenolift_mem_read32(0x8004FE1Cu);
        uint32_t pc_r31 = r[31];
        uint32_t pc_fdf8 = xenolift_mem_read32(0x8004FDF8u);
        time_t now = xl_wall();
        int changed = (cd_last_cmd != r1474_lcmd)
            || (pc_fe1c != r1474_lfe1c)
            || (pc_r31 != r1474_lr31);
        int debounced = ((r1474_evals - r1474_last_print_eval) >= 1024u);
        int heartbeat = (r1474_last_hb == 0 || (now - r1474_last_hb) >= 2);
        r1474_evals++;
        if (pc_r31 == 0x80041CA0u) r1474_n_ca0++;
        else if (pc_r31 == 0x80041BB0u) r1474_n_bb0++;
        else r1474_n_other++;
        if (r1474_prints < 384u && ((changed && debounced) || heartbeat)) {
            const char *kind = (changed && debounced) ? "chg" : "hb";
            r1474_prints++;
            r1474_last_print_eval = r1474_evals;
            r1474_lcmd = cd_last_cmd;
            r1474_lfe1c = pc_fe1c;
            r1474_lr31 = pc_r31;
            if (heartbeat) r1474_last_hb = now;
            r861_out("[platcam] R1474 %s #%u @t=%lds seek=%u cmd=%02X FE1C=%u r31=%08X cur_fn=%08X FDF8=%u pend=%u sched=%d act=%d | ctx ca0=%u bb0=%u other=%u evals=%u\n",
                     kind, r1474_prints, (long)(now - g_boot_wall_t0),
                     (unsigned)cd_seek_lba, (unsigned)cd_last_cmd,
                     (unsigned)pc_fe1c, (unsigned)pc_r31,
                     (unsigned)xenolift_cur_fn, (unsigned)pc_fdf8,
                     (unsigned)cd_pending, (int)(cd_scheduled ? 1 : 0),
                     (int)cd_read_active,
                     r1474_n_ca0, r1474_n_bb0, r1474_n_other, r1474_evals);
        }
    }
}
// === END R1474 CAMERA ===
```

---

## 4. Log line format (Mac digest grep)

**Unique tag:** `[platcam]`

```
[platcam] R1474 chg #N @t=Ts seek=S cmd=CC FE1C=F r31=RRRRRRRR cur_fn=FFFFFFFF FDF8=X pend=P sched=Q act=A | ctx ca0=A bb0=B other=O evals=E
[platcam] R1474 hb  #N @t=Ts seek=S cmd=CC FE1C=F r31=RRRRRRRR cur_fn=FFFFFFFF FDF8=X pend=P sched=Q act=A | ctx ca0=A bb0=B other=O evals=E
```

Grep helpers:

```bash
rg '\[platcam\]' run.log
rg '\[platcam\].*r31=80041(CA0|BB0)' run.log
rg '\[platcam\] chg' run.log | awk '{print $0}'   # period / churn sequence
```

---

## 5. Gate conditions

| Gate | Value |
|---|---|
| Seek band | `108880 .. 108920` (covers observed ceiling ~108886–108907 with small margin; deliberately **not** the wider R1472 `[108900,109120]` movie-adjacent approach band) |
| On-change | `(cmd, FE1C, r31)` tuple change |
| Debounce | ≥1024 composer evals since last print (keeps 900s logs usable) |
| Heartbeat | every 2 wall-clock seconds while in band (proves seam live + dumps cumulative `ca0`/`bb0`/`other`) |
| Cap | 384 prints total |
| Side effects | **none** — no writes, no armstart, no pend/sched/FE1C mutation |

---

## 6. Explicit NON-goals

- **No** new armstart / pausestart / pausepend sibling  
- **No** stillness / time-hold / 2M-poll confirm detector  
- **No** FE1C OR / widen (`reapply_OR_forbidden=YES`)  
- **No** pend/sched gate edits  
- **No** behavioral change of any kind — camera-only until Hiroshi grades  

---

## 7. How to verify (Hiroshi, 600s+ run)

Expect on a 600s+ fuse run that stays organic in the plateau:

1. **`[platcam]` lines appear** once seek enters ~108880+ (if zero lines → composer seam cold at plateau; escalate to dispatch-site camera on `0x80041CA0` / `0x80041BB0` entry — see open questions).
2. **`chg` lines** show `cmd` and/or `FE1C` and/or `r31` flipping while **seek stays flat** in-band (confirms churn-without-progress).
3. **`ctx ca0=` / `bb0=`** counters on `hb` lines grow over time — ratio + growth rate characterize pump vs fd-processor residency during the plateau (the pump-invocation-rarity question).
4. **R1473 still 0/8** (unchanged — we did not touch it); no new `[pausestart]` / `[pausepend]` fires from this patch.
5. Log stays usable: ≤384 `[platcam]` lines even at 900s (debounce + cap).

Pass for *this* cycle = receipts that name the churn period / dominant `r31` context. Not a field-loading win.

---

## 8. Suggested next tip SHA note

- Land is **camera-only**; **`runtime.c` SHA will change** after apply (current base `f1c92b791ff0dc1f251e3fa57878b53ebc02f52c4de24f90657a82b396461748`).
- Behavioral baseline comparison for seek ceiling / R1473 fire counts should still pin **prior pins** (`d81d5d7` digest tree / R1473 behavioral SHA) unless DIRECTOR explicitly updates the baseline to the post-camera tip.
- Do **not** treat a post-R1474 tip as a new behavioral experiment pin until Hiroshi clears the camera receipts.

---

## Risks / open questions

1. **Seam cold?** R1457 already flagged that some freezes poll model cells / datasync and skip 1800. If `[platcam]=0` at 600s with seek in-band, the next camera should hook dispatch/entry of `r31` contexts (or the existing `[cd] fd-collector tick` path at `a==0x800415B4`) rather than widening this block.
2. **`r[31]` meaning at 1800:** meaningful when the *guest* is the reader mid-call; host-driven paths that touch the register without a guest frame may show stale/ unrelated `r31`. Heartbeat `cur_fn` column helps attribute.
3. **Band vs divert:** prior 900s run jumped into movie diagnostic ~239317. Camera self-gates off when seek leaves 108880–108920 — no spam in that divert region (intentional).
4. **Cap 384:** if churn is extremely dense, early-window characterization is favored; raise cap only after Hiroshi asks.
5. **HOLD:** do not draft another R1473-style stillness/armstart in the same cycle.
