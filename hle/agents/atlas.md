# ATLAS.MD — dossier
(tracking name: atlas.md)

**Role:** Directory/file-table decoder
**Dossier:** read this + /app/conversations/6aa26c825d5b4135ae6b48b5/xenolift/hle/BRIEFING.md (esp. LATEST KERNEL FINDINGS) + LESSONS.md before starting.

## Current task
S-TIER ASSIGNMENT (c155, Jos directive): Derive the file-completion CONTRACT from the callback disasm (L_8002B1D4 path: HandleCdReadyCompletion(0) -> read 0x8004FE38 -> write FDF8=0 -> PositionArchiveEntry -> write FDFC=0 -> return) + what stepper fn 80041430 must observe. Deliverable: atlas-findings.md, cell-by-cell completion signature. Level L4 (decide+act, report). Checkpoint: next bridge cycle.

## Mistakes & lessons taught
(none yet — record each mistake + the lesson here when verified)

## Status

GRADE c154 (Jos request): B+ — file table fully decoded and PROVEN: file 14 (LBA 108933, 125,304 bytes) shipped from his table straight into the install; file-table lookups feed the installer. His field has the best scoreboard on the roster
