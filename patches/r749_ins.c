
{ /* R749 GATED field-cb completion bypass (day-4 clause). c324 lesson: the cb's FIRST dispatch (t=0, all state cells 0) is part of boot initialization - the real body must run then (instant return unwound main at 2s, zero ticks). Bypass ONLY the field-committed era (cur(92C0)>=1 or idx(FAEC)>=1) where the record copy + helper run and the un-translatable scratchpad tail-jump kills the walk. */
if (xenolift_mem_read32(0x800592C0u) >= 1u || xenolift_mem_read32(0x8005FAECu) >= 1u) {
    static int r749n;
    if (r749n < 8) { r749n++; fprintf(stderr, "[fcbdone] R749 field cb COMPLETED at dispatch (gated bypass: clean return in committed era - kernel walk continues past field; idx(FAEC)=%u cur(92C0)=%u req(18088)=%u)\n", xenolift_mem_read32(0x8005FAECu), xenolift_mem_read32(0x800592C0u), xenolift_mem_read32(0x80018088u)); }
    return;
}
}
