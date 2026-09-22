# Diagnostic lead: pump/fd-processor invocation is rare, not the gate values

No FIX proposed here — camera-only finding, per standing instruction (Nasir grades, one FIX at a time).

## Observation

At the field-loading plateau (~108900-109042), `cmd`/`FE1C` **do** pass through the
exact tuple both `R1467A` and `R1472` care about (`cmd=09`, `FE1C=6`) periodically -
this isn't a case of the guest never reaching the right values. The blocker is that
the state changes again within a handful of log lines, resetting both gates'
stability counters before they reach threshold (R1467A needs 2,000,000 consecutive
matching polls; R1472 needs 65,536 qualifying evals).

Checked why: `[pendclr]` receipts show individual INT1 events sitting armed for
**up to 140 seconds** before a single pump clears them (`1 pumps since set`). The
`r31` context distribution over one full 120s run:

```
120  r31=80041BB0   (the "pump" context per PROJECT_LOG - fn_80041B3C's caller)
108  r31=80041CA0   (the fd-processor context)
 91  r31=80041B70
 59  r31=8002B168
```

Only **25 total** `[cd] fd-collector tick` receipts fired in the whole 120s run
(literal `a==0x800415B4` entries) - i.e. the actual CD-interrupt collector function
is being invoked roughly once every 4-5 seconds on average, and with real variance
(some intervals stretch past 100s). Given per-sector completion depends on this
collector running, this pacing alone caps organic progress to roughly what's been
observed regardless of gate tuning.

## A specific thread worth following up

`docs/history/PROJECT_LOG.md` (R150, an early revision) describes a fix for exactly
this class of park: *"the fd leaf-spin (r31=0x80041CA0, polling ISTAT r3=0x1F801070
+ CD reg r4=0x1F801803)... R150 FIXES: ISTAT leaf-spin rescue - after 16 polls with
cd_pending, assert I_STAT bit 3."*

That exact rescue (searched for its comment text, `0x1F801070`, "leaf-spin") is
**not present in the current tree** in that form. There's general I_STAT handling
(R78, DMA-channel IRQ assertion) but nothing matching R150's specific 16-poll
cd_pending trigger. Two possibilities, not distinguished yet:

1. It was superseded/refactored into one of the many later CD-delivery mechanisms
   (R1298/R1407-family) and is functionally still present under a different name.
2. It was genuinely lost across ~1,300 later revisions and the leaf-spin class it
   addressed has partially regressed.

## Suggested next step (for Nasir's grading, not landed by me)

Instrument `r31==0x80041CA0` and `r31==0x80041BB0` entry/exit directly (not via the
existing tick-eval cameras, which only fire under specific gate conditions) to get
a true measurement of how much wall-clock time is spent in each context during the
plateau, and whether the collector is being *starved of calls* (guest not reaching
the poll site) or *called but declining* (reaching it, but some inner gate refuses).
That distinction determines whether the right fix is a pacing/frequency issue or
another narrow posture gate like R1467A/R1472.
