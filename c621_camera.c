                        { /* R845C (c621) decline camera: the park terms held but the door holds non-module data - receipt what it holds (R1383 near-miss precedent) */
                            static uint32_t r845c_n;
                            if (xenolift_churn_armed && mv_n >= 4000000u
                                && (long)(xl_wall() - g_boot_wall_t0) > 20
                                && r845_reforces < 8
                                && !g_splash_live
                                && (mv_n % 1048576u) == 0u
                                && xenolift_mem_read32(0x80077E88u) != 0x27BDFFC8u) {
                                if (r845c_n < 8u) { r845c_n++;
                                    r861_out("[r845decline] R845C re-force DECLINED: door 0x80077E88 holds %08X %08X %08X %08X (not the module prologue 27BDFFC8 - window repurposed; waiting for the game own install)\n",
                                            xenolift_mem_read32(0x80077E88u), xenolift_mem_read32(0x80077E8Cu),
                                            xenolift_mem_read32(0x80077E90u), xenolift_mem_read32(0x80077E94u));
                                }
                            }
                        }
