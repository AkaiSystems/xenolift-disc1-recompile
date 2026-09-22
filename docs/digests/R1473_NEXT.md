# Next Mac cycle: R1473

Landed on xenolift-clean. runtime.c SHA-256: `f1c92b791ff0dc1f251e3fa57878b53ebc02f52c4de24f90657a82b396461748`

Behavioral FIX: pause-scheduled armstart admitting pend>=1 with 2s time confirm on (seek,FDF8,sched). Look for `[pausepend] R1473 fire`. Budget 120s. One cycle. No FE1C OR. Ignore 239634 as field win.
