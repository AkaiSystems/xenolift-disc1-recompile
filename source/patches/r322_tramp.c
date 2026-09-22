#include <setjmp.h> /* R322 */
#include <stdio.h> /* R322 SM-TRAMPOLINE (fixes R321 owner-leak: the first dispatch ran the normal
                     * switch and RETURNED, leaving the owner flag set forever + the setjmp frame dead;
                     * the first bounce longjmp'd into the dead frame = UB chaos -> R320 guard at 1s.
                     * R322: the owner RE-DISPATCHES RECURSIVELY (its frame stays live while active) and
                     * the bounce check measures ACTUAL stack distance (no leaky counter). */
jmp_buf xenolift_sm_jmp; int xenolift_sm_active; uint32_t xenolift_sm_pend; uintptr_t xenolift_sm_sp0;
void xenolift_dispatch(uint32_t pc)
{
    if (pc >= 0x8002A600u && pc <= 0x8002B400u) { /* R322 SM-TRAMPOLINE: bound the churn */
        if (!xenolift_sm_active) {
            xenolift_sm_active = 1;
            xenolift_sm_pend = pc;
            for (;;) {
                uint32_t pend = xenolift_sm_pend;
                volatile int probe0_ = 0;
                xenolift_sm_pend = 0;
                xenolift_sm_sp0 = (uintptr_t)&probe0_;
                if (setjmp(xenolift_sm_jmp) == 0)
                    xenolift_dispatch(pend); /* chain runs nested; bounces longjmp back HERE (frame live) */
                if (xenolift_sm_pend == 0u)
                    break; /* chain completed + returned: state machine done, unwind owner */
            }
            xenolift_sm_active = 0;
            return;
        } else {
            volatile int probe1_ = 0;
            if (xenolift_sm_sp0 - (uintptr_t)&probe1_ > 0x180000u) { /* 1.5MB nesting budget */
                static unsigned long xenolift_sm_nb;
                if (xenolift_sm_nb < 24u || (xenolift_sm_nb % 100000u) == 0u) {
                    if (xenolift_sm_nb < 24u)
                        fprintf(stderr, "[smtr] bounce #%lu pend=%08X\n", xenolift_sm_nb, pc);
                    else
                        fprintf(stderr, "[smtr] bounce #%lu (rate checkpoint)\n", xenolift_sm_nb);
                }
                xenolift_sm_nb++;
                xenolift_sm_pend = pc;
                longjmp(xenolift_sm_jmp, 1);
            }
        }
    }
