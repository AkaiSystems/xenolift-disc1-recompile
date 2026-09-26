# R1495 REGRESSION: never put a second writer on FDF8. My safety argument was wrong.

Not a null result — **harm**. Recorded so nobody rebuilds it.

## What it was
The early field-band death is the same disease as the TOC stall R1493 fixed.
Non-escaping trials' terminal `waitbr`:
```
ret=0  FDFC=0  FE1C=0  FE04=0001A941(108865)  FDF8=0x800
ret=0  FDFC=0  FE1C=0  FE04=0001A93F(108863)  FDF8=0x800
```
All three waiter exit terms hold, 2048 bytes still owed. Escaping trials differ
in exactly one cell: `FDF8=0`. And the sector **was** delivered — LBA 108865
loads 5x/DMAs 2x, LBA 108863 loads 6x/DMAs 4x, full 2048/2048 to valid KSEG
buffers (`0x80070AF8`, `0x800A5BF0`). Nothing missing but the decrement.

So R1495 posted the decrement, in the R1423A/R1426A family shape.

## Result: regression
```
trial   R1495 fires   escape   lastField(t)
1       9             no        1s
2       10            no        6s
3       12            no        5s
4       9             no        1s
5       11            no       56s
6       11            no        4s

R1495            0 / 6
R1493 + R1494    8 / 18  (44%)
```
It fired 9-12 times per trial, so it was active. Under the 44% rate,
**P(0 of 6) = 0.56^6 ~ 3%** — this is evidence of harm, not noise. Last field
read collapsed to 1-6s in five of six trials, *earlier* than baseline.

## Why my safety argument was wrong
I claimed a double-decrement was impossible:

> *"it decrements only when a sector was served AND FDF8 is still exactly what it
> was at that serve by the next evaluation. In healthy flow the game's own
> decrement moves FDF8 and this stands down."*

That is false. The FDF8-unchanged test only proves the game had not decremented
**yet at the moment I sampled**. The game's decrement is asynchronous — when it
lands after my sample, mine has already double-counted. And `FDF8` is the exact
cell the waiter's exit term reads, so corrupting it breaks the *healthy* path.
That is why runs died **earlier** than baseline instead of merely not improving.
No sampling scheme fixes this; it is a race between two writers, not a timing
window I sampled badly.

## The distinction I had already written down and then ignored
R1423A gets away with this mechanism in the **deep band** because nothing there
decrements natively. The **field band drains natively in the escaping runs** —
that observation is in my own earlier digest. It should have told me a second
writer would race the game, not that I needed a cleverer sample.

## Rule for this family
`FDF8` bookkeeping arms are safe only in bands where the guest never decrements.
Before adding one, prove the guest does not write that cell in that band. In the
field band it does. **Do not add a second writer to FDF8 there** — the fix for the
early field-band death has to be something other than posting the decrement
ourselves.

## Standing results, unchanged
- **R1493** (act-agnostic R1426A): 8/18 = 44% vs prior pool 2/24 = 8%,
  Fisher one-tailed p = 0.009. Stands.
- **R1494** (budget 4->32): budget exonerated, reverted.
- **R1495**: reverted. Never committed to the branch, so the tree is already
  clean; this digest is the only artifact.
- The early field-band death remains **unfixed** and still gates ~56% of runs.
