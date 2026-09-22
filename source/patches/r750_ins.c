{ /* R758 GATED field-cb bypass, REAL-ENTRY ERA (fixes R757's unbalanced block). DEFINITION-ANCHORED (c325 lesson). c336 lesson: the splice fragment MUST be brace-balanced standalone - verify programmatically, never eyeball.
   R988 (b8-c99): the two fprintf(stderr,...) calls that lived here were THE hidden libc print entry (EMITAUDIT c99: "disc1.c printf-family call count: 2", both this fragment) behind the 10-cycle exit-134 class (macreport: __stack_chk_fail <- __xvprintf <- vfprintf_l <- fprintf attributed to real_main). Now routed through xenolift_receipt (runtime.c, non-static wrapper over xl_format + write(2)) - ZERO libc print machinery reachable from the guest binary. */
extern void xenolift_receipt(const char *fmt, ...);
extern int xenolift_blank_page_guard(void);
extern int xenolift_stage2_blank_guard(void);
if (xenolift_mem_read32(0x800592C0u) >= 1u || xenolift_mem_read32(0x8005FAECu) >= 1u) {
    static int r757c;
    r757c++;
    if (r757c <= 8) {
        xenolift_receipt("[fcbdone] R758 field cb bypassed (walk phase) #%d (idx(FAEC)=%u cur(92C0)=%u req(18088)=%u)\n", r757c, xenolift_mem_read32(0x8005FAECu), xenolift_mem_read32(0x800592C0u), xenolift_mem_read32(0x80018088u));
        return;
    }
    if (r757c == 9) { xenolift_receipt("[cbreal] R758 REAL-ENTRY ERA begins: dispatch #9 falls through to the real field-cb body (idx(FAEC)=%u cur(92C0)=%u req(18088)=%u; heals + fault recovery armed)\n", xenolift_mem_read32(0x8005FAECu), xenolift_mem_read32(0x800592C0u), xenolift_mem_read32(0x80018088u)); }
    /* R1141 (b8-c324): blank-page guard at the real-entry door. c324 segvdie: dispatch fell through into a zeroed window (anchor BSS-clear class, R682 prediction). If the coordinator words are blank, remap the pristine overlay before the body runs. */
    xenolift_blank_page_guard();
    /* R1145 (b8-c328): stage-2 blank guard at the same door - the coordinator body dispatches into stage-2 (caller 0x801D3064); c328 fault cur_fn=0x801D3190 all zeros, same wipe class. */
    xenolift_stage2_blank_guard();
}
}
