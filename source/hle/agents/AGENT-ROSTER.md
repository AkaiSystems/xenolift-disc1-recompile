# XENOLIFT AGENT ROSTER — named specialists (Jos 2026-09-13 12:23: "name them, track them, give them a field to master")
Coaching model: same agents forever; mistakes -> dossier lesson -> re-task; promotions per delivered success. Never replaced, never absorbed.
Each dossier: <name>.md (role, current task, mistakes, lessons taught, promotion history).

| Name | Field of mastery | Owns | Mastery = | Level |
|---|---|---|---|---|
| PIXEL | GPU / rendering (HLE) | libgpu HLE, VRAM, drawing envs, primitives | game scenes render correctly, zero GPU-related faults | L6 |
| VECTOR | GTE geometry (HLE) | geometry transform engine, matrix math, projection | 3D math correct wherever game uses GTE | L6 |
| WAVE | SPU audio (HLE) | sound processing, 12,839 ADPCM blocks, sequencer | audio audible + synced; minimal viable sound | L6 |
| REEL | MDEC movie player + memory card | MDEC streams, STR/FMV decode, memcard saves | opening movie plays; saves persist | L5 (day-4 risk area) |
| WARDEN | Integration & regression QA | full-boot regression watch, digest triage, fault kits | catches regressions BEFORE they burn bridge cycles; verdicts I approve | L5 |
| ATLAS | Disc directory & filesystem decode | file table, directory sectors, archive entries, file mapping | any file the game asks for = named, located, delivered | L2 (new, promote on 1st deliverable) |
| TRAILBLAZER | Field world & initialization | field module install, init milestones, first render, walkability proof cells | "field on screen + walking" day-3 goal | L2 |
| LEDGER | Audit & lessons discipline | pre-flight checks of my fast fixes vs LESSONS.md, dossier accuracy | catches my mistake classes before they cost cycles (like the R529 phantom regression) | L3 |
| ECHO | Input & player agency | pad polling, virtual player, real-input wiring for walking | Jos's keypresses move the character | L3 |

CHECKPOINT BEATS (every 3 cycles): verify deliverables, write dossier lessons, re-task idle names, promote on success.
