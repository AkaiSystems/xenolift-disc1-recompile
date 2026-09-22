
{ /* R748 field cb completion bypass (day-4 clause): the entry tail-jumps into the scratchpad stub (jr sp+0xB0) - un-translatable, fatal for 10 cycles. The record copy + transform commit before the jump; complete the cb HERE with a clean return so the kernel state walk advances. */
static int r748n;
if (r748n < 8) { r748n++; fprintf(stderr, "[fcbdone] R748 field cb COMPLETED at dispatch (bypass: clean return - kernel walk continues past field; idx(FAEC)=%u cur(92C0)=%u req(18088)=%u)\n", xenolift_mem_read32(0x8005FAECu), xenolift_mem_read32(0x800592C0u), xenolift_mem_read32(0x80018088u)); }
return; }
