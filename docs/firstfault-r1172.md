# R1172 stop-only checkpoint

R1171 did NOT stop before every recovery path: xenolift_io_fault could service a module fault with a return, or execute R493 frontier repair before its stop. The earlier blanket claim is withdrawn.

R1172 adds a diagnostic-only branch at xenolift_io_fault entry, before all legacy counters, service returns and repairs. It captures all 32 GPRs, bounded raw RAM windows, complete 2MB RAM (when the capture path is supplied), and host backtrace, then exits 99. It does not call guest memory helpers; raw capture avoids their hooks. Timer signals are blocked on the faulting thread during this report. This is a replacement diagnostic dossier, not a claim that every legacy camera executes. A synchronous host fault during capture remains a possible capture failure and must be checked in the result.

All existing guest memory-helper call lines, including faulty reads and dropped writes, are unchanged from the pre-patch runtime. R828 is still only a fault-source candidate; no replacement cell is verified, no read corrected, and no completion write changed.

run.sh records R848_NAME at the launch site, archives its exact executable and matching compiled sources/object files before launch, records hashes and symbols, attempts dSYM generation with explicit status, and copies the entire authoritative run.log immediately after process exit before digest assembly. firstfault.latest names the unique capture directory. The runtime RAM file is written there with O_EXCL. No guessed newest-file match is used. Old c355 xenogears_boot_020814 is not selected or rebuilt for this new-run analysis.

Verification performed locally:
- gcc syntax check: exit 0; full warnings preserved in manager worktree. Warnings are NOT guest-address validation.
- bash -n run.sh: exit 0.
- Every pre-existing memory-helper call line matches byte-for-byte.
- Isolated harness using exact production stop helper: flag on -> exit 99, target receipt, full RAM byte-exact with no legacy mutation sentinel; flag off -> exit 0, legacy sentinel reached, no diagnostic output.

The harness is NOT a Xenogears run and does not prove game behavior. The Mac stop-only run and matching symbolication are still required. Diagnose the call preceding a backtrace return PC using that exact binary's symbol+offset or correct load slide, then verify intended cell independently before correcting one read.
