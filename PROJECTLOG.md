
## R429 (cycle 186) — FONTBT JOURNEY COMPLETE: the install paradox
- Journey camera worked: full builder run (menu-launch caller, heap alloc, LZSS unpack
  into ctx r16=0x801EF558 = the mysterious fault-dump address, NOT field data), palette
  decodes, field fills, then the glyph-batch reset call from return 0x80037838 =
  immediately AFTER the ctx-install store at 0x8003782C.
- Straight-line block to the store has NO branches (verified in emitted source) —
  the install store EXECUTED. Yet the cell reads 0 at fault; no clear write logged.
- CONCLUSION: cleared AFTER install. Suspects: (1) fn_80037494 font-ctx UNLOADER
  (releases block + zeroes cell when a0 != 0; runtime-pointer invoked, no static
  caller), (2) hidden SECOND journey after the kernel restart (24-line budget was
  EXACTLY exhausted; a menu relaunch re-runs the journey).
- R429 SHIPPED: fontbt budget 24->48 + digest tail -48; [fkunld] unload-camera on
  fn_80037494 entry (a0/caller/cell-state). Next digest names the clear's caller
  or shows journey 2's failed install.

## R430 (cycle 187) — both suspects cleared; the vanishing-store paradox
- c187 verdict: FKUNLD empty (unloader fn NEVER ran), FONTBT still exactly ONE
  journey (budget 48, no second journey), watcher k74 has 239 spare lines yet
  the cell reads 0 at the ResetGlyphBatch dispatch — ONE instruction after the
  unconditional install store on a proven straight-line path.
- Remaining hypotheses: (a) Mac's emitted disc1.c differs at the store (R224
  guard rewrites the file AFTER emission — sandbox copy is pre-guard), (b) the
  store writes a different value, (c) a byte-write zeroer invisible to the
  dispatch-sampled watcher.
- R430 truth table (three probes): (1) TRUE write-level hook [ctxw] inside
  mem_write32 for the ctx cell — catches the store + value + any word-zeroer;
  (2) fontbt extended with neighbor cells 0x9390/0x9398/0x93A0 (SWL/SWR
  targets) — if neighbors hold data, the tail block ran on the Mac;
  (3) modsrc window L_8003782C — photographs the MAC's actual emitted+guarded
  code at the store region.
- Field pump steady; 5 HLE sub-agents stable.

## R431 (cycle 188) — TRUTH TABLE COMPLETE: stale-map lesson
- c188 verdict: [ctxw] true write-hook fired ONCE all run (0 -> 0) = the
  install store NEVER EXECUTED. Neighbors 0x9398/0x93A0 zero at every step =
  the SWL/SWR stores I read from MY sandbox disc1.c DO NOT EXIST in the Mac's
  code. The modsrc window proved the Mac's disc1.c is a DIFFERENT BUILD
  (L_8003782C at line 96640 Mac vs 95060 sandbox; ~1580-line drift before
  this region; the R224 guard + emit evolution changed the file).
- CONSEQUENCE: all fine-grained static analysis from the sandbox copy is VOID
  for control flow. The MODSRC window = the only ground truth. LESSON LEDGED.
- Mac's REAL tail (window c188) HAS the install store at L_8003782C (same
  structure: r1=0x8006<<16, SW(+0x9394,r16), ResetGlyphBatch, ReleaseHeapBlock).
  Execution provably passes 0x800377C0 (last 80043E20 call) and reaches
  0x80037838 (ResetGlyphBatch call) but the store never fires => the skip
  branch lives in the UNSHOT GAP L_800377C0..L_80037814 on the Mac's code.
- R431 SHIP: window ('L_800377C0', 72) covering the gap. Suspect: an
  external-font-storage condition (the unloader reads flag 0x800693A0;
  SetFontExternalStorage exists in menu + module regions) - if the field era
  selects EXTERNAL font storage (memcard font file), the install path may
  branch around the cell store. Runtime unchanged, banner-only bump.
- ALSO NOTED: menu text drew with ctx=0 for ~7 min using guest 0x38 as the
  batch ptr; at ~150s the value at 0x38 changed -> fault. Fixing the ctx
  install heals both eras.

## R432 (cycle 189) — the paradox narrows to ONE unphotographed gap
- c189's gap window (L_800377C0, 41 lines, truncated at L_800377F4) matched
  the sandbox copy EXACTLY: SB/SW stores, straight-line, no branch. c188's
  tail window (L_8003782C) also matches. SW macro verified: raw address to
  mem_write32, hook correctly placed, budget 8, only 1 line used.
- PHYSICS CHAIN: straight-line C from proven-executed call-return (0x800377C0)
  to the install store, hook sound, yet no 0->801EF558 write logged and the
  cell reads 0 one dispatch later. All escape routes eliminated EXCEPT the
  Mac's code in L_800377F8..L_80037814 - BETWEEN the two windows' coverage
  (c189 truncated before it; c188 starts after it). The Mac's file diverged
  from the sandbox copy (~1590 lines of drift) so the sandbox's version of
  the gap (plain stores) is UNVERIFIED. If the Mac's gap holds a conditional
  (suspect: external-font-storage gate), the install store is conditionally
  skipped.
- R432 SHIP: single window ('L_800377F8', 41) covering exactly the gap.
  Stale windows removed. Runtime unchanged, banner-only bump.
- Font pump steady; 5 HLE sub-agents stable.

## R433 (cycle 190) — full path photographed; watch upgraded to all-widths+context
- c190's gap window (L_800377F8) matches the sandbox copy EXACTLY - the
  builder tail L_800377C0..L_8003782C is now 100% photographed across three
  tiled windows (c188 tail / c189 first half / c190 gap) and is PURE
  STRAIGHT-LINE. The install store is unconditional. Compile cache verified
  mtime-based with fresh emit+compile each cycle (stale-.o theory dead).
- Remaining paradox: store unconditional in a proven-executed straight-line
  path, hook sound, yet the ONLY write32 to the cell all run was one 0->0
  with NO CONTEXT - cannot tell if it was the boot BSS clear (t=0) or the
  install with r16=0 (t~30s). Also the word-hook is blind to SB/SH zeroers.
- R433 SHIP: (1) ctxw upgraded - every write32 to the cell now stamps
  @t=elapsed r31= r16= (install store would show r31=800377C0 r16=801EF558);
  budget 8->16. (2) NEW [ctxb] hooks in mem_write8 + mem_write16 for the
  cell range 0x80069394-97, same context stamps, budget 8 each. Next digest
  names the writer definitively: install-fires (machine fine, zeroer next),
  install-fires-with-0 (register anomaly), install-never-fires (execution
  skip at machine level despite photographed straight-line C).
- Field pump steady 8th cycle; 5 HLE sub-agents stable.

## R434 (cycle 191) — WRITER NAMED: the cell's ONLY write all run = t=0 boot zero
- c191 verdict (R433 all-widths+context watch): [ctxw] ONE line @t=0s r31=0 r16=0
  (process-start clear) + [ctxb] ONE line @t=0s. NO guest write to the cell EVER,
  at word/half/byte width. The install store NEVER EXECUTES on the Mac.
- Trampoline audited: churn bounce applies ONLY to family 0x8002A600-0x8002B400
  (CD fns) - ConfigureTexturePagePacket (0x80043E20) is NOT family; a bounce from
  inside the builder cannot explain the skip. Journey is one pass (24/48 budget),
  tail call r31=0x80037838 directly follows the 80043E20 call r31=0x800377C0.
- REMAINING PARADOX: contiguous straight-line photographed C (three tiled windows
  L_800377B0-L_80037850, verified identical to sandbox copy) with proven-executed
  endpoints and a store that never runs at any width.
- R434 SHIP: mid-block tripwires - [midw] SB hooks on 0x801EF59F/0x801EF5A3 (the
  middle block's 2nd-4th statements, ctx-struct byte stores) + SW hook on
  0x801EF5A4 (the 5th store). Bisection: fire => middle runs, the skip is between
  0x80037808 and the cell store; silent => the skip is at the 80043E20 call return
  (callee exit path = sole suspect). =MIDW= digest section added.
