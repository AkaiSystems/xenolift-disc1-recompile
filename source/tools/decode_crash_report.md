# How-To: Decoding Bridge Digest Crash Dumps

1. Save the `[crash]` block from the bridge digest into a text file (e.g., `crash.txt`).
2. Run `mips_decode.py` specifying the base address from `[crash] code @cur_fn @<addr>`:
   `python3 xenolift/tools/mips_decode.py crash.txt --base 0x800769A4`
   (Or pipe directly: `cat crash.txt | python3 xenolift/tools/mips_decode.py`)
3. Scan the disassembly output for memory load/store instructions (`lw`, `lh`, `lb`, `sw`, `sh`, `sb`).
4. Identify the faulting instruction (typically a `lw` or `sw` performing an invalid memory access).
5. Note the base register used in the instruction, e.g., `lw v0, 16(a1)` or `sw v0, 8(r5)`.
6. Match register names/aliases: MIPS `r5` corresponds to `a1`, `r4` to `a0`, `r2` to `v0`, etc.
7. Locate the matching data dump header in the digest, e.g., `[crash] data @r5 @0x80077194:`.
8. Take the offset from the load/store instruction (e.g., `16` or `0x10` from `16(a1)`).
9. Calculate the data cell index: `cell_index = byte_offset / 4` (e.g., `16 / 4 = 4`).
10. Look up word #4 (0-indexed) in the 4-word-per-line `data @r5` dump.
11. Check if the cell value is NULL (`0x00000000`), uninitialized, or an out-of-bounds pointer.
12. Trace which structure member or argument index feeds that data cell index.
13. Cross-reference the instruction address with `xenolift/annotations.csv` for symbol name.
14. Inspect C source at that function to fix the underlying HLE state or missing buffer.
15. Re-run harness tests to verify the bridge digest crash is fully resolved.
