# Status correction — 12 Mac trials (2026-09-22)

## Honest field bar
- `[pausestart] R1467A` **never fired** (0/12) with FE1C `6||0` already in tree.
- Field door seek **120634 never crossed** (0/12).
- Real field-loading progress topped out ~**108987–109042** every time.

## Misleading signal (do not reuse)
- Seek ~**239634** is **not** deep field progress. It is the CD-ROM diagnostic stress path (`MovieQueueRandomSectorRead`, PROJECT_LOG R143), often from the same stuck point.

## Implication
FE1C widen was not the missing key for these runs. R1467A Pause-armstart posture never formed (or never confirmed). Next work = **gate-approach census** at the actual 1089xx terminal vs R1467A requirements (wrong door class / thrash / upstream). `reapply_OR_forbidden=YES`.

## 5-day finish
Still continuous Disc1 **field** past the real CD/field door — but the door in play may be the **1089xx** family, not a 120634 park that these trials never reached.

## Next FIX landed: R1472 (instrumentation)
Log-only `[pausestart] R1472 decline` camera between R1467A and R1464C. No armstart. runtime.c SHA after patch: `7f31353a545c739cca3172a5e3c5c059d7c4f5b099eca5176ff77f07c0e4e4d7`. Mac: pull `xenolift-clean`, rebuild, run; expect decline lines at 1089xx naming cmd/FE1C fails.
