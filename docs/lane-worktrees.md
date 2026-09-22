# Lane work trees & cross-impact rule (c346, Jos directive)

> Directive (Jos, Sep 16): "Give the sub agents work trees in certain areas and
> make sure the heals they are doing aren't stepping on others toes. Changing
> something in one area may change the code in others."

## The rule

1. Every lane heals ONLY inside its work tree (zones below).
2. A heal that must touch a SHARED or OTHER lane's zone goes through the
   manager with a cross-impact note: what zone it touches, which lanes'
   receipts/cells could read differently, and why the lane-local approach
   failed. The manager ships it and names it in the digest so every lane
   sees the change (silent parallel edits are the failure mode - c474/c494
   watcher-thread race precedent).
3. Cross-impact check before every ship (manager): diff the touched files and
   verify each edit lands in the owning lane's zone. An edit outside the
   declared zone = ship blocked until re-declared or re-assigned.
4. Zones are receipt-anchored, not vibes: each zone lists the cells/addresses
   its lane owns. A heal touching a cell owned by another lane = cross-impact.

## Zones (receipt-anchored)

| Lane | Work tree | Anchored cells / receipts |
|---|---|---|
| WAVE (sound) | hle_spu.c; runtime.c sound hooks ([sndinit]/[spudone]/[spuerr] blocks) | g_SoundControlFlags 0x8005957C, sound heap 0x80059410, queue 0x80059458, idx 0x80059510/0x800594F4 |
| ATLAS (disc/FS) | runtime.c CD cells ([cdf]/[sdoor]/[skipgate]/[archreq] blocks); disc delivery in run.sh | FE1C/FE04/FDF8/FDFC/A22C family, ftab base 0x8004FDF0 |
| TRAILBLAZER (field/overlay AOT) | src/ (Rust tool) + emit pipeline ([fldx]/[fldx2]/[modhdr]/[cbmod]); overlay map 0x8006F000/0x801D3000 | staged f14/f15 0x801D9724/0x801F8724, door 0x80077E88 |
| WARDEN (crash/regression) | crash kit ([crash]/[segvrec]/[segvdie]), park, fuse, budgets ([wd]/[faultbudget]) | recovery counter, park stages, R789 window |
| PIXEL (GPU) | hle_gpu.c ([gpulive]) | GPU cells, 0x800465EC family |
| VECTOR (GTE) | hle_gte.c | cop0/GTE state |
| REEL (movie/saves) | hle_mdec.c ([mv-conv]/[mvdoor]) | movie-loop cells, save blocks |
| LEDGER (audit) | receipt budgets ([digest]/[logcap]/[emitaudit]), shieldcheck audits | R751/R865 caps, printf audit |
| ECHO (input) | pad/SIO cells ([padrdw]/[siopad]/[cardgate]) | 0x800625FC band, SIO regs |
| MANAGER (shared core) | xenolift_runtime.h, xenolift_dispatch, alarm/drain (R885/R918/R969), mem_read/write hooks, banner, package, run.sh build gates | - |

## Shared-core change protocol (the "stepping on toes" guard)

The read/write path (xenolift_mem_read* / write*), dispatch, and alarm
machinery are MANAGER zone because every lane's hook rides them. Precedents
receipted: R1160 (sound completion) hooked mem_read16/32 - a WAVE heal in
shared core; R1151's recovery trigger windowed cur_fn to module windows and
silently missed the kernel-context runaway (c346, 131M ops, aborts=0).
Both classes are why shared-core edits require the cross-impact note.

Cross-impact checklist (run before ship):
- [ ] Which functions/cells does the edit touch?
- [ ] Which lane owns each (table above)?
- [ ] Which other lanes' receipts could change output (silent = changed
      behavior; changed output = declare in digest)?
- [ ] Is any heal gated on a window/range condition written for a different
      class? (c346 hole: window-gated recovery missed out-of-window context.)
