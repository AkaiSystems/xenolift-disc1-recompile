# Lane work-tree protocol (Jos directive, Sep 16 c346)

Each roster agent works ONLY in its own work tree. Nobody edits shared files
directly; all shared-file changes go through the manager as patch fragments.

## Areas and ownership (files are LANE-OWNED or SHARED)

| Lane      | Owns (direct edits OK)                | Reads freely      |
|-----------|---------------------------------------|-------------------|
| WAVE      | hle/hle_spu.c                         | everything        |
| PIXEL     | hle/hle_gpu.c                         | everything        |
| VECTOR    | hle/hle_gte.c                         | everything        |
| REEL      | hle/hle_mdec.c, hle/hle_memcard.c     | everything        |
| TRAILBLAZER | src/ (Rust tool) + tools/            | everything        |
| WARDEN    | (audit-only, no edits)                | everything        |
| ATLAS     | (contract research, no edits)         | everything        |
| LEDGER    | docs/ only                            | everything        |

SHARED FILES - runtime/runtime.c, runtime/xenolift_runtime.h, run.sh, Cargo.toml:
  - NO lane edits these directly, ever. Propose a unified-diff patch fragment in
    worktrees/<lane>/shared-*.patch; the manager integrates, banner-bumps,
    syntax-checks, packages and ships. One integration per cycle = one R-bump.
  - Reason: a heal in one area changes code/cells another area's cameras watch
    (e.g. spu completion cells vs module-restore wipes vs coordinator heals).
    Single-file integration with a syntax check is the collision firewall.

## Work trees

Each lane has worktrees/<lane>/ for scratch, drafts, reports and patch
fragments. Anything outside your worktree + owned files is READ-ONLY.

## Rules that already stand (unchanged)

- Every claim needs a receipt (decomp symbol or source file:line).
- Register-by-register guessing is forbidden.
- Cross-lane findings go through the manager and land in the digest.
- Areas are not independent: changing one can change another. Before proposing
  a shared-file patch, list every OTHER lane whose cells/fns your change touches.
