            { /* R627A (c627): FTAB-REGION WRITE CAMERA (instrumentation only,
               * no behavior change). The c625/c626 receipts: the ftab at
               * 80010004 decoded HEALTHY mid-era (LBA 108754@0x800100AC,
               * ftab camera 13842/16993) and GARBAGE movie-era (LBA 2167314
               * at the same address, stab 33060+) - the ENTRIES were
               * overwritten between 20172 and 33060; base FDF0 (80010004,
               * set once at boot by 80019548) and offset FE14 (23) NEVER
               * CHANGED. The hook camera watches only 0x80010000 (one
               * write) so the table writer is UNRECEIPTED. THIS camera
               * snapshots the first 0x100 bytes of the table once, then
               * diffs every hot-loop pass and receipts each changed word
               * with the last-dispatched fn. Cameras only. */
                static uint32_t r627a_snap[0x40u]; static int r627a_have;
                static uint32_t r627a_n;
                const uint32_t *r627a_p = (const uint32_t *)(xenolift_mem + 0x10004u);
                if (!r627a_have) { memcpy(r627a_snap, r627a_p, 0x100u); r627a_have = 1; }
                else if (r627a_n < 96u) {
                    for (uint32_t r627a_i = 0u; r627a_i < 0x40u; r627a_i++) {
                        if (r627a_p[r627a_i] != r627a_snap[r627a_i]) {
                            r627a_n++;
                            r861_out("[ftabw] R627A ftab word %08X: %08X -> %08X (fn=%08X) - the table writer receipted\n",
                                    0x80010004u + r627a_i * 4u, r627a_snap[r627a_i], r627a_p[r627a_i],
                                    (uint32_t)(uintptr_t)xenolift_cur_fn);
                            r627a_snap[r627a_i] = r627a_p[r627a_i];
                        }
                    }
                }
            }
