# Digest: field coordinator (0x80077E88) reached and interpreted - one trial, needs reproduction

## Context
R1475 trial #2 (180s budget, ~/Downloads/xenolift, R1472-R1475 all present).
Max seek only 108983 (same familiar band, NOT past 120634) - this did NOT come
from crossing the CD door. Exit status 99 (internal watchdog, not a crash).

## What's new
For the first time observed this session, the `ovlint` (overlay interpreter,
R1394) fallback actually entered and began interpreting the field coordinator
module at `fn=0x80077E88` (RunFieldCoordinator per project docs):
```
[ovlint] R1394 guard #1: the live module at 80077E88 is NOT the emit-era ref
  - INTERPRETING the installed module (never the wrong translation)
[ovlint] R1394 interp entry #1 fn=80077E88 r31=80041CA0 sp=801FFE10
[ovlint] R1394 UNSUPPORTED REGIMM rt=16 at pc=80077604 w=04960E00
[ovlstop] R1394 interpreter FAIL class=3 fn=80077E88 - explicit unsupported-overlay stop
```
Also notable in the same trial: `[busyrecover] seq=351 old=1 new=0 recovery=0`
- the cd_tick_busy guard was found genuinely stuck at 1 and recovered (first
time `old=1` observed all session) - but via the non-signal recovery class
(computed-garbage-address), not a true SIGSEGV/SIGABRT, so still partial, not
full, proof of that fix's crash-recovery chain.

## Decoding the "unsupported" instruction precisely
`w=0x04960E00`: opcode=0x01 (REGIMM, correct), rs=4, **rt=0x16 (22 decimal, NOT
hex 0x10)** - I initially misread this as the already-supported bltzal (0x10)
before checking the log's `%02X` format. rt=0x16 is not a standard MIPS I
REGIMM opcode (defined values: 0x00/01/02/03/08/09/0A/0B/0C/0E/10/11/12/13).

## Why this probably isn't a missing-opcode gap
The SPECIAL-opcode handler immediately above this REGIMM code has an existing
R1463G comment describing exactly this class: *"the R844 forced field-
coordinator door entered a NOT-READY module... null-jump or partial install."*
That strongly suggests the interpreter is landing on a field-coordinator image
that hasn't finished installing/loading yet, and rt=0x16 is decoded data (a
still-loading table, an overlay slice not yet in place), not a genuine PS1
instruction. Adding an opcode case for 0x16 without confirming this would be
guessing at semantics for something that may not be real code.

## Recommendation
One trial only - not yet reproduced. Before treating this as an actionable
target: run several more trials and check whether (a) fn=80077E88 gets reached
again, (b) the same pc=0x80077604 / w=0x04960E00 recurs (suggesting a stable,
real code path) or varies (suggesting genuinely uninitialized/partial data).
Camera-only observation, no FIX proposed.
