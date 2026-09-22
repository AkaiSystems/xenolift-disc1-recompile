
{ /* R750 GATED field-cb completion bypass (day-4 clause). DEFINITION-ANCHORED (c325 lesson: R748/R749 anchored on the name string, which matches the FORWARD DECLARATION first - the gate landed in an unrelated function; the real fn ran ungated and the sp-jump crash returned). Era gate kept: bypass only when the field is committed (cur(92C0)>=1 or idx(FAEC)>=1); earlier calls run the real body. */
if (xenolift_mem_read32(0x800592C0u) >= 1u || xenolift_mem_read32(0x8005FAECu) >= 1u) {
    static int r750n;
    if (r750n < 8) { r750n++; fprintf(stderr, "[fcbdone] R750 field cb COMPLETED at dispatch (gated bypass, definition-anchored: clean return in committed era - kernel walk continues past field; idx(FAEC)=%u cur(92C0)=%u req(18088)=%u)\n", xenolift_mem_read32(0x8005FAECu), xenolift_mem_read32(0x800592C0u), xenolift_mem_read32(0x80018088u)); }
    return;
}
}
