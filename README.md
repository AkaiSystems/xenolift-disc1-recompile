# Xenolift Disc 1 Recompile

Organized private continuation repo for the Xenogears Disc 1 Xenolift recompile.

## Layout

| Path | Purpose |
|------|---------|
| `source/` | Live project source (Rust crate, C runtime/HLE, run scripts, tools, patches) |
| `ext/` | External / third-party reference material (not built as primary) |
| `docs/` | Handoffs, plans, and project history notes |
| branch `xenolift-source` | **ARCHIVE** of the messy full working-tree dump — do not rewrite or delete |

### `source/`

- `src/` — Rust recompiler (`Cargo.toml` lives here in `source/`)
- `runtime/` — C HLE harness (`runtime.c`, headers)
- `hle/` — GPU / GTE / SPU / MDEC / memcard HLE + agent notes
- `patches/` — trampoline / insert snippets
- `tools/` — decode and audit helpers
- `qa/` — internal theory / census notes
- `run.sh`, `bridge-v1-api.py`, `xenolift_budget.txt` — Mac run / bridge entrypoints

### `ext/`

- `ext/noah/` — Noah / STR player reference sources
- `ext/oracle/` — PSX CD oracle reference

## Baseline

Verified in `docs/`: **c1252 / R1470B**.  
`source/runtime/runtime.c` SHA-256: `096f27debdcdfb5ff92dc4f82e20a705d7dfe0c205d7758899bbbf970d00e36e`.

Disc images and secrets stay on the Mac only. See `ARCHIVE.md` and `.gitignore`.
