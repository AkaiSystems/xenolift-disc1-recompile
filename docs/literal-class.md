# The nine-digit literal class (R1171 audit, Jos c360 protocol)

Out-of-range constants passed to uint32_t guest-address helpers. They truncate
when converted: reads take the computed-garbage guest-fault path (each firing =
a recovery/restart cycle that damages state, R962), writes are silently
dropped by the wdrop funnel. Detected by `sh tools/litscan.sh` (gcc/clang
-Woverflow; a clean syntax check does NOT validate these accesses).

Per-site rule (Jos c360): role + narrowed value + intended-cell candidate +
supporting evidence. An eight-digit address elsewhere is CORROBORATION, not
proof of intent; removing a digit could select the wrong cell (0x8004FDF8 and
0x8005FDF8 are both live, receipted cells). ALL sites below are UNCHANGED in
R1171: faulty reads fault, dropped writes drop. Corrections ship only after
per-site verification (atos of the faulting build + guest-writer receipts).

| line | fn/receipt | role | literal | narrowed | candidate(s) | evidence / status |
|------|-----------|------|---------|----------|--------------|-------------------|
| 919 | R825 fldfrz2 | read | 0x80059FAEC | 0x0059FAEC | 0x8005FAEC (walk idx) | 40+ correct-form reads labeled walk-idx; guest-writer receipts pending. HELD |
| 7714 | R844 resume-key | write | 0x80059FAEC | 0x0059FAEC | 0x8005FAEC | wdrop'd since introduction; landing it changes behavior. HELD (write) |
| 7937 | on_alarm R801-arm | read | 0x80059FDF8 | 0x0059FDF8 | 0x8005FDF8 (chain member; lines 3959-71, archx 18532) VS 0x8004FDF8 (main request counter - R801 writes a file SIZE, semantics match) | CONFLICT unresolved. HELD |
| 7943 | on_alarm R801-arm | write | 0x80059FDF8 | 0x0059FDF8 | same conflict as 7937 | completion-arm heal, dropped since introduction. HELD (write) |
| 8820 | fldfrz freeze dump | read | 0x80059FAEC | 0x0059FAEC | 0x8005FAEC | as 919. HELD |
| 11238 | R927 heap sentinel | read | 0x800BFBFF8u + 8u | 0x00BFC000 (compiler folds the add at 64-bit, then truncates) | 0x801FBFF8 header's pNext slot (header at 0x801FBFF8, +8 = pNext) | R927's own comment names 0x801FBFF8; decomp memory.c:112-115; bankw receipts `800B3260 <- 801FBFF8`. NOT a remove-one-digit form. HELD |
| 11239 | R927 | read | 0x800BFBFF8u + 12u | 0x00BFC004 | 0x801FBFFC (+12 = flags slot of the header) | as 11238. HELD |
| 11240 | R927 | write | 0x800BFBFF8u + 8u | 0x00BFC000 | 0x801FC000 (pNext self-next value into the header's +8 slot) | sentinel never landed; landing it changes heap-walk behavior. HELD (write) |
| 11241 | R927 | write | 0x800BFBFF8u + 12u | 0x00BFC004 | 0x00200000 (userTag flags into the header's +12 slot) | as 11240. HELD (write) |
| 11362 | R796 zband | read | 0x80059FE04 | 0x0059FE04 | 0x8004FE04 (4F request LBA - receipt labels mirror the 4F cells) VS 0x8005FE04 | CONFLICT unresolved. HELD |
| 11363 | R796 zband | read | 0x80059FDF8 | 0x0059FDF8 | 0x8004FDF8 VS 0x8005FDF8 | as 11362. HELD |
| 11364 | R796 zband | read x2 | 0x80059FE1C / 0x80059FE20 | 0x0059FE1C / 0x0059FE20 | 0x8004FE1C/FE20 VS 0x8005FE1C (sdoor "FE1C(5F)" receipts) / 0x8005FE20 (NO correct form exists anywhere) | CONFLICT unresolved; FE20 has zero corroboration. HELD |
| 12241 | R828 WALK COMPLETE | read | 0x80059FAEC | 0x0059FAEC | 0x8005FAEC | fault#1 candidate (gate F0C==2/FDF8==0/FDFC==0 receipted except FDFC; cap 4 == 4 faults). HELD - the fault being measured |
| 15071 | R821 early handoff | write | 0x80059FAEC | 0x0059FAEC | 0x8005FAEC | wdrop'd since introduction. HELD (write) |
| 15326 | mpad | read | 0x80059FDF8 | 0x0059FDF8 | as 7937 | HELD |
| 15330 | mpad | read | 0x80059FDF8 | 0x0059FDF8 | as 7937 | HELD |
| 16245 | walk-complete stamp | write | 0x80059FAEC | 0x0059FAEC | 0x8005FAEC | wdrop'd since introduction. HELD (write) |
| 21184 | R895 bypass stamp | write | 0x80059FAEC | 0x0059FAEC | 0x8005FAEC | "idx: walk complete"; wdrop'd since introduction. HELD (write) |

Total: 12 reads, 7 writes, 19 accesses across 4 families
(FAEC idx, FDF8 request-counter, FE04/FE1C/FE20 posture, BFBFF8 heap-sentinel).

R1171 ships ONLY: the guest-fault firstfault stop (XENOLIFT_FIRSTFAULT_STOP
honored on the computed-garbage path BEFORE band-scrub/exception-routing/
restart), this audit + litscan tool, the R910 false-premise comment fix, and
the R1170 fence revert (back to the parked R1169v2 behavior). No access above
is corrected.
