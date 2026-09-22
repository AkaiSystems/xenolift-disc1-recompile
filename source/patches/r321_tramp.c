#include <setjmp.h> /* R321 SM-TRAMPOLINE */
jmp_buf xenolift_sm_jmp; int xenolift_sm_active; int xenolift_sm_depth; uint32_t xenolift_sm_pend;
void xenolift_dispatch(uint32_t pc)
{
    if (pc >= 0x8002A600u && pc <= 0x8002B400u) { /* R321 SM-TRAMPOLINE: bound the churn */
        if (xenolift_sm_active) {
            if (++xenolift_sm_depth > 8192) {
                xenolift_sm_pend = pc;
                longjmp(xenolift_sm_jmp, 1);
            }
        } else {
            xenolift_sm_active = 1; xenolift_sm_depth = 0; xenolift_sm_pend = 0;
            if (setjmp(xenolift_sm_jmp) == 0) goto xenolift_sm_normal;
            for (;;) {
                uint32_t pend = xenolift_sm_pend;
                xenolift_sm_depth = 0; xenolift_sm_pend = 0;
                xenolift_dispatch(pend);
                if (xenolift_sm_pend == 0u) break;
            }
            xenolift_sm_active = 0;
            return;
        }
    }
xenolift_sm_normal:
