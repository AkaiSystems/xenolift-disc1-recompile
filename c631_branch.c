    if (sig == SIGSEGV) { /* R631A: SIGSEGV via the siginfo wrapper - host_pc + si_addr receipted, same exitdiag recovery chain */
        r1207_sa.sa_sigaction = xenolift_segvdiag;
        r1207_sa.sa_flags = SA_ONSTACK | SA_RESTART | SA_SIGINFO;
    } else {
