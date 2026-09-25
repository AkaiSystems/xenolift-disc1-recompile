# FIX proposal: R1481 `[r96gate]` — stop R96 from re-asserting INT1 without a new sector (CD_flush exit)

**Author lane:** Programming · Nasir (grade for DIRECTOR)
**Tree pin:** `xenolift-clean` @ `58c7a68` (runtime still `bcbfce8` body; sha256 `264079e5453abd85211ac02a692dc70d0734379ac8ff5fc4120e56e9c4abc32b`)
**Digest:** `docs/digests/ROOT-CAUSE-cdflush-alarmguard-deadlock.md`
**reapply_OR_forbidden:** YES
**Verdict ask:** APPROVE **one behavioral FIX** at the R96 site (guest MMIO path) — not alarm context

## Grade of ROOT-CAUSE digest — **PASS / agree**

| Claim | Verdict |
|-------|---------|
| Field freeze = `CD_flush` (`fn_0x8004252C`) spin until `1F801803&7==0` | **PASS** — matches `[wedge]` R967 + alarmguard depth=2 |
| R96 re-arm on every ReadN response drain keeps the flag set → flush never exits | **PASS (causal)** — revises earlier “R96 real but not harm” note: harm is **flush starvation**, not data delivery |
| DRAIN==0 DMA trap still holds | **PASS** — leave that rule locked |
| Alarm-context rescues/cameras (`[xcam]`, `[fldfrz]`, …) silent by construction | **PASS** — explains R1480 null result despite binary match |
| Method: grade `run.log.raw` only; `run.log` 16k head/tail hides the freeze | **PASS / locked** |
| Fix shape = R1160-style (guest read/MMIO path), not another alarm camera | **PASS** |
| Pass bar = `[pendclr]` collapses orders of magnitude + `8004252C` gone from `[alarmguard]`/`[wedge]` | **PASS** — supersedes rate / short-window bars for this cycle |

**HOLDs unchanged:** stillness / FE1C OR / opcode-0x16 / fldbatch revive / R1477 re-land.

## Why this site (not 803 heal-only)

Legitimate INT1 arms already exist:
1. **INT3→INT1 ack-pair** (`cd_arm_int1_pending` → `0x1F801802` write-7 path ~L2402)
2. **DMA sector-complete next-sector arm** (~L6250 after `[fldsec]`)

R96 (~L5076) conflates “response FIFO fully popped” with “drive has a new sector.” During `CD_flush` / getintr drain under active ReadN that re-assert races the guest’s only exit (`803&7==0`) and produces the ~1.03B ack storm. Hardware: flag stays clear until the next sector is actually ready.

R1160 precedent: break the alarmguard circular wait **inline on the guest path that owns the polled condition** — here, stop wrongful re-assert at the response-consume site (same thread as flush), rather than forging completion from `on_alarm`.

## What (ONE behavioral change)

**Site:** `source/runtime/runtime.c` ~L5076–5103, the R96 block inside `case 0x1F801801` after full response consume:

```c
if ((cd_last_cmd == 0x06u || cd_last_cmd == 0x09u) && cd_read_active) {
    cd_pending = 1;
    r861_out("[cd] data-ready INT1 armed (ReadN INT3 consumed)\n");
    g_cd_irq_force = 1;
    /* … r96cam FIRE … */
}
```

**Replace with gated arm** (behavior + small camera):

```c
if ((cd_last_cmd == 0x06u || cd_last_cmd == 0x09u) && cd_read_active) {
    /* R1481 [r96gate]: only re-assert INT1 when a staged sector is actually
     * waiting (HW: flag stays clear until next sector). Unconditional R96
     * re-arm starved CD_flush exit (fn_0x8004252C) — ROOT-CAUSE digest. */
    int r1481_sector_ready = (cd_data_loaded && cd_data_pos < cd_data_n);
    if (r1481_sector_ready && cd_pending == 0) {
        cd_pending = 1;
        g_cd_irq_force = 1;
        r861_out("[cd] data-ready INT1 armed (ReadN INT3 consumed)\n");
        /* keep existing [r96cam] FIRE block here (unchanged caps/band) */
    } else {
        static uint32_t r1481_sup_n;
        if (r1481_sup_n < 32u
            || (r1481_sup_n & 0xFFFFu) == 0u) {
            r861_out("[r96gate] R1481 SUPPRESS #%u: seek=%u cmd=%02X act=%d "
                     "loaded=%d pos=%u/%u pend=%u cur_fn=%08X "
                     "(no new sector — CD_flush exit)\n",
                     r1481_sup_n + 1u, cd_seek_lba, (unsigned)cd_last_cmd,
                     cd_read_active ? 1 : 0, cd_data_loaded ? 1 : 0,
                     (unsigned)cd_data_pos, (unsigned)cd_data_n,
                     (unsigned)cd_pending, (unsigned)xenolift_cur_fn);
        }
        r1481_sup_n++;
    }
}
```

**Non-goals at this site:** do not touch ack-pair INT1 arm, DMA next-sector arm, FE1C, stillness, fldbatch, or alarm handler.

## Pass / fail (Mac — **`run.log.raw` only**)

Run tip after land; **≥1500s external killer** preferred (short runs may still show early burst). Grade from **`run.log.raw`**, never truncated `run.log`.

| Meter | FAIL (current) | PASS |
|-------|----------------|------|
| `[pendclr]` print count (first-32 + 1/65536 sampling) | ~15699 ≈ **1.03B** clears | **orders of magnitude down** (target: sampling lines in tens, not thousands) |
| `[alarmguard]` / `[wedge]` `cur_fn` | `8004252C` | **absent** (or fleeting, not 30s STUCK) |
| `[r96gate] SUPPRESS` | n/a | fires during former storm era (proves gate hit) |
| Field seek | stuck ~108910 | **advances** toward door ~120634 (secondary; pendclr+wedge are primary) |

**REVERT if:** pendclr still billions **or** stream dies earlier than tip `bcbfce8` baseline (boot/field regression).

## Ask

Approve **R1481 `[r96gate]`** as the single behavioral FIX this cycle. DIRECTOR lands (or authorizes Nasir to land). Mac rebuild → raw-log grade on pendclr + wedge. No second FIX until that grade.
