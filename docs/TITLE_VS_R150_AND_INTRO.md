# Title loop vs R150; c124 “intro” vs MDEC

DIRECTOR census 2026-09-22.

## Healthy title vs R150 error redraw
- **R150 (false success):** one 4-word GPU packet forever — prim `0x801FFF98`, tag `0x040AA6B0`, caller `0x80019E78` (splash DrawPrim). Boot error-screen redraw, not steady-state.
- **Healthy title (c124 shape):** park `fn_80036BE8`, state-0 / `cb=0x8001A4B4`, file-18 module load, millions of tex **8x8** rects.
- `[halt] render alive` alone is insufficient.

## c124 “intro finished NATIVELY” vs MDEC
- c124 receipts = title handoff / Movie **module** / GPU tiles — **not** STR/MDEC FMV decode.
- File 18 = Movie overlay code, not proof FMV bitstream played.
- Skip-movie path exists (`fn_80076AE0`).
- Real FMV still needs `[mdec] cmd1` + DMA0/1 markers.
- Conclusion: docs overclaim “intro” if that means FMV; no evidence MDEC ran then regressed.

## 5-day finish
Critical path remains field/CD door (`[pausestart] R1467A`, seek past 120634). Movie/FMV out of scope for the window.
