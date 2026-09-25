# ROOT CAUSE: CD_flush spins on an IRQ flag the runtime keeps re-asserting, which deadlocks the entire alarm-context rescue family

**This supersedes the throughput framing.** The field-band freeze is not a pacing
problem, not a stall the rescue arms can reach, and not a CD data-delivery
problem. It is a two-part deadlock, and both parts are receipted below.

First, the method note that made this findable: **`run.sh` preserves the full
uncapped log as `run.log.raw`** (`mv run.log run.log.raw`, run.sh ~line 1578).
Every "fired zero times" verdict in this project should be re-checked against
that file, not against the 32,000-line `run.log`. In the run analyzed here the
kept head of `run.log` ends at **t=7s** and the tail resumes at **t=463s** - the
discarded middle is exactly the freeze. `run.log.raw` is 287,966 lines.

## Part 1 - the guest loop that never exits

The wedge is in `fn_0x8004252C`, which the emitter names **`CD_flush`**. Its body
(disc1.c) is the PS1 kernel's interrupt-drain routine:

```
set  *(u8*)[0x80056770] = 1          ; index register -> bank 1
read *(u8*)[0x8005677C] & 7          ; 1F801803, the IRQ flag
if (flag == 0) goto exit             ; THE ONLY EXIT
write 7 -> 1F801803                  ; acknowledge
write 7 -> 1F801802
goto re-read                         ; loop
```

It exits only when the IRQ flag reads **zero**. The runtime never lets it.

The ack path (`case 0x1F801803`, index 1, `v & 7 == 7`) does clear state -
`cd_pending = 0`, `cd_resp_n = cd_resp_pos = 0` - but the same ack also sets
`cd_arm_int1_pending = 1` on a ReadN INT3, and R96 in the response-FIFO read path
re-arms unconditionally while a read is active:

```c
if ((cd_last_cmd == 0x06u || cd_last_cmd == 0x09u) && cd_read_active) {
    cd_pending = 1;
    r861_out("[cd] data-ready INT1 armed (ReadN INT3 consumed)\n");
    g_cd_irq_force = 1;
}
```

So the flag is re-asserted as fast as the guest clears it. Quantified from
`run.log.raw`: `[pendclr]` printed **15,699** times under a cap that prints the
first 32 and then one line per 65,536 clears - **roughly 1.03 billion
acknowledgements in a single run**. `[cd]` lines are 255,398 of the 287,966-line
log (89%), and they are this loop, printed.

## Part 2 - why no rescue can intervene

`CD_flush` spins at `g_guest_depth = 2`. R885's alarmguard refuses to do anything
heavy while the anchor is mid-guest-step:

```
[alarmguard] R885 on_alarm deferred - anchor mid-guest-step (depth=2 cur_fn=8004252C) - drain runs at next dispatch boundary
```

That boundary never arrives, because the loop above never ends. **The tree already
says this**, in R967 (c76), and it has been true since then:

> *"the alarmguard deferral is correct, but 'the next dispatch boundary' NEVER
> CAME because the guest polls a condition that never flips."*

R1160 (c345) documents the identical deadlock for the SPU path and names the
shape of the fix: deliver the completion **inline from the guest's own read
context**, at the exact cell the driver polls, rather than from alarm/heartbeat
context.

### The consequence, measured
Everything that lives in `on_alarm_ctx` is dead for the whole freeze. Counts from
`run.log.raw` for tags whose only print site is inside that handler:

```
[wd]        0      [park]      0      [halt]     0
[fldfrz]    0      [fld2sig]   0      [fldbell]  0
[xcam]      0      [r96cam] STUCK 0   [trail]    0
[alarmguard] 5     <- its own print cap is 6; it defers silently thereafter
```

`[alarmguard]`'s 5 lines are **not** 5 deferrals - `r885_skips < 6` caps the
print. It defers for the entire freeze without further receipts. Reading that
count as a frequency is the same class of trap as the truncated log.

This explains a large amount of prior work at once: **any rescue, arm, camera or
heal placed in the alarm handler cannot fire during the very condition it was
written to fix.** That includes R1480 `[xcam]`, which is why it produced nothing
despite being present in the binary with a matching source sha.

## Corrections this forces to my own earlier notes
- The R96 INT1 re-arm **is** implicated after all - but not the way I first
  proposed. It is not a data-delivery fault (delivery is healthy DMA; see the
  `drains=0` trap). It starves `CD_flush`'s only exit condition.
- "Instrument the transition out of the working regime" was the wrong next step.
  There is no gradual transition; there is a loop that, once entered with a read
  active, cannot terminate.

## Wedge contract (R967, verbatim from the run)
```
[wedge] R967 STUCK 30s in fn 0x8004252C (print 3):
  cells c0=06 c1=01 c2=00 c3=02 c4=06 c5=02 c6=00 c7=00 c8=00
  CD FE1C=00 FE04=0001A970 FDF8=00000800 FDFC=00000000 A22C=00000022 flag578A6=00
  DRV act=1 loaded=1 pos=0/2060 sched=0 pend=0 cmd=06
```
Note `flag578A6 = 00` and `c6 = 00`: the announce flag the R722D/R1296B composite
sets to 1 reads zero at the wedge. The response-consume path writes it to zero
(`memcpy(xenolift_mem + 0x800578A6, &zero, 2)`), and that path is running about a
billion times. Stated as an observation, not a mechanism - it has not been traced
to a consumer.

## Where a fix has to aim
At `CD_flush`'s exit condition, in the guest's own read context (the R1160 shape),
not in alarm context - alarm context is unreachable here by construction. The
narrow question a fix must answer: **while a ReadN is active and the guest is
draining interrupts, when is the runtime entitled to re-assert INT1?** On real
hardware the flag stays clear until the drive delivers the next sector; R96
re-asserts it on every response drain, which is not the same thing.

## Pass/fail bar
`[pendclr]` print count in `run.log.raw`. It currently reads ~15,699 (≈1.03
billion acks). A fix works if that count collapses by orders of magnitude and
`fn_0x8004252C` stops appearing in `[alarmguard]` / `[wedge]` receipts. Do not use
a rate profile, and do not read `run.log`.
