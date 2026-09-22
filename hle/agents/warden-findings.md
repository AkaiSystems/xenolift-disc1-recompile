# WARDEN FINDINGS — R585 ADJUDICATION & S-TIER PRE-FLIGHT CHECKLIST

**Author:** WARDEN (Integration & Regression QA Specialist, Xenolift Project)  
**Date:** 2026-09-13  
**Status:** Complete  
**Deliverable Path:** `xenolift/hle/agents/warden-findings.md`

---

## SECTION 1: R585 WATCHER-RESIZE ADJUDICATION (c154 Incident)

### Incident Context
Cycle 154 died 1 second into execution with `[disc] SLUS EXE LOAD LINE MISSING` and a `SIGSEGV` at boot entry with all guest registers zeroed. Two suspect theories were evaluated:
1. **Flaky emit cache race:** Flaky emit raced the `.emit.md5` cache gate (same failure mode as cycle 52) and the recompiled disc binary failed to load/population.
2. **R585 Watcher-Resize (81 -> 90 cells):** Build R585 expanded the bookkeeping-cell watcher array from 81 to 90 cells (adding 9 watch cells on the game's read-struct at `0x80059EF8..0x80059F2C`).

---

### Failure Mode Enumeration & Analysis
Grounded in static analysis of `xenolift/runtime/runtime.c`:

#### 1. Failure Mode: Companion Array Un-Resized / Mismatched Bounds (OOB Memory Access)
* **Code Evidence:** `runtime.c:7095` enforces compile-time verification:
  ```c
  typedef char hc_size_guard_[(sizeof(hc_addr)/sizeof(hc_addr[0]) == sizeof(hc_prev)/sizeof(hc_prev[0]) &&
                               sizeof(hc_addr)/sizeof(hc_addr[0]) == sizeof(hc_seen)/sizeof(hc_seen[0]) &&
                               sizeof(hc_addr)/sizeof(hc_addr[0]) == sizeof(hc_n)/sizeof(hc_n[0])) ? 1 : -1];
  ```
* **Analysis:** Introduced in R516 (Lesson 54), this static assert causes a compile error if `hc_addr`, `hc_prev`, `hc_seen`, or `hc_n` differ in element count. Since R585 compiled successfully, all four arrays were resized in lockstep to 90 elements. With `k < 90`, all array accesses remained strictly within static memory bounds.
* **Verdict:** **UNLIKELY**

#### 2. Failure Mode: Sweep Execution Before Memory Initialization / Out-of-Bounds Pointer Dereference
* **Code Evidence:** The sweep loop in `xenolift_trace(uint32_t a)` (`runtime.c:7282`) performs:
  ```c
  uint32_t v; memcpy(&v, xenolift_mem + hc_addr[k], 4);
  ```
* **Analysis:** `xenolift_mem` is the 2MB guest RAM buffer allocated at harness launch. The addresses monitored (`0x59EF8..0x59F2C`) are low-RAM offsets (`< 2MB`). `xenolift_trace` is only invoked upon guest function entry. `memcpy` performs a passive read from host memory without mutating guest memory or executing guest code.
* **Verdict:** **UNLIKELY**

#### 3. Failure Mode: Log Floods Stalling Execution or Deadlocking I/O
* **Code Evidence:** `runtime.c:7285` applies strict per-cell log caps:
  ```c
  int hc_cap = (k == 0 || k == 22 || k == 51 || k >= 61) ? 240 : 24;
  if (hc_n[k] < hc_cap) fprintf(stderr, "[hook] ...");
  ```
* **Analysis:** Even under continuous trigger conditions, output for the 9 new cells is capped at 240 lines per cell (Lesson 15). Log formatting does not alter guest CPU registers or trigger boot-entry `SIGSEGV` faults.
* **Verdict:** **UNLIKELY**

#### 4. Failure Mode: Re-entrancy or Nested Hook Recursion
* **Code Evidence:** `memcpy` reads directly from `xenolift_mem`. It does not invoke `xenolift_mem_read32()`, register read handlers, or `xenolift_trace()`.
* **Analysis:** The passive read path creates no execution recursion, side effects, or stack accumulation.
* **Verdict:** **UNLIKELY**

---

### Adjudication Verdict & Recommendation
* **Primary Cause of Cycle 154:** The crash was caused by the emit build/cache race. The recompiled executable `disc1.c` was truncated/missing before launch, resulting in zeroed registers and immediate `SIGSEGV` at boot entry. R586 implemented an emit self-heal check (verifying `disc1.c` contains `'xenolift_region'` and exceeds 100KB), which directly resolves this issue.
* **Watcher Recommendation:** **KEEP THE WATCHERS**. The 81->90 passive watcher array is code-safe, protected by `hc_size_guard_` compile assertions, bounded by log line caps, and provides essential passive visibility into the game's read-struct (`0x80059EF8..0x80059F2C`).

---

## SECTION 2: S-TIER PRE-FLIGHT CHECKLIST

Distilled from `LESSONS.md` as standing operational protocol before shipping any package:

1. **Probe Triple Verification (Runtime + Digest + Budget):** Every new `fprintf` probe MUST ship as a complete triple: runtime code + matching `run.sh` digest grep section + era-sized line budget (e.g. 240 lines for long runs).  
   *Rationale:* Probes missing digest greps produce invisible output, and undersized budgets expire before fault-era execution (L1, L15, L36, Lesson N+2).

2. **Parallel Array Resize-Together Rule:** When modifying fixed-size tables (e.g. `hc_addr`), update array declarations, element initializers, loop bounds, and compile-time assertions (`typedef char guard[...]`) simultaneously across all companion arrays.  
   *Rationale:* Mismatched array dimensions or loop bounds lead to initializer truncation, out-of-bounds stack/static writes, memory corruption, or silent probe death (L48, L53, L54).

3. **No Guest Code Dispatch from MMIO-Read Context:** Retirement and register read handlers MUST perform memory cell writes/state updates only, never invoking `xenolift_dispatch()` or synchronous guest functions.  
   *Rationale:* Dispatched guest code inside register-read handlers causes recursive loops and watchdog deadlocks (L2, L3).

4. **Mandatory Syntax and Implicit Function Compile Gate:** Run `gcc -fsyntax-only -Werror=implicit-function-declaration` on all C files prior to packaging.  
   *Rationale:* Sandbox GCC silently forgives missing headers and implicit function declarations, breaking target compiler builds (L7, L41).

5. **Single Package & Banner Bump Enforcement:** Bump the banner version exactly once per ship, upload only one package per turn, and verify directive block formatting before sending.  
   *Rationale:* Multiple package uploads race bridge execution, unbumped banners obscure build tracking, and literal grep tokens in banners pollute digest output (L8, L10, L15).

6. **Workspace Root Archive Construction & Content Verification:** Always execute archive packaging (`os.walk('xenolift')`) from the workspace root (not inside subfolders) and programmatically verify zip contents before shipping.  
   *Rationale:* Archiving from inside subdirectories creates empty zip files, resulting in immediate execution failure (L8, L9, L48).

7. **State Signature Probe Gating:** Gate probes and assists on explicit state signature values or state flags rather than transient phase flags (e.g. `g_movie_live`).  
   *Rationale:* Transient era flags may not clear during phase handoffs, leaving probes blind at critical transition boundaries (L4).

8. **Cached Pipeline & Artifact Verification:** Any cached build or skip path MUST verify the complete presence and structural integrity of the target artifact (e.g. verifying signature strings and minimum file size) before reuse.  
   *Rationale:* Unverified cache hits allow truncated or unpopulated binaries to run, causing zeroed-register `SIGSEGV` boot crashes (c154/R586).

9. **Digest-Matched Park & Dump Placement:** Place logging and instrumentation inside the specific park/crash dump function that the `run.sh` digest script actually reads.  
   *Rationale:* Instrumenting unused or cold park paths results in empty digest tails and lost evidence (L13).

10. **Hard Timeout Fuse & Per-Access Logging Caps:** Include a background execution fuse (`sleep 210; kill -9`) for every run, and apply explicit line caps or sparse strides to per-access loggers.  
    *Rationale:* Uncapped logging storms stall digest processing, while hung processes lock execution without yielding crash evidence (L14, L15).

11. **Signed Immediate MIPS Address Calculation:** When wiring probes from MIPS instructions (`SW/LW rX, imm(rY)`), calculate target addresses using 16-bit signed extension (offsets `>= 0x8000` extend negative).  
    *Rationale:* Unextended offset calculations monitor phantom addresses, leaving actual target memory unmonitored (Lesson 34).

12. **Direct Memory Writer & DMA Audit:** Audit direct memory writers (`memcpy`, CD-DMA staging, HLE helpers) whenever memory-store watchers report no activity on modified memory.  
    *Rationale:* Direct memory copies bypass MMIO store hooks, rendering standard address watchers silent (Lesson 37).

13. **Target MODSRC Photographic Window Authority:** Base fine-grained control flow and code analysis on MODSRC photographic windows captured from the target machine rather than sandbox source copies.  
    *Rationale:* Code layout and line numbers differ between sandbox and target environments, invalidating sandbox-only source assumptions (Lesson 38).

14. **Exact Photographed Marker Keying for Rescues:** Key rescue and defib triggers strictly on photographed state markers, omitting unverified cleanliness conditions or bad silence-clock resets.  
    *Rationale:* Over-constrained rescue conditions fail to fire when live stall states contradict theoretical assumptions (Lesson 41).

15. **Digest Script Clean Shell Syntax Formatting:** Place every new digest section on its own distinct shell line in `run.sh`, never appending after inline comment characters (`#`).  
    *Rationale:* Appending shell commands after inline comments causes bash to swallow the directive, dropping the digest section (Lesson 44).

16. **Re-entry Protection on Hook-Called Memory Helpers:** Include a top-level re-entry guard in any helper function called by memory hooks if the helper reads or writes guest memory.  
    *Rationale:* Memory reads inside unguarded memory hook helpers trigger infinite recursion and stack overflows (Lesson 33/R404).

17. **Evidence-First Gate Changes:** Verify that a target behavior is provably defective in log evidence before adding blocking latches or flow gates.  
    *Rationale:* Restricting normal game batch or retry protocols freezes active communication channels (Lesson N+1).

18. **Hardware & CD Oracle Behavior Cross-Check:** Audit CD drive and hardware emulation semantics against `docs/oracle/ORACLE_PSX_CD.md` and reference implementation prior to shipping.  
    *Rationale:* Incorrect ACK/FIFO assumptions or missing absolute deadlines cause permanent kernel execution hangs (Lesson 16).
