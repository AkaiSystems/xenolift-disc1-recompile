/* xenolift runtime — phase 1
 * PS1: 2MB RAM, KSEG0 base 0x80000000. Xenogears text at 0x80010000.
 * All recompiled code goes through these helpers.
 */
#pragma once
#include <stdint.h>
#include <string.h>

/* R1153 (b8-c337): FRESH-EMIT COMPILE FIX. c337 receipts: the disc-stage
 * tool rebuild changed the emit hash -> first FRESH emit in ~20 cycles ->
 * disc1.c compile FATAL: "call to undeclared function 'xenolift_receipt'"
 * at the R1108 patch site (line 24469). The CACHED disc1.c had a patch-era
 * declaration masking the dependency (same cache-masked-regression class
 * as R766's stdio include). The post-emit patch family calls this fn, so
 * the shared contract header must declare it: definition is runtime.c:125. */
void xenolift_receipt(const char *fmt, ...);

#define XENOLIFT_RAM_SIZE 0x200000u
/* R926: overrun-read signature counter (defined in runtime.c) - the
 * translated LZSS loop reads it to abort runaway decompresses cleanly. */
extern volatile uint32_t g_lzss_overrun_reads;
extern volatile uint32_t g_lzss_abort_fired; /* R927: translated-loop abort counter (telemetry) */
extern volatile uint32_t g_vsync_cap_fires; /* R929: Vsync recursion-cap fires */
#define XENOLIFT_IO_BASE 0x1F800000u /* hardware registers district */
#define XENOLIFT_IO_SIZE 0x200000u

/* flat address space: RAM first, then the hardware registers */
extern uint8_t xenolift_mem[XENOLIFT_RAM_SIZE + XENOLIFT_IO_SIZE];
extern uint32_t r[32]; /* r[0] hardwired zero — emitter elides writes */
extern uint32_t hi, lo;

/* routing + typed access, implemented in runtime.c: RAM and the hardware
 * register district are handled; anything else (BIOS, cache control) faults */
uint32_t xenolift_phys(uint32_t a);
void xenolift_io_fault(uint32_t a);
uint32_t xenolift_mem_read8(uint32_t a);
uint32_t xenolift_mem_read16(uint32_t a);
uint32_t xenolift_mem_read32(uint32_t a);
void xenolift_mem_write8(uint32_t a, uint32_t v);
void xenolift_mem_write16(uint32_t a, uint32_t v);
void xenolift_mem_write32(uint32_t a, uint32_t v);

/* memory helpers */
static inline uint32_t LBU(uint32_t a) { return xenolift_mem_read8(a); }
static inline uint32_t LHU(uint32_t a) { return xenolift_mem_read16(a); }
static inline uint32_t LW (uint32_t a) { return xenolift_mem_read32(a); }
static inline uint32_t LB (uint32_t a) { return (uint32_t)(int32_t)(int8_t)xenolift_mem_read8(a); }
static inline uint32_t LH (uint32_t a) { return (uint32_t)(int32_t)(int16_t)xenolift_mem_read16(a); }

/* R1197 (Jos c493): SH/SB were static-inline FNS with NO __LINE__ capture -
 * sw_line could never attribute them. Now CALL-SCOPED MACROS: set line+width
 * +active around the write, RESTORE previous metadata after (nested-safe).
 * Direct runtime writes (not via macro) run with sw_active==0 and are labeled
 * runtime/unknown by [tblw] - never misattributed. */
#define SB(a, v) do { uint32_t _xl_svl = xenolift_sw_line, _xl_svw = xenolift_sw_width; int _xl_sva = xenolift_sw_active; xenolift_sw_line = (uint32_t)__LINE__; xenolift_sw_line_last = (uint32_t)__LINE__; xenolift_sw_width = 1u; xenolift_sw_active = 1; xenolift_mem_write8((a), (v)); xenolift_sw_line = _xl_svl; xenolift_sw_width = _xl_svw; xenolift_sw_active = _xl_sva; } while (0)
#define SH(a, v) do { uint32_t _xl_svl = xenolift_sw_line, _xl_svw = xenolift_sw_width; int _xl_sva = xenolift_sw_active; xenolift_sw_line = (uint32_t)__LINE__; xenolift_sw_line_last = (uint32_t)__LINE__; xenolift_sw_width = 2u; xenolift_sw_active = 1; xenolift_mem_write16((a), (v)); xenolift_sw_line = _xl_svl; xenolift_sw_width = _xl_svw; xenolift_sw_active = _xl_sva; } while (0)
/* R1112 (b8-c290): SW now carries the caller's disc1.c line to the
 * runtime (watcher receipts name the EXACT store site, not just the
 * containing fn). c290 elimination proof: vsyncguards APPLIED+silent
 * while the 0x80090000 poison still lands at fn 0x8004B54C - the
 * writer is a callback dispatched inside Vsync's frame; the hook
 * receipt + sw_line pins the guest store instruction that does it. */
extern uint32_t xenolift_sw_line;
extern uint32_t xenolift_sw_width; /* R1197: call-scoped width 4=SW,2=SH,1=SB */
extern int xenolift_sw_active; /* R1197: 1 only inside an SW/SH/SB call */
extern uint32_t xenolift_sw_line_last; /* R1197 (Jos c494): PERSISTENT last store line - retains R1112 "last SW caller line" semantics outside the call window (call-scoped sw_line is restored; this one is not) */
#define SW(a, v) do { uint32_t _xl_svl = xenolift_sw_line, _xl_svw = xenolift_sw_width; int _xl_sva = xenolift_sw_active; xenolift_sw_line = (uint32_t)__LINE__; xenolift_sw_line_last = (uint32_t)__LINE__; xenolift_sw_width = 4u; xenolift_sw_active = 1; xenolift_mem_write32((a), (v)); xenolift_sw_line = _xl_svl; xenolift_sw_width = _xl_svw; xenolift_sw_active = _xl_sva; } while (0)

/* partial-word accesses (LWL/LWR/SWL/SWR), little-endian semantics.
 * each merges the addressed part of the aligned word with the register value */
static inline uint32_t LWL(uint32_t a, uint32_t v)
{
    uint32_t o = a & 3u, W = xenolift_mem_read32(a & ~3u);
    uint32_t keep = (o == 3u) ? 0u : (0xFFFFFFFFu >> ((o + 1u) * 8));
    return (W << ((3u - o) * 8)) | (v & keep);
}
static inline uint32_t LWR(uint32_t a, uint32_t v)
{
    uint32_t o = a & 3u, W = xenolift_mem_read32(a & ~3u);
    uint32_t keep = (o == 0u) ? 0u : (0xFFFFFFFFu << ((4u - o) * 8));
    return (W >> (o * 8)) | (v & keep);
}
static inline void SWL(uint32_t a, uint32_t v)
{
    uint32_t o = a & 3u, W = xenolift_mem_read32(a & ~3u);
    uint32_t keep = (o == 3u) ? 0u : (0xFFFFFFFFu >> ((o + 1u) * 8));
    W = (W & keep) | (v >> ((3u - o) * 8));
    xenolift_mem_write32(a & ~3u, W);
}
static inline void SWR(uint32_t a, uint32_t v)
{
    uint32_t o = a & 3u, W = xenolift_mem_read32(a & ~3u);
    uint32_t keep = (o == 0u) ? 0u : (0xFFFFFFFFu >> ((4u - o) * 8));
    W = (W & keep) | (v << (o * 8));
    xenolift_mem_write32(a & ~3u, W);
}

/* computed control transfer: hand the (translated) target PC to the
 * dispatcher; phase 2 replaces this with a generated jump table */
#define DISPATCH(a) do { xenolift_dispatch((uint32_t)(a)); return; } while (0)

/* execution trace: every translated function prints its address on entry,
 * so a stalled/unwound run shows exactly which function misbehaved */
void xenolift_trace(uint32_t a);
#define XTRACE(a) xenolift_trace((uint32_t)(a))

/* BIOS HLE: PS1 programs call built-in services by loading the function
 * number into r9 and jumping to one of three magic addresses (0xA0/0xB0/
 * 0xC0). On real hardware that fault lands in the BIOS exception handler,
 * which dispatches. We intercept the gates in the dispatcher instead. */
void xenolift_bios_gate(uint32_t gate, uint32_t fn);
void xenolift_trap_hook(uint32_t ra, uint32_t gp);
void xenolift_boot_trace(uint32_t code);

void xenolift_dispatch(uint32_t pc);
int r1394_dispatch_guard(unsigned int t); /* R1394 (c504): the module-window interpreter guard - extern, called from the disc1.c dispatcher */
extern uint32_t xenolift_park_ticks;
void xenolift_park_tick(void);
void xenolift_syscall(void);
void xenolift_break(uint32_t code);
void xenolift_cop_stub(uint32_t word); /* COP0/1/2 — GTE goes here until phase 2 */
void xenolift_unknown(uint32_t word);
uint32_t xenolift_cdcb_slot(uint32_t addr); /* R933: CD ready/data callback slot read with garbage->NULL heal */
uint32_t xenolift_freelist_head_heal(uint32_t heap); /* R934: allocator band freelist head NULL->END-sentinel heal */
void xenolift_drawprim_cam(uint32_t prim); /* R936: DrawPrim env+prim context camera (cap 4) */
void xenolift_bodycam(uint32_t fn, uint32_t a0, uint32_t a1, uint32_t a2, uint32_t a3); /* R1051: emitted-body entry camera (dispatch hooks never see translated-to-translated calls) */
void xenolift_region(void);
