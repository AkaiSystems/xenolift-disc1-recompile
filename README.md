# Xenolift Disc 1 Recompile

Organized private continuation repo for the Xenogears Disc 1 Xenolift recompile.

**Active work branch:** `xenolift-clean`.

**Owner map:** edit/run the game stack in `source/`; read-only third-party refs in `ext/`; reading and history in `docs/`; the messy full dump is branch `xenolift-source` (ARCHIVE) — that is **not** the same thing as the `source/` folder.

## Layout

| Path | Purpose |
|------|---------|
| `source/` | Live project source (Rust crate, C runtime/HLE, run scripts, tools, patches) |
| `ext/` | Third-party reference copies (Noah/oracle). Do not treat as the game you edit. |
| `docs/` | Handoffs, plans, and project history notes |
| branch `xenolift-source` | Frozen ARCHIVE dump (≠ folder `source/`). Never rewrite/delete. |

### `source/`

- `src/` — Rust recompiler (`Cargo.toml` lives here in `source/`)
- `runtime/` — C harness you run with; `hle/` — hardware-emulation C + agent notes (siblings, both live)
- `patches/` — trampoline / insert snippets used by the live tree
- `tools/` — decode and audit helpers
- `qa/` — internal theory / census notes
- `run.sh`, `bridge-v1-api.py`, `xenolift_budget.txt` — Mac run / bridge entrypoints

### `ext/`

- `ext/noah/` — Noah / STR player reference sources
- `ext/oracle/` — PSX CD oracle reference

### `docs/`

- Handoffs and history under `docs/` and `docs/history/`
- `docs/patches/` = patch notes/records; `source/patches/` = code snippets used by the live tree

## Baseline

Verified in `docs/`: **c1252 / R1470B**.  
`source/runtime/runtime.c` SHA-256: `096f27debdcdfb5ff92dc4f82e20a705d7dfe0c205d7758899bbbf970d00e36e`.

**Source note:** that SHA already includes the R1467A FE1C gate as `6u || 0u` (docs that say the widen has not landed are stale relative to this tree).

Disc images and secrets stay on the Mac only. See `ARCHIVE.md` and `.gitignore`.
