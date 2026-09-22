# xenogears-recomp intel (github.com/OpokXeno/xenogears-recomp)
Study 2026-09-11 07:29 (Jos ask). Everything below cross-checked against our own decodes.

## Cross-validations (independent proof of our work)
- File 18 (0x12) = MOVIE overlay: sector 109158, stored 14,360B = EXACTLY our
  first full file-18 read (R132: 14360B, LBA 109158-109165).
- Module table files 13-18 = Battling(0x0D) / Field(0x0E) / World(0x0F) /
  Battle(0x10) / Menu(0x11) / Movie(0x12) — matches our R120 module table.
- Battle-effect overlays load at 0x801FC000 = our R116/R118 captured windows.
- Directory 0x01 files 2-5 = `wds ` AUDIO BANKS = the sound bank we upload via
  ch4 (152,576B; staging block 0x80067210 evt=2). WDS = sample bank format.
- LBA 239317 (R136 first deep read) = battle/menu family territory (0x10/0x04
  battle-result starts sector 239322).
- Menu overlay (0x11) loads at 0x801C5000 — a SEPARATE region.

## LOAD BASE FIX (R142)
- Modules load at 0x8006FAF0 — our capture window started at 0x80070000 =
  0x5B10 bytes too high, missing module-base code. R142 window:
  0x8006F000-0x8008FFFF (135KB); emitter maps at 0x8006F000; size gate
  rejects stale 131072B captures (0x10000 misalignment hazard).

## EXE facts (game.toml)
- entry_pc 0x80019524, load 0x80010000, text_size 0x4A000 -> image end
  0x8005A000 (our R117 estimate 0x59800 was 0x800 short). stack 0x801FFFF0.
- discovery = "whole-image" (they scan the whole image; our seed-based
  discovery caused the 0x80056700+ phantom — data pocket emitted as code).
- mod_function_entry_funcs = 0x8004B54C = the module fn entry (our R140 watch:
  it CLEARS slot-bits 0x80056788 — the module bookkeeping trampoline).
- disc_speed "1x" — NEVER "instant" (divisor=0 hangs at PlayStation logo).
- bios_hle = true; overlay capture-compile, identity-authenticated, cache off.

## Sound driver (docs/xenogears/audio/01-driver-architecture.md)
- InitializeSoundSystem 0x80037C80; 240Hz callback SoundSequencerCallback240Hz
  0x8003C020 (root-counter installed); InterpretReadySequenceTracks 0x8003C6E8;
  opcode fn-ptr table ~0x80050624, size table 0x80050824.
- WDS loading 0x80037FD8: alloc SPU RAM region -> ASYNC ADPCM upload (our ch4
  queue) -> copy WDS header/preset records into driver main-RAM (our 0x840
  staging block) -> record SPU address -> link loaded-WDS list.
- LoadInstrumentVoiceParameters 0x8003E5BC: 16-BYTE PRESET RECORDS (ADPCM
  start/repeat addr, pitch, ADSR) — our 128B descriptor feeds = 8 preset recs.
- SoundSpuIRQHandler 0x8003BFA0 (system/sound.c; installed via SpuSetIRQCallback,
  interrupt-context entry). Watch this entry in our runs.
- SetReverbModeDepthDelayFeedback 0x80038934; reverb work area realloc per mode.
- 24 voices, ownership/priority (SMDS 0x0100, SEDS 0x0200); one-callback
  staging rule (params/key-ons land at N+1, key-offs at N).

## Key symbols (seeds "verified promotions", decomp-backed)
- WorkListUpdate 0x8001C9F8 + WorkListsFreeAllEntries 0x8001C8DC (per-frame
  work-list dispatcher = the game loop pump, g_WorkList + onTriggerCallback).
- cb_data 0x800431C0 (CD callback, xref cb_read 0x80042F78, cd_read_retry
  0x80043460) — pairs with our CdSync 0x8003A68C / CdReady 0x8003B084.
- HeapCalloc 0x80032B64, HeapFreeBlocksWithFlag 0x8003218C (module-transition
  teardown — the 0x30 teardown class we watch at fn_800324B8).
- GfxFreeWorkBuffers 0x80024FB8; RenderFlatTriangleNearest[Mode] 0x8002E8DC/E470.
- 3D kernel renderer fns 0x8002E0FC-0x80030EF4; X-clip global 0x800500F8 (319),
  Y-clip 0x800500FC (238<<16) — RAM globals we can watch.

## BIOS thunks (seeds/slus_00664_bios_thunks.txt, 37 thunks)
- SysEnqIntRP 0x80040ACC / SysDeqIntRP 0x80040ADC — the R92-era IRQ-chain class.
- ChangeClearRCnt 0x8004B730; FlushCache(A0:44) 0x80040454 (writes our hook
  cells 0x800593AC/B0); OpenEvent 0x80040474 .. full A0/B0/C0 inventory in repo.
- ReturnFromException 0x8004BEF0, SetDefaultExitFromException 0x8004BF00.

## Overlay census (annotations/overlays/)
- 24 authenticated executable images; per-module CSVs in annotations/overlays/
  (battle/, field/, gear/, menu/, movie/, world/). disc1-images.toml has
  identities/CRCs. Usable to name Module 6 functions once it executes.
