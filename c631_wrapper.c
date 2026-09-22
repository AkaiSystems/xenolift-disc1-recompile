static void xenolift_segvdiag(int sig, siginfo_t *si, void *ucv)
{ /* R631A (c631): SIGSEGV SIGINFO RECEIPT. The anchor-thread
   * xenolift_install_kit_handler(SIGSEGV) installs LAST (dispositions are
   * process-wide) and overrode main R228 SA_SIGINFO segv_handler, so the
   * c628 TRUE DEATH receipts carried cur_fn but NO faulting host PC (16
   * recoveries, budget exhausted, the address unnamed). This wrapper prints
   * BOTH addresses sigsafe (host_pc from ucontext = the faulting host
   * INSTRUCTION; si_addr = the faulting DATA address) then delegates to
   * xenolift_exitdiag_sig - the SAME recovery chain (longjmp arms, R834
   * budget, exit 99 door) proven by the c628 run; behavior byte-identical
   * after the print. Registered for SIGSEGV only, inside the R1207 armored
   * installer (per-thread altstack preserved). */
    { char _b[224]; int _n = 0; /* R984: sigsafe - handler ctx, no libc print */
      xenolift_sigput(_b, &_n, "[segvpc] R631A host_pc=0x");
      { uintptr_t _pc = 0;
#if defined(__APPLE__)
        ucontext_t *UC = (ucontext_t *)ucv;
# if defined(__x86_64__)
        _pc = (uintptr_t)UC->uc_mcontext->__ss.__rip;
# elif defined(__arm64__)
        _pc = (uintptr_t)UC->uc_mcontext->__ss.__pc;
# endif
#endif
        { static const char _hx[] = "0123456789ABCDEF";
          for (int _q = (int)(sizeof(uintptr_t) * 2) - 1; _q >= 0; _q--)
              _b[_n++] = _hx[(_pc >> (_q * 4)) & 0xFu]; } }
      xenolift_sigput(_b, &_n, " si_addr=0x");
      { uintptr_t _fa = (uintptr_t)(si ? si->si_addr : NULL);
        static const char _hx2[] = "0123456789ABCDEF";
        for (int _q2 = (int)(sizeof(uintptr_t) * 2) - 1; _q2 >= 0; _q2--)
            _b[_n++] = _hx2[(_fa >> (_q2 * 4)) & 0xFu]; }
      xenolift_sigput(_b, &_n, " cur_fn=");
      xenolift_sighex(_b, &_n, (uint32_t)(uintptr_t)xenolift_cur_fn);
      xenolift_sigput(_b, &_n, " r31=");
      xenolift_sighex(_b, &_n, (uint32_t)r[31]);
      xenolift_sigput(_b, &_n, " (faulting host instruction + faulting data address; recovery delegates unchanged)\n");
      (void)!write(2, _b, (size_t)_n); }
    xenolift_exitdiag_sig(sig);
}
