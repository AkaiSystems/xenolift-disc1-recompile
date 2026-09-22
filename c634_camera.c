            { /* R634A (c634): MODULE-WINDOW WRITE CAMERA (instrumentation
               * only, no behavior change). THE c632/c633 RECEIPTS: the whole
               * module window (8006F000-80090000, 33792 words incl. the door
               * 80077E88) holds 0x25252525 at stop; 0x25 = legal ADDIU - the
               * R1394 interpreter marched the fill to the 80090000 fall-off
               * (the wedgespin E88->F00 reads ARE the fetches, not a module
               * scan). The fill was LIKELY PRESENT AT ENTRY (interp entry #1
               * came via the R844 backup-bypass which SKIPS the c621 prologue
               * gate), and the WRITER IS UNRECEIPTED: the era is silent, no
               * 2525-value write receipts exist, hooks watch only fixed
               * cells, and the file#3 DMA ladder covers only the upper band.
               * THIS camera: sparse-ladder snapshot of 256 words across the
               * window (stride 0x84 = full 0x21000 coverage) at first hot-loop
               * pass - printed so boot-state is known - then diffed every
               * pass; any changed word receipts old->new + fn. Cameras only. */
                static uint32_t r634a_snap[256]; static int r634a_have;
                static uint32_t r634a_n;
                if (!r634a_have) {
                    for (uint32_t r634a_i = 0u; r634a_i < 256u; r634a_i++)
                        r634a_snap[r634a_i] = xenolift_mem_read32(0x8006F000u + r634a_i * 0x84u);
                    r634a_have = 1;
                    r861_out("[winw] R634A first snapshot: w0=%08X w1=%08X w255=%08X (the window state at camera start - fill present from boot or not)\n",
                            r634a_snap[0], r634a_snap[1], r634a_snap[255]);
                } else if (r634a_n < 40u) {
                    for (uint32_t r634a_i = 0u; r634a_i < 256u; r634a_i++) {
                        uint32_t r634a_v = xenolift_mem_read32(0x8006F000u + r634a_i * 0x84u);
                        if (r634a_v != r634a_snap[r634a_i]) {
                            r634a_n++;
                            r861_out("[winw] R634A window word %08X: %08X -> %08X (fn=%08X) - the window writer receipted\n",
                                    0x8006F000u + r634a_i * 0x84u, r634a_snap[r634a_i], r634a_v,
                                    (uint32_t)(uintptr_t)xenolift_cur_fn);
                            r634a_snap[r634a_i] = r634a_v;
                        }
                    }
                }
            }
