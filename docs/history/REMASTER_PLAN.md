---
title: "Xenolift Remaster Plan — Xenoblade-Style Aesthetic"
summary: "Long-term plan for upgrading Xenogears' visuals to a Xenoblade Chronicles (Switch/Definitive Edition) look in Unreal Engine 5, built on the xenolift recompilation. Four phases, each gated on the previous. CONFIRMED DIRECTION (Jos, 2026-09-11): the Disc 1 straight port comes FIRST — remaster is strictly downstream."
---

# Remaster Plan: Xenoblade-Style Aesthetic

Owner's goal (2026-09-11): down the line, alter the code so the game resembles Xenoblade Chronicles on Switch. Target engine: Unreal Engine 5. This plan sits downstream of the primary goal — a fully playable, recompiled Xenogears Disc 1.

## Guiding architecture

- The **xenolift recompilation is the brain**: story, scripts, battle rules, movement, menus — all as readable native code.
- **Unreal Engine 5 is the body**: resolution, lighting, materials, camera.
- The **disc's assets** (sprites, backgrounds, models, music) are extracted once and feed both sides.
- Golden rule: the brain never changes behavior when the body changes. Visual upgrades are renderer-side or asset-side, never logic-side, until Phase 4 (explicit remake territory).

## Phase 0 — Foundation (IN PROGRESS — the current sprint)

Get the game fully playable as-is: boot → title → new game → opening movie → first field. Nothing visual changes. Every week of sprint work is permanent infrastructure for the later phases.

**Exit:** playable opening on Disc 1.

## Phase 1 — Asset extraction (the museum)

- Images: TIM/tiled texture decoder → backgrounds, sprites, UI art (partially validated via VRAM captures and the GP0 blit map).
- Audio: ADPCM sample map exists (12,839 blocks, 113 streams) → full bank dump + sequenced music (WDS/SMDS from SOUND_DRIVER_INTEL.md).
- 3D models: Gear/battle mesh extraction (GTE pipeline is live, so model data paths are known).
- Text/scripts: field/event script dump (archive FS fully decoded — the file table is the map).
- Movies: STR demux (STR_PIPELINE.md 18-step checklist).

**Exit:** organized asset tree reproducible from the disc image.

## Phase 2 — Modern renderer pass (the "clearcoat")

Run the game inside Unreal with its ORIGINAL art: recompiled logic runs unmodified; its drawing requests (the PsyQ primitive stream captured at fn_80044B70) become Unreal scene draws. 1080p+/widescreen/60fps. Look: "HD remaster," like Xenoblade Definitive Edition was to the Wii original.

**Exit:** title → opening → first field playable in Unreal at HD.

## Phase 3 — Art upgrades (the Xenoblade look, proper)

1. Backgrounds: AI-upscale or redraw the painted backdrops + modern ambient light.
2. Characters: 3D models with animation replace 2D field sprites (battles already have 3D to build on).
3. Lighting/effects: UE5 Lumen, shadows, particles for Ether/Gear attacks.
4. UI: HD redraw, Xenoblade-style typography; button-for-button identical behavior.
5. Camera: optional free-camera toggle.

**Exit:** reads as a modern JRPG while playing 1:1 like Xenogears.

## Phase 4 — Full remake territory (explicit, optional, distant)

True Xenoblade-style: fields rebuilt as real 3D spaces, free movement, remake camera. This is a new game built from the extracted story/scripts — fan-remake scale, only if Phase 3 lands and appetite remains. Original scenes were designed 2D, so every space must be re-imagined, not converted.

## Standing notes

- **Legal line**: personal project; Square Enix assets never redistributed. Private build only.
- **Sequencing discipline**: never start Phase N+1 before Phase N's exit. Phase 1 piggybacks on existing dumps (SPU RAM, ADPCM map, VRAM captures, archive FS) — starts nearly free.
- **Do-not-poison**: remaster work is additive tooling around xenolift; it must never regress the playable sprint builds.

*Drafted 2026-09-11 from Jos's direction. Disc 1 straight port confirmed as the active focus.*
