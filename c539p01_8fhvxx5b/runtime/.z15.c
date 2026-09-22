/* xenolift runtime — phase 2
 * The "fake console": everything the recompiled code expects to exist.
 * RAM, registers, and stub functions for anything not yet translated
 * (BIOS calls, GTE math). Stubs report and halt so we can see exactly
 * where the run gets to — that's the smoke test.
 */
#include <string.h>
#include <time.h>
#include <setjmp.h>
#include "xenolift_runtime.h"
unsigned xenolift_errc_count; /* R143: fn_80019ACC per-cycle spike counter */
int g_field_era; /* R348: set when state-1 (field) entered — movie->field handoff done */
#include <signal.h>
#include <pthread.h>
#include <execinfo.h> /* R424: moved up - fault kit (line ~3560) backtrace needs it before the R365-era copy at 3681 */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
/* R134: HLE hardware modules delivered by the sub-agent program.
 * SPU + MDEC + memcard compile in and are wired below; GTE is held
 * out until its RTPS math passes verification. */
#include "../hle/hle_gpu.h"
#include "../hle/hle_gte.h"
#include "../hle/hle_spu.h"
#include "../hle/hle_mdec.h"
#include "../hle/hle_memcard.h"
static unsigned xl_spu_writes, xl_mdec_writes, xl_spu_dma_bytes, xl_gpu_writes, xl_gte_cmds;
static uint32_t spu_wr_pos; /* R138: file-scope so the halt dump can report the upload map */

uint8_t xenolift_mem[XENOLIFT_RAM_SIZE + XENOLIFT_IO_SIZE];
uint32_t g_sectors_loaded = 0; /* R221: stream-alive signal for the watchdog */
uint32_t r[32];
uint32_t hi, lo;

/* ---- the fake hardware district ----
 * Writes are stored and read back; the first touch of each register is
 * logged so the trace shows which chips the game talks to. A few
 * registers get real behavior so polls don't hang: timers tick, the
 * GPU reports "ready", the interrupt controller reports "nothing pending". */

static uint32_t g_tick = 0;
static uint32_t g_poll_imask = 0, g_poll_t2 = 0, g_poll_gpu = 0, g_poll_sio = 0, g_poll_istat = 0;
static long g_sio_acc_menu; /* R377: SIO (controller port) accesses since last menu frame — decisive direct-poll test */

static void io_log(uint32_t p, int is_write, uint32_t v)
{
    /* CDROM + SIO: log EVERY access. The device protocol dialogs (card
     * detect, pad poll, CD commands) are what we need to see now, and
     * the first-touch dedup hides them after the first SPU flood. */
    if (p >= 0x1F801040u && p <= 0x1F801054u)
        g_sio_acc_menu++; /* R377: count every controller-port access */
    if ((p >= 0x1F801040u && p <= 0x1F801054u) || (p >= 0x1F801800u && p <= 0x1F801803u)) {
        /* R357/L15: per-access loggers MUST be capped — cycle 105's WaitForCdData
         * poll loop wrote 20MB+ and the SIGALRM watchdog never parked (deadlock
         * class: storm fprintf vs signal-unsafe park). First 24, then sparse. */
        static long dn = 0;
        long n = ++dn;
        if (n <= 24 || (n % 50000) == 0) {
            fprintf(stderr, is_write ? "[dev] write 0x%08X = 0x%08X\n"
                                     : "[dev] read  0x%08X = 0x%08X (n=%ld)\n", p, v, n);
        }
        return;
    }
    /* SPU: throttled always-log. The game's sound task runs from the
     * periodic callback ~60 times/sec; we want the init dialogue AND
     * the steady-state register the stuck task polls, without flooding
     * the digest: first 60 accesses, then every 20000th. */
    if (p >= 0x1F801C00u && p <= 0x1F801DFFu) {
        static long sn = 0;
        long n = ++sn;
        if (n <= 60 || n % 20000 == 0) {
            fprintf(stderr, is_write ? "[spu] #%ld write 0x%08X = 0x%08X\n"
                                     : "[spu] #%ld read  0x%08X = 0x%08X\n", n, p, v);
        }
        return;
    }
    static uint8_t seen[XENOLIFT_IO_SIZE / 4];
    static long n = 0;
    uint32_t i = (p - XENOLIFT_IO_BASE) >> 2;
    if (seen[i]) {
        return;
    }
    seen[i] = 1;
    if (n++ < 80) {
        if (is_write) {
            fprintf(stderr, "[io] write 0x%08X = 0x%08X\n", p, v);
        } else {
            fprintf(stderr, "[io] read  0x%08X\n", p);
        }
    } else if (n == 81) {
        fprintf(stderr, "[io] (further registers not logged)\n");
    }
}

/* ---- GPU model (values from the nocash PSXSPX GPU chapter) ----
 * After GP1(00h) reset the status register reads 14802000h: write FIFO
 * empty (bit 28), ready to receive commands (bit 26), display disabled
 * (bit 23), interlace field (bit 13). GP1(10h) GetGPUInfo latches a
 * response word for the next GPUREAD; sub-selector 07h = "GPU type 2",
 * the retail 208-pin chip. */
static uint32_t gpu_stat = 0x14802000u;
static uint32_t gpu_read_latch = 0;

/* ---- GPU frame capture (R125) ----
 * PS1 VRAM is not CPU-addressable: pixels arrive only as GP0 command
 * streams written to 0x1F801810. Command 0xA0 (DataToVRAM) carries
 * TIM/pixel blits — the loading and title screens. Capture them into
 * a 1024x512x16bpp model; the watchdog dumps it and the host renders
 * screen.png cropped to the GP1 display area. Draw/CLUT/poly packets
 * are counted, not interpreted (first-iteration: blits only). */
static uint16_t gpu_vram[1024u * 512u];
static uint32_t gpu_blit_total, gpu_gp0_other, gpu_gp0_state;
static uint32_t gpu_blit_x, gpu_blit_y, gpu_blit_w, gpu_blit_h, gpu_blit_left;
static uint16_t gpu_disp_x, gpu_disp_y;         /* GP1(0x05) display area */
static uint16_t gpu_disp_w = 320, gpu_disp_h = 240; /* GP1(0x08) mode */
static int gpu_blit_log_budget = 24;

static void gpu_gp0(uint32_t v)
{
    switch (gpu_gp0_state) {
    case 1: /* DataToVRAM: X|Y */
        gpu_blit_x = v & 0x3FFu; gpu_blit_y = (v >> 16) & 0x1FFu;
        gpu_gp0_state = 2; return;
    case 2: { /* W|H (W in halfwords; 0 wraps to 1024) */
        gpu_blit_w = v & 0x3FFu; gpu_blit_h = (v >> 16) & 0x1FFu;
        if (!gpu_blit_w) gpu_blit_w = 1024u;
        if (!gpu_blit_h) gpu_blit_h = 512u;
        gpu_blit_left = gpu_blit_w * gpu_blit_h;
        gpu_blit_total++;
        if (gpu_blit_log_budget-- > 0)
            fprintf(stderr, "[gpu] blit %ux%u @(%u,%u)\n",
                    gpu_blit_w, gpu_blit_h, gpu_blit_x, gpu_blit_y);
        gpu_gp0_state = gpu_blit_left ? 3 : 0;
        return;
    }
    case 3: { /* pixel words: 2 halfwords each, row-major in the rect */
        for (int half = 0; half < 2 && gpu_blit_left > 0; half++, gpu_blit_left--) {
            uint32_t px = half ? (v >> 16) : (v & 0xFFFFu);
            uint32_t done = gpu_blit_w * gpu_blit_h - gpu_blit_left;
            uint32_t dx = gpu_blit_x + done % gpu_blit_w;
            uint32_t dy = gpu_blit_y + done / gpu_blit_w;
            if (dx < 1024u && dy < 512u)
                gpu_vram[dy * 1024u + dx] = (uint16_t)px;
        }
        if (!gpu_blit_left) gpu_gp0_state = 0;
        return;
    }
    default: break;
    }
    uint32_t cmd = v >> 24;
    if (cmd == 0xA0u) { /* DataToVRAM */
        gpu_gp0_state = 1;
    } else {
        gpu_gp0_other++;
    }
}

static uint32_t gpu_snap_count; /* R126 live-view counter (hoisted: used below) */

static void gpu_dump_capture(void)
{    { /* R138: full SPU RAM snapshot for memory-map verification.
       * gpu_dump_capture runs at BOTH halt paths, so the snapshot
       * survives any exit. */
        FILE *sf = fopen("spu_ram.bin", "wb");
        if (sf) {
            fwrite(g_spu.ram, 1, sizeof(g_spu.ram), sf);
            fclose(sf);
        }
        fprintf(stderr, "[hle-spu] ram snapshot %zuB -> spu_ram.bin | dma total %uB last pos 0x%X\n",
                sizeof(g_spu.ram), xl_spu_dma_bytes, spu_wr_pos);
    }

    FILE *vf = fopen("vram.bin", "wb");
    if (vf) { fwrite(gpu_vram, 2, 1024u * 512u, vf); fclose(vf); }
    FILE *mf = fopen("vram.meta", "w");
    if (mf) {
        fprintf(mf, "%u %u %u %u\n", gpu_disp_x, gpu_disp_y,
                gpu_disp_w, gpu_disp_h);
        fclose(mf);
    }
    fprintf(stderr, "[gpu] capture: %u blits, %u other cmds, %u live snapshots, display %ux%u @(%u,%u) -> vram.bin\n",
            gpu_blit_total, gpu_gp0_other, gpu_snap_count, gpu_disp_w,
            gpu_disp_h, gpu_disp_x, gpu_disp_y);
}

/* R126: live framebuffer — snapshot the VRAM model at ~4fps (wall
 * clock rate-limited) so the host Terminal viewer (xenoview.py) can
 * render the boot as it happens. Atomic via tmp+rename; the meta file
 * rides along so the viewer crops to the display area. */
static void gpu_snapshot(void)
{
    static uint32_t last_ms;
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    uint32_t ms = (uint32_t)(ts.tv_sec * 1000u + ts.tv_nsec / 1000000u);
    if (ms - last_ms < 250u) return; /* ~4 fps */
    last_ms = ms;
    FILE *f = fopen("vram_live.tmp", "wb");
    if (!f) return;
    fwrite(gpu_vram, 2, 1024u * 512u, f);
    fclose(f);
    rename("vram_live.tmp", "vram_live.bin");
    FILE *m = fopen("vram_live.meta.tmp", "w");
    if (m) {
        fprintf(m, "%u %u %u %u\n", gpu_disp_x, gpu_disp_y,
                gpu_disp_w, gpu_disp_h);
        fclose(m);
        rename("vram_live.meta.tmp", "vram_live.meta");
    }
    gpu_snap_count++;
}

static void gpu_gp1(uint32_t v)
{
    uint32_t cmd = v >> 24;
    uint32_t param = v & 0x00FFFFFFu;
    switch (cmd) {
    case 0x00: /* reset GPU */
        gpu_stat = 0x14802000u;
        break;
    case 0x02: /* acknowledge GPU IRQ */
        gpu_stat &= ~(1u << 24);
        break;
    case 0x03: /* display enable */
        if (param & 1u) {
            gpu_stat |= (1u << 23);
        } else {
            gpu_stat &= ~(1u << 23);
        }
        break;
    case 0x04: /* DMA direction */
        gpu_stat = (gpu_stat & ~(3u << 29)) | ((param & 3u) << 29);
        if (param & 3u) {
            gpu_stat |= (1u << 25); /* DRQ */
        } else {
            gpu_stat &= ~(1u << 25);
        }
        break;
    case 0x05: /* R125: display area start — the visible screen origin */
        gpu_disp_x = param & 0x3FFu;
        gpu_disp_y = (param >> 10) & 0x1FFu;
        break;
    case 0x08: { /* R125: display mode — crop size for screen.png */
        static const uint16_t hres[4] = {256, 320, 512, 640};
        gpu_disp_w = hres[(param >> 4) & 3u];
        gpu_disp_h = (param & 0x04u) ? 480u : 240u;
        break;
    }
    default:
        if (cmd >= 0x10 && cmd <= 0x1F) { /* Get GPU Info */
            switch (param & 0x0Fu) {
            case 0x02: gpu_read_latch = 0; break; /* texture window */
            case 0x03: gpu_read_latch = 0; break; /* draw area top left */
            case 0x04: gpu_read_latch = 0; break; /* draw area bottom right */
            case 0x05: gpu_read_latch = 0; break; /* draw offset */
            case 0x07: gpu_read_latch = 2; break; /* GPU type: retail 208-pin */
            case 0x08: gpu_read_latch = 0; break;
            default: break; /* 00,01,06,09-0Fh: latch unchanged */
            }
        }
        break;
    }
}

/* registers with real behavior */
static void lazy_event_check(void);

static int disc_read_lba(uint32_t lba, void *dst);

/* ---- CDROM controller model (0x1F801800-0x1F801803) ----
 * The kernel dialogs with the disc drive: select register bank via the
 * index (write 0x1F801800), send commands (write 0x1F801801 at index 0:
 * 01h GetStat, 0Ah Init, ...), then poll the interrupt state (index 1,
 * 0x1F801802/803) and pop response bytes (index 1, 0x1F801801) while
 * status bit 5 says "response FIFO not empty". We have the disc image
 * mounted, so eventually raw sector reads can be served here too; for
 * now commands get canned "drive ready" (INT3, status 02h) responses. */
extern int g_rspop_win;
uint32_t g_walk_max = 0; long g_walk_last_t = -100;
static uint32_t g_ack_starve = 0; /* R561: acks since last heartbeat tick — the c129 starve meter (top-of-file: used at line ~695, declared before first use) */
static volatile int g_park_stage = 0; /* R365: park-dump stage counter */
static volatile int g_in_park = 0;   /* R365: park backstop latch */ /* R317: defined next to g_vb_ns */
static int lad2_boot_ok = 60; /* R319: budget for boot ladder cmds (0x13 always dispatches) */
static uint8_t cd_index, cd_pending, cd_resp[16], cd_resp_n, cd_resp_pos;
static void evt_deliver_class(uint32_t cls, uint32_t spec);
unsigned xenolift_spu_dma_count;
static void cd_restore_pend(void); /* R308: fwd — spin-conv sites precede the def */
static uint8_t cd_scheduled;  /* response scheduled, not yet delivered */
static uint8_t cd_pend_ans[24]; static uint8_t cd_pend_ans_n; static uint8_t cd_pend_ans_cmd; /* R307: full multi-byte answer saved at build, restored at INT delivery (hardware order: the INT fires with its whole answer intact; our lazy delivery lets GetStat polls stomp the FIFO to 1 byte = truncated TOC = verify ladder never completes) */
static uint8_t cd_last_cmd;
/* disc data pipeline: Setloc (BCD mm/ss/sect) -> seek LBA; ReadN serves
 * 2048-byte user sectors from the mounted image through the data FIFO
 * (0x1F801802 bank0), status bit 6 (DRQSTS) says data is available. */
static uint8_t cd_params[16], cd_param_n;
static uint8_t cd_last_full[16], cd_last_full_n;
static uint32_t mv_last_cd_pass, mv_pass_now; /* R263: mvloop pass at the last CD command */ /* R263: last full command response (for re-prime replay) */
static FILE *g_disc;          /* R262: forward (defined below) — GetTD lead-out needs the image length */
static uint32_t g_sec_bytes;  /* R262: forward (defined below) */
static uint32_t cd_seek_lba;
static uint8_t cd_stream_live; /* R601: ReadS streak active — suppresses FE04 re-anchor; cleared by Setloc */
static uint32_t xenolift_stream_next = 0; /* R607: load-time needle assert (c174: drag-back beat the dispatch-time heal) */
/* R479: PORTER-CARRY state. c43 decode windows proved the porter
 * (fn_8002B084 ArchiveCurrentFileReadyCallback - "copies each ready
 * sector into the current archive destination, advances its
 * destination and remaining byte state") never runs during our stalls:
 * FDF8 freezes at FULL size (0 sectors copied), file buffers stay
 * stale, and the WDS sound-bank loader parsed a garbage record
 * (0xDF000011) from file-5's empty buffer -> fault. The rescue faked
 * FDF8=0 without delivering bytes to the destination. Now: capture the
 * dest (a1) at each module-file-read announcement (fn_800295D8) +
 * the seek LBA there, and track the file's full size (max FDF8 seen
 * since that announcement). At rescue fire, carry real disc bytes to
 * dest + (size - FDF8) exactly like the porter would. */
static uint32_t r479_dest, r479_max, r479_seek0;
static uint32_t r497_shelved_lba; /* R497: lba already pre-shelved to its frontier-armed dest */
/* R490: file#->dest / file#->disc-LBA directory, filled by the ovlread
 * announce probe (fn_800295D8). c56 proof: the game announces file N+1's
 * read while file N is still in flight, so r479_dest (last announce) is
 * ONE FILE AHEAD at rescue time — carry-v2 shelved file 3's 155KB onto
 * file 4's shelf (0x800A49E8). The map keys the carry to the file whose
 * disc address matches the rescue seek. */
static uint32_t s_ovl_dest[64], s_ovl_lba[64], s_ovl_size[64];
static uint8_t s_r491_carried[64];
static uint32_t r490_map_lookup(uint32_t lba, uint32_t *dest_out)
{ /* R492: RANGE match - the game's seek advances per-sector mid-file, so exact
   * lba equality only matched the first sector of each file (c58: sectors
   * 108866+ of file 4 missed the map -> fell back to a stale dest). Match any
   * lba inside [file_lba, file_lba + ceil(size/2048) + 2). */
    for (uint32_t k = 1u; k < 64u; k++) {
        if (s_ovl_lba[k] > 100000u && s_ovl_dest[k] >= 0x80000000u
            && s_ovl_size[k] >= 8u && s_ovl_size[k] <= 0x400000u
            && lba >= s_ovl_lba[k]
            && lba < s_ovl_lba[k] + (s_ovl_size[k] / 2048u) + 2u) {
            if (dest_out) *dest_out = s_ovl_dest[k];
            return k;
        }
    }
    return 0u;
}
static int r479_valid;
/* R155: lost-register kick. Cycle-6 proof: the module file-18 read is
 * issued (FE04=109158) each cycle, but no slot event ever dispatches
 * its h2; the next boot cycle's dir read then walks FE04 back to
 * 108886, so the R130 kick condition (FE04 != seek_lba) can never
 * fire. Snapshot the request AT ISSUE; when the register goes missing
 * at drive-idle, restore it and deliver the missing h2 event. */
static uint32_t xenolift_kick2_lba, xenolift_kick2_len;
/* R360: field-stream queue-consumer drive. Cycle-108 proof: the kernel's
 * own data handler DMAs sectors into the batch-list ring monotonically
 * (0x801E9000, +0x800/sector) and NEVER stops at ring bounds — on
 * hardware the CD driver invokes fn_8002AC24_ArchiveQueuedReadReadyCallback
 * once per data-ready signal (a0=1), and that consumer copies ring->dest,
 * advances the bookkeeping, and repositions the next entry (fn_8002AF74).
 * Without it the 61-sector field file climbs past 0x801FF800 into the
 * kernel stack (cycle-108 crash: file data 0x4294C370/0x1803E23B read as
 * the loader's saved regs) and past RAM top (0x80206800 DMA). We arm a
 * consume-pending flag per delivered sector and dispatch the REAL consumer
 * from the status-poll context (spin-kick precedent: save/restore regs,
 * guest fn dispatch) — same cadence as hardware. */
static uint8_t g_fld_stream, g_fld_consume_pending;
static uint32_t g_fldsec_total; /* R462: total field sectors delivered (freeze clock) */
static int xenolift_kick2_armed, xenolift_kick2_ticks;
static time_t g_boot_wall_t0; /* R315: process-start wall clock for the run budget */
static uint8_t cd_read_active, cd_data[2064], cd_data_loaded;
static void cd_force_deliver_int1(const char *why); /* R258 */
static uint8_t g_slot4_dispatch_pending; /* INT1 collected, handler not yet run */
static uint8_t g_cd_irq_force; /* R101: INT1 armed -> dispatch the registered CD IRQ handler pair at the next wait tick */
static uint8_t cd_arm_int1_pending; /* arm INT1 after the 802-ack of the pair */
static uint32_t cd_data_pos, cd_data_n;

static uint32_t cd_bcd(uint8_t x) { return ((x >> 4) & 15u) * 10u + (x & 15u); }
static FILE *g_disc = NULL; static uint32_t g_sec_bytes = 2048u; /* R262: hoisted decls (used by cd_cmd GetTD) */

static void cd_data_load(void)
{
    /* The kernel reads each sector as TWO DMA transfers: 12 bytes of
     * CD-XA header (minute/second/frame in BCD — it verifies the
     * sector's own address from the header!) followed by the 2048
     * user bytes. fn 0x80041534 BCD-decodes header[0..2] and the data
     * handler compares it with the expected LBA. */
    /* R105: the kernel's request stream interleaves — our seek tracking
     * can lag the kernel's expected-LBA cell (FE04). The FIFO must hold
     * the sector the CURRENT request expects or the header compare
     * fails / the wrong bytes drain. Re-anchor on every load. */
    {
        uint32_t want = xenolift_mem_read32(0x8004FE04u);
        if (want != 0u && want != cd_seek_lba) {
            /* R601: c168 receipts — the advance fired 40x to 108997 and the
             * needle was dragged back to 108996 EVERY time. FE04 holds the
             * batch start LBA all era, so this re-anchor is the counter-
             * force. While the ReadS streak is live, keep the advanced
             * needle; a genuine re-aim arrives as Setloc (0x02), which
             * clears the streak. */
            if (!cd_stream_live) {
                fprintf(stderr, "[cd] FIFO re-anchor: seek %u -> expected %u\n",
                        cd_seek_lba, want);
                cd_seek_lba = want;
            } else {
                static int ra_skip_n;
                if (ra_skip_n < 20) { ra_skip_n++;
                    fprintf(stderr, "[adv599] R601 re-anchor skipped (stream live): seek=%u expected=%u\n",
                            cd_seek_lba, want); }
            }
        }
    }
    uint32_t msf = cd_seek_lba + 150u; /* MSF = LBA + 150 */
    uint8_t mm = (uint8_t)((msf / 75u) / 60u), ss = (uint8_t)((msf / 75u) % 60u),
            ff = (uint8_t)(msf % 75u);
    if (cd_last_cmd == 0x13u) { /* R310: GetTN answer pending = command context; loading a stale
        * sector here dresses the completion up as a DATA event -> collector counts slot-4
        * -> wl dispatches h4 (sector copier) = the wrong-worker loop (cycle-58). */
        fprintf(stderr, "[cd] sector-load suppressed: GetTN (cmd 0x13) answer pending — no data event\n");
        return;
    }
    cd_data_loaded = 1;
    cd_data_pos = 0;
    cd_data[0] = (uint8_t)((mm / 10u) << 4 | (mm % 10u)); /* minute BCD */
    cd_data[1] = (uint8_t)((ss / 10u) << 4 | (ss % 10u)); /* second BCD */
    cd_data[2] = (uint8_t)((ff / 10u) << 4 | (ff % 10u)); /* frame BCD */
    cd_data[3] = 0x02; /* mode 2 (XA) */
    memset(cd_data + 4, 0, 8); /* subheader + padding */
    /* R607 (c174 verdict): the archive callback validates each served
     * sector header against its expected position; served header was 108996
     * on EVERY serve (50+ identical headers on a 46-sector file = validator
     * can never reach the final sector = file never completes, F0C frozen
     * at 14). The dispatch-time R602 heal fires, but a per-dispatch drag-
     * back re-targets the needle before this load runs. LAST-MOMENT ASSERT:
     * stream live = the stream pointer IS the truth — snap the needle right
     * before reading the payload so the served sector + header match. */
    if (cd_stream_live && xenolift_stream_next >= 108997u && xenolift_stream_next <= 109040u
        && cd_seek_lba != xenolift_stream_next) {
        static int r607_n;
        if (r607_n < 60) { r607_n++;
            fprintf(stderr, "[adv599] R607 load-time assert: seek %u -> stream %u (drag-back defeated at payload-read)\n",
                    cd_seek_lba, xenolift_stream_next); }
        cd_seek_lba = xenolift_stream_next;
    }
    if (disc_read_lba(cd_seek_lba, cd_data + 12) != 0)
        memset(cd_data + 12, 0, 2048); /* no disc: zeros */
    cd_data_n = 2060;
    g_sectors_loaded++;
    if (cd_seek_lba < 108500u || cd_seek_lba > 109400u) { /* R305: new-region delivery (state-1 files live at LBA 41/11055/36637/45581) */
            static int bigread_n = 60;
            if (bigread_n-- > 0)
                fprintf(stderr, "[bigread] sector LBA %u -> data FIFO (NEW-REGION read chain ACTIVE)\n", cd_seek_lba);
        }
        fprintf(stderr, "[cd] sector LBA %u loaded into data FIFO (header %02X:%02X:%02X + 2048 bytes)\n",
            cd_seek_lba, cd_data[0], cd_data[1], cd_data[2]);
}

/* Commands in the kernel's per-command handler table (0x80056570): their
 * completions set slot byte 3, which the event pump treats as "keep
 * looping" forever — the pump only exits on slot 2 or 5. On real
 * hardware the interrupt dispatcher runs these handlers; without
 * interrupts the cleanest emulation is to let the sync "clear stale"
 * path ack these responses silently so the slot byte stays 2. */
static int cd_flag_suppressed(uint8_t c)
{
    (void)c;
    return 0; /* experiment: deliver every response with the op flag */
}

int cd_getstat_spins = 0; /* R213: consecutive idle GetStat re-primes
                              * (the kernel POLLING for progress) */

int cd_motor_on = 1; /* R212: spindle state — Stop (0x08) turns it OFF;
                       * Setloc/ReadN/Seek/Init spin it back up. GetStat must
                       * report the LIVE state or the kernel's post-Stop poll
                       * never sees the motor-off transition it waits for. */

static void cd_cmd(uint8_t cmd)
{
    /* R533 [cmdtl]: field-era command timeline - c101: dirack4 fired 3x, the
     * Setloc ack popped, yet the game RE-ISSUED the same Setloc (seek 108934):
     * a retry loop whose missing next-step must be NAMED, not guessed.
     * Log every disc-command dispatch in the field era, in order, with the
     * full state at dispatch. (Probe-only cycle - no new heals.) */
    {
        static int ct_n;
        if (cd_seek_lba >= 108900u && ct_n < 80u) {
            ct_n++;
            fprintf(stderr, "[cmdtl] R533 #%d cmd %02x->%02x seek=%u FE1C=%u FE20=%u resp=%u/%u pend=%u sched=%u data=%u/%u FDF8=%u FE04=%08x\n",
                    ct_n, cd_last_cmd, cmd, cd_seek_lba,
                    xenolift_mem_read32(0x8004FE1Cu), xenolift_mem_read32(0x8004FE20u),
                    cd_resp_n, cd_resp_pos, cd_pending, cd_scheduled,
                    cd_data_pos, cd_data_n,
                    xenolift_mem_read32(0x8004FDF8u), xenolift_mem_read32(0x8004FE04u));
        }
    }
    /* R598 [ReadS stream advance]: c166 verdict — the field-era file layer
     * re-issues 0x09 (ReadS, streaming read) ~80x (cmdtl 09->09) and our
     * model re-served THE SAME sector every time (cd-dma LBA 108996 x80,
     * seek frozen per c159's f15stream comment). Per psx-spx, ReadN/ReadS
     * AUTO-ADVANCE: after a sector is delivered the drive reads the NEXT
     * sector. The game's re-issues are its per-sector streaming cadence —
     * each expects a NEW sector. Advance one LBA per consecutive 0x09
     * (any other command between resets the streak; Setloc re-anchors
     * anyway). Gate: only in the file-15 batch range (108996..109040) —
     * boot-era reads are 0x06+Setloc and never touch this range. When the
     * batch's last sector (109040) is consumed the game's own finalize
     * takes over (node done-form 00001524 -> stepper F0C 14->15). */
    {
        /* R599 (c167): R598's streak never survived the game's GetStat
         * (0x01) polls between ReadS re-issues — per psx-spx the drive
         * keeps streaming once reading; polls don't re-anchor it. Only a
         * new Setloc does. Streak survives 0x01; breaks on 0x02. */
        static int rs_streak;
        /* R602 (c169): c169 receipts — every advance (108996->108997) was
         * dragged back to 108996 before the next 0x09 (40+ identical
         * advances; FE04=0 so the old R105 re-anchor is NOT the resetter —
         * some per-dispatch path re-targets the needle). Fix: while the
         * stream is live, THE STREAM POINTER IS THE TRUTH — snap seek to
         * the stream's next LBA at every 0x09 dispatch, defeating ANY
         * drag-back regardless of its source. First 0x09 seeds the pointer
         * at seek+1 (current sector already served). Setloc (0x02) kills
         * the stream (fresh seek = fresh stream). Range-capped at 109040:
         * past the batch's last sector, stop snapping so the game's own
         * finalize takes over. */
        static uint32_t rs_next;
        if (cmd == 0x09u && cd_seek_lba >= 108995u && cd_seek_lba < 109041u) {
            if (!rs_streak) { rs_streak = 1; rs_next = cd_seek_lba + 1u; }
            if (rs_next >= 108997u && rs_next <= 109040u && cd_seek_lba != rs_next) {
                { static int rs_n;
                  if (rs_n < 60) { rs_n++;
                    fprintf(stderr, "[adv599] R602 needle heal: seek %u -> stream %u (FE1C=%u FDF8=%u F0C=%u)\n",
                            cd_seek_lba, rs_next, xenolift_mem_read32(0x8004FE1Cu),
                            xenolift_mem_read32(0x8004FDF8u),
                            xenolift_mem_read32(0x80059F0Cu)); } }
                cd_seek_lba = rs_next;
                xenolift_stream_next = rs_next; /* R607 mirror for load-time assert */
            } else if (rs_next >= 108997u && rs_next <= 109040u) {
                { static int rs_n2;
                  if (rs_n2 < 60) { rs_n2++;
                    fprintf(stderr, "[adv599] R602 stream serve: seek %u (FE1C=%u)\n",
                            cd_seek_lba, xenolift_mem_read32(0x8004FE1Cu)); } }
            }
            rs_next++;
            xenolift_stream_next = rs_next; /* R607 */
        } else if (cmd == 0x02u) {
            rs_streak = 0;      /* Setloc: fresh seek = fresh stream */
        } else if (cmd == 0x09u && cd_seek_lba >= 108995u && cd_seek_lba < 109041u) {
            static int rj_n;
            if (rj_n < 12) { rj_n++;
                fprintf(stderr, "[adv599] gate-REJECT 0x09 streak=%d seek=%u FE04=%08X F0C=%u\n",
                        rs_streak, cd_seek_lba, xenolift_mem_read32(0x8004FE04u),
                        xenolift_mem_read32(0x80059F0Cu)); }
        }
        if (cmd == 0x02u) {
            rs_streak = 0;           /* Setloc re-anchors the drive */
            cd_stream_live = 0;      /* R601: genuine re-aim ends the streak */
        } else if (cmd == 0x09u || cmd == 0x01u) {
            rs_streak = 1;            /* ReadS keeps streaming; GetStat polls don't break it */
            if (cmd == 0x09u && cd_seek_lba >= 108995u && cd_seek_lba < 109041u)
                cd_stream_live = 1;  /* R601: ReadS in the batch range = streak live */
        } else
            rs_streak = 0;
    }
    cd_last_cmd = cmd;
    if (cmd == 0x02u || cmd == 0x06u || cmd == 0x07u
        || cmd == 0x09u || cmd == 0x0Au) /* R212: spin-up cmds */
        cd_motor_on = 1;
    if (cmd != 0x13u) /* R213: GetStat IS the poll — don't reset on it */
        cd_getstat_spins = 0;
    cd_resp_n = 0;
    cd_resp_pos = 0;
    /* R124 (psx-spx): stat bit1 = spindle on; bit5 (0x20) = Reading.
     * Nop/GetStat returns LIVE state; Pause's first response keeps
     * bit5 set when issued mid-read. */
    uint8_t stat0 = 0x02u;
    if (cmd == 0x01u || cmd == 0x09u)
        stat0 = cd_read_active ? (0x02u | 0x20u) : 0x02u;
    cd_resp[cd_resp_n++] = stat0;
    /* R262 TOC/POSITION COMMANDS (psx-spx "CDROM Controller Command Summary").
     * Cycle-10: the movie player issued 0x13 in a retry treadmill (84
     * re-primes). 0x13 is GetTN — INT3(stat,first,last) — NOT a status poll
     * (R213 mislabeled it GetStat = 0x01); one stat byte = malformed TOC =
     * retry forever. Jos's disc = single MODE2 data track. */
    if (cmd == 0x13u) {                       /* GetTN: first/last track, BCD */
        cd_resp[cd_resp_n++] = 0x01u; cd_resp[cd_resp_n++] = 0x01u;
        fprintf(stderr, "[cd] GetTN -> stat %02X first 01 last 01\n", stat0);
    } else if (cmd == 0x14u) {                /* GetTD(track): INT3(stat,mm,ss) BCD */
        uint32_t trk = cd_param_n ? cd_bcd(cd_params[0]) : 0u;
        uint32_t lba_abs;                     /* absolute frame incl. 150 lead-in */
        if (trk == 0u) {                      /* track 0 = lead-out = disc length */
            long bytes = 0; if (g_disc) { long cur = ftell(g_disc); fseek(g_disc, 0, SEEK_END); bytes = ftell(g_disc); fseek(g_disc, cur, SEEK_SET); }
            lba_abs = (bytes > 0 ? (uint32_t)(bytes / (long)g_sec_bytes) : 305352u) + 150u;
        } else lba_abs = 150u;                /* track 1 starts at 00:02:00 */
        { uint32_t mm = lba_abs / 4500u, ss = (lba_abs / 75u) % 60u;
          cd_resp[cd_resp_n++] = (uint8_t)(((mm / 10u) << 4) | (mm % 10u));
          cd_resp[cd_resp_n++] = (uint8_t)(((ss / 10u) << 4) | (ss % 10u));
          fprintf(stderr, "[cd] GetTD(%u) -> %02u:%02u\n", trk, mm, ss); }
    } else if (cmd == 0x10u || cmd == 0x11u) { /* GetlocL / GetlocP: 8 bytes, BCD */
        uint32_t a = cd_seek_lba + 150u, mm = a / 4500u, ss = (a / 75u) % 60u, ff = a % 75u;
        uint8_t bmm = (uint8_t)(((mm / 10u) << 4) | (mm % 10u)), bss = (uint8_t)(((ss / 10u) << 4) | (ss % 10u)), bff = (uint8_t)(((ff / 10u) << 4) | (ff % 10u));
        cd_resp_n = 0;                        /* no stat byte in these two */
        if (cmd == 0x10u) { cd_resp[cd_resp_n++] = bmm; cd_resp[cd_resp_n++] = bss; cd_resp[cd_resp_n++] = bff;
                            cd_resp[cd_resp_n++] = 0x02u; cd_resp[cd_resp_n++] = 0x00u; cd_resp[cd_resp_n++] = 0x00u; cd_resp[cd_resp_n++] = 0x08u; cd_resp[cd_resp_n++] = 0x00u; }
        else              { uint32_t rl = cd_seek_lba, rm = rl / 4500u, rs = (rl / 75u) % 60u, rf = rl % 75u;
                            cd_resp[cd_resp_n++] = 0x01u; cd_resp[cd_resp_n++] = 0x01u;
                            cd_resp[cd_resp_n++] = (uint8_t)(((rm / 10u) << 4) | (rm % 10u)); cd_resp[cd_resp_n++] = (uint8_t)(((rs / 10u) << 4) | (rs % 10u)); cd_resp[cd_resp_n++] = (uint8_t)(((rf / 10u) << 4) | (rf % 10u));
                            cd_resp[cd_resp_n++] = bmm; cd_resp[cd_resp_n++] = bss; cd_resp[cd_resp_n++] = bff; }
        fprintf(stderr, "[cd] Getloc%c -> %02X:%02X:%02X (LBA %u)\n", cmd == 0x10u ? 'L' : 'P', bmm, bss, bff, cd_seek_lba);
    }
    if (cmd == 0x02u && cd_param_n >= 3u) { /* Setloc(amm,ass,asect) BCD */
        { static int w02n = 12;
          if (w02n > 0) { w02n--;
              fprintf(stderr, "[cdw02] Setloc issue: FE04=%u FE1C=%u FE20=%u pending=%u resp_n=%u read_active=%u motor=%u sched=%u seek(before)=%u\n",
                      xenolift_mem_read32(0x8004FE04u), xenolift_mem[0x4FE1Cu], xenolift_mem[0x4FE20u],
                      cd_pending, cd_resp_n, cd_read_active, cd_motor_on, cd_scheduled, cd_seek_lba);
          } }
        cd_seek_lba = (cd_bcd(cd_params[0]) * 60u + cd_bcd(cd_params[1])) * 75u
                    + cd_bcd(cd_params[2]) - 150u;
        fprintf(stderr, "[cd] Setloc BCD %02X:%02X:%02X -> LBA %u\n",
                cd_params[0], cd_params[1], cd_params[2], cd_seek_lba);
    } else if (cmd == 0x0Eu && cd_param_n >= 1u) { /* Setmode — R149
         * (STR_PIPELINE.md checklist #3): the movie player sets mode
         * 0x80/0xE0 (2x double-speed + XA-ADPCM + raw sectors) before
         * STR streaming. Log the transition; 2x does not change our
         * instant-serve model but flags the STR phase in the digest. */
        uint8_t m = cd_params[0];
        fprintf(stderr, "[cd] Setmode 0x%02X (speed=%sx XA=%s realidx=%s ReportAF=%s)\n",
                m, (m & 0x80u) ? "2x" : "1x", (m & 0x20u) ? "on" : "off",
                (m & 0x08u) ? "raw" : "cooked", (m & 0x10u) ? "on" : "off");
    } else if (cmd == 0x06u || cmd == 0x09u) { /* ReadN/ReadS: data will be
        served from seek LBA. R163: per psx-spx, 0x09 = CdlReadS (streams
        sectors like ReadN, variable speed) — the R124-era model wrongly
        classed it as Pause and STOPPED the drive, starving the kernel's
        deep-boot 0x09 requests (cycle-14 park: file#6, FDF8=2660 stuck,
        read_active=0, 329 response re-primes, no sectors). */
        /* Anchor the served sector to the CDFS's OWN expected LBA
         * (cell 0x8004FE04): the data handler verifies the sector
         * header address against this cell (compare in fn 0x8002B084),
         * and it advances by +1 per accepted sector (MIPS delay-slot
         * increment at 0x8002B178). Anchoring here keeps the header
         * check passing even when our event ordering made the kernel
         * issue ReadN before it processed the Setloc. */
        uint32_t expect = xenolift_mem_read32(0x8004FE04u);
        if (expect != cd_seek_lba) {
            fprintf(stderr, "[cd] ReadN: serving LBA %u (kernel expected, "
                            "was seeked %u)\n", expect, cd_seek_lba);
            cd_seek_lba = expect;
        }
        cd_read_active = 1;
        cd_data_loaded = 0; /* load on first demand (status poll/data read) */
    } else if (cmd == 0x08u) { /* Stop (0x09 re-classed ReadS in R163) */
        cd_read_active = 0;
    }
    /* R263: remember the FULL response so a re-prime replays it. Cycle-11:
     * GetTN answered (stat,01,01), consumed, then the kernel re-read the port
     * and the re-prime handed back ONE status byte = truncated TOC = re-ask
     * treadmill (10x). */
    memcpy(cd_last_full, cd_resp, sizeof cd_resp); cd_last_full_n = cd_resp_n;
    if (cd_resp_n > 1u) { memcpy(cd_pend_ans, cd_resp, sizeof cd_resp); cd_pend_ans_n = cd_resp_n; cd_pend_ans_cmd = (uint8_t)cmd; } /* R307 */
    mv_last_cd_pass = mv_pass_now;
    cd_param_n = 0; /* parameter fifo consumed by the command */
    /* Event-driven arrival: the response is NOT pending yet. It becomes
     * "ready" (INT3 raised) when the kernel's event-flag check function
     * (fn 0x8004B894, which reads the RAM flag cell 0x800578A6) is next
     * entered — our stand-in for the asynchronous controller interrupt.
     * The kernel's wait loops poll that flag cell, not the CD registers,
     * so a read-triggered delay would never fire inside them. */
    cd_pending = 0;
    cd_scheduled = 1;
    /* R252 LOG BUDGET: a stuck wait class (cycle-1-R250 GetStat treadmill)
     * can log millions of lines — the GB-scale run.log stalled the digest
     * greps 220s (bridge watchdog kill mid-digest). First 40, then every
     * 65536th. */
    static uint32_t cd_log_n;
    cd_log_n++;
    if (cd_log_n <= 40u || (cd_log_n & 65535u) == 0u)
        fprintf(stderr, "[cd] command 0x%02X -> INT3 scheduled (event delivery) (n=%u)\n", cmd, cd_log_n);
}

uint32_t cdreg_r[8], cdreg_w[8]; /* per-index read/write counters (R95) */
static int cd_write(uint32_t p, uint32_t v)
{
    if (p >= 0x1F801800u && p <= 0x1F801803u) cdreg_w[p - 0x1F801800u]++;
    v &= 0xFFu;
    switch (p) {
    case 0x1F801800:
        cd_index = v & 3u; /* register bank select */
        return 1;          /* reads of 800 return STATUS, not the index */
    case 0x1F801801:
        if ((cd_index & 3u) == 0u) {
            cd_cmd((uint8_t)v); /* command register (bank 0) */
        }
        return 1;
    case 0x1F801802:
        if ((cd_index & 3u) == 0u) { /* parameter fifo (bank 0) */
            if (cd_param_n < sizeof(cd_params))
                cd_params[cd_param_n++] = (uint8_t)v;
            return 1;
        }
        if ((cd_index & 3u) == 1u && (v & 7u) == 7u && cd_arm_int1_pending) {
            /* final ack concluding a ReadN's INT3: the drive now has the
             * sector ready -> raise INT1 so the pump's slot-4 data
             * handler drains the FIFO into the kernel's buffer. */
            cd_arm_int1_pending = 0;
            cd_resp[0] = 0x02; /* data-ready status byte */
            cd_resp_n = 1;
            cd_resp_pos = 0;
            cd_pending = 1;
            if (!cd_data_loaded)
                cd_data_load();
            fprintf(stderr, "[cd] ReadN ack pair done -> INT1 armed (LBA %u, %u bytes)\n",
                    cd_seek_lba, cd_data_n);
            g_cd_irq_force = 1;
            return 1;
        }
        /* fall through to bank1 ack handling */
    case 0x1F801803:
        if ((cd_index & 3u) == 0u) {
            /* request register: bit7 = want-data (arm the NEXT data
             * interrupt). It does NOT reset the data FIFO — the kernel
             * issues it before EVERY DMA arm (see fn 0x80042AA8), and
             * the position read + data read of one sector must see a
             * CONTINUOUS stream (12-byte header, then 2048 user bytes).
             * The FIFO reload happens in the DMA drain hook, when a
             * sector is fully consumed. */
            return 1;
        }
        if ((cd_index & 3u) == 1u && (v & 7u) == 7u) {
            /* acknowledge interrupt (write 7 to the flag register). The
             * sync "clear stale" path acks responses it doesn't want —
             * from the driver's point of view the op is over either way,
             * so the kernel op flag must clear here too (otherwise the
             * event pump spins forever waiting for a consumed response
             * that was discarded). */
            uint16_t zero = 0;
            int was_pending = (cd_pending != 0);
            uint8_t was_level = cd_pending;
            cd_pending = 0;
            cd_resp_n = cd_resp_pos = 0;
            if (was_pending && was_level == 3u && cd_read_active
                && (cd_last_cmd == 0x06u || cd_last_cmd == 0x09u)) {
                /* this ack pair concludes a ReadN's INT3: after the
                 * final 802-ack, raise INT1 (sector data ready). */
                cd_arm_int1_pending = 1;
            }
            /* R124 (psx-spx): Pause (0x09) delivers a SECOND response
             * — INT2 (Complete), 1 stat byte with bit5 Read CLEARED —
             * after its INT3 ack. The kernel's fd layer treats the
             * INT2 as "drive officially stopped, request done": it
             * pops the queue and services the next request (the
             * overlay module file read). Without this the pump polls
             * GetStat forever on a state that never changes. */
            if (was_pending && was_level == 3u
                && (cd_last_cmd == 0x0Au
                    || cd_last_cmd == 0x07u
                    || cd_last_cmd == 0x08u
                    || cd_last_cmd == 0x1Au)) { /* R262: GetID has the same INT3-then-INT2 shape */ /* 0x09 ReadS removed R163; R208: Stop (0x08) same shape — cycle-41 Mac: reads completed FDF8->0, kernel sent Stop (0x08) between files and parked polling its completion; the re-prime treadmill spun (7x, last_cmd=0x08) because the Stop INT2 never armed */
                /* R124: Pause second response INT2; R132: Init (0x0A)
                 * has the SAME two-response shape per psx-spx
                 * (INT3(stat) then INT2(stat)). R147: Seek (0x07) TOO —
                 * the R146 Mac read file 18 COMPLETE (FDF8->0, all
                 * sectors to the 0x801F0494 install region, module
                 * native at 0x8006F000), then issued Seek(0x07) to LBA
                 * 109166 (first-past-the-module territory), got the
                 * INT3 ack, and PARKED in the fd processor (r31=
                 * 0x80041C78, r16=0xE fd queue, r11/r15 holding the
                 * movie-module tail 0x80076F3B/43) waiting for the
                 * Seek's INT2 that this model never armed — the same
                 * missing-second-response class R123 found for Pause.
                 * Stat: motor on, Read cleared (the drive is AT the
                 * target, not reading). */
                cd_resp[0] = 0x02u; /* motor on, Read cleared */
                cd_resp_n = 1;
                cd_resp_pos = 0;
                cd_pending = 2; /* INT2: Complete */
                if (cd_last_cmd == 0x1Au) { /* GetID INT2: stat, flags, type(0x20=mode2 licensed), atip, "SCEA" */
                    cd_resp[1] = 0x00u; cd_resp[2] = 0x20u; cd_resp[3] = 0x00u;
                    cd_resp[4] = 'S'; cd_resp[5] = 'C'; cd_resp[6] = 'E'; cd_resp[7] = 'A';
                    cd_resp_n = 8;
                    fprintf(stderr, "[cd] GetID complete: INT2 (licensed mode2, SCEA) armed\n");
                } else if (cd_last_cmd == 0x07u)
                    fprintf(stderr, "[cd] Seek complete: INT2 (at target %u) armed\n", cd_seek_lba);
                else if (cd_last_cmd == 0x08u) {
                    fprintf(stderr, "[cd] Stop complete: INT2 (drive stopped) armed\n");
                    cd_motor_on = 0; /* R212: spindle OFF after Stop */
                }
                else
                    fprintf(stderr, "[cd] Pause complete: INT2 (drive stopped) armed\n");
            }
            if (was_pending) {
                memcpy(xenolift_mem + (0x800578A6u & 0x1FFFFFFFu), &zero, 2);
                fprintf(stderr, "[cd] interrupt acknowledged (op flag cleared)\n");

{ static uint32_t ack_cam; uint32_t ac_fe1c = xenolift_mem_read32(0x8004FE1Cu);
  if (cd_seek_lba >= 108933u && cd_seek_lba < 108996u) {
    /* R561 STARVE FIX: c129 verdict — the guest ack loop runs in execution
     * context where the SIGALRM heartbeat STARVES (wd fired t=30s then not
     * until t=200s; the f14pump armed its only sector on the only tick it
     * got). This code runs on EVERY ack INSIDE the loop — re-arm the host
     * timer here so on_alarm keeps ticking through the loop, and count acks
     * between ticks so the next digest shows the starvation directly. */
    g_ack_starve++;
    alarm(1); /* fresh 1s heartbeat from inside the loop — pump engine stays alive */
    if (ack_cam < 48u) { ack_cam++;
      fprintf(stderr, "[ackcam] R561 field-era ack#%u starve=%u t=%lds: FE1C=%u pend=%u last_cmd=%02X seek=%u resp_n=%u resp_pos=%u data=%u/%u\n",
              ack_cam, g_ack_starve, (long)(time(NULL) - g_boot_wall_t0), ac_fe1c, cd_pending, cd_last_cmd, cd_seek_lba, cd_resp_n, cd_resp_pos, cd_data_pos, cd_data_n);
    } } }
            } else {
                fprintf(stderr, "[cd] interrupt acknowledged\n");
            }
        }
        return (cd_index & 3u) == 1u ? 1 : 0;
    }
    return 0;
}

/* R396 REGISTER-POLL DELIVERY. Cycles 152/153 park: field-era ReadN
 * waits in the kernel's LOW-LEVEL driver poll (fault regs: r3=0x1F801802,
 * r31 in the 0x80028xxx CD driver) reading the INT flag register — but a
 * SCHEDULED response (cd_scheduled=1) only becomes pending when the
 * kernel's event-flag check fn (0x8004B894/0x8004293C/0x800286CC dispatch
 * hooks) runs, which this wait loop never reaches -> deadlock (park:
 * sched=1 resp_n=1 pending=0 for 130s+). psx-spx hardware truth:
 * 1F801802h/1F801803h.Index1 bits 0-2 ("Response Received") show the
 * drive's interrupt AS SOON AS the response is ready — no event-layer
 * gating. Deliver inline at the INT-flag poll: pure HLE state writes +
 * the RAM flag cell 0x800578A6 the kernel polls (R113 instant-release
 * precedent). NO guest dispatch from this MMIO-read context (R350).
 * Guard mirrors the event-hook defer: skip while a sector event is in
 * flight (cd_pending!=0) or mid-stream (0x800286CC variant guard). */
static void cd_sched_poll_release(void)
{
    /* R399 SEEK-WIDEN: cycle 156 — the kernel mounted state 1 (FIELD,
     * Channel F + native commit at fn_80036760: req(8088)=1, sentinel
     * 92C0=-1), restart step consumed it, and the mount chain issued the
     * field data seek (Setloc 24:14:33 -> LBA 108933) — then stalled: the
     * seek reply has NO delivery vehicle in this era (the R395 menu-frame
     * assist died with the menu era; the event-hook fns are not reached;
     * the R398 gate accepted only cmd 06). The seek reply (cmd 02) needs
     * the same poll delivery. Boot-safety: the cmd-06 deliveries fired 6x
     * during boot c156 with zero harm (hardware-faithful: the reply IS
     * ready; the INT flag register must show it) — cmd-02 seeks during
     * boot module reads share the identical signature and are equally
     * hardware-faithful. R397 gate history: ungated release broke boot
     * (c154) by stealing deliveries with NO signature match; the
     * response-wait signature (FE1C==2 + FE04==seek + FDF8!=0) is the
     * safety boundary, not the command byte. */

    /* R611 TRUE ENDGAME BRANCH: c178 proved the R610 twin could never fire —
     * the shared gate tail (FDF8!=0, FE04==seek) re-applied the read-era legs
     * to the completion posture that lacks them BY DEFINITION. Hoisted here,
     * the tail legs are bypassed ONLY for this exact fingerprint:
     * GetStat poll + state-7 seek-waiter + needle inside file-15 band +
     * ledger drained (the R607 success state) + stream ring slot armed. */
    int r611_end = (cd_last_cmd == 0x01u
        && xenolift_mem_read32(0x8004FE1Cu) == 7u
        && cd_seek_lba >= 108995u && cd_seek_lba < 109041u
        && xenolift_mem_read32(0x8004FDF8u) == 0u
        && xenolift_mem_read32(0x8004FE08u) == 0x8007F2F8u);
    /* R397 FIELD-SIGNATURE GATE (kept): response-wait state + request
     * matches drive + bytes still wanted — boot and plain movie eras
     * can never match when no read is armed (FDF8==0 / FE04 mismatch). */
    /* R401 STATE-WIDEN: c158 park — the field Setloc reply waits at
     * FE1C=1 (seek-issued wait), NOT state 2 (read-issued); the R400
     * release sat in every polled branch yet never fired because the
     * gate demanded state 2 only. Accept BOTH reply-wait states. */
    /* R614 TRUE TOP-LEVEL HOIST (c181: r613post=0 while 11 releases fired
     * as ordinary cmd-02/06 seek replies — the OUTER command leg
     * (cmd==02||06) gates the WHOLE chain, so the cmd-01 completion
     * branch inside the OR-chain could never fire. Same lesson as R611,
     * one level up: the completion posture must own its OWN top-level
     * leg, not share the read-era command gate. */
    /* R628 INSTALL-DONE LEG (c198: RESUMEFIX fired, file-14 install COMPLETED
     * - FDF8 walked full->0, done-path ran, PA positioned next entry FE04=108989.
     * New park posture: cmd=02 sched=1 pend=0 at fe1c=0 with FDF8==0 FDFC==0 -
     * the CONCLUDED wait. The c181-era gate demands fe1c 1/2 + FDF8!=0
     * (read-in-flight); this waiter is read-finished, drive at the answered
     * position. The scheduled reply was queued at issue - deliver it. */
    if (cd_scheduled && cd_pending == 0u
        && (cd_last_cmd == 0x02u || cd_last_cmd == 0x06u)
        && xenolift_mem_read32(0x8004FE1Cu) == 0u
        && xenolift_mem_read32(0x8004FDF8u) == 0u
        /* R629 (c199): the real concluded park holds FDFC=1 (PA stamped
         * its entry-positioned flag at install-done, PA#5 receipt). The
         * FDFC==0 demand was one flag too strict - 3 boot-region releases
         * fired but the seek=108989 field park never matched. Concluded
         * posture = fe1c==0 + FDF8==0 + FE04==seek; FDFC is not a gate. */
        && cd_seek_lba != 0u
        && xenolift_mem_read32(0x8004FE04u) == cd_seek_lba) {
        cd_restore_pend();
        { static int r628n; if (r628n < 200) { r628n++;
            fprintf(stderr, "[cd] R628 install-done release: cmd=%02X stat=%02X seek=%u FE04=%u - concluded-wait answer delivered\n",
                    cd_last_cmd, cd_resp[0], cd_seek_lba, xenolift_mem_read32(0x8004FE04u)); } }
        cd_scheduled = 0;
        cd_pending = 3; /* INT3: response ready in the FIFO */
    }
    if (cd_scheduled && cd_pending == 0u
        && (r611_end
            || ((cd_last_cmd == 0x02u || cd_last_cmd == 0x06u)
                && (xenolift_mem_read32(0x8004FE1Cu) == 1u
                    || xenolift_mem_read32(0x8004FE1Cu) == 2u
                    /* R412 NOP-PROBE STATE (c169): cmd-01 probe reply
                     * waits in FE1C state 10 (field-band strict). */
                    || (xenolift_mem_read32(0x8004FE1Cu) == 10u
                        && cd_last_cmd == 0x01u
                        && cd_seek_lba >= 108900u && cd_seek_lba < 109150u))
                && cd_seek_lba != 0u
                && xenolift_mem_read32(0x8004FE04u) == cd_seek_lba
                && xenolift_mem_read32(0x8004FDF8u) != 0u))) {
        /* R398: mid-stream guard REMOVED — cd_cmd(0x06) sets
         * cd_read_active=1 BEFORE the stat INT3 can ever deliver, so the
         * guard blocked the release in the exact scenario it gates (c155:
         * park signature matched, release silent, CD6 empty). The
         * sector-event defer is already covered by cd_pending==0. */
        /* R612 CONTENT FIX (c179: r611release=11 fired, waiter STILL parked):
         * the restore handed back the PREVIOUS cmd's answer (the seek-ack
         * envelope, n=3) for a cmd-0x01 GetStat poll — wrong envelope, wrong
         * content. The game accepted status 0x02 (motor on, not reading, not
         * seeking) for its read-era GetStat polls (R594 Pause precedent,
         * psx-spx status byte). Completion posture = seek done: deliver the
         * 1-byte status directly. */
        if (r611_end && cd_last_cmd == 0x01u) {
            /* R615: c182 receipts show stat=00 on most completion answers
             * (cd_motor_on flag cleared in this era) — a motor-off GetStat
             * tells the driver to re-spin instead of concluding. The drive
             * HAS been streaming ring sectors nonstop (fldsec receipts):
             * the motor is objectively on. Hardware-faithful status = 0x02
             * (motor on, not reading, not seeking) for the completion
             * posture. */
            cd_resp[0] = 0x02u;
            cd_resp_n = 1u;
            cd_resp_pos = 0u;
        } else {
            cd_restore_pend(); /* R308: restore the full multi-byte answer */
        }
        { static int r610n; if (r610n < 400) { r610n++;
            fprintf(stderr, "[cd] R612 endgame release: cmd=%02X stat=%02X fe1c=%u seek=%u - scheduled answer delivered\n",
                    cd_last_cmd, cd_resp[0], xenolift_mem_read32(0x8004FE1Cu), cd_seek_lba); } }
        cd_scheduled = 0;
        cd_pending = 3; /* INT3: response ready in the FIFO */
        uint16_t one = 1;
        memcpy(xenolift_mem + (0x800578A6u & 0x1FFFFFFFu), &one, 2);
        /* R613 EVENT LEG (c180: 426 GetStat answers popped, waiter STILL
         * parked — the answer leg was never the gate). fn_80041CA0 (the
         * game's own event dispatcher, MODSRC-shipped disasm) routes on
         * the SLOT BITS word 0x80056788: bit2 (mask 4) set -> the
         * registered seek-complete handler chain (0x800564AC cell); bit2
         * clear -> the 80041CE0 branch (the parked path we keep seeing).
         * Post the EVENT, not just the answer: slotbits |= 4 in the
         * completion posture. Wrong-bit worst case = same parked path
         * (receipt decides). */
        if (r611_end) {
            uint32_t slotbits = xenolift_mem_read32(0x80056788u);
            xenolift_mem_write32(0x80056788u, slotbits | 4u);
            { static int r613n; if (r613n < 400) { r613n++;
                fprintf(stderr, "[cd] R613 event post: slotbits %08X -> %08X (bit2=seek-complete event, handler cell 564AC=%08X)\n",
                        slotbits, slotbits | 4u, xenolift_mem_read32(0x800564ACu)); }
            /* R616: track the true walk frontier — the release receipt caps
             * hid how far the needle got each run (=ENDREL= tail now shows
             * it, but a hard number in =COUNTS= survives cap+tail edits). */
            { static uint32_t walk_steps; static long walk_t_prev;
              if (cd_seek_lba > g_walk_max) g_walk_max = cd_seek_lba;
              g_walk_last_t = g_boot_wall_t0 ? (long)(time(NULL) - g_boot_wall_t0) : 0L;
              walk_steps++;
              /* R623 EARLY LATCH: c193 fired the 92BC stamp at wrap (t=201)
               * = 4s before park -> zero observation window for the mount
               * waiter. Stamp at walk-era ENTRY instead so the whole walk
               * (84s, ~20 mount polls) runs with the success signal live.
               * Wrap-site stamp stays as a held/not-held receipt. */
              { static int early_latched;
                if (!early_latched && g_walk_max >= 109000u) {
                    early_latched = 1;
                    uint32_t lv = xenolift_mem_read32(0x800592BCu);
                    if (lv == 0u) {
                        xenolift_mem_write32(0x800592BCu, 1u);
                        fprintf(stderr, "[cd] R623 mountlatch-early: 92BC forced 0 -> 1 at walk-era entry t=%lds (mount-success stamped early; watch MNTACC idx/req/92D0 across the walk)\n", g_walk_last_t);
                    } else {
                        fprintf(stderr, "[cd] R623 mountlatch-early: 92BC already %08X at walk entry\n", lv);
                    }
                } }
              long now = g_boot_wall_t0 ? (long)(time(NULL) - g_boot_wall_t0) : 0L;
              if ((walk_steps & 1u) == 0u)
                  fprintf(stderr, "[cd] R617 walk frontier: steps=%u max_seek=%u t=%lds dt=%lds\n",
                          walk_steps, g_walk_max, now, now - walk_t_prev);
              walk_t_prev = now;
              /* R618 WRAP DETECTOR (c187: walk hit 109038, 2 sectors from
               * file-15 end 109040, then the game re-seeked to 108996 and
               * restarted the read — mount never concluded). One-shot: when
               * the needle drops far below the walk's max, dump the read
               * queue node + counters to fingerprint the restart decision. */
              { static int wrapped;
                if (!wrapped && g_walk_max >= 109010u && cd_seek_lba + 4u < g_walk_max) {
                    wrapped = 1;
                    fprintf(stderr, "[cd] R618 WRAP DETECTED: seek %u -> %u (max %u) t=%lds | "
                            "F0C=%08X F10=%08X F14=%08X F18=%08X FDF8=%08X FDE4=%08X FE04=%08X FE08=%08X "
                            "FE1C=%08X FE20=%08X cur92C0=%08X req8088=%08X idxFAEC=%08X 92D0=%08X 92BC=%08X\n",
                            g_walk_max, cd_seek_lba, g_walk_max, now,
                            xenolift_mem_read32(0x80059F0Cu),
                            xenolift_mem_read32(0x80059F10u),
                            xenolift_mem_read32(0x80059F14u),
                            xenolift_mem_read32(0x80059F18u),
                            xenolift_mem_read32(0x8004FDF8u),
                            xenolift_mem_read32(0x8004FDE4u),
                            xenolift_mem_read32(0x8004FE04u),
                            xenolift_mem_read32(0x8004FE08u),
                            xenolift_mem_read32(0x8004FE1Cu),
                            xenolift_mem_read32(0x8004FE20u),
                            xenolift_mem_read32(0x800592C0u),
                            xenolift_mem_read32(0x80018088u),
                            xenolift_mem_read32(0x8005FAECu),
                            xenolift_mem_read32(0x800592D0u),
                            xenolift_mem_read32(0x800592BCu));
                    /* R619 (c189 fingerprint verdict): at wrap the game's
                     * remaining-bytes FDF8=0 — the read is DONE from its own
                     * accounting, yet the mount never concludes (92D0=0,
                     * idx=1 frozen) and the read restarts. The recorded plan:
                     * stamp the mount-success latch 92BC at exactly this
                     * moment (one-shot) and watch whether the mount waiter
                     * concludes (idx/req/F0C advance) or the game clears it. */
                    { uint32_t latch_v = xenolift_mem_read32(0x800592BCu);
                      if (latch_v == 0u) {
                          xenolift_mem_write32(0x800592BCu, 1u);
                          fprintf(stderr, "[cd] R619 mountlatch: 92BC forced 0 -> 1 at wrap (mount-success stamp, one-shot) - watch MNTACC idx/req/92D0 next\n");
                      } else {
                          fprintf(stderr, "[cd] R619 mountlatch: 92BC already %08X at wrap - NOT forced\n", latch_v);
                      } }
                } } } }
        }
        { static int rpd_logs; if (rpd_logs++ < 24)
            fprintf(stderr, "[cd] INT3 delivered at INT-flag poll (register ctx, cmd 0x%02X FE1C=%u FDF8=%u)\n",
                    cd_last_cmd, xenolift_mem_read32(0x8004FE1Cu), xenolift_mem_read32(0x8004FDF8u)); }
    }
    /* R398 near-miss: every field condition holds EXCEPT FE1C==2 — log once
     * so the next digest NAMES the blocker instead of silence. */
    if (cd_scheduled && cd_pending == 0u && cd_last_cmd == 0x06u
        && cd_seek_lba != 0u
        && xenolift_mem_read32(0x8004FE04u) == cd_seek_lba
        && xenolift_mem_read32(0x8004FDF8u) != 0u
        && xenolift_mem_read32(0x8004FE1Cu) != 2u) {
        static int nm_logs;
        if (nm_logs++ < 24)
            fprintf(stderr, "[cd] poll-release near-miss: FE1C=%u (need 2) sched=%u pend=%u cmd=%02X seek=%u FE04=%08X FDF8=%u act=%u\n",
                    xenolift_mem_read32(0x8004FE1Cu), cd_scheduled, cd_pending,
                    cd_last_cmd, cd_seek_lba, xenolift_mem_read32(0x8004FE04u),
                    xenolift_mem_read32(0x8004FDF8u), cd_read_active);
    }
}
/* R403 FIELD-DATA CAMERA: c160 — the field read chain UNLOCKED (Setloc cmd-02
 * AND ReadN cmd-06 both delivered at the FE1C RAM-poll; counters drifted by
 * exactly 2 deliveries with boot sections untouched) — the run now stalls one
 * stage LATER: data phase started (1 sector loaded, data_n=2060) but NOTHING
 * flows (FDF8=125048 owed, no dmaarm/cd-dma for LBA 108933, field dest zero,
 * fd-ticks +1 only). The guest sits in ANOTHER RAM-poll wait at the data stage
 * while the boot-era sector pump (fd-tick -> handler pair -> h2 ->
 * LegacyCdSectorFetch -> ch3 DMA) never gets its dispatch. Camera: log which
 * disc registers, RAM cells, and dispatch contexts are touched while the
 * field-data signature holds. Latch resets per instance (Lesson 32). */
static int fld_data_sig(void)
{
    /* R404 RECURSION GUARD (c161 crash, 2s in): the camera probes watch
     * reads of FE04/FDF8/FE1C/578A6 — and this helper ITSELF reads
     * FE04/FDF8 through the same hook => probe -> sig -> read -> probe
     * -> ... unbounded recursion -> stack guard page -> SIGBUS at
     * xenolift_mem_read32+792 (crash kit resolved it: cur_fn 0x80041820
     * r31 0x80041CA0, sig 10, boot file-2 read). Guard at the ROOT:
     * re-entered sig checks simply return 0. */
    static int in_sig;
    if (in_sig) return 0;
    in_sig = 1;
    /* R405 ERA-GATE: c162 — the camera's 96-line budget was eaten whole
     * by BOOT module reads (seeks 108754-108886; mapped pattern: guest
     * polls 800 idx0 while sectors flow, seek +1 / FDF8 -2048 per sector).
     * The field stage (seek 108933+) never logged. Gate the shared sig to
     * the field's disc region: >=108900 (boot files 108754-108886, file-18
     * 109158 stays visible after). Boot's pattern is banked; the field
     * stage is the unmapped stall. */
    int r = cd_scheduled == 0u && cd_pending == 0u && cd_last_cmd == 0x06u
        && cd_seek_lba >= 108900u
        && xenolift_mem_read32(0x8004FE04u) == cd_seek_lba
        && xenolift_mem_read32(0x8004FDF8u) != 0u;
    in_sig = 0;
    return r;
}
static uint32_t fld_seen;   /* per-instance combo latch */
static int fld_was;         /* signature held last check? */
static uint32_t fld_n;      /* total budget 96 */
static void fld_data_note(int in_sig)
{
    if (in_sig && !fld_was)
        fld_seen = 0; /* new instance: reset latch (Lesson 32) */
    fld_was = in_sig;
}

static uint32_t cd_read(uint32_t p)
{
    if (p >= 0x1F801800u && p <= 0x1F801803u) cdreg_r[p - 0x1F801800u]++;
    {   /* R403 fld-data camera: disc-register poll map */
        int fs = fld_data_sig(); fld_data_note(fs);
        if (fs && fld_n < 96u) {
            unsigned combo = (unsigned)((p - 0x1F801800u) * 4u) + (cd_index & 3u);
            if (combo < 32u && !((fld_seen >> combo) & 1u)) {
                fld_seen |= 1u << combo;
                fprintf(stderr, "[cd] fld-data poll reg=1F8018%02X idx=%u seek=%u FDF8=%u\n",
                        (unsigned)(p - 0x1F801800u), (unsigned)(cd_index & 3u),
                        cd_seek_lba, xenolift_mem_read32(0x8004FDF8u));
                fld_n++;
            }
        }
    }

    /* R400 FIELD-POLL MAP: cycles 156/157 — the R399 release (in the 802/803
     * idx1 INT-flag branches) NEVER fires for the field read (CD6 shows only
     * the 6 boot deliveries) even though EVERY gate condition matches the
     * park (FE1C=2 cmd=06 seek=FE04 FDF8!=0 sched=1 pending=0) => the field
     * wait polls some OTHER register/index. Log each distinct (reg,idx) read
     * while the signature holds — once per combo, budget 16. No lines next
     * digest = the wait is on a RAM cell (0x800578A6 flag family), not MMIO. */
    /* R401 STATE-WIDEN: c158 park — the field Setloc reply waits at
     * FE1C=1 (seek-issued wait), NOT state 2 (read-issued); the R400
     * release sat in every polled branch yet never fired because the
     * gate demanded state 2 only. Accept BOTH reply-wait states. */
    if (cd_scheduled && cd_pending == 0u
        && (cd_last_cmd == 0x02u || cd_last_cmd == 0x06u)
        && (xenolift_mem_read32(0x8004FE1Cu) == 1u
            || xenolift_mem_read32(0x8004FE1Cu) == 2u)
        && cd_seek_lba != 0u
        && xenolift_mem_read32(0x8004FE04u) == cd_seek_lba
        && xenolift_mem_read32(0x8004FDF8u) != 0u) {
        unsigned combo = (unsigned)((p - 0x1F801800u) * 4u) + (cd_index & 3u);
        static uint32_t fpm_seen;
        if (combo < 32u && !((fpm_seen >> combo) & 1u)) {
            fpm_seen |= 1u << combo;
            fprintf(stderr, "[cd] field-poll reg=1F8018%02X idx=%u (signature hold)\n",
                    (unsigned)(p - 0x1F801800u), (unsigned)(cd_index & 3u));
        }
    }

    switch (p) {
    case 0x1F801800: /* status: index | motor | resp fifo | data fifo */
        cd_sched_poll_release(); /* R400: field wait may poll STATUS */
        if (cd_read_active && !cd_data_loaded)
            cd_data_load(); /* serve on demand */
        /* R123: the fd-processor context (BIOS-style INT handling,
         * r31=0x80041CA0) polls this status register waiting for
         * bit 0x20 (response byte available). Our per-command
         * status byte gets consumed during INT3 processing, leaving
         * the FIFO empty -> bit 0x20 never lights -> infinite poll.
         * On real HW a status read reflects the drive's LIVE state:
         * re-prime the FIFO with a GetStat-style status byte so the
         * handler can fetch it and complete its processing. */
        /* R132: TREADMILL FIX — only re-prime at DRIVE-IDLE. The
         * R131 condition included cd_read_active, so during streams
         * EVERY status poll refilled the FIFO with a fake byte; the
         * kernel consumed 100000 of them in a poll treadmill until
         * the budget died mid-stream and the fd spin froze. During
         * active reads the native INT1 machinery owns the loop. */
        /* R391 FIELD-SEEK ASSIST (HOISTED — cycle 148: the assist never fired because it lived INSIDE the FIFO-empty gate; the field stall holds 1 stray byte in the FIFO (resp_n=1,pos=0) so the gate can never open. Hoisted above the gate so every status poll checks the field-stall config) — cycles 146/147 parked IDENTICALLY: field read
                 * fully armed (FE04==seek LBA 108933, ~124KB batch at 801D0BD8) but the
                 * state machine wedged in state 1 (FE1C==1) after SetLoc (last_cmd=02):
                 * pending=0, data_n=0, resp FIFO holds only the 1-byte re-prime, reads-done
                 * frozen, every movie-era assist refire=0 (their gates don't match the
                 * field-era config). The movie-era SetLoc advanced 1->2 on a 3-byte answer
                 * ([rspop] 02/01/01 pattern, last_cmd=0x02) delivered via the INT1
                 * handler-pair conversion. Manufacture exactly that: prime the canonical
                 * 3-byte SetLoc answer + arm INT1 (pending=3) so the established fd-tick
                 * handler-pair path converts it natively. No guest dispatch here (R350). */
                if (cd_last_cmd == 0x02u) {
                    static int fassist_budget = 400;
                    uint32_t fe04f = xenolift_mem_read32(0x8004FE04u);
                    uint32_t fe1c_f = ((uint32_t)xenolift_mem[0x4FE1Cu]) | ((uint32_t)xenolift_mem[0x4FE1Du] << 8);
                    if (fassist_budget > 0
                        && fe04f != 0u && fe04f == cd_seek_lba
                        && fe1c_f == 1u
                        && cd_pending == 0u && cd_data_n == 0u
                        && cd_resp_n < 3u) {
                        fassist_budget--;
                        cd_resp[0] = 0x02u; cd_resp[1] = 0x01u; cd_resp[2] = 0x01u;
                        cd_resp_n = 3u; cd_resp_pos = 0u;
                        memcpy(cd_last_full, cd_resp, sizeof cd_resp);
                        cd_last_full_n = 3u;
                        cd_pending = 3u;
                        fprintf(stderr, "[cd] FIELD-SEEK assist: 3-byte SetLoc answer primed + INT1 armed (LBA %u, FE1C=%u)\n",
                                cd_seek_lba, fe1c_f);
                    }
                }
        /* R503 FLDBELL: the field pump's GetStat hang (c69, menu->Field era):
         * sched=1 read is STALLED-DEAD (FDF8=0, pend=0, arm1=0, FE1C=10,
         * last_cmd=0x01, resp_n=0) and cd_read_active stays 1, which blocks
         * the generic re-prime below forever -> the delivery bell never rings,
         * pump frozen t=46s..109s at seek 108995 with a stale 2060B sector in
         * the FIFO. Treat the drained read as done (discard leftover like the
         * proven fd-kick pattern) so the standing re-prime answers GetStat
         * and state 10 walks on. */
        {
            static int fldbell_budget = 500;
            uint32_t fdf8_b = xenolift_mem_read32(0x8004FDF8u);
            uint32_t fe1c_b = ((uint32_t)xenolift_mem[0x4FE1Cu]) | ((uint32_t)xenolift_mem[0x4FE1Du] << 8);
            if (fldbell_budget > 0
                && cd_read_active
                && fe1c_b == 0x0Au
                && cd_last_cmd == 0x01u
                && cd_resp_n == 0u && cd_resp_pos == 0u
                && cd_pending == 0u
                && cd_arm_int1_pending == 0u
                && fdf8_b == 0u) {
                fldbell_budget--;
                if (cd_data_pos < cd_data_n) {
                    fprintf(stderr, "[fldbell] R503: stale FIFO leftover %u bytes discarded (stalled-dead read)\n",
                            cd_data_n - cd_data_pos);
                    cd_data_pos = cd_data_n = 0;
                    cd_data_loaded = 0;
                }
                cd_read_active = 0;
                fprintf(stderr, "[fldbell] R503: stalled-dead read closed at seek=%u (FE1C=%u) - GetStat re-prime unlocked\n",
                        cd_seek_lba, fe1c_b);
            }
        }
        if (cd_resp_pos >= cd_resp_n && !cd_read_active
                                         && (cd_pending || cd_last_cmd)) {
            static int reprimed_budget = 100000;
            if (reprimed_budget > 0) {
                reprimed_budget--;
                /* R212: live motor state — after Stop the kernel polls
                 * GetStat waiting for the spindle-off transition; answering
                 * 0x02 (motor on) forever = the cycle-45 GetStat treadmill
                 * (last_cmd=0x13, 7+ re-primes, phase machinery done, FE1C=11). */
                cd_resp[0] = cd_read_active ? 0x22u : (cd_motor_on ? 0x02u : 0x00u); /* +bit5: reading */
                cd_resp_n = 1;
                cd_resp_pos = 0;
                if (cd_last_full_n > 1u && cd_last_cmd != 0x01u) { /* R263: multi-byte answers (GetTN/GetTD/Getloc/GetID) replay whole */
                    memcpy(cd_resp, cd_last_full, sizeof cd_resp);
                    cd_resp_n = cd_last_full_n;
                    if (cd_last_cmd != 0x10u && cd_last_cmd != 0x11u) /* live stat byte where the response starts with stat */
                        cd_resp[0] = cd_read_active ? 0x22u : (cd_motor_on ? 0x02u : 0x00u);
                }
                /* R538 [fldack]: c106 named the wedge family — every clean
                 * sector advance in the timeline follows a 3-byte answer
                 * ([02 01 01], rspop n=3); both wedge postures (FE1C=10
                 * c105, FE1C=7 c106) sat in a GetStat wait where we primed
                 * ONE byte — the game popped it and waited for the rest
                 * forever. In the field file-14 window, answer GetStat with
                 * the full ack family like every successful posture. */
                if (cd_last_cmd == 0x01u && cd_scheduled
                    && cd_seek_lba >= 108933u && cd_seek_lba <= 108995u
                    && cd_resp_n < 3u) {
                    cd_resp[0] = 0x02u; cd_resp[1] = 0x01u; cd_resp[2] = 0x01u;
                    cd_resp_n = 3u;
                    cd_resp_pos = 0u;
                }
                /* R593 [fldpause]: c161 — FE34 bump + f14node combined: the
                 * game's own callback finalized the stream (F10 held at done-
                 * form 00001524), the kernel woke (reads 5->148, re-read file
                 * 14 into landing) and ended parked on a Pause (cmd 0x09) with
                 * an EMPTY response FIFO (cmdtl #79/#80: cmd 09->09 resp=0/0,
                 * FE1C=6). Pause answers with the same 3-byte ack family in
                 * every successful posture — extend the R538 field-window
                 * reprime to cover it. */
                if (cd_last_cmd == 0x09u && cd_resp_n < 1u
                    && cd_seek_lba >= 108933u && cd_seek_lba <= 108995u) {
                    /* R594: c162 popped our R593 answer (0x22 = still-reading)
                     * but the game stayed parked — per psx-spx a Pause's
                     * completion answer must show the READING BIT CLEAR:
                     * stat 0x02 (motor on, not reading) = pause complete. */
                    cd_resp[0] = cd_motor_on ? 0x02u : 0x00u;
                    cd_resp_n = 1u;
                    cd_resp_pos = 0u;
                }
                fprintf(stderr, "[cd] re-primed response FIFO (status 0x%02X, last_cmd=0x%02X)\n",
                        cd_resp[0], cd_last_cmd);
                
                if (cd_last_cmd == 0x13u && !cd_read_active) {
                    cd_getstat_spins++;
                    /* R213: run the AT-TARGET SPIN-KICK right here — this
                     * wedge spins in the LEGACY wait, so the fd-tick block
                     * never gets to run its kick3 check. The wl block
                     * already dispatches game code from this same
                     * register-read context (proven pattern). */
                    uint32_t fe04k = xenolift_mem_read32(0x8004FE04u);
                    if (cd_getstat_spins == 32u) {
                        fprintf(stderr, "[cd] spin-kick probe: fe04k=%u seek=%u slotbits=%02X pending=%u sched=%u arm1=%u\n",
                                fe04k, cd_seek_lba, xenolift_mem[0x56788], cd_pending, cd_scheduled, cd_arm_int1_pending);
                    }
                    if (cd_getstat_spins >= 32u && fe04k != 0u
                        && fe04k == cd_seek_lba
                        && xenolift_mem[0x56788] == 0u
                        && cd_pending == 0u && cd_scheduled == 0u
                        && cd_arm_int1_pending == 0u) {
                        cd_getstat_spins = 0;
                        uint32_t ksr[32]; uint32_t kshi, kslo;
                        memcpy(ksr, r, sizeof r); kshi = hi; kslo = lo;
                        fprintf(stderr, "[cd] spin-kick: kernel polling w/ formed at-target request (FE04=%u) — dispatching h2\n", fe04k);
                        xenolift_dispatch(0x800415B4u);
                        uint32_t h2k = *(uint32_t *)(xenolift_mem + 0x564A8);
                        if (h2k >= 0x80010000u && h2k < 0x80060000u) {
                            r[4] = xenolift_mem[0x56788];
                            r[5] = 0x8005A210u;
                            fprintf(stderr, "[cd] spin-kick: dispatch h2 0x%08X (a0=%u)\n", h2k, r[4]);
                            xenolift_dispatch(h2k);
                        }
                        memcpy(r, ksr, sizeof r); hi = kshi; lo = kslo;
                    }
                }
            }
        }
        /* R360: field-stream queue-consumer drive (cycle-108 fix).
         * One consumer run per delivered sector, dispatched from this
         * poll context (spin-kick precedent: snapshot regs, set a0,
         * dispatch, restore). fn_8002AC24 (a0=1) copies the ring slot
         * to the request dest, advances the batch bookkeeping, and
         * positions the next entry — without it the ring climbs into
         * the kernel stack (cycle-108 crash). */
        if (g_fld_stream && g_fld_consume_pending) {
            g_fld_consume_pending = 0;
            uint32_t csr[32]; uint32_t cshi, cslo;
            memcpy(csr, r, sizeof r); cshi = hi; cslo = lo;
            r[4] = 1u; /* ready-signal arg per the callback decode */
            static int fldcons = 0;
            if (fldcons < 80)
                fprintf(stderr, "[fldcon] dispatching queue consumer (sector consumed; FE04=%u FDF8=%u FE08=%08X)\n",
                        xenolift_mem_read32(0x8004FE04u), xenolift_mem_read32(0x8004FDF8u),
                        xenolift_mem_read32(0x8004FE08u));
            fldcons++;
            xenolift_dispatch(0x8002AC24u);
            memcpy(r, csr, sizeof r); hi = cshi; lo = cslo;
            /* R363: FIELD COMPLETION MARKING (cycle-111 verdict: file-14
             * fully delivered — FDF8 hit 0 at LBA 108994, module code
             * confirmed landing at 0x801D4B34 — but the loader task stays
             * blocked because the entry's pending marker (+1C, the SAME
             * cell the boot-era batfin assist clears at 0x80059F14) is
             * never marked complete in the field era. Mirror the batfin
             * semantics once FDF8 reaches 0: clear +1C one-shot and let
             * the game's own batch logic advance to the next queue
             * entry / loader wake. */
            {
                static int fldfin_done;
                if (!fldfin_done && g_fld_stream
                    && xenolift_mem_read32(0x8004FDF8u) == 0u
                    && xenolift_mem_read32(0x80059F14u) != 0u) {
                    xenolift_mem_write32(0x80059F14u, 0u);
                    fldfin_done = 1;
                    fprintf(stderr, "[fldfin] field entry complete marked (+1C -> 0, FDF8=0) — batch should advance; loader wake expected\n");
                }
            }
        }
        /* R361: ring-window wrap. Cycle-109 proof: the consumer advances
         * FE08 (+0x800/sector) monotonically; on hardware the queued-
         * destination ring is a small window (movie ring = 0x3000). A
         * 61-sector stream at base 0x801E9000 would climb into the kernel
         * stack (0x801FF000+) around sector 44 and past RAM top. Wrap the
         * guest cell into a 6-slot window AFTER each consumer run (the
         * slot the consumer just read is already consumed, so reuse is
         * safe — same cadence as the movie ring). */
        if (g_fld_stream) {
            uint32_t fe08 = xenolift_mem_read32(0x8004FE08u);
            if (fe08 >= 0x801F0000u) {
                uint32_t wrapped = 0x801E9000u + ((fe08 - 0x801E9000u) % 0x3000u);
                xenolift_mem_write32(0x8004FE08u, wrapped);
                fprintf(stderr, "[fldring] FE08 wrap %08X -> %08X (6-slot window @0x801E9000)\n",
                        fe08, wrapped);
            }
        }
        return (cd_index & 3u) | 0x04u
             | ((cd_resp_pos < cd_resp_n) ? 0x20u : 0u)
             | ((cd_read_active && cd_data_pos < cd_data_n) ? 0x40u : 0u);
    case 0x1F801801: /* bank 1: response FIFO */
        if ((cd_index & 3u) == 1u && cd_resp_pos < cd_resp_n) {
            uint8_t b = cd_resp[cd_resp_pos++];
            { int popwin = g_rspop_win; g_rspop_win = popwin > 0 ? popwin - 1 : 0; /* R317/R318: decrement (was re-arm — window never closed) */
              if (popwin > 0) { popwin--;
                fprintf(stderr, "[rspop] byte#%u val=0x%02X (pos=%u n=%u last_cmd=0x%02X FE1C=%u)\n",
                        (unsigned)(cd_resp_pos), b, cd_resp_pos, cd_resp_n, cd_last_cmd,
                        xenolift_mem_read32(0x8004FE1Cu)); } }
            if (cd_resp_pos == cd_resp_n) {
                /* Last byte popped: the response is fully consumed — the
                 * kernel's own completion path (fn 0x8004BB6C) would clear
                 * the device-op flag here. Without interrupts, we do it:
                 * the event pump then exits via its slot check while the
                 * slot byte still holds the GetStat success value (2). */
                uint16_t zero = 0;
                memcpy(xenolift_mem + (0x800578A6u & 0x1FFFFFFFu), &zero, 2);
                fprintf(stderr, "[cd] response consumed — op flag cleared\n");
                /* R285: LADDER-COMPLETION SYNC DISPATCH. Cycle-31/32/33
                 * verdict: the state-11 ladder dispatcher (fn_8002AB28)
                 * NEVER runs — state 10 arms FE1C=11 and issues GetTN,
                 * but the movie module's file-queue stepper (fn_800413EC
                 * et al, states 1/2/5/0) overwrites FE1C before the next
                 * poll dispatches h2. On hardware the INT1 from the
                 * ladder commands (GetTN 0x13, 0x09, 0x08, 0x0A, 0x0E)
                 * delivers the slot-2 event within interrupt latency —
                 * the queue stepper cannot run between the response and
                 * the handler. Dispatch h2(a0=2) synchronously here when
                 * FE1C holds a ladder-pending state, exactly like the
                 * established fd-kick/spin-kick pattern. [lad2] logs it. */
                if (cd_last_cmd == 0x13u || cd_last_cmd == 0x09u
                    || cd_last_cmd == 0x08u || cd_last_cmd == 0x0Au
                    || cd_last_cmd == 0x0Eu) {
                    uint32_t fe1c = *(uint32_t *)(xenolift_mem + 0x4FE1Cu);
                    /* R286: MISS logging — ladder-cmd response consumed but
                     * FE1C holds a non-ladder state: names the exact
                     * (last_cmd, FE1C) pair when stage-4 cmd 8 completes
                     * somewhere the wedge gate misses. */
                    if (!(fe1c == 11u || fe1c == 6u || fe1c == 7u || fe1c == 9u
                          || fe1c == 12u || fe1c == 13u)) {
                        static int lad2_miss = 30;
                        if (lad2_miss-- > 0)
                            fprintf(stderr, "[lad2] ladder-cmd response SKIPPED (last_cmd=0x%02X FE1C=%u)\n",
                                    cd_last_cmd, fe1c);
                    }
                    /* R287: PENDING-STATE RESTORE (cycle-35 verdict: the
                     * [lad2] miss summary showed cmd 8 completing 2x with
                     * FE1C=10, cmd 9 9x with FE1C=0/1/10, cmds 0x0A/0x0E
                     * 16x with FE1C=0 — the ladder's pending-handoff marker
                     * in FE1C gets recycled by the file-queue state machine
                     * before the answer lands. On hardware the INT1
                     * delivers within interrupt latency so the marker
                     * survives. Each ladder command has a KNOWN completion
                     * state (GetTN 0x13 -> 11, 0x09 -> 6, 0x08 -> 7,
                     * 0x0A -> 9, 0x0E -> 12): if the marker was erased,
                     * restore it to the command's completion state, then
                     * dispatch. The ladder state handlers rewrite FE1C
                     * themselves as their first action, so the restore
                     * only bridges the handoff gap. */
                    uint32_t lad_target = 0;
                    if (cd_last_cmd == 0x13u) lad_target = 11u;
                    else if (cd_last_cmd == 0x09u) lad_target = 6u;
                    else if (cd_last_cmd == 0x08u) lad_target = 7u;
                    else if (cd_last_cmd == 0x0Au) lad_target = 9u;
                    else if (cd_last_cmd == 0x0Eu) lad_target = 12u;
                    if (lad_target != 0u && fe1c != lad_target) {
                        /* R318: the RESTORE is hardware semantics (the pending-handoff
                         * marker survives until INT latency on real HW) — it must ALWAYS
                         * run. Cycle-66 proof: the one-shot budgets (30/60) were drained
                         * by boot's ladder completions, so the movie's GetTN sync was
                         * silently skipped and state 11 NEVER dispatched ([sm11] silent,
                         * [rspop] shows the answer popped with nobody home). Cap the
                         * LOG, never the action. */
                        static int lad2_restore = 60;
                        uint32_t prev = fe1c;
                        *(uint32_t *)(xenolift_mem + 0x4FE1Cu) = lad_target;
                        fe1c = lad_target;
                        if (lad2_restore-- > 0)
                            fprintf(stderr, "[lad2] restored pending state %u for cmd 0x%02X (was %u) — dispatching\n",
                                    lad_target, cd_last_cmd, prev);
                    } else if (lad_target != 0u) {
                        static int lad2_ok = 30;
                        if (lad2_ok-- > 0)
                            fprintf(stderr, "[lad2] marker intact (last_cmd=0x%02X FE1C=%u)\n", cd_last_cmd, fe1c);
                    }
                    if (fe1c == 11u || fe1c == 6u || fe1c == 7u || fe1c == 9u
                        || fe1c == 12u || fe1c == 13u) {
                        /* R319: R318 hung the run (cycle-67, 240s kill): the
                         * always-dispatch re-entered itself — the dispatched
                         * state machine drains more responses, each consumption
                         * knocks again = infinite nesting. TWO scoping rules:
                         * (1) RE-ENTRANCY GUARD — never sync-dispatch from inside
                         * a sync-dispatch; (2) the GetTN (0x13) answer is the one
                         * the old one-shot budget silently ate ([sm11] silent,
                         * [rspop] answer popped with nobody home) — only cmd
                         * 0x13 dispatches unconditionally; the boot ladder cmds
                         * (0x08/09/0A/0E) keep the proven budgeted path. */
                        static int lad2_in_sync;
                        int do_sync = !lad2_in_sync
                                      && (cd_last_cmd == 0x13u || lad2_boot_ok-- > 0);
                        if (do_sync) {
                            static int lad2_budget = 60;
                            lad2_in_sync = 1;
                            uint32_t ksr[32]; uint32_t kshi, kslo;
                            memcpy(ksr, r, sizeof r); kshi = hi; kslo = lo;
                            if (lad2_budget-- > 0)
                                fprintf(stderr, "[lad2] ladder-completion sync h2 dispatch (last_cmd=0x%02X FE1C=%u)\n", cd_last_cmd, fe1c);
                            xenolift_dispatch(0x800415B4u); /* collector: gate struct + slot bits */
                            uint32_t h2k = *(uint32_t *)(xenolift_mem + 0x564A8u);
                            if (h2k >= 0x80010000u && h2k < 0x80060000u) {
                                r[4] = 2u;             /* completion event arg (wait-loop parity) */
                                r[5] = 0x8005A210u;    /* gate struct */
                                xenolift_dispatch(h2k);
                            }
                            memcpy(r, ksr, sizeof r); hi = kshi; lo = kslo;
                            lad2_in_sync = 0;
                        }
                    }
                }
                if ((cd_last_cmd == 0x06u || cd_last_cmd == 0x09u) && cd_read_active) {
                    /* R96: ReadN — the drive reads the sector immediately
                     * after the INT3 ack; the data-ready INT1 goes
                     * pending NOW (the kernel polls 1F801803 idx1 for
                     * it before draining the FIFO at 802 idx0). */
                    cd_pending = 1;
                    fprintf(stderr, "[cd] data-ready INT1 armed (ReadN INT3 consumed)\n");
                    g_cd_irq_force = 1;
                }
            }
            return b;
        }
        return 0;
    case 0x1F801802:
        if ((cd_index & 3u) == 0u) { /* data fifo (bank 0) */
            cd_sched_poll_release(); /* R400: field wait may poll data slot */
            if (cd_read_active) {
                /* R167: demand-reload also when EXHAUSTED (pos>=n) — the
                 * FetchCdSector (fn_800413AC -> LegacyCdSectorFetch) verify
                 * spin parked exactly here: cd_data_loaded STUCK 1 with an
                 * empty FIFO (discards emptied it without clearing the flag)
                 * -> demand never reloaded -> 22k forced-INT1 treadmill.
                 * The ch3 DMA path already reloads in this state. */
                if (!cd_data_loaded || cd_data_pos >= cd_data_n)
                    cd_data_load();
                if (cd_data_pos < cd_data_n) {
                    uint8_t b = cd_data[cd_data_pos++];
                    if (cd_data_pos == cd_data_n) {
                        /* sector fully consumed: advance and raise INT1
                         * for the next one (delivered silently — the
                         * kernel polls DRQSTS instead in our model) */
                        cd_seek_lba++;
                        cd_data_loaded = 0;
                        cd_pending = 1;
                        fprintf(stderr, "[cd] sector consumed, LBA -> %u, INT1 pending\n", cd_seek_lba);
                    }
                    return b;
                }
            }
            return 0;
        }
        if ((cd_index & 3u) == 1u) {
            cd_sched_poll_release(); /* R396 */
            return cd_pending;
        }
        return 0;
    case 0x1F801803: /* bank 1: INT flag register (psx-spx) */
        if ((cd_index & 3u) == 1u) {
            cd_sched_poll_release(); /* R396 */
            static uint32_t cd_poll803;
            {   /* R407 FIELD-FORCE CAMERA: c164 — the census proved the
             * field data-stage wait polls 803 idx1 millions of times
             * (RAM hot-blocks scored only ~267/1M; everything else is
             * MMIO). The R96/R112 force-INT1 fallback sits in THIS
             * branch and park says every gate condition holds, yet no
             * "forced data-ready INT1" line shape exists in the log and
             * rspops are byte-identical to c160/c162 — the force is
             * silent at the field stage for an unknown reason. Dump the
             * gate's own state from inside the branch while the field
             * data signature holds (inline — fld_data_sig is defined
             * after cd_read). One cycle to name the failing bit. */
                static int frc_n;
                if (frc_n < 8
                    && cd_scheduled == 0u && cd_pending == 0u
                    && cd_last_cmd == 0x06u && cd_seek_lba >= 108900u
                    && xenolift_mem_read32(0x8004FE04u) == cd_seek_lba
                    && xenolift_mem_read32(0x8004FDF8u) != 0u) {
                    fprintf(stderr, "[frc] field 803-idx1 poll #%u: read_active=%u data_loaded=%u data=%u/%u arm1=%u sched=%u seek=%u FDF8=%u poll803=%u\n",
                            (unsigned)frc_n, cd_read_active, cd_data_loaded,
                            cd_data_pos, cd_data_n, cd_arm_int1_pending,
                            cd_scheduled, cd_seek_lba,
                            xenolift_mem_read32(0x8004FDF8u), cd_poll803);
                    frc_n++;
                }
            }
            /* R408 FIELD DATA-READY POLL ASSIST (c165 verdict: the R96
             * force gate is fine — read_active=1 data_loaded=1 cmd=06 —
             * but its 4096-poll threshold never trips: the field data-
             * stage wait polls 803-idx1 only rarely ([frc] poll803=2053
             * at entry, frozen all run). Hardware truth (psx-spx): with
             * a sector buffered under an active ReadN and bytes still
             * owed, the drive raises the data-ready INT1 NOW — no poll
             * quorum. Arm instantly under the strict field signature:
             * nothing scheduled/pending, ReadN active, sector loaded,
             * seek parked in the field's disc region, bytes owed.
             * Mirrors the R96 arm byte-for-byte (cd_pending=1 +
             * g_cd_irq_force) so every downstream consumer is the
             * already-proven machinery; the poll then returns the flag
             * and the kernel's own loop drains the FIFO at 802-idx0.
             * Arming also bypasses the R96 force's pair-dispatch (its
             * pending==0 gate) = no guest dispatch from this MMIO-read
             * context (R350).
             * R409 ERA-SIZE GATE (c166 lesson): the R408 arm fired during
             * HEALTHY boot module reads (seeks 239317/109158 — poll803
             * jumped 2053->2999) and desynced the boot's file accounting:
             * the movie module faulted to the dispatcher (r4=131,
             * AbortOnGameFault, "never-loaded config render path" family)
             * and exited at 90s — no menu, no field stage. NOT harmless.
             * The field request is uniquely HUGE (FDF8=125304); every
             * boot module read is < 15000. Gate on the size: arm only
             * for field-sized reads (FDF8 > 100000), restoring the
             * proven boot trajectory bit-for-bit. */
            /* R414 PAIR-LATCH REVERT (c171): the latch BROKE the pump.
             * c171 timeline: pass 1 (6 sectors) flowed, then the guest
             * RESET its request counter back to (108933, 125304) — its
             * NORMAL per-batch-window protocol (FE04 stepper 1A98A→
             * 1A98B then back to 1A985 at fn 800415B4) — and the latch
             * refused to ring at the reset state because the pair
             * already fired. c170 flowed THROUGH the reset precisely
             * because the arm re-fired there (the "wasteful restart"
             * was the batch protocol, not a double-bell artifact).
             * LESSON: never gate a working flow on an unverified theory
             * mid-breakthrough. Original R408 semantics restored: arm
             * whenever the signature holds and nothing is armed. */
            /* R453 SCHEDULED-STALL ARM (c212/c213 verdict): field file 2
             * completed (108933-108994, 9x rate) and the game queued the
             * NEXT batch via its request queue (Setloc 108995, ReadN
             * last_cmd=02, sched=1): the drive LOADED the first sector
             * (data_n=2060, data_pos=0) but the R408 arm above can never
             * fire (needs scheduled==0, last_cmd 06/09, FE04==seek) and
             * the fd-kick refuses scheduled==1 — so the sector sits
             * undelivered forever (both cycles frozen at exactly this
             * park). Hardware truth (psx-spx): sector buffered under an
             * ACTIVE read -> data-ready INT1 NOW. Arm pending+force,
             * same flag-set as R408 (no guest dispatch, R350-safe).
             * ERA GATE (R409 lesson): FDF8==0 + seek>=108900 excludes
             * every boot/movie scheduled read (they all carry a nonzero
             * FDF8 size) — this shape only exists in the field batch. */
            if (cd_scheduled == 1u && cd_pending == 0u && cd_arm_int1_pending == 0u
                && cd_data_loaded && cd_data_pos < cd_data_n
                && cd_last_cmd == 0x02u && cd_seek_lba >= 108900u
                && xenolift_mem_read32(0x8004FDF8u) == 0u) {
                cd_pending = 1;
                g_cd_irq_force = 1;
                { static uint32_t fld2_n;
                  if (fld2_n < 24u) {
                    fprintf(stderr, "[fld2-int1] scheduled field batch INT1 armed (seek=%u data=%u/%u FDF8=0 sched=1)\n",
                            cd_seek_lba, cd_data_pos, cd_data_n);
                    fld2_n++;
                  }
                }
            }
            if (cd_scheduled == 0u && cd_pending == 0u && cd_read_active
                && cd_data_loaded && (cd_last_cmd == 0x06u || cd_last_cmd == 0x09u)
                && cd_seek_lba >= 108900u
                && xenolift_mem_read32(0x8004FE04u) == cd_seek_lba
                && xenolift_mem_read32(0x8004FDF8u) > 100000u) {
                cd_pending = 1;
                g_cd_irq_force = 1;
                { static uint32_t fldi_n;
                  if (fldi_n < 24u) {
                    fprintf(stderr, "[fld-int1] field data-ready INT1 armed at 803-idx1 poll (seek=%u FDF8=%u data=%u/%u poll803=%u)\n",
                            cd_seek_lba, xenolift_mem_read32(0x8004FDF8u),
                            cd_data_pos, cd_data_n, cd_poll803);
                    fldi_n++;
                  }
                }
            }
            /* R113: instant read-complete release. While the kernel
             * spins in its wait chain (file layer poll -> fd INT
             * processor -> collector polls this flag), a completed
             * read shows FE1C=5 + FDF8=0. The old nudge was buried in
             * the tick body, gated on cd_pending — at read-end nothing
             * is pending, so the file layer waited for the R96
             * fallback's 4096-poll delay EVERY read (Mac R112:
             * 98,980 forces, ~405M wasted polls per watchdog). The
             * file layer reads FE1C from RAM in its own loop — clear
             * it here and the wait releases on its next iteration.
             * Proven safe: this exact nudge drove all 2,048 R112
             * releases and every real decompress. */
            if (xenolift_mem_read32(0x8004FE1Cu) == 5u
                && xenolift_mem_read32(0x8004FDF8u) == 0u) {
                uint32_t zero = 0;
                memcpy(xenolift_mem + (0x8004FE1Cu & 0x1FFFFFFFu), &zero, 4);
                fprintf(stderr, "[cd] read complete (instant): FE1C 5 -> 0, releasing the file layer\n + ring: %08X %08X %08X %08X %08X %08X 77448=%08X\n",
                xenolift_mem_read32(0x800773B8u), xenolift_mem_read32(0x800773BCu),
                xenolift_mem_read32(0x800773C0u), xenolift_mem_read32(0x800773C4u),
                xenolift_mem_read32(0x800773C8u), xenolift_mem_read32(0x800773CCu),
                xenolift_mem_read32(0x80077448u));

            }
            /* R96 fallback: kernel polling the INT flag with a loaded
             * sector under ReadN but INT1 never armed (arm-ack path
             * missed) -> force it after a healthy sample of polls. */
            if (cd_pending == 0u && cd_read_active && cd_data_loaded
                && (cd_last_cmd == 0x06u || cd_last_cmd == 0x09u)
                && ++cd_poll803 > 4096u) {
                cd_pending = 1;
                fprintf(stderr, "[cd] forced data-ready INT1 after %u INT-flag polls\n", cd_poll803);
                g_cd_irq_force = 1;
                /* R112: the collector the kernel is spinning inside
                 * (fn_800415B4, called from the fd INT processor at
                 * 0x80041C98) can only convert an INT flag into a slot
                 * event via the registered handler pair. The tick gate
                 * fires at the collector's DISPATCH, which happened
                 * before this INT1 was pending (Mac R111: gate never
                 * fired, FE1C=5 stuck, spin forever). Dispatch the
                 * pair HERE so the spinning collector's next scan
                 * finds a real event and returns slot bits to the fd
                 * caller, which dispatches the real handler. The
                 * pair reads the freshly-armed flag itself and acks
                 * it when done (pending==0 guard above prevents
                 * re-entry during the pair's own register reads). */
                {
                    uint32_t sa4 = r[4], sa5 = r[5];
                    r[4] = 0; r[5] = 0;
                    xenolift_dispatch(0x800409E4u);
                    xenolift_dispatch(0x80040A4Cu);
                    r[4] = sa4; r[5] = sa5;
                }
            }
            return cd_pending;
        }
        return 0;
    }
    return 0;
}

static uint32_t io_raw_read32(uint32_t ioaddr);
static void io_raw_write32(uint32_t ioaddr, uint32_t v);
static int g_movie_live; /* R327 fwd (tentative; real def below — pump-side rdcomp assist) */
static int io_special_read(uint32_t p, uint32_t *out)
{
    /* R134: MDEC status/data-out reads served by the HLE module
     * (MDEC0 0x1F801820 status, MDEC1 0x1F801824 data). The kernel
     * does not touch these until FMV playback, so boot is inert. */
    if (p == 0x1F801820u || p == 0x1F801824u) {
        *out = hle_mdec_port_read(p);
        return 1;
    }
    if (p >= 0x1F801800u && p <= 0x1F801803u) {
        *out = cd_read(p);
        return 1;
    }
    switch (p) {
    case 0x1F801070: {
        /* R78 I_STAT HLE: the kernel's video init (fn_80044764 vtable
         * call) waits for the VBlank interrupt by polling I_STAT & its
         * enabled I_MASK; our event machinery delivers IRQs at the
         * BIOS-event layer, so raw I_STAT never asserts and the init
         * spins (R76 watchdog, r3=0x1F801074). Hardware truth: after a
         * few polls, assert every interrupt the kernel enabled in
         * I_MASK (its written mask lives in the IO mirror). The
         * kernel ACKs by writing 1s (write path clears mirror bits).
         * Safety bailout at 1M polls: assert VBlank (bit 0). */
        uint32_t mask, pend;
        memcpy(&mask, xenolift_mem + xenolift_phys(0x1F801074u), 4);
        memcpy(&pend, xenolift_mem + xenolift_phys(0x1F801070u), 4);
        g_poll_istat++;
        if (g_poll_istat > 8u) pend |= mask;
        if (g_poll_istat > 1000000u) pend |= 1u; /* VBlank bailout */
        memcpy(xenolift_mem + xenolift_phys(0x1F801070u), &pend, 4);
        *out = pend;
        return 1;
    }
    case 0x1F801074:
        /* R78 I_MASK: return the kernel's written mask (generic write
         * path stores it in the IO mirror). r3=0x1F801074 in the R76
         * watchdog — the video-init spin builds I_STAT & I_MASK here. */
        g_poll_imask++;
        memcpy(out, xenolift_mem + xenolift_phys(0x1F801074u), 4);
        return 1;
    case 0x1F801810:
        *out = gpu_read_latch; /* GPUREAD: last GetGPUInfo response */
        return 1;
    case 0x1F801814: {
        g_poll_gpu++;
        /* Bit 31 = interlace FIELD flag: toggles every half-frame (~60Hz)
         * on real hardware. The kernel's time function waits for this bit
         * to CHANGE as a coarse vertical-refresh clock — a frozen value
         * would spin it forever (watchdog in fn 0x8004B54C). Toggle every
         * 64 reads. */
        static uint32_t gpu_reads;
        gpu_reads++;
        *out = gpu_stat ^ (((gpu_reads >> 6) & 1u) << 31);
        gpu_snapshot(); /* R126: live framebuffer feed */
        return 1;
    }
    case 0x1F801054:
        g_poll_sio++;
        /* SIO status: TX ready (bit 0), no RX data. The pad driver polls
         * this; "no response" means "no controller plugged in". */
        *out = 0x0005u;
        return 1;
    case 0x1F801110:
        g_poll_t2++;
        /* timer 2: the kernel's device-op event pump reads this every
         * iteration while waiting for a card/pad/CD transfer to complete.
         * We have no interrupts, so we watch the kernel's "op pending"
         * flag here (RAM, we can read it directly) and force-complete:
         * clearing it lets the pump exit through the kernel's own path. */
        lazy_event_check();
        g_tick += 1;
        /* R327 STALLED-READ HAPPY-PATH ASSIST (relocated from the R326 zrf
         * context, which only evaluated ~12x/run — the threshold could never
         * arm). This pump is the machine's guaranteed-hot rail during the
         * freeze (~470K reads/sec, 84M over the 195s budget). Cycle-74/75
         * decode: park = WaitForCdData (fn_80041410); the manufactured sector
         * (loaded=1, pos=0) never drains because the state machine is wedged
         * busy at FE1C=6 and the state-6 arc happy path (fn_8002A894, a0==2:
         * FE1C=1, A488++, A494++, HandleCdReadyCompletion, state-2 re-dispatch)
         * never runs (park counters A488/A494=0), so the kernel data handler
         * never arms the ch3 DMA. ONE-SHOT after ~4s of the exact stall
         * signature (movie live, read active, sector loaded, ZERO bytes ever
         * drained, machine pinned at state 6): perform the happy path's CELL
         * EFFECTS — FE1C->1, A488/A494 increment, proven INT1 redelivery —
         * and let the guest's own handler pair re-run with an idle machine.
         * Normal reads drain in far under the threshold; the movie-live gate
         * excludes the boot era entirely. */
        {
            static uint32_t rd_ticks; static uint8_t rd_fired;
            if (!rd_fired) {
                if ((g_movie_live || g_field_era) && cd_read_active && cd_data_loaded
                    && cd_data_pos == 0u
                    && xenolift_mem_read32(0x8004FE1Cu) == 6u) {
                    if (++rd_ticks >= 2000000u) {
                        rd_fired = 1;
                        fprintf(stderr, "[rdcomp] stalled read @LBA %u%s: happy-path assist FIRED from pump (FE1C 6->1, A488/A494++, INT1 redelivered)\n",
                                cd_seek_lba, g_field_era ? " (FIELD-ERA retire)" : "");
                        xenolift_mem_write32(0x8004FE1Cu, 1u);
                        xenolift_mem_write32(0x8006A488u,
                                xenolift_mem_read32(0x8006A488u) + 1u);
                        xenolift_mem_write32(0x8006A494u,
                                xenolift_mem_read32(0x8006A494u) + 1u);
                        cd_pending = 1;
                        cd_force_deliver_int1("rdcomp");
                    }
                } else {
                    rd_ticks = 0;
                    /* R329: re-arm once the signature clears — the movie file
                     * is 88KB (~9 batches); each batch can wedge at state 6
                     * exactly like the first. The assist stays one-shot PER
                     * STALL, never per poll. */
                    rd_fired = 0;
                }
            }
        }
        /* R330 STATE-7 SEEK-ISSUER ASSIST. Cycle-78 proof: [sm7] shows 24+
         * state-7 entries with a0=2 (the happy-path arg) while A4A8/A4B4 stay
         * ZERO at every entry — the handler runs but its cell effects never
         * stick, and the movie read chain stopped at the batch boundary
         * (last DMA = LBA 108604; state 7 IS the next-batch seek issuer).
         * Same medicine as the proven R327 state-6 assist: sustained wedge
         * signature on the guaranteed-hot pump rail (~4s), ONE-SHOT per
         * stall with re-arm on signature break: perform the state-7 happy
         * path's CELL EFFECTS (FE1C 7->6 = data-wait, A4A8 increment = the
         * cell the game's own handler writes) + the proven data-ready INT1,
         * so the kernel's own handler chain re-runs with a machine in the
         * state that expects data. If the kernel's chain issues the next
         * batch seek through its own code, new [cd-dma] lines appear. */
        {
            static uint32_t s7_ticks; static uint8_t s7_fired;
            static uint32_t s7x_ticks; static uint8_t s7x_armed; static uint8_t s7x_fired;
            if (!s7_fired) {
                /* R337: signature widened to FE20 3 OR 4 — cycle-85 parked
                 * at 7/3 (the R335 state-6 serve shifted the wedge substate),
                 * zero assists fired for the whole 196s. Transient passes
                 * still can't reach the 2M tick threshold; only a true
                 * multi-second wedge can. */
                if (g_movie_live
                    && xenolift_mem_read32(0x8004FE1Cu) == 7u
                    && (xenolift_mem_read32(0x8004FE20u) == 4u
                        || xenolift_mem_read32(0x8004FE20u) == 3u)
                    && cd_read_active == 0
                    && xenolift_mem_read32(0x8006A4A8u) == 0u) {
                    if (++s7_ticks >= 2000000u) {
                        s7_fired = 1;
                        fprintf(stderr, "[seek7] state-7 wedge @movie batch boundary: assist FIRED (FE1C 7->6, A4A8++, INT1 redelivered)\n");
                        xenolift_mem_write32(0x8004FE1Cu, 6u);
                        xenolift_mem_write32(0x8006A4A8u, 1u);
                        cd_pending = 1;
                        cd_force_deliver_int1("seek7");
                        s7x_armed = 1; /* R333: R332 wrote =0 (backwards!) — the escalation was NEVER armed; seek7x=0 all cycle-81. Now armed for real. */
                        s7x_ticks = 0;
                    }
                } else {
                    s7_ticks = 0;
                    s7_fired = 0;
                }
            }
            /* R350: FIELD-ERA STALE-STREAM RETIREMENT. Cycle-98 proof: this
             * rail IS hot in the field era (seek7x fires here) — rdcomp
             * never fired because its signature demands cd_read_active,
             * which is 0 post-handoff (drive idle, read struct complete).
             * The stale movie stream wedges the arc machine in the
             * batch-wait states forever and the field file-14 read (LBA
             * 108933) can never start. Same cell effects as the proven R327
             * state-6 happy path (FE1C->1 idle, A488/A494++, INT1), applied
             * to the IDLE signature. Re-fires up to 8x (once per ~100K
             * ticks) if the guest re-wedges; stands down the moment FE04
             * leaves the movie range = a new file got seeded (success). */
            {
                static uint32_t fr_ticks; static uint32_t fr_fires; static uint32_t fr_last_fe04;
                if (g_field_era
                    && (xenolift_mem_read32(0x8004FE1Cu) == 6u
                        || xenolift_mem_read32(0x8004FE1Cu) == 7u
                        || xenolift_mem_read32(0x8004FE1Cu) == 10u
                        || xenolift_mem_read32(0x8004FE1Cu) == 11u)
                    && cd_read_active == 0
                    && xenolift_mem_read32(0x8004FDF8u) == 0u) {
                    uint32_t fe04 = xenolift_mem_read32(0x8004FE04u);
                    if (fe04 >= 108593u && fe04 <= 108606u) {
                        if (++fr_ticks >= 100000u && fr_fires < 8u && fr_last_fe04 != fe04) {
                            uint32_t fe1c = xenolift_mem_read32(0x8004FE1Cu);
                            fr_ticks = 0;
                            fr_fires++;
                            fr_last_fe04 = fe04;
                            xenolift_mem_write32(0x8004FE1Cu, 1u);
                            xenolift_mem_write32(0x8006A488u, xenolift_mem_read32(0x8006A488u) + 1u);
                            xenolift_mem_write32(0x8006A494u, xenolift_mem_read32(0x8006A494u) + 1u);
                            /* R351: cycle-99 HUNG — cd_force_deliver_int1 from this
                             * MMIO-read context synchronously runs the guest handler
                             * chain, which can loop forever internally in the
                             * field-era state (watchdog park never happened; bridge
                             * killed at 240s). ASYNC-ONLY now: mark the INT pending
                             * and let the proven fd-tick collector deliver it on its
                             * own safe cadence. ZERO guest dispatch from this read. */
                            cd_pending = 1;
                            fprintf(stderr, "[fldret] FIELD stale-stream retire #%u (async): FE1C %u->1, A488/A494++, INT1 left pending for collector (FE04=%u)\n",
                                    fr_fires, fe1c, fe04);
                            /* R355 FIELD FILE-14 SEED. Cycle-103 park: kernel sits INSIDE
                             * fn_80028704 (member-poll, r16=14, r17=0x801D4B34) waiting for
                             * the disc before it seeds the next file's read (fn_800288EC
                             * seeds FE04 per file — proven at boot: FE04 0->A8D2 etc.).
                             * The stale movie stream keeps the drive busy so the poll never
                             * ends. Seed the file-14 read cells DIRECTLY — same values the
                             * boot-era ladder arms with ([slot] h2 STARTER for member-5:
                             * FE04=LBA FDF8=size). R105 cd_data_load re-anchors on FE04 and
                             * the native h4 chain walks FE04++ / FDF8-=2048 per sector to
                             * the fn_8002AF5C batch-done. Cell writes only — no dispatch
                             * (LESSON L8); INT rides the async collector (L351). */
                            {
                                /* R357: SEED REVERTED (cycle-105 verdict: kernel then sat in
                                 * fn_80041410_WaitForCdData polling 0x1F801800 forever — the
                                 * ladder/CD delivery chain must be engaged, not just the cells).
                                 * Reserve for the proper delivery assist once 80028704/41410
                                 * semantics are decoded from the next stable park. */
                                static uint8_t seeded;
                                if (!seeded) {
                                    /* R359: seed + WAKE THE CD DELIVERY LAYER. Cycle-107
                                     * root cause: the R105 re-anchor inside cd_data_load
                                     * only runs when (cd_read_active && !cd_data_loaded)
                                     * or on a status poll with !cd_data_loaded — in the
                                     * field era both flags were stuck (read_active=0,
                                     * data_loaded=1 with the STALE movie sector in the
                                     * FIFO) => FE04 was re-anchored NEVER (the
                                     * "[cd] FIFO re-anchor" line never printed in any
                                     * digest). Fix: seed the cells AND force the serve
                                     * path: read_active=1, data_loaded=0 => the next
                                     * status poll runs cd_data_load, which sees
                                     * FE04=108933 != seek_lba=108605 and re-anchors.
                                     * Sector header is manufactured BCD-correct for
                                     * the seeked LBA, so the kernel's 0x80041534
                                     * header-compare passes and fn_800415B4 walks
                                     * FE04++ / FDF8-=2048 natively (L8: our globals +
                                     * guest cells only; INT rides the async collector). */
                                    seeded = 1;
                                    xenolift_mem_write32(0x8004FE04u, 108933u);
                                    xenolift_mem_write32(0x8004FDF8u, 125304u);
                                    cd_read_active = 1;
                                    cd_data_loaded = 0;
                                    fprintf(stderr, "[fldseed] FIELD file-14 seed v2: FE04=108933 FDF8=125304 + CD layer WOKEN (read_active=1 fifo->reload; R105 re-anchor will engage on next poll)\n");
                        g_fld_stream = 1; g_fld_consume_pending = 0;
                                }
                            }
                        }
                    } else {
                        if (fr_fires != 0u && fr_ticks != 0u) {
                            fprintf(stderr, "[fldret] stale range LEFT: FE04=%u (retirement freed the disc; fires=%u)\n", fe04, fr_fires);
                            fr_fires = 0u;
                        }
                        fr_ticks = 0;
                    }
                } else {
                    fr_ticks = 0;
                }
            }
            /* R332 ESCALATION (the promised fallback): if the wedge signature
             * is STILL present ~4s AFTER the cell-assist fired (kernel chain
             * did not follow through — no new batch delivery), hand the disc
             * machinery the next batch address ourselves: FE04 (guest LBA
             * cell) +1 and the HLE seek pointer likewise, then ring the same
             * data-ready bell. The stream is sequential (batch 1 = LBA
             * 108599-108604, the fake first sector was manufactured @108605);
             * if the ladder just needed the next address, it flows now. Fully
             * observable — the next digest shows the kernel's reaction. */
            /* R338: cycle-86 = seek7 FIRED (7->6 served) but the kernel then
             * parked in state 10/3 (batch-advance wait, prior sector consumed:
             * data_n=0 data_loaded=0, drive idle, FE04 unchanged). The escalation
             * was only licensed for state-7 wedges, so the batch-wait starved.
             * This mirrors MovieStrUpdatePlayback's own stall-recovery trigger:
             * any of the batch-wait states (7 seek-issuer, 10/11 collect ring),
             * drive idle, no demand, movie live, post-assist era. Same action:
             * FE04+1 (the game's GetBackLocation = saved frame-start + 1)
             * + data-ready bell. One-shot per run. */
            if (s7x_armed && !s7x_fired) {
                if (g_movie_live
                    && (xenolift_mem_read32(0x8004FE1Cu) == 7u
                        || xenolift_mem_read32(0x8004FE1Cu) == 10u
                        || xenolift_mem_read32(0x8004FE1Cu) == 11u)
                    && (xenolift_mem_read32(0x8004FE20u) == 4u
                        || xenolift_mem_read32(0x8004FE20u) == 3u)
                    && cd_read_active == 0) {
                    if (++s7x_ticks >= 100000u) { /* R333: 2M unreachable — 100K ≈ seconds of wedge */
                        s7x_fired = 1;
                        uint32_t fe04 = xenolift_mem_read32(0x8004FE04u);
                        xenolift_mem_write32(0x8004FE04u, fe04 + 1u);
                        cd_seek_lba = fe04 + 1u;
                        fprintf(stderr, "[seek7x] wedge survived cell-assist: ESCALATING (FE04 %u -> %u, seek_lba armed, INT1 redelivered)\n",
                                fe04, fe04 + 1u);
                        cd_pending = 1;
                        cd_force_deliver_int1("seek7x");
                    }
                } else {
                    /* R334: the R333 stand-down was too trigger-happy — any
                     * transient non-wedge state-7 entry (the 6->1->2->7 ladder
                     * right after the assist) permanently disarmed the
                     * escalation, so seek7x never fired even while the wedge
                     * persisted for 100+ seconds. Now a mismatch only resets
                     * the clock; the one-shot s7x_fired remains the sole
                     * terminator. */
                    s7x_ticks = 0;
                }
            }
        }
        *out = g_tick & 0xFFFFu;
        return 1;
    case 0x1F801100:
    case 0x1F801120:
    case 0x1F801130:
        /* timer counters: advance by 1 per read — real timers count ~1-2
         * ticks per read instruction, and stepping by 1 means a kernel
         * "wait until counter == N" loop can't jump over N */
        g_tick += 1;
        *out = g_tick & 0xFFFFu;
        return 1;
    }
    return 0;
}

/* kernel "device op pending" flag: set by the driver when an SIO/CD
 * transfer starts (fn at 0x8004BA28), cleared by the interrupt-driven
 * completion path (fn at 0x8004BB6C). No interrupts in static recomp,
 * so we clear it lazily when the event pump is observed waiting. */
static void dump_driver_state(const char *why);
static void lazy_event_check(void)
{
    /* Bailout only: the flag is now SET deliberately by the CD model when
     * a response arrives, and cleared by the kernel's own completion path.
     * If the kernel fails to clear it (completion never comes), force it
     * after MANY pump iterations so the boot cannot wedge. Legitimate
     * kernel waits (the cdsync timeout loop, per-frame polls) can hold
     * the flag for hundreds of function entries — 200 was killing them
     * mid-flight; 5000 keeps the bailout for true deadlocks only. */
    static uint32_t observations;
    uint32_t off = 0x800578A6u & 0x1FFFFFFFu; /* kernel RAM, in image */
    uint16_t flag;
    memcpy(&flag, xenolift_mem + off, 2);
    if (flag != 0 && !(cd_read_active && xenolift_mem_read32(0x8004FDF8u) != 0u)) {
        if (++observations > 5000u) {
            flag = 0;
            memcpy(xenolift_mem + off, &flag, 2);
            observations = 0;
            xenolift_mem[0x56788] = 2; /* slot byte: success value */
            fprintf(stderr, "[evt] cooperative tick: slot=2, op flag cleared\n");
            dump_driver_state("cooptick");
        }
    } else {
        observations = 0;
    }
}

/* writes with real behavior; returns 1 if fully handled */
/* raw IO accessors: read/write the IO district WITHOUT routing through
 * io_special_read/write (needed inside those handlers themselves to
 * avoid re-entrancy) */
static uint32_t io_raw_read32(uint32_t ioaddr)
{
    uint32_t v;
    memcpy(&v, xenolift_mem + xenolift_phys(ioaddr), 4);
    return v;
}
static void io_raw_write32(uint32_t ioaddr, uint32_t v)
{
    memcpy(xenolift_mem + xenolift_phys(ioaddr), &v, 4);
}

static int io_special_write(uint32_t p, uint32_t v)
{
    /* R134 HLE feeds - ADDITIVE: return 0 so the register-district
     * store still happens (existing behavior preserved exactly). */
    if (p >= 0x1F801C00u && p <= 0x1F801DAFu) {
        hle_spu_port_write(p, (uint16_t)(v & 0xFFFFu));
        if (++xl_spu_writes <= 3u)
            fprintf(stderr, "[hle-spu] reg write #%u 0x%08X = 0x%04X\n", xl_spu_writes, p, v & 0xFFFFu);
    }
    if (p >= 0x1F801820u && p <= 0x1F801828u) {
        hle_mdec_port_write(p, v);
        if (++xl_mdec_writes <= 3u)
            fprintf(stderr, "[hle-mdec] reg write #%u 0x%08X = 0x%08X\n", xl_mdec_writes, p, v);
    }
    if (p >= 0x1F801800u && p <= 0x1F801803u) {
        return cd_write(p, v);
    }
    if (p == 0x1F801810u) {
        gpu_gp0(v); /* R125: GP0 command port — capture VRAM blits */
        gpu_gp0_write(v); /* R135: full GP0 interpreter (dual-feed) */
        xl_gpu_writes++;
        return 1;
    }
    if (p == 0x1F801814) {
        gpu_gp1(v); /* GP1 command port */
        gpu_gp1_write(v); /* R135: GP1 interpreter */
        xl_gpu_writes++;
        return 1;
    }
    if (p == 0x1F801088u || p == 0x1F801098u || p == 0x1F8010A8u) {
        /* R255 DMA CHANNEL MAP FIX (verified psx-spx "DMA Channels"):
         *   1F80108x = DMA0 MDECin   1F80109x = DMA1 MDECout
         *   1F8010Ax = DMA2 GPU      1F8010Bx = DMA3 CDROM (handled below)
         * The old block labeled 0x1F8010A8 as "ch3 CD" and 0x1F801098 as
         * "ch2 GPU" — so the movie player's FIRST GPU linked-list send
         * (CHCR=01000401 MADR=0x80077140, R254 cycle-3) was treated as a
         * 1-word CD transfer: the display list never reached the GPU,
         * the frame counter froze = the named movie wall. Also: hardware
         * clears CHCR bit 24 on completion (old code left it set).
         * MDEC DMA0/DMA1 now route to hle_mdec (STR_PIPELINE gap 1). */
        static int dma_logs;
        int ch = (p == 0x1F801088u) ? 0 : (p == 0x1F801098u) ? 1 : 2;
        uint32_t base = 0x1F801080u + 0x10u * (uint32_t)ch;
        uint32_t madr = io_raw_read32(base) & 0x00FFFFFFu;
        uint32_t bcr  = io_raw_read32(base + 4u);
        if (v & 0x01000000u) {
            uint32_t sync = (v >> 9) & 3u;
            uint32_t bs = bcr & 0xFFFFu, ba = (bcr >> 16) & 0xFFFFu;
            if (bs == 0u) bs = 0x10000u;
            if (ba == 0u) ba = 0x10000u;
            uint32_t words = (sync == 0u) ? bs : bs * ba;
            if (words > 0x80000u) words = 0x80000u;
            uint32_t addr = 0x80000000u | (madr & 0x1FFFFCu);
            uint32_t done_words = 0, nodes = 0;
            if (ch == 2 && sync == 2u) {
                /* GPU linked list: node header = (nwords<<24)|next; walk
                 * until the end marker (bit 23 set / 0xFFFFFF). */
                uint32_t cur = addr;
                while (nodes < 0x10000u) {
                    uint32_t hdr = xenolift_mem_read32(cur);
                    uint32_t n = hdr >> 24, i;
                    for (i = 1; i <= n; i++) {
                        uint32_t w = xenolift_mem_read32(cur + 4u * i);
                        gpu_gp0(w); gpu_gp0_write(w); xl_gpu_writes++;
                    }
                    done_words += n; nodes++;
                    if (hdr & 0x00800000u) break;
                    cur = 0x80000000u | (hdr & 0x1FFFFCu);
                }
                io_raw_write32(base, 0x00FFFFFFu); /* MADR = end marker */
                if (dma_logs < 40)
                    fprintf(stderr, "[dma] GPU LIST DMA2 from %08X: %u nodes, %u words -> GP0\n", addr, nodes, done_words);
            } else if (ch == 2) {
                if (v & 1u) { /* RAM -> GPU (VRAM write image data) */
                    uint32_t i;
                    for (i = 0; i < words; i++) {
                        uint32_t w = xenolift_mem_read32(addr + 4u * i);
                        gpu_gp0(w); gpu_gp0_write(w); xl_gpu_writes++;
                    }
                } else { /* GPU -> RAM (VRAM read) via the GPUREAD latch */
                    uint32_t i;
                    for (i = 0; i < words; i++)
                        xenolift_mem_write32(addr + 4u * i, gpu_get_read_latch());
                }
                done_words = words;
                if (dma_logs < 40)
                    fprintf(stderr, "[dma] GPU DMA2 %s %u words @%08X (sync %u)\n", (v & 1u) ? "RAM->VRAM" : "VRAM->RAM", words, addr, sync);
            } else if (ch == 0) {
                hle_mdec_dma0_in(addr, bcr);
                done_words = words;
                if (dma_logs < 40)
                    fprintf(stderr, "[dma] MDEC-IN DMA0 %u words @%08X -> hle_mdec\n", words, addr);
            } else {
                hle_mdec_dma1_out(addr, bcr);
                done_words = words;
                if (dma_logs < 40)
                    fprintf(stderr, "[dma] MDEC-OUT DMA1 %u words -> @%08X from hle_mdec\n", words, addr);
            }
            dma_logs++;
            /* completion: clear start/busy (24) + force (28); DICR flag +
             * I_STAT bit 3 when the channel IRQ is enabled (b23 && b16+ch) */
            io_raw_write32(p, v & ~0x11000000u);
            {
                uint32_t dicr = io_raw_read32(0x1F8010F4u);
                if ((dicr & 0x00800000u) && (dicr & (1u << (16 + ch)))) {
                    dicr |= (1u << (24 + ch)) | 0x80000000u;
                    io_raw_write32(0x1F8010F4u, dicr);
                    uint32_t pend;
                    memcpy(&pend, xenolift_mem + xenolift_phys(0x1F801070u), 4);
                    pend |= 8u; /* IRQ3 = DMA */
                    memcpy(xenolift_mem + xenolift_phys(0x1F801070u), &pend, 4);
                }
            }
        } else {
            io_raw_write32(p, v);
        }
        return 1;
    }
    if (p == 0x1F8010C8u) {
        /* ch4 (SPU) CHCR — THE SPU UPLOAD LOADER. The kernel's async load
         * task (type 1) streams a sound bank from RAM into SPU memory
         * in 2048-byte chunks: the submit writes D4_MADR (0x1F8010C0 =
         * the RAM source buffer), D4_BCR (0x1F8010C4 = 0x10 words x 32
         * blocks), then CHCR (here) with start bit 24; a memory-control
         * handshake follows at 0x1F801014. SPU RAM is not memory-mapped
         * — model the transfer as consuming the chunk, then report
         * completion exactly the way the kernel's driver state machine
         * expects: busy bit 24 cleared (busy-polls pass), the "ready"
         * bits at 0x1F801DA6 |= 0x30 (the next chunk's arm-spin passes),
         * and SPUCNT (0x1F801DAA) bit 7 = the arrival the consumer
         * (fn_8004DD1C, kicked each heartbeat round) waits on and
         * consumes. The kernel then advances its own state machine. */
        static int spu_dma_logs;
        extern unsigned xenolift_spu_dma_count;
        if (v & 0x01000000u) { /* start */
            uint32_t madr = io_raw_read32(0x1F8010C0u);
            uint32_t bcr  = io_raw_read32(0x1F8010C4u);
            uint32_t words = bcr & 0xFFFFu, blocks = (bcr >> 16) & 0xFFFFu;
            /* R139 hardware-fidelity fix 1: BA=0 means 0x10000 blocks on
             * real hardware (psx-spx DMA spec), not 1. Unobserved so far
             * (every feed had BA!=0) but spec-wrong. */
            uint32_t bytes = words * (blocks ? blocks : 0x10000u) * 4u;
            /* R139 fix 2: the old 0x10000 cap could silently CLIP a
             * >64KB chunk and desync MADR (kernel reads it back to track
             * upload position). Hardware transfers the FULL BCR; the
             * only real limit is RAM size. The Mac's 65536B feed sat
             * exactly at the old cap - if the kernel ever asks for more
             * in one chunk, we now transfer it all. hle_spu_dma_write
             * wraps at 512KB internally (= SPU RAM wraparound). */
            if (bytes > 0x200000u) bytes = 0x200000u;
            if (spu_wr_pos + bytes > 0x80000u) spu_wr_pos = 0; /* 512KB SPU RAM */
            /* R134: feed the REAL chunk bytes into the SPU HLE module
             * (previously consume-only - the module voices now see
             * the actual uploaded sound banks). */
            if (madr >= 0x80000000u && madr + bytes <= 0x80200000u) {
                hle_spu_dma_write(spu_wr_pos,
                                  xenolift_mem + xenolift_phys(madr), bytes);
                xl_spu_dma_bytes += bytes;
                if (xl_spu_dma_bytes <= 3u * 0x800u || xl_spu_dma_bytes % 0x8000u < bytes)
                    fprintf(stderr, "[hle-spu] dma feed %uB @spu 0x%X (total %uB)\n", bytes, spu_wr_pos, xl_spu_dma_bytes);
            }
            spu_wr_pos += bytes; /* consume the chunk into sound memory */
            /* Real DMA hardware ADVANCES MADR as it transfers — the kernel
             * reads it back to track upload position. Ours must too. */
            io_raw_write32(0x1F8010C0u, madr + bytes);
            if (spu_dma_logs < 40u || spu_dma_logs % 500u == 0u) {
                uint32_t chunks, flag;
                memcpy(&chunks, xenolift_mem + (0x80058E60u-0x80000000u), 4);
                memcpy(&flag, xenolift_mem + (0x80058E24u-0x80000000u), 4);
                fprintf(stderr, "[spu-dma] #%u CHCR=%08X MADR %08X->%08X BCR=%08X %uB (spu 0x%X, chunks=%u, flag=%u)\n",
                        spu_dma_logs+1u, v, madr, madr+bytes, bcr, bytes, spu_wr_pos, chunks, flag);
            }
            spu_dma_logs++;
            { static unsigned spu_total; spu_total++;
              xenolift_spu_dma_count = spu_total; }
            io_raw_write32(p, v & ~(uint32_t)0x01000000u); /* transfer done */
            io_raw_write32(0x1F801DA6u, io_raw_read32(0x1F801DA6u) | 0x30u);
            io_raw_write32(0x1F801DAAu, io_raw_read32(0x1F801DAAu) | 0x80u);
            /* Hardware truth: the SPU DMA completion raises the DMA
             * interrupt, which delivers F0000009 to the loader — that's
             * what lets the kernel's module manager advance the job
             * (next main-bank chunk / finish / completion callback).
             * The heartbeat also fires this per round, but the DELIVERY
             * MOMENT matters: fire it exactly when the transfer ends. */
            evt_deliver_class(0xF0000009u, 0x20u);
            return 1;
        }
        io_raw_write32(p, v);
        return 1;
    }
    if (p == 0x1F8010B8u) {
        /* ch3 (CDROM) CHCR. Start (bit 24) = transfer BCR words from the
         * CD data FIFO into MADR, then report done (bit 8 set, busy bit 24
         * clear — the kernel polls both). */
        if (v & 0x01000000u) {
            uint32_t madr = io_raw_read32(0x1F8010B0u);
            uint32_t bcr = io_raw_read32(0x1F8010B4u);
            uint32_t words = bcr & 0xFFFFu, blocks = (bcr >> 16) & 0xFFFFu;
            uint32_t bytes = words * (blocks ? blocks : 1u) * 4u;
            if (bytes > 0x10000u) bytes = 0x10000u;
            /* R106: the kernel's data handler starts these DMAs in
             * pairs (12-byte BCD header to its compare buffer, then the
             * 2048 user bytes to the request dest). Serve the ACTIVE
             * request: re-anchor to the kernel's expected-LBA cell and
             * reload fresh whenever the FIFO is stale (wrong sector
             * for the current request) or exhausted (pos == n). Mid-
             * pair (header drained, seek already anchored) is left
             * untouched so the data phase continues the same sector. */
            {
                uint32_t want = xenolift_mem_read32(0x8004FE04u);
                /* R107 mid-pair guard: 0 < pos < n means the header
                 * phase of THIS sector already drained — the data phase
                 * must continue the same sector even if FE04 moved (a
                 * reload here would write header bytes into the user
                 * data slot). Only re-anchor at pair boundaries. */
                uint32_t midpair = (cd_data_pos != 0u
                                    && cd_data_pos < cd_data_n);
                if (want != 0u && !midpair && (cd_seek_lba != want
                                  || cd_data_pos >= cd_data_n
                                  || !cd_data_loaded)) {
                    if (cd_seek_lba != want)
                        fprintf(stderr, "[cd] ch3 DMA re-anchor: %u -> expected %u\n",
                                cd_seek_lba, want);
                    cd_seek_lba = want;
                    cd_data_load(); /* fresh: pos = 0, right sector */
                }
            }
            {
                uint32_t avail = cd_data_n - cd_data_pos;
                uint32_t n = (bytes < avail) ? bytes : avail;
                /* R362: duplicate-header suppression (cycle-110 wedge).
                 * At LBA 108959 the kernel re-issued its 12-byte BCD
                 * header DMA before the first arm's data phase ran; the
                 * second header drained 12 bytes out of the DATA region
                 * (fifo 24/2060) -> every following data block 12 bytes
                 * short -> the archive layer's location validation
                 * failed -> retry loop wedged the stream. A repeated
                 * header request for a fill whose header already
                 * drained serves ZERO bytes: the kernel's compare
                 * buffer still holds the correct header (this DMA just
                 * doesn't overwrite it) and the data phase continues
                 * cleanly. */
                if (g_fld_stream && bytes == 12u && cd_data_pos == 12u
                    && cd_data_n == 2060u && n == 12u) {
                    fprintf(stderr, "[fldhdr] duplicate header suppressed (LBA %u, fifo cursor kept at 12/2060)\n",
                            cd_seek_lba);
                    n = 0u;
                }
                uint32_t dst = madr & 0x1FFFFFFEu;
                if (n > 0u && dst < 0x001EF660u && dst + n > 0x001EF558u) {
                    /* R438: DMA SIDE-DOOR GUARD — this memcpy bypasses every
                     * CPU-store watcher (frclash stayed silent while the font
                     * record turned to garbage). If a staged sector write
                     * intersects the record page, NAME it here. */
                    fprintf(stderr, "[frclash] DMA %u bytes -> 0x%08X INTERSECTS RECORD PAGE (LBA %u) @t=%lds\n",
                            n, madr, cd_seek_lba,
                            (g_boot_wall_t0 ? (long)(time(NULL) - g_boot_wall_t0) : 0L));
                }
                dst = madr & 0x1FFFFFFFu;
                if (n > 0u && dst + n <= XENOLIFT_RAM_SIZE) {
                    /* R442: RECORD-PAGE SHIELD. c198-c201 proof: the heap
                     * carves DOWNWARD and the staging region ends exactly at
                     * the record base 0x801EF558; the linear sector fill's
                     * last sector(s) overshoot the region top and stomp the
                     * live font record's first bytes — the root of every
                     * loading-screen crash. Divert intersecting bytes to a
                     * shadow so the record stays pristine; the staging loses
                     * only its top overflow (file-tail bytes). */
                    static uint8_t shadow_rec[0x4000];
                    /* R443 MASK FIX (agent): dst is MEMORY-INDEX space (addr-0x80000000;
                     * 0x801EF558 -> 0x1EF558). R442 compared index-space lo/hi vs 32-bit
                     * bounds -> NEVER matched -> shield was dead code while [frclash]
                     * (index-space, correct) fired at 0x801EF3D8. */
                    uint32_t rec_lo = 0x001EF558u, rec_hi = 0x001F34B4u;
                    uint32_t lo = dst, hi = dst + n;
                    /* R446 SCOPE FIX: clip ONLY fills CROSSING the record BASE
                     * (lo < rec_lo && hi > rec_lo) - the staging-top overshoot that
                     * caused the historical crash. Fills INSIDE the span (lo >= rec_lo)
                     * are the game's own legitimate file loads (file 3 re-read
                     * 0x801F1154, file 18 0x801EFC94, field sectors) - let them pass. */
                    if (lo < rec_lo && hi > rec_lo) {
                        uint32_t cut_lo = (lo > rec_lo) ? lo : rec_lo;
                        uint32_t cut_hi = (hi < rec_hi) ? hi : rec_hi;
                        uint32_t lead = cut_lo - lo;
                        uint32_t tail = (hi > cut_hi) ? (hi - cut_hi) : 0u;
                        if (lead > 0u)
                            memcpy(xenolift_mem + lo, cd_data + cd_data_pos, lead);
                        if (cut_lo - rec_lo + (cut_hi - cut_lo) <= sizeof shadow_rec)
                            memcpy(shadow_rec + (cut_lo - rec_lo),
                                   cd_data + cd_data_pos + lead, cut_hi - cut_lo);
                        if (tail > 0u)
                            memcpy(xenolift_mem + cut_hi,
                                   cd_data + cd_data_pos + lead + (cut_hi - cut_lo), tail);
                        fprintf(stderr, "[dmashield] LBA %u fill %08X..%08X clipped at record page: %u lead + %u tail bytes written, %u diverted to shadow\n",
                                cd_seek_lba, lo, hi, lead, tail, cut_hi - cut_lo);
                        cd_data_pos += n;
                    } else {
                        memcpy(xenolift_mem + dst, cd_data + cd_data_pos, n);
                        cd_data_pos += n;
                    }
                }
                { /* R591 [f15stream] ready-count mimic: c159 — the stream callback (fn
                         * 8002B2F0) gates on FE34 ("sectors ready"): <=0 -> pause/retry, never
                         * advancing the ring write pointer (FE08) or the stream LBA. Every
                         * stream-era sector landed at the SAME ring slot 8007F2F8, FE34 frozen
                         * at 0, seek frozen at 108996. Bump FE34 per ring-zone sector so the
                         * game's own callback walks. */
                        uint32_t dst_now = (uint32_t)(madr); /* R592: madr is the DMA dest (c160: dst was wrong local — gate never matched) */
                        if (cd_seek_lba >= 108995u && dst_now >= 0x8007E000u && dst_now < 0x80080000u) {
                            uint32_t fe34 = xenolift_mem_read32(0x8004FE34u);
                            /* R604 DISARMED -> log-only: c171 CBCALL receipts
                             * prove the FILE-CB copies sectors natively when
                             * FE34=0 (install run #38-42, FDF8 counting down).
                             * FE34>0 at its entry = skip-copy + premature finalize
                             * jump — the R591 bump was the consumer killer. The
                             * game owns FE34 from now on. */
                            { static int fe34_n;
                              if (fe34_n < 20) { fe34_n++;
                                fprintf(stderr, "[f15stream] R604: ring-zone sector served (FE34=%u — NO bump, assist disarmed) @0x%08X seek=%u\n",
                                        fe34, dst_now, cd_seek_lba); } }
                        }
                    }
                    fprintf(stderr, "[cd-dma] CHCR=%08X %u/%u bytes -> 0x%08X (LBA %u, fifo %u/%u, FDF8=%u)\n",
                        v, n, bytes, madr, cd_seek_lba, cd_data_pos, cd_data_n,
                        xenolift_mem_read32(0x8004FDF8u));
                /* R508 CB-DMA camera: c74 verdict — the on-change watcher saw
                 * ZERO guest writes to the callback cell 0x80059F08 all run,
                 * yet cbheal kept finding it empty again. Only DMA blasts memory
                 * without tripping the SW watcher. The 12B sector-header DMA
                 * targets 0x80059EF8 every sector; the 2048B data DMAs target
                 * the ring. Log every DMA that touches the read-struct region
                 * [0x80059EF8, 0x80059F20) with the pre-write callback value
                 * and whether the blast covers 0x80059F08 (+0x10). */
                if (madr < 0x80059F20u && (madr + bytes) > 0x80059EF8u) {
                    static uint32_t cbdma_n;
                    if (cbdma_n < 40u) {
                        cbdma_n++;
                        fprintf(stderr, "[cbdma] R508: DMA into read-struct region dst=0x%08X len=%u covers+10=%u | cell+10=0x%08X pre-blast\n",
                                madr, bytes,
                                (madr <= 0x80059F08u && (madr + bytes) > 0x80059F08u) ? 1u : 0u,
                                xenolift_mem_read32(0x80059F08u));
                    }
                }
                if (cd_data_pos >= cd_data_n) {
                    if (g_fld_stream) g_fld_consume_pending = 1; /* R360: one consumer run per delivered sector */
                    /* Sector consumed. R110: on real hardware ReadN
                     * does NOT stop at the request size — the drive
                     * keeps delivering sectors and the fd module
                     * drains-and-discards the excess until it issues
                     * Pause/Stop (cd_read_active = 0). The old
                     * "FDF8 > 2048" stop left the collector spinning
                     * for a next INT1 that never came (Mac R109:
                     * FDF8=0 FE1C=5, spin inside fn_800415B4 called
                     * from the fd INT processor at 0x80041C98). Feed
                     * while the read is active; Pause ends it. */
                    cd_data_loaded = 0;
                    /* R445: [fldsec] per-sector delivery clock. c204 verdict: crash
                     * DEAD (0 faults), field file 1 fully delivered, loading screen
                     * drawing - but sector rate ~1/1.9s cannot finish field file 2
                     * within the 210s budget. Measure per-sector latency to tune the
                     * pump. Index-space only (dst < 0x200000), no tokens in banner. */
                    {
                        static uint32_t fldsec_n;
                        static int fldsec_prev_n = -1;
                        extern int xenolift_ring_n; /* global guest-dispatch counter (R81) */
                        long fel = (g_boot_wall_t0 ? (long)(time(NULL) - g_boot_wall_t0) : 0);
                        fldsec_n++; g_fldsec_total++;
                        if (fldsec_n <= 4u || (fldsec_n % 8u) == 0u)
                            fprintf(stderr, "[fldsec] #%u LBA %u consumed @t=%lds fifo=%u/%u ring_n=%d dring=%d\n",
                                    fldsec_n, cd_seek_lba, fel, cd_data_pos, cd_data_n,
                                    xenolift_ring_n,
                                    fldsec_prev_n < 0 ? -1 : (xenolift_ring_n - fldsec_prev_n));
                        fldsec_prev_n = xenolift_ring_n;
                    }
                    cd_seek_lba++; /* next sector in the stream */
                    if (cd_read_active) {
                        cd_pending = 1; /* INT1: next sector ready */
                        uint16_t one = 1;
                        memcpy(xenolift_mem + (0x800578A6u & 0x1FFFFFFFu), &one, 2);
                        fprintf(stderr, "[cd] INT1: next sector event flagged (LBA %u next)\n", cd_seek_lba);
                    } else {
                        fprintf(stderr, "[cd] stream stop: bytes=%u FDF8=%u (no next arm)\n",
                                bytes, xenolift_mem_read32(0x8004FDF8u));
                    }
                } else if (bytes > 12u) {
                    /* R109: partial DATA drain — the FIFO still holds
                     * this sector's remainder. On real hardware the
                     * drive keeps the data-ready INT pending while
                     * the FIFO is non-empty; the kernel's next handler
                     * run drains the remainder into its scratch
                     * buffer (observed MADR 0x800596F8) and then
                     * completes the request (full-sector subtract ->
                     * notify -> FE1C release). Without this arm the
                     * tail sector of every request deadlocks the
                     * file layer's completion poll (Mac R108:
                     * FDF8=1480 stuck, 568 bytes left, watchdog at
                     * 0x800413BC). */
                    cd_pending = 1;
                    uint16_t one = 1;
                    memcpy(xenolift_mem + (0x800578A6u & 0x1FFFFFFFu), &one, 2);
                    fprintf(stderr, "[cd] INT1 re-armed: FIFO remainder %u bytes (LBA %u)\n",
                            cd_data_n - cd_data_pos, cd_seek_lba);
                }
            }
            io_raw_write32(0x1F8010B8u, 0x00000000u); /* R217 PSXSPX-faithful: busy+trigger auto-clear on completion; bit 8 = chopping-enable, never set in normal CD mode */
            return 1;
        }
        io_raw_write32(p, v);
        return 1;
    }
    return 0;
}

uint32_t xenolift_phys(uint32_t a)
{
    uint32_t p = a & 0x1FFFFFFFu;
    if (p < XENOLIFT_RAM_SIZE) {
        return p;
    }
    if (p >= XENOLIFT_IO_BASE && p < XENOLIFT_IO_BASE + XENOLIFT_IO_SIZE) {
        return XENOLIFT_RAM_SIZE + (p - XENOLIFT_IO_BASE);
    }
    xenolift_io_fault(a);
    return 0u;
}

static uint32_t io_phys(uint32_t off)
{
    return XENOLIFT_IO_BASE + (off - XENOLIFT_RAM_SIZE);
}

/* R200: LZSS HLE decoder — faithful port of lzss_ref.py (reference
 * decoder verified against the Mac's captured decompress dumps). The
 * kernel format (fn_80032EB4 semantics): u32le expanded size, then
 * groups of [ctrl][8 tokens], LSB-first: bit SET = match (b1,b2:
 * off=((b2&0xF)<<8)|b1, len=(b2>>4)+3, forward byte-copy, overlap
 * allowed), bit CLEAR = literal. Stop at expanded size (per group). */
static int xenolift_lzss_hle(uint32_t src, uint32_t dst, uint32_t size)
{
    /* byte-wise via the RAM map; source window cap 0x20000 for safety */
    uint32_t pos = 0, i = src + 4, lim = src + 0x20000u;
    if (size == 0u || size > 0x800000u) return -1;
    while (pos < size) {
        if (i >= lim) return -1;
        uint32_t ctrl = xenolift_mem_read8(i); i++;
        for (int t = 0; t < 8 && pos < size; t++) {
            if (ctrl & 1u) {
                if (i + 1 >= lim) return -1;
                uint32_t b1 = xenolift_mem_read8(i), b2 = xenolift_mem_read8(i + 1); i += 2;
                uint32_t off = ((b2 & 0xFu) << 8) | b1;
                uint32_t ln = (b2 >> 4) + 3;
                uint32_t sp = pos - off;
                if (sp > pos) return -1; /* before block = corrupt */
                for (uint32_t k = 0; k < ln && pos < size; k++) {
                    xenolift_mem_write8(dst + pos, xenolift_mem_read8(dst + sp + k));
                    pos++;
                }
            } else {
                if (i >= lim) return -1;
                xenolift_mem_write8(dst + pos, xenolift_mem_read8(i));
                pos++; i++;
            }
            ctrl >>= 1;
        }
    }
    return (int)pos;
}

/* R192 lzss-guard state */
static volatile int lzss_armed = 0;
static int lzss_over_n = 0;
static uint32_t lzss_last_a = 0;
static uint32_t lzss_in_end = 0;   /* R195: src + declared compressed len (stream word0) */
static uint32_t lzss_exit_target = 0; /* R198: dst + expanded (word0) — the LZSS exit address, computed at entry */
static int lzss_heal_n = 0;
static uint32_t lzss_fake_zero_addr = 0; /* R202: one-shot — the core entry LW of src returns 0 once */
static uint32_t lzss_hle_src_saved = 0;
static int lzss_inpast_n = 0;      /* R195: token reads past the stream end (LOG-ONLY) */

static int g_r402_in_hook; /* R402 recursion guard (see RAM-POLL RELEASE below) */
uint32_t xenolift_mem_read32(uint32_t a)
{
    /* R209: SELF-DRIVING VBLANK COUNTER. WaitForVerticalRetrace
     * (fn_8004B54C, VSync(-1)) polls kernel cell 0x80057848 waiting for
     * it to ADVANCE (BIOS vblank IRQ increments it per frame on real
     * HW). The R205 heartbeat increment only fires on park/kick rounds —
     * cycles 41/42 parked INSIDE the VSync wait with the counter frozen
     * (the wait chain never reaches those rounds). Make time move from
     * the wait's own polling: every 64th read of the cell, +1 frame. */
    if (a == 0x80057848u) {
        static uint32_t vb_polls;
        if (++vb_polls >= 64u) {
            vb_polls = 0;
            uint32_t vb = *(uint32_t *)(xenolift_mem + 0x57848);
            *(uint32_t *)(xenolift_mem + 0x57848) = vb + 1u;
        }
    }
    /* R402 RAM-POLL RELEASE (c159): the field Setloc wait polls NO disc
     * MMIO register at all — the kernel file layer reads the state cell
     * 0x8004FE1C from RAM in its own spin loop (R113 precedent, the
     * "file layer reads FE1C from RAM" idiom). c159 proved every MMIO
     * release branch silent while the full signature held at park: the
     * delivery must happen AT the RAM poll itself. Same gate, same body,
     * proven-safe delivery (the c155 menu-frame assist delivered this
     * exact answer + INT1-armed and the chain advanced to the ReadN).
     * Boot safety: boot reply-waits resolve in a handful of polls via the
     * event machinery; if a boot delivery shifts to this earlier hook,
     * the delivery body is identical — the determinism counters tell us
     * next digest. Guard: cd_sched_poll_release's own gate re-reads FE1C
     * through this hook — suppress re-entry. */
    /* R633 (c204 REVISED): who READS the state/position cells DURING THE
     * PARK? c203's cap burned out on 14 boot-era reads (all cells zero) -
     * era-blind cap AGAIN. Gate receipts to the park era (t>=15s) and add
     * FE04 (the drag-back cell the PA/stepper math compares against). */
    /* R635 (c205): heal worked - R628 fired at the REAL position (FE04=108989,
     * first time), sched cleared, game's math read FE04 at the park. But the
     * stepper still parks at F0C=14 and no member-15 read issues. Unknown =
     * WHO (if anyone) polls the request cells during the park. Widen the
     * park-era camera to the full read-struct family so the next digest names
     * the park waiter's reads - or proves nobody reads (=> waiter is a task
     * scheduler event, not a cell). */
    if ((a == 0x800592C0u || a == 0x800592D0u || a == 0x8005FAECu || a == 0x80010000u
         || a == 0x8004FE04u || a == 0x8004FE08u || a == 0x8004FE34u
         || a == 0x8004FE1Cu || a == 0x80059EFCu || a == 0x80059F08u
         || a == 0x8004FDE4u) && (time(NULL) - g_boot_wall_t0) >= 25) {
        static int r633n;
        if (r633n < 20) { r633n++;
            fprintf(stderr, "[cd] R633 mountcell READ #%u: cell=%08X | 92C0=%08X 92D0=%08X 92BC=%08X idx=%08X FE04=%08X t=%lds\n",
                    r633n, a,
                    xenolift_mem_read32(0x800592C0u), xenolift_mem_read32(0x800592D0u),
                    xenolift_mem_read32(0x800592BCu), xenolift_mem_read32(0x8005FAECu),
                    xenolift_mem_read32(0x8004FE04u), time(NULL) - g_boot_wall_t0);
        }
    }
    if (a == 0x8004FE1Cu && cd_scheduled && !g_r402_in_hook) {
        g_r402_in_hook = 1;
        cd_sched_poll_release();
        if (!cd_scheduled) { /* delivered — name the context */
            static int r402_logs;
            if (r402_logs++ < 24)
                fprintf(stderr, "[cd] INT3 delivered at FE1C RAM-poll (file-layer wait, cmd 0x%02X FDF8=%u)\n",
                        cd_last_cmd, xenolift_mem_read32(0x8004FDF8u));
        }
        g_r402_in_hook = 0;
    }
    /* R411 FIELD PUMP RE-ARM (c168): the R408 arm STARTED the field
     * data pump — 6 sectors flowed natively (LBA 108933-108938, FDF8
     * 125304->115064, DMA into the field dest ring) — then the queue
     * stepper stopped mid-read: the [fldpump] timeline froze solid at
     * sector 7 (t=60s..195s, EVERY cell identical) with the drive
     * side perfect (act=1 loaded=1 data=0/2060 pend=0 sched=0) —
     * the stepper consumed the first data-ready bell, advanced its
     * batch, and now waits for the NEXT sector's bell. Hardware
     * truth (psx-spx): the drive raises INT1 PER DELIVERED SECTOR
     * under ReadN, not once per request. The FE1C RAM-poll is the one
     * context proven live in this era (R402 deliveries landed here,
     * budgeted logs). While the mid-read stall signature holds, ring
     * the next bell: identical R96/R408 arming bits (cd_pending=1 +
     * g_cd_irq_force=1), zero guest dispatch (R350) — the guest's own
     * queue does the consuming. BOOT-STRICT band: seek 108900-109150
     * excludes every healthy boot read (239317, 109158+); the c166
     * lesson — an extra bell in a healthy flow desyncs it — is why
     * pend/sched must both be idle AND the band is narrow. FDF8 gate
     * 1..125304 = strictly mid-field-read. */
    if (a == 0x8004FE1Cu && cd_scheduled == 0u && cd_pending == 0u
        && cd_read_active && cd_data_loaded
        && (cd_last_cmd == 0x06u || cd_last_cmd == 0x09u)
        && cd_seek_lba >= 108900u && cd_seek_lba < 109150u
        && xenolift_mem_read32(0x8004FE04u) == cd_seek_lba) {
        uint32_t r411_fdf8 = xenolift_mem_read32(0x8004FDF8u);
        /* R412: strictly MID-read — the initial FDF8==125304 state is the
         * R408 arm's job; c169 showed a double-bell there made the guest
         * restart the whole request once (two re-arm passes 108933-108939). */
        if (r411_fdf8 != 0u && r411_fdf8 < 125304u) {
            cd_pending = 1;
            g_cd_irq_force = 1;
            /* R415: budget 24->96 — c172: the budget exhausted at sector
             * 16 of file 1 and the native path took over at a SLOWER pace
             * (pump ran out of clock with file 2 at 6/15 sectors). The
             * assisted bell path is the faster one; 96 covers file 1 (62
             * sectors) + file 2 (~15) end to end. Flow unchanged — budget
             * only; c171 lesson respected (no gate changes to working
             * flow). */
            {   static int r411_n;
                if (r411_n++ < 96u)
                    fprintf(stderr, "[fld-rearm] sector bell re-armed at FE1C poll (seek=%u FDF8=%u pend=%u)\n",
                            cd_seek_lba, r411_fdf8, cd_pending);
            }
        }
    }
    {   /* R403 fld-data camera: RAM-cell polls during the data-stage wait */
        static uint32_t ram_seen;
        if ((a == 0x800578A6u || a == 0x8004FE1Cu || a == 0x8004FDF8u)
            && fld_n < 96u && !(ram_seen & (1u << ((a >> 2) & 31u)))
            && fld_data_sig()) {
            ram_seen |= 1u << ((a >> 2) & 31u);
            fprintf(stderr, "[cd] fld-data RAM-poll 0x%08X val=0x%08X\n",
                    a, *(uint32_t *)(xenolift_mem + (a & 0x7FFFFFu)));
            fld_n++;
        }
    }
    {   /* R406 HOT-READ CENSUS (c163): the field data-stage wait reads
         * NOTHING we watch — one 803-idx1 ack, zero MMIO after, zero
         * probes of FDF8/FE1C/578A6, and the vblank counter only crawls
         * a few frames per run => the wait is a pure RAM spin on an
         * UNNAMED cell. Stop guessing: while the field signature holds,
         * count reads per 256-byte block over the whole low RAM window
         * (0x80010000-0x801FFFFF) and report the hottest blocks every
         * 1M reads (counters reset each report = per-window hot spots).
         * Recursion-safe: fld_data_sig guards itself (R404), so the
         * sig's own FE04/FDF8 reads don't count. */
        static uint32_t fh_n;
        static uint16_t fh[0x1F0];
        if (fld_data_sig()) {
            if (a >= 0x80010000u && a < 0x80200000u)
                fh[(a - 0x80010000u) >> 8]++;
            if (++fh_n >= 1048576u) {
                fh_n = 0;
                uint32_t top_i[4] = {0, 0, 0, 0};
                for (uint32_t i = 0; i < 0x1F0u; i++) {
                    for (int k = 3; k >= 0; k--) {
                        if (fh[i] > fh[top_i[k]]) {
                            if (k < 3) top_i[k + 1] = top_i[k];
                            top_i[k] = i;
                        } else break;
                    }
                }
                fprintf(stderr, "[fld-hot] 1M reads: %08X=%u %08X=%u %08X=%u %08X=%u\n",
                        0x80010000u + (top_i[0] << 8), fh[top_i[0]],
                        0x80010000u + (top_i[1] << 8), fh[top_i[1]],
                        0x80010000u + (top_i[2] << 8), fh[top_i[2]],
                        0x80010000u + (top_i[3] << 8), fh[top_i[3]]);
                for (uint32_t i = 0; i < 0x1F0u; i++) fh[i] = 0;
            }
        }
    }
    if (lzss_fake_zero_addr && a == lzss_fake_zero_addr) {
        /* R202: HLE-exit one-shot. The core's entry reads LW(src) as the
         * expanded size; after our native decode we feed 0 so its math
         * lands r15 = 0 + r5 == r5 = the final position -> immediate
         * exit at the first group check. No memory cell borrowed (the
         * cycle-35 read-struct cell got a CD header DMA'd into it
         * mid-flight = timing-dependent garbage). Self-clearing. */
        lzss_fake_zero_addr = 0;
        return 0;
    }
    /* R193: lzss-guard reads — the cycle-26 fault moved to a READ walk
     * (0x802408CF, LZSS back-reference history past RAM). Suppress and
     * return zero so the walk logs instead of halting. */
    if (lzss_armed && lzss_in_end && a >= lzss_in_end && a < 0x80200000u) {
        /* R195: input-overrun — token byte read PAST the stream's declared end.
         * LOG-ONLY (no behavior change): names the runaway's fuel source. */
        if (lzss_inpast_n < 8 && !g_in_park) fprintf(stderr, "[lzss-inpast] token read past input end (end=0x%08X) @0x%08X\n", lzss_in_end, a); /* R367: park-time host reads must not fire decode hooks */
        lzss_inpast_n++;
    }
    if (lzss_armed && a >= 0x80200000u) {
        if (lzss_over_n < 8) {
            fprintf(stderr, "[lzss-guard-r] suppressed read @0x%08X -> 0\n", a);
        }
        lzss_over_n++;
        if ((lzss_over_n & 0xFFF) == 0) {
            fprintf(stderr, "[lzss-runaway] %d ops suppressed, read frontier 0x%08X\n", lzss_over_n, a);
        }
        return 0;
    }
    /* Kernel system-time cell 0x80058960: on real hardware the timer
     * IRQ handler increments it and fn_8004B694 sleeps by polling it
     * ("wait until time >= target"). No timer IRQs exist here, so each
     * read advances the cell by one tick — every bounded sleep then
     * terminates naturally after (target - now) polls. */
    {
        uint32_t __p = xenolift_phys(a);
        if (__p == 0x58960u) {
            uint32_t __v;
            memcpy(&__v, xenolift_mem + __p, 4);
            __v += 1u;
            memcpy(xenolift_mem + __p, &__v, 4);
            static int __told;
            if (!__told) {
                __told = 1;
                fprintf(stderr, "[time] system-time cell 0x80058960 advancing (simulated timer ticks)\n");
            }
        }
    }
    uint32_t off = xenolift_phys(a);
    uint32_t v, tmp;
    if (off >= XENOLIFT_RAM_SIZE && io_special_read(io_phys(off), &tmp)) {
        io_log(io_phys(off), 0, tmp);
        return tmp;
    }
    memcpy(&v, xenolift_mem + off, 4);
    if (off >= XENOLIFT_RAM_SIZE) {
        io_log(io_phys(off), 0, v);
    }
    return v;
}

/* ---- BIOS event system (B0 gates 07h/08h/0Ch/0Dh) ----
 * The game registers event callbacks via OpenEvent/EnableEvent; the
 * kernel delivers them when hardware events fire (VBlank F0000001,
 * GPU F0000002, CD F0000009, SIO/periodic F200000x, ...). Previously
 * these gates were capture-only stubs returning handle 0 — the game's
 * boot registrations were silently dropped. Real table now; handles
 * are 1..MAX_EVENTS (never 0). */
#define MAX_EVENTS 64
static struct {
    uint32_t cls, spec, mode, handler;
    uint8_t in_use, enabled, fired;
} evt_tab[MAX_EVENTS];

static uint32_t evt_open(uint32_t cls, uint32_t spec, uint32_t mode, uint32_t handler)
{
    for (int i = 0; i < MAX_EVENTS; i++) {
        if (!evt_tab[i].in_use) {
            evt_tab[i].cls = cls; evt_tab[i].spec = spec;
            evt_tab[i].mode = mode; evt_tab[i].handler = handler;
            evt_tab[i].enabled = 0; evt_tab[i].in_use = 1; evt_tab[i].fired = 0;
            return (uint32_t)i + 1;
        }
    }
    return 0;
}

/* deliver to every ENABLED event of this class (any spec) */
static void evt_deliver_class(uint32_t cls, uint32_t spec)
{
    for (int i = 0; i < MAX_EVENTS; i++) {
        if (evt_tab[i].in_use && evt_tab[i].enabled && evt_tab[i].cls == cls) {
            evt_tab[i].fired = 1; /* events with null handlers wake waiters only */
            if (evt_tab[i].handler >= 0x80010000u && evt_tab[i].handler < 0x80060000u) {
                fprintf(stderr, "[evt] DELIVER class=0x%08X spec=0x%08X -> handler 0x%08X\n",
                        cls, spec, evt_tab[i].handler);
                /* R196: full register-file + hi/lo save/restore — the
                 * cycle-27/28 runaway root cause. The sound driver's
                 * event handler (0x8003C020) ran mid-decompression and
                 * trampled the LZSS core's live t7 (r15 = the exit
                 * target dst+expanded), t8/t9/t6 — the decompressor's
                 * end-of-output compare could never fire again, so it
                 * produced forever (watchdog, linear byte march past
                 * the RAM ceiling). On real HW this handler runs as a
                 * full interrupt with complete context save. */
                uint32_t sr[32]; uint32_t shi, slo;
                memcpy(sr, r, sizeof r); shi = hi; slo = lo;
                r[4] = cls; r[5] = spec;
                xenolift_dispatch(evt_tab[i].handler);
                memcpy(r, sr, sizeof r); hi = shi; lo = slo;
            }
        }
    }
}

/* Synthetic recurring-hardware heartbeat. The game polls its task
 * queue busy flag at 0x8006957C (bit 4, fn 0x8003BDFC) in a tight
 * loop; on real hardware the queue is processed from periodic event
 * callbacks (VBlank / SIO classes) at ~60 Hz. After many polls we
 * deliver one synthetic round to all enabled F0000001/F2000002
 * handlers — the spin reloads every register each iteration, so
 * resuming mid-loop after the handler dispatch is safe. The handlers
 * themselves carry re-entrancy guards (busy bit 0x40). */
static uint32_t g_vb_polls;
/* Queue snapshot: the task queue is a circular buffer of 20-byte
 * nodes in a table pointed to by cell 0x80059458; head index (u16)
 * at 0x80059510, tail (u16) at 0x800594F4, state flags (u16) at
 * 0x8005957C (bit 4 = busy), frame counter (u32) at 0x80059504.
 * Photograph once per heartbeat round: shows whether the queue
 * advances and names the head node's callback = the stuck task. */
static void vb_topup_60hz(void); /* R316: fwd decl (defined below the kick helpers) */
static void heartbeat_diag(void)
{
    /* R205: VBLANK COUNTER. The kernel's WaitForVerticalRetrace
     * (fn_8004B54C, called from LegacyCdDataWait fn_8004299C) does NOT
     * poll GPUSTAT — it waits for the kernel's vblank counter cell
     * 0x80057848 to ADVANCE. On real HW the BIOS vblank IRQ (RC3/IRQ0,
     * the ChangeClearRCnt(rc=3) channel — the R145 audit's #1 risk,
     * now confirmed) increments it once per frame. Our HLE never did,
     * so VSync(-1)/VSync(N) spins forever (cycle-38 Mac park). Each
     * heartbeat round = one emulated frame: increment the cell. */
    {
        static int vb_logged;
        uint32_t vb = xenolift_mem_read32(0x80057848u);
        xenolift_mem_write32(0x80057848u, vb + 1u);
        if (vb_logged < 3 || ((vb & 0x3FFu) == 0x3FFu)) {
            fprintf(stderr, "[vsync] vblank counter 0x80057848: %u -> %u (frame emulated)\n", vb, vb + 1u);
            vb_logged++;
        }
    }
    vb_topup_60hz(); /* R316 */
    static long rn = 0;
    long n = ++rn;
    if (n <= 40 || n % 1000 == 0) {
        uint16_t st, h, t; uint32_t fr, tbl, cb = 0, n4 = 0;
        memcpy(&st, xenolift_mem + 0x5957Cu, 2);
        memcpy(&h,  xenolift_mem + 0x59510u, 2);
        memcpy(&t,  xenolift_mem + 0x594F4u, 2);
        memcpy(&fr, xenolift_mem + 0x59504u, 4);
        memcpy(&tbl, xenolift_mem + 0x59458u, 4);
        if (h < 64u && tbl >= 0x80000000u && tbl < 0x80200000u) {
            uint32_t p = (tbl - 0x80000000u) + (uint32_t)h * 20u;
            if (p + 8u < XENOLIFT_RAM_SIZE) {
                memcpy(&cb, xenolift_mem + p, 4);
                memcpy(&n4, xenolift_mem + p + 4u, 4);
            }
        }
        fprintf(stderr, "[q] #%ld fr=%u st=%04X h=%u t=%u node_cb=0x%08X node4=0x%08X\n",
                n, fr, st, h, t, cb, n4);
        /* full head node: +0 type, +4 ctx, +8/+12 args, +16 completion cb */
        if (h < 64u && tbl >= 0x80000000u && tbl < 0x80200000u) {
            uint32_t p = (tbl - 0x80000000u) + (uint32_t)h * 20u;
            if (p + 20u < XENOLIFT_RAM_SIZE) {
                uint32_t w0, w8, w12, w16;
                memcpy(&w0, xenolift_mem + p, 4);
                memcpy(&w8, xenolift_mem + p + 8u, 4);
                memcpy(&w12, xenolift_mem + p + 12u, 4);
                memcpy(&w16, xenolift_mem + p + 16u, 4);
                fprintf(stderr, "[qn] #%ld type=%u ctx=0x%08X a8=0x%08X a12=0x%08X ccb=0x%08X\n",
                        n, w0 & 0xFu, cb, w8, w12, w16);
            }
        }
    }
    /* CD-driver state timeline: log only when the tuple changes, so the
     * digest shows exactly when the CDFS exchange stalled and in what
     * state (sync cell FE1C, remaining FDF8, expected LBA FE04, plus
     * the runtime's pending-response bookkeeping). */
    {
        uint32_t fe1c, fdf8, fe04;
        memcpy(&fe1c, xenolift_mem + 0x4FE1Cu, 4);
        memcpy(&fdf8, xenolift_mem + 0x4FDF8u, 4);
        memcpy(&fe04, xenolift_mem + 0x4FE04u, 4);
        static uint32_t s_fe1c, s_fdf8, s_fe04;
        static int s_init;
        if (!s_init || fe1c != s_fe1c || fdf8 != s_fdf8 || fe04 != s_fe04) {
            s_init = 1; s_fe1c = fe1c; s_fdf8 = fdf8; s_fe04 = fe04;
            fprintf(stderr, "[cdst] #%ld FE1C=%u FDF8=%u FE04=%u pend=%u cmd=0x%02X arm1=%u\n",
                    n, fe1c, fdf8, fe04, cd_pending, cd_last_cmd, cd_arm_int1_pending);
        }
    }
}

static int hb_active; /* kernel code dispatched from the heartbeat/kick may
     * itself poll the spin cell -> recursive read16 hook -> guard */

/* R78: the IRQ-context driver body. Called by the VBlank heartbeat
 * (paced by spin-cell reads) and by xenolift_park_tick (paced by
 * self-jump park iterations). Caller manages the hb_active guard. */
/* R85: THE 0x90C BOOT GATE = CONTROLLER CONNECTED.
 * fn_80040828 (from fn_80036288, boot main) calls the B0(0x12) stub with
 * (buf1, 34, buf2, 34) — the BIOS pad-buffer pair at 0x800625FC (34B
 * each, the "+34-stride device table" from earlier decodes). fn_8003569C
 * reads entry: byte0 must be 0 (ok), byte1 high nibble in {0x40 digital,
 * 0x50 analog, 0x70 mouse}, returns ~(bytes2..3) — 0x41/0x5A (digital
 * id+sync) gives nonzero "present". The walker was gated forever
 * (=WALK= gate=00 state 0000 -> 0000). Our B0(0x12) HLE is a no-op so
 * nothing ever clears the buffers; fill once at init + refresh per kick. */
static int g_movie_live;       /* R295: tentative decl — real def at R254 site (file-scope merge) */
static uint32_t g_park_fills;  /* R295 */
static uint32_t g_mv_poll_n; /* R312: movie-loop poll iteration counter (watchdog liveness) */
/* R320: C-recursion guard. Cycle-67/68 proof: the now-ALIVE CD state machine
 * (state 11 dispatching per R319) churns via DISPATCH tail-calls that NEVER
 * RETURN — each state hop nests another host C frame. The machine cycles at
 * ~100K hops/sec; after ~15s the 2048MB thread stack (R261) is exhausted and
 * macOS SIGKILLs the process (cycle-68 "Killed: 9", zero [wd] evidence).
 * Measure actual stack depth at the state-11 probe (address of a local vs the
 * base captured at kernel entry 0x80019524); near the limit, force the
 * graceful budget halt (park + exit) instead of the OOM kill. */
uintptr_t g_stack_base; int g_force_halt;
/* R323 CHURN TRAMPOLINE (cycle-71: R322 dispatcher-level trampoline bypassed —
 * the state machine also hops via DIRECT emitted calls (e.g. xenolift_fn_8002AC08),
 * which never touch xenolift_dispatch; the watchdog caught the machine inside the
 * h4 retry tail at 1.25GB depth with zero dispatcher bounces). NEW CHOKEPOINT:
 * xenolift_trace() sees EVERY guest function entry via XTRACE, direct or dispatched.
 * The permanent anchor lives at the guest thread base (xenolift_real_main entry —
 * setjmp there never dies); any family fn (0x8002A600-B400) entered >8MB deep
 * longjmps back to the anchor and re-dispatches at fresh stack. The abandoned
 * frames are the eternal churn chain — its enclosing poller context is already
 * permanently stuck (the churn never returns), so nothing live is lost. */
jmp_buf xenolift_churn_jmp; int xenolift_churn_armed;
uint32_t xenolift_churn_pend; unsigned long xenolift_churn_bounces;
uintptr_t xenolift_churn_base;
/* R316: TRUE 60HZ VBLANK. The kernel vblank counter 0x80057848 only
 * advanced from the busy-flag heartbeat (1 per 3000 polls of 0x8005957C)
 * — during the movie/stress diagnostic that poll barely runs, so frames
 * trickled at ~4 per 195s run (cycle-64: 76F04 0->4, ~20s per CD event).
 * EVERY frame-paced wait in the game spins on this counter. Advance it at
 * a hardware-faithful 60Hz wall-clock rate, topped up from the movie-loop
 * probe (fires millions of times/sec) so any frame-paced wait completes at
 * real speed. Bounded catch-up (max 8 frames per call). */
static uint64_t g_vb_ns;
int g_rspop_win; /* R317: response-pop trace window armed by cd_restore_pend */
static void vb_topup_60hz(void)
{
    struct timespec ts;
    uint64_t now;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    now = (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
    if (g_vb_ns == 0) { g_vb_ns = now; return; }
    {
        int caught = 0;
        while (now - g_vb_ns >= 16666666ull && caught < 8) {
            g_vb_ns += 16666666ull;
            xenolift_mem_write32(0x80057848u, xenolift_mem_read32(0x80057848u) + 1u);
            caught++;
        }
        if (g_vb_ns < now - 100000000ull) g_vb_ns = now; /* never lag hours behind */
    }
}
static uint32_t g_press_state; /* R295 */
const char *g_exit_why = "main-returned-region"; /* R679: which exit path fired (set at each exit site) */
static uint32_t g_press_held;   /* R295 */
static uint32_t g_skip_polls;       /* R296: SkipInput polls in movie phase */
static uint32_t g_menu_seen;         /* R371: kernel menu header rendered (FontVPrintf fmt 0x800182C0) */
static uint32_t g_menu_press_state; /* R371: 0=wait, 1=settle, 2=hold X, 3=done */
static uint32_t g_menu_reads;       /* R371: ReadControllerButtons entries in menu era */
static uint32_t g_menu_frames;         /* R373: menu-header renders seen */
static uint32_t g_menu_callset[128];  /* R375: widened - cycle 132 hit the 32 cap and may have dropped the menu's input reader */
static int g_menu_callcount;
static uint32_t g_readbutton_holds; /* R296: ReadControllerButtons entries during hold */

static int g_pad_phase; /* 0 = pre-handshake (state 0x90C), 1 = identified */

static void pad_fill(void)
{
    uint32_t bufs[2] = { 0x800625FCu, 0x8006261Eu };
    /* R89: the boot's BSS clear (fn_80019524: zero 0x800592B8-0x8007FAEC)
     * wipes the armed latch (0x80059330) — the digest caught 1 -> 0 at
     * fn_80019548 entry. Keep it armed in the same kick refresh as the
     * pads; only write when it reads zero so a real kernel set_latch
     * value is never clobbered. On real HW the latch is nonzero by the
     * display step's report (the walker fn_800320F8 would trap 0x83
     * otherwise). */
    { uint32_t cur; memcpy(&cur, xenolift_mem + 0x59330u, 4);
      if (cur == 0u) { uint32_t one = 1u; memcpy(xenolift_mem + 0x59330u, &one, 4); } }
    int b, i;
    for (b = 0; b < 2; b++) {
        uint32_t base = bufs[b] - 0x80000000u;
        xenolift_mem[base + 0] = 0x00;  /* status: ok */
        xenolift_mem[base + 1] = 0x40;  /* digital controller */
        /* R86: the boot check (fn_80019578@0x800198E8) reads the
         * pad-state cell 0x80059570 and wants 0x90C = "connected,
         * handshake pending" — that requires pad bytes 2-3 = 0xF6 0xF3
         * (state = ~0xF6F3 = 0x090C). After the settle loop
         * (while state==0x90C: fn_80035CDC) runs the handshake, the
         * state must CHANGE — we flip to the identified digital pad
         * (0x41 0x5A -> 0xBEA5) once fn_80035CDC has been stepped. */
        if (g_pad_phase) {
            /* R284: THE SKIP-STORM FIX (cycle-32 watcher verdict: the
             * movie countdown 0x80077014 oscillated 5->4->3->5 forever
             * because fn_80076AE0 [the SKIP-MOVIE path of SkipInput]
             * re-armed it every pass: the button cells 0x800773AC/74
             * held 0xBEA5 = ~(0x415A) = our handshake id/sync bytes
             * left in the BUTTON slot, whose bit 0x800 reads as
             * "skip held". Per psx-spx/BIOS pad-buffer format, after
             * the handshake bytes 2-3 must hold the live BUTTON data
             * (active-low: 0xFFFF = all released). ~0xFFFF = 0 -> the
             * game sees NO buttons; the boot gate still passes because
             * state cell 0x80059570 = ~bytes2-3 = 0 != 0x090C
             * ("changed away"), exactly like hardware. */
            /* R295: THE VIRTUAL PLAYER. Cycle-43 decode of fn_800769A4
             * (MoviePollSkipInput): the pre-movie poll waits for the
             * controller — button bit 0x40 (X) held on consecutive polls
             * (cells 0x800773AC prev + 0x800773B4 cur) with gate 0x80077028
             * clear (parked=0=OPEN) -> SetSpuCdVolumeFade(0,10) -> movie
             * state cell 0x80077014 = 5 = START. Real hardware had a human;
             * our run waits forever. Inject ONE X press once the movie park
             * is stable (movie live + FE1C>=10 + no remaining bytes + a
             * seek target), hold it across polls, then release. */
            {
                /* R296: pad_fill runs only at boot handshake cadence — its park
                 * trigger accumulated zero (cycle-44 =PADIN= empty). The press
                 * engine now lives in the bios_inspect entry hooks; this block
                 * only mirrors the hold state if pad_fill ever runs mid-hold. */
                if (g_press_state == 1u) {
                    xenolift_mem[base + 2] = 0xFF;
                    xenolift_mem[base + 3] = 0xBF; /* bit 0x40 clear = X pressed (active-low) */
                    if (++g_press_held > 400u) {
                        g_press_state = 2u;
                        fprintf(stderr, "[padin] X released after %u held polls (one-shot done)\n", g_press_held);
                        xenolift_mem[base + 2] = 0xFF;
                        xenolift_mem[base + 3] = 0xFF;
                    }
                } else {
                    xenolift_mem[base + 2] = 0xFF;  /* buttons: all released (active-low) */
                    xenolift_mem[base + 3] = 0xFF;
                }
            }
            { static int logged; if (!logged) { logged = 1;
                fprintf(stderr, "[padfix] R284: idle button frame 0xFFFF -> ReadControllerButtons reports 0 (no skip storm)\n"); } }
        } else {
            xenolift_mem[base + 2] = 0xF6;  /* pre-handshake: -> state 0x90C */
            xenolift_mem[base + 3] = 0xF3;
        }
        for (i = 4; i < 34; i++) xenolift_mem[base + i] = 0xFF; /* released */
    }
}

static void xenolift_kick(void)
{
    heartbeat_diag();
    pad_fill();
    /* R80: driver state walk. On real HW this runs from interrupt
     * context (CD/timer IRQs) and advances the state cell 0x80059550
     * toward the 0x90C "ready" magic the boot checks. Our event HLE
     * delivers events but never ran the kernel's own walker, so the
     * state stayed dead (=STATE= empty) and the boot failed its
     * checks -> trap 0x83 -> SystemError. One step per kick round. */
    {
        uint32_t s4 = (uint32_t)r[4], s5 = (uint32_t)r[5];
        r[4] = 0; r[5] = 0;
        {
            static uint32_t w_n; uint16_t st_b, st_c; uint8_t gate;
            memcpy(&st_b, xenolift_mem + 0x59550, 2);
            memcpy(&gate, xenolift_mem + 0x59388, 1);
            xenolift_dispatch(0x800358BCu);
            memcpy(&st_c, xenolift_mem + 0x59550, 2);
            if (w_n < 12 || (w_n % 1000u) == 0u || st_b != st_c)
                fprintf(stderr, "[walk] #%u gate=%02X state %04X -> %04X\n", w_n, gate, st_b, st_c);
            w_n++;
        }
        r[4] = s4; r[5] = s5;
    }
    fprintf(stderr, "[evt] heartbeat: synthetic VBlank + periodic round\n");
    evt_deliver_class(0xF0000001u, 0);
    evt_deliver_class(0xF2000002u, 2);
    /* CD event F0000009: the kernel's async file loader (module 4)
     * registers it with a NULL handler (wake-waiters-only) and paces
     * its chunk loop with B0(0x0A) WaitEvent. On real HW the BIOS
     * delivers it from CD interrupt context per completed chunk. Fire
     * it every round so any loader waiter progresses. */
    evt_deliver_class(0xF0000009u, 0x20u);
    /* File-device step: the async loader submits chunk jobs to the
     * kernel file device (module 4) and returns; on real hardware the
     * device processes them from CD-interrupt context. Static recomp
     * has no interrupt chain, so step the device's own request
     * processor exactly the way its callers do (fn_8004E574(0,0)
     * records the wait params, then fn_8004DD1C(slot 0) processes the
     * 20-byte job struct). If a CDFS read is needed it runs through
     * the kernel's own sync-wait + tick machinery, which is r31-gated
     * and works from any dispatch context. */
    {
        static uint32_t kick_n;
        static int32_t last_rv; static int rv_seen;
        int32_t s4 = (int32_t)r[4], s5 = (int32_t)r[5];
        /* Queue state cell 0x8005957C on-change: bit 4 = task-in-flight,
         * and its CLEARING is the moment the main thread's spin exits.
         * Log every distinct state as boot progresses. */
        {
            static uint16_t qs_last; static int qs_seen; static uint32_t qs_n;
            uint16_t qs;
            memcpy(&qs, xenolift_mem + (0x8005957Cu-0x80000000u), 2);
            if (!qs_seen || qs != qs_last) {
                fprintf(stderr, "[task] queue state 0x%04X (%s)\n",
                        qs, (qs & 0x10u) ? "busy" : "IDLE-main-free");
                qs_last = qs; qs_seen = 1;
            }
            qs_n++;
        }
        r[4] = 0; r[5] = 0;
        xenolift_dispatch(0x8004E574u);
        /* slot 0 | 0x100: the 0x100 flag makes the consumer (fn_8004DD1C)
         * call the chunk-chaining STEPPER (fn_8004E3C8) after processing
         * the arrival — exactly how the kernel's own caller at 0x80038A64
         * invokes it. Without the flag the arrival is consumed but no
         * next chunk is ever armed. */
        r[4] = 0x100u;
        xenolift_dispatch(0x8004DD1Cu);
        kick_n++;
        /* The kernel's own submit path (0x8004CBBC) honors this contract:
         * when a callback is parked in the completion cell *(0x80058E40)
         * and the transfer work is done, it CALLS it (jalr v0). The
         * parked callback is the task notifier 0x8003BB64 — the very
         * routine that advances the queue and clears the busy flag bit 4,
         * freeing the main thread. The stepper consumes + restores the
         * cell but never calls it in our runs, so the queue freezes.
         * After each SPU DMA completes, if the cell is nonzero, call it
         * exactly as the kernel would. */
        {
            static unsigned last_dma;
            uint32_t cb;
            memcpy(&cb, xenolift_mem + (0x80058E40u-0x80000000u), 4);
            if (cb != 0u && xenolift_spu_dma_count != last_dma) {
                fprintf(stderr, "[task] pending notifier 0x%08X: CALL (after spu-dma #%u)\n",
                        cb, xenolift_spu_dma_count);
                last_dma = xenolift_spu_dma_count;
                xenolift_dispatch(cb);
            }
        }
        int32_t rv = (int32_t)r[2];
        if (kick_n <= 3u || !rv_seen || rv != last_rv || kick_n % 20000u == 0u) {
            fprintf(stderr, "[task] kick #%u: file-device step -> %d\n", kick_n, rv);
            rv_seen = 1; last_rv = rv;
        }
        /* Photograph the loader/file-device state block on any change.
         * R59 lesson: the loader cells are reached via lui 0x8006 + a
         * NEGATIVE imm — the real block is 0x80058DF0..0x80058EC0, and
         * hand-derived addresses invite sign-extension mistakes (three
         * prior bugs of this exact class). So dump the WHOLE region as
         * raw words and let offline analysis map it, plus the dev-info
         * struct's status words and the request structs' first words. */
        {
            #define LBLK_BASE 0x80058980u
            #define LBLK_WORDS 344 /* covers 0x80058980-0x80058EE0 */
            static uint32_t last_blk[LBLK_WORDS]; static int blk_seen;
            uint32_t blk[LBLK_WORDS]; int changed = 0;
            for (int i = 0; i < LBLK_WORDS; i++) {
                memcpy(&blk[i], xenolift_mem + (LBLK_BASE-0x80000000u) + (uint32_t)i*4u, 4);
                if (!blk_seen || blk[i] != last_blk[i]) changed = 1;
            }
            memcpy(last_blk, blk, sizeof blk); blk_seen = 1;
            if (changed) {
                fprintf(stderr, "[task] loader-block @kick %u (0x80058980-0x80058EE0):\n", kick_n);
                for (int r_ = 0; r_ < LBLK_WORDS; r_ += 8) {
                    fprintf(stderr, "[task]  %04X:", (unsigned)(0x8980 + r_*4));
                    for (int c_ = 0; c_ < 8 && r_+c_ < LBLK_WORDS; c_++)
                        fprintf(stderr, " %08X", blk[r_+c_]);
                    fprintf(stderr, "\n");
                }
                /* dev-info struct (ptr at 0x80058E08 — imm -29176) + status
                 * words, request ptrs 0x80058E0C/10/14 first words, and the
                 * blocksize/init-flag cells. */
                uint32_t dev; memcpy(&dev, xenolift_mem + (0x80058E08u-0x80000000u), 4);
                fprintf(stderr, "[task]  dev-info ptr = 0x%08X\n", dev);
                if (dev >= 0x80000000u && dev < 0x80200000u) {
                    uint16_t w16[8];
                    for (int i = 0; i < 8; i++)
                        memcpy(&w16[i], xenolift_mem + (dev-0x80000000u) + 0x180u + (uint32_t)i*2u, 2);
                    fprintf(stderr, "[task]  dev+180..+18E: %04X %04X %04X %04X %04X %04X %04X %04X\n",
                            w16[0],w16[1],w16[2],w16[3],w16[4],w16[5],w16[6],w16[7]);
                    fprintf(stderr, "[task]  dev+1A0..+1AE: ");
                    for (int i = 0; i < 8; i++) {
                        memcpy(&w16[i], xenolift_mem + (dev-0x80000000u) + 0x1A0u + (uint32_t)i*2u, 2);
                        fprintf(stderr, "%04X ", w16[i]);
                    }
                    fprintf(stderr, "\n");
                }
                for (int i = 0; i < 3; i++) {
                    uint32_t p; memcpy(&p, xenolift_mem + (0x80058E0Cu-0x80000000u) + (uint32_t)i*4u, 4);
                    if (p >= 0x80000000u && p < 0x80200000u) {
                        uint32_t w; memcpy(&w, xenolift_mem + (p-0x80000000u), 4);
                        fprintf(stderr, "[task]  req%d: ptr=0x%08X *ptr=0x%08X\n", i+1, p, w);
                    } else {
                        fprintf(stderr, "[task]  req%d: ptr=0x%08X\n", i+1, p);
                    }
                }
                {
                    uint32_t w18, w1c;
                    memcpy(&w18, xenolift_mem + (0x80058E18u-0x80000000u), 4);
                    memcpy(&w1c, xenolift_mem + (0x80058E1Cu-0x80000000u), 4);
                    fprintf(stderr, "[task]  blocksize/8E18=0x%08X init/8E1C=0x%08X\n", w18, w1c);
                }
            }
        }
        /* Job-cells compact photo: mode/ctx/chunks/transfer-amount/
         * flag/obj/bank-descriptor/name — the whole SPU-upload state at
         * a glance, on change. */
        {
            static uint32_t jc_last[8]; static int jc_seen; static uint32_t jc_n;
            uint32_t jc[8];
            memcpy(&jc[0], xenolift_mem + (0x80058E58u-0x80000000u), 4); /* mode */
            memcpy(&jc[1], xenolift_mem + (0x80058E5Cu-0x80000000u), 4); /* ctx */
            memcpy(&jc[2], xenolift_mem + (0x80058E60u-0x80000000u), 4); /* chunks */
            memcpy(&jc[3], xenolift_mem + (0x80058E40u-0x80000000u), 4); /* xfer amount */
            memcpy(&jc[4], xenolift_mem + (0x80058E24u-0x80000000u), 4); /* flag */
            memcpy(&jc[5], xenolift_mem + (0x80058E70u-0x80000000u), 4); /* dev obj */
            memcpy(&jc[6], xenolift_mem + (jc[1]-0x80000000u), 4);        /* bank[0] */
            memcpy(&jc[7], xenolift_mem + (0x80058EC0u-0x80000000u), 4); /* name0 */
            int chg = !jc_seen;
            for (int i = 0; i < 5; i++)
                if (jc[i] != jc_last[i]) chg = 1;
            memcpy(jc_last, jc, sizeof jc); jc_seen = 1; jc_n++;
            if (chg || jc_n % 20000u == 0u)
                fprintf(stderr, "[task] job-cells #%u: mode=%u ctx=%08X chunks=%u xfer=%08X flag=%u obj=%08X bank0=%08X name0=%08X\n",
                        jc_n, jc[0], jc[1], jc[2], jc[3], jc[4], jc[5], jc[6], jc[7]);
        }
        r[4] = (uint32_t)s4; r[5] = (uint32_t)s5;
    }
}

static void xenolift_vblank_heartbeat(void)
{
    if (hb_active) return;
    /* R448 FIELD-LOAD FRAME ACCELERATION (c207 data): each field sector
     * costs the guest only ~9 dispatches ([fldsec] dring) — the 1.9s/sector
     * wall time IS the frame clock: one heartbeat round per frame, ~0.53
     * fps. The game loads ONE SECTOR PER FRAME by design (matches a 2x CD
     * at 60fps on real hardware). Accelerate the frame clock ONLY during
     * the field-sized read — the proven R409 era gate (FE20=3, FDF8>100000,
     * read active) — boot and menu trajectories are untouched (gate false
     * through the whole boot era). 3000->64 polls per frame round. */
    uint32_t vb_thresh = 3000u;
    {
        uint32_t fe20 = 0, fdf8 = 0;
        memcpy(&fe20, xenolift_mem + 0x4FE20, 4);
        memcpy(&fdf8, xenolift_mem + 0x4FDF8, 4);
        if (cd_read_active && fe20 == 3u && fdf8 > 100000u)
            vb_thresh = 64u;
    }
    if (++g_vb_polls < vb_thresh) return;
    g_vb_polls = 0;
    hb_active = 1;
    xenolift_kick();
    hb_active = 0;
}

/* R78 park tick: a `j self` block is an IRQ-park — the thread hands
 * control to interrupt-driven machinery (CD/driver state walk, event
 * delivery, device processing). Emulate the preemption: every 1024th
 * iteration run the kernel's own drivers. fn_800358BC is the kernel's
 * driver state walker (advances *(u16*)0x80059550 state -> next via
 * fn_800357C0; reaching 0x90C lets the boot proceed toward the
 * main-program load). Registers may be clobbered: a self-jump park
 * has no exit and no live register state, matching real HW park
 * semantics. */
uint32_t xenolift_park_ticks;
/* R541 [liftctl]: live patch panel (jdBasic posture — Jos 13:12):
 * command file "liftctl" polled each park tick; each command set
 * executes ONCE (first-seen) and logs a receipt. Commands (hex):
 *   W <addr> <val>   write32 to guest RAM cell
 *   R <n> <b0..bN>   prime response FIFO with n bytes
 *   F <flag> <0|1>   toggle drive flag: 0=motor 1=read_active 2=scheduled
 * Built for live contract experiments at the wall: change an answer,
 * watch the kernel react in the SAME run — no rebuild per guess. */
static int lc_seen;
static void liftctl_poll(void)
{
    static char lc_prev[96];
    FILE *f = fopen("liftctl", "r");
    if (!f) return;
    char lines[8][96];
    int n = 0;
    char buf[96];
    while (n < 8 && fgets(buf, sizeof buf, f)) {
        size_t L = strlen(buf);
        while (L && (buf[L-1] == '\n' || buf[L-1] == '\r' || buf[L-1] == ' ')) buf[--L] = 0;
        if (L && L < 96) { memcpy(lines[n], buf, L+1); n++; }
    }
    fclose(f);
    if (n && strcmp(lc_prev, lines[0]) != 0) { memcpy(lc_prev, lines[0], strlen(lines[0])+1); lc_seen = 0; }
    if (!n || lc_seen) return;
    lc_seen = 1;
    for (int i = 0; i < n; i++) {
        char *p = lines[i];
        if (p[0] == 'W') {
            unsigned a, v; if (sscanf(p+1, "%x %x", &a, &v) == 2 && a >= 0x80010000u && a < 0x80200000u) {
                xenolift_mem_write32(a, v);
                fprintf(stderr, "[liftctl] W 0x%08X <- 0x%08X applied\n", a, v);
            }
        } else if (p[0] == 'R') {
            unsigned k, b[8]; int got = sscanf(p+1, "%x %x %x %x %x %x %x %x %x", &k, &b[0],&b[1],&b[2],&b[3],&b[4],&b[5],&b[6],&b[7]);
            if (got >= 2 && k <= 8 && (unsigned)(got-1) >= k) {
                for (unsigned j = 0; j < k; j++) cd_resp[j] = (uint8_t)b[j];
                cd_resp_n = k; cd_resp_pos = 0;
                fprintf(stderr, "[liftctl] R primed %u bytes (%02X...)\n", k, cd_resp[0]);
            }
        } else if (p[0] == 'F') {
            unsigned w, s; if (sscanf(p+1, "%x %x", &w, &s) == 2) {
                if (w == 0) cd_motor_on = s ? 1 : 0;
                else if (w == 1) cd_read_active = s ? 1 : 0;
                else if (w == 2) cd_scheduled = s ? 1 : 0;
                fprintf(stderr, "[liftctl] F flag%u=%u applied\n", w, !!s);
            }
        }
    }
}

void xenolift_park_tick(void)
{
    liftctl_poll();
    uint32_t n = ++xenolift_park_ticks;
    if ((n & 0x3FFu) != 0u) return;
    { /* R622 STALL2: c191/c192 walk froze at step 8 (109019 @t=153) with
         * SIGALRM starved (wd gap t=161-203) — the on_alarm stall watch
         * was dead code exactly then. park_tick KEPT RUNNING (the t=205
         * [halt] printed from here), so the fingerprint lives here:
         * walk-quiet >10s in walk era -> dump dispatcher + guest regs
         * every ~5s, cap 10 lines. */
        static long s2_last; static int s2_n; static long s2_wall;
        long tn = (long)time(NULL);
        long boot = g_boot_wall_t0 ? (long)(tn - g_boot_wall_t0) : 0L;
        if (g_walk_max >= 109000u && g_walk_last_t >= 0 &&
            boot - g_walk_last_t > 10 && boot - s2_last >= 5 && s2_n < 10) {
            s2_last = boot; s2_n++;
            fprintf(stderr, "[cd] R622 STALL2: t=%lds quiet=%lds max_seek=%u | last_cmd=0x%02X seek=%u FE1C=%u FE20=%u pend=%u sched=%u FDF8=%08X FDFC=%08X FE34=%08X F0C=%08X F10=%08X slot56788=%08X hdl564AC=%08X cb59F08=%08X | r31=%08X r29=%08X r2=%08X r4=%08X pticks=%u\n",
                    boot, boot - g_walk_last_t, g_walk_max,
                    cd_last_cmd, cd_seek_lba,
                    xenolift_mem_read32(0x8004FE1Cu), xenolift_mem_read32(0x8004FE20u),
                    (unsigned)cd_pending, (unsigned)cd_scheduled,
                    xenolift_mem_read32(0x8004FDF8u), xenolift_mem_read32(0x8004FDFCu),
                    xenolift_mem_read32(0x8004FE34u),
                    xenolift_mem_read32(0x80059F0Cu), xenolift_mem_read32(0x80059F10u),
                    xenolift_mem_read32(0x80056788u), xenolift_mem_read32(0x800564ACu),
                    xenolift_mem_read32(0x80059F08u),
                    r[31], r[29], r[2], r[4], xenolift_park_ticks);
        }
        (void)s2_wall;
    }
    if (!hb_active) {
        hb_active = 1;
        r[4] = 0; r[5] = 0;
        xenolift_kick();
        r[4] = 0; r[5] = 0;
        xenolift_dispatch(0x800358BCu); /* driver state walk step */
        hb_active = 0;
    }
    { /* R597 [f15cont] continuous file-15 batch feed: c165 stepper
         * receipts — the queue stepper (fn 80041430) IS alive post-mount
         * (caller 8002B244 = archive-callback continuation), set up the
         * file-15 batch (node 00341424, dest 8007EAF8..F2F8) and the game's
         * own walk consumed the ONE sector R591's one-shot delivered
         * (node 00010200 walk, FDF8=0x800 remaining) — then parked at
         * idle node 00000200 because no more sectors ever arrived. The
         * batch needs ~45 ring sectors (file 15 = LBA 108995..109039,
         * 92180 bytes). Feed one sector per park heartbeat, into the
         * slot FE08 currently names, bumping FE34 (sectors-ready counter
         * the stream callback gates on). Stop at file-15's end; the
         * game's own walk/finalize does all bookkeeping. */
        static uint32_t f15_lba = 108997u; /* 108996 delivered by R591 */
        uint32_t f0c = xenolift_mem_read32(0x80059F0Cu);
        uint32_t node = xenolift_mem_read32(0x80059F10u);
        uint32_t fe08 = xenolift_mem_read32(0x8004FE08u);
        uint32_t fe34 = xenolift_mem_read32(0x8004FE34u);
        uint32_t cur = xenolift_mem_read32(0x800592C0u);
        uint16_t node_lo = (uint16_t)(node & 0xFFFFu);
        if (f0c == 14u && cur == 1u
            && fe08 >= 0x8007E000u && fe08 < 0x80080000u
            && (node_lo == 0x0200u) /* idle/walk forms; done-form 0x1524 stops the feed */
            && f15_lba <= 109039u) {
            /* R605: ring force-feed DISARMED — the native stream owns
             * the ring write pointer; force-feeding corrupts the
             * consumer's slot expectations. Log-only. */
            fprintf(stderr, "[f15cont] R605: feed SKIPPED (native owns ring; LBA %u -> 0x%08X observed only)\n", f15_lba, fe08);
            if (0) { uint8_t fbuf[2048];
            if (disc_read_lba(f15_lba, fbuf) == 0) {
                memcpy(xenolift_mem + (fe08 & 0x1FFFFFFFu), fbuf, 2048);
                /* R604: FE34 bump DISARMED here too — c171 receipts: FE34>0
                 * at FILE-CB entry = skip-copy + premature finalize. The
                 * game owns FE34; the feed only stages data. */
                {   static uint32_t f15feed_n;
                    if (f15feed_n < 60u)
                        fprintf(stderr, "[f15cont] R597 #%u: fed LBA %u -> 0x%08X (node=%08X FE34=%u->%u FDF8=%u)\n",
                                ++f15feed_n, f15_lba, fe08, node, fe34,
                                fe34 /* R604: no bump */,
                                xenolift_mem_read32(0x8004FDF8u));
                }
            } /* R605 close dead feed block */
            } /* R605 close if(0) feed guard */
            f15_lba++;
        }
    }
    if (((n >> 10) & 0xFFFFFu) == 0u) {
        uint16_t st; uint8_t sb;
        memcpy(&st, xenolift_mem + 0x59550, 2);
        memcpy(&sb, xenolift_mem + 0x59388, 1);
        fprintf(stderr, "[park] ticks=%u state=%04X status=%02X\n", n, st, sb);
    }
}

uint32_t xenolift_mem_read16(uint32_t a)
{
    /* R193: lzss-guard reads — the cycle-26 fault moved to a READ walk
     * (0x802408CF, LZSS back-reference history past RAM). Suppress and
     * return zero so the walk logs instead of halting. */
    if (lzss_armed && lzss_in_end && a >= lzss_in_end && a < 0x80200000u) {
        /* R195: input-overrun — token byte read PAST the stream's declared end.
         * LOG-ONLY (no behavior change): names the runaway's fuel source. */
        if (lzss_inpast_n < 8 && !g_in_park) fprintf(stderr, "[lzss-inpast] token read past input end (end=0x%08X) @0x%08X\n", lzss_in_end, a); /* R367: park-time host reads must not fire decode hooks */
        lzss_inpast_n++;
    }
    if (lzss_armed && a >= 0x80200000u) {
        if (lzss_over_n < 8) {
            fprintf(stderr, "[lzss-guard-r] suppressed read @0x%08X -> 0\n", a);
        }
        lzss_over_n++;
        if ((lzss_over_n & 0xFFF) == 0) {
            fprintf(stderr, "[lzss-runaway] %d ops suppressed, read frontier 0x%08X\n", lzss_over_n, a);
        }
        return 0;
    }
    uint32_t off = xenolift_phys(a);
    uint16_t v;
    uint32_t tmp;
    /* R157: LEAF-SPIN RESCUE. Cycle-8 proof: after the last dir read
     * completes, the fd processor polls the CD data register in a
     * leaf loop with NO function entries — the trace-hook tick
     * machinery is completely deaf there (log silent after the read,
     * no fd-tick lines). This read hook is the ONLY code that still
     * runs in that spin (702k+ CD data-reg polls per park). When the
     * lost-register kick conditions hold (issued module read's LBA
     * cell walked over, request phase idle, drive quiet), restore the
     * snapshot and deliver the missing slot event — same mechanism
     * as the R130/R155 kicks, injected where the spin actually
     * lives. Registers are saved/restored; the spin reloads them
     * each iteration anyway. */
    if (a == 0x1F801800u || a == 0x1F801802u || a == 0x1F801803u) {
        /* R159: SPIN-CONV FIRST. Cycle-10 proof: the final spin sits
         * BEFORE the module read is even issued — the dir read's LAST
         * sector is unconsumed in the sector FIFO (data_n=2060,
         * data_pos=0), its data-ready INT stuck pending (arm1=0), and
         * NO trace events fire in this leaf spin to run the R137
         * conversion. The file layer never releases, mount never
         * reaches READ ISSUED, FE04 still equals seek — the R158 kick
         * below correctly stays silent. Convert the stuck INT here
         * (proven handler pair) and run the collector so the slot
         * event dispatches h2/h4 and drains the sector. Once the
         * cycle advances to issuing the module read, the R158 kick
         * handles the module-read wait spin. */
        static uint32_t spin_conv_n;
        static uint32_t spin_conv_budget = 100000u;
        if (cd_pending != 0u && cd_arm_int1_pending == 0u
            && xenolift_mem_read32(0x8004FE1Cu) != 0u
            && spin_conv_budget > 0u && ++spin_conv_n > 512u) {
            spin_conv_n = 0;
            spin_conv_budget--;
            {
                static int spin_conv_busy;
                if (!spin_conv_busy) {
                uint32_t sr[32]; uint32_t shi, slo;
                spin_conv_busy = 1;
                memcpy(sr, r, sizeof r); shi = hi; slo = lo;
                /* R160: cycle-11 Mac crash class — dispatching from
                 * mid-read clobbered the spin's live registers (jump
                 * through a corrupted slot -> 0x80200000 fault in the
                 * event pump). Full register-file + hi/lo save/restore,
                 * plus a reentrancy guard. The stream DID resume past
                 * the old 108886 wall — the concept works; this makes
                 * the delivery context safe. */
                r[4] = 0; r[5] = 0;
                cd_restore_pend(); /* R308: spin door */
fprintf(stderr, "[cd] spin-conv: converting stuck INT1 (pending=%u) via handler pair + collector\n",
                        cd_pending);
                xenolift_dispatch(0x800409E4u);
                xenolift_dispatch(0x80040A4Cu);
                xenolift_dispatch(0x800415B4u);
                memcpy(r, sr, sizeof r); hi = shi; lo = slo;
                spin_conv_busy = 0;
                }
            }
        } else if (cd_pending != 0u && cd_arm_int1_pending == 0u
                   && cd_data_pos >= cd_data_n && !cd_read_active) {
            /* R256: !cd_read_active guard — R255 cycle-4: the stage-2 load
             * (LBA 108561, 44 sectors) died at sector 1: sector drained via
             * DMA -> FIFO empty + next INT1 pending = LIVE read state that
             * looked identical to the R162 dead-INT case; this 256-poll
             * clear beat the 512-poll spin-conv and killed the read. A
             * pending INT1 during an active read is never dead. */
            /* R162: DEAD-INT, EMPTY FIFO. Cycle-13 park: after the
             * minute-53 deep read (239317-239321) completed natively
             * and the spin-discard drained its last sector, a dead
             * INT remains with an EMPTY sector FIFO (data_n=0) —
             * nothing to discard, nothing to convert, the flag just
             * sits and the deaf spin can't clear it. Clear the dead
             * pending directly (R130-kick precedent: pending=0 on
             * dead-request cleanup), no dispatches. */
            static uint32_t spin_clear_n;
            if (++spin_clear_n > 256u) {
                spin_clear_n = 0;
                fprintf(stderr, "[cd] spin-clear: dead INT, FIFO empty — clearing pending=%u\n",
                        cd_pending);
                cd_pending = 0;
            }
        } else if (cd_pending != 0u && cd_arm_int1_pending == 0u
                   && cd_data_pos < cd_data_n) {
            /* R161: DEAD-REQUEST INT. The chain is released (FE1C==0)
             * but its last sector sits unconsumed with the data-ready
             * INT still pending. R159/R160 crashed IDENTICALLY both
             * runs: converting a dead INT pushes a slot event for a
             * request that no longer exists -> collector walks a
             * garbage handler -> 0x80200000 guard halt. The R130 kick
             * treats this exact case as DISCARD, never convert: drop
             * the stale FIFO + clear the dead INT, no dispatches. */
            static uint32_t spin_disc_n;
            if (++spin_disc_n > 256u) {
                spin_disc_n = 0;
                fprintf(stderr, "[cd] spin-discard: dead INT w/ stale FIFO (%u bytes) — discarding\n",
                        cd_data_n - cd_data_pos);
                cd_data_pos = cd_data_n = 0;
                cd_data_loaded = 0; /* R167: flag stuck 1 = starved demand */
                cd_arm_int1_pending = 0;
                cd_pending = 0;
            }
        } else
        /* R158: SPIN-SITE KICK — when a queued request's LBA sits
         * unserved at a quiet drive (module read issued but its h2
         * never dispatched): discard any stale FIFO leftover and
         * deliver the missing slot event (collector + h2). */
        {
        static uint32_t cd_poll_n;
        uint32_t fe04_spin = xenolift_mem_read32(0x8004FE04u);
        /* R164: cycle-15 — the 14360B module-18 read COMPLETED natively;
         * the new park (fn 0x800413BC) holds the install VERIFY request
         * (read struct file#=18, FDFC=1 = queued-active, FE1C=0 phase-0,
         * FDF8=24) with the slot-2 handler cell EMPTY (0x564A8=0) — the
         * old kick's FE04!=seek is false (FE04==seek post-read) and the
         * blank handler cell would skip dispatch. Fire also when
         * FDFC==1 (queued request awaiting its slot event), and fall
         * back to the known h2 (0x8002A68C — every =SLOT= ENQUEUE
         * writes it) when the cell is blank. */
        if ((fe04_spin != 0u && fe04_spin != cd_seek_lba)
            || xenolift_mem_read32(0x8004FDFCu) == 1u) {
            ; /* handled below via shared quiet-gate */
        }
        /* R168: cycle-3 — R167 killed the starve treadmill (forces
         * 22166 -> 0), CdReady callbacks fire (first time), 110KB
         * content stream flowed (reads-done 10 -> 35). NEW park class:
         * mid-stream stall (park r31=0x800429A4 cd event pump) with a
         * LOADED-UNDRAINED sector (data_pos 0 < data_n 2060) + request
         * unfinished (FDF8=93680) + FE1C=6 NONZERO -> the FE1C==0 quiet
         * gate blocked every rescue. New trigger: drain the stall by
         * dispatching h4 (drain handler, cell 0x800564AC, fallback
         * 0x8002B084); FE1C bypass allowed ONLY for this sub-trigger. */
        uint32_t fe1c_spin = xenolift_mem_read32(0x8004FE1Cu);
        uint32_t midstream_stall = (cd_read_active && cd_data_pos < cd_data_n
                                    && xenolift_mem_read32(0x8004FDF8u) > 2048u);
        if (((fe04_spin != 0u && fe04_spin != cd_seek_lba)
             || xenolift_mem_read32(0x8004FDFCu) == 1u)
            && (fe1c_spin == 0u || midstream_stall)
            && cd_pending <= 1u && cd_scheduled == 0u
            && cd_arm_int1_pending == 0u
            && ++cd_poll_n > 256u) {
            cd_poll_n = 0;
            {
                static int spin_kick_busy;
                if (!spin_kick_busy) {
                uint32_t sr[32]; uint32_t shi, slo;
                spin_kick_busy = 1;
                memcpy(sr, r, sizeof r); shi = hi; slo = lo;
                /* R160: full register-file + hi/lo save/restore, same
                 * mid-read crash class as the spin-conv. */
                if (cd_data_pos < cd_data_n) {
                    fprintf(stderr, "[cd] spin-kick: discarding stale FIFO leftover (%u bytes, request done)\n",
                            cd_data_n - cd_data_pos);
                    cd_data_pos = cd_data_n = 0;
                cd_data_loaded = 0; /* R167: flag stuck 1 = starved demand */
                    cd_arm_int1_pending = 0;
                    cd_pending = 0;
                }
                fprintf(stderr, "[cd] spin-kick: queued request FE04=0x%08X unserved (seek=%u) — dispatching h2\n",
                        fe04_spin, cd_seek_lba);
                xenolift_dispatch(0x800415B4u);
                {
                    uint32_t h2 = xenolift_mem_read32(0x800564A8u);
                    if (h2 < 0x80010000u || h2 >= 0x80060000u) {
                        h2 = 0x8002A68Cu; /* R164: known h2 fallback */
                        fprintf(stderr, "[cd] spin-kick: slot cell blank — using known h2 0x8002A68C\n");
                    }
                    {
                        r[4] = xenolift_mem[0x56788];
                        r[5] = 0x8005A210u;
                        if (midstream_stall) {
                    uint32_t h4 = xenolift_mem_read32(0x800564ACu);
                    uint32_t save4 = r[4], save5 = r[5];
                    if (h4 < 0x80010000u || h4 >= 0x80060000u) {
                        h4 = 0x8002B084u; /* R168: known h4 fallback */
                        fprintf(stderr, "[cd] spin-drain: h4 cell blank — using known 0x8002B084\n");
                    }
                    r[4] = xenolift_mem[0x56789];
                    r[5] = 0x8005A218u;
                    fprintf(stderr, "[cd] spin-drain: mid-stream stall (LBA %u, FDF8 %u, fifo %u/%u) — dispatching h4 0x%08X\n",
                            cd_seek_lba, xenolift_mem_read32(0x8004FDF8u),
                            cd_data_pos, cd_data_n, h4);
                    xenolift_dispatch(h4);
                    r[4] = save4; r[5] = save5; /* restore h2's args */
                }
                fprintf(stderr, "[cd] spin-kick: dispatch h2 0x%08X (a0=%u)\n", h2, r[4]);
                        fprintf(stderr, "[cd] spin-kick: pre-h2: FE14=%08X FE08=%08X FE38=%08X gate48=%08X struct=%08X node0=%08X\n",
                                xenolift_mem_read32(0x8004FE14u), xenolift_mem_read32(0x8004FE08u),
                                xenolift_mem_read32(0x8004FE38u), xenolift_mem_read32(0x8004FE48u),
                                xenolift_mem_read32(0x80059EF8u), xenolift_mem_read32(0x80059F10u));
                        xenolift_dispatch(h2);
                    }
                }
                memcpy(r, sr, sizeof r); hi = shi; lo = slo;
                spin_kick_busy = 0;
                }
            }
        }
        }
    }

    /* VBlank heartbeat: the game polls the task-queue busy flag at
     * 0x8006957C in a tight loop (fn 0x8003BDFC, bit 4). On real
     * hardware its task processor runs from a 60 Hz VBlank callback.
     * Deliver a synthetic VBlank (class F0000001) to all enabled
     * events after many polls. The spin loop reloads every register
     * each iteration, so resuming mid-loop after the handler is safe. */
    /* NOTE: fn_8003BDFC polls the busy flag via lui 0x8006 + lhu with
     * SIGNED imm 0x957C = -0x6A84 -> actual address 0x8005957C (not
     * 0x8006957C). Hook both spellings. */
    if (off == 0x6957Cu || off == 0x5957Cu)
        xenolift_vblank_heartbeat();
    if (off >= XENOLIFT_RAM_SIZE && io_special_read(io_phys(off), &tmp)) {
        io_log(io_phys(off), 0, tmp);
        return tmp & 0xFFFFu;
    }
    memcpy(&v, xenolift_mem + off, 2);
    if (off >= XENOLIFT_RAM_SIZE) {
        io_log(io_phys(off), 0, v);
    }
    return v;
}

uint32_t xenolift_mem_read8(uint32_t a)
{
    /* R193: lzss-guard reads — the cycle-26 fault moved to a READ walk
     * (0x802408CF, LZSS back-reference history past RAM). Suppress and
     * return zero so the walk logs instead of halting. */
    if (lzss_armed && lzss_in_end && a >= lzss_in_end && a < 0x80200000u) {
        /* R195: input-overrun — token byte read PAST the stream's declared end.
         * LOG-ONLY (no behavior change): names the runaway's fuel source. */
        if (lzss_inpast_n < 8 && !g_in_park) fprintf(stderr, "[lzss-inpast] token read past input end (end=0x%08X) @0x%08X\n", lzss_in_end, a); /* R367: park-time host reads must not fire decode hooks */
        lzss_inpast_n++;
    }
    if (lzss_armed && a >= 0x80200000u) {
        if (lzss_over_n < 8) {
            fprintf(stderr, "[lzss-guard-r] suppressed read @0x%08X -> 0\n", a);
        }
        lzss_over_n++;
        if ((lzss_over_n & 0xFFF) == 0) {
            fprintf(stderr, "[lzss-runaway] %d ops suppressed, read frontier 0x%08X\n", lzss_over_n, a);
        }
        return 0;
    }
    uint32_t off = xenolift_phys(a);
    uint32_t tmp;
    /* R157: LEAF-SPIN RESCUE. Cycle-8 proof: after the last dir read
     * completes, the fd processor polls the CD data register in a
     * leaf loop with NO function entries — the trace-hook tick
     * machinery is completely deaf there (log silent after the read,
     * no fd-tick lines). This read hook is the ONLY code that still
     * runs in that spin (702k+ CD data-reg polls per park). When the
     * lost-register kick conditions hold (issued module read's LBA
     * cell walked over, request phase idle, drive quiet), restore the
     * snapshot and deliver the missing slot event — same mechanism
     * as the R130/R155 kicks, injected where the spin actually
     * lives. Registers are saved/restored; the spin reloads them
     * each iteration anyway. */
    if (a == 0x1F801800u || a == 0x1F801802u || a == 0x1F801803u) {
        /* R159: SPIN-CONV FIRST. Cycle-10 proof: the final spin sits
         * BEFORE the module read is even issued — the dir read's LAST
         * sector is unconsumed in the sector FIFO (data_n=2060,
         * data_pos=0), its data-ready INT stuck pending (arm1=0), and
         * NO trace events fire in this leaf spin to run the R137
         * conversion. The file layer never releases, mount never
         * reaches READ ISSUED, FE04 still equals seek — the R158 kick
         * below correctly stays silent. Convert the stuck INT here
         * (proven handler pair) and run the collector so the slot
         * event dispatches h2/h4 and drains the sector. Once the
         * cycle advances to issuing the module read, the R158 kick
         * handles the module-read wait spin. */
        static uint32_t spin_conv_n;
        static uint32_t spin_conv_budget = 100000u;
        if (cd_pending != 0u && cd_arm_int1_pending == 0u
            && xenolift_mem_read32(0x8004FE1Cu) != 0u
            && spin_conv_budget > 0u && ++spin_conv_n > 512u) {
            spin_conv_n = 0;
            spin_conv_budget--;
            {
                static int spin_conv_busy;
                if (!spin_conv_busy) {
                uint32_t sr[32]; uint32_t shi, slo;
                spin_conv_busy = 1;
                memcpy(sr, r, sizeof r); shi = hi; slo = lo;
                /* R160: cycle-11 Mac crash class — dispatching from
                 * mid-read clobbered the spin's live registers (jump
                 * through a corrupted slot -> 0x80200000 fault in the
                 * event pump). Full register-file + hi/lo save/restore,
                 * plus a reentrancy guard. The stream DID resume past
                 * the old 108886 wall — the concept works; this makes
                 * the delivery context safe. */
                r[4] = 0; r[5] = 0;
                cd_restore_pend(); /* R308: spin door */
fprintf(stderr, "[cd] spin-conv: converting stuck INT1 (pending=%u) via handler pair + collector\n",
                        cd_pending);
                xenolift_dispatch(0x800409E4u);
                xenolift_dispatch(0x80040A4Cu);
                xenolift_dispatch(0x800415B4u);
                memcpy(r, sr, sizeof r); hi = shi; lo = slo;
                spin_conv_busy = 0;
                }
            }
        } else if (cd_pending != 0u && cd_arm_int1_pending == 0u
                   && cd_data_pos >= cd_data_n && !cd_read_active) {
            /* R256: !cd_read_active guard — R255 cycle-4: the stage-2 load
             * (LBA 108561, 44 sectors) died at sector 1: sector drained via
             * DMA -> FIFO empty + next INT1 pending = LIVE read state that
             * looked identical to the R162 dead-INT case; this 256-poll
             * clear beat the 512-poll spin-conv and killed the read. A
             * pending INT1 during an active read is never dead. */
            /* R162: DEAD-INT, EMPTY FIFO. Cycle-13 park: after the
             * minute-53 deep read (239317-239321) completed natively
             * and the spin-discard drained its last sector, a dead
             * INT remains with an EMPTY sector FIFO (data_n=0) —
             * nothing to discard, nothing to convert, the flag just
             * sits and the deaf spin can't clear it. Clear the dead
             * pending directly (R130-kick precedent: pending=0 on
             * dead-request cleanup), no dispatches. */
            static uint32_t spin_clear_n;
            if (++spin_clear_n > 256u) {
                spin_clear_n = 0;
                fprintf(stderr, "[cd] spin-clear: dead INT, FIFO empty — clearing pending=%u\n",
                        cd_pending);
                cd_pending = 0;
            }
        } else if (cd_pending != 0u && cd_arm_int1_pending == 0u
                   && cd_data_pos < cd_data_n) {
            /* R161: DEAD-REQUEST INT. The chain is released (FE1C==0)
             * but its last sector sits unconsumed with the data-ready
             * INT still pending. R159/R160 crashed IDENTICALLY both
             * runs: converting a dead INT pushes a slot event for a
             * request that no longer exists -> collector walks a
             * garbage handler -> 0x80200000 guard halt. The R130 kick
             * treats this exact case as DISCARD, never convert: drop
             * the stale FIFO + clear the dead INT, no dispatches. */
            static uint32_t spin_disc_n;
            if (++spin_disc_n > 256u) {
                spin_disc_n = 0;
                fprintf(stderr, "[cd] spin-discard: dead INT w/ stale FIFO (%u bytes) — discarding\n",
                        cd_data_n - cd_data_pos);
                cd_data_pos = cd_data_n = 0;
                cd_data_loaded = 0; /* R167: flag stuck 1 = starved demand */
                cd_arm_int1_pending = 0;
                cd_pending = 0;
            }
        } else
        /* R158: SPIN-SITE KICK — when a queued request's LBA sits
         * unserved at a quiet drive (module read issued but its h2
         * never dispatched): discard any stale FIFO leftover and
         * deliver the missing slot event (collector + h2). */
        {
        static uint32_t cd_poll_n;
        uint32_t fe04_spin = xenolift_mem_read32(0x8004FE04u);
        /* R164: cycle-15 — the 14360B module-18 read COMPLETED natively;
         * the new park (fn 0x800413BC) holds the install VERIFY request
         * (read struct file#=18, FDFC=1 = queued-active, FE1C=0 phase-0,
         * FDF8=24) with the slot-2 handler cell EMPTY (0x564A8=0) — the
         * old kick's FE04!=seek is false (FE04==seek post-read) and the
         * blank handler cell would skip dispatch. Fire also when
         * FDFC==1 (queued request awaiting its slot event), and fall
         * back to the known h2 (0x8002A68C — every =SLOT= ENQUEUE
         * writes it) when the cell is blank. */
        if ((fe04_spin != 0u && fe04_spin != cd_seek_lba)
            || xenolift_mem_read32(0x8004FDFCu) == 1u) {
            ; /* handled below via shared quiet-gate */
        }
        /* R168: cycle-3 — R167 killed the starve treadmill (forces
         * 22166 -> 0), CdReady callbacks fire (first time), 110KB
         * content stream flowed (reads-done 10 -> 35). NEW park class:
         * mid-stream stall (park r31=0x800429A4 cd event pump) with a
         * LOADED-UNDRAINED sector (data_pos 0 < data_n 2060) + request
         * unfinished (FDF8=93680) + FE1C=6 NONZERO -> the FE1C==0 quiet
         * gate blocked every rescue. New trigger: drain the stall by
         * dispatching h4 (drain handler, cell 0x800564AC, fallback
         * 0x8002B084); FE1C bypass allowed ONLY for this sub-trigger. */
        uint32_t fe1c_spin = xenolift_mem_read32(0x8004FE1Cu);
        uint32_t midstream_stall = (cd_read_active && cd_data_pos < cd_data_n
                                    && xenolift_mem_read32(0x8004FDF8u) > 2048u);
        if (((fe04_spin != 0u && fe04_spin != cd_seek_lba)
             || xenolift_mem_read32(0x8004FDFCu) == 1u)
            && (fe1c_spin == 0u || midstream_stall)
            && cd_pending <= 1u && cd_scheduled == 0u
            && cd_arm_int1_pending == 0u
            && ++cd_poll_n > 256u) {
            cd_poll_n = 0;
            {
                static int spin_kick_busy;
                if (!spin_kick_busy) {
                uint32_t sr[32]; uint32_t shi, slo;
                spin_kick_busy = 1;
                memcpy(sr, r, sizeof r); shi = hi; slo = lo;
                /* R160: full register-file + hi/lo save/restore, same
                 * mid-read crash class as the spin-conv. */
                if (cd_data_pos < cd_data_n) {
                    fprintf(stderr, "[cd] spin-kick: discarding stale FIFO leftover (%u bytes, request done)\n",
                            cd_data_n - cd_data_pos);
                    cd_data_pos = cd_data_n = 0;
                cd_data_loaded = 0; /* R167: flag stuck 1 = starved demand */
                    cd_arm_int1_pending = 0;
                    cd_pending = 0;
                }
                fprintf(stderr, "[cd] spin-kick: queued request FE04=0x%08X unserved (seek=%u) — dispatching h2\n",
                        fe04_spin, cd_seek_lba);
                xenolift_dispatch(0x800415B4u);
                {
                    uint32_t h2 = xenolift_mem_read32(0x800564A8u);
                    if (h2 < 0x80010000u || h2 >= 0x80060000u) {
                        h2 = 0x8002A68Cu; /* R164: known h2 fallback */
                        fprintf(stderr, "[cd] spin-kick: slot cell blank — using known h2 0x8002A68C\n");
                    }
                    {
                        r[4] = xenolift_mem[0x56788];
                        r[5] = 0x8005A210u;
                        if (midstream_stall) {
                    uint32_t h4 = xenolift_mem_read32(0x800564ACu);
                    uint32_t save4 = r[4], save5 = r[5];
                    if (h4 < 0x80010000u || h4 >= 0x80060000u) {
                        h4 = 0x8002B084u; /* R168: known h4 fallback */
                        fprintf(stderr, "[cd] spin-drain: h4 cell blank — using known 0x8002B084\n");
                    }
                    r[4] = xenolift_mem[0x56789];
                    r[5] = 0x8005A218u;
                    fprintf(stderr, "[cd] spin-drain: mid-stream stall (LBA %u, FDF8 %u, fifo %u/%u) — dispatching h4 0x%08X\n",
                            cd_seek_lba, xenolift_mem_read32(0x8004FDF8u),
                            cd_data_pos, cd_data_n, h4);
                    xenolift_dispatch(h4);
                    r[4] = save4; r[5] = save5; /* restore h2's args */
                }
                fprintf(stderr, "[cd] spin-kick: dispatch h2 0x%08X (a0=%u)\n", h2, r[4]);
                        fprintf(stderr, "[cd] spin-kick: pre-h2: FE14=%08X FE08=%08X FE38=%08X gate48=%08X struct=%08X node0=%08X\n",
                                xenolift_mem_read32(0x8004FE14u), xenolift_mem_read32(0x8004FE08u),
                                xenolift_mem_read32(0x8004FE38u), xenolift_mem_read32(0x8004FE48u),
                                xenolift_mem_read32(0x80059EF8u), xenolift_mem_read32(0x80059F10u));
                        xenolift_dispatch(h2);
                    }
                }
                memcpy(r, sr, sizeof r); hi = shi; lo = slo;
                spin_kick_busy = 0;
                }
            }
        }
        }
    }

    /* CDROM/SIO dialogs are BYTE-granular — route them through the
     * special handlers just like the 16/32-bit paths (previously byte
     * reads silently bypassed the hardware model) */
    if (off >= XENOLIFT_RAM_SIZE && io_special_read(io_phys(off), &tmp)) {
        io_log(io_phys(off), 0, tmp);
        return tmp & 0xFFu;
    }
    uint8_t v = xenolift_mem[off];
    if (off >= XENOLIFT_RAM_SIZE) {
        io_log(io_phys(off), 0, v);
    }
    return v;
}

extern uint32_t xenolift_ring[64]; extern int xenolift_ring_n; /* R81 */
void xenolift_mem_write32(uint32_t a, uint32_t v)
{
    /* R487: garbage-family WRITE drop. The WDS high-end allocator
     * (fn_80039044) computes a poisoned free-list end (fault addr
     * 0xA106BDD8, r17=0xDF000011 family) and stores a bookkeeping
     * word there. R186 proved route-to-exception is futile (kernel
     * exception exit = blank page in this EXE -> handler returns to
     * the same store -> ping-pong halt). Real HW: bus error, write
     * lands nowhere, driver continues. Match that: DROP, receipt,
     * continue. READS still halt (probe signal). */
    if ((a >= 0x80200000u) || (a < 0x80000000u && a > 0x00100000u
          && !(a >= 0x1F800000u && a <= 0x1FAF0000u)) || (a >= 0xBFC10000u)) {
        static uint32_t dw_last; static int dw_n; static uint32_t dw_tot;
        if ((a != dw_last || dw_n < 4) && dw_tot < 24u) {
            dw_tot++;
            fprintf(stderr, "[wdrop] garbage write 0x%08X val=%08X dropped (r31=%08X r17=%08X) — continuing\n",
                    (unsigned)a, (unsigned)v, (unsigned)r[31], (unsigned)r[17]);
            dw_last = a; dw_n++;
        }
        return;
    }
    /* R517: [mangleguard] — c83/c84 decoded the 0x03-mangle family: guest fn
     * 0x800317E0 (pointer-fixup loop) stores, into kernel cells AND the irq
     * chain (0x80065B10+12), values like 0x0304FE0C/0x03059F1C/0x03065B0C =
     * (real cell address - 0x10) with the MSB turned to 0x03. Every one of
     * them dereferences OUTSIDE guest RAM (0x03xxxxxx < 0x80000000) and the
     * exception-recovery walk of the poisoned chain is what KILLS the run
     * (c83/c84 HALT). Gate: a VALUE in [0x03000000,0x04000000) whose low-24
     * bits land in the guest-RAM mirror window [0x00010000,0x00080000) can
     * never be a usable pointer or a plausible game scalar — drop it (same
     * bus-error semantics as R487), keep the kernel's records whole so the
     * game's own recovery completes. Receipt + 24-line budget. */
    if (v >= 0x03000000u && v < 0x04000000u
        && (v & 0x00FFFFFFu) >= 0x00010000u && (v & 0x00FFFFFFu) < 0x00080000u
        && a >= 0x80010000u && a < 0x80200000u) {
        static uint32_t mg_last; static int mg_n; static uint32_t mg_tot;
        if ((a != mg_last || mg_n < 4) && mg_tot < 24u) {
            mg_tot++;
            fprintf(stderr, "[mangleguard] R517 mangled-pointer store a=%08X val=%08X dropped (r31=%08X) — chain preserved\n",
                    (unsigned)a, (unsigned)v, (unsigned)r[31]);
            mg_last = a; mg_n++;
        }
        return;
    }
    /* R435: THE CELL IS 0x80059394 — (int16_t)0x9394 is NEGATIVE (-0x6C6C); lui 0x8006 -> 0x80060000 + signext(0x9394) = 0x80059394. 0x80069394 was a PHANTOM cell for ~10 cycles (sign-extension misread). R430 CTXW hook, repointed: c187
     * verdict: journey provably executes the install store (straight-line,
     * no branches; ResetGlyphBatch called from 0x80037838 = 1 instr later),
     * unloader never ran, no second journey, watcher has 239 spare lines
     * yet the cell reads 0 at the very next dispatch. Either the store
     * never reaches this path (Mac emitted/guarded code differs) or its
     * value differs - this hook names which. */
        if (a == 0x801EF590u) { /* R436 batch-ptr field (ctx+0x38) — THE fault's LW source. Who writes it, when, with what? */
        static int s_btw_n;
        long bw_el = (g_boot_wall_t0 ? (long)(time(NULL) - g_boot_wall_t0) : 0);
        if (s_btw_n < 24)
            fprintf(stderr, "[btw] SW 0x801EF590 val=%08X @t=%lds r31=%08X r16=%08X\n",
                    (unsigned)v, bw_el, (unsigned)r[31], (unsigned)r[16]);
        s_btw_n++;
    }
    if (a >= 0x801EF558u && a < 0x801EF660u) { /* R437 FRCLASH: font-record page guard — record sits inside the field pump's ring span (0x801EABD8-0x801EFBD8); log any post-boot writer */
        static int s_frc_n;
        long fc_el = (g_boot_wall_t0 ? (long)(time(NULL) - g_boot_wall_t0) : 0);
        if (fc_el >= 2 && s_frc_n < 24)
            fprintf(stderr, "[frclash] W32 0x%08X val=%08X @t=%lds r31=%08X r16=%08X\n",
                    (unsigned)a, (unsigned)v, fc_el, (unsigned)r[31], (unsigned)r[16]);
        s_frc_n++;
    }
    if (a == 0x801EF5A4u) { /* R434 mid-block tripwire (SW +0x4C, middle's 5th store) */
        static int s_midw_n;
        long mw_el = (g_boot_wall_t0 ? (long)(time(NULL) - g_boot_wall_t0) : 0);
        if (s_midw_n < 8)
            fprintf(stderr, "[midw] SW 0x801EF5A4 val=%08X @t=%lds r31=%08X r16=%08X\n",
                    (unsigned)v, mw_el, (unsigned)r[31], (unsigned)r[16]);
        s_midw_n++;
    }
    if (a == 0x801FBFF8u || a == 0x801FBFFCu) { /* R439 ROOT-NODE WATCH: every alloc reads root w0/w1 UNCHANGED ([take] #1-#7 all read 0x801FC000/0x80200000) -> the carve's store-back never advances the root -> stale-root double-allocation (record 0x801EF558 handed out twice). WHO (if anyone) writes the root? */
        static int s_rootw_n;
        if (s_rootw_n < 20) {
            long rw_el = (g_boot_wall_t0 ? (long)(time(NULL) - g_boot_wall_t0) : 0);
            uint32_t rw_old = xenolift_mem_read32(a);
            fprintf(stderr, "[rootw] %s 0x%08X: %08X -> %08X @t=%lds r31=%08X r12=%08X r17=%u\n",
                    a == 0x801FBFF8u ? "w0" : "w1", (unsigned)a, (unsigned)rw_old, (unsigned)v,
                    rw_el, (unsigned)r[31], (unsigned)r[12], (unsigned)r[17]);
        }
        s_rootw_n++;
    }
    if (a == 0x80059394u) {
        static int s_ctxw_n;
        long cw_el = (g_boot_wall_t0 ? (long)(time(NULL) - g_boot_wall_t0) : 0);
        if (s_ctxw_n < 16)
            fprintf(stderr, "[ctxw] write32 0x80059394: %08X -> %08X @t=%lds r31=%08X r16=%08X\n",
                    (unsigned)xenolift_mem_read32(0x80059394u), (unsigned)v,
                    cw_el, (unsigned)r[31], (unsigned)r[16]);
        s_ctxw_n++;
    }
    /* R441: HEAP DESCRIPTOR WATCH. R440 carve2 proved the descriptor cell
     * 0x8006FAF0 still holds 0x801EF558 (the LIVE font record) as the free
     * pointer after the record+verdict carves — the advance never moved it
     * (stale-descriptor double-booking). Log EVERY writer of the free-
     * pointer cell (and its flags word 0x8006FAF4) so we learn which store
     * is missing/silenced; the fix then writes the correct next-free value
     * at the right moment. */
    /* R442: FILL-RING SEED WATCH. R441 proof: the carve redirect advanced the
     * free pointer past the record (descw #27/#28) but the movie-era fill
     * ring STILL seeded at 0x801EF3xx and stomped the record ([frclash]
     * LBA 108980 -> 0x801EF334 @t=135s) — the caller stores the ORIGINAL
     * carve result (0x801EF558) into its request/ring cells regardless of
     * the advance-argument redirect. Photograph the writers of the ring
     * target cells (0x8004FE08/FE0C — the [fldpump] fill targets) and the
     * request slot cells (0x80059F10/F14/F18) so the next ship redirects
     * the SEED (the stored result), not the advance argument. */
    if (a == 0x8004FE08u || a == 0x8004FE0Cu || a == 0x8004FE10u) {
        static uint32_t rgn; static uint32_t rgn_0;
        long rg_el = (g_boot_wall_t0 ? (long)(time(NULL) - g_boot_wall_t0) : 0);
        rgn++;
        if (cd_seek_lba < 150u) rgn_0++; /* R512: fresh budget for the LBA-0/directory era — boot consumed the first 32 before this era began */
        if (rgn <= 32u || (rgn % 200u) == 0u
            || (cd_seek_lba < 150u && rgn_0 <= 48u))
            fprintf(stderr, "[ringw] #%u 0x%08X: 0x%08X -> 0x%08X r31=%08X r16=%08X @t=%lds\n",
                    rgn, a, (unsigned)xenolift_mem_read32(a), (unsigned)v,
                    (unsigned)r[31], (unsigned)r[16], rg_el);
    }
    if (a == 0x80028A74u && cd_seek_lba < 150u) { /* R512: LBA-0 era request-issuer — does anyone re-aim FE08 at the new decompress buffer? */
        static uint32_t rsw;
        if (rsw < 24u) { rsw++;
            fprintf(stderr, "[reqsw] R512 fn_80028A74 a0=%08X a1=%08X a2=%08X | FE08=%08X FE0C=%08X FE10=%08X FE34=%08X F10=%08X F14=%08X heap80A4=%08X\n",
                    (unsigned)r[4], (unsigned)r[5], (unsigned)r[6],
                    (unsigned)xenolift_mem_read32(0x8004FE08u), (unsigned)xenolift_mem_read32(0x8004FE0Cu),
                    (unsigned)xenolift_mem_read32(0x8004FE10u), (unsigned)xenolift_mem_read32(0x8004FE34u),
                    (unsigned)xenolift_mem_read32(0x80059F10u), (unsigned)xenolift_mem_read32(0x80059F14u),
                    (unsigned)xenolift_mem_read32(0x801F80A4u));
        }
    }
    if (a == 0x80059F10u || a == 0x80059F14u || a == 0x80059F18u) {
        static uint32_t rqn;
        long rq_el = (g_boot_wall_t0 ? (long)(time(NULL) - g_boot_wall_t0) : 0);
        rqn++;
        if ((v >= 0x80100000u && v < 0x80200000u) && (rqn <= 32u || (rqn % 200u) == 0u))
            fprintf(stderr, "[reqres] #%u 0x%08X: 0x%08X -> 0x%08X r31=%08X r16=%08X @t=%lds\n",
                    rqn, a, (unsigned)xenolift_mem_read32(a), (unsigned)v,
                    (unsigned)r[31], (unsigned)r[16], rq_el);
    }
    if (a == 0x80018088u || a == 0x8001808Cu || a == 0x8001809Cu ||
        a == 0x800180ACu || a == 0x80018098u || a == 0x800180A8u) {
        /* R688 [descw2]: the kernel phase-queue cells. c259 proof: file-14's
         * expansion IS the real window-0 content (dst+0x4000 = real code, the
         * crash window == post-decompress window bit-for-bit) - so the stale
         * table at 0x80077E88 is the TRUE content at the state-1 cb address,
         * and a healthy boot MUST rewrite the cb cell (0x8001809C) before
         * dispatch - or never dispatch through it at all. Watch every write
         * to the request + cb cells: WHO rewrites them, with WHAT value. */
        static uint32_t d2n;
        long d2_el = (g_boot_wall_t0 ? (long)(time(NULL) - g_boot_wall_t0) : 0);
        d2n++;
        if (d2n <= 40u || (d2n % 200u) == 0u)
            fprintf(stderr, "[descw2] #%u queue-cell 0x%08X: 0x%08X -> 0x%08X r31=%08X r16=%08X @t=%lds\n",
                    d2n, a, (unsigned)xenolift_mem_read32(a), (unsigned)v,
                    (unsigned)r[31], (unsigned)r[16], d2_el);
    }
    if (a == 0x8006FAF0u || a == 0x8006FAF4u) {
        static uint32_t dwn;
        long dw_el = (g_boot_wall_t0 ? (long)(time(NULL) - g_boot_wall_t0) : 0);
        dwn++;
        if (dwn <= 40u || (dwn % 200u) == 0u)
            fprintf(stderr, "[descw] #%u %s 0x%08X: 0x%08X -> 0x%08X r31=%08X r16=%08X @t=%lds\n",
                    dwn, a == 0x8006FAF0u ? "FREEPTR" : "FLAGS  ", a,
                    (unsigned)xenolift_mem_read32(a), (unsigned)v,
                    (unsigned)r[31], (unsigned)r[16], dw_el);
    }
    if (a == 0x801EF59Fu || a == 0x801EF5A3u) { /* R434 mid-block tripwire (SB +0x47/+0x4C-family) */
        static int s_midb_n;
        long mb_el = (g_boot_wall_t0 ? (long)(time(NULL) - g_boot_wall_t0) : 0);
        if (s_midb_n < 8)
            fprintf(stderr, "[midw] SB 0x%08X val=%08X @t=%lds r31=%08X r16=%08X\n",
                    (unsigned)a, (unsigned)v, mb_el, (unsigned)r[31], (unsigned)r[16]);
        s_midb_n++;
    }
    /* R433 BYTE-WATCH: the word hook missed a possible SB/SH zeroer - the
     * one 0->0 ctxw line had no context (boot BSS? menu-era? the install
     * with r16=0?). This names the writer for ANY width. */
    if (a >= 0x80059394u && a <= 0x80069397u) {
        static int s_ctxb_n;
        long cb_el = (g_boot_wall_t0 ? (long)(time(NULL) - g_boot_wall_t0) : 0);
        if (s_ctxb_n < 8)
            fprintf(stderr, "[ctxb] byte/half write 0x%08X val=%08X @t=%lds r31=%08X r16=%08X\n",
                    (unsigned)a, (unsigned)v, cb_el, (unsigned)r[31], (unsigned)r[16]);
        s_ctxb_n++;
    }
    /* R192 lzss-guard: block writes past the RAM ceiling while the
     * decompressor is armed — the final-partial-group overrun dies
     * here instead of halting the machine. */
    if (lzss_armed && lzss_exit_target && r[15] != lzss_exit_target) {
        /* R198: SELF-HEALING EXIT TARGET. Cycle-31 proof: the LZSS entry
         * computed the correct exit (dst+word0, e.g. 0x801F34A9) and two
         * streams exited EXACTLY there — but the third stream's r15 was
         * silently changed mid-loop (watchdog r15 = 0x801FBFF8, a heap
         * node address, not the entry target). The core checks
         * (r[5]==r[15]) before every group; a wrong r15 = the exit can
         * never fire = the ~1GB linear runaway. The core itself never
         * writes r15 mid-loop (verified vs original), so re-healing it
         * on every armed store restores exactly the value the core
         * computed at entry — trample-proof finish line. */
        r[15] = lzss_exit_target;
        if (lzss_heal_n < 8) fprintf(stderr, "[lzss-heal] r15 restored 0x%08X -> 0x%08X (exit target)\n",
                                     (unsigned)0, (unsigned)lzss_exit_target);
        lzss_heal_n++;
    }
    if (lzss_armed && a >= 0x80200000u) {
        if (lzss_over_n < 8) {
            fprintf(stderr, "[lzss-guard] suppressed write to 0x%08X (val 0x%08X)\n", a, v);
        }
        lzss_over_n++;
        lzss_last_a = a;
        if ((lzss_over_n & 0xFFF) == 0) {
            fprintf(stderr, "[lzss-runaway] %d ops suppressed, write frontier 0x%08X inpast=%d\n", lzss_over_n, lzss_last_a, lzss_inpast_n);
        }
        return;
    }
    /* R187: CLOBBER GUARD — the big swing. R186 watchers named the writers:
     * the heap walker family (fn_80031C58 et al., R187 sandbox: 0x801FFFB0
     * <- 0x65A2 = chunk-tag bits stomping the display working cell) and
     * fn_8004DEF8 (0x801FFF28 <- 0x09730BD9 garbage) writing through
     * tag-derived computed addresses that land on the STACK REGION
     * [0x801FF000, 0x80200000). The translation is byte-faithful, so on
     * real hardware these computed targets are valid chunk addresses —
     * in our run the heap history divergence (round-2 dump_0=zeros) aims
     * them at the stack. A store into the live stack from these writers
     * clobbers return addresses -> the 0x80200000 jr fault. Guard: block
     * allocator-family stores into the stack region, log loudly. The
     * game continues with an intact stack; the guard is inert for every
     * legitimate store (allocator data lives BELOW 0x801FC000). */
    {
        uint32_t cf = xenolift_ring_n > 0 ? xenolift_ring[(xenolift_ring_n - 1u) % 64u] : 0;
        if (a >= 0x801FF000u && a < 0x80200000u
            && (cf == 0x80031BDCu || cf == 0x80031C58u || cf == 0x80031C2Cu
                || cf == 0x80031DA8u || cf == 0x80031F58u || cf == 0x80031FF8u
                || cf == 0x80031B3Cu || cf == 0x8004DEF8u)) {
            static int cg_n;
            if (cg_n < 64) {
                cg_n++;
                fprintf(stderr, "[clobber-guard] stack-region store 0x%08X <- 0x%08X from fn 0x%08X (%s)\n",
                        a, v, cf,
                        (v >= 0x80010000u && v < 0x80060000u) ? "looks-like-ra" : "data/tag");
            }
            /* R187.1: LOG-ONLY. The first R187 guard BLOCKED these stores and
             * the sandbox showed them to be legitimate register saves at the
             * top of the game's stack (the game sets SP=0x80200000 itself —
             * fn_80019548 symbol). Blocking broke real frames. The tripwire
             * now records the FULL store sequence at the stack frontier so
             * the Mac digest shows the exact writer/value when the ra slot
             * (restored later as 0x80200000) gets its poison — then the fix
             * is a one-liner at the named source. */
        }
    }
    /* R81 poison hunt: the irq-chain walk faulted at 0x8F5A0014 — an
     * entry's +12 field holds 0x8F5A0008 (NOT a file-data constant: the
     * word exists in SLUS at 0x3BD20 as the instruction `lw a0, 8(s6)`).
     * Any store of this exact value names the writer. */
    if (a >= 0x80000080u && a < 0x800000C0u) {
        static int ex_n;
        if (ex_n < 20)
            fprintf(stderr, "[exch] install 0x%08X <- %08X (fn 0x%08X)\n", a, v,
                    xenolift_ring_n > 0 ? xenolift_ring[(xenolift_ring_n - 1u) % 64u] : 0);
        ex_n++;
    }
    if (v == 0x8F5A0008u) {
        uint32_t cf = xenolift_ring_n > 0 ? xenolift_ring[(xenolift_ring_n - 1u) % 64u] : 0;
        fprintf(stderr, "[poison] store 0x%08X <- 8F5A0008 at fn 0x%08X\n", a, cf);
    }
    uint32_t off = xenolift_phys(a);
    if (off >= XENOLIFT_RAM_SIZE) {
        io_log(io_phys(off), 1, v);
        if (io_phys(off) == 0x1F801070) {
            /* I_STAT: writing 1s ACKNOWLEDGES (clears) those interrupts */
            uint32_t cur;
            memcpy(&cur, xenolift_mem + off, 4);
            cur &= ~v;
            memcpy(xenolift_mem + off, &cur, 4);
            return;
        }
        if (io_special_write(io_phys(off), v)) {
            return;
        }
    }
    memcpy(xenolift_mem + off, &v, 4);
}

void xenolift_mem_write16(uint32_t a, uint32_t v)
{
    /* R518 mangleguard (16-bit path): c85 proof — =MANGLE= silent while FE1C
     * still received 0304FE0C at fn 800317E0 => the mangled pointer pairs are
     * stored as HALFWORDS; the R517 write32 guard never sees them. High half
     * of the family = v in [0x0300,0x0400) landing on a word-aligned +2 slot.
     * The full value is never a usable pointer in this address space. Drop +
     * receipt + continue (R487/R488 bus-error semantics). */
    if (a >= 0x80010000u && a < 0x80200000u && (a & 3u) == 2u
        && v >= 0x0300u && v < 0x0400u) {
        static uint32_t mg16_last; static int mg16_n; static uint32_t mg16_tot;
        if ((a != mg16_last || mg16_n < 4) && mg16_tot < 24u) {
            mg16_tot++;
            fprintf(stderr, "[mangleguard] R518 hw mangle a=%08X val=%04X dropped (r31=%08X) — chain preserved\n",
                    (unsigned)a, (unsigned)(v & 0xFFFFu), (unsigned)r[31]);
            mg16_last = a; mg16_n++;
        }
        return;
    }

    /* R488: garbage-family WRITE drop (16-bit path) — c54 proof: the SH
     * header store in fn_80039044+320 (0xA106BDD0 = 0x8006BE00 - 0xDF000030)
     * faulted here; R487's drop only covered write32. Real HW eats the bus
     * error; we drop + receipt + continue. */
    if ((a >= 0x80200000u) || (a < 0x80000000u && a > 0x00100000u
          && !(a >= 0x1F800000u && a <= 0x1FAF0000u)) || (a >= 0xBFC10000u)) {
        static uint32_t dw16_last; static int dw16_n; static uint32_t dw16_tot;
        if ((a != dw16_last || dw16_n < 4) && dw16_tot < 24u) {
            dw16_tot++;
            fprintf(stderr, "[wdrop] garbage write16 0x%08X val=%08X dropped (r31=%08X) — continuing\n",
                    (unsigned)a, (unsigned)v, (unsigned)r[31]);
            dw16_last = a; dw16_n++;
        }
        return;
    }
    if (a >= 0x801EF558u && a < 0x801EF660u) { /* R437 frclash */
        static int s_frc16_n;
        long f6_el = (g_boot_wall_t0 ? (long)(time(NULL) - g_boot_wall_t0) : 0);
        if (f6_el >= 5 && s_frc16_n < 12)
            fprintf(stderr, "[frclash] W16 0x%08X val=%08X @t=%lds r31=%08X\n",
                    (unsigned)a, (unsigned)v, f6_el, (unsigned)r[31]);
        s_frc16_n++;
    }
    /* R433 ctxb16 */
    if (a >= 0x80059394u && a <= 0x80069397u) {
        static int s_ctxb16_n;
        long c6_el = (g_boot_wall_t0 ? (long)(time(NULL) - g_boot_wall_t0) : 0);
        if (s_ctxb16_n < 8)
            fprintf(stderr, "[ctxb] write16 0x%08X val=%08X @t=%lds r31=%08X r16=%08X\n",
                    (unsigned)a, (unsigned)v, c6_el, (unsigned)r[31], (unsigned)r[16]);
        s_ctxb16_n++;
    }
    /* R192 lzss-guard: block writes past the RAM ceiling while the
     * decompressor is armed — the final-partial-group overrun dies
     * here instead of halting the machine. */
    if (lzss_armed && a >= 0x80200000u) {
        if (lzss_over_n < 8) {
            fprintf(stderr, "[lzss-guard] suppressed write to 0x%08X (val 0x%08X)\n", a, v);
        }
        lzss_over_n++;
        lzss_last_a = a;
        if ((lzss_over_n & 0xFFF) == 0) {
            fprintf(stderr, "[lzss-runaway] %d ops suppressed, write frontier 0x%08X inpast=%d\n", lzss_over_n, lzss_last_a, lzss_inpast_n);
        }
        return;
    }
    uint32_t off = xenolift_phys(a);
    if (off >= XENOLIFT_RAM_SIZE) {
        io_log(io_phys(off), 1, v);
        /* 16-bit GP1 writes: zero-extended to a full command word */
        if (io_special_write(io_phys(off), (uint32_t)(v & 0xFFFFu))) {
            return;
        }
    }
    uint16_t h = (uint16_t)v;
    memcpy(xenolift_mem + off, &h, 2);
}

/* R658: transition-era flag — set when the f15 field request is stamped. */
uint32_t g_statshield_era = 0;

/* R660 [phase-bulk]: c230 — the f15 request stamped, the game streamed 8
 * sectors natively, then the boot concluded @14s BEFORE the alarm-side R651
 * bulk (1s cadence + settle) could fire — death state FDF8=75796, exactly
 * the posture the bulk completes. Anti-race doctrine, 3rd application: the
 * bulk also fires from the dispatcher-family entry hook (main thread), so
 * the install completes in the same breath as the read that needs it. */
static uint32_t xenolift_f15_bulk(const char *tag)
{
    /* R663: family-wide + in-flight-only (never fire at the full-remaining
     * posture — the native FILE-CB walk must run its bookkeeping first, its
     * finalize chain is what advances the game's own request queue). */
    static const uint32_t r663_sz[19] = {
        0u,0u,0u,0u,0u,0u,0u,0u,0u,0u,0u,0u,0u,0u,0u,92180u,166564u,70944u,14360u
    };
    uint32_t f15c = xenolift_mem_read32(0x80059F0Cu);
    uint32_t f15r = xenolift_mem_read32(0x8004FDF8u);
    if (f15c < 15u || f15c > 18u || f15r == 0u) return 0u;
    if (f15r >= r663_sz[f15c]) return 0u;   /* full posture = walk not started, wait */
    uint32_t lba = xenolift_mem_read32(0x8004FE04u);
    uint32_t dst = xenolift_mem_read32(0x8004FE08u);
    uint32_t rem = f15r;
    int nsec = 0;
    while (rem > 0u && nsec < 64) {
        unsigned char sbuf[2048];
        if (disc_read_lba(lba, sbuf) != 0) break;
        uint32_t chunk = (rem < 2048u) ? rem : 2048u;
        for (uint32_t i = 0u; i + 4u <= chunk; i += 4u) {
            uint32_t w;
            memcpy(&w, sbuf + i, sizeof(w));
            xenolift_mem_write32(dst + i, w);
        }
        lba += 1u; dst += 0x800u;
        rem = (rem > 2048u) ? (rem - 2048u) : 0u;
        nsec++;
    }
    xenolift_mem_write32(0x8004FE04u, lba);
    xenolift_mem_write32(0x8004FE08u, dst);
    xenolift_mem_write32(0x8004FDF8u, rem);
    if (rem == 0u) {
        xenolift_mem_write32(0x8004FDFCu, 0u);
        xenolift_mem_write32(0x8004FE1Cu, 6u);
    }
    fprintf(stderr, "[mtrans] R660 f15 bulk (%s): %d sectors LBA %u..%u, FDF8 %u -> %u%s\n",
            tag, nsec, lba - (uint32_t)nsec, (lba > 0u ? lba - 1u : 0u), f15r, rem,
            rem == 0u ? " DONE posture set" : " (partial)");
    return 1u;
}
void xenolift_mem_write8(uint32_t a, uint32_t v)
{
    /* R658 statecell shield (c228): after the field mount COMPLETED (walk to
     * 8020F724, done posture, cur=1 held 8s) the game's own number formatter
     * (fn 80040034 family) printed "00000000" ASCII through a torn buffer
     * pointer - byte 0x30 writes landed across the live state cells
     * (92C0/FAEC/59F0C/59F10/FE04/FDF8/FE1C/FE20/6A488/6A494/6A498) and the
     * dispatcher read 0x30303030 as its phase -> boot unwound @t=28s.
     * The print is a debug overlay (cosmetic per triage policy); the cells
     * are the mission. Divert ASCII '0' writes to these cells in the
     * transition era (drop + receipt, mangleguard precedent). */
    if (g_statshield_era > 0u && v == 0x30u
        && ((a >= 0x8004FE04u && a < 0x8004FE24u)
         || (a >= 0x800592C0u && a < 0x800592E0u)
         || (a >= 0x80059F0Cu && a < 0x80059F14u)
         || (a >= 0x8005FAECu && a < 0x8005FAF0u)
         || (a >= 0x8006A488u && a < 0x8006A49Cu))) {
        static uint32_t scs_last; static uint32_t scs_n;
        if (scs_n < 96u) {
            scs_n++;
            if (a != scs_last)
                fprintf(stderr, "[statshield] R658: ASCII '0' write to state cell %08X dropped (torn debug-print ptr; r31=%08X) #%u\n",
                        (unsigned)a, (unsigned)r[31], scs_n);
            scs_last = a;
        }
        return;
    }
    /* R518 mangleguard (8-bit path): byte 0x03 written into the MSB slot
     * ((a&3)==3) of a pointer word — byte-granular variant of the family. */
    if (a >= 0x80010000u && a < 0x80200000u && (a & 3u) == 3u && v == 0x03u) {
        static uint32_t mg8_last; static int mg8_n; static uint32_t mg8_tot;
        if ((a != mg8_last || mg8_n < 4) && mg8_tot < 24u) {
            mg8_tot++;
            fprintf(stderr, "[mangleguard] R518 byte mangle a=%08X val=03 dropped (r31=%08X) — chain preserved\n",
                    (unsigned)a, (unsigned)r[31]);
            mg8_last = a; mg8_n++;
        }
        return;
    }

    /* R488: garbage-family WRITE drop (8-bit path) — same predicate. */
    if ((a >= 0x80200000u) || (a < 0x80000000u && a > 0x00100000u
          && !(a >= 0x1F800000u && a <= 0x1FAF0000u)) || (a >= 0xBFC10000u)) {
        static uint32_t dw8_last; static int dw8_n; static uint32_t dw8_tot;
        if ((a != dw8_last || dw8_n < 4) && dw8_tot < 24u) {
            dw8_tot++;
            fprintf(stderr, "[wdrop] garbage write8 0x%08X val=%08X dropped (r31=%08X) — continuing\n",
                    (unsigned)a, (unsigned)v, (unsigned)r[31]);
            dw8_last = a; dw8_n++;
        }
        return;
    }
    if (a >= 0x801EF558u && a < 0x801EF660u) { /* R437 frclash */
        static int s_frc8_n;
        long f8_el = (g_boot_wall_t0 ? (long)(time(NULL) - g_boot_wall_t0) : 0);
        if (f8_el >= 5 && s_frc8_n < 12)
            fprintf(stderr, "[frclash] W8 0x%08X val=%08X @t=%lds r31=%08X\n",
                    (unsigned)a, (unsigned)v, f8_el, (unsigned)r[31]);
        s_frc8_n++;
    }
    /* R433 ctxb8 */
    if (a >= 0x80059394u && a <= 0x80069397u) {
        static int s_ctxb8_n;
        long c8_el = (g_boot_wall_t0 ? (long)(time(NULL) - g_boot_wall_t0) : 0);
        if (s_ctxb8_n < 8)
            fprintf(stderr, "[ctxb] write8 0x%08X val=%08X @t=%lds r31=%08X r16=%08X\n",
                    (unsigned)a, (unsigned)v, c8_el, (unsigned)r[31], (unsigned)r[16]);
        s_ctxb8_n++;
    }
    /* R192 lzss-guard: block writes past the RAM ceiling while the
     * decompressor is armed — the final-partial-group overrun dies
     * here instead of halting the machine. */
    if (lzss_armed && a >= 0x80200000u) {
        if (lzss_over_n < 8) {
            fprintf(stderr, "[lzss-guard] suppressed write to 0x%08X (val 0x%08X)\n", a, v);
        }
        lzss_over_n++;
        lzss_last_a = a;
        if ((lzss_over_n & 0xFFF) == 0) {
            fprintf(stderr, "[lzss-runaway] %d ops suppressed, write frontier 0x%08X inpast=%d\n", lzss_over_n, lzss_last_a, lzss_inpast_n);
        }
        return;
    }
    uint32_t off = xenolift_phys(a);
    if (off >= XENOLIFT_RAM_SIZE) {
        io_log(io_phys(off), 1, v);
        if (io_special_write(io_phys(off), v)) {
            return;
        }
    }
    xenolift_mem[off] = (uint8_t)v;
}

/* called when the recompiled code hits something not yet implemented.
 * prints what it was plus a register dump, then stops the run cleanly. */
static void dump_state(void)
{
    for (int i = 0; i < 32; i += 4) {
        fprintf(stderr,
                "  r%-2d = 0x%08X   r%-2d = 0x%08X   r%-2d = 0x%08X   r%-2d = 0x%08X\n",
                i, r[i], i + 1, r[i + 1], i + 2, r[i + 2], i + 3, r[i + 3]);
    }
    fprintf(stderr, "  hi  = 0x%08X   lo  = 0x%08X\n", hi, lo);
    fprintf(stderr, "[h2tbl] arc-state table @0x800188F4 (real base, R264):");
    for (int ti = 0; ti < 13; ti++)
        fprintf(stderr, " [%d]=%08X", ti, xenolift_mem_read32(0x800188F4u + (uint32_t)ti * 4u));
    fprintf(stderr, "\n");
}

static void dump_driver_state(const char *why)
{
    fprintf(stderr, "[state %s] slot=%02X %02X %02X  flags=%02X %02X %02X  "
                    "type=%02X opflag=%04X  result7=[%02X %02X %02X %02X %02X %02X %02X]\n",
            why,
            xenolift_mem[0x56788], xenolift_mem[0x56789], xenolift_mem[0x5678A],
            xenolift_mem[0x564B8], xenolift_mem[0x564B9], xenolift_mem[0x564BA],
            xenolift_mem[0x564C9], *(uint16_t *)(xenolift_mem + 0x578A6),
            xenolift_mem[0x5A210], xenolift_mem[0x5A211], xenolift_mem[0x5A212],
            xenolift_mem[0x5A213], xenolift_mem[0x5A214], xenolift_mem[0x5A215],
            xenolift_mem[0x5A216]);
}

/* R238 file-scope RAM reader for the halt object dump (clang has no
 * nested functions — cycle-24 Mac compile failure taught this). */
static uint32_t xenolift_halt_rd32(uint32_t a)
{
    if (a + 4 > XENOLIFT_RAM_SIZE) return 0;
    return (uint32_t)xenolift_mem[a] | ((uint32_t)xenolift_mem[a+1] << 8)
        | ((uint32_t)xenolift_mem[a+2] << 16) | ((uint32_t)xenolift_mem[a+3] << 24);
}

/* R241 kernel-data boot baseline (0x80056400-0x80058000) for the halt diff */
uint8_t xenolift_dp_base[0x1C00]; int xenolift_dp_snap = 0;
/* R244: shared last-known-good stack pointer — the R233b tag-strip and the
 * R243 kernel-data spguard both restore to THIS (a REAL recent stack value)
 * instead of synthetic addresses (0x80000018-class floors underflow on the
 * first push — cycle-29 crash exactly there: 0x80000018-0x40 -> 0x7FFFFFD8). */
uint32_t xenolift_last_good_sp = 0x80200000;

static void halt_report(const char *what, uint32_t detail)
{
    dump_driver_state("halt");
    fprintf(stderr, "\n[xenolift] HALT: %s (detail 0x%08X)\n", what, detail);
    {   /* R241 [staldiff]: boot-baseline diff of the kernel data window —
     * every cell that diverged from the boot snapshot (except the three
     * healed static cells) names a live corruption write for the fix list. */
        if (xenolift_dp_snap) {
            int dn = 0;
            for (uint32_t off = 0; off < 0x1C00 && dn < 16; off += 4) {
                uint32_t live = (uint32_t)xenolift_mem[0x56400+off] | ((uint32_t)xenolift_mem[0x56401+off] << 8)
                    | ((uint32_t)xenolift_mem[0x56402+off] << 16) | ((uint32_t)xenolift_mem[0x56403+off] << 24);
                uint32_t base = (uint32_t)xenolift_dp_base[off] | ((uint32_t)xenolift_dp_base[off+1] << 8)
                    | ((uint32_t)xenolift_dp_base[off+2] << 16) | ((uint32_t)xenolift_dp_base[off+3] << 24);
                if (live != base) {
                    fprintf(stderr, "[staldiff] 0x%08X: 0x%08X -> 0x%08X\n", 0x80056400u + off, base, live);
                    dn++;
                }
            }
            if (!dn) fprintf(stderr, "[staldiff] kernel data window CLEAN vs boot baseline\n");
        }
    }
    {   /* R235: TARGET SCAN. Cycle-21's movie-player halt = unresolved indirect
         * jump to 0x00800000 = the poison stack-top 0x80800000 with the top
         * byte stripped (0x80800000 & 0x00FFFFFF == 0x00800000). Scan RAM for
         * the exact target AND its KSEG0-restored variant AND the 24-bit-mask
         * class — the cell holding it names the producer, then the next
         * cycle's store-watcher names the writer. Budget 12 hits each. */
        static const uint32_t vars[3] = { 1, 0, 0 };
        uint32_t needles[3];
        /* R250: detail==0 means "no meaningful target" - scanning all RAM
         * for the literal 0 produced 14 noise hits (cycle-2 digest). */

        needles[0] = detail;                       /* exact target */
        needles[1] = detail | 0x80000000u;         /* KSEG0-restored */
        needles[2] = (detail < 0x01000000u && detail != 0)
            ? 0x80000000u | detail : 0xFFFFFFFFu;  /* skip if same */
        (void)vars;
        {   /* R237: the fatal jalr (decoded from disc @0x80044F48-5C) reads
         * *( *(0x800568C8) + 0x10 ) as a function pointer — dump the driver
         * object at halt so the +0x10 callback slot and its siblings are
         * visible, plus the source cell and its writers over time.
         * R238: the reader helper is at FILE SCOPE (clang rejects nested
         * function definitions — the cycle-24 Mac compile failure class). */
            uint32_t obj = xenolift_halt_rd32(0x568C8);
            fprintf(stderr, "[objdump] drv-ptr cell 0x800568C8 = 0x%08X\n", obj);
            if (obj >= 0x80000000u && obj < 0x80000000u + XENOLIFT_RAM_SIZE && (obj & 3u) == 0u) {
                for (int q = 0; q < 4; q++) {
                    fprintf(stderr, "[objdump] obj+%02X:", q * 16);
                    for (int r = 0; r < 4; r++)
                        fprintf(stderr, " %08X", xenolift_halt_rd32((obj - 0x80000000u) + q*16 + r*4));
                    fprintf(stderr, "\n");
                }
            }
        }
        for (int v = 0; v < 3; v++) {
            if (needles[v] == 0u) continue; /* R250: zero needle = noise */
            if (needles[v] == 0xFFFFFFFFu && v == 2) break;
            if (v > 0 && needles[v] == needles[v - 1]) break;
            int found = 0;
            for (uint32_t off = 0; off + 4 <= XENOLIFT_RAM_SIZE && found < 12; off += 4) {
                uint32_t w = xenolift_mem[off] | ((uint32_t)xenolift_mem[off+1] << 8)
                    | ((uint32_t)xenolift_mem[off+2] << 16) | ((uint32_t)xenolift_mem[off+3] << 24);
                if (w == needles[v]) {
                    uint32_t base = 0x80000000u + off;
                    fprintf(stderr, "[halt-scan] 0x%08X at RAM 0x%08X nb[%08X %08X %08X] next[%08X %08X]\n",
                            w, base,
                            (off >= 8) ? (xenolift_mem[off-8] | ((uint32_t)xenolift_mem[off-7] << 8)
                                | ((uint32_t)xenolift_mem[off-6] << 16) | ((uint32_t)xenolift_mem[off-5] << 24)) : 0,
                            (off >= 4) ? (xenolift_mem[off-4] | ((uint32_t)xenolift_mem[off-3] << 8)
                                | ((uint32_t)xenolift_mem[off-2] << 16) | ((uint32_t)xenolift_mem[off-1] << 24)) : 0,
                            (off + 12 <= XENOLIFT_RAM_SIZE) ? (xenolift_mem[off+8] | ((uint32_t)xenolift_mem[off+9] << 8)
                                | ((uint32_t)xenolift_mem[off+10] << 16) | ((uint32_t)xenolift_mem[off+11] << 24)) : 0,
                            (off + 16 <= XENOLIFT_RAM_SIZE) ? (xenolift_mem[off+12] | ((uint32_t)xenolift_mem[off+13] << 8)
                                | ((uint32_t)xenolift_mem[off+14] << 16) | ((uint32_t)xenolift_mem[off+15] << 24)) : 0,
                            (off + 20 <= XENOLIFT_RAM_SIZE) ? (xenolift_mem[off+16] | ((uint32_t)xenolift_mem[off+17] << 8)
                                | ((uint32_t)xenolift_mem[off+18] << 16) | ((uint32_t)xenolift_mem[off+19] << 24)) : 0);
                    found++;
                }
            }
            if (!found) fprintf(stderr, "[halt-scan] 0x%08X NOT in RAM (computed in-register)\n", needles[v]);
        }
    }
    g_exit_why = "halt-scan";
    dump_state();
    fprintf(stderr, "[xenolift] this is expected in early phases — it tells us what to build next.\n");
    exit(0);
}

/* the game touched an address that isn't RAM — hardware registers,
 * scratchpad, or BIOS. Report exactly which address; that's the next
 * thing to emulate. */
extern uint32_t xenolift_ring[64]; extern int xenolift_ring_n; /* R79 */
void xenolift_cop_stub(uint32_t word);
void xenolift_cop0_exception(uint32_t bad_vaddr, uint32_t fault_pc_approx);
void xenolift_io_fault(uint32_t a)
{
    static int s_fault_no; int fk_no = ++s_fault_no; /* R425 (c182): menu-era recovered faults run first; the digest must prefer the LAST fault */
    /* R188: FAULT-MOMENT REGISTER DUMP. Cycles 19-21 pinned the fault to
     * the 0x80032E90 chunk (the unpack push, between XTRACE and the walker
     * dispatch) — the original code there is: sw ra,-8(sp); sw a0,-4(sp);
     * addiu sp,sp,-8; jal walker; DELAY lw a0,+0(a0). The only memory op =
     * the delay load through a0. If a0 is garbage here, the load IS the
     * fault. Print the live registers AT the fault instant — one digest
     * then shows which register fed the poison (a0 = arg chain, sp = stack
     * drift, ra = frame slot) and the fix is at the named source. */
    fprintf(stderr, "[faultregs] fault#%d a(target)=0x%08X r4(a0)=0x%08X r5=0x%08X r6=0x%08X r29(sp)=0x%08X r30(fp)=0x%08X r31(ra)=0x%08X r17=0x%08X r21=0x%08X\n", fk_no,
            a, r[4], r[5], r[6], r[29], r[30], r[31], r[17], r[21]);
    /* R191: full file — which register(s) equal the fault target names the
     * faulting instruction's base register (v0-family = the alloc return). */
    fprintf(stderr, "[faultregs2] r2=%08X r3=%08X r7=%08X r8=%08X r9=%08X r10=%08X r11=%08X r12=%08X r13=%08X r14=%08X r15=%08X r16=%08X r18=%08X r19=%08X r20=%08X r22=%08X r23=%08X r24=%08X r25=%08X r26=%08X r27=%08X r28=%08X\n",
            r[2], r[3], r[7], r[8], r[9], r[10], r[11], r[12], r[13], r[14], r[15], r[16], r[18], r[19], r[20], r[22], r[23], r[24], r[25], r[26], r[27], r[28]);
    /* R419: fault-time fd/staging state — on a CRASH the park never runs,
     * so the field-era crash kit had no kernel request state. The stale-
     * scratch theory (c176: staging head 0x7178 = boot-era stamp, NO field
     * writer ever) says the field module decompressed stale data because
     * the gate cell it checks was satisfied by the boot value. Dump the
     * in-flight request + staging verdict AT the fault instant. */
    {
        long fk_el = (long)(time(NULL) - g_boot_wall_t0);
        fprintf(stderr, "[fkfd] t=%lds seek=%u sched=%u pend=%u arm1=%u last_cmd=%02X data_n=%u FE04=%08X FE08=%08X FE0C=%08X FE10=%08X FDF8=%08X FDE4=%08X FDE8=%08X FE1C=%08X FE20=%08X\n",
                fk_el, cd_seek_lba, cd_scheduled, cd_pending, cd_arm_int1_pending, cd_last_cmd, cd_data_n,
                xenolift_mem_read32(0x8004FE04u), xenolift_mem_read32(0x8004FE08u),
                xenolift_mem_read32(0x8004FE0Cu), xenolift_mem_read32(0x8004FE10u),
                xenolift_mem_read32(0x8004FDF8u), xenolift_mem_read32(0x8004FDE4u),
                xenolift_mem_read32(0x8004FDE8u), xenolift_mem_read32(0x8004FE1Cu),
                xenolift_mem_read32(0x8004FE20u));
        fprintf(stderr, "[fkstg] staging head@800AFC98=%08X w4=%08X w8=%08X wC=%08X | ring@801EABD8=%08X | node59F10=%08X/%08X | node59F08=%08X/%08X\n",
                xenolift_mem_read32(0x800AFC98u), xenolift_mem_read32(0x800AFC9Cu),
                xenolift_mem_read32(0x800AFCA0u), xenolift_mem_read32(0x800AFCA4u),
                xenolift_mem_read32(0x801EABD8u),
                xenolift_mem_read32(0x80059F10u), xenolift_mem_read32(0x80059F14u),
                xenolift_mem_read32(0x80059F08u), xenolift_mem_read32(0x80059F0Cu));
    { /* R421: guest stack scan at fault - kernel-text words between sp and
       * stack top name the crash-path caller chain (dispatch history cannot:
       * the field wrapper enters the LZSS loop mid-body, skipping probes). */
        uint32_t rsp = r[29];
        { /* R438: full font-record hexdump at fault — intact boot fields vs garbage pattern names the writer */
        uint32_t fkb = xenolift_mem_read32(0x80059394u);
        if (fkb >= 0x80000000u && fkb < 0x80200000u) {
            for (int dq = 0; dq < 8; dq++) {
                fprintf(stderr, "[recdump] +%02X: %08X %08X %08X %08X %08X %08X %08X %08X\n",
                        dq * 32,
                        xenolift_mem_read32(fkb + dq*32 + 0), xenolift_mem_read32(fkb + dq*32 + 4),
                        xenolift_mem_read32(fkb + dq*32 + 8), xenolift_mem_read32(fkb + dq*32 + 12),
                        xenolift_mem_read32(fkb + dq*32 + 16), xenolift_mem_read32(fkb + dq*32 + 20),
                        xenolift_mem_read32(fkb + dq*32 + 24), xenolift_mem_read32(fkb + dq*32 + 28));
            }
        }
    }
    fprintf(stderr, "[fkctx] fault#%d ctx-cell(59394-REAL)=%08X ctx+38=%08X ctx+0=%08X ctx+20=%08X ctx+30=%08X | (R423: batch ptr LW(ctx+0x38) feeds the faulting packet store)\n",
                fk_no, xenolift_mem_read32(0x80059394u),
                (xenolift_mem_read32(0x80059394u) >= 0x80000000u && xenolift_mem_read32(0x80059394u) < 0x80200000u) ? xenolift_mem_read32(xenolift_mem_read32(0x80059394u) + 0x38u) : 0xDEAD0001u,
                (xenolift_mem_read32(0x80059394u) >= 0x80000000u && xenolift_mem_read32(0x80059394u) < 0x80200000u) ? xenolift_mem_read32(xenolift_mem_read32(0x80059394u) + 0x00u) : 0xDEAD0001u,
                (xenolift_mem_read32(0x80059394u) >= 0x80000000u && xenolift_mem_read32(0x80059394u) < 0x80200000u) ? xenolift_mem_read32(xenolift_mem_read32(0x80059394u) + 0x20u) : 0xDEAD0001u,
                (xenolift_mem_read32(0x80059394u) >= 0x80000000u && xenolift_mem_read32(0x80059394u) < 0x80200000u) ? xenolift_mem_read32(xenolift_mem_read32(0x80059394u) + 0x30u) : 0xDEAD0001u);
    { /* R424 (c181): HOST BACKTRACE AT GUEST FAULT. The translated guest
         * functions carry real host symbols - the C call stack names the
         * exact emitted function performing the bad access (fkctx ctx-cell=0
         * yet crash regs imply a live context: register inference has hit its
         * resolution limit; the host frames settle it). Same pattern as the
         * R365 watchdog backtrace, non-signal context so fprintf is safe. */
        void *bt[24];
        int n = backtrace(bt, 24);
        char **syms = backtrace_symbols(bt, n);
        fprintf(stderr, "[fkhbt] fault#%d guest-fault host backtrace (%d frames):\n", fk_no, n);
        for (int i = 0; i < n && i < 24; i++) fprintf(stderr, "  %s\n", syms ? syms[i] : "?");
        free(syms);
    }
                fprintf(stderr, "[fkstk] sp=%08X scan:", rsp);
        if (rsp >= 0x80000000u && rsp < 0x80200000u) {
            int found = 0;
            uint32_t a2 = rsp & ~3u;
            while (a2 + 4 <= 0x80200000u && (a2 - (rsp & ~3u)) < 0x200u) {
                uint32_t w = xenolift_mem_read32(a2);
                if (w >= 0x80010000u && w < 0x80050000u) {
                    fprintf(stderr, " [%08X]=%08X", a2, w);
                    if (++found >= 24) break;
                }
                a2 += 4u;
            }
        }
        fprintf(stderr, "\n");
    }
    }
    /* R169: RAM-END JUMP CLASS -> kernel exception recovery. Cycle-4 crash:
     * fetch epilogue restored a garbage ra (0x80200000 = RAM frontier) and
     * jumped; we HALTed. Real hardware would raise a CPU exception and the
     * kernel's own recovery (SetCustomExitFromException @0x800578DC,
     * confirmed live in =GATE=) would restart the boot — the kernel is
     * DESIGNED for this. Route the fault through the kernel's exception
     * exit instead of dying; if the handler can't take it, fall through to
     * the normal HALT. Budget: 8 recoveries per run. */
    /* R170: generalize to the COMPUTED-GARBAGE family. Cycle-5 proof:
     * R169's recovery WORKED — kernel restarted via its own exit and ran
     * DEEPER than ever (boot-main 0x800197BC -> installer fn_800324B8 ->
     * UnpackCompressedHeapBlock fn_80032E88 = LZSS heap-block decode,
     * then a sign-extended bad target 0xFFFF93D4 = out-of-range LZSS
     * back-reference offset. PS1 has no MMU: real HW -> CPU exception ->
     * kernel recovery. Family = anything outside RAM AND outside the
     * plausible hardware districts (0x1F800000-0x1FAF0000 registers,
     * 0xBFC00000 BIOS). Plausible-hardware faults still HALT = the
     * "build next hardware" signal. Budget 16. */
    int garbage_addr = (a >= 0x80200000u)
                    || (a < 0x80000000u && a > 0x00100000u
                        && !(a >= 0x1F800000u && a <= 0x1FAF0000u))
                    || (a >= 0xBFC10000u);
    if (garbage_addr) {
        static int recoveries;
        static uint32_t last_fault; static int last_fault_n;
        /* R171: ping-pong guard — cycle-6 showed the kernel's own handler
         * faulting on the SAME address after recovery (handler reads its
         * exception-state cells, finds them unset in our HLE, faults again).
         * Two hits on the same address = stop routing, HALT honestly. */
        /* R493: FRONTIER-RECORD REPAIR. If this fault is the heap
         * walker following a poisoned next out of a frontier record
         * (fault addr == r[4]-4, r[4] not in RAM, node r[10] is one of
         * the known frontier cells), reroute the record's next to the
         * heap-top terminator (ROOTW: [0x801FBFF8]=0x801FC000,
         * [0x801FBFFC]=0x80200000 — the walk then reads the RAM-top
         * end marker and terminates) instead of the void. The boot
         * retries the step after recovery, so the repaired walk must
         * succeed on the retry. */
        {
            static uint32_t r493_fix_n;
            if (r493_fix_n < 6u
                && a + 4u == r[4]
                && r[4] != 0x80200000u
                && (r[4] >= 0x80200000u || (r[4] < 0x80000000u && r[4] > 0x00100000u))
                && r[10] >= 0x80060000u && r[10] < 0x801FC000u
                && (r[10] == 0x8007EBE8u || r[10] == 0x800A49E0u || r[10] == 0x800AA6A8u)) {
                r493_fix_n++;
                fprintf(stderr, "[frontfix] R493 frontier record 0x%08X next 0x%08X POISONED (walk would read [next-4]) - rerouting to heap-top terminator 0x801FC000 (fix %u/6)\n",
                        r[10], r[4], r493_fix_n);
                *(uint32_t *)(xenolift_mem + (r[10] - 0x80000000u)) = 0x801FC000u;
                last_fault = 0u; last_fault_n = 0; /* repaired record must not ping-pong-halt */
            }
        }
        if (a == last_fault) last_fault_n++; else { last_fault = a; last_fault_n = 1; }
        if (last_fault_n >= 2) {
            fprintf(stderr, "[fault] ping-pong on 0x%08X — kernel handler also faults; halting for honest analysis\n", a);
        } else if (recoveries < 16) {
            recoveries++;
            fprintf(stderr, "[fault] computed-garbage address 0x%08X — routing to kernel exception exit 0x800578DC (recovery %d/16)\n",
                    a, recoveries);
            /* R186: RECOVERY REMOVED — the ghost unmasked. The custom
             * exception exit 0x800578DC sits INSIDE the EXE text bounds
             * (t_addr 0x80019524, size 0x49800) but the ORIGINAL FILE HAS
             * 400+ WORDS OF ZEROS THERE, and no patcher exists in the
             * binary (zero lui 0x8005/ori 0x78xx pairs). On real hardware
             * those faults never happen, so the never-populated stub never
             * runs. Every R169+ "recovery" dispatched a NOP-slide through
             * the blank page and MANUFACTURED the 0xFFFF93D4 halt. Set the
             * honest exception context (for the record) and HALT with the
             * real fault — the true original fault is a return address
             * clobbered on the stack by an earlier wild write, which the
             * R186 stackclobber watcher now names. */
            xenolift_cop0_exception(a, 0x80032EB4u);
        }
    }
    gpu_dump_capture(); /* R125: capture survives any halt path */
    fprintf(stderr, "\n[xenolift] HALT: address outside RAM and the register district: 0x%08X\n", a);
    fprintf(stderr, "[xenolift] (PS1 hardware registers live around 0x1F80xxxx-0x1FAFxxxx;\n"
                    " the scratchpad is 0x1F800000-0x1F8003FF; BIOS is 0xBFC00000.)\n");
    {   /* R79: dispatch ring — the call path into this fault */
        int i, n = xenolift_ring_n, first = (n > 64) ? n - 64 : 0;
        /* R176: cycle-11 decode — decompressors VINDICATED (reference
         * decodes match live RAM byte-for-byte for streams 0/1). The crash =
         * Unpack heap-alloc with size LW(ptr)=0xC2C0CBA5 from some block.
         * Scan RAM for the poison word at halt so its home block is named. */
        {
            uint32_t needle = 0xC2C0CBA5u;
            int found = 0;
            for (uint32_t off = 0; off + 4 <= XENOLIFT_RAM_SIZE; off += 4) {
                uint32_t w = xenolift_mem[off] | ((uint32_t)xenolift_mem[off+1] << 8)
                    | ((uint32_t)xenolift_mem[off+2] << 16) | ((uint32_t)xenolift_mem[off+3] << 24);
                if (w == needle && found < 8) {
                    fprintf(stderr, "[fault] poison word 0x%08X at RAM 0x%08X\n", needle, 0x80000000u + off);
                    found++;
                }
            }
            if (!found) fprintf(stderr, "[fault] poison word 0x%08X NOT in RAM (computed, not stored)\n", needle);
        }
        fprintf(stderr, "[fault] last %d dispatches:\n", n - first);
        for (i = first; i < n; i++)
            fprintf(stderr, "[fault]   #%-3d 0x%08X\n", i, xenolift_ring[i % 64]);
    }
    {   /* R79: interrupt-handler chain at 0x80059410 — head +10 entries */
        uint32_t q, words[4]; int i, ok;
        memcpy(&q, xenolift_mem + 0x59410, 4);
        fprintf(stderr, "[fault] irq-chain head 0x80059410=0x%08X (walk start)\n", q);
        for (i = 0; i < 10; i++) {
            if (q < 0x80000000u || q >= 0x80200000u) {
                fprintf(stderr, "[fault]   entry[%d] 0x%08X (outside RAM — chain broken here)\n", i, q);
                break;
            }
            ok = 1;
            for (int j = 0; j < 4; j++) {
                memcpy(&words[j], xenolift_mem + (q - 0x80000000u) + j*4, 4);
                if (q - 0x80000000u + j*4 >= 0x200000u) ok = 0;
            }
            if (!ok) { fprintf(stderr, "[fault]   entry[%d] 0x%08X (bad)\n", i, q); break; }
            fprintf(stderr, "[fault]   entry[%d] 0x%08X: +0=%08X +4=%08X +8=%08X +12=%08X\n",
                    i, q, words[0], words[1], words[2], words[3]);
            uint32_t nx;
            memcpy(&nx, xenolift_mem + (q - 0x80000000u) + 12, 4);
            if (nx == 0u) { fprintf(stderr, "[fault]   chain terminator at entry[%d]\n", i); break; }
            q = nx;
        }
        fprintf(stderr, "[fault] irq-chain walk printed %d entries (done)\n", i);
    }
    g_exit_why = "fault-walk";
    dump_state();
    fprintf(stderr, "[xenolift] this is the smoke test telling us which hardware to fake next.\n");
    exit(0);
}

/* watchdog: if the recompiled code loops forever (e.g. waiting for a
 * hardware flag we don't emulate), stop cleanly and report. */
#include <execinfo.h>

/* R148 (R147 Mac park = GPU RENDER STREAM): the kernel reached the
 * PsyQ primitive submission path — fn_80044B70 SubmitGpuPrimitive ->
 * table[5] fn_8004659C "cwb" (GP0 word-pusher; per-prim FINITE loop:
 * GP1(0x04) DMA-off toggle, then r5 words -> GP0 via cell 0x800569A0).
 * The watchdog killed it mid-stream because a pure render stretch
 * produces ZERO park ticks. Track submission volume so the digest can
 * tell "resubmitting the same display list forever" from "new prims
 * forever", and let on_alarm treat GPU writes as liveness (bounded). */
static uint32_t g_gpu_prims, g_gpu_last_prim, g_gpu_last_tag;
static uint64_t g_gpu_words;

extern volatile uint32_t xenolift_cur_fn;
uint32_t xenolift_chanf_fired; /* R643: set at CHANNEL F dispatch; disarms channel E sentinel re-stamp */
uint32_t xenolift_fntrail[16]; /* R642 rolling last-16 dispatch trail */
uint32_t xenolift_fntrail_n;

static void on_alarm(int sig)
{
    /* R365 PARK BACKSTOP: if we re-enter on_alarm while a park dump is
     * in flight, a park printer has wedged inside the signal handler
     * (nothing else can interrupt it - cycle 122 died here with zero
     * evidence). Print the stage and force-exit so run.sh always
     * completes and the digest always generates. */
    if (g_in_park) {
        fprintf(stderr, "[park] STAGE-HANG at stage %d - backstop exit 77 (park printer wedged in signal context)\n", g_park_stage);
        _exit(77);
    }
    static uint32_t last_park; static int defers;
    /* R314: GLOBAL RUN BUDGET — the bridge kills the run at 240s (SIGKILL, no
     * park, mangled evidence; cycles 61-62). No liveness defer may extend the
     * run past ~205s: we always want OUR graceful HALT + park, never the kill. */
    time_t run_now;
    int over_budget;
    (void)sig;
    if (g_boot_wall_t0 == 0) g_boot_wall_t0 = time(NULL); /* paranoia: alarm before main? */
    run_now = time(NULL);
    static int run_budget_s = -2; /* R449 FAST-CYCLE KNOB: read xenolift_budget.txt
     * once (written by run.sh; default 210 = full trajectory, unchanged).
     * Quick-verdict cycles set a shorter window so the report lands sooner. */
    if (run_budget_s == -2) {
        FILE *bf = fopen("xenolift_budget.txt", "r");
        int b = 210;
        if (bf) { if (fscanf(bf, "%d", &b) != 1) b = 210; fclose(bf); }
        run_budget_s = (b >= 30) ? b : 210;
    }
    over_budget = ((run_now - g_boot_wall_t0) >= run_budget_s) || g_force_halt /* R415: 205->210 (c172: file 2 6/15 at halt; shell 232, bridge 240) */ /* R413: +10s (c170 pump ran out of clock mid-flow; bridge 240, shell 225, park ~15) */; /* R320: recursion guard can force */
    if (g_force_halt && (run_now - g_boot_wall_t0) < 195)
        fprintf(stderr, "[halt] FORCED (R320 recursion guard) - parking now (churn bounces=%lu)\n", xenolift_churn_bounces);
    fprintf(stderr, "[wd] t=%lds budget=%s\n", (long)(run_now - g_boot_wall_t0), over_budget ? "OVER" : "ok");
    { static long wd_prev_t; long tn = (long)(run_now - g_boot_wall_t0);
      if (wd_prev_t && tn - wd_prev_t > 10)
          fprintf(stderr, "[cd] R622 ALARM STARVED: %lds gap (prev wd t=%lds) - host context held the alarm off\n", tn - wd_prev_t, wd_prev_t);
      wd_prev_t = tn; }
    {   /* R642 FN TRAIL (c212): state-1 entry 80077E88 RAN (cur 0xFFFFFFFF->1,
         * second file-14 install completed, then the guest went dark at ~t=9.5s:
         * no CD events, no wd ticks, run.sh progress-kill at 10s. Every guest-
         * driven camera is blind in a dead spin; this HOST-side alarm keeps
         * filming: prints the rolling last-16 dispatched fns so the park site
         * is named even when nothing else fires. Early run: every alarm (the
         * transition era); after 40s: every 10th (era surveillance). */
        static int tr_n;
        long tr_t = (long)(run_now - g_boot_wall_t0);
        if ((tr_t < 40) || ((tr_n % 10) == 0)) {
            int i; uint32_t st = xenolift_fntrail_n;
            fprintf(stderr, "[trail] R642 #%d t=%lds cur_fn=%08X:", tr_n, tr_t, xenolift_cur_fn);
            for (i = 15; i >= 0; i--) fprintf(stderr, " %08X", xenolift_fntrail[(st - 1u - (uint32_t)i) & 15u]);
            fprintf(stderr, "\n");
        }
        tr_n++;
    }
    /* R621 STALL WATCH: c191 — the walk reached 8 steps (109019 @t=153)
     * then went silent for 50+s: no releases, no wrap, no latch. If the
     * walk era has gone quiet >15s, dump the dispatcher state so we see
     * WHO stopped (game stopped issuing seeks? answers not delivered?).
     * Repeats every ~5s, capped at 8 lines. */
    { static long stall_last; static int stall_n;
      long tnow = (long)(run_now - g_boot_wall_t0);
      if (g_walk_max >= 109000u && g_walk_last_t >= 0 &&
          (tnow - g_walk_last_t) > 15 && (tnow - stall_last) >= 5 && stall_n < 8) {
          stall_last = tnow; stall_n++;
          fprintf(stderr, "[cd] R621 STALL WATCH: t=%lds walk_quiet=%lds max_seek=%u | last_cmd=0x%02X FE1C=%u FE20=%u pend=%u sched=%u fifo=%u/%u FDF8=%08X FDFC=%08X FE34=%08X F0C=%08X F10=%08X slotbits=%08X hdl564AC=%08X cb59F08=%08X\n",
                  tnow, tnow - g_walk_last_t, g_walk_max,
                  cd_last_cmd, xenolift_mem_read32(0x8004FE1Cu), xenolift_mem_read32(0x8004FE20u),
                  (unsigned)cd_pending, (unsigned)cd_scheduled, (unsigned)cd_resp_n, (unsigned)(sizeof(cd_resp)),
                  xenolift_mem_read32(0x8004FDF8u), xenolift_mem_read32(0x8004FDFCu),
                  xenolift_mem_read32(0x8004FE34u),
                  xenolift_mem_read32(0x80059F0Cu), xenolift_mem_read32(0x80059F10u),
                  xenolift_mem_read32(0x80056788u), xenolift_mem_read32(0x800564ACu),
                  xenolift_mem_read32(0x80059F08u));
      }
    }
    if (g_ack_starve > 400u) fprintf(stderr, "[ackcam] R561 HEARTBEAT after %u starved acks\n", g_ack_starve);
    g_ack_starve = 0;
    { /* R588 [rsdump] read-struct sampler, RELOCATED: the R587 copy sat below
     * the mount-era region and never ran before t~21s (c156 first sample 21s,
 * gate irrelevant) — the boot-era NATIVE completions (files 2-6, t=0-9s) were
 * missed. New home = top of tick (runs from t=0, proven by mountw t=9s).
 * Cadence: 1s from t=2s through t=20s (boot fingerprint window), then 3s
 * (stuck-era record). Cap 60 lines. F10 node form at each native completion
 * = the completion signature the stepper (fn 80041430) polls. */
        static time_t rs_last; static int rs_n;
        long rs_age = (long)(time(NULL) - g_boot_wall_t0);
        int rs_due = (rs_n < 60) && (rs_age >= 2) &&
                     (rs_age <= 20 ? (time(NULL) - rs_last >= 1) : (time(NULL) - rs_last >= 3));
        if (rs_due) {
            rs_last = time(NULL); rs_n++;
            fprintf(stderr, "[rsdump] R588 #%u t=%lds: EF8=%08X EFC=%08X F00=%08X F04=%08X cb=%08X F0C=%08X F10=%08X F14=%08X F18=%08X F1C=%08X FE08=%08X FE34=%08X seek=%u FDF8=%u | pend=%u sched=%u arm1=%u cmd=%02X fe1c=%u fe20=%u fifo=%u/%u\n",
                    rs_n, rs_age,
                    xenolift_mem_read32(0x80059EF8u), xenolift_mem_read32(0x80059EFCu),
                    xenolift_mem_read32(0x80059F00u), xenolift_mem_read32(0x80059F04u),
                    xenolift_mem_read32(0x80059F08u), xenolift_mem_read32(0x80059F0Cu),
                    xenolift_mem_read32(0x80059F10u), xenolift_mem_read32(0x80059F14u),
                    xenolift_mem_read32(0x80059F18u), xenolift_mem_read32(0x80059F1Cu),
                    xenolift_mem_read32(0x8004FE08u), xenolift_mem_read32(0x8004FE34u),
cd_seek_lba, xenolift_mem_read32(0x8004FDF8u),
                    cd_pending, cd_scheduled, cd_arm_int1_pending, cd_last_cmd,
                    xenolift_mem_read32(0x8004FE1Cu), xenolift_mem_read32(0x8004FE20u),
                    cd_data_pos, cd_data_n);
        }
    }

    /* R630 CONCLUDED-PARK DELIVERY (c199/c200: the R628 leg's gate matches
     * the field park receipts exactly - cmd=02, fe1c=0, FDF8=0, FE04==seek,
     * sched=1 pend=0 - yet NEVER fired: the game at this park polls NO
     * hooked location (no MMIO status reads, no FE1C RAM reads - the
     * R402/R400 hook contexts never run), so the check sleeps. The answer
     * stays queued forever and the game's post-read conclusion never runs
     * (mount latch 92BC stays 0, MNTACC idx frozen). Fix: run the SAME
     * gate on the tick cadence (this block provably runs every 3-4s at
     * parks - rsdump/mntacc samples prove it) and deliver via the proven
     * cd_restore_pend path. Belt-and-suspenders: if the game's own
     * conclusion still leaves latch 92BC==0 two deliveries later, stamp
     * it (R623 precedent, receipted, capped) so the mount chain can
     * accept and the phase idx can advance. */
    if (cd_scheduled && cd_pending == 0u
        && (cd_last_cmd == 0x02u || cd_last_cmd == 0x06u)
        && xenolift_mem_read32(0x8004FE1Cu) == 0u
        && xenolift_mem_read32(0x8004FDF8u) == 0u
        && cd_seek_lba >= 108900u
        /* R631 (c201): every OTHER gate condition is receipt-proven at the
         * park (rsdump prints sched/pend/cmd/fe1c/FDF8 from the same vars) -
         * so the silent miss is FE04!=seek: PositionArchiveEntry moved the
         * file-position cell (likely to the NEXT entry, 108995 = file-15
         * LBA, or drag-back 0). Accept the whole field band for FE04 (the
         * drive is band-locked too, so no boot risk). Posture note proves
         * it either way - never ship a check whose failure is invisible. */
        && (xenolift_mem_read32(0x8004FE04u) == cd_seek_lba
            || (xenolift_mem_read32(0x8004FE04u) >= 108900u
                && xenolift_mem_read32(0x8004FE04u) <= 109150u)
            || xenolift_mem_read32(0x8004FE04u) == 0u)) {
                { static int r630n;
          if (r630n < 4) { r630n++;
            cd_restore_pend();
            fprintf(stderr, "[cd] R630 tick-cadence delivery: cmd=%02X seek=%u FE04=%u - answer delivered (c202: game proven to ignore - capped)\n",
                    cd_last_cmd, cd_seek_lba, xenolift_mem_read32(0x8004FE04u)); }
          /* R632 (c202): THE ADDRESS BUG - MNTACC proves the mount latch
           * is at 0x8006_92BC, but every stamp since R619 wrote
           * 0x8005_92BC - ONE DIGIT OFF. The stamp landed on the wrong
           * desk for ~30 cycles while MNTACC watched the real cell stay
           * 0. Real cell now. Re-stamp if the game wipes it (max 8,
           * receipted); skip receipt if nonzero - never invisible. */
          { static int r632stamps;
            if (r632stamps < 8) {
              uint32_t r632v = xenolift_mem_read32(0x800592BCu);
              if (r632v == 0u) {
                  xenolift_mem_write32(0x800592BCu, 1u);
                  r632stamps++;
                  fprintf(stderr, "[cd] R632 mountlatch stamp #%u: 92BC(0x800592BC) 0 -> 1 @t=%lds (REAL cell - watch MNTACC idx/cur/92D0 accept)\n",
                          r632stamps, time(NULL) - g_boot_wall_t0);
              } else if (r632stamps < 4) { r632stamps += 4;
                  fprintf(stderr, "[cd] R632 stamp-skip: 92BC(0x800592BC)=%08X nonzero - game or prior stamp already wrote it\n", r632v);
              } } }
          /* R633 (c203): latch STAMPED and HELD (latch=1 all park) yet
           * idx/cur/92D0 stayed frozen - the mount loop gates on another
           * line. Prime candidate: the result cell 92D0 (0=busy). With
           * latch==1 + this concluded park posture, stamp 92D0=1; re-arm
           * max 8 if the game wipes it, every stamp receipted. */
          { static int r633stamps;
            if (r633stamps < 8
                && xenolift_mem_read32(0x800592BCu) == 1u
                && xenolift_mem_read32(0x800592D0u) == 0u) {
                xenolift_mem_write32(0x800592C8u, 1u);    /* exit-parity set */
                r633stamps++;
                fprintf(stderr, "[cd] R633 exitgate stamp #%u: 92D0 0 -> 1 (latch held; watch MNTACC idx/cur move)\n", r633stamps);
            } else if (r633stamps == 0
                && xenolift_mem_read32(0x800592D0u) != 0u) { r633stamps = 4;
                fprintf(stderr, "[cd] R633 stamp-skip: 92D0 already %08X (game or era wrote it)\n",
                        xenolift_mem_read32(0x800592D0u));
            } }
        }
        /* R634 (c204) DRAG-BACK HEAL: decode of fn_8001996C + MNTACC shows the
         * state transition ALREADY COMMITTED (cur 0x800592C0=1 = Field; the
         * park is FIELD-INIT, not the menu-mount). The archive FS positioning
         * math (fn_8002B168 PA entry: compares ConvertDiscLocationToSector()
         * result against FE04, walks the file table) needs FE04 to hold the
         * game's own file-position - but FE04 sits at 0 (the banked drag-back
         * class). PA #5 wrote FE04=0x1A9BD (108989) with its own math at
         * install-done; restore THAT value (the game's own number, not a
         * guess) so the PA/stepper comparison can find member 15. Receipted,
         * re-arms (max 8) if dragged back again. */
        { static int r634n;
          if (r634n < 8 && xenolift_mem_read32(0x8004FE04u) == 0u) {
              xenolift_mem_write32(0x8004FE04u, 0x1A9BDu);
              r634n++;
              /* R637 (c207): THE PARK'S OWN RESUME KEY, decoded from the
               * game itself. fn_80019F00 (state-transition wipe/park) reads
               * word 0x80010000 at L_80019F20: resume iff (val+1) >= 2
               * unsigned (1 <= val <= 0xFFFFFFFE); val 0 or FFFFFFFF wipes
               * the screen and sinks into the ORIGINAL self-loop at
               * L_80019F74 (j-self, verified in SLUS bytes). No writer
               * exists in the kernel text - the writer is the mounted
               * module's install-completion count. File-14 install DID
               * stream fully (FILE-CB #69 FDF8=0), so count=1 is factual.
               * Stamp 1 when the math parks; receipted, re-arm cap 8. */
              { uint32_t mc = xenolift_mem_read32(0x80010000u);
                static int r637n;
                if (r637n < 8 && (mc == 0u || mc == 0xFFFFFFFFu)) {
                    xenolift_mem_write32(0x80010000u, 1u);
                    r637n++;
                    fprintf(stderr, "[cd] R637 mountcount stamp #%d: 80010000 %08X -> 1 (fn_80019F00 resume key @L_80019F20 - watch park release)\n", r637n, mc);
                } }
              fprintf(stderr, "[cd] R634 dragback heal #%d: FE04 0 -> 0x1A9BD (108989, PA #5's own value - restore the game's file-position so the stepper math can find member 15)\n", r634n);
          }
        }
    }

    { /* R639 (c209) EXIT-FLAG CLEAR: real cells finally visible (R638 retarget) -
       * cur(0x800592C0)=FFFFFFFF (transition committed), req=1, latch held at 1,
       * but 92D0(0x800592D0)=1 CONSTANT: the menu's exit gate (0x8001A580:
       * BNE 92D0!=0 -> loop) never passes because the virtual player HELD the
       * confirm (no fresh input edge -> the poll never re-clears the flag the
       * loop-head re-arms every frame). The game's own poll clears this cell
       * when it processes fresh input - mimic exactly that. Gate on
       * cur==FFFFFFFF so we only fire in the committed-transition state. */
      static int r639n;
      if (r639n < 40 && xenolift_mem_read32(0x800592C0u) == 0xFFFFFFFFu
          && xenolift_mem_read32(0x800592D0u) != 0u) {
          xenolift_mem_write32(0x800592D0u, 0u);
          r639n++;
          fprintf(stderr, "[cd] R639 exitflag clear #%d: 800592D0 1 -> 0 (mimic poll's own input-processed clear - menu exit gate 0x8001A580 needs 92D0==0 && 92C8!=0)\n", r639n);
      }
    }

    { /* R631 posture note: concluded-park posture held but FE04 escaped
       * even the widened band - receipt the values so the miss can never
       * be invisible again (cap 4). */
      if (cd_scheduled && cd_pending == 0u
          && (cd_last_cmd == 0x02u || cd_last_cmd == 0x06u)
          && xenolift_mem_read32(0x8004FE1Cu) == 0u
          && xenolift_mem_read32(0x8004FDF8u) == 0u
          && cd_seek_lba >= 108900u
          && xenolift_mem_read32(0x8004FE04u) != cd_seek_lba
          && !(xenolift_mem_read32(0x8004FE04u) >= 108900u
               && xenolift_mem_read32(0x8004FE04u) <= 109150u)
          && xenolift_mem_read32(0x8004FE04u) != 0u) {
          static int r631n; if (r631n < 4) { r631n++;
              fprintf(stderr, "[cd] R631 posture note: seek=%u FE04=%u cmd=%02X - concluded park, FE04 escaped band\n",
                      cd_seek_lba, xenolift_mem_read32(0x8004FE04u), cd_last_cmd); }
      }
    }
    /* R566 [mountw]: c134 MILESTONE — file-14 read completed (FDF8=0 at seek 108995,
     * wrap cmds 13/08/09 issued) but the game re-reads the directory and loops the
     * mount; phase idx (8006FAEC) never advances. Camera on the ACCEPTANCE cells:
     * idx / cur-state / req / latch / landing-zone head words — every 4th tick once
     * the zone is non-empty. Observe before patching (Lesson 53). */
    {
        static uint32_t mw_n; static uint32_t mw_lastidx;
        uint32_t mw_head = xenolift_mem_read32(0x801D9724u);
        uint32_t mw_idx  = xenolift_mem_read32(0x8005FAECu);
        if (mw_head != 0u && (mw_n < 30u) && ((mw_n & 3u) == 0u || mw_idx != mw_lastidx)) {
            fprintf(stderr, "[mountw] R566 #%u t=%lds: idx=%08X cur(92C0)=%08X req(8088)=%08X latch(92BC)=%08X land=%08X %08X %08X %08X FDF8=%u | +10=%08X %08X +40=%08X +80=%08X | 92CC=%08X 92E8=%08X\n",
                    mw_n, (long)(time(NULL) - g_boot_wall_t0), mw_idx,
                    xenolift_mem_read32(0x800592C0u), xenolift_mem_read32(0x80018088u),
                    xenolift_mem_read32(0x800592BCu),
                    xenolift_mem_read32(0x801D9724u), xenolift_mem_read32(0x801D9728u),
                    xenolift_mem_read32(0x801D972Cu), xenolift_mem_read32(0x801D9730u),
                    xenolift_mem_read32(0x8004FDF8u),
                    xenolift_mem_read32(0x801D9734u), xenolift_mem_read32(0x801D9738u),
                    xenolift_mem_read32(0x801D9764u), xenolift_mem_read32(0x801D97A4u),
                    xenolift_mem_read32(0x800592CCu), xenolift_mem_read32(0x800592E8u));
            mw_lastidx = mw_idx;
        }
        /* R570 [mtrans]: c138 decode — cur(92C0)=1 means Field COMMITTED
         * (symbol table: 0=Menu 1=Field 2=Battle...), the install transform
         * COMPLETED by t=17s (landing zone fully rewritten, strings->pointers,
         * state struct alive: 92CC alternates). But req(8088) still pending=1
         * and the phase idx byte (8006FAEC) never advances — kernel disasm has
         * NO writer for it; the copier lives in the mount-success chain that
         * never fires. Contract enumerated -> deliver the copy ourselves,
         * mimicking the real copier: idx=cur(=Field) + req cleared. One-shot,
         * era-gated on the installed posture, logged + digest-verified. */
        /* R643: old gate rode walk-era mw_head machinery that no longer forms ->
         * delivery never fired (no mtrans receipt c212/213). Era-independent gate:
         * after CHANNEL F, on the observed install-concluded posture. */
        /* R646/R647 [mtrans-rearm]: c216 receipts — the R645 one-shot delivery FIRED
         * (gate sample + delivered) and the kernel CONSUMED it: req 1->0 (kernel's
         * own accept), idx 0->1 held, and the kernel then re-stamped its
         * committed-pending sentinel cur(92C0)=-1 and now runs the FULL native
         * transition machinery every frame (163-fn census: 80019ACC teardown chain,
         * heap release, ResetHeapOwner, 80019AF8 dispatcher, module-init fns) —
         * but the state-1 entry (80077E88) still does not dispatch, and c212
         * proved it dispatches only when the completer has answered cur=idx.
         * The contract is a REPEATED handshake, not a one-shot: kernel stamps
         * pending(-1)+idx(target) -> completer answers cur=target while the
         * install stands (F0C(59F0C)=14, FDF8=0). Re-armable delivery: refires
         * whenever the pending posture returns, capped receipt lines. */
        /* R667: c237 receipts - the R666 refire-time guard never matched
         * (28088 still holds the menu-era value at refire; it clears only AT
         * the transition = the loop's abort moment). Re-arm on the maintenance
         * clock: field accepted (idx=1, cur=1) AND era cell cleared -> stamp
         * the field era so the resident loop runs subsystems instead of
         * aborting (R499 decode: 28088==0 => loop returns BEFORE subsystem 0
         * => the clean ~15s main return). Capped, one receipt per fire. */
        { /* R668: R667 re-arm removed — c238 exitdiag loop28088=A7A00032 (nonzero garbage):
          * 0x80028088 is NOT the loop state cell in this era; R499 note was era-specific. */ }
        if (xenolift_chanf_fired) {
            static uint32_t mt_settle; static int mt_n;
            static int mt_diag;
            if (!mt_diag) { mt_diag = 1;
                fprintf(stderr, "[mtrans] R650 gate sample: idx=%u cur=%08X F0C(59F0C)=%u F0C(4FE0C)=%u FDF8=%u\n",
                        xenolift_mem_read32(0x8005FAECu), xenolift_mem_read32(0x800592C0u),
                        xenolift_mem_read32(0x80059F0Cu), xenolift_mem_read32(0x8004FE0Cu),
                        xenolift_mem_read32(0x8004FDF8u)); }
            uint32_t mt_idx = xenolift_mem_read32(0x8005FAECu);
            if ((xenolift_mem_read32(0x800592C0u) == 0xFFFFFFFFu /* kernel re-stamped pending (refire side) */
                 || xenolift_mem_read32(0x800592C0u) == 1u)      /* R647: OR first-mount posture (cur=Field,
                                                                  *  c215/c217 fresh boots present this and the
                                                                  *  FIRST delivery must answer it — c216 regression) */
                && (xenolift_mem_read32(0x80059F0Cu) == 14u    /* file-14 install stands */
                    ? xenolift_mem_read32(0x8004FDF8u) == 0u     /* file layer concluded */
                    : xenolift_mem_read32(0x80059F0Cu) == 15u)   /* R650: f15 install era — keep answering
                                                                  * (c220 exitdiag: kernel concluded & main
                                                                  * clean-returned @t=15s when the refire retired
                                                                  * mid-install; the handshake must live through
                                                                  * the whole install, FDF8 unconstrained) */
                && (mt_idx == 0u || mt_idx == 1u)) {             /* target = Field (or pre-accept) */
                mt_settle++;
                if (mt_settle >= 2u) {
                    mt_settle = 0u;
                    mt_n++;
/* R665: c233/c235 [phase] receipts — the state dispatcher (0x80019ACC enter,
                     * r31=8001A5B8 post-menu-exit) reads THIS cell as its QUEUE READ INDEX:
                     * node[0] = menu cb 0x8001A4B4, node[1] = FIELD ENTRY cb 0x80077E88.
                     * Our delivery stamped 0 here => dispatcher kept calling the menu cb
                     * => menu exit => main clean-returned @15s. On refire (mt_idx==1, field
                     * accepted) answer with the FIELD NODE INDEX so the dispatcher calls
                     * the field's own entry code. First accept keeps 0 (kernel's own
                     * consumption path follows the R648 stamp + install). */
/* R666: c236 receipts — req(18088)=1 RE-ARMED the mount machine (FE04 reset
                     * to 0, FE1C 0A->0, file layer dragged back to era start): the mount
                     * machine consumes req as "request pending" — it must stay 0 after
                     * accept. The REAL resident-loop state cell is 0x80028088 (R499/R501
                     * decode: loop reads req-state 0x80028088, aborts BEFORE subsystem 0
                     * when it is 0 => the clean @15s main return; it is ALSO the DISPENV
                     * config selector). Field era = 1. */
                    xenolift_mem_write32(0x80018088u, 0u);
                    if (mt_idx == 0u) xenolift_mem_write32(0x8005FAECu, 1u); /* idx = Field, first accept */
                    xenolift_mem_write32(0x800592D0u, 0u);     /* menu redraw loop cleared */
                    xenolift_mem_write32(0x800592C8u, 1u);     /* exit flag set */
                    xenolift_mem_write32(0x800592C0u, 1u);      /* cur = Field: mount ACCEPTED */
                    /* R648 [f15req]: c218 - handshake live (40 refires consumed)
                     * but kernel re-stamps pending every pass: the state-1 dispatch
                     * waits on the FIELD MODULE INSTALL (file 15) and the read
                     * list ends at file 14 - the native mount never enqueued it
                     * (FTAB2: file#15 LBA=108995 size=92180; read-order members
                     * 1/2/6; no size-lookup ever hits 15). Stamp the file-15
                     * request with the game's own directory values once the
                     * handshake is proven live: FE04=LBA, FDF8=size, FDE4=2
                     * (install mode per cbcall form), FDFC=1 (install pending),
                     * F0C(59F0C)=15, node form mimics file-14's request
                     * (0x00331424 -> 0x00331524). Gate on F0C==14 means this
                     * also retires the refire (handoff to install phase). */
                    { static int mt_f15done;
                      if (!mt_f15done && mt_n >= 2) { mt_f15done = 1;
                        xenolift_mem_write32(0x8004FE04u, 108995u);     /* file-15 LBA */
                        xenolift_mem_write32(0x8004FDF8u, 92180u);      /* file-15 size */
                        xenolift_mem_write32(0x8004FDE4u, 2u);           /* install mode */
                        xenolift_mem_write32(0x8004FDFCu, 1u);           /* install pending */
                        xenolift_mem_write32(0x80059F0Cu, 15u);          /* request index 15 */
                        xenolift_mem_write32(0x80059F10u, 0x00331524u); /* node form (file-14 req analog) */
                        fprintf(stderr, "[mtrans] R648 f15 request stamped: FE04=108995 FDF8=92180 F0C=15 F10=00331524 - watch READ ISSUED file#15\n");
                        g_statshield_era = 1u;
                      } }
                    if (mt_n <= 40) {
                        fprintf(stderr, "[mtrans] R650 mount-success %s #%d: cur=-1->1 idx=%u + exit pair (re-armable handshake)\n",
                                mt_idx == 0u ? "first" : "refire", mt_n, mt_idx);
                    }
                }
            } else {
                mt_settle = 0u; /* posture broke - re-arm from scratch */
            }
        }
        /* R651 [f15bulk]: kernel conclude trigger fires ~2s after the f15 stamp
         * (c219/c220/c221 identical clean-returns @t=15s, 8 sectors in); native
         * install needs ~7s (46 sectors at event cadence). Bulk-deliver ALL
         * remaining sectors in THIS probe pass: same disc data (disc_read_lba),
         * same walking dest (FE08+0x800/sector - the DMA lands sectors there
         * natively per cd-dma receipts), same bookkeeping the FILE-CB does
         * (FE04+1, FDF8-2048). Done posture mimics cbcall #69 (observed file-14
         * done form): FDF8=0 FDFC=0 FE1C=6 -> next native FILE-CB entry takes
         * the finalize path (L_8002B1D4). */
        {
            uint32_t f15c = xenolift_mem_read32(0x80059F0Cu);
            uint32_t f15r = xenolift_mem_read32(0x8004FDF8u);
            /* R663 (c233 receipts): the assist must NOT fire at the FULL-REMAINING posture.
             * c232: native walk streamed 8 sectors first (92180 -> 75796), assist completed
             * the rest, and the game's FILE-CB finalize chain ran -> queue ADVANCED to the
             * next file (F10 00331524 -> 00661524). c233: assist fired at full 92180 BEFORE
             * the walk -> finalize chain never ran -> queue never advanced. The walk's own
             * bookkeeping IS the queue-advance mechanism, so the assist waits for
             * in-flight (remaining < full size) and only then completes the tail.
             * Full sizes from the ftab receipts: 15=92180 16=166564 17=70944 18=14360. */
            {
                static const uint32_t r663_full[19] = {
                    0u,0u,0u,0u,0u,0u,0u,0u,0u,0u,0u,0u,0u,0u,0u,92180u,166564u,70944u,14360u
                };
                uint32_t r663_fullsz = (f15c <= 18u) ? r663_full[f15c] : 0u;
                if (f15c >= 15u && f15c <= 18u && f15r > 0u
                    && (r663_fullsz == 0u || f15r < r663_fullsz)) {
                uint32_t lba = xenolift_mem_read32(0x8004FE04u);
                uint32_t dst = xenolift_mem_read32(0x8004FE08u);
                uint32_t rem = f15r;
                int nsec = 0;
                while (rem > 0u && nsec < 64) {
                    unsigned char sbuf[2048];
                    if (disc_read_lba(lba, sbuf) != 0) break;
                    uint32_t chunk = (rem < 2048u) ? rem : 2048u;
                    for (uint32_t i = 0u; i + 4u <= chunk; i += 4u) {
                        uint32_t w;
                        memcpy(&w, sbuf + i, sizeof(w));
                        xenolift_mem_write32(dst + i, w);
                    }
                    lba += 1u; dst += 0x800u;
                    rem = (rem > 2048u) ? (rem - 2048u) : 0u;
                    nsec++;
                }
                xenolift_mem_write32(0x8004FE04u, lba);
                xenolift_mem_write32(0x8004FE08u, dst);
                xenolift_mem_write32(0x8004FDF8u, rem);
                if (rem == 0u) {
                    xenolift_mem_write32(0x8004FDFCu, 0u);   /* done posture per cbcall #69 */
                    xenolift_mem_write32(0x8004FE1Cu, 6u);
                }
                fprintf(stderr, "[mtrans] R651 f15 bulk install: %d sectors LBA %u..%u, FDF8 %u -> %u%s\n",
                        nsec, lba - (uint32_t)nsec, (lba > 0u ? lba - 1u : 0u), f15r, rem,
                        rem == 0u ? " DONE posture set (FDF8=0 FDFC=0 FE1C=6)" : " (partial)");
                }
            } /* end R663 full-size gate wrapper */
        }
        static uint32_t g_f15_waked = 0u;
        /* R653 [fieldreselect]: c223 receipts — after the f15done wake the kernel
         * tore down VOLUNTARILY (FE08/FE20/FE1C zeroed at fn 0x80019524 = boot-main,
         * module chain rebuilt 2..F, file 15 re-requested on its own, then 92C0 reset
         * to 0 = the "Field" selection itself wiped by the soft reset; region returned
         * clean @t=15s with the whole state machine at zero). The kernel re-boots INTO
         * the loaded field program — but the fresh boot finds no selection and concludes.
         * Re-write the commit posture AFTER the reset completes, using the exact values
         * the game's own CHANNEL F produced at commit (minput c223: 92C0=1 req(8088)=1
         * idx(FAEC)=0 latch(92BC)=801D9724). The phase dispatcher (fn 80019ACC, seen
         * entering with phase=1 armed) then dispatches state-1 (cb 0x80077E88) natively. */
        {
            static uint32_t fr_n;
            uint32_t fr_f0c = xenolift_mem_read32(0x80059F0Cu);
            uint32_t fr_fe08 = xenolift_mem_read32(0x8004FE08u);
            uint32_t fr_fe20 = xenolift_mem_read32(0x8004FE20u);
            uint32_t fr_cur = xenolift_mem_read32(0x800692C0u);
            if (g_f15_waked > 0u && fr_n < 4u
                && fr_f0c == 0u && fr_fe08 == 0u && fr_fe20 == 0u && fr_cur == 0u) {
                fr_n++;
                xenolift_mem_write32(0x800692C0u, 1u);          /* cur = Field */
                xenolift_mem_write32(0x80028088u, 1u);         /* req = Field */
                xenolift_mem_write32(0x8006FAECu, 0u);         /* idx reset */
                xenolift_mem_write32(0x800692BCu, 0x801D9724u); /* latch: field landing */
                xenolift_mem_write32(0x800692C8u, 1u);         /* exit-pair: processed */
                xenolift_mem_write32(0x800692D0u, 0u);
                fprintf(stderr, "[mtrans] R653 field reselect #%u: post-reset posture rebuilt (cur=1 req=1 idx=0 latch=801D9724) - fresh boot should dispatch state-1 natively\n", fr_n);
            }
        }
        /* R656 (c226): WARM-REBUILD POSTURE - teardown this cycle PRESERVED the
         * pending transition (cur=-1, idx=1) and the fresh boot re-armed the f15
         * request (F0C=15, FDF8 back to full 75796, FE20=3) then began NATIVE f15
         * streaming (own DMA + FILE-CB walk, 8 sectors @t=14s) before boot-main
         * concluded @t=16s. The dispatcher needs cur=1 (state-1 READY) to
         * dispatch the field callback (phase table[1] cb 0x80077E88); cur=-1 =
         * committed-but-never-marked-ready. The cold R653 arm never matched (it
         * watches the all-zero reset posture). WARM ARM: when the rebuild has
         * re-stamped the module chain through F0C=15, advance ONLY cur to 1 -
         * idx/req/latch/F0C stay exactly as the game set them (idx=1 = field). */
        {
            static uint32_t wr_n;
            uint32_t wr_cur = xenolift_mem_read32(0x800592C0u);
            uint32_t wr_f0c = xenolift_mem_read32(0x80059F0Cu);
            if (g_f15_waked > 0u && wr_n < 4u
                && wr_cur == 0xFFFFFFFFu && wr_f0c == 15u) {
                xenolift_mem_write32(0x800592C0u, 1u);
                wr_n++;
                fprintf(stderr, "[mtrans] R656 warm reselect #%u: cur -1 -> 1 (F0C=15 warm rebuild; idx/req/latch untouched - game's own values) - dispatcher should dispatch state-1 (cb 0x80077E88) natively\n", wr_n);
            }
        }
        /* R652 [f15wake]: c222 - bulk landed (38 sectors, FDF8=0, done
         * posture) but NO cbcall #78: the scheduled-answer rail went idle
         * (rsdump sched 1->0 at the f15 stamp) so the guest's FILE-CB never
         * re-entered to consume the done posture and run its own finalize
         * (L_8002B1D4 -> HandleCdReadyCompletion -> PositionArchiveEntry).
         * Ring the PROVEN doorbell (cd_force_deliver_int1, zrf0's mechanism,
         * same on_alarm context): handler pair + collector run the armed
         * FILE-CB with FDF8=0 -> native finalize -> install-done -> kernel
         * mount record advances -> state-1 dispatch. */
        {
            static int w52;
            if (w52 < 6
                && xenolift_mem_read32(0x80059F0Cu) >= 15u
                && xenolift_mem_read32(0x80059F0Cu) <= 18u
                && xenolift_mem_read32(0x8004FDF8u) == 0u
                && xenolift_mem_read32(0x8004FE1Cu) == 6u) {
                w52++;
                g_f15_waked = 1u;
                /* R655: c225 crash dossier - the f15done force-deliver ran the
                 * guest CD chain in alarm context while boot-main was mid-
                 * dispinit on the live thread -> register/stack collision
                 * (ra smeared to 0x20202020 from menu string data -> wild
                 * jump, SIGSEGV addr 0x14C02000, kit recovered to t=152s).
                 * LESSON-CLASS R350: never dispatch guest code from a context
                 * that can collide with live guest execution. Swap for the
                 * R525-proven MAILBOX prime: load the done-ack answer +
                 * arm pending; the game's own main-thread poll (fn_8002AC14
                 * chain, constant in every digest) pops it natively (rspop
                 * path) and walks its own finalize at FDF8=0. */
                cd_resp[0] = 0x02u; cd_resp[1] = 0x01u; cd_resp[2] = 0x01u;
                cd_resp_n = 3u; cd_resp_pos = 0u;
                if (cd_pending == 0u) cd_pending = 1u;
                fprintf(stderr, "[mtrans] R655 f15 done-ack mailbox primed #%d (rspop path - main thread pops natively, no signal-context dispatch)\n", w52);
                /* R671: c241 — the R669 queue answer hung off the phase-hook
                 * (fn 80019ACC entry with f0c=15), which does NOT fire on
                 * alarm-path bulk cycles (c241: R651 alarm bulk landed, no
                 * phase-hook entry, req stayed 0 at death). Write it here,
                 * straight off the done posture: field accepted (cur=1),
                 * file-15 loaded (F0C=15), nothing remaining (FDF8=0),
                 * done state (FE1C=6), and the cell still empty. Post-menu
                 * dispatcher 80019AF8 reads req as queue index: node[1] =
                 * 0x80077E88 (FIELD). Idempotent with R669 (both guard
                 * req==0); capped. */
                if (xenolift_mem_read32(0x800592C0u) == 1u
                    && xenolift_mem_read32(0x80059F0Cu) == 15u
                    && xenolift_mem_read32(0x8004FDF8u) == 0u
                    && xenolift_mem_read32(0x8004FE1Cu) == 6u
                    && xenolift_mem_read32(0x80018088u) == 0u) {
                    xenolift_mem_write32(0x80018088u, 1u);
                    fprintf(stderr, "[mtrans] R671 queue answer (alarm path): req 0 -> 1 (done posture - field node for post-menu dispatcher)\n");
                }

            }
        }
    }
            /* R583 [f14inst] FILE-14 INSTALLER. c151 F15W receipts: the copy
             * path is ALIVE (FE08 walked the landing 801D9724 7 sectors at
             * fn 415B4) but the driver then switched FE08 to the read-ahead
             * ring (8007EAF8->F2F8, F10 node replaced 00341424->00000200)
             * BEFORE closing the file-14 request: F0C stays 14, FDF8 frozen,
             * landing holds only 7 of 61 sectors. Fix: finish file 14 the
             * way defib6's porter-carry finished boot files — stream the
             * whole file from the disc into the landing zone + write the
             * callback's own end-of-read bookkeeping (FDF8=0, FDFC=0, per
             * L_8002B1D4 window). Data-only writes, no guest dispatch (R350).
             * Posture: request slot says file 14, driver has seeked PAST the
             * file's last sector (108994), FDF8 stuck small. One-shot. */
            {
                static int f14i_fired;
                static time_t f14i_stuck_since;
                static uint32_t f14i_last_f0c;
                uint32_t f14i_f0c = xenolift_mem_read32(0x80059F0Cu);
                uint32_t f14i_fdf8 = xenolift_mem_read32(0x8004FDF8u);
                /* R584: c152 receipts — after the pass-1 install the kernel
                 * RESTARTED and re-issued the whole module sweep (F0C walked
                 * 0->2->3->4->5->6->14 again at fn 41430) = each boot pass
                 * stalls at the same wall. Re-arm per pass: when F0C drops
                 * from 14 to a low file# the kernel re-booted, so the next
                 * file-14 stall gets the install again. One fire per pass. */
                if (f14i_fired && f14i_last_f0c == 14u && f14i_f0c >= 2u && f14i_f0c <= 6u) {
                    f14i_fired = 0;
                    f14i_stuck_since = 0;
                    fprintf(stderr, "[f14inst] R584: kernel restart detected (F0C 14->%u) - installer RE-ARMED for next pass\n", f14i_f0c);
                }
                f14i_last_f0c = f14i_f0c;
                if (!f14i_fired && f14i_f0c == 14u
                    && cd_seek_lba >= 108995u && cd_seek_lba <= 109200u
                    && f14i_fdf8 > 0u && f14i_fdf8 <= 4096u) {
                    if (f14i_stuck_since == 0) f14i_stuck_since = time(NULL);
                    if (time(NULL) - f14i_stuck_since >= 5) {
                        /* R605: DISARMED — c171 CBCALL receipts proved the
                         * native FILE-CB copy path consumes the install run
                         * itself (FDF8 walks down 0x800 per accepted
                         * sector). This force-install + FDF8=0/FDFC=0
                         * premature-finalize fired mid-flight (4th
                         * old-assist-trap) and made the game re-issue the
                         * file-14 read every pass. Native path owns it now;
                         * this watcher only logs the stall. */
                        f14i_fired = 1;
                        fprintf(stderr, "[f14inst] R605: stall OBSERVED (F0C=14 FDF8=%u seek=%u) - NO force-install, native path owns it\n",
                                f14i_fdf8, cd_seek_lba);
                    }
                }
            }
{ /* R589 [f14node] completion-node mimic — c157 receipts: at native
             * completions the sync handler walks the file node 00NN1424 ->
             * 00201524 -> 00001524 (file-done) and the stepper advances F0C.
             * File 14's walk was hijacked by the ring-switch: node = 00000200
             * (stream form), F0C frozen at 14 for 100s+. One-shot restore of
             * the completion form once the stream node is observed post-install. */
                static int f14n_done;
                long f14n_age = (long)(time(NULL) - g_boot_wall_t0);
                if (!f14n_done && f14n_age >= 30 && /* R590: self-contained era gate
                     * (f14i_fired is scoped inside the f14inst block — c158 Mac
                     * compile error; arm on the mount-era clock instead) */
                    xenolift_mem_read32(0x80059F0Cu) == 14u &&
                    (xenolift_mem_read32(0x80059F10u) & 0xFFFFu) == 0x0200u) {
                    f14n_done = 1;
                    /* R599 DISARMED -> log-only: the stream walker parks at
                     * idle (0x0200) BETWEEN SECTORS; converting it to done-form
                     * (0x1524) after ONE streamed sector told the queue the
                     * whole file was complete, killing the batch walk. The
                     * done-form must come from the game's own code only. */
                    fprintf(stderr, "[f14node] R599: idle stream node OBSERVED (F10=0x%08X, F0C=%u) - NO conversion (disarmed; done-form must be native)\n",
                            xenolift_mem_read32(0x80059F10u), xenolift_mem_read32(0x80059F0Cu));
                }
            }

            /* R584 [mntacc] MOUNT-ACCEPTANCE CAMERA. c152: pass-1 install
             * landed + driver wrap completed (cmdtl 13->08->01 at seek
             * 108996) yet the kernel still restarted = the mount did not
             * ACCEPT before its timeout. Sample the acceptance cells across
             * every pass so the next digest shows WHAT pass 2 waits on:
             * idx (phase index), cur-state, req, latch, phase cells. */
            {
                static time_t ma_last;
                static uint32_t ma_n;
                if (ma_n < 70u && time(NULL) - ma_last >= 3 && time(NULL) - g_boot_wall_t0 >= 20) {
                    ma_last = time(NULL); ma_n++;

            


                    fprintf(stderr, "[mntacc] R584 #%u t=%lds: idx=%08X cur=%08X req=%08X latch=%08X 92D0=%08X 92C8=%08X 92E8=%08X F0C=%u FDF8=%u FE1C=%u seek=%u\n",
                            ma_n, time(NULL) - g_boot_wall_t0,
                            xenolift_mem_read32(0x8005FAECu), xenolift_mem_read32(0x800592C0u),
                            xenolift_mem_read32(0x80018088u), xenolift_mem_read32(0x800592BCu),
                            xenolift_mem_read32(0x800592D0u), xenolift_mem_read32(0x800592C8u),
                            xenolift_mem_read32(0x800592E8u),
                            xenolift_mem_read32(0x80059F0Cu), xenolift_mem_read32(0x8004FDF8u),
                            xenolift_mem_read32(0x8004FE1Cu), cd_seek_lba);
                }
            }
            /* R558 [f14pump v3]: THIRD Lesson-52 bite — v1/v2 sat inside the
             * fd-tick CALL-HOOK (runs only when guest executes one of four
             * specific fns AND pending/kick nonzero; my gate needs pending==0
             * = mathematically dead). R458's comment said it: "every arm
             * shipped there is dead on arrival." The real tick is HERE.
             * Supply-only: load the sector + arm pending=1; the PROVEN hook
             * conversion (guest polls 0x800415B4 at state 6 per R333 watcher)
             * delivers the INT1 + handler pair when the guest arrives. No
             * guest dispatch from signal context (R350). Sector index kept
             * in-runtime (game zeroes FDF8 each pass — Lesson 53). */
            {
                uint32_t fp_fe1c = xenolift_mem_read32(0x8004FE1Cu);
                uint32_t fp_fe08 = xenolift_mem_read32(0x8004FE08u);
                static uint32_t fp_seen;
                if (fp_seen < 12u) {
                    fp_seen++;
                    fprintf(stderr, "[f14pump] R559 eval fe1c=%u fe08=%08X seek=%u pend=%u sched=%u\n",
                            fp_fe1c, fp_fe08, cd_seek_lba, cd_pending, cd_scheduled);
                }
                /* R559: c127 — FIRST ARM FIRED (idx=0, callback ran a 3rd time,
                 * game state walked 6->1->0 and parked in a status-poll loop at
                 * 1F801803 acking our INTs). Continue the ReadN walk at BOTH
                 * postures: the state-6 data wait AND the between-sectors
                 * state-0 poll (ReadN = continuous read; the game's own state
                 * machine cycles 6->5->6->1->0->6 between sectors). */
                /* R577 [f15pump v3]: c145 — v2 armed ONCE then waited
                 * forever for a consumption that never came (fe08 never
                 * left EAF8; the 60s pass restart needs idx>=2 to reset).
                 * MODEL FIX: the game's FE08 copy pointer IS the ground
                 * truth — derive the sector index from it (idx = (fe08 -
                 * EAF8) >> 11) instead of counting our own arms. Arm that
                 * sector, hold a few ticks; if the game still hasn't copied
                 * it, RE-ARM the same sector (delivery retry — the INT1
                 * conversion is fd-tick-gated and can miss). Consumption is
                 * receipted. Restart detection is free: fe08 drops -> idx
                 * drops -> re-stream from the new position. saw15 (the
                 * proof of a live file-15 read) clears whenever the game
                 * seeks the directory (0/1) with fe08 back at base, so we
                 * never inject sectors into the directory pass. */
                {
                    { /* R580: one-shot callback-table dump at the file-15 posture */
                        static int ftd = 1;
                        if (ftd-- > 0 && xenolift_mem_read32(0x8004FE08u) >= 0x8007E000u) {
                            fprintf(stderr, "[f15pump] R580 cbtab dump: F00=%08X F04=%08X F08=%08X F0C=%08X F10=%08X F14=%08X F18=%08X F1C=%08X F20=%08X F24=%08X F28=%08X F2C=%08X\n",
                                    xenolift_mem_read32(0x80059F00u), xenolift_mem_read32(0x80059F04u),
                                    xenolift_mem_read32(0x80059F08u), xenolift_mem_read32(0x80059F0Cu),
                                    xenolift_mem_read32(0x80059F10u), xenolift_mem_read32(0x80059F14u),
                                    xenolift_mem_read32(0x80059F18u), xenolift_mem_read32(0x80059F1Cu),
                                    xenolift_mem_read32(0x80059F20u), xenolift_mem_read32(0x80059F24u),
                                    xenolift_mem_read32(0x80059F28u), xenolift_mem_read32(0x80059F2Cu));
                        }
                    }
                    uint32_t fp2_fe1c = xenolift_mem_read32(0x8004FE1Cu);
                    uint32_t fp2_fe08 = xenolift_mem_read32(0x8004FE08u);
                    static uint32_t fp2_saw15; static uint32_t fp2_hold;
                    static uint32_t fp2_cons; static uint32_t fp2_rt;
                    if (fp2_fe08 >= 0x8007EAF8u && fp2_fe08 < (0x8007EAF8u + (45u << 11))) {
                        uint32_t fp2_idx = (fp2_fe08 - 0x8007EAF8u) >> 11;
                        if (fp2_idx != fp2_cons) {
                            if (fp2_idx > fp2_cons) { static uint32_t fp2_cn; if (fp2_cn < 90u) { fp2_cn++;
                                fprintf(stderr, "[f15pump] R577: CONSUMED - game copied %u sector(s), next dest=%08X\n",
                                        fp2_idx, fp2_fe08); } }
                            else { static uint32_t fp2_rn; if (fp2_rn < 24u) { fp2_rn++;
                                fprintf(stderr, "[f15pump] R579: RESTART - fe08 fell back to %08X (had reached idx %u) - pass restarted, re-streaming\n",
                                        fp2_fe08, fp2_cons); } }
                            fp2_cons = fp2_idx;
                        }
                        /* R579 trace: slow-mo on one consumption gap (treadmill diagnosis) */
                        { static uint32_t fp2_trace_on; static uint32_t fp2_tn;
                          if (fp2_cons >= 1u && fp2_trace_on == 0u && fp2_tn == 0u) fp2_trace_on = 1u;
                          if (fp2_trace_on == 1u && fp2_tn < 60u) {
                            fp2_tn++;
                            fprintf(stderr, "[f15trace] R579 tick: fe1c=%u fe08=%08X pend=%u seek=%u hold=%u cons=%u\n",
                                    fp2_fe1c, fp2_fe08, cd_pending, cd_seek_lba, fp2_hold, fp2_cons);
                            if (fp2_cons >= 2u) { fp2_trace_on = 2u;
                                fprintf(stderr, "[f15trace] R579: capture done (consumed %u)\n", fp2_cons); }
                          }
                        }
                        if (fp2_idx >= 45u) { static uint32_t fp2_done; if (fp2_done == 0u) { fp2_done = 1u;
                                fprintf(stderr, "[f15pump] R578: FILE-15 COMPLETE - all 45 sectors stored (fe08=%08X)\n", fp2_fe08); } }
                        if (fp2_fe08 == 0x8007EAF8u && (cd_seek_lba == 0u || cd_seek_lba == 1u)) fp2_saw15 = 0u;
                        if (cd_seek_lba == 108995u) fp2_saw15 = 1u;
                        if (fp2_hold > 0u) fp2_hold--;
                        if ((fp2_fe1c == 10u || fp2_fe1c == 6u || fp2_fe1c == 0u)
                            && cd_pending == 0u && fp2_hold == 0u && fp2_idx < 45u
                            && (fp2_idx > 0u || fp2_saw15 == 1u)) {
                            uint32_t fp2_lba = 108995u + fp2_idx;
                            fp2_hold = 1u;
                            cd_seek_lba = fp2_lba;
                            cd_data_load();
                            cd_pending = 1;
                            { static uint32_t fp2_log;
                              if (fp2_log < 90u) { fp2_log++;
                                if (fp2_rt > 0u) {
                                    fprintf(stderr, "[f15pump] R577: RETRY arm idx=%u LBA=%u dest=%08X pend=1\n",
                                            fp2_idx, fp2_lba, fp2_fe08);
                                    fp2_rt = 0u;
                                } else {
                                    fprintf(stderr, "[f15pump] R577: armed file-15 sector idx=%u LBA=%u dest=%08X pend=1\n",
                                            fp2_idx, fp2_lba, fp2_fe08);
                                }
                              } }
                        } else if (fp2_hold == 0u && cd_pending == 0u
                                   && (fp2_fe1c == 10u || fp2_fe1c == 6u || fp2_fe1c == 0u)) {
                            fp2_rt++;
                        }
                    }
                }
                                if ((fp_fe1c == 6u || fp_fe1c == 0u)
                    && fp_fe08 >= 0x801D9724u && fp_fe08 < (0x801D9724u + 125304u)
                    && cd_seek_lba >= 108900u && cd_seek_lba < 108996u
                    && cd_pending == 0) {
                    static uint32_t fp_idx; static uint32_t fp_epoch; static uint32_t fp_last_fe04;
                    uint32_t fp_fe04 = xenolift_mem_read32(0x8004FE04u);
                    if (fp_epoch == 0u || (fp_fe04 != 0u && fp_last_fe04 == 0u)) fp_idx = 0u;
                    fp_epoch = 1u; fp_last_fe04 = fp_fe04;
                    static uint32_t fp_cooldown;
                    if (fp_cooldown > 0u) fp_cooldown--;
                    if (fp_cooldown == 0u && fp_idx < 62u) {
                        uint32_t fp_lba = 108933u + fp_idx;
                        if (fp_lba < 108995u) {
                            fp_cooldown = 3u;
                            cd_seek_lba = fp_lba;
                            cd_data_load();
                            cd_pending = 1;   /* hook conversion delivers when guest polls 800415B4 */
                            { static uint32_t fp_log;
                              if (fp_log < 80u) { fp_log++;
                                fprintf(stderr, "[f14pump] R559: armed sector idx=%u LBA=%u dest=%08X pend=1\n",
                                        fp_idx, fp_lba, fp_fe08);

                /* R560 [f14land]: c128 — seek walked +28 (108933->108961, standard
                 * path served sectors!) but the landing zone head still reads ZERO
                 * and the game parks in an ack loop. Camera: per tick, era-gated,
                 * log any CHANGE in the dest head (first 8 bytes at 801D9724) and
                 * the batch cells — who (if anyone) ever writes the landing zone? */
                {
                    static uint32_t fl_last; static uint32_t fl_n;
                    uint32_t fl_head = xenolift_mem_read32(0x801D9724u);
                    uint32_t fl_fe08 = xenolift_mem_read32(0x8004FE08u);
                    uint32_t fl_fdf8 = xenolift_mem_read32(0x8004FDF8u);
                    if ((fl_head != fl_last || fl_n == 0u) && fl_n < 20u
                        && cd_seek_lba >= 108933u && cd_seek_lba < 108996u) {
                        fl_n++;
                        fprintf(stderr, "[f14land] R560 #%u: dest-head=%08X FE08=%08X FDF8=%u seek=%u pend=%u cmd=%02X\n",
                                fl_n, fl_head, fl_fe08, fl_fdf8, cd_seek_lba, cd_pending, cd_last_cmd);
                        fl_last = fl_head;
                    }
                }
                              }
                            }
                            fp_idx++;
                        }
                    }
                }
            }

    /* R458 UNCONDITIONAL ARM (c218 verdict: the camera photographed the
     * stall THROUGH its last visible state (pend=3 cmd=01 FE1C=1) then went
     * DARK while [wd] kept printing every round — the fd-tick branch that
     * hosts the camera + R122 + all stall arms is gated by the spin-context
     * detector, which stops matching when the game's wait loop changes shape
     * at t~46. Every arm shipped there is dead on arrival. This copy lives at
     * the TOP of on_alarm, unconditional: fires every round no matter what
     * the guest is waiting on. Same unique-batch fence as R457 variant-B. */
    static uint32_t fld3_era; /* R459: latched once batch-3 read era begins */
    if (cd_seek_lba >= 108995u && (cd_scheduled || cd_read_active)) fld3_era = 1u;
        /* R462: POST-FREEZE CAMERA — c24/c25 verdict: sector flow STOPS at LBA
         * 108946 (~t=32s) but the batch handler keeps ticking FDE4 on empty
         * (c25: FDE4 reached 105 with zero new sectors) — the existing camera
         * + arms stop matching at the new wait shape, leaving us blind.
         * Photograph the frozen drive state every 20s once no sector has been
         * delivered for 20s: batch-list cells, queue nodes, read struct. */
        if (fld3_era) { /* R463: was g_fld_stream && — dead flag, camera never armed */
            static time_t frz_last_chg; static uint32_t frz_last_cnt; static uint32_t frz_n;
            if (g_fldsec_total != frz_last_cnt) {
                frz_last_cnt = g_fldsec_total; frz_last_chg = run_now;
            } else if (frz_n < 40u && (run_now - frz_last_chg) >= 15) {
                fprintf(stderr, "[fldfrz] t=%lds sectors=%u | seek=%u pend=%u sched=%u act=%u arm1=%u loaded=%u data=%u/%u cmd=%02x resp=%u/%u | FDF8=%u FE04=%08x FE1C=%u FE20=%u FDE4=%08x FDE8=%08x | batch FE08=%08x FE0C=%08x FE10=%08x FE34=%08x | q10=%08x/%08x q18=%08x/%08x | rs+18=%08x rs+1C=%08x\n",
                        (long)(run_now - g_boot_wall_t0), g_fldsec_total,
                        cd_seek_lba, cd_pending, cd_scheduled, cd_read_active,
                        cd_arm_int1_pending, cd_data_loaded, cd_data_pos, cd_data_n,
                        cd_last_cmd, cd_resp_n, cd_resp_pos,
                        xenolift_mem_read32(0x8004FDF8u),
                        xenolift_mem_read32(0x8004FE04u),
                        xenolift_mem_read32(0x8004FE1Cu),
                        xenolift_mem_read32(0x8004FE20u),
                        xenolift_mem_read32(0x8004FDE4u),
                        xenolift_mem_read32(0x8004FDE8u),
                        xenolift_mem_read32(0x8004FE08u),
                        xenolift_mem_read32(0x8004FE0Cu),
                        xenolift_mem_read32(0x8004FE10u),
                        xenolift_mem_read32(0x8004FE34u),
                        xenolift_mem_read32(0x80059F10u), xenolift_mem_read32(0x80059F14u),
                        xenolift_mem_read32(0x80059F18u), xenolift_mem_read32(0x80059F1Cu),
                        xenolift_mem_read32(0x80059EF8u + 0x18u), xenolift_mem_read32(0x80059EF8u + 0x1Cu));
                frz_last_chg = run_now; frz_n++;
            }
        }
    /* R521[dirack] — c88 verdict: THE GLYPH WALL IS DEAD (glyphguard
     * restore #1, fault-kit 0 blocks, first full-budget run of the era,
     * 200s of textured menu rects). NEW WALL: the post-mount directory
     * scan asks for sector LBA 1 (Setloc 00:02:01) and then sits at
     * FE1C=10, cmd=0x02, resp_n=0 for 150+s (fldfrz t=64..192 frozen):
     * the game is polling for the 3-byte ack to its command and our
     * answer FIFO is EMPTY — the boot-era auto-answer armed answers for
     * the boot reads, not this request. The existing re-prime (R212)
     * only fires when (cd_pending || cd_last_cmd) at the moment
     * resp_pos >= resp_n, but here the pair was already consumed and
     * the drive shows idle bookkeeping. HEAL (R502 latch family): when
     * the directory-era state machine polls with an empty answer
     * window, arm one tick then prime the standard Setloc/ReadN ack
     * [02 01 01] into the response FIFO so the game pops it (rspop
     * path), advances its state machine, and issues the actual ReadN
     * for LBA 1 - which the generic sector loader then serves from
     * disc (disc_read_lba(1)), and the zrf0 force-deliver completes
     * the copy. 12-fire budget, flutter-tolerant arm (R510 pattern). */
    {
        static int da_armed; static int da_fires;
        uint32_t fe1c_da = xenolift_mem_read32(0x8004FE1Cu);
        if (da_fires < 12u && cd_seek_lba > 0u && cd_seek_lba < 150u
            && fe1c_da == 10u && cd_last_cmd == 0x02u
            && cd_resp_n == 0u && cd_resp_pos == 0u) {
            /* R522: c89 — the !cd_read_active gate blocked the heal
             * forever (fldfrz act=1 across the whole freeze while the
             * sector data already loads). Prime regardless of drive
             * state; the state-10 poll only wants its ack bytes. */
            if (da_armed) {
                da_armed = 0; da_fires++;
                cd_resp[0] = 0x02u; cd_resp[1] = 0x01u; cd_resp[2] = 0x01u;
                cd_resp_n = 3u; cd_resp_pos = 0u;
                /* R525: c92 — prime LANDED (fld2sig resp_n=3) but game never
                 * popped it (resp_pos=0 for 140s): an ack needs a DOORBELL.
                 * Arm pending so the boot-era handler-pair conversion rings the
                 * guest's CD handler -> rspop delivers the 3 bytes. */
                if (cd_pending == 0u) {
                    cd_pending = 1u;
                    fprintf(stderr, "[dirack] R525: doorbell armed - handler pair will deliver the ack (rspop path)\n");
                }
                fprintf(stderr, "[dirack] R521: empty-ack heal fire #%d (seek=%u FE1C=10 cmd=02) - [02 01 01] primed, game pops + advances\n",
                        da_fires, cd_seek_lba);
            } else {
                da_armed = 1;
            }
        } else {
            if (fe1c_da != 10u) da_armed = 0;
        }
    }

    /* R526 [dirack2]: c94 - R525 doorbell WORKED: the game popped the
     * Setloc ack, left state 10, issued ReadS (cmd 09) and now parks at
     * FE1C=0 with a short 1-byte answer staged (resp=1/0) and no bell.
     * Same family, next door: top the answer up to the full 3-byte ack
     * and ring the handler-pair bell so the guest pops it and advances. */
    {
        static int d9_armed; static int d9_fires;
        uint32_t fe1c_d9 = xenolift_mem_read32(0x8004FE1Cu);
        if (d9_fires < 24u && cd_seek_lba > 0u && cd_seek_lba < 150u
            && fe1c_d9 == 0u && cd_last_cmd == 0x09u
            && cd_resp_n > 0u && cd_resp_pos == 0u && cd_pending == 0u
            && cd_arm_int1_pending == 0) {
            if (d9_armed) {
                d9_armed = 0; d9_fires++;
                cd_resp[0] = 0x02u; cd_resp[1] = 0x01u; cd_resp[2] = 0x01u;
                cd_resp_n = 3u; cd_resp_pos = 0u;
                cd_pending = 1u;
                fprintf(stderr, "[dirack2] R526: ReadS-ack doorbell fire #%d (seek=%u FE1C=0 cmd=09) - 3-byte ack + bell armed\n", d9_fires, cd_seek_lba);
            } else {
                d9_armed = 1;
            }
        } else {
            if (!(fe1c_d9 == 0u && cd_last_cmd == 0x09u)) d9_armed = 0;
        }
    }


    if (cd_seek_lba >= 108900u || (fld3_era && cd_pending == 0u)) {
        static uint32_t fld3_n;
        if (fld3_n < 60u) {
            fprintf(stderr, "[fld2sig] UNCOND sched=%u seek=%u pend=%u arm1=%u loaded=%u data=%u/%u cmd=%02x FDF8=%u FE04=%08x FE1C=%u resp_n=%u\n",
                    cd_scheduled, cd_seek_lba, cd_pending, cd_arm_int1_pending,
                    cd_data_loaded, cd_data_pos, cd_data_n, cd_last_cmd,
                    xenolift_mem_read32(0x8004FDF8u),
                    xenolift_mem_read32(0x8004FE04u),
                    xenolift_mem_read32(0x8004FE1Cu), cd_resp_n);
                    /* R542 [fldbell2]: c108-c110 — three completion signals
                     * delivered (end-of-read FE04, read-active clear, sched
                     * clear) and the kernel STILL holds at its FE1C=10
                     * poll with our 3-byte answer primed but UNCONSUMED.
                     * In the working dance every step advanced by INT1
                     * delivery + answer pop; at the wall we armed the
                     * answer and silenced every bell (pending/sched all
                     * cleared) — nobody RANG. Re-arm the doorbell at the
                     * wall: arm pending INT1 (rate-limited) so the existing
                     * handler-pair machinery delivers it and the kernel
                     * consumes the GetStat answer. */
                    {
                        static uint32_t bell_n; static uint32_t bell_c;
                        uint32_t fe1c0 = xenolift_mem_read32(0x8004FE1Cu);
                        uint32_t fdf8w = xenolift_mem_read32(0x8004FDF8u);
                        if (cd_seek_lba >= 108995u && cd_seek_lba <= 108996u &&
                            fdf8w == 0u && cd_pending == 0u &&
                            (fe1c0 == 10u || fe1c0 == 11u || fe1c0 == 6u)) {
                            /* R544 [fldbell3]: c112 — fldbell2 fired ZERO times:
                             * (a) rate limiter needed 64 probe invocations but the
                             * probe only ran ~47x at the wall; (b) resp_n>=3 gate
                             * failed because the kernel POPS each primed answer,
                             * emptying the FIFO. The bell must SELF-PRIME: fresh
                             * [02 01 01] + armed pending, every 8th invocation
                             * (~1-2s), cap 40 fires. Handler contract decoded
                             * c112 (L_8002AAF0): needs dispatcher call w/ r4=2,
                             * byte@r5 bit4 clear, then writes FE1C=11. */
                            if (++bell_c >= 8u) {
                                bell_c = 0;
                                if (bell_n < 40u) {
                                    bell_n++;
                                    cd_resp[0] = 0x02; cd_resp[1] = 0x01; cd_resp[2] = 0x01;
                                    cd_resp_n = 3; cd_resp_pos = 0;
                                    cd_pending = 1;
                                    fprintf(stderr, "[fldbell3] R544: doorbell fire #%u — answer [02 01 01] primed + INT1 armed (FE1C=%u)\n",
                                            bell_n, fe1c0);
                                }
                            }
                        }
                    }

            /* R532 [dirack4]: c100 verdict - the game re-issued Setloc at seek
             * 108934 (field era) and parks at FE1C=1 with an EMPTY answer
             * (resp 0/0, no bell) while the sector sits staged. Boot-era rspop
             * receipts prove Setloc acks pop AT FE1C=1 with n=3 [02 01 01].
             * The R521 heal lives in the dirscan-era context (seek<150) and is
             * blind here. Same service, placed in THIS poll because c97-99
             * digests prove the UNCOND poll runs during the field stall (final
             * line: UNCOND ... cmd=02 FE1C=1 resp_n=0). Flutter arm + 24 fires. */
            {
                static int da4_armed; static int da4_fires; static uint32_t da4_seek;
                uint32_t fe1c_da4 = xenolift_mem_read32(0x8004FE1Cu);
                if (cd_seek_lba >= 150u && fe1c_da4 == 1u && cd_last_cmd == 0x02u &&
                    cd_resp_n == 0u && cd_resp_pos == 0u && cd_pending == 0u &&
                    cd_data_n >= 2048u && da4_fires < 128u) {
                    da4_armed = 0; if (cd_seek_lba != da4_seek) { da4_seek = cd_seek_lba; da4_fires = 0; } da4_fires++;
                    if (1) {
                        cd_resp[0] = 0x02u; cd_resp[1] = 0x01u; cd_resp[2] = 0x01u;
                        cd_resp_n = 3u; cd_resp_pos = 0u;
                        cd_pending = 1u;
                        fprintf(stderr, "[dirack4] R532: field-era Setloc-ack doorbell fire #%d (seek=%u FE1C=1 cmd=02 data_n=%u) - [02 01 01] primed + bell\n",
                                da4_fires, cd_seek_lba, cd_data_n);
                    } else {
                        da4_armed = 1;
                    }
                } else {
                    if (!(fe1c_da4 == 1u && cd_last_cmd == 0x02u)) da4_armed = 0;
                }
            }
            fld3_n++;
        }
        /* R503b FLDBELL v2 — c70 verdict: the R503 copy lives in the
         * response-pop region (never executes during the stall: the game
         * waits in FE1C=0x0A without popping). THIS copy lives at on_alarm
         * TOP (runs every round, proven by the [fldfrz]/[fld2sig] camera).
         * Stall signature c69/c70 (frozen 74s): seek=108995, sched=1,
         * pend=0, arm1=0, FDF8=0, resp_n=0, cmd=01 (GetStat), FE1C=0x0A,
         * data_loaded=0 BUT data_n=2060 (stale leftover) — variant-C
         * requires data_n==0 so it can't hear this shape; my R503 copy
         * required data_pos<data_n discard in a dead context. Action:
         * discard the stale leftover (fd-kick pattern), close the
         * stalled-dead read, ring the GetStat bell exactly like the
         * proven variant-C arm (pend=1 + irq force; the converter pair
         * restores the full 02/01/01 answer). */
        if ((cd_scheduled == 1u || cd_read_active == 1u)
            && cd_pending == 0u && cd_arm_int1_pending == 0
            && fld3_era
            && cd_seek_lba >= 108900u
            && xenolift_mem_read32(0x8004FDF8u) == 0u
            && cd_resp_n == 0u && cd_resp_pos == 0u
            && cd_last_cmd == 0x01u
            && cd_data_n > 0u
            && xenolift_mem_read32(0x8004FE1Cu) <= 0x1Fu) { /* R505: any state — c71 idle-shape */
            { static uint32_t fldbell2_n;
              if (fldbell2_n < 50u) {
                fldbell2_n++;
                fprintf(stderr, "[fldbell] R503b: stale %uB leftover discarded + stalled-dead read closed (seek=%u cmd=01 FE1C=0x0A) - GetStat bell rung\n",
                        cd_data_n, cd_seek_lba);
              }
            }
            cd_data_pos = cd_data_n = 0;
            cd_arm_int1_pending = 0;
            cd_read_active = 0;
            cd_pending = 1;
            g_cd_irq_force = 1;
        }
        /* R549 FE34FIX — c117: dirloop v2 receipts prove the decoded ArchiveCurrentFileReadyCallback
         * (0x8002B084) walks its whole file-stream (FE08 dest +0x800/sector, FDF8 -2048/sector) but its
         * copy path is gated on FE34 (batch sector count) > 0 — and FE34 is 0 at EVERY callback entry.
         * Result: banks stay empty (wdsdiff ram=00) and wdsheal must re-shelve every file. The honest fix:
         * prime FE34=1 per in-flight sector read when the callback is armed and the count is unarmed.
         * The game's OWN copy path then fills its banks; re-shelving patches become unnecessary. */
        if (0) { /* R564 REMOVED R549 tick-prime TOO: same disasm verdict as R551 —
                 * FE34>0 = SKIP-copy + teardown (HandleCdReadyCompletion -> FDF8=0 +
                 * PositionArchiveEntry = the re-dance). Both primes were the bug. */
            xenolift_mem_write32(0x8004FE34u, 1u);
            { static uint32_t fe34n;
              if (fe34n < 40u) {
                fe34n++;
                fprintf(stderr, "[fe34fix] R549: batch count FE34 primed 0->1 (dest FE08=%08X FDF8=%u) - game copy path unblocked\n",
                        xenolift_mem_read32(0x8004FE08u), xenolift_mem_read32(0x8004FDF8u));
              }
            }
        }
        /* R545 FLDBELL4 — c113: the mount phase issues NEW reads (seek=0 dir
         * re-read, cmd=02 Setloc-ack shape) that stall in the SAME state-10
         * posture. Gate on POSTURE, not seek: kernel parked at FE1C=10 with
         * no answer (resp 0/0), nothing real left in the runtime fifo
         * (empty, or the stale-2060 leftover after guest DMA delivery), and
         * a stale nonzero FDF8 byte-count. Discard leftovers, close the
         * read, ring the GetStat bell (proven R503b pattern). */
        { /* R565 STREAK GATE: c133 — the copy loop WORKS now (dest advances 0x800/sector,
         * file-14 hit 11% in 8s) but this bell fired MID-STREAM at the sector boundary
         * (same posture as a true stall) and closed a read with 110KB still owed —
         * deadlock, dead run at 12s. A LIVE stream's FDF8+seek CHANGE between ticks;
         * a TRUE stall is frozen. Ring only after 3 consecutive ticks unchanged. */
          static uint32_t pb_prev_fdf8, pb_prev_seek, pb_streak;
          uint32_t pb_now_fdf8 = xenolift_mem_read32(0x8004FDF8u);
          if (pb_now_fdf8 == pb_prev_fdf8 && cd_seek_lba == pb_prev_seek && pb_now_fdf8 != 0u)
              pb_streak++;
          else
              pb_streak = 0;
          pb_prev_fdf8 = pb_now_fdf8; pb_prev_seek = cd_seek_lba;
          if (pb_streak >= 3u
            && (cd_scheduled == 1u || cd_read_active == 1u)
            && cd_pending == 0u && cd_arm_int1_pending == 0
            && cd_resp_n == 0u && cd_resp_pos == 0u
            && (cd_data_n == 0u || (cd_data_loaded == 1u && cd_data_pos == 0u && cd_data_n == 2060u))
            && xenolift_mem_read32(0x8004FE1Cu) <= 0x1Fu
            && pb_now_fdf8 != 0u) {
            uint32_t fdf8s = pb_now_fdf8;
            { static uint32_t bell4_n;
              if (bell4_n < 60u) {
                bell4_n++;
                fprintf(stderr, "[fldbell4] R545: posture bell — stale FDF8=%u discarded, stalled read closed (seek=%u cmd=%02x loaded=%u data=%u/%u) - GetStat bell rung\n",
                        fdf8s, cd_seek_lba, cd_last_cmd, cd_data_loaded, cd_data_pos, cd_data_n);
              }
            }
            xenolift_mem_write32(0x8004FDF8u, 0u);
            cd_data_pos = cd_data_n = 0;
            cd_data_loaded = 0;
            cd_arm_int1_pending = 0;
            cd_read_active = 0;
            cd_scheduled = 0;
            cd_pending = 1;
            g_cd_irq_force = 1;
} }
        /* R506 CBHEAL — c72: bell freed the batch handler and it now cycles
         * (FE1C 0A->0B->06->01->02->00 loop) but re-seeks LBA 108934 forever:
         * the field-era read struct's ready-callback slot (0x80059EF8+0x10 =
         * 0x80059F08) is ZERO — [cbreg] shows the game registering NULL
         * callbacks and the park read struct confirms +10=00000000. Sectors
         * DMA into the ring but no one consumes them (fldsec stuck at #32).
         * Boot era proves the correct value: the game's own ready-callback
         * fn_8002B084 (ArchiveCurrentFileReadyCallback — copies each ready
         * sector into the destination, advances remaining-byte state). Re-arm
         * the slot only-when-zero, same discipline as the pad/latch heals. */
        static uint32_t cbheal_n;
        if (fld3_era && cd_scheduled
            && xenolift_mem_read32(0x80059F08u) == 0u
            && cbheal_n < 400u) {
            cbheal_n++;
            xenolift_mem_write32(0x80059F08u, 0x8002B084u);
            fprintf(stderr, "[cbheal] R506: field read ready-callback re-armed (0x80059F08: 0 -> 0x8002B084) seek=%u\n",
                    cd_seek_lba);
        }
        /* R460: VARIANT-C ARM — c221 verdict: R459's variant-B arm fired at
         * 108995 AND the game kept walking (batch counter 0x33 -> 0x55, field
         * sectors 108939-108945 landed in the field ring 0x801D73D8+, GPU
         * snapshots doubled). NEW third stall shape at halt: era latched,
         * seek=0 (front-matter verify), ReadN armed but conveyor EMPTY
         * (loaded=0 data=0/0) with pend=0 arm1=0 resp_n=0 FDF8=0 FE04=0
         * FE1C=11 — variant-B requires loaded+data so it can't hear this.
         * Ring the bell on the EMPTY-conveyor signature; the game's state-11
         * dispatcher drives its own read stepper on the ring (that is how
         * 108995 released). Fence: seek==0 or >=108900, era latched. */
        if ((cd_scheduled == 1u || cd_read_active == 1u)
            && cd_pending == 0u && cd_arm_int1_pending == 0
            && fld3_era
            && (cd_seek_lba == 0u || cd_seek_lba >= 108900u)
            && xenolift_mem_read32(0x8004FDF8u) == 0u
            && xenolift_mem_read32(0x8004FE04u) == 0u
            && cd_resp_n == 0u
            && cd_data_loaded == 0u && cd_data_n == 0u
            && cd_last_cmd == 0x01u) {
            cd_pending = 1;
            g_cd_irq_force = 1;
            { static uint32_t fld3c_n;
              if (fld3c_n < 24u) {
                fprintf(stderr, "[fld2sig] UNCOND-ARM-C fired (seek=%u pend set=1 loaded=0 data=0/0 cmd=01 FE1C=%u)\n",
                        cd_seek_lba,
                        xenolift_mem_read32(0x8004FE1Cu));
                fld3c_n++;
              }
            }
        }

            /* R527 [dirack3]: c95 — dirack2 WORKED (FDE4 0x12->0x13, game past
             * the ReadS ack) and the LBA-1 sector data is loaded in the FIFO
             * (data_n=2060, loaded=1) — but the game now polls GetStat
             * (cmd=01, FE1C=0) with an EMPTY answer window (resp_n=0) and no
             * bell. Boot-era GetStat pops n=1 val=0x02 at FE1C=0 — same
             * service here: prime the status byte, ring the handler-pair bell
             * so the state machine advances to consume the sector data. */
            {
                static int d1_armed; static int d1_fires;
                uint32_t fe1c_d1 = xenolift_mem_read32(0x8004FE1Cu);
                if (d1_fires < 12u && cd_seek_lba > 0u && cd_seek_lba < 150u
                    && fe1c_d1 == 0u && cd_last_cmd == 0x01u
                    && cd_resp_n == 0u && cd_resp_pos == 0u && cd_pending == 0u
                    && cd_data_loaded != 0u) {
                    if (d1_armed) {
                        d1_armed = 0; d1_fires++;
                        cd_resp[0] = 0x02u;
                        cd_resp_n = 1u; cd_resp_pos = 0u;
                        cd_pending = 1u;
                        fprintf(stderr, "[dirack3] R527: GetStat doorbell fire #%d (seek=%u FE1C=0 cmd=01 loaded=1) - [02] primed + bell\n",
                                d1_fires, cd_seek_lba);
                    } else {
                        d1_armed = 1;
                    }
                } else {
                    if (!(fe1c_d1 == 0u && cd_last_cmd == 0x01u)) d1_armed = 0;
                }
            }
        /* R459: signature arm — c219 verdict: UNCOND-ARM FIRED at 108995,
         * the stalled read RELEASED and the game advanced to a NEW seek
         * (LBA 0 system-area verify, park seek_lba=0). The old fixed fence
         * can't hear the new stall. Arm now on the stall SIGNATURE within
         * the latched field-3 era: bell dropped (pend=0 arm1=0), sector
         * loaded+undrained, drive idle (FDF8=0 FE04=0 resp_n=0) — matches
         * the photographed 108995 drop AND the new LBA-0 drop; excludes
         * healthy rounds (cmd=06/FDF8!=0/FE04!=0). */
        if ((cd_scheduled == 1u || cd_read_active == 1u)
            && cd_pending == 0u && cd_arm_int1_pending == 0
            && fld3_era
            && xenolift_mem_read32(0x8004FDF8u) == 0u
            && xenolift_mem_read32(0x8004FE04u) == 0u
            && cd_resp_n == 0u
            && cd_data_loaded == 1u && cd_data_n > 0u) {
            cd_pending = 1;
            g_cd_irq_force = 1;
            { static uint32_t fld3a_n;
              if (fld3a_n < 24u) {
                fprintf(stderr, "[fld2sig] UNCOND-ARM fired (seek=%u pend set=1 data=%u/%u cmd=02)\n",
                        cd_seek_lba, cd_data_pos, cd_data_n);
                fld3a_n++;
              }
            }
        }
    }
    /* R410 FIELD PUMP TIMELINE (c167): the R409 arm WORKED — the field
     * sectors flowed natively (LBA 108933-108938, FDF8 125304 -> 115064,
     * DMA into the field dest ring 0x801D0BD8+0x800/sector) for SIX
     * sectors, then the guest queue stepper stopped (park: seek=108939,
     * FDF8=112504, sector loaded, pending=0 — mid-read stall, cause
     * unknown; the one-shot [frc]/instance probes are blind here: the
     * field signature never dropped). Ride the 15s watchdog cadence:
     * while the field read is alive-but-undone, dump the full pump
     * state every tick — the timeline shows WHEN it stops and WHICH
     * cell freezes first (stepper flag vs queue node vs dest pointer).
     * Budget 20 lines (~13 ticks in a 195s run). */
    {
        static int fp_n;
        uint32_t fp_fdf8 = xenolift_mem_read32(0x8004FDF8u);
        if (fp_n < 20 && fp_fdf8 > 0u && cd_seek_lba >= 108900u /* R415: >0 not >100000 — file 2 (29048B) was invisible; era-size lesson */
            && (cd_last_cmd == 0x06u || cd_last_cmd == 0x09u
                || cd_last_cmd == 0x01u)) { /* R412: keep the timeline alive
                                             * across the mid-read cmd-01 probe
                                             * sub-era (c169 went blind). */
            fprintf(stderr, "[fldpump] t=%lds act=%d loaded=%d data=%u/%u pend=%u sched=%u arm1=%d cmd=%02X seek=%u FDF8=%u FE04=%08X FE1C=%u FE20=%u node59F10=%08X/%08X FE08=%08X FE0C=%08X FE10=%08X FDE4=%08X\n",
                    (long)(run_now - g_boot_wall_t0), cd_read_active, cd_data_loaded,
                    cd_data_pos, cd_data_n, cd_pending, cd_scheduled, cd_arm_int1_pending,
                    cd_last_cmd, cd_seek_lba, fp_fdf8,
                    xenolift_mem_read32(0x8004FE04u), xenolift_mem_read32(0x8004FE1Cu),
                    xenolift_mem_read32(0x8004FE20u),
                    xenolift_mem_read32(0x80059F10u), xenolift_mem_read32(0x80059F14u),
                    xenolift_mem_read32(0x8004FE08u), xenolift_mem_read32(0x8004FE0Cu),
                    xenolift_mem_read32(0x8004FE10u), xenolift_mem_read32(0x8004FDE4u));
            fprintf(stderr, "[fldpump]   r31=%08X r2=%08X r4=%08X r29=%08X (guest pc-adjacent regs at tick)\n",
                    r[31], r[2], r[4], r[29]);
            fp_n++;
        }
    }
    if (over_budget)
        fprintf(stderr, "[halt] run budget 210s from process start - parking now (bridge kills at 240s)\n");
    /* R221: STREAM-ALIVE — cycle-6 verdict: the boot is now streaming
     * big archive members (file 3 = 155,120B mid-flight at watchdog);
     * an active read with sectors still loading is WORK, not a stall.
     * Same bounded-defer class as the R148 render-alive path. */
    {
        static uint32_t last_sec; static int sdefers;
        if (!over_budget && cd_read_active && g_sectors_loaded != last_sec && sdefers < 40) {
            last_sec = g_sectors_loaded;
            sdefers++;
            fprintf(stderr, "[halt] stream alive (sectors=%u FDF8=%u seek=%u) — deferring watchdog (stream #%u)\n",
                    g_sectors_loaded, xenolift_mem_read32(0x8004FDF8u), cd_seek_lba, sdefers);
            alarm(2); /* R452: was 15 — round cadence is the field sector clock */
            return;
        }
    }
    /* R361: FIELD-STREAM LIVENESS — the file-14 stream advances ~1 sector
     * per poll round (consumer-driven; cycle-109: 27 sectors in 61s).
     * FE04 advancing = alive. Bounded defers keep the run inside the
     * 195s budget while the ~61-sector file completes (~135s). */
    {
        static uint32_t last_ff; static uint32_t last_rtry; static uint32_t last_fdf8; static uint32_t last_zs; static int fdefers;
        uint32_t ffe04 = xenolift_mem_read32(0x8004FE04u);
        uint32_t ffdf8 = xenolift_mem_read32(0x8004FDF8u);
        uint32_t frtry = xenolift_mem_read32(0x8004FDE8u); uint32_t fzseek = cd_seek_lba; /* R364: retry counter — a double-header desync makes FE04 freeze while the archive layer retries the sector (cycle-112: 24 consumers then stall @108959, park @77s with FE04 frozen = no defers). Retry-count movement = ALSO alive. */
        int alive = (ffe04 != last_ff) || (frtry != last_rtry) || (ffdf8 != last_fdf8) || (fzseek != last_zs) || (cd_scheduled && fzseek >= 108933u && fzseek <= 108995u); /* R536: in-window scheduled = alive outright (sector exchange may span rounds); R535: seek-LBA advance is the zrfm era's own clock; R461: FDF8 ticks every sector — the grind's own clock */
        if (!over_budget && ((g_fld_stream && ffdf8 > 0u) || (cd_scheduled && fzseek >= 108933u && fzseek <= 108995u)) && alive && fdefers < 120) {
            last_ff = ffe04; last_rtry = frtry; last_fdf8 = ffdf8; last_zs = fzseek; fdefers++;
            fprintf(stderr, "[halt] field-stream alive (FE04=%u FDF8=%u retry=%u) — deferring watchdog (fs #%u)\n",
                    ffe04, ffdf8, frtry, fzseek, fdefers);
            alarm(2); /* R452: was 15 — round cadence is the field sector clock */
            return;
        }
    }
    /* R312: MOVIE-POLL LIVENESS — the movie module's pre-movie polling loop
     * is the engine that force-delivers each CD event (cdf cadence); the
     * stress test needs many of those cycles to finish its passes. The
     * watchdog shooting the run at ~60s was cutting the checklist short
     * (cycles 59-60: verify passes climbing, X-skip countdown at 5->1, run
     * ends mid-loop). Poll iteration progress = alive. Bounded 25 defers
     * (~6 min worst case, fits the bridge patience window). */
    {
        static uint32_t last_mvp; static int mdefers;
        if (!over_budget && g_mv_poll_n != last_mvp && mdefers < 90) { /* R461: cap 14->90 — defers already bounded by run budget + fuse */
            last_mvp = g_mv_poll_n;
            mdefers++;
            fprintf(stderr, "[halt] movie-poll alive (n=%u) - deferring watchdog (mp #%u) | R325 timeline: cntdn(77014)=%u pass(77448)=%u frame(76F04)=%u FE1C=%u FE20=%u gdisp=%u\n",
                    g_mv_poll_n, mdefers,
                    xenolift_mem_read32(0x80077014u), xenolift_mem_read32(0x80077448u),
                    xenolift_mem_read32(0x80076F04u), xenolift_mem_read32(0x8004FE1Cu),
                    xenolift_mem_read32(0x8004FE20u), xenolift_mem_read32(0x80018088u));
            alarm(2); /* R452: was 15 — round cadence is the field sector clock */
            return;
        }
    }
    /* R78: if the park tick is driving interrupt-context machinery,
     * the boot is alive (IRQ emulation) — defer the watchdog. */
    if (!over_budget && xenolift_park_ticks != last_park && defers < 150) {
        last_park = xenolift_park_ticks;
        defers++;
        fprintf(stderr, "[halt] park alive (ticks=%u) — deferring watchdog #%u\n",
                xenolift_park_ticks, defers);
        alarm(2); /* R452: was 15 — round cadence is the field sector clock */
        return;
    }
    {
        static uint64_t last_words; static int rdefers;
        if (!over_budget && g_gpu_words != last_words && rdefers < 40) {
            last_words = g_gpu_words;
            rdefers++;
            fprintf(stderr, "[halt] render alive (prims=%u words=%llu last_prim=0x%08X tag=0x%08X) — deferring watchdog (render #%u)\n",
                    g_gpu_prims, (unsigned long long)g_gpu_words,
                    g_gpu_last_prim, g_gpu_last_tag, rdefers);
            alarm(2); /* R452: was 15 — round cadence is the field sector clock */
            return;
        }
    }
    {
        uint32_t idx, ph1, ph2;
        memcpy(&idx, xenolift_mem + (0x80018088u-0x80000000u), 4);
        memcpy(&ph1, xenolift_mem + (0x800592BCu-0x80000000u), 4);
        memcpy(&ph2, xenolift_mem + (0x800592C0u-0x80000000u), 4);
        fprintf(stderr, "[halt] dispatch index 0x80018088=%u  phase 0x800592BC=%08X 0x800592C0=%08X\n", idx, ph1, ph2);
        {
        uint32_t latch, callsite;
        memcpy(&latch,   xenolift_mem + (0x80059330u-0x80000000u), 4);
        memcpy(&callsite,xenolift_mem + (0x80059340u-0x80000000u), 4);
        {
        uint32_t h0, h2;
        memcpy(&h0, xenolift_mem + (0x8005932Cu-0x80000000u), 4);
        memcpy(&h2, xenolift_mem + (0x8005933Cu-0x80000000u), 4);
        fprintf(stderr, "[halt] trap cells: latch 0x80059330=%08X callsite 0x80059340=%08X heap 0x8005932C=%08X 0x8005933C=%08X\n", latch, callsite, h0, h2);
        {
        uint32_t fr, cl, term0, term1;
        memcpy(&fr, xenolift_mem + 0x6FAF0, 4);
        memcpy(&cl, xenolift_mem + 0x59318, 4);
        memcpy(&term0, xenolift_mem + 0x1FBFF8, 4);
        memcpy(&term1, xenolift_mem + 0x1FBFFC, 4);
        fprintf(stderr, "[halt] heap frontier=%08X class-cells=%08X term %08X %08X\n",
                fr, cl, term0, term1);
        fprintf(stderr, "[halt] polls: imask=%u istat=%u t2=%u gpu=%u sio=%u\n",
                g_poll_imask, g_poll_istat, g_poll_t2, g_poll_gpu, g_poll_sio);
        }
        }
        }
        int hits = 0;
        for (uint32_t a = 0x80010000u; a < 0x801F0000u && hits < 8; a += 4) {
            uint32_t w;
            memcpy(&w, xenolift_mem + (a-0x80000000u), 4);
            if (w == 0x80019EF8u) {
                fprintf(stderr, "[halt] fn ptr 0x80019EF8 stored at 0x%08X (index=%+.1f from table base 0x8001808C)\n",
                        a, ((double)((int32_t)a - (int32_t)0x8001808Cu))/16.0);
                hits++;
            }
        }
        if (!hits) fprintf(stderr, "[halt] fn ptr 0x80019EF8 NOT found in RAM\n");
    {   /* R83: device table 0x800625FC — entries 0/1 + gate byte */
        int i; uint8_t b, g;
        memcpy(&g, xenolift_mem + 0x59388, 1);
        fprintf(stderr, "[devt] gate 0x80059388=%02X  e0:", g);
        for (i = 0; i < 16; i++) {
            memcpy(&b, xenolift_mem + 0x625FC + i, 1);
            fprintf(stderr, "%02X", b);
        }
        fprintf(stderr, "  e1:");
        for (i = 34; i < 50; i++) {
            memcpy(&b, xenolift_mem + 0x625FC + i, 1);
            fprintf(stderr, "%02X", b);
        }
        fprintf(stderr, "\n");
    }
    }
    {
        uint32_t expect_lba, slot_byte;
        memcpy(&expect_lba, xenolift_mem + (0x8004FE04u-0x80000000u), 4);
        slot_byte = xenolift_mem[0x80056788u-0x80000000u];
        fprintf(stderr, "[cdstate] last_cmd=0x%02X read_active=%u data_loaded=%u pending=%u sched=%u\n",
                cd_last_cmd, cd_read_active, cd_data_loaded, cd_pending, cd_scheduled);
        fprintf(stderr, "[cdstate] resp_n=%u resp_pos=%u seek_lba=%u expected_lba=0x%08X slot=0x%02X\n",
                cd_resp_n, cd_resp_pos, cd_seek_lba, expect_lba, slot_byte);
        fprintf(stderr, "[cdstate] data_pos=%u data_n=%u arm1=%u\n", cd_data_pos, cd_data_n, cd_arm_int1_pending);
        fprintf(stderr, "[cdstate] FDFC=%u FDF8=%u FE1C=%u FE20=%u gate(0x80077194&0x10)=%u\n",
                xenolift_mem_read32(0x8004FDFCu), xenolift_mem_read32(0x8004FDF8u),
                xenolift_mem_read32(0x8004FE1Cu), xenolift_mem_read32(0x8004FE20u),
                (xenolift_mem_read32(0x80077194u) & 0x10u) >> 4);
        fprintf(stderr, "[cdstate] stream-node 0x80059F18: +C=%08X +10=%08X +14=%08X (result area — cycle-12 parked 02020202/02020202 = STAT filler, TOC answer never landed?)\n",
                xenolift_mem_read32(0x80059F18u + 0xCu), xenolift_mem_read32(0x80059F18u + 0x10u),
                xenolift_mem_read32(0x80059F18u + 0x14u));
        fprintf(stderr, "[hle] spu-writes=%u spu-dma-bytes=%u mdec-writes=%u\n",
                xl_spu_writes, xl_spu_dma_bytes, xl_mdec_writes);
        fprintf(stderr, "[hle] gpu-writes=%u\n", xl_gpu_writes);
        fprintf(stderr, "[hle] gte-cmds=%u\n", xl_gte_cmds);
        fprintf(stderr, "[cdstate] cdreg reads: idx=%u cmd/param=%u ctrl1=%u ctrl2=%u | writes: idx=%u cmd/param=%u ctrl1=%u ctrl2=%u\n",
                cdreg_r[0], cdreg_r[1], cdreg_r[2], cdreg_r[3],
                cdreg_w[0], cdreg_w[1], cdreg_w[2], cdreg_w[3]);
    }
    g_in_park = 1; g_park_stage = 1; alarm(8); /* R365: park backstop - 8s hard ceiling on the whole park dump */
    fprintf(stderr, "\n[xenolift] HALT: watchdog fired — the code has been running a while.\n");
    fprintf(stderr, "[xenolift] likely polling a hardware register in a loop.\n");
    g_park_stage = 2; /* R365: registers dump_state */
    dump_state();
    g_park_stage = 3; /* R365: post-register park printers */
    {
        /* R144 (Jos 07:41 park decode): the R143 Mac parked in the pump
         * fn_80041B3C (r31=0x80041BB0) with NOTHING ARMED (pending=0,
         * arm1=0) — the pump waits for a slot event whose source the
         * runtime does not emit. Dump everything the pump could be
         * waiting on: slot table, slot-bits, the slot-2 handler cell,
         * the queued request nodes, the read struct, CD model state. */
        int pi;
        g_park_stage = 4; /* R365: park tables */
        /* R399: cd line FIRST — the c156 digestcap head/tail boundary ate
         * the park cd line (fell in the gap) = visibility bug 4th costume.
         * The most-diagnostic line goes at the top where caps can't reach. */
        fprintf(stderr, "[park] cd: pending=%u sched=%u arm1=%u last_cmd=%02X resp_n=%u resp_pos=%u data_n=%u seek_lba=%u\n",
                cd_pending, cd_scheduled, cd_arm_int1_pending, cd_last_cmd, cd_resp_n, cd_resp_pos, cd_data_n, cd_seek_lba);
        fprintf(stderr, "[park] FE20 subtable REAL @0x8001891C (int16 0x892C = -0x76E4): [1]=%08X [2]=%08X [3]=%08X [4]=%08X [5]=%08X [6]=%08X [7]=%08X [8]=%08X [9]=%08X [10]=%08X [11]=%08X [12]=%08X\n",
                LW(0x8001891Cu), LW(0x80018920u), LW(0x80018924u), LW(0x80018928u), LW(0x8001892Cu), LW(0x80018930u), LW(0x80018934u), LW(0x80018938u), LW(0x8001893Cu), LW(0x80018940u), LW(0x80018944u), LW(0x80018948u));
        fprintf(stderr, "[park] slot-bits 0x80056788=%08X (b0) 0x80056789=%02X\n",
                xenolift_mem_read32(0x80056788u),
                xenolift_mem_read32(0x80056789u) & 0xFFu);
        fprintf(stderr, "[park] slot table @0x80056420:");
        for (pi = 0; pi < 12; pi++)
            fprintf(stderr, " [%d]=%u", pi, xenolift_mem_read32(0x80056420u + pi * 4u));
        fprintf(stderr, "[park] arc state jump table @0x800188F4 (R264: the LW offset -0x770C makes 0x80020000+0x88F4 NEGATIVE — real base 0x800188F4):");
        for (pi = 0; pi < 13; pi++)
            fprintf(stderr, " [%d]=%08X", pi, xenolift_mem_read32(0x800188F4u + pi * 4u));
        fprintf(stderr, "\n");
        fprintf(stderr, "\n[park] slot2-handler cell 0x800564A8=%08X\n",
                xenolift_mem_read32(0x800564A8u));
        fprintf(stderr, "[park] queue node 0x80059F10:");
        for (pi = 0; pi < 6; pi++)
            fprintf(stderr, " +%X=%08X", pi * 4, xenolift_mem_read32(0x80059F10u + pi * 4u));
        fprintf(stderr, "\n[park] queue node 0x80059F18:");
        for (pi = 0; pi < 6; pi++)
            fprintf(stderr, " +%X=%08X", pi * 4, xenolift_mem_read32(0x80059F18u + pi * 4u));
        fprintf(stderr, "\n[park] read struct 0x80059EF8:");
        for (pi = 0; pi < 8; pi++)
            fprintf(stderr, " +%X=%08X", pi * 4, xenolift_mem_read32(0x80059EF8u + pi * 4u));
        fprintf(stderr, "[park] gpu: prims=%u words=%llu last_prim=%08X last_tag=%08X\n",
                g_gpu_prims, (unsigned long long)g_gpu_words,
                g_gpu_last_prim, g_gpu_last_tag);
        fprintf(stderr, "[park] cells: FE04=%08X FDF8=%08X FDFC=%08X FE1C=%08X ptr5677C=%08X\n",
                xenolift_mem_read32(0x8004FE04u), xenolift_mem_read32(0x8004FDF8u),
                xenolift_mem_read32(0x8004FDFCu), xenolift_mem_read32(0x8004FE1Cu),
                xenolift_mem_read32(0x8005677Cu));
        fprintf(stderr, "[park] menu input (R381): 694A4=%02X%02X 6948C=%02X%02X cursor(F2D8)=%08X post92D0=%02X cur-state(92C0)=%08X req-state(8088)=%08X\n",
                xenolift_mem[0x694A5u], xenolift_mem[0x694A4u],
                xenolift_mem[0x6948Du], xenolift_mem[0x6948Cu], xenolift_mem[0x692D0u],
                xenolift_mem_read32(0x8005F2D8u),
                xenolift_mem_read32(0x800592C0u), xenolift_mem_read32(0x80018088u));
        fprintf(stderr, "[park] module cells (R265): FE20=%08X FE34=%08X FE38=%08X FE48=%08X | 76F04=%08X 76F08=%08X | 773AC=%08X 773B4=%08X 773D0=%08X 773D4=%08X | render@77180=%08X %08X %08X %08X\n",
                xenolift_mem_read32(0x8004FE20u), xenolift_mem_read32(0x8004FE34u),
                xenolift_mem_read32(0x8004FE38u), xenolift_mem_read32(0x8004FE48u),
                xenolift_mem_read32(0x80076F04u), xenolift_mem_read32(0x80076F08u),
                xenolift_mem_read32(0x800773ACu), xenolift_mem_read32(0x800773B4u),
                xenolift_mem_read32(0x800773D0u), xenolift_mem_read32(0x800773D4u),
                xenolift_mem_read32(0x80077180u), xenolift_mem_read32(0x80077184u),
                xenolift_mem_read32(0x80077188u), xenolift_mem_read32(0x8007718Cu));
        fprintf(stderr, "[park] movie ctl (R266): 77014=%08X 77018=%08X 7701C=%08X 77020=%08X 77028=%08X | 7711C=%08X 77448=%08X 77191=%02X | ring 73B8-C8=%08X %08X %08X %08X %08X %08X\n",
                xenolift_mem_read32(0x80077014u), xenolift_mem_read32(0x80077018u),
                xenolift_mem_read32(0x8007701Cu), xenolift_mem_read32(0x80077020u),
                xenolift_mem_read32(0x80077028u), xenolift_mem_read32(0x8007711Cu),
                xenolift_mem_read32(0x80077448u), xenolift_mem_read32(0x80077191u) & 0xFFu,
                xenolift_mem_read32(0x800773B8u), xenolift_mem_read32(0x800773BCu),
                xenolift_mem_read32(0x800773C0u), xenolift_mem_read32(0x800773C4u),
                xenolift_mem_read32(0x800773C8u), xenolift_mem_read32(0x800773CCu));
        fprintf(stderr, "[park] fsm ring (R275): s1c=%08X s1e=%08X s6s8r=%08X s6s8inc=%08X s7=%08X s11=%08X n8=%08X n8b=%08X | reqF08=%08X reqF10=%08X reqF14=%08X reqF15=%08X FE28=%08X FE2C=%08X | guest-cnt A488/A494/A498/A4A8/A4B4=%08X %08X %08X %08X %08X ready8/10=%08X %08X\n", LW(0x8005A48Cu), LW(0x8005A490u), LW(0x8005A488u), LW(0x8005A494u), LW(0x8005A4A8u), LW(0x8005A4B4u), LW(0x8005A498u), LW(0x8005A49Cu), LW(0x80059F08u), LW(0x80059F10u), LW(0x80059F14u), LW(0x80059F15u), LW(0x8004FE28u), LW(0x8004FE2Cu), xenolift_mem_read32(0x8006A488u), xenolift_mem_read32(0x8006A494u),
                    xenolift_mem_read32(0x8006A498u), xenolift_mem_read32(0x8006A4A8u), xenolift_mem_read32(0x8006A4B4u),
                    xenolift_mem_read32(0x80069F08u), xenolift_mem_read32(0x80069F10u));
        fprintf(stderr, "[park] stream cells (R273): FE30=%08X FE34=%08X FE38=%08X FE3C=%08X FE40=%08X FE44=%08X FE48=%08X FE4C=%08X FE50=%08X | idx-head@801E1400=%08X %08X %08X %08X | 77398=%04X 7739C=%04X\n", LW(0x8004FE30u), LW(0x8004FE34u), LW(0x8004FE38u), LW(0x8004FE3Cu), LW(0x8004FE40u), LW(0x8004FE44u), LW(0x8004FE48u), LW(0x8004FE4Cu), LW(0x8004FE50u), LW(0x801E1400u), LW(0x801E1404u), LW(0x801E1408u), LW(0x801E140Cu), LHU(0x80077398u), LHU(0x8007739Cu));
        fprintf(stderr, "[park] height gate (R272): cell773A0=%08X dispY77024=%08X buf801E6000=%08X %08X %08X %08X | w773A4=%08X h773A8=%08X chk77438=%08X\n", LW(0x800773A0u), LW(0x80077024u), LW(0x801E6000u), LW(0x801E6004u), LW(0x801E6008u), LW(0x801E600Cu), LW(0x800773A4u), LW(0x800773A8u), LW(0x80077438u));
        fprintf(stderr, "[park] player state (R301: 0x800704E0 = pad+prologue of ReadStressTestScreen@0x800704E8, NOT cfg): 704E0=%08X %08X %08X %08X | 704F0=%08X %08X | gate77194=%02X | 77010=%02X 77012=%02X 7702C=%08X 77030=%08X\n",
                xenolift_mem_read32(0x800704E0u), xenolift_mem_read32(0x800704E4u),
                xenolift_mem_read32(0x800704E8u), xenolift_mem_read32(0x800704ECu),
                xenolift_mem_read32(0x800704F0u), xenolift_mem_read32(0x800704F4u),
                xenolift_mem_read32(0x80077194u) & 0xFFu,
                xenolift_mem_read32(0x80077010u) & 0xFFu, xenolift_mem_read32(0x80077012u) & 0xFFu,
                xenolift_mem_read32(0x8007702Cu), xenolift_mem_read32(0x80077030u));
    }
    { /* R354: batch request list MOVED here (R353 planted it in a cold park context by mistake — LESSON L13: instrument the park path the digest =TAIL= actually shows). FE0C = list ptr, FE10 = index, entries = u16 size @+0, ptr @+4. */
        uint32_t fe0c = xenolift_mem_read32(0x8004FE0Cu);
        uint32_t fe10 = xenolift_mem_read32(0x8004FE10u);
        fprintf(stderr, "[park] field dest (R361): 801D4B34=%08X %08X %08X %08X (file-14 landing zone head)\n",
                    xenolift_mem_read32(0x801D4B34u), xenolift_mem_read32(0x801D4B38u), xenolift_mem_read32(0x801D4B3Cu), xenolift_mem_read32(0x801D4B40u));
                    fprintf(stderr, "[park] batch list (R354): FE0C=%08X FE10=%08X FE08=%08X FDE8=%08X FDE4=%08X FE3C=%08X FE34=%08X\n",
                fe0c, fe10, xenolift_mem_read32(0x8004FE08u), xenolift_mem_read32(0x8004FDE8u),
                xenolift_mem_read32(0x8004FDE4u), xenolift_mem_read32(0x8004FE3Cu),
                xenolift_mem_read32(0x8004FE34u));
        if (fe0c >= 0x80010000u && fe0c < 0x80200000u) {
            for (uint32_t i = 0u; i < 9u; i++) {
                uint32_t e = fe0c + i * 8u;
                fprintf(stderr, "[park] batch[%u] size=%u ptr=%08X%s\n", i,
                        xenolift_mem_read32(e) & 0xFFFFu, xenolift_mem_read32(e + 4u),
                        (i == fe10) ? " <== INDEX" : "");
            }
        }
    }
    {
        /* R92: free-list walk of 0x80059410 — the fd module's block heap.
         * fn_80038F18 spins here when the chain cycles; name the poison. */
        uint32_t a, first; int it = 0;
        memcpy(&a, xenolift_mem + 0x59410, 4);
        first = a;
        g_park_stage = 5; /* R365: gpu capture + free-list walk */
        gpu_dump_capture(); /* R125 */
    fprintf(stderr, "[fl] free-list head 0x80059410 -> 0x%08X\n", a);
        { uint32_t evc, lim;
          memcpy(&evc, xenolift_mem + 0x595BC, 4);
          memcpy(&lim, xenolift_mem + 0x595E4, 4);
          fprintf(stderr, "[fl] limit cells: 0x800695BC=%08X 0x800695E4=%08X\n", evc, lim); }
        while (it++ < 24) {
            uint32_t w0, d8, n12;
            if (!(a >= 0x80000000u && a < 0x80200000u)) {
                fprintf(stderr, "[fl]  #%d INVALID addr 0x%08X\n", it, a); break;
            }
            memcpy(&w0, xenolift_mem + (a - 0x80000000u), 4);
            memcpy(&d8, xenolift_mem + (a - 0x80000000u) + 8, 4);
            memcpy(&n12, xenolift_mem + (a - 0x80000000u) + 12, 4);
            fprintf(stderr, "[fl]  #%d entry=0x%08X w0=%08X data=%08X next=%08X (size %d)\n",
                    it, a, w0, d8, n12, (int32_t)(n12 - d8));
            if (n12 == 0u) { fprintf(stderr, "[fl]  terminator\n"); break; }
            if (n12 == first || n12 == a) {
                fprintf(stderr, "[fl]  *** CYCLE: 0x%08X -> 0x%08X ***\n", a, n12); break;
            }
            a = n12;
        }
        if (it > 24) fprintf(stderr, "[fl]  WALK LIMIT hit\n");
    }
    {
        /* C call-stack backtrace: names the exact kernel function chain
         * that is spinning (xenolift_fn_XXXXXXXX symbols). */
        g_park_stage = 6; /* R365: native backtrace */
        void *bt[32];
        int n = backtrace(bt, 32);
        char **syms = backtrace_symbols(bt, n);
        fprintf(stderr, "[xenolift] call stack at watchdog:\n");
        for (int i = 0; i < n; i++) fprintf(stderr, "  %s\n", syms ? syms[i] : "?");
        free(syms);
    }
    g_exit_why = "watchdog-alarm";
    exit(0);
}

/* ---- CD-ROM disc image: a real ISO9660 file system ----
 * The kernel just called FileOpen — it wants files from the disc.
 * ISO9660 keeps a Primary Volume Descriptor at fixed sector 16, with
 * the root directory record chained from it; every file is then just
 * an LBA (sector number) plus a byte length. Raw .bin rips wrap each
 * 2048-byte data sector in a 2352-byte frame (sync + header before
 * the data), plain .iso images store bare 2048-byte sectors.
 * Paths on PS1 use backslashes: "XENOGEARS\FONT\TITLE.FNT" */

#include <stdlib.h>
static int g_mod6_live = 0; /* R253: set at MovieModuleEntry 0x800737EC */
static int g_movie_live = 0; /* R254: set when the movie PLAYER chain actually starts */

/* R262: g_disc hoisted above */
/* R262: g_sec_bytes declared above; initialised at disc open */
static uint32_t g_sec_off = 0u;       /* user data offset in frame */

typedef struct {
    uint32_t lba;   /* first sector of the file */
    uint32_t size;  /* file length in bytes */
    uint32_t pos;   /* current read position */
    int in_use;
} DiscFile;

static DiscFile g_files[16];

static int disc_read_lba(uint32_t lba, void *dst)
{
    if (g_disc == NULL) {
        return -1;
    }
    if (fseek(g_disc, (long)lba * (long)g_sec_bytes + (long)g_sec_off, SEEK_SET) != 0) {
        return -1;
    }
    return fread(dst, 1, 2048, g_disc) == 2048 ? 0 : -1;
}

/* compare an ISO name (uppercase, may end in ";1") to a path component */
static int iso_name_eq(const char *iso, uint32_t iso_len, const char *want)
{
    if (iso_len >= 2 && iso[iso_len - 2] == ';') {
        iso_len -= 2; /* strip version suffix, e.g. "TITLE.FNT;1" */
    }
    uint32_t n = 0;
    while (want[n] != 0) {
        n++;
    }
    if (n != iso_len) {
        return 0;
    }
    for (uint32_t i = 0; i < iso_len; i++) {
        char a = iso[i];
        char b = want[i];
        if (a >= 'a' && a <= 'z') {
            a = (char)(a - 'a' + 'A');
        }
        if (b >= 'a' && b <= 'z') {
            b = (char)(b - 'a' + 'A');
        }
        if (a != b) {
            return 0;
        }
    }
    return 1;
}

/* find a file/dir record inside one directory buffer; returns record
 * extent LBA and size, or -1. dir==NULL means the root directory. */
static int iso_lookup(const uint8_t *dir, uint32_t dir_size,
                      const char *name, int want_dir,
                      uint32_t *out_lba, uint32_t *out_size)
{
    uint32_t p = 0;
    while (p + 33 <= dir_size) {
        uint32_t rec_len = dir[p];
        if (rec_len == 0) {
            p = (p + 2048) & ~(uint32_t)2047; /* skip to next sector */
            continue;
        }
        if (p + rec_len > dir_size) {
            break;
        }
        uint32_t name_len = dir[p + 32];
        uint32_t flags = dir[p + 25];
        if (name_len > 0 && iso_name_eq((const char *)&dir[p + 33], name_len, name)) {
            int is_dir = (flags & 0x02u) != 0;
            if (is_dir == want_dir || (want_dir == 0 && is_dir)) {
                /* a path component that names a directory works too */
                *out_lba = (uint32_t)dir[p + 2] |
                           ((uint32_t)dir[p + 3] << 8) |
                           ((uint32_t)dir[p + 4] << 16) |
                           ((uint32_t)dir[p + 5] << 24);
                *out_size = (uint32_t)dir[p + 10] |
                            ((uint32_t)dir[p + 11] << 8) |
                            ((uint32_t)dir[p + 12] << 16) |
                            ((uint32_t)dir[p + 13] << 24);
                return 0;
            }
        }
        p += rec_len;
    }
    return -1;
}

/* resolve a kernel path like "XENOGEARS\TITLE.FNT" against the disc */
static int iso_resolve(const char *path, uint32_t *out_lba, uint32_t *out_size)
{
    if (g_disc == NULL) {
        return -1;
    }
    uint8_t pvd[2048];
    if (disc_read_lba(16, pvd) != 0 || memcmp(pvd + 1, "CD001", 5) != 0) {
        fprintf(stderr, "[disc] no ISO9660 volume found\n");
        return -1;
    }
    /* root directory record lives at PVD offset 156 */
    uint32_t lba = (uint32_t)pvd[156 + 2] |
                   ((uint32_t)pvd[156 + 3] << 8) |
                   ((uint32_t)pvd[156 + 4] << 16) |
                   ((uint32_t)pvd[156 + 5] << 24);
    uint32_t size = (uint32_t)pvd[156 + 10] |
                    ((uint32_t)pvd[156 + 11] << 8) |
                    ((uint32_t)pvd[156 + 12] << 16) |
                    ((uint32_t)pvd[156 + 13] << 24);

    char comp[128];
    const char *q = path;
    for (;;) {
        /* pull one path component, accepting \ or / separators */
        uint32_t n = 0;
        while (*q != 0 && *q != '\\' && *q != '/' && n + 1 < sizeof comp) {
            comp[n++] = *q++;
        }
        comp[n] = 0;
        int last = (*q == 0);
        if (*q == '\\' || *q == '/') {
            q++;
        }
        if (n == 0) {
            if (last) {
                break;
            }
            continue;
        }

        uint32_t next_lba, next_size;
        /* lba/size currently name the directory we are inside;
         * load it and look for the component within it */
        uint8_t *dirbuf = malloc(size ? size : 2048);
        if (dirbuf == NULL) {
            return -1;
        }
        int ok = 0;
        for (uint32_t done = 0; done < size; done += 2048) {
            if (disc_read_lba(lba + done / 2048, dirbuf + done) != 0) {
                break;
            }
            ok = 1;
        }
        if (!ok) {
            free(dirbuf);
            return -1;
        }
        int found = iso_lookup(dirbuf, size, comp, 0, &next_lba, &next_size);
        free(dirbuf);
        if (found != 0) {
            return -1;
        }
        lba = next_lba;
        size = next_size;
        if (last) {
            break;
        }
    }
    *out_lba = lba;
    *out_size = size;
    return 0;
}

int xenolift_disc_mount(const char *path)
{
    g_disc = fopen(path, "rb");
    if (g_disc == NULL) {
        return -1;
    }
    uint8_t hdr[16];
    if (fread(hdr, 1, 16, g_disc) != 16) {
        fclose(g_disc);
        g_disc = NULL;
        return -1;
    }
    static const uint8_t sync[12] =
        { 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00 };
    if (memcmp(hdr, sync, 12) == 0) {
        g_sec_bytes = 2352u;
        g_sec_off = (hdr[15] == 2) ? 0x18u : 0x10u; /* mode2 form1 : mode1 */
    } else {
        g_sec_bytes = 2048u;
        g_sec_off = 0u;
    }
    uint8_t pvd[2048];
    if (disc_read_lba(16, pvd) != 0 || memcmp(pvd + 1, "CD001", 5) != 0) {
        fprintf(stderr, "[disc] %s: no ISO9660 volume (wrong file?)\n", path);
        fclose(g_disc);
        g_disc = NULL;
        return -1;
    }
    for (int i = 0; i < 16; i++) {
        g_files[i].in_use = 0;
    }
    fprintf(stderr, "[disc] mounted %s (%u-byte sectors)\n", path, g_sec_bytes);
    return 0;
}

/* read from an open file into PS1 RAM; returns bytes read */
static int disc_file_read(int fd, uint32_t dst, uint32_t len)
{
    if (fd < 0 || fd >= 16 || !g_files[fd].in_use) {
        return -1;
    }
    DiscFile *f = &g_files[fd];
    uint32_t remain = f->size > f->pos ? f->size - f->pos : 0;
    if (len > remain) {
        len = remain;
    }
    uint32_t done = 0;
    uint8_t sec[2048];
    while (done < len) {
        uint32_t chunk = len - done;
        uint32_t in_off = (f->pos + done) & 2047u;
        uint32_t avail = 2048 - in_off;
        if (chunk > avail) {
            chunk = avail;
        }
        if (disc_read_lba(f->lba + (f->pos + done) / 2048, sec) != 0) {
            break;
        }
        for (uint32_t i = 0; i < chunk; i++) {
            xenolift_mem_write8(dst + done + i, sec[in_off + i]);
        }
        done += chunk;
    }
    return (int)done;
}

/* ---- BIOS HLE: the A0/B0/C0 call gates ----
 * PS1 programs call built-in services by loading the function number into
 * r9 and jumping to one of three magic addresses (0xA0/0xB0/0xC0); the
 * kernel also reaches the same services via the `syscall` instruction.
 * Names below are from the nocash PSXSPX kernel specification.
 * Convention: args in a0-a2 (r4-r6), return value in v0 (r2). */

    static const char *A_names[] = {
    "FileOpen", "FileSeek", "FileRead",
    "FileWrite", "FileClose", "FileIoctl",
    "exit", "FileGetDeviceFlag", "FileGetc",
    "FilePutc", "todigit", "atof",
    "strtoul", "strtol", "abs",
    "labs", "atoi", "atol",
    "atob", "SaveState", "RestoreState",
    "strcat", "strncat", "strcmp",
    "strncmp", "strcpy", "strncpy",
    "strlen", "index", "rindex",
    "strchr", "strrchr", "strpbrk",
    "strspn", "strcspn", "strtok",
    "strstr", "toupper", "tolower",
    "bcopy", "bzero", "bcmp",
    "memcpy", "memset", "memmove",
    "memcmp", "memchr", "rand",
    "srand", "qsort", "strtod",
    "malloc", "free", "lsearch",
    "bsearch", "calloc", "realloc",
    "InitHeap", "SystemErrorExit", "std_in_getchar",
    "std_out_putchar", "std_in_gets", "std_out_puts",
    "printf", "SystemErrorUnresolvedException", "LoadExeHeader",
    "LoadExeFile", "DoExecute", "FlushCache",
    "init_a0_b0_c0_vectors", "GPU_dw", "gpu_send_dma",
    "SendGP1Command", "GPU_cw", "GPU_cwp",
    "send_gpu_linked_list", "gpu_abort_dma", "GetGPUStatus",
    "gpu_sync", "SystemError", "SystemError",
    "LoadAndExecute", "GetSysSp", "SystemError",
    "CdInit", "_bu_init", "CdRemove",
    "return0", "return0", "return0",
    "return0", "dev_tty_init", "dev_tty_open",
    "dev_tty_in_out", "dev_tty_ioctl", "dev_cd_open",
    "dev_cd_read", "dev_cd_close", "dev_cd_firstfile",
    "dev_cd_nextfile", "dev_cd_chdir", "dev_card_open",
    "dev_card_read", "dev_card_write", "dev_card_close",
    "dev_card_firstfile", "dev_card_nextfile", "dev_card_erase",
    "dev_card_undelete", "dev_card_format", "dev_card_rename",
    "dev_card_clear_error", "_bu_init", "CdInit",
    "CdRemove", "return0", "return0",
    "return0", "return0", "return0",
    "CdAsyncSeekL", "return0", "return0",
    "return0", "CdAsyncGetStatus", "return0",
    "CdAsyncReadSector", "return0", "return0",
    "CdAsyncSetMode",
    };
    static const char *B_names[] = {
    "alloc_kernel_memory", "free_kernel_memory", "init_timer",
    "get_timer", "enable_timer_irq", "disable_timer_irq",
    "restart_timer", "DeliverEvent", "OpenEvent",
    "CloseEvent", "WaitEvent", "TestEvent",
    "EnableEvent", "DisableEvent", "OpenThread",
    "CloseThread", "ChangeThread", "jump_to_00000000h",
    "InitPad", "StartPad", "StopPad",
    "OutdatedPadInitAndStart", "OutdatedPadGetButtons", "ReturnFromException",
    "SetDefaultExitFromException", "SetCustomExitFromException", "SystemError",
    "SystemError", "SystemError", "SystemError",
    "SystemError", "SystemError", "UnDeliverEvent",
    "SystemError", "SystemError", "SystemError",
    "jump_to_00000000h", "jump_to_00000000h", "jump_to_00000000h",
    "jump_to_00000000h", "jump_to_00000000h", "jump_to_00000000h",
    "SystemError", "SystemError", "jump_to_00000000h",
    "jump_to_00000000h", "jump_to_00000000h", "jump_to_00000000h",
    "jump_to_00000000h", "jump_to_00000000h", "FileOpen",
    "FileSeek", "FileRead", "FileWrite",
    "FileClose", "FileIoctl", "exit",
    "FileGetDeviceFlag", "FileGetc", "FilePutc",
    "std_in_getchar", "std_out_putchar", "std_in_gets",
    "std_out_puts", "chdir", "FormatDevice",
    "firstfile", "nextfile", "FileRename",
    "FileDelete", "FileUndelete", "AddDevice",
    "RemoveDevice", "PrintInstalledDevices", "InitCard",
    "StartCard", "StopCard", "_card_info_subfunc",
    "write_card_sector", "read_card_sector", "allow_new_card",
    "Krom2RawAdd", "SystemError", "Krom2Offset",
    "GetLastError", "GetLastFileError", "GetC0Table",
    "GetB0Table", "get_bu_callback_port", "testdevice",
    "SystemError", "ChangeClearPad", "get_card_status",
    "wait_card_status",
    };
    static const char *C_names[] = {
    "EnqueueTimerAndVblankIrqs", "EnqueueSyscallHandler", "SysEnqIntRP",
    "SysDeqIntRP", "get_free_EvCB_slot", "get_free_TCB_slot",
    "ExceptionHandler", "InstallExceptionHandlers", "SysInitMemory",
    "SysInitKernelVariables", "ChangeClearRCnt", "SystemError",
    "InitDefInt", "SetIrqAutoAck", "return0",
    "return0", "return0", "return0",
    "tty_cdevinput", "tty_cdevscan", "tty_circgetc",
    "tty_circputc", "ioabort", "set_card_find_mode",
    "KernelRedirect", "AdjustA0Table", "get_card_find_mode",
    };
    static const char *SYS_names[] = {
    "NoFunction", "EnterCriticalSection", "ExitCriticalSection",
    "ChangeThreadSubFunction", "DeliverEvent",
    };

/* ---- synthetic BIOS module ----
 * Xenogears (like Metal Gear Solid and Legacy of Kain) calls
 * B0(0x57) GetB0Table, then reads entry 0x5B of the returned table
 * (the ChangeClearPad handler pointer, at offset 0x16C) and uses fixed
 * offsets from it (+0x884, +0x894) as entry points into the REAL
 * BIOS's internal pad driver. We have no real BIOS ROM, so we hand it
 * a synthetic table in scratch RAM whose entry 0x5B points at our own
 * module; the kernel computes hook addresses X+0x884/X+0x894 and later
 * jumps to them. xenolift_unknown recognizes those and services them. */
#define XENOLIFT_BIOS_T 0x80102000u /* synthetic A0/B0/C0 "table" base */
#define XENOLIFT_BIOS_X 0x80100000u /* synthetic BIOS module base      */
#define XENOLIFT_HOOK_A (XENOLIFT_BIOS_X + 0x884u)
#define XENOLIFT_HOOK_B (XENOLIFT_BIOS_X + 0x894u)

static void bios_module_setup(void)
{
    /* "B0 table" entry 0x5B (= offset 0x16C) points at our module */
    xenolift_mem_write32(XENOLIFT_BIOS_T + 0x16Cu, XENOLIFT_BIOS_X);
    /* R82 FIX — THE 0x8F5A0014 FAULT, SOLVED: fn_8004B4AC (kernel init)
     * does v0=*(C0_table+24), then copies 15 words of the kernel's
     * EXCEPTION HANDLER template (file 0x8004B514-0x8004B54C: lw k0,8(sp);
     * sw ra,4(k0); mtc0 v0,Cause; ...) to [v0..v0+60]. On real HW the C0
     * table's +24 = the exception vector base 0x80000080. Ours was 0, so
     * the handler got installed over the kernel low-variable table at
     * 0x80000000 — and cell 0x8000000C = `lw k0, 8(sp)` (0x8F5A0008) was
     * later read as a pointer -> io-fault at 0x8F5A0014. Point it home. */
    xenolift_mem_write32(XENOLIFT_BIOS_T + 0x18u, 0x80000080u);
    fprintf(stderr, "[bios] synthetic module at 0x%08X, hooks 0x%08X / 0x%08X\n",
            XENOLIFT_BIOS_X, XENOLIFT_HOOK_A, XENOLIFT_HOOK_B);
}

/* returns 1 if the target is inside the synthetic BIOS module
 * (and was serviced). The kernel installs hooks at module offsets
 * (+0x884, +0x894, +0x7A0, ... more will come — card driver, SIO, etc.)
 * by storing them from GetB0Table-derived pointers, then calls them.
 * Any jump into the module range is a hook call: service it generically. */
static uint32_t g_hook_calls;
static int bios_hook(uint32_t target)
{
    if (target < XENOLIFT_BIOS_X || target >= XENOLIFT_BIOS_X + 0x1000u) {
        return 0;
    }
    static uint8_t seen[0x1000 / 4];
    uint32_t off = (target - XENOLIFT_BIOS_X) / 4;
    if (off / 4 < sizeof(seen) && !seen[off / 4]) {
        seen[off / 4] = 1;
        fprintf(stderr, "[bios] synthetic hook +0x%03X (0x%08X) called — serviced\n",
                target - XENOLIFT_BIOS_X, target);
    }
    g_hook_calls++;
    if (g_hook_calls % 500 == 0) {
        fprintf(stderr, "[bios] synthetic hooks: %u calls so far\n", g_hook_calls);
    }
    r[2] = 0;
    return 1;
}

static const char *bios_name(uint32_t gate, uint32_t fn)
{
    const char *const *tab = NULL;
    uint32_t n = 0;
    fn &= 0xFFu;
    switch (gate) {
    case 0xA0: tab = A_names; n = sizeof(A_names) / sizeof(A_names[0]); break;
    case 0xB0: tab = B_names; n = sizeof(B_names) / sizeof(B_names[0]); break;
    case 0xC0: tab = C_names; n = sizeof(C_names) / sizeof(C_names[0]); break;
    }
    if (tab != NULL && fn < n) {
        return tab[fn];
    }
    return "?";
}

static void bios_log(uint32_t gate, uint32_t fn, const char *what)
{
    static uint8_t seen[3][256];
    uint32_t g = (gate - 0xA0u) / 0x10u; /* 0xA0->0, 0xB0->1, 0xC0->2 */
    fn &= 0xFFu;
    if (seen[g][fn]) {
        return;
    }
    seen[g][fn] = 1;
    fprintf(stderr, "[bios] %c0(0x%02X) %-28s %s\n",
            (char)('A' + g), fn, bios_name(gate, fn), what);
}

/* safe C-string read from RAM (for printf-style logging) */
static void bios_read_str(uint32_t a, char *buf, uint32_t n)
{
    uint32_t i;
    for (i = 0; i < n - 1; i++) {
        uint32_t p = (a + i) & 0x1FFFFFFFu;
        if (p >= XENOLIFT_RAM_SIZE) {
            break; /* not RAM — stop rather than fault */
        }
        uint8_t c = xenolift_mem[p];
        if (c == 0) {
            break;
        }
        buf[i] = (char)c;
    }
    buf[i] = 0;
}


/* diagnostic: dump words at a RAM pointer, and follow it one level
 * (kernel structures often store name pointers inside) */
int zsr_pending = 0; /* R293 zero-size-read sync-complete arming */
static uint32_t fin_r20_saved = 0; /* R304: finale cleanup handle (captured at fn_80073B28 entry) */
static void bios_inspect(const char *label, uint32_t a)
{
    uint32_t p = a & 0x1FFFFFFFu;
    if (p + 32 > XENOLIFT_RAM_SIZE) {
        return; /* not RAM */
    }
    fprintf(stderr, "[bios]     %s 0x%08X:", label, a);
    for (int i = 0; i < 8; i++) {
        uint32_t w;
        memcpy(&w, xenolift_mem + p + i * 4, 4);
        fprintf(stderr, " %08X", w);
    }
    fprintf(stderr, "\n");
    uint32_t pv;
    memcpy(&pv, xenolift_mem + p, 4);
    if ((pv & 0x1FFFFFFFu) + 1 < XENOLIFT_RAM_SIZE && pv != 0) {
        char b2[128];
        bios_read_str(pv, b2, sizeof b2);
        if (b2[0] != 0) {
            fprintf(stderr, "[bios]     *%s -> 0x%08X \"%s\"\n", label, pv, b2);
        }
    }
}

/* R145 (BIOS_THUNK_AUDIT.md top-5 implementation): gate-side state
 * for the pad, exception-exit, and root-counter-clear thunks. */
static uint8_t g_pad_active;          /* StartPAD() called */
static uint32_t g_pad_buf1, g_pad_buf2; /* InitPAD(buf1,len1,buf2,len2) */
static uint32_t g_custom_exception_exit; /* SetCustomExitFromException */
static uint8_t g_rc_clear[3];         /* ChangeClearRCnt flags RC0-2 */
void xenolift_bios_gate(uint32_t gate, uint32_t fn)
{
    switch (gate) {
    case 0xA0:
        switch (fn) {
        case 0x44: /* FlushCache: no host cache to flush in static code */
            bios_log(gate, fn, "(nop)");
            r[2] = 0;
            return;
        case 0x48: /* SendGP1Command(gp1cmd) */
            bios_log(gate, fn, "-> GPU GP1");
            xenolift_mem_write32(0x1F801814u, r[4]);
            r[2] = 0;
            return;
        case 0x49: /* GPU_cw(gp0cmd) — send one GP0 command word */
            bios_log(gate, fn, "-> GPU GP0");
            xenolift_mem_write32(0x1F801810u, r[4]);
            r[2] = 0;
            return;
        case 0x4D: /* GetGPUStatus */
            bios_log(gate, fn, "-> 0x10000000");
            r[2] = 0x10000000u;
            return;
        case 0x4E: /* gpu_sync */
            bios_log(gate, fn, "(nop)");
            r[2] = 0;
            return;
        case 0x19: { /* strcpy(dst, src) */
            bios_log(gate, fn, "(real)");
            uint32_t d = r[4], sc = r[5], i = 0;
            uint8_t c;
            do {
                c = xenolift_mem_read8(sc + i);
                xenolift_mem_write8(d + i, c);
                i++;
            } while (c != 0);
            r[2] = d;
            return;
        }
        case 0x1B: { /* strlen(s) */
            bios_log(gate, fn, "(real)");
            uint32_t i = 0;
            while (xenolift_mem_read8(r[4] + i) != 0) {
                i++;
            }
            r[2] = i;
            return;
        }
        case 0x28: { /* bcopy(src, dst, len) */
            bios_log(gate, fn, "(real)");
            uint32_t i;
            for (i = 0; i < r[6]; i++) {
                xenolift_mem_write8(r[5] + i, xenolift_mem_read8(r[4] + i));
            }
            r[2] = 0;
            return;
        }
        case 0x2A: { /* memcpy(dst, src, len) */
            bios_log(gate, fn, "(real)");
            uint32_t i;
            for (i = 0; i < r[6]; i++) {
                xenolift_mem_write8(r[4] + i, xenolift_mem_read8(r[5] + i));
            }
            r[2] = r[4];
            return;
        }
        case 0x2B: { /* memset(dst, fill, len) */
            bios_log(gate, fn, "(real)");
            uint32_t i;
            for (i = 0; i < r[6]; i++) {
                xenolift_mem_write8(r[4] + i, r[5] & 0xFFu);
            }
            r[2] = r[4];
            return;
        }
        case 0x00: { /* FileOpen(filename, access) -> fd or -1 */
            char buf[128];
            uint32_t lba, size;
            bios_read_str(r[4], buf, sizeof buf);
            if (buf[0] == 0) {
                /* this kernel may pass the name in a1 instead: try it */
                char b5[128];
                bios_read_str(r[5], b5, sizeof b5);
                if (b5[0] != 0) {
                    fprintf(stderr, "[bios]     (filename seen in a1, not a0)\n");
                    memcpy(buf, b5, sizeof buf);
                }
            }
            fprintf(stderr, "[bios]     args: a0=0x%08X a1=0x%08X a2=0x%08X\n",
                    r[4], r[5], r[6]);
            if (g_disc != NULL && iso_resolve(buf, &lba, &size) == 0) {
                bios_log(gate, fn, "(REAL — from disc)");
                fprintf(stderr, "[bios]     file \"%s\" at LBA %u, %u bytes\n",
                        buf, lba, size);
                int fd = -1;
                for (int i = 0; i < 16; i++) {
                    if (!g_files[i].in_use) {
                        fd = i;
                        break;
                    }
                }
                if (fd < 0) {
                    r[2] = (uint32_t)-1;
                } else {
                    g_files[fd].lba = lba;
                    g_files[fd].size = size;
                    g_files[fd].pos = 0;
                    g_files[fd].in_use = 1;
                    r[2] = (uint32_t)fd;
                }
            } else {
                bios_log(gate, fn, "(file not found, v0=-1)");
                fprintf(stderr, "[bios]     wants file: \"%s\" (access %u)\n", buf, r[5]);
                bios_inspect("a1", r[5]);
                bios_inspect("a2", r[6]);
                r[2] = (uint32_t)-1;
            }
            return;
        }
        case 0x01: { /* FileSeek(fd=r4, offset=r5, seektype=r6) */
            bios_log(gate, fn, "(REAL)");
            int fd = (int)r[4];
            if (fd >= 0 && fd < 16 && g_files[fd].in_use) {
                uint32_t base = (r[6] == 0u) ? 0u :
                                (r[6] == 1u) ? g_files[fd].pos : g_files[fd].size;
                g_files[fd].pos = base + r[5];
            }
            r[2] = 0;
            return;
        }
        case 0x02: { /* FileRead(fd=r4, dst=r5, len=r6) -> bytes read */
            bios_log(gate, fn, "(REAL)");
            r[2] = (uint32_t)disc_file_read((int)r[4], r[5], r[6]);
            return;
        }
        case 0x04: { /* FileClose(fd=r4) */
            bios_log(gate, fn, "(REAL)");
            int fd = (int)r[4];
            if (fd >= 0 && fd < 16) {
                g_files[fd].in_use = 0;
            }
            r[2] = 1;
            return;
        }
        case 0x3C: /* std_out_putchar(char) */
            bios_log(gate, fn, "(-> console)");
            fputc((int)(r[4] & 0xFFu), stderr);
            r[2] = r[4];
            return;
        case 0x3F: { /* printf(fmt, ...) — show the format string */
            char buf[128];
            bios_read_str(r[4], buf, sizeof buf);
            bios_log(gate, fn, "(printf)");
            fprintf(stderr, "[game] \"%s\"\n", buf);
            r[2] = 0;
            return;
        }
        }
        break;
    case 0xB0:
        switch (fn) {
        case 0x5B: /* R83: called by the driver-object init chain
             * (fn_80040828/fn_800408C4 both do B0(0x5B)(0)). Logged so
             * the digest shows the kernel's args; returns 0. */
            bios_log(gate, fn, "(logged)");
            fprintf(stderr, "[gate5B] a0=%u a1=%u a2=%u\n", r[4], r[5], r[6]);
            r[2] = 0;
            return;
        case 0x56: /* GetC0Table */
        case 0x57: /* GetB0Table */
            bios_log(gate, fn, "(REAL — synthetic table)");
            r[2] = XENOLIFT_BIOS_T;
            return;
        case 0x08: /* OpenEvent(class, spec, mode, handler) */
            bios_log(gate, fn, "(REAL — event table)");
            r[2] = evt_open(r[4], r[5], r[6], r[7]);
            fprintf(stderr, "[evt] OpenEvent class=0x%08X spec=0x%08X mode=0x%08X handler=0x%08X -> ev=%u\n",
                    r[4], r[5], r[6], r[7], r[2]);
            return;
        case 0x09: /* CloseEvent(ev) */
            bios_log(gate, fn, "(REAL — event table)");
            if (r[4] >= 1u && r[4] <= MAX_EVENTS && evt_tab[r[4]-1].in_use)
                evt_tab[r[4]-1].in_use = 0;
            r[2] = 1;
            return;
        case 0x0A: /* WaitEvent(ev) — real HW blocks the thread until the
         * event is delivered. Static recomp can't block: the load's
         * chunk loop paces on this. We fire CD events from the
         * heartbeat, and reads are synchronous, so report delivered
         * and consume the flag. */
            bios_log(gate, fn, "(REAL — event table)");
            if (r[4] >= 1u && r[4] <= MAX_EVENTS && evt_tab[r[4]-1].in_use) {
                fprintf(stderr, "[evt] WaitEvent ev=%u class=0x%08X fired=%u\n",
                        r[4], evt_tab[r[4]-1].cls, evt_tab[r[4]-1].fired);
                evt_tab[r[4]-1].fired = 0;
            }
            r[2] = 1; /* delivered */
            return;
        case 0x0B: /* TestEvent(ev) — non-blocking probe */
            r[2] = 0;
            if (r[4] >= 1u && r[4] <= MAX_EVENTS && evt_tab[r[4]-1].in_use)
                r[2] = evt_tab[r[4]-1].fired;
            return;
        case 0x0C: /* EnableEvent(ev) */
            bios_log(gate, fn, "(REAL — event table)");
            r[2] = r[4];
            if (r[4] >= 1u && r[4] <= MAX_EVENTS && evt_tab[r[4]-1].in_use) {
                evt_tab[r[4]-1].enabled = 1;
                fprintf(stderr, "[evt] EnableEvent ev=%u class=0x%08X handler=0x%08X\n",
                        r[4], evt_tab[r[4]-1].cls, evt_tab[r[4]-1].handler);
            } else {
                fprintf(stderr, "[evt] EnableEvent BAD ev=%u\n", r[4]);
            }
            return;
        case 0x0D: /* DisableEvent(ev) */
            bios_log(gate, fn, "(REAL — event table)");
            if (r[4] >= 1u && r[4] <= MAX_EVENTS && evt_tab[r[4]-1].in_use)
                evt_tab[r[4]-1].enabled = 0;
            r[2] = r[4];
            return;
        case 0x07: /* DeliverEvent(class, spec) */
            bios_log(gate, fn, "(REAL — event table)");
            fprintf(stderr, "[evt] DeliverEvent class=0x%08X spec=0x%08X\n", r[4], r[5]);
            evt_deliver_class(r[4], r[5]);
            r[2] = 0;
            return;
        case 0x12: /* InitPAD(buf1, len1, buf2, len2) — R145
             * (BIOS_THUNK_AUDIT.md #5): the kernel registers its dual
             * controller buffers (Xenogears pair at 0x800625FC /
             * 0x8006261E, 34B each). Record the pointers; the proven
             * pad-feed mechanism keeps driving the settled handshake
             * (do-not-poison: never rewrite the buffers here). */
            g_pad_buf1 = r[4]; g_pad_buf2 = r[6];
            bios_log(gate, fn, "(pad buffers registered)");
            fprintf(stderr, "[bpad] InitPAD buf1=%08X len1=%u buf2=%08X len2=%u\n",
                    r[4], r[5], r[6], r[7]);
            r[2] = 1;
            return;
        case 0x13: /* StartPAD() — R145 (audit #4): acknowledge pad
             * background polling ON. The existing pad-feed continues
             * to service the buffers. */
            g_pad_active = 1;
            bios_log(gate, fn, "(pad active)");
            fprintf(stderr, "[bpad] StartPAD — pad background polling ACTIVE\n");
            r[2] = 1;
            return;
        case 0x17: /* ReturnFromException — R145 (audit #2): our HLE
             * never raises CPU exceptions, so this should NEVER fire.
             * If it does, the kernel is in its exception-recovery
             * path — name it loudly so the digest catches the class. */
            bios_log(gate, fn, "(*** EXCEPTION RETURN — HLE never traps! ***)");
            fprintf(stderr, "[bxcep] ReturnFromException r31=0x%08X custom_exit=0x%08X r4=0x%08X r5=0x%08X\n",
                    r[31], g_custom_exception_exit, r[4], r[5]);
            r[2] = 0;
            return;
        case 0x19: /* SetCustomExitFromException(addr) — R145 (audit
             * #3): record the kernel's exception-recovery hook and
             * return the previous one (BIOS semantics). */
            bios_log(gate, fn, "(custom exit registered)");
            fprintf(stderr, "[bxcep] SetCustomExitFromException addr=0x%08X (prev=0x%08X)\n",
                    r[4], g_custom_exception_exit);
            r[2] = g_custom_exception_exit;
            g_custom_exception_exit = r[4];
            return;
        }
        break;
    case 0xC0:
        switch (fn) {
        case 0x0A: { /* ChangeClearRCnt(rcnt, flag) — R145 (audit #1):
             * root-counter auto-clear config. Store the flag, return
             * the PREVIOUS flag (BIOS semantics). Deliberately NOT
             * writing the RC mode MMIO (0x1F801104/114/124): the
             * display/VSync flow is proven and the kernel configures
             * RC modes itself via the register district; the R144
             * park digest decides whether RC mode emulation is the
             * missing slot-event source before we touch live counters. */
            uint32_t prev = 0;
            if (r[4] < 3u) {
                prev = g_rc_clear[r[4]];
                g_rc_clear[r[4]] = r[5] ? 1u : 0u;
            }
            bios_log(gate, fn, "(rc clear flag stored)");
            fprintf(stderr, "[rcntc] ChangeClearRCnt rc=%u flag=%u -> prev=%u\n",
                    r[4], r[5], prev);
            r[2] = prev;
            return; }
        case 0x02: { /* SysEnqIntRP(priority, struct): REAL chain insert.
             * The unregister walk (fn_80039144, from completion cb
             * fn_80038B4C) compares chain links against (struct-16) and
             * spins forever when the entry was never inserted — the old
             * "captured" stub caused exactly that. Entry base = r5-16;
             * +12 = next link (pre-zeroed by the struct creator). */
            uint32_t ent = (r[5] - 16u) & ~15u, q, nx;
            bios_log(gate, fn, "(REAL insert)");
            memcpy(&q, xenolift_mem + 0x59410, 4);
            { /* R100: dump the registered struct to identify the kernel CD IRQ handlers */
            fprintf(stderr, "[enqstruct] 0x8005A1F0: %08X %08X %08X %08X | 0x8005A200: %08X %08X %08X %08X\n",
                    *(uint32_t*)(void*)(xenolift_mem + 0x5A1F0u), *(uint32_t*)(void*)(xenolift_mem + 0x5A1F4u),
                    *(uint32_t*)(void*)(xenolift_mem + 0x5A1F8u), *(uint32_t*)(void*)(xenolift_mem + 0x5A1FCu),
                    *(uint32_t*)(void*)(xenolift_mem + 0x5A200u), *(uint32_t*)(void*)(xenolift_mem + 0x5A204u),
                    *(uint32_t*)(void*)(xenolift_mem + 0x5A208u), *(uint32_t*)(void*)(xenolift_mem + 0x5A20Cu));
        }
fprintf(stderr, "[enq] SysEnqIntRP prio=%u struct=0x%08X entry=0x%08X head=0x%08X\n",
                    r[4], r[5], ent, q);
            bios_inspect("irq-struct", r[5]);
            /* R84: the BIOS SysEnqIntRP list is SEPARATE from the
             * kernel's own chain at 0x80059410 (the kernel's list init
             * overwrites the head later — inserting there orphans entries).
             * Keep a BIOS-side shadow for logging; kernel list untouched. */
            if (ent >= 0x80000000u && ent < 0x80200000u) {
                uint32_t z = 0, shadow = XENOLIFT_BIOS_T + 0x300u;
                memcpy(xenolift_mem + (shadow - 0x80000000u) + 12, &ent, 4);
                (void)z; (void)q; (void)nx;
            }
            r[2] = 0;
            return;
        }
        case 0x03: { /* SysDeqIntRP(priority, struct): LOG-ONLY (R92).
             * REVERT of the R83 unlink: 0x80059410 is NOT an IRQ event
             * chain — fn_80038F18 walks it as a first-fit BLOCK FREE-LIST
             * (size = next - data; the fd module allocates 0x850-byte CD
             * sector buffers from it). Our unlink rewired +12 links of
             * REAL heap blocks and created the cycle the allocator now
             * spins in. No writes, ever. */
            uint32_t ent = (r[5] - 16u) & ~15u, q;
            bios_log(gate, fn, "(log-only)");
            memcpy(&q, xenolift_mem + 0x59410, 4);
            fprintf(stderr, "[deq] SysDeqIntRP prio=%u struct=0x%08X entry=0x%08X flhead=0x%08X\n",
                    r[4], r[5], ent, q);
            r[2] = 0;
            return;
        }
        }
        break;
    }

    /* everything else: stubbed for now */
    bios_log(gate, fn, "(stubbed, v0=0)");
    r[2] = 0;
}

static long g_trace_lines = 0;

/* R79: last-24 dispatch ring — printed on any fault so the exact call
 * path into the crash is on the record. */
uint32_t xenolift_ring[64]; int xenolift_ring_n;
int xenolift_spfix_n = 0; /* R233 sp-poison strip counter */
volatile uint32_t xenolift_cur_fn = 0; /* R227: live current-function for the crash report */

/* R117: overlay capture helper — dump a clamped window of RAM to
 * overlay_dump_N.bin. R116 bug: the guard `dest < 0x1E0000` skipped
 * the module region entirely (the module lives at 0x801F34B4 etc. =
 * the LAST 128KB of 2MB RAM → empty files, Jos md5 d41d8...x8).
 * Clamp to the RAM end instead of skipping. */
static int xenolift_ovl_dump(uint32_t vaddr, const char *tag)
{
    static int n = 0;
    if (n >= 8) return -1;
    if (vaddr < 0x80000000u || vaddr >= 0x80200000u) return -1;
    uint32_t dest = vaddr & 0x1FFFFFFFu; /* kseg0 -> phys */
    uint32_t avail = 0x200000u - dest;   /* clamp: never past RAM end */
    if (avail > 0x20000u) avail = 0x20000u;
    if (avail < 0x100u) return -1;
    char path[64];
    snprintf(path, sizeof path, "overlay_dump_%d.bin", n);
    FILE *f = fopen(path, "wb");
    if (!f) return -1;
    fwrite(xenolift_mem + dest, 1, avail, f);
    fclose(f);
    fprintf(stderr, "[ovl] captured %s @0x%08X (%u bytes) -> %s\n",
            tag, vaddr, avail, path);
    return n++;
}

void xenolift_trace(uint32_t a)
{
    xenolift_cur_fn = a;
    xenolift_fntrail[xenolift_fntrail_n++ & 15u] = a;  /* R642: rolling last-16 dispatch trail */
    /* R323 CHURN BOUNCE: universal entry chokepoint (XTRACE fires for every
     * guest fn, direct call or dispatch). Family fn entered >8MB deep from the
     * thread base = the eternal churn recursion -> bounce to the anchor. */
    if (a >= 0x8002A600u && a <= 0x8002B400u && xenolift_churn_armed) {
        volatile int pd_ = 0;
        if (xenolift_churn_base - (uintptr_t)&pd_ > 0x800000u) {
            if (xenolift_churn_bounces < 24u || (xenolift_churn_bounces % 100000u) == 0u)
                fprintf(stderr, "[smtr] bounce #%lu pend=%08X depth=0x%llX\n",
                        xenolift_churn_bounces, a,
                        (unsigned long long)(xenolift_churn_base - (uintptr_t)&pd_));
            xenolift_churn_bounces++;
            xenolift_churn_pend = a;
            longjmp(xenolift_churn_jmp, 1);
        }
    }
    /* R233: SP POISON STRIP at every function entry. Cycles 15-19: the
     * crash sp = 0x807FC8C8/0x807FC910 = healthy 0x801Fxxxx-class value
     * PLUS exactly 0x600000 (tag bits 21/22, same poison family as the
     * handoff stack-top). A LEGIT sp NEVER has bits 21-23 set (RAM tops at
     * 0x801FFFFF), so stripping those bits can never corrupt a valid
     * stack pointer. Catches the corruption at the FIRST entry after it
     * happens, whichever producer wrote it. */
    /* R233b predicate hardening: the LEGIT kernel stack top 0x80200000 HAS
     * bit 21 set (0x00200000) — the original mask would corrupt it to
     * 0x80000000. Strip ONLY when: value out of RAM, the stripped result
     * lands in valid RAM, and the low 21 bits are nonzero (round RAM-top
     * candidates like 0x80200000 are never touched; observed poisoned sp
     * values 0x807FC8C8/0x807FC910 always carry frame-offset low bits). */
    if ((r[29] & 0x00E00000u) != 0u && r[29] >= 0x80200000u && r[29] < 0x81000000u
        && (r[29] & 0x001FFFFFu) != 0u) {
        uint32_t stripped = r[29] & ~0x00E00000u;
        /* R244: tag-class poison (0x807FC910 -> 0x801FC910) keeps the
         * mask-strip (same frame, tag removed). But when the stripped
         * result is NOT a real stack frame (cycle-29: 0x80200018-class ->
         * 0x80000018 = RAM floor -> first push underflows to 0x7FFFFFE8),
         * restore the last-known-good stack instead. */
        if (stripped >= 0x801F0000u && stripped <= 0x80200000u)
            r[29] = stripped;
        else
            r[29] = xenolift_last_good_sp;
        if (xenolift_spfix_n < 8) {
            xenolift_spfix_n++;
            fprintf(stderr, "[sp-fix] #%d entry 0x%08X sp POISONED 0x807xxxxx-class -> stripped to 0x%08X caller r31=0x%08X\n",
                    xenolift_spfix_n, a, r[29], r[31]);
        }
    }
    xenolift_ring[xenolift_ring_n % 64] = a; xenolift_ring_n++;
    { /* R466: SECOND DEFIB POSTURE — staged-sector rescue. c29: after defib
       * #1 the chain runs to 108941 then stalls with the drive FULLY idle
       * (sched=0 act=0 pend=0 arm1=0) while a 2060B sector sits staged and
       * unconsumed (FE1C=1 poll). All natural armers gate on sched/act=0.
       * Same silence clock as R465; arm the data-ready INT1 instead. */
      static time_t r466_last_chg; static uint32_t r466_last_cnt; static uint32_t r466_fires;
      if (cd_seek_lba >= 108900u && r466_fires < 90u) {
        /* R467: c30 fix — clock must reset ONLY on real deliveries. The
         * R466 `|| cd_data_n != 0` reset defeated the timer (the stalled
         * posture has a sector staged forever = clock never accumulates),
         * and act stays 1 in the photo so the sched/act==0 gate never
         * matched. Posture per c28/c30 photos: staged unconsumed sector
         * (data_n>0) + no bell (pend=0, arm1=0) + FE1C=1 game poll. */
        if (g_fldsec_total != r466_last_cnt) {
          r466_last_cnt = g_fldsec_total;
          r466_last_chg = time(NULL);
        } else if ((r466_last_cnt > 0u) && (time(NULL) - r466_last_chg) >= 5
                   && cd_data_n > 0u && cd_pending == 0u
                   && cd_arm_int1_pending == 0u
                   && xenolift_mem_read32(0x8004FDF8u) > 0u) {
          cd_arm_int1_pending = 1; r466_fires++;
          fprintf(stderr, "[defib2] staged-sector INT1 arm #%u @dispatch loop (seek=%u data=%u/%u FDF8=%u FE1C=%u)\n", r466_fires, cd_seek_lba, cd_data_pos, cd_data_n,
                  xenolift_mem_read32(0x8004FDF8u),
                  xenolift_mem_read32(0x8004FE1Cu));
        }
      }
    }
    { /* R469->R470: FOURTH DEFIB v2 — pending-answer repair. c32: the
       * defib trio drove the ring self-pumping (108936->108960, 8 sectors/5s,
       * FDF8 125304->63864) until a NEW stall at t=36s: park shows
       * last_cmd=0x09 (SeekL) with its answer PENDING (pend=1), data staged,
       * and the game parked in FE1C=10 (the ladder state that arms 11).
       * The lad2 completion normally restores FE1C to the cmd's target state
       * (0x09 -> 6) on answer CONSUMPTION; the stalled game never consumes.
       * RAM-ONLY fix (lesson-safe: no guest dispatch from this context):
       * after 5s silence in field era with pend!=0 && last_cmd==0x09 &&
       * FE1C==10 && FDF8>0, write FE1C=6 (what lad2 would write) and let the
       * game's own FE1C poll (fn 80041CA0 -> state-6 handler) dispatch
       * natively on its next pass. The state-6 handler pops the response. */
      /* R470: c33 — defib4 v1 never fired: its clock keyed on g_fldsec_total
       * (stall forms LATE, after last delivery + healthy GetStat pops), and
       * park shows the true posture is BROKEN-PENDING: pend=1 with an EMPTY
       * response shelf (resp_n=0) — the SeekL answer was never staged.
       * v2: clock on the CD posture tuple itself; fire when the tuple is
       * STABLE for 5s AND matches (pend=1, resp_n=0, last_cmd=09, FE1C=10).
       * Action: stage the known-good 3-byte SeekL answer (02 01 01 — same
       * bytes the working FE1C=6 pops delivered), keep last_cmd=0x09,
       * restore FE1C 10->6 (the 0x09 target state, per lad2 mapping) so the
       * game's own state-6 handler pops it natively. RAM/CD-state only —
       * no guest dispatch (Lesson 1). rspop window armed for the verdict. */
      static time_t r470_last_chg; static uint32_t r470_tuple; static uint32_t r470_fires;
      uint32_t r470_now = (uint32_t)cd_pending | ((uint32_t)cd_resp_n << 4)
                        | ((uint32_t)cd_last_cmd << 8)
                        | ((uint32_t)xenolift_mem_read32(0x8004FE1Cu) << 16);
      if (r470_now != r470_tuple) {
        r470_tuple = r470_now;
        r470_last_chg = time(NULL);
      } else if ((time(NULL) - r470_last_chg) >= 5
                 && cd_seek_lba >= 108900u && r470_fires < 90u
                 && cd_pending != 0u && cd_resp_n == 0u
                 && cd_last_cmd == 0x09u
                 && xenolift_mem_read32(0x8004FE1Cu) == 10u
                 && cd_data_n > 0u
                 && xenolift_mem_read32(0x8004FDF8u) > 0u) {
        cd_resp[0] = 0x02; cd_resp[1] = 0x01; cd_resp[2] = 0x01;
        cd_resp_n = 3; cd_resp_pos = 0;
        memcpy(cd_last_full, cd_resp, 3); cd_last_full_n = 3;
        *(uint32_t *)(xenolift_mem + 0x4FE1Cu) = 6u;
        { extern int g_rspop_win; g_rspop_win = 24; }
        r470_fires++;
        fprintf(stderr, "[defib4] broken-pending repaired #%u: staged 02 01 01, FE1C 10->6 (seek=%u pend=%u FDF8=%u)\n",
                r470_fires, cd_seek_lba, cd_pending,
                xenolift_mem_read32(0x8004FDF8u));
      }
    }
        { /* R498: PHASE-CB CAMERA. c64: pre-shelved file 7 but phase-0 cb
         * 0x8001A4B4 still aborted(130) - photograph its entry state
         * (args + the request bookkeeping it plausibly checks). */
            /* R520 [glyphguard] — c87 verdict: there is NO menu#2. The mount
             * transition (MoveHeapAllocation 0x80019B44 -> RESTART STEP ->
             * ClearHeapRuntime 0x80019BEC -> MountGameStateModule) runs INSIDE
             * the single RunKernelMenu session; the 0x1E978 staging input then
             * lands at 0x801F80A4 = the LIVE font ctx block, and the NEXT frame's
             * SubmitGlyphPrimitives reads field data as glyph packets -> 0x03056410.
             * R519's entry-triggered phoenix was structurally too late/too early.
             * FIX at the fault site itself: ROLLING snapshot — every
             * SubmitGlyphPrimitives entry with a healthy in-RAM ctx+0x38 refreshes
             * the snapshot; an entry with ctx+0x38 outside RAM restores it. */
            if (a == 0x80037324u) { /* SubmitGlyphPrimitives entry */
                static uint8_t gg_snap[0x100]; static uint32_t gg_ctx; static int gg_saved;
                static int gg_restores; static int gg_snaps;
                uint32_t gctx = xenolift_mem_read32(0x80059394u);
                if (gctx >= 0x801F0000u && gctx < 0x80200000u) {
                    uint32_t v38 = xenolift_mem_read32(gctx + 0x38u);
                    if (v38 >= 0x80000000u && v38 < 0x80200000u) {
                        if (gg_snaps < 40u) {
                            memcpy(gg_snap, xenolift_mem + (gctx - 0x80000000u), 0x100);
                            gg_ctx = gctx; gg_saved = 1; gg_snaps++;
                            if (gg_snaps <= 4u)
                                fprintf(stderr, "[glyphguard] R520: healthy ctx %08X (+38=%08X) snapshotted #%d\n", gctx, v38, gg_snaps);
                        }
                    } else if (gg_saved && gctx == gg_ctx && gg_restores < 4u) {
                        memcpy(xenolift_mem + (gctx - 0x80000000u), gg_snap, 0x100);
                        gg_restores++;
                        fprintf(stderr, "[glyphguard] R520: ctx %08X SICK (+38=%08X) — RESTORED snapshot (restore #%d)\n", gctx, v38, gg_restores);
                    }
                }
            }
            if (a == 0x8001A4B4u) {
                /* R519 [ctxphoenix]: c84-c86 verdict — the glyph fault
                 * (SubmitGlyphPrimitives reading LW(ctx+0x38) garbage,
                 * computed 0x03056410, recovery->HALT ~30s) is the OLD
                 * double-booking: font ctx cell 0x80059394 = 0x801F80A4,
                 * the SAME high-end block the field mount re-allocates as
                 * its 0x1E978 decompress staging input (fn_80031C58 @
                 * caller 80031C2C). Menu #1 draws BEFORE the field data
                 * lands (fvp strings prove it); the restart's menu #2
                 * draws AFTER, reading field garbage as font packets.
                 * The mangleguard family (R517/R518) is orthogonal — the
                 * c86 crash is byte-identical with those drops active.
                 * FIX: snapshot the ctx block at menu #1 entry (healthy),
                 * restore it at menu #2 entry. The staging input is dead
                 * data by then (field module already installed at
                 * 0x801D9724, fldsec #32-96 prove delivery complete), so
                 * the restore is free. One-shot, 4-fire budget. */
                static int ctpx_n; static uint32_t ctpx_ctx; static int ctpx_saved;
                static uint8_t ctpx_snap[0x100];
                uint32_t ctx_now = xenolift_mem_read32(0x80059394u);
                ctpx_n++;
                if (ctpx_n == 1u && ctx_now >= 0x80000000u && ctx_now < 0x80200000u) {
                    ctpx_ctx = ctx_now; ctpx_saved = 1;
                    memcpy(ctpx_snap, xenolift_mem + (ctpx_ctx - 0x80000000u), 0x100);
                    fprintf(stderr, "[ctxphoenix] R519: menu#1 ctx %08X snapshotted (0x100B) — will restore at menu#2\n", ctpx_ctx);
                } else if (ctpx_n == 2u && ctpx_saved &&
                           ctx_now == ctpx_ctx &&
                           xenolift_mem_read32(ctpx_ctx + 0x38u) != ((uint32_t *)ctpx_snap)[14]) {
                    memcpy(xenolift_mem + (ctpx_ctx - 0x80000000u), ctpx_snap, 0x100);
                    fprintf(stderr, "[ctxphoenix] R519: menu#2 ctx %08X RESTORED (ctx+38 was garbage, now %08X) — glyph path re-armed\n",
                            ctpx_ctx, ((uint32_t *)ctpx_snap)[14]);
                }
                static int r498_n;
                if (r498_n++ < 8u)
                    fprintf(stderr, "[ph2] cb 0x8001A4B4 entry r4=%08X r5=%08X r6=%08X r17=%08X r31=%08X | FE04=%08X FDF8=%08X FE1C=%08X FE20=%08X | q59F10=%08X q59F18=%08X | cfg0=%08X cfg1=%08X\n",
                            r[4], r[5], r[6], r[17], r[31],
                            xenolift_mem_read32(0x8004FE04u), xenolift_mem_read32(0x8004FDF8u),
                            xenolift_mem_read32(0x8004FE1Cu), xenolift_mem_read32(0x8004FE20u),
                            xenolift_mem_read32(0x80059F10u), xenolift_mem_read32(0x80059F18u),
                            xenolift_mem_read32(0x800694A4u), xenolift_mem_read32(0x8006948Cu));
            }
        }
        { /* R473: STALLED-LOAD COMPLETION (defib6, MOVED c37: was parked at the fd-tick helper site - DEAD CONTEXT during the SliceLoopA stall, never evaluated; defibs live in the hot dispatch loop where defib4 runs every pass) (defib6). c34-c36: THREE identical
           * stall photos at the file2->file3 handoff: the guest slips into the
           * SliceLoopA movie-skip poll BEFORE file 3 (LBA 108785, FDF8=155120)
           * drains, and the skip countdown never advances until the CURRENT
           * read completes (c33 proof: skip fired at FDF8=0) - but the drain
           * is driven by the very poll contexts the guest no longer visits.
           * Self-locking door. R471's drain fired 25x with zero effect =
           * stacked conversions were never the issue. RESCUE: when the read
           * posture (FDF8, seek) is FROZEN >=8s with 0 < FDF8 < 200000 and a
           * staged-undrained sector, complete the load OURSELVES the same way
           * the guest's DMA would: payload -> current ring slot (FE08), FE08
           * += 0x800 (the walker's own cadence), FDF8 -= 2048 clamped at 0,
           * seek++. RAM-only (no guest dispatch from this context). The skip
           * poll reads FDF8 itself; at 0 it walks on natively. Mercy 5. */
            static time_t r472_chg; static uint32_t r472_f1, r472_sk, r472_fires;
            uint32_t fdf8 = xenolift_mem_read32(0x8004FDF8u);
            if (fdf8 != r472_f1 || cd_seek_lba != r472_sk) {
            if (fdf8 > r479_max) r479_max = fdf8; /* R479: full size = max FDF8 this file */
                r472_f1 = fdf8; r472_sk = cd_seek_lba; r472_chg = time(NULL);
            } else if (fdf8 == 0u && (time(NULL) - r472_chg) >= 2u) {
                /* R496: NEVER-ARMED REQUEST. c62: boot completed ALL
                 * file installs natively (no walker fault - carry-v3 +
                 * frontguard clean), the phase engine ran cb 0x8001A4B4,
                 * and the game ABORTED (AbortOnGameFault 130 @0x80019AF8):
                 * file 7 (LBA 108886, 13768B) was queued (FE04=0x1A954,
                 * 6+ unserved kicks) but FDF8 was never armed - the
                 * rescue gate needs 0<FDF8 so it never fired, and the
                 * phase's poll limit expired. FIX: the game's own file
                 * table lives at 0x800100A5 (7-byte members: 3-byte LBA
                 * + 4-byte size, m=1..12 - confirmed by [ftab]/[stab]
                 * receipts). If the frozen seek matches a member, arm
                 * FDF8 with its size exactly like a fresh announce; the
                 * rescue's own machinery then stuffs the ring and the
                 * guest porter delivers to its own dest. */
                static uint32_t r496_served;
                for (uint32_t m = 1u; m <= 12u; m++) {
                    const uint8_t *fe = xenolift_mem + 0x000100A5u + 7u * (m - 1u);
                    uint32_t mlba = fe[0] | (fe[1] << 8) | (fe[2] << 16);
                    uint32_t msize = fe[3] | (fe[4] << 8) | (fe[5] << 16) | ((uint32_t)fe[6] << 24);
                    if (mlba == cd_seek_lba && mlba > 100000u && msize >= 8u && msize <= 0x100000u
                        && r496_served != cd_seek_lba
                        && r497_shelved_lba != cd_seek_lba) { /* R497: pre-shelved files need no arm */
                        r496_served = cd_seek_lba;
                        xenolift_mem_write32(0x8004FDF8u, msize);
                        if (msize > r479_max) r479_max = msize;
                        fprintf(stderr, "[defib6] R496 ARM: queued request lba %u never armed (FDF8=0) - armed FDF8=%u from game file table member %u, rescue follows\n",
                                cd_seek_lba, msize, m);
                        break;
                    }
                }
            } else if ((time(NULL) - r472_chg) >= 2 /* R477: 8s->2s.
                       * c41 race: boot reached file-6's INSTALL step at
                       * the same ~8s mark the rescue needed to fire, so
                       * fn_80019740 installed an EMPTY WDS bank (fd-kick
                       * showed the 108884 request queued-unserved the whole
                       * time) -> LoadAndRegisterWdsBank parsed garbage ->
                       * store to heap_ptr+0x21000000 -> fault. The posture
                       * (frozen FDF8 + staged sector + read_active + boot
                       * LBA range) is tight: healthy drains move FDF8 in
                       * ms, so 2s freeze = genuine stall. Fire BEFORE the
                       * boot's installer arrives. */
                       && fdf8 > 0u && fdf8 < 200000u
                       && cd_read_active && cd_data_loaded
                       && r472_fires < 5u
                       && cd_seek_lba >= 108754u && cd_seek_lba <= 109400u) {
                uint32_t r472_n = 0u;
                while (fdf8 > 0u && r472_n < 200u) {
                    uint32_t slot = xenolift_mem_read32(0x8004FE08u);
                    /* R476: RING WRAP. c40: skip gate OPENED (4 rescues,
                     * files 3/4/5/6 completed) but the rescue walked FE08
                     * 101 slots straight past the ring's end into the
                     * 0x800Axxxx module/heap arena - trampling file-4/6
                     * buffers (0x800A49E8) and heap nodes (0x800A544C)
                     * -> boot crashed at fn_800197BC's heap walk with a0=0.
                     * The guest's own walker CYCLES slots; observed span:
                     * base 0x8006FAF8, last seen slot 0x8007EAF8. Wrap
                     * there: later sectors reuse slots (decoder consumes
                     * as they fill - and we skip the movie anyway). */
                    if (slot < 0x8006FAF8u || slot > 0x8007EAF8u)
                        slot = 0x8006FAF8u;
                    uint32_t idx = slot - 0x80000000u;
                    if (idx < 0x10000u || idx + 2048u > 0x200000u) {
                        fprintf(stderr, "[defib6] R473 rescue ABORT: ring slot 0x%08X out of RAM\n", slot);
                        break;
                    }
                    if (disc_read_lba(cd_seek_lba, xenolift_mem + idx) != 0)
                        memset(xenolift_mem + idx, 0, 2048);
                    /* R479: PORTER-CARRY. Ring-stuff alone is cargo on the
                     * dock: the boot only waits on FDF8, the porter copies
                     * ring->dest, and the porter is stalled. Copy the chunk
                     * to the DESTINATION ourselves: dest + (size - FDF8) is
                     * the porter's own destination math (dest advances as
                     * FDF8 drops). Guard: only when dest was announced for
                     * the current file (seek within ~80 LBAs of the announce
                     * snapshot) - otherwise skip carry and say so. */
                    if (r479_valid
                        && (r490_map_lookup(cd_seek_lba, 0) != 0u
                            || (cd_seek_lba >= r479_seek0
                                && cd_seek_lba <= r479_seek0 + 80u))) {
                        /* R482: CARRY-V2 (header + payload stream). c46 decode
                         * final: the fault regs show the WDS bank record
                         * pointer at r12 = dest-8 — each file's first 8
                         * bytes are an internal header (declares size)
                         * that lands at dest-8, and the payload streams to
                         * dest from file offset 8. The stalled game
                         * consumed those 8 bytes (FDF8 froze at size-8) but
                         * never wrote them; R479's carry also shifted the
                         * whole payload +8. The consumer parsed the stale
                         * header -> size 0xDF000011 -> the sound-heap
                         * allocator walked off the world. V2, one shot per
                         * fire: write file[0:8] -> dest-8, then stream
                         * file[8+done_p .. size) to dest+done_p with proper
                         * sector-boundary math. */
                        static uint32_t r482_stamp;
                        uint32_t stamp = cd_seek_lba; /* R490: key to the file being rescued, not the drifting announce */
                        if (r482_stamp != stamp) {
                            r482_stamp = stamp;
                            uint32_t start = cd_seek_lba;
                            /* R486: c52 crash @runtime.c:5569 — on the FIRST stuff
                             * pass after a new ovlread, r479_max still holds the
                             * PREVIOUS file's size while fdf8 is the new file's
                             * FULL count: done = max - fdf8 UNDERFLOWED (~4GB),
                             * the payload stream ran to a wild offset and the
                             * disc read segfaulted the host. Gate the carry on
                             * size sanity; if stale, DON'T stamp so a later pass
                             * (after r479_max catches the new file's FDF8) can
                             * still carry. */
                            /* R489: c55 verdict — the DEFER was lethal:
                             * fdf8 IS this file's authoritative remaining
                             * count (155120 = file-3 size exactly), captured
                             * by the game's own request. The rescue finishes
                             * the whole file in ONE fire, so a "later pass"
                             * never comes: the carry never fired, dest kept
                             * stale heap bytes, and the sound installer read
                             * garbage (wdsdiff bank-2 struct). PROMOTE fdf8 to
                             * r479_max when the file identity gate already
                             * passed, then carry on THIS pass. */
                            if (fdf8 != r479_max && r479_valid && fdf8 >= 8u && fdf8 <= 0x400000u) { /* R490: adopt BOTH directions (c56 fire#3: 21984 < stale 23744, never promoted) */
                                r479_max = fdf8;
                                fprintf(stderr, "[defib6] R489 carry PROMOTE: size adopted from fdf8 (%u) — carrying this pass\n", fdf8);
                            }
                            if (fdf8 > r479_max || r479_max < 8u) {
                                fprintf(stderr, "[defib6] R486 carry DEFER: size stale (max=%u fdf8=%u, likely pre-sample pass)\n",
                                        r479_max, fdf8);
                            } else {
                            uint32_t rem = 0u, src = 0u, doff = 0u;
                            uint32_t cdest = 0u;
                            uint32_t cmap = r490_map_lookup(start, &cdest);
                            int r495_full = (cmap != 0u && s_ovl_size[cmap] >= 8u
                                             && s_ovl_size[cmap] <= 0x400000u);
                            if (r495_full) {
                                /* R495: FULL RE-SHELVE. c61: the old mid-file
                                 * offset heuristic (payload_done derived from the
                                 * stall's FDF8 bookkeeping, size PROMOTEd from a
                                 * mid-file fdf8) wrote file-6's TAIL bytes over
                                 * its header - dest[0:4] read 0xBEB87639 (= file
                                 * bytes [2056:2060)) -> decompressor ran with
                                 * len=3.2GB, produced garbage, walker then faulted
                                 * at 0xC16749B8. The only safe carry is the WHOLE
                                 * file from its start lba with the native layout:
                                 * payload = file[8:] -> dest+0. Same as the heal. */
                                start = s_ovl_lba[cmap];
                                r479_max = s_ovl_size[cmap] + 8u;
                                rem = s_ovl_size[cmap] - 8u;
                                src = 8u;
                                doff = 0u;
                            } else {
                                uint32_t done = r479_max - fdf8;
                                uint32_t payload_done = (done >= 8u) ? done - 8u : 0u;
                                uint32_t hdr_pending = (done < 8u);
                                rem = fdf8 - (hdr_pending ? 8u : 0u);
                                src = 8u + payload_done;
                                doff = payload_done;
                            }
                            if (cmap == 0u) {
                                static int r492_nomap;
                                if (r492_nomap++ < 3)
                                    fprintf(stderr, "[defib6] R492 carry SKIP: lba %u not in directory (no stale fallback) - heal will cover\n", start);
                            } else if (s_r491_carried[cmap]) {
                                /* R491: c57 — the game's seek advances PER SECTOR mid-file;
                                 * each advance re-armed the carry and re-shelved the whole file
                                 * 10x. One carry per file, keyed by the directory's file#.
                                 * The ring-stuffing below still satisfies the state machine. */
                                static int r491_skipn;
                                if (r491_skipn++ < 3)
                                    fprintf(stderr, "[defib6] R491 carry SKIP: file#%u already shelved (sector-seek %u)\n", cmap, start);
                                goto r491_carry_done;
                            }
                            if (cmap != 0u && cdest != r479_dest)
                                fprintf(stderr, "[defib6] R490 DIR-LOOKUP: lba %u => file#%u dest 0x%08X (last-announce 0x%08X was off-by-one)\n",
                                        start, cmap, cdest, r479_dest);
                            uint32_t dstart = cdest - 0x80000000u;
                            static uint8_t r482_tmp[2048];
                            if (dstart >= 0x10008u
                                && dstart + (r479_max - 8u) <= 0x200000u) {
                                /* R492: dest-8 belongs to the game's heap
                                 * machinery (live record at 0x8007EBE8 in
                                 * c58) - never write the file header there.
                                 * Payload -> dest only (native layout). */
                                while (rem > 0u) {
                                    uint32_t lba = start + (src / 2048u);
                                    uint32_t in_sec = src % 2048u;
                                    uint32_t chunk = 2048u - in_sec;
                                    if (chunk > rem) chunk = rem;
                                    if (src > r479_max || lba > start + (r479_max / 2048u) + 1u) {
                                        fprintf(stderr, "[defib6] R486 carry CLAMPED: src=%u lba=%u past file (max=%u)\n",
                                                src, lba, r479_max);
                                        break;
                                    }
                                    if (disc_read_lba(lba, r482_tmp) != 0)
                                        memset(r482_tmp, 0, 2048);
                                    memcpy(xenolift_mem + dstart + doff, r482_tmp + in_sec, chunk);
                                    src += chunk; doff += chunk; rem -= chunk;
                                }
                                fprintf(stderr, "[defib6] R495 carry-v3: full re-shelve %uB -> 0x%08X (file lba %u, %s)\n",
                                        doff + (rem > 0u ? rem - doff : 0u), cdest, start,
                                        r495_full ? "whole-file native layout" : "legacy offsets");
                            } else {
                                fprintf(stderr, "[defib6] R482 carry ABORT: dest range out of RAM (dstart 0x%08X)\n", dstart);
                            }
                            if (cmap != 0u) s_r491_carried[cmap] = 1u;
                            }
                        }
r491_carry_done: ;
                    } else if (r479_valid) {
                        fprintf(stderr, "[defib6] R479 carry SKIP: seek %u not in file window [%u,%u]\n",
                                cd_seek_lba, r479_seek0, r479_seek0 + 80u);
                    }
                    *(uint32_t *)(xenolift_mem + 0x4FE08u) = slot + 0x800u;
                    fdf8 = (fdf8 > 2048u) ? fdf8 - 2048u : 0u;
                    cd_seek_lba++;
                    r472_n++;
                }
                *(uint32_t *)(xenolift_mem + 0x4FDF8u) = fdf8;
                cd_data_loaded = 0; /* retire the staged-undrained sector */
                /* R474: skip-gate completion cells. c38: rescue completed the
                 * load (FDF8=0) but SliceLoopA's skip gate stayed shut. The
                 * healthy skip photo (c33 cntdn#3) shows at the skip instant:
                 * pass(77448)=0, FDF8=0, driver idle. c38 parked with
                 * pass(77448)=F41D0231 (movie module initialized EARLY) and
                 * FDFC=1 (we bypassed the file layer's completion steps).
                 * Mirror those two completion writes; camera verifies. */
                *(uint32_t *)(xenolift_mem + 0x4FDFCu) = 0u;
                *(uint32_t *)(xenolift_mem + 0x77448u) = 0u;
                r472_fires++;
                r472_chg = time(NULL);
                fprintf(stderr, "[defib6] R473 stalled-load COMPLETED: %u sectors stuffed into ring, FDF8=%u, seek=%u (fire #%u)\n",
                        r472_n, fdf8, cd_seek_lba, r472_fires);
                /* R539 [fldfin]: whole-file completion, second half (Jos
                 * 12:59 milestone directive — M1, no more per-sector
                 * chasing). c105-c107: the ring gets the whole file, FDF8
                 * hits 0, but the KERNEL DRIVER still sits mid-dance at its
                 * GetStat wait (FE1C 7/10; 3-byte answer alone didn't
                 * clear it). Complete the DRIVER side too: jump its
                 * expected-LBA cell to end-of-read, clear staged/pending
                 * state, leave the ack-family answer primed — its next poll
                 * should conclude end-of-read and report completion UP the
                 * stack to the file layer (mount chain proceeds). */
                if (cd_seek_lba >= 108995u && cd_seek_lba <= 108996u) {
                    xenolift_mem_write32(0x8004FE04u, cd_seek_lba);
                    cd_data_n = 0;
                    cd_pending = 0;
                    /* R540 [fldfin2]: c108 — the jump landed (park: seek=108995,
                     * FE04=1A9C3, 3-byte answer primed) but the kernel sat at
                     * its state-10 poll ALL RUN: rspop showed status 0x22 =
                     * motor-on + READING bit — the wait is for the reading bit
                     * to CLEAR (read done = not reading). fldfin left
                     * cd_read_active=1, so every re-prime kept saying
                     * "still reading" forever. End-of-read = drive NOT
                     * reading: clear the flag so re-primes answer 0x02 and
                     * the kernel's wait sees the done-transition. */
                    cd_read_active = 0;
                    cd_motor_on = 1;
                    /* R541 [fldfin3]: c109 — status now clean (act=0, 0x02
                     * answers) but kernel STILL parked at its state-10 poll;
                     * park shows sched=1 — the queue processor (0x80041CA0)
                     * sees "a read is still scheduled" and waits forever.
                     * End-of-read = request COMPLETE from the scheduler's
                     * view too: drop the scheduled flag. */
                    cd_scheduled = 0;
                    fprintf(stderr, "[fldfin3] R541: scheduler request cleared (cd_scheduled=0) at end-of-read\n");
                    cd_resp[0] = 0x02u; cd_resp[1] = 0x01u; cd_resp[2] = 0x01u;
                    cd_resp_n = 3; cd_resp_pos = 0;
                    fprintf(stderr, "[fldfin] R540: end-of-read + read-active CLEARED (FE04=%u FDF8=0 status=0x02) — done-transition armed\n",
                            cd_seek_lba);
                }
            }
        }
    { /* R474: SKIP-GATE CAMERA. c38: rescue completed the load (FDF8=0)
       * but the SliceLoopA skip gate stayed shut - stop theorizing gate
       * cells, observe them. While the skip-countdown sentinel is armed,
       * print the full candidate tuple every 2s. Healthy skip photo (c33
       * cntdn#3): frame=1196866 pass=0 FE1C=0 FE20=3 FDF8=0 last_cmd=01. */
        static time_t r474_last; static uint32_t r474_n;
        if (xenolift_mem_read32(0x80077014u) == 0x452DAAEEu && r474_n < 40u
            && (time(NULL) - r474_last) >= 2) {
            r474_last = time(NULL);
            fprintf(stderr, "[skipgate] FDF8=%u FDFC=%u pass=%08X frame=%08X FE1C=%u FE20=%u last_cmd=%02X read_act=%u loaded=%u armed1=%u\n",
                    xenolift_mem_read32(0x8004FDF8u),
                    xenolift_mem_read32(0x8004FDFCu),
                    xenolift_mem_read32(0x80077448u),
                    xenolift_mem_read32(0x80076F04u),
                    xenolift_mem_read32(0x8004FE1Cu),
                    xenolift_mem_read32(0x8004FE20u),
                    cd_last_cmd, cd_read_active, cd_data_loaded,
                    cd_arm_int1_pending);
            r474_n++;
        }
    }
    { /* R468: THIRD DEFIB — deliver the armed data-ready ring. c31: defib2
       * arms arm1=1 (park proves it), but the 802-ack delivery path (case
       * 0x1F801802 arm block) only fires when the GUEST writes 0x7 to bank1 —
       * and the stalled game sits polling FE1C=1 without writing (deadlock:
       * we wait for its ack-write, it waits for our data-ready ring).
       * Same 5s-silence clock: if arm1==1 + staged data + ring owes bytes,
       * execute the 802-arm body verbatim (prime data-ready resp, pend=1,
       * force IRQ) so the existing rspop/conversion machinery delivers it
       * at the guest's next poll. Mercy 90; one-shot per arm (arm1 clears). */
      static time_t r468_last_chg; static uint32_t r468_last_cnt; static uint32_t r468_fires;
      if (cd_seek_lba >= 108900u && r468_fires < 90u) {
        if (g_fldsec_total != r468_last_cnt) {
          r468_last_cnt = g_fldsec_total;
          r468_last_chg = time(NULL);
        } else if ((r468_last_cnt > 0u) && (time(NULL) - r468_last_chg) >= 5
                   && cd_arm_int1_pending == 1u && cd_data_n > 0u
                   && cd_pending == 0u
                   && xenolift_mem_read32(0x8004FDF8u) > 0u) {
          cd_arm_int1_pending = 0;
          cd_resp[0] = 0x02;
          cd_resp_n = 1;
          cd_resp_pos = 0;
          cd_pending = 1;
          if (!cd_data_loaded)
              cd_data_load();
          g_cd_irq_force = 1;
          r468_fires++;
          fprintf(stderr, "[defib3] armed-ring delivered #%u @dispatch loop (seek=%u data=%u/%u FDF8=%u FE1C=%u)\n",
                  r468_fires, cd_seek_lba, cd_data_pos, cd_data_n,
                  xenolift_mem_read32(0x8004FDF8u),
                  xenolift_mem_read32(0x8004FE1Cu));
        }
      }
    }
    {   /* R465: SELF-DRIVING SECTOR BELL (defibrillator) — c28 freeze photo
         * decoded the wall: after the last natural rearm (LBA 108946) no
         * emulator context re-arms the bell again; the grind's new wait-loop
         * shape never re-enters the stepper branches that do the arming, so
         * nothing stages the next sector and the game waits forever. The
         * main dispatch loop runs in EVERY guest context — so it is the one
         * place that can always ring the bell. Tight gates: field ring owes
         * bytes (FDF8>0), nothing staged (data_n==0), no bell pending
         * (pend==0 AND arm1==0), read still active/scheduled, and delivery
         * silent >=5s. Same action as the FE1C-poll rearm: cd_pending=1.
         * Mercy budget: 90 fires. */
        static time_t r465_last_del; static uint32_t r465_last_cnt, r465_fires;
        if (cd_seek_lba >= 108900u && r465_fires < 90u) {
            time_t r465_now = time(NULL);
            if (g_fldsec_total != r465_last_cnt) { r465_last_cnt = g_fldsec_total; r465_last_del = r465_now; }
            else if (r465_last_cnt > 0u && (r465_now - r465_last_del) >= 5
                     && cd_data_n == 0u && cd_pending == 0u && cd_arm_int1_pending == 0u
                     && xenolift_mem_read32(0x8004FDF8u) > 0u
                     && (cd_scheduled || cd_read_active)) {
                cd_pending = 1; r465_fires++;
                fprintf(stderr, "[defib] self-driving sector bell #%u @dispatch loop (seek=%u FDF8=%u sectors=%u FDE4=%08x)\n",
                        r465_fires, cd_seek_lba,
                        xenolift_mem_read32(0x8004FDF8u), g_fldsec_total,
                        xenolift_mem_read32(0x8004FDE4u));
            }
        }
    }
    /* task-family entry trace: the work queue is a 20-byte-node ring
     * (post core 0x8003BCA0, start/advance 0x8003BE68, notifier
     * 0x8003BB64, type-1 body 0x8004D878 -> loader 0x8004CF38).
     * These run rarely; always log entries to see the task lifecycle. */
    if (a == 0x800392ECu) /* R94: block-clear from FOUND = alloc RESULT */
        fprintf(stderr, "[clear] AllocateSoundHeapBlock RESULT block=0x%08X size=0x%X\n", r[4], r[5]);
    if (a == 0x80038F18u) { /* R93: AllocateSoundHeapBlock entry trace */
        uint32_t fh_, lim_, evc_;
        memcpy(&fh_, xenolift_mem + 0x59410, 4);
        memcpy(&lim_, xenolift_mem + 0x595E4, 4);
        memcpy(&evc_, xenolift_mem + 0x595BC, 4);
        fprintf(stderr, "[alloc] AllocateSoundHeapBlock size=0x%X caller=0x%08X head=0x%08X limit=0x%08X evt=0x%08X\n",
                r[4], r[31], fh_, lim_, evc_);
    }
    if (a == 0x8003BCA0u || a == 0x8003BE68u || a == 0x8003BB64u ||
        a == 0x8004D878u || a == 0x8004CF38u || a == 0x8004CCA8u ||
        a == 0x8004C970u || a == 0x80038B4Cu ||
        a == 0x8002A68Cu || a == 0x8002B084u ||
        a == 0x8004E3C8u || a == 0x8004D930u ||
        a == 0x8004D028u || a == 0x8004D270u ||
        a == 0x80037DC0u || a == 0x80037B88u ||
        a == 0x80040A8Cu) {
        static uint32_t task_log_n;
        task_log_n++;
        if (task_log_n <= 40u || (task_log_n & 65535u) == 0u)
            fprintf(stderr, "[task] enter 0x%08X (n=%u)\n", a, task_log_n);
    }
    /* R603 [cbcall]: c170 verdict — the R602 stream-truth needle CLIMBS the
     * whole batch (heals 108998..109025+, monotonic, drag-back defeated) yet
     * the game never consumes: FE34 frozen at 1, queue node parked idle,
     * stepper F0C stuck at 14. Are the game's OWN archive callbacks
     * (file-ready 0x8002B084 / stream-ready 0x8002B2F0) ever ENTERED during
     * the stream era, and with what state? Entry probe answers it. */
    /* R624 INSTALLRESET witness: c194 verdict — early latch HELD the whole
     * walk (game accepted 92BC=1, never cleared) yet mount still did not
     * conclude (idx=1 at park). The remaining suspect is the file-14 install
     * itself: FILE-CB #43 (dest 801DBF24, FDF8=0x1C178) is followed by #44
     * (dest ADVANCED +0x800, FDF8 RESET to FULL 0x1E978) — the install
     * restarts after ~6 sectors. When remaining jumps UP mid-install, dump
     * the full archive state ONCE per occurrence (cap 6) so the reset's
     * driving cells (FE38/FE3C archive position, FDE4/FDE8 pass counters,
     * FDFC) land in the digest. */
    if (a == 0x8002B084u) {
        static uint32_t prev_fdf8; static int rst_n;
        uint32_t now_fdf8 = xenolift_mem_read32(0x8004FDF8u);
        if (rst_n < 6 && prev_fdf8 != 0u && now_fdf8 > prev_fdf8 + 0x1000u) {
            rst_n++;
            fprintf(stderr, "[cd] R624 INSTALLRESET #%d: FDF8 %08X -> %08X (remaining JUMPED UP) | FE00=%08X FE04=%08X FE08=%08X FE0C=%08X FE10=%08X FE14=%08X FE18=%08X FE1C=%08X FE20=%08X FE24=%08X FE28=%08X FE2C=%08X FE30=%08X FE34=%08X FE38=%08X FE3C=%08X | FDE4=%08X FDE8=%08X FDFC=%08X F0C=%08X F10=%08X | 92BC=%08X idxFAEC=%08X\n",
                    rst_n, prev_fdf8, now_fdf8,
                    xenolift_mem_read32(0x8004FE00u), xenolift_mem_read32(0x8004FE04u),
                    xenolift_mem_read32(0x8004FE08u), xenolift_mem_read32(0x8004FE0Cu),
                    xenolift_mem_read32(0x8004FE10u), xenolift_mem_read32(0x8004FE14u),
                    xenolift_mem_read32(0x8004FE18u), xenolift_mem_read32(0x8004FE1Cu),
                    xenolift_mem_read32(0x8004FE20u), xenolift_mem_read32(0x8004FE24u),
                    xenolift_mem_read32(0x8004FE28u), xenolift_mem_read32(0x8004FE2Cu),
                    xenolift_mem_read32(0x8004FE30u), xenolift_mem_read32(0x8004FE34u),
                    xenolift_mem_read32(0x8004FE38u), xenolift_mem_read32(0x8004FE3Cu),
                    xenolift_mem_read32(0x8004FDE4u), xenolift_mem_read32(0x8004FDE8u),
                    xenolift_mem_read32(0x8004FDFCu),
                    xenolift_mem_read32(0x80059F0Cu), xenolift_mem_read32(0x80059F10u),
                    xenolift_mem_read32(0x800592BCu), xenolift_mem_read32(0x8005FAECu));
        }
        /* R626 RESUMEFIX (c195/c196 decode: PAENTRY #5 entered with FE04=1 =
         * half-restart: dest kept mid-install but remaining re-primed FULL.
         * The game's own arithmetic says N sectors already copied (dest -
         * 801D9724). Restore remaining = 0x1E978 - bytes-copied so the
         * callback's copy math stays coherent and the install can run to
         * completion (FDF8 -> 0 fires the done-path: HandleCdReadyCompletion
         * -> PositionArchiveEntry advances the archive request). Era-gated
         * to the file-14 install dest range; receipt per correction; cap 8. */
        if (now_fdf8 == 0x0001E978u) {
            uint32_t dstp = xenolift_mem_read32(0x8004FE08u);
            if (dstp > 0x801D9724u && dstp < 0x801DF924u && prev_fdf8 != 0u &&
                prev_fdf8 < now_fdf8) { /* R627: real reset sig = FULL-minus-5-sectors (0x1C178 vs 0x1E978) */
                uint32_t copied = dstp - 0x801D9724u;
                uint32_t corrected = 0x0001E978u - copied;
                static int rsn; static int rsn_done;
                if (rsn_done < 8 && corrected > 0u && corrected < now_fdf8) {
                    rsn_done++;
                    xenolift_mem_write32(0x8004FDF8u, corrected);
                    fprintf(stderr, "[cd] R626 RESUMEFIX #%d: FDF8 reprimed FULL 0x1E978 -> corrected %08X (dest %08X, %u bytes copied) - install resumes from game's own math\n",
                            rsn_done, corrected, dstp, copied);
                }
            }
        }
        prev_fdf8 = now_fdf8;
    }

    if (a == 0x8002A394u) { /* R625 PAENTRY: c195 INSTALLRESET #2 fingerprint —
     * the file callback's done-path runs PositionArchiveEntry the instant a
     * read chunk ends (L_8002B1D4 window), and the NEXT FILE-CB entry shows
     * FDF8 reset to FULL size with dest kept advanced. Is PA the reset writer?
     * Dump the archive cells BEFORE it runs and AFTER it returns (the return
     * is the cbcall entry that follows). Cap 8. */
        static uint32_t pa_n;
        pa_n++;
        if (pa_n <= 8u)
            fprintf(stderr, "[paentry] R625 #%u ENTRY: FE00=%08X FE04=%08X FE08=%08X FE0C=%08X FE14=%08X FE18=%08X FE20=%08X FE38=%08X FE3C=%08X FDE4=%08X FDE8=%08X FDF8=%08X FDFC=%08X F0C=%u F10=%08X\n",
                    pa_n,
                    xenolift_mem_read32(0x8004FE00u), xenolift_mem_read32(0x8004FE04u),
                    xenolift_mem_read32(0x8004FE08u), xenolift_mem_read32(0x8004FE0Cu),
                    xenolift_mem_read32(0x8004FE14u), xenolift_mem_read32(0x8004FE18u),
                    xenolift_mem_read32(0x8004FE20u),
                    xenolift_mem_read32(0x8004FE38u), xenolift_mem_read32(0x8004FE3Cu),
                    xenolift_mem_read32(0x8004FDE4u), xenolift_mem_read32(0x8004FDE8u),
                    xenolift_mem_read32(0x8004FDF8u), xenolift_mem_read32(0x8004FDFCu),
                    xenolift_mem_read32(0x80059F0Cu), xenolift_mem_read32(0x80059F10u));
    }
    if (a == 0x8002B084u || a == 0x8002B2F0u) {
        static uint32_t cb_n;
        cb_n++;
        if (cb_n <= 200u)
            fprintf(stderr, "[cbcall] R603 entry %s #%u: FE34=%u FE08=%08X FDE4=%u FDE8=%08X FDF8=%08X FDFC=%08X FE1C=%u FE20=%u F0C=%u F10=%08X\n",
                    a == 0x8002B084u ? "FILE-CB 8002B084" : "STREAM-CB 8002B2F0", cb_n,
                    xenolift_mem_read32(0x8004FE34u), xenolift_mem_read32(0x8004FE08u),
                    xenolift_mem_read32(0x8004FDE4u), xenolift_mem_read32(0x8004FDE8u),
                    xenolift_mem_read32(0x8004FDF8u), xenolift_mem_read32(0x8004FDFCu),
                    xenolift_mem_read32(0x8004FE1Cu), xenolift_mem_read32(0x8004FE20u),
                    xenolift_mem_read32(0x80059F0Cu), xenolift_mem_read32(0x80059F10u));
    }
    if (a == 0x80044B70u) { /* SubmitGpuPrimitive___PsyQ_libgpu (R148) */
        g_gpu_prims++;
        g_gpu_last_prim = r[4];
        g_gpu_last_tag = xenolift_mem_read32(r[4]);
        if (g_gpu_prims <= 24u || (g_gpu_prims % 500u) == 0u)
            fprintf(stderr, "[gpuprim] #%u prim=0x%08X tag=0x%08X len=%u caller=0x%08X\n",
                    g_gpu_prims, r[4], g_gpu_last_tag,
                    xenolift_mem_read8(r[4] + 3u), r[31]);
    }
    if (a == 0x8004659Cu) { /* cwb: the finite GP0 word-pusher (R148) */
        g_gpu_words += r[5] & 0xFFFFu;
    }

    /* R71 heap + trap trace: crash chain decoded — fn_80019D48 (display
     * step) does s2 = fn_80032E88(0x8004EABC,1) (heap-alloc + decompress);
     * s2 == NULL -> jalr-report fn_800320E8(NULL) = trap 0x83 ->
     * fn_80019ACC(0x83) -> SystemError park. The allocator fn_80031BDC
     * walks a freelist at gp+432 (0x80059320), installed by heap-init
     * fn_80031A30 (called from boot state machine 0x80019BE4). Earlier
     * factory calls (0x800197C8, 0x80019820) succeeded, so the heap
     * exhausted by the display step. Trace every piece. */
    /* R75 arena installs: fn_80031A68 (called from boot main 0x80019638)
     * installed the observed freelist block 0x8006FAF8; fn_80031B10 (called
     * from state machine 0x80019B3C/0x80019BDC which never ran) installs
     * phase-table blocks (+8 field). Log both installs + header words to
     * see what arena the kernel built vs what it should have had. */
    if (a == 0x80031A68u) {
        /* R185: PRIME-OBJECTIVE CLOSURE. fn_80031A68 emitted-vs-original
         * verified INSTRUCTION-FOR-INSTRUCTION faithful (a3/t0 masks, a0&=-4,
         * head=block+8 -> gp+0x1B0, w0=end, w1=old|0x84000000, terminator
         * {end, old_tail&0xFE1FFFFF|0x00200000|0x80000000} at end-8). Every
         * crash-chain link is now faithful; the divergence must be STATE:
         * the arena (start,end) ARGUMENTS come from earlier boot steps. Log
         * each heap's declared bounds -> the first-difference capture. */
        static int hi_n;
        if (hi_n < 12) {
            hi_n++;
            uint32_t st = r[4], en = r[5];
            fprintf(stderr, "[heapinit] #%d start=0x%08X end=0x%08X size=%u caller=0x%08X\n",
                    hi_n, st & ~3u, en & ~3u, (en & ~3u) - (st & ~3u), r[31]);
        }
    }
    if (a == 0x80031A68u || a == 0x80031B10u) {
        uint32_t p = r[4], w0 = 0, w1 = 0, w2 = 0, w3 = 0;
        if (p >= 0x80010000u && p < 0x80200000u) {
            uint32_t b = p - 0x80000000u;
            memcpy(&w0, xenolift_mem + b - 8u, 4);
            memcpy(&w1, xenolift_mem + b - 4u, 4);
            memcpy(&w2, xenolift_mem + b, 4);
            memcpy(&w3, xenolift_mem + b + 4u, 4);
        }
        fprintf(stderr, "[arena] %s ptr=0x%08X w[-2]=%08X w[-1]=%08X w[0]=%08X w[1]=%08X\n",
                a == 0x80031A68u ? "bootmain-install" : "table-install", p, w0, w1, w2, w3);
    }
    if (a == 0x80038B4Cu) { /* R81: loader-task completion teardown —
         * v1=*(0x800595E0)!=0 skips the unregister; a0=*(0x800595A4) is
         * the handler block removed from the irq chain (fn_80039144,
         * walk faulted at chain tail). Log both cells. */
        uint32_t e0, a0c;
        memcpy(&e0, xenolift_mem + 0x595E0, 4);
        memcpy(&a0c, xenolift_mem + 0x595A4, 4);
        fprintf(stderr, "[teardown] fn_80038B4C gate=0x%08X hblock=0x%08X\n", e0, a0c);
    }
    if (a == 0x80031BDCu) { /* kernel allocator: size-class chain walker.
         * R76: frontier = END field of first block (0x8006FAF0) = carve
         * position; class = a1. Ledger shows why #10 failed. */
        static uint32_t ha_n;
        uint32_t fl, fr;
        memcpy(&fl, xenolift_mem + 0x59320, 4);
        memcpy(&fr, xenolift_mem + 0x6FAF0, 4);
        ha_n++;
        if (ha_n <= 40u || (ha_n % 500u) == 0u)
            fprintf(stderr, "[heap] alloc #%u size=%u class=%u frontier=0x%08X r31=0x%08X\n",
                    ha_n, r[4], r[5], fr, r[31]);
    }
    /* R76: fn_80044894 is the display-rect call inside fn_80019D48 with
     * a1 = s2+20, invoked right after the factory. Entry + a1 proves
     * whether fn_80032E88 returned a real buffer (alloc/decompress OK). */
    /* R77: fn_80044764 = 640x480 display-env init (called by SystemError
     * at 0x80019F6C right before its j-self park, and by the boot display
     * step). Log entry + caller to pin which path reached it. */
    if (a == 0x80044764u) {
        static uint32_t di_n;
        di_n++;
        if (di_n <= 8u || (di_n % 100u) == 0u)
            fprintf(stderr, "[dispinit] fn_80044764 call#%u r31=0x%08X\n", di_n, r[31]);
    }
    if (a == 0x80044894u) {
        static uint32_t dr_n;
        dr_n++;
        if (dr_n <= 12u)
            fprintf(stderr, "[disp2] fn_80044894 a0=0x%08X a1=0x%08X -> s2=0x%08X\n",
                    r[4], r[5], r[5] - 20u);
    }
    if (a == 0x80031A30u) { /* heap-init */
        uint32_t fl = xenolift_mem[0x59320] | ((uint32_t)xenolift_mem[0x59321] << 8)
                     | ((uint32_t)xenolift_mem[0x59322] << 16) | ((uint32_t)xenolift_mem[0x59323] << 24);
        fprintf(stderr, "[heap] init entered, freelist=0x%08X r31=0x%08X\n", fl, r[31]);
    }
    if (a == 0x80032E88u) /* alloc+decompress factory */
        fprintf(stderr, "[heap] factory(0x%08X) size=%u\n",
                r[4], xenolift_mem[(r[4]-0x80000000u)] | ((uint32_t)xenolift_mem[(r[4]-0x80000000u)+1] << 8)
                     | ((uint32_t)xenolift_mem[(r[4]-0x80000000u)+2] << 16) | ((uint32_t)xenolift_mem[(r[4]-0x80000000u)+3] << 24));
    if (a == 0x800320E8u && r[4] == 0u && r[31] == 0x80073B9Cu && fin_r20_saved != 0u) { /* R304: FINALE RELEASE HEAL.
         * Movie finale ReleaseHeapBlock(r20) with r20 clobbered to 0 by the stage-2 call.
         * Restore the captured handle so the NATIVE release frees the REAL stage-2 block
         * exactly as on hardware; finale then returns normally, slice loop proceeds w/ 77014=1. */
            static int finfree_n = 4;
            if (finfree_n-- > 0) {
                fprintf(stderr, "[finfree] RESTORE: finale release handle 0 -> %08X (clobbered during fn_801D43B0; native release proceeds)\n", fin_r20_saved);
                r[4] = fin_r20_saved;
            } else xenolift_trap_hook(r[31], r[28]);
        } else if (a == 0x800320E8u && r[4] == 0u) xenolift_trap_hook(r[31], r[28]);
    if (a == 0x80019ACCu) xenolift_boot_trace(r[4]);
    if (a == 0x80019D48u) { fprintf(stderr, "[boot] display-step fn_80019D48 entered\n"); gpu_snapshot(); } /* R126 */

    /* Driver state-walk trace (R74): cell 0x80059550 (u16) is the kernel
     * driver state ("ready" magic 0x90C, checked in fn_80019578 before
     * the main-program load; failure -> error screen -> the trap).
     * Status byte 0x80059388 gates transitions (device status nibble
     * from hardware). Log every change with the running function so
     * the digest names the stall point. */
    {
        static uint16_t st_prev; static uint8_t sb_prev; static int st_n;
        uint16_t st = xenolift_mem[0x59550] | ((uint16_t)xenolift_mem[0x59551] << 8);
        uint8_t  sb = xenolift_mem[0x59388];
        if (st != st_prev) {
            if (st_n < 60 || (st_n % 200) == 0)
                fprintf(stderr, "[state] 0x80059550: %04X -> %04X at fn 0x%08X\n", st_prev, st, a);
            st_prev = st; st_n++;
        }
        if (sb != sb_prev) {
            fprintf(stderr, "[state] status 0x80059388: %02X -> %02X at fn 0x%08X\n", sb_prev, sb, a);
            sb_prev = sb;
        }
        /* R84: boot-critical cells — on-change with the WRITING fn.
         * 0x800593AC/B0: hook fn cells (stubs at 0x80040AEC/B00 jr through
         * them); 0x800595A4: handler block cell (teardown walk arg — stuck
         * at 0 -> search for -16 -> spin); 0x80059410: kernel irq list. */
        {
            static uint32_t hc_prev[81]; static int hc_seen[81]; static int hc_n[81]; /* R587 REVERT to R584-proven 81: R585 90-cell set correlated with 2 dead cycles (crash at first guest insn, zeroed regs, wild fault addr) - read-struct cells moved to a passive tick sampler */ /* R516: FIFTH resize-together miss — R513/R515 grew hc_addr to 78 + loop to 78 but left these at 75: every sweep OOB-wrote hc_prev/seen/n[75..77] = smashed adjacent statics = the c83 kernel-cell corruption (mangled 0x03xxxxxx pointers, irq-chain poison, glyph crash at 31s). Compile-time tripwire below makes #6 impossible. */
            /* R332: resize together — cycle-80 audit found hc_addr at 61 but these at 57 and the loop bound at 57: watchers 57..60 were SILENTLY DEAD (4th occurrence of the resize-together lesson). */ /* R260: 36→44 — R246 grew hc_addr to 44 but left these at 36: k=36..43 (render-struct watchers) wrote OOB, the per-cell 24-line cap never held for them = the movie-phase log FLOOD (2806 [hook] lines / 200KB, cycle-8 =FLOOD=). THIRD occurrence of the resize-together lesson. */ /* R187: R140 lesson — resize decl+init+loop TOGETHER; hc_addr grew to 31 in R186 but these stayed 30 → OOB write at k=30 = the cycle-20 earlier-fault regression */
            /* R128 archive cells: 0x8004FDF0 = FAT base (7-byte entries),
             * 0x8004FDF4 = 16-bit directory table ptr, 0x8004FE14 = ACTIVE
             * ARCHIVE OFFSET (set by SelectArchiveDirectoryEntry = entry-1),
             * 0x8004FE48 = host/debug route gate (nonzero bypasses the FAT) */
            static const uint32_t hc_addr[81] = { /* R515: was [76] with 78 elements — GCC silently DROPPED the last two (0x59F08 R507 + 0x4FDF8 R513 watchers) = dead cameras, the c82 "no FDF8 writer" verdict was a ghost. Lesson: verify ELEMENT COUNT <= declared size, not just the loop bound. */ 0x4FE04u, /* R341: FE04 = the kernel expected-LBA cell — cycle-89 strscan PROVED real STR frames live at LBA 108081+ while the kernel seeks 108593+ (all served sectors NOT-STR = silently rejected). This watcher names the kernel fn that computes the wrong movie stream base. */ 0x69360u, 0x69368u, /* R189.1: the caller-side table cells — the linker (fn_8003342C) gets a0 from s0 which the caller stores here (sw a0,-27808/27800(at) = 0x80069360/68). Our run hands it the heap frontier 0x801FBFF0 instead of the real archive table; these watchers name the writer. */ 0x1FBFF0u, 0x1FBFF4u, /* R189: the relocator count word pair @0x801FBFF0 (the word before the heap terminator node 0x801FBFF8). Cycle-22 decode: fn_8003342C LinkArchiveDirectoryEntries walks count words from a0+4 adding a2 (the base) — on the fault round count=0x1004 walked [0x801FBFF4, 0x80200000] = one word PAST RAM = the 21-cycle crash. Real HW: count=0x1003 fits exactly. Watchers name every writer of this slot. */ 0x593ACu, 0x593B0u, 0x595A4u, 0x59410u,
                0x1FFF28u, 0x1FFF2Cu, 0x1FFFB0u, /* R186: stackclobber — the live
                            * stack slots (sp=0x801FFF28, disp2 base
                            * 0x801FFFB0). The original fault = a jr through
                            * ra restored as 0x80200000 (RAM frontier) = a
                            * return-address slot clobbered by an earlier wild
                            * store. These watchers name the clobberer. */
                0x1FBFF8u, 0x1FBFFCu, /* R184: the ZERO-WIDTH take-chunk
                            * header at 0x801FBFF8 {w0=0x801FC000, w1=0x80200000}
                            * — [hand]/[take] show EVERY alloc takes THIS
                            * sliver (extent=8B) for wants 6596-29048; the
                            * bit-assembly then reads (block-4) = the TAIL of
                            * the prior decompressed stream as metadata and
                            * builds the 0x?xC0CBA5 poison family. Names the
                            * writer: carve-stores (allocator self-loop) vs
                            * decompress-out (game data as metadata). */
                0x59320u, /* R181: HEAP FREE-LIST HEAD (gp+0x1B0, gp=0x80059170).
                            * R180: head read at walk time = 0x8006FAF8 = points
                            * AT THE MODULE BASE (r10 = 0x8006FAF0) — the walker
                            * tours module-land as a chunk ring, flags never
                            * match, alloc fails. Names the writer of the
                            * collision live. */
                0x1F34B8u, /* R171: verdict block +4 — the 0xC2C0CBA5 garbage size
                            * passed to the heap allocator (fn_80031FF8 caller
                            * 0x80031B3C) before the 0xFFFF93D4 crash. Names the
                            * writer live. */
                0x59330u, 0x59340u, 0x59570u,
                0x4FDF0u, 0x4FDF4u, 0x4FE14u, 0x4FE48u,
                /* R129 slot-queue cells: 0x8004FE1C = ACTIVE FILE# cell
                 * (StartArchiveRead writes it — NOT a status flag!), 0x8004FE10
                 * = status, 0x8005A488 = queued-read counter (bumped per
                 * enqueue), 0x800564A8 = cell zeroed inside fn_8004111C */
                0x4FE1Cu, 0x4FE10u, 0x5A488u, 0x564A8u,
                /* R93 sound-heap poison watch: head entry next (0x65B1C),
                 * bogus entry 0x80065B20 {data 0x65B28, next 0x65B2C},
                 * allocator limit cells 0x595E4 / event 0x595BC
                 * (R94 fix: 0x800695xx was WRONG — lui 0x8006 + negative
                 * offsets land in BSS 0x800595xx; limit = base+size set by
                 * SoundHeapInit fn_80038EC0 at 0x80038EE4) */
                0x65B1Cu, 0x65B28u, 0x65B2Cu, 0x595E4u, 0x595BCu,
                /* R140 drive-struct cells (Jos ask 07:23 "what touches
                 * the drive-state"): 0x8005677C = the DRIVE-STATE byte
                 * the collector fn_800415B4 polls (&7 mask, read-twice-
                 * compare until stable, per the R131 kernel disasm) —
                 * a kernel-side cached drive state; 0x80056788 = the
                 * SLOT-BITS byte (r18 in every fd park; the R130 kick
                 * reads it to dispatch h2). Watching = every WRITER
                 * named live in the next digest. */
                0x5677Cu, 0x56788u,
                /* R152 game-state dispatch cells (static decode 16:35):
                 * 0x80018088 = REQUESTED state (CommitGameStateTransition
                 * writes it), 0x8001808C = game descriptor table base
                 * (dispatcher indexes +state*16; disc image shows CODE-like
                 * words there — runtime content UNKNOWN), 0x800280EC =
                 * gdesc[6] cb for state 6 (Movie), 0x800592C0 = CURRENT
                 * state cell (commit compares + Mount sets), 0x800592BC =
                 * pending state-resource cell */
                0x28084u, 0x18088u, 0x2808Cu, 0x280ECu, 0x692C0u, 0x692BCu, 0x4FE04u, 0x4FE1Cu, 0x568C8u /* R237: kernel driver-object ptr cell — the fatal jalr reads *( *(0x800568C8) + 0x10 ) as a function pointer (decoded from disc: lui v0,0x8005; lw v0,0x68c8; lw v0,0x10; jalr). Watcher names who installs/repoints the driver object. */,
                /* R245: the MOVIE POLL cells — MoviePollSkipInput (disc disasm):
                 * 0x800773AC/B4 = the poll's exchange cell (read, saved to 73B4,
                 * read back, restored — an atomic xchg idiom), 0x80076F04/6F08 =
                 * frame counter / frame limit (counter++ each poll; limit reached
                 * = poll exits). The cycle-30 crash = the ORIGINAL R228-era wild
                 * pointer fault INSIDE this poll's call tree (addr 0xB53A8FF8,
                 * libc territory = wild ptr handed to a copy fn). These watchers
                 * name every writer live on the Mac run. */
                0x773ACu, 0x773B4u, 0x6F04u, 0x6F08u,
                /* R246: the MOVIE RENDER STRUCT @0x80077180 — cycle-31 crash:
                 * fn_80044EA4 (GPU dispatch) entered from the movie render path
                 * (r31=0x800767F8) with r4=0x80077180 + transfer size r5=0x8000;
                 * the struct's halfword fields (+0,+2,+8,+0xA,+0xC,+0xE) feed the
                 * VRAM-coord math and the driver method call. Watch the head. */
                0x77180u, 0x77188u, 0x77190u, 0x77198u,
 0x4FE1Cu /* R279: FE1C lives at 0x80050000+(int16)0xFE1C = 0x8004FE1C — R275 read wrong family; sign-extension trap #4 */,
                0x4FE20u /* R280: FE20 = CD setup LADDER STAGE pointer — state-11 sub-dispatch table @0x8001892C (0x80020000+(int16)0x892C); state-7 alt path writes 4; sub-handlers: 1=ReadN(node 0x80059F10) 2,3=cmd9 4=cmd8 5,6=cmdE(node 0x80059F08); ladder parks at stage 3/4 — watcher names the incrementer */,
                0x4FE38u /* R280: FE38 = stream cell read by state-12 handler */,
 0x59F24u /* R281: node 0x80059F18 result area +C — GetTN/GetTD answers should land; zero forever */,
 0x59F28u /* R281: node result +10 */,
 0x59F2Cu /* R281: node result +14 */,
                0x77014u /* R283: MOVIE PLAYBACK STATE countdown — SliceLoopB reads it each pass: ==1 -> real stage-2 movie call (fn_801D4318); >=2 -> decrement + reloop; SkipInput paths set 5; park shows 5->3 drift. Watch who writes it + why it stalls */, 0x704E0u /* R301 CORRECTION: NOT cfg — pad+prologue of ReadStressTestScreen@0x800704E8 (static code); control watcher only */, 0x59EFCu, 0x59F0Cu, 0x59F14u /* R298: read-struct +4/+14/+1C batch cells — cycle-46: +1C 0->1 when movie pair built; boot single-member reads left it 0 = member-2 pending marker */, 0x6A488u, 0x6A494u, 0x6A498u, 0x6A4A8u, 0x6A4B4u,
                /* R332: the state-6/7 happy/fail progress counters. Cycle-78/79
                 * prove the handler fns are ENTERED (XTRACE is their first
                 * statement, probe reads a0=2) yet these cells never move
                 * (except our own assist writes). Either the bodies die between
                 * XTRACE and their SW, or something else writes/zeroes these
                 * cells. These watchers name EVERY writer live. */  /* R386: TRANSITION PIPELINE CAMERA — every write to the state-request/pending/latch/current/idx cells, with writer fn. Cycle-143 window PROVED the handler+commit emit is CORRECT (single fn, internal gotos, direct calls) and r4=1 residue shows the confirm path firing; the open question is only WHO consumes the sentinel. */
    0x692C0u, /* cur-state: -1 sentinel = transition pending */ 0x692BCu, /* pending-resource latch */ 0x18088u, /* requested-state cell */ 0x692D0u, /* post-confirm latch */ 0x6FAECu, /* mount idx-cell (restart step mounts THIS) */ 0xAFC98u, /* R418: staging-buffer head — who refills the module scratch after boot? */ 0x50594u, 0x59394u /* R423 (c180): k74 = font ctx ptr cell - glyph batch ptr = LW(ctx+0x38) read packet data at crash */, 0x50594u /* R422 (c179): font-renderer callback cell — EmitFontCharacter indirect-dispatches LW(0x80050594); at the field crash it holds 0x44602C06 (string garbage) = THE fault. Name the writer. */, 0x59F08u /* R507: field read ready-callback cell — c73: cbheal re-arms 8002B084 but game re-clears each round; name the clear/load writers */, /* R513: FDF8 = the request-length cell. c80: the directory read (member 1) registers with FDF8=0
                 * (its native table size reads -6), so the archive callback has no countdown and never
                 * copies the sector out of the FIFO. Watch every FDF8 writer to find the piece that
                 * writes the REAL length on hardware. */ 0x4FDF8u,
                            0x4FE08u, /* R581: batch/ring dest cell — who ADVANCES it (game copy callback vs DMA)? c149: FDF8 park=2048 = file-14 read stuck one sector short; FE08 pinned F2F8. */
                            0x59F10u /* R581: read-req queue cell — companion to F08(cb)/F0C(file#=14). Dump showed F10=00341424 garbage vs ph2 00591324 — watch its writers. */,
                            0x64ACu /* R582: dispatcher gate — L_80041CB4 reads 0x80064AC; if 0 it SKIPS the callback dispatch (goto 80041CDC). If this stays 0 in the field era while a read is active, the copy callback can never run = file-14 completion deadlock. */
};
            typedef char hc_size_guard_[(sizeof(hc_addr)/sizeof(hc_addr[0]) == sizeof(hc_prev)/sizeof(hc_prev[0]) && sizeof(hc_addr)/sizeof(hc_addr[0]) == sizeof(hc_seen)/sizeof(hc_seen[0]) && sizeof(hc_addr)/sizeof(hc_addr[0]) == sizeof(hc_n)/sizeof(hc_n[0])) ? 1 : -1]; /* R516 static assert (ELEMENT counts, not bytes — first draft compared bytes and self-tripped): the four arrays must resize TOGETHER, else compile ERROR */



            
            if (a == 0x80032F4Cu) { /* R197: LZSS normal-exit chunk (a1 == t7) */
                fprintf(stderr, "[lzss-x] EXIT reached: r5=0x%08X r15(t7)=0x%08X r14(ret-base)=0x%08X r4=0x%08X\n",
                        r[5], r[15], r[14], r[4]);
            }
if (a == 0x80032EB4u) { /* R197: exit-target trace */
                uint32_t orig_r5 = r[5];
                uint32_t dst_final = 0;
                uint32_t w0 = (r[4] < 0x80200000u && r[4] >= 0x80000000u) ? xenolift_mem_read32(r[4]) : 0u;
                lzss_exit_target = (uint32_t)(r[5] + w0); /* R198: remember the correct exit target */
                if (w0 > 0u && w0 <= 0x800000u && r[5] >= 0x80000000u && r[5] + w0 <= 0x80200000u) {
                    /* R200/R201: HLE the decompression natively (verified-
                     * faithful decoder). Four cycles of context-save fixes
                     * (R196/R199) never stopped stream-2's in-loop register
                     * destruction. Instead of protecting the loop, run it
                     * ourselves: produce the exact expanded bytes, then make
                     * the core exit at its FIRST group check.
                     * R201 FIX (cycle-34 taught): the core's entry math
                     * recomputes r15 = LW(r4) + r5 — pre-setting r5/r15 made
                     * it DOUBLE-ADD (r15 = dst+2*w0, r5 = dst+w0) and the
                     * core re-ran a bogus pass over the heap walk metadata
                     * (crash 0x00FE000A). CLEAN TRICK: point r4 at the
                     * archive read-struct's zero word (0x80059EF8 = {0,0,0,0}
                     * per =PARK= dumps, read-only for us) — the core reads
                     * word0=0, computes r15 = 0 + r5, and with r5 pre-set to
                     * the FINAL write position (dst+w0, exactly where a
                     * normal exit leaves it) the first check passes. r14 =
                     * dst = the normal exit return value. No register
                     * conflicts, dst untouched, input stream untouched. */
                    int prod = xenolift_lzss_hle(r[4], r[5], w0);
                    if (prod >= 0 && (uint32_t)prod == w0) {
                        { static int s_dech_n;
        fprintf(stderr, "[dechist] #%d src-arg dst=%08X\n", ++s_dech_n, (unsigned)r[5]); }
        { uint32_t _f0 = xenolift_mem_read32(r[5]), _f1 = xenolift_mem_read32(r[5]+4u);
        fprintf(stderr, "[lzss-hle] src=0x%08X dst=0x%08X expanded=%u decoded natively; one-shot zero-read armed | out-first8: %08X %08X\n",
                                r[4], r[5], w0, _f0, _f1);
        /* R686 [fldcap]: the FIELD-MODULE RELOCATION (c257 proof: staged file-14
         * LZSS @0x801D9724 -> window-0 slot 0x8006FAF0, expanded 260862) runs
         * during the shell-restart's second boot - AFTER the R681 fault-moment
         * capture fires. Re-capture window 0 HERE so the emitter maps the REAL
         * expanded field module (coordinator 0x80077E88 = offset 0x8398 inside
         * it = real field code, not the stale module-2 data island). */
        if (r[4] == 0x801D9724u && r[5] == 0x8006FAF0u && prod > 0) {
            uint32_t _nn = 0; uint32_t _base = 0x8006F000u, _sz = 135168u;
            FILE *_fo = fopen("overlay_fault.bin", "wb");
            unsigned char *_buf = (unsigned char*)malloc(_sz);
            if (_buf && _fo) {
                for (uint32_t _o = 0; _o < _sz; _o += 4u) {
                    uint32_t _w = xenolift_mem_read32(_base + _o);
                    if (_w) _nn++;
                    _buf[_o] = (unsigned char)(_w & 0xFF);
                    _buf[_o+1] = (unsigned char)((_w >> 8) & 0xFF);
                    _buf[_o+2] = (unsigned char)((_w >> 16) & 0xFF);
                    _buf[_o+3] = (unsigned char)((_w >> 24) & 0xFF);
                }
                fwrite(_buf, 1, _sz, _fo);
                fprintf(stderr, "[fldcap] R686 field-module RELOCATED into window 0 - recaptured overlay_fault.bin: %u nonzero words of 33792 (coordinator @+0x8398 should be REAL field code next emit)\n", _nn);
                /* R687 [fldsnap]: c258 verdict - nonzero count UNCHANGED (32604) after
                 * a claimed 260KB write. Either the expanded output == the old module
                 * content (file 14 re-installs the same bytes) or the write landed
                 * elsewhere. Decide by photographing the exact spots the dispatcher
                 * calls, IMMEDIATELY post-decompress: */
                {
                    const uint32_t _spots[4] = {0x80077E88u, 0x800737ECu, 0x8006FAF0u, 0x80073AF0u};
                    const char *_names[4] = {"coord-80077E88", "movie-slot-800737EC", "dst-base-8006FAF0", "dst+0x4000"};
                    for (int _s = 0; _s < 4; _s++) {
                        char _b[9*8+1]; int _q = 0; _b[0] = 0;
                        for (int _i = 0; _i < 8; _i++)
                            _q += sprintf(_b+_q, "%08X ", xenolift_mem_read32(_spots[_s] + 4u*(uint32_t)_i));
                        fprintf(stderr, "[fldsnap] R687 post-decompress %s: %s\n", _names[_s], _b);
                    }
                }
            }
            if (_buf) free(_buf);
            if (_fo) fclose(_fo);
        } }
                        /* R203: cycle-36 taught — the exit chunk derives the
                         * block BASE as r14 = r15 - t6(saved word0) = r15 - 0
                         * (our faked size) = r5. The wrapper returns that
                         * to the install chain, so r5 must BE the base.
                         * (R202 set r5 = dst+w0 = final position -> chain
                         * linked from past-the-end -> count = heap node
                         * -> 2B-entry walk -> RAM trashed.) r5 = base:
                         * entry r15 = 0 + base, first check passes, exit
                         * r14 = base - 0 = base = exactly what a normal
                         * completion hands the installer. */
                        r[5] = orig_r5;
                        r[14] = orig_r5;
                        lzss_hle_src_saved = r[4]; /* R202: r4 untouched; the armer watch sets the one-shot */
                    } else {
                        fprintf(stderr, "[lzss-hle] decode FAILED (prod=%d) — falling back to core loop\n", prod);
                    }
                }
                fprintf(stderr, "[lzss-t] src=0x%08X dst=0x%08X word0=0x%08X computed_exit=0x%08X r15pre=0x%08X\n",
                        r[4], r[5], w0, (uint32_t)(r[5] + w0), r[15]);
            }
            if (a == 0x80032EB4u) { /* R191/R192: LZSS core entry. CYCLE-25
                * CLOSED THE CASE: the game's heap = TOP-DOWN bump from the
                 * RAM ceiling 0x80200000 — carve dst = 0x80200000 - expanded
                 * - 8 (verified EXACT for both streams: 0x801FA634+22988 =
                 * 0x80200000, 0x801F34B4+52044+8 = 0x80200000). The expanded
                 * stream ENDS at the last RAM word; the LZSS (per its own
                 * symbol: no destination capacity, checks only per-group)
                 * writes ONE FINAL PARTIAL GROUP past the end -> 0x80200000
                 * = the 25-cycle halt. R192 lzss-guard: arm at entry; the
                 * write funnels suppress any >= 0x80200000 access while
                 * armed — the LZSS completes its real output, the overrun
                 * tail is dropped, and the boot round SURVIVES. */
                static int lz_n;
                lzss_armed = 1; lzss_over_n = 0; /* R192/R194: guard armed, counter reset per decompression */
                lzss_in_end = r[4] + xenolift_mem_read32(r[4]); /* R195: input fence = src + stream word0 (declared compressed length) */
                lzss_heal_n = 0;
                lzss_inpast_n = 0;
                if (lz_n < 12) {
                    lz_n++;
                    fprintf(stderr, "[lzss] #%d src(r4)=0x%08X dst(r5)=0x%08X ctl(r6)=0x%08X r17=0x%08X first16@src=%08X %08X %08X %08X ctlblk@r17=%08X %08X %08X %08X\n",
                            lz_n, r[4], r[5], r[6], r[17],
                            (r[4] < 0x80200000u) ? xenolift_mem_read32(r[4]) : 0xDEAD0011u,
                            (r[4] + 4 < 0x80200000u) ? xenolift_mem_read32(r[4] + 4) : 0xDEAD0012u,
                            (r[4] + 8 < 0x80200000u) ? xenolift_mem_read32(r[4] + 8) : 0xDEAD0013u,
                            (r[4] + 12 < 0x80200000u) ? xenolift_mem_read32(r[4] + 12) : 0xDEAD0014u,
                            (r[17] && r[17] + 12 < 0x80200000u && r[17] >= 0x80000000u) ? xenolift_mem_read32(r[17]) : 0xDEAD0021u,
                            (r[17] && r[17] + 12 < 0x80200000u && r[17] >= 0x80000000u) ? xenolift_mem_read32(r[17] + 4) : 0xDEAD0022u,
                            (r[17] && r[17] + 12 < 0x80200000u && r[17] >= 0x80000000u) ? xenolift_mem_read32(r[17] + 8) : 0xDEAD0023u,
                            (r[17] && r[17] + 12 < 0x80200000u && r[17] >= 0x80000000u) ? xenolift_mem_read32(r[17] + 12) : 0xDEAD0024u);
                }
            }
                /* R418 (c175) FIELD-DECOMPRESS FINGERPRINT AT THE SHARED LZSS
                 * LOOP ENTRY: the R416 hook sat on the 0x80032E88 wrapper —
                 * it logged ONLY the boot calls (#0 t=0s proved it); the
                 * field module's crash-time decompress reaches this loop
                 * through a DIFFERENT wrapper and was never fingerprinted.
                 * c175 evidence: field call reads src=0x800AFC98 whose
                 * bytes are byte-identical to the boot-era module-6 stream
                 * (word0=0x7178=29048 = ITS length) — the staging buffer
                 * appears to still hold the STALE BOOT ARCHIVE, and no disc
                 * file is 29048 bytes, so the input the field module expects
                 * (file 2's 29048 bytes) was never staged. This probe rides
                 * the loop entry so EVERY caller is fingerprinted: src crc
                 * + staging-vs-disc when src==0x800AFC98 (is it file 2's
                 * disc bytes or stale?) + caller r31 + elapsed time. The
                 * R418 staging-buffer write-watcher (0xAFC98 cell) answers
                 * the other half: did ANYONE try to refill the scratch? */
                if (r[4] >= 0x80000000u && r[4] < 0x80200000u) {
                    uint32_t r418_len = xenolift_mem_read32(r[4]);
                    long r418_el = (long)(time(NULL) - g_boot_wall_t0);
                    /* R419 BUDGET-ERA FIX (c176): c176's 16-line budget was
                     * eaten by 16 BOOT calls at t=0-1s (#0..#15) — the field
                     * call at t~150s NEVER fingerprinted. 4th occurrence of
                     * the era-budget lesson. Gate: only t>30s fires (boot
                     * decompresses are all t<=1s per c176 timestamps). */
                    if (r[4] == 0x800AFC98u && r418_len >= 0x1000u && r418_len <= 0x10000u && r418_el > 30 && r418_el < 300) { /* R420 (c177): src gate — menu-glyph caller (src=0x801FFFCE) flooded the t>30 gate at t=31s; only the module scratch matters */
                        static int r418_n;
                        if (r418_n < 16) {
                            uint32_t r418_off = r[4] - 0x80000000u;
                            uint32_t r418_crc = 2166136261u;
                            for (uint32_t i = 0; i < r418_len && r418_off + i < 0x200000u; i++)
                                r418_crc = (r418_crc ^ (uint32_t)xenolift_mem[r418_off + i]) * 16777619u;
                            const char *r418_stg = "n/a"; uint32_t r418_fd = 0;
                            if (r[4] == 0x800AFC98u) {
                                r418_stg = "MATCH";
                                unsigned char r418_sb[2048];
                                uint32_t r418_so = 0;
                                for (uint32_t r418_lba = 108979u; r418_lba <= 108994u; r418_lba++) {
                                    if (disc_read_lba(r418_lba, r418_sb) != 0) { r418_stg = "disc-err"; break; }
                                    for (uint32_t r418_k = 0; r418_k < 2048u; r418_k++) {
                                        if (r418_so + r418_k >= 29048u) break;
                                        if (xenolift_mem[r418_off + r418_so + r418_k] != r418_sb[r418_k]) {
                                            r418_stg = "DIFF"; r418_fd = r418_so + r418_k; break;
                                        }
                                    }
                                    if (r418_stg[0] == 'D') break;
                                    r418_so += 2048u;
                                }
                            }
                            fprintf(stderr, "[fld-dec2] #%d t=%lds caller=%08X src=%08X len=%u srccrc=%08X staging-vs-disc=%s@%u\n",
                                    r418_n, (long)(time(NULL) - g_boot_wall_t0), r[31], r[4], r418_len, r418_crc, r418_stg, r418_fd);
                            r418_n++;
                        }
                    }
                }
            if (a == 0x80032EB4u && lzss_hle_src_saved) {
                /* R202: arm the one-shot zero-read LAST (after the R191
                 * trace's own src reads) — the core's very next LW(src)
                 * returns 0, so r15 = 0 + r5 == r5 -> first-check exit. */
                lzss_fake_zero_addr = lzss_hle_src_saved;
                lzss_hle_src_saved = 0;
            }
            if (a == 0x8003342Cu) { /* R189/R190: LinkArchiveDirectoryEntries —
                 * the table linker: walks count=LW(a0) words from a0+4 adding
                 * a2 (the rebase delta) to each. CYCLE-23 MAC DATA: a0=0x801F34B4
                 * count=0x35 entries=small-offsets = all CORRECT; a2 = 0x00C00000
                 * / 0xC6C0CBA5 = TAG-MATH POISON from the alloc chain (fn_800320A4
                 * leaves r6 = tag instead of a base). The poisoned rebase writes
                 * non-addresses into the link table -> next round's decompress
                 * headers garble -> LZSS walks past RAM top -> the 0x80200000
                 * halt. R190 [reloc-fix]: the entries are offsets-from-block
                 * (0xDC/0x16C/0x23C vs block 0x801F34B4 = self-referential link
                 * table), so the correct delta = the block base = a0. When a2
                 * is not a valid RAM pointer, substitute a0 and log loudly. */
                static int rel_n;
                if (r[6] != 0 && (r[6] < 0x80000000u || r[6] >= 0x80200000u)) {
                    if (rel_n < 24) {
                        rel_n++;
                        fprintf(stderr, "[reloc-fix] #%d POISON DELTA a2=0x%08X (tag-math) -> substituting block base a0=0x%08X count=0x%08X\n",
                                rel_n, r[6], r[4],
                                (r[4] >= 0x80000000u && r[4] < 0x80200000u) ? xenolift_mem_read32(r[4]) : 0xDEAD0001u);
                    }
                    r[6] = r[4]; /* HLE correction: rebase by the block base */
                } else if (rel_n < 24) {
                    rel_n++;
                    fprintf(stderr, "[reloc] a0=0x%08X a2=0x%08X count=0x%08X w[0..3]=%08X %08X %08X %08X\n",
                            r[4], r[6],
                            (r[4] >= 0x80000000u && r[4] < 0x80200000u) ? xenolift_mem_read32(r[4]) : 0xDEAD0001u,
                            (r[4] + 4 < 0x80200000u) ? xenolift_mem_read32(r[4] + 4) : 0xDEAD0002u,
                            (r[4] + 8 < 0x80200000u) ? xenolift_mem_read32(r[4] + 8) : 0xDEAD0003u,
                            (r[4] + 12 < 0x80200000u) ? xenolift_mem_read32(r[4] + 12) : 0xDEAD0004u);
                }
            }
            /* R677: loop28088 write-watcher - exitdiag prints 0x80028088 at
             * every clean return (c248: A7A00032). R666 ledger says it is the
             * resident-loop req-state cell (Field era = 1, aborts when 0);
             * R668 said era-specific. Name every writer + old->new. */
            {
                static uint32_t lw_prev; static int lw_seen, lw_n;
                uint32_t lw_v; memcpy(&lw_v, xenolift_mem + (0x80028088u - 0x80000000u), 4);
                if (!lw_seen || lw_v != lw_prev) {
                    if (lw_n < 40) {
                        lw_n++;
                        fprintf(stderr, "[loopw] R677 0x80028088: %08X -> %08X at fn 0x%08X r31=%08X @t=%lds\n",
                                lw_prev, lw_v, (unsigned)xenolift_cur_fn,
                                (unsigned)r[31], (long)(time(NULL) - g_boot_wall_t0));
                    }
                    lw_prev = lw_v; lw_seen = 1;
                }
            }
            int k;
            for (k = 0; k < 81; k++) { /* R587: 90 -> 81 WITH the array revert (R513/R516 lesson: bound must grow/shrink WITH the array - loop 90 + array 81 = OOB read of garbage addresses + OOB write of hc_prev/seen/n) */ /* R513: 75 -> 76 (FDF8 watcher added) */ /* R423: k74 = font ctx ptr cell 0x80059394 */ /* R332: bound grows WITH the array (was 57 while hc_addr held 61 = 4 dead watchers) — R186 added
                         * 3 stackclobber watchers but left the bound at 30,
                         * silently killing the 0x1FFFB0 (disp2 working cell)
                         * watcher — the prime clobber target. */
                uint32_t v; memcpy(&v, xenolift_mem + hc_addr[k], 4);
                if (!hc_seen[k] || v != hc_prev[k]) {
                    /* R333: the FE1C/FE20/counter watchers exhausted their
                     * 24-line budgets during BOOT, so movie-era writes were
                     * never logged = the 3-cycle "handler bodies never write"
                     * GHOST was dead cameras, not dead bodies. Movie-era cells
                     * get a 240-line budget; boot cells keep 24 (digest size). */
                    int hc_cap = (k == 0 || k == 22 || k == 51 || k >= 61) ? 240 : 24; /* R585: k81-89 = read-struct cells — 240 via >=61 */ /* R386: k67-71 = transition pipeline, 240 */ /* R342: k0=FE04 watcher — 24-line budget died during boot file-loads, silent for the movie era */
                    if (hc_n[k] < hc_cap)
                        fprintf(stderr, "[hook] 0x%08X: %08X -> %08X at fn 0x%08X\n",
                                0x80000000u + hc_addr[k], hc_prev[k], v, a);
                    hc_prev[k] = v; hc_seen[k] = 1; hc_n[k]++;
                }
            }
            {   /* R243 [spguard]/[task]: THE MOVIE SP-POISON ROOT. Disc scan
             * found 5 lw-sp sites; 0x8004BE94 = `lw sp,4(a0)` inside the
             * kernel TASK-SWITCH (the 0x8004B54C entry the R229 sp-strip
             * catches) loads the next task's sp from its task struct. That
             * field is corrupted in our run (0x800568E0-class, kernel data)
             * so every movie-chain push `sw X,16(sp)` writes INTO kernel
             * static cells (fn_80044EA4's prologue = the drv-cell clobber
             * instruction). GUARD: a sp parked in kernel .data
             * [0x80056000,0x8005A000) can never be a real stack -> restore
             * last-good sp (tracked while sp is in the legit stack window)
             * and log. PROBE: dump the task-switch args live (budget 12). */
                static int sg_n = 0; static int task_n = 0;
                uint32_t sg_sp = r[29];
                if (sg_sp >= 0x801F0000u && sg_sp <= 0x80200000u) xenolift_last_good_sp = sg_sp;
                else if (sg_sp >= 0x80056000u && sg_sp < 0x8005A000u) {
                    r[29] = xenolift_last_good_sp;
                    if (sg_n < 16) {
                        fprintf(stderr, "[spguard] sp 0x%08X in kernel-data at fn 0x%08X -> restored 0x%08X\n",
                                sg_sp, a, xenolift_last_good_sp);
                        sg_n++;
                    }
                }
                if (a == 0x8004B54Cu && task_n < 12) {
                    task_n++;
                    uint32_t ta = r[4];
                    if (ta >= 0x80000000u && ta < 0x80000000u + XENOLIFT_RAM_SIZE - 8) {
                        uint32_t tsp = (uint32_t)xenolift_mem[(ta-0x80000000u)+4]
                            | ((uint32_t)xenolift_mem[(ta-0x80000000u)+5] << 8)
                            | ((uint32_t)xenolift_mem[(ta-0x80000000u)+6] << 16)
                            | ((uint32_t)xenolift_mem[(ta-0x80000000u)+7] << 24);
                        fprintf(stderr, "[task] switch fn_8004B54C a0=0x%08X tasksp=0x%08X sp=0x%08X\n",
                                ta, tsp, sg_sp);
                    } else {
                        fprintf(stderr, "[task] switch fn_8004B54C a0=0x%08X (not a struct ptr) sp=0x%08X\n", ta, sg_sp);
                    }
                }
            }
            {   /* R242 (moved): R241 wired the heal into the if-changed branch = fired only when a WATCHED cell changed (sandbox coincidence); the Mac run never hit it after the last watcher change. NOW UNCONDITIONAL at every dispatch entry [drvptr-heal]: THREE kernel driver cells
             * (0x800568C4/C8/CC) ship from disc static data and NO EXE
             * code EVER stores to any of them (full-text scan proof) — on
             * hardware they hold the disc values forever. Cycle-26 caught a
             * poison-family store clobbering 0x800568C8 to 7/GARBAGE, which
             * killed the movie video path's jalr *(drv+0x10). Enforcing the
             * disc invariant is hardware-faithful: every violation is
             * logged with the offending function and HEALED.
             * Plus: boot-baseline snapshot of the kernel data window for
             * the halt-time static-diff (names every clobbered neighbor). */
                static const uint32_t dp_addr[3] = { 0x568C4u, 0x568C8u, 0x568CCu };
                static const uint32_t dp_good[3] = { 0x80046DB4u, 0x80056888u, 0x80019964u };
                /* snapshot buffers at file scope: xenolift_dp_base */
                static int dp_heal_n = 0;
                for (int q = 0; q < 3; q++) {
                    uint32_t v = (uint32_t)xenolift_mem[dp_addr[q]]
                        | ((uint32_t)xenolift_mem[dp_addr[q]+1] << 8)
                        | ((uint32_t)xenolift_mem[dp_addr[q]+2] << 16)
                        | ((uint32_t)xenolift_mem[dp_addr[q]+3] << 24);
                    if (v != dp_good[q]) {
                        xenolift_mem[dp_addr[q]]   = (uint8_t)(dp_good[q]);
                        xenolift_mem[dp_addr[q]+1] = (uint8_t)(dp_good[q] >> 8);
                        xenolift_mem[dp_addr[q]+2] = (uint8_t)(dp_good[q] >> 16);
                        xenolift_mem[dp_addr[q]+3] = (uint8_t)(dp_good[q] >> 24);
                        if (dp_heal_n < 16) {
                            fprintf(stderr, "[drvptr-heal] 0x%08X: 0x%08X -> 0x%08X at fn 0x%08X (r31=0x%08X r16=0x%08X r17=0x%08X)\n",
                                    0x80000000u + dp_addr[q], v, dp_good[q], a, r[31], r[16], r[17]);
                            dp_heal_n++;
                        }
                    }
                }
                if (xenolift_dp_snap == 0 && a == 0x80019524u) {
                    memcpy(xenolift_dp_base, xenolift_mem + 0x56400, 0x1C00);
                    xenolift_dp_snap = 1;
                    fprintf(stderr, "[drvptr] boot baseline snapshotted @fn_80019524\n");
                    if (g_stack_base == 0) {
                        volatile int sb_local = 0; /* R320: real stack address — a static's address is data-segment, not stack! */
                        g_stack_base = (uintptr_t)&sb_local; /* kernel-entry stack base */
                        fprintf(stderr, "[depth] stack base captured @0x%llX (R320 recursion guard armed)\n",
                                (unsigned long long)g_stack_base);
                    }
                }
            }

        }
        /* R86: pad handshake settle steps. The boot check passes when
         * state==0x90C, then loops `while(state==0x90C) fn_80035CDC()`
         * processing the pad command queue. After 64 steps we flip
         * the pad to its identified state and write the state cell
         * directly (the walker runs from kick context, not here). */
        if (a == 0x80035CDCu) {
            static int pad_settle_calls;
            if (++pad_settle_calls == 64) {
                g_pad_phase = 1;
                { uint16_t st = 0xBEA5u; memcpy(xenolift_mem + 0x59570u, &st, 2); }
                pad_fill();
                fprintf(stderr, "[pad] settle handshake done (64 steps) — state 0x90C -> 0xBEA5\n");
            }
        }
        /* R79: irq-chain head cell 0x80059410 — walk faulted at
         * 0x8F5A0014 (= head_chain+12). Who builds/poisons this list? */
        {
            static uint32_t ic_prev; static int ic_n; static uint32_t scan_n;
            uint32_t ic;
            memcpy(&ic, xenolift_mem + 0x59410, 4);
            if (ic != ic_prev) {
                if (ic_n < 60)
                    fprintf(stderr, "[irqc] 0x80059410: %08X -> %08X at fn 0x%08X\n", ic_prev, ic, a);
                ic_prev = ic; ic_n++;
            }
            /* R80: chain-health scan every 256 dispatches — walk up to
             * 16 entries; the FIRST out-of-RAM entry names the poison
             * with the running function (the writer). */
            if ((++scan_n & 0xFFu) == 0u && ic >= 0x80000000u && ic < 0x80200000u) {
                uint32_t q = ic; int i;
                for (i = 0; i < 16; i++) {
                    uint32_t nx;
                    if (q < 0x80000000u || q >= 0x80200000u) {
                        if (ic_n < 200)
                            fprintf(stderr, "[irqc] POISON entry 0x%08X at pos %d, chain from 0x%08X, running fn 0x%08X\n", q, i, ic, a);
                        break;
                    }
                    memcpy(&nx, xenolift_mem + (q - 0x80000000u) + 12, 4);
                    if (nx == 0u) break;
                    q = nx;
                }
            }
        }
        if (a == 0x80019D48u)
            fprintf(stderr, "[dispstep] display-step fn_80019D48 (normal path) r31=0x%08X\n", r[31]);
    }

    /* Boot state-machine trace (R70): the kernel drives boot through a
     * 16-byte-entry table at 0x8001808C (idx cell 0x80018088, walker
     * flag / phase cells 0x800592BC / 0x800592C0, setter fn_8001996C,
     * driver fn_80019ACC). The FILE's entry 0 callback is fn_8001A4B4,
     * but the parked crash goes to fn_80019EF8 (SystemError) — so at
     * runtime the table differs from the file image (built by a path
     * the R69 write-watch could not see). Trace the machine: who sets
     * which phase, and which phase's callback is SystemError. */
    /* R72: decompress+heap trace — boot driver fn_80019D48 does
     * s2 = fn_80032E88(0x8005EABC,1): fn_80032E88 = LZ decompressor
     * (len = *(src) first word; output buffer from heap fn_80031BDC).
     * NULL return -> trap 0x83 (callsite 0x80019ED4) -> SystemError.
     * Log src/len/bytes to decide: bad data (load never arrived) vs
     * heap exhaustion (sane request, no space). */
    if (a == 0x80032E88u) {
        uint32_t src = r[4];
        uint32_t len = 0; char hex[49]; int p = 0;
        hex[0] = 0;
        if (src >= 0x80010000u && src < 0x80200000u) {
            uint32_t off = src - 0x80000000u;
            len = xenolift_mem[off] | ((uint32_t)xenolift_mem[off+1] << 8)
                | ((uint32_t)xenolift_mem[off+2] << 16) | ((uint32_t)xenolift_mem[off+3] << 24);
            for (int i = 0; i < 16; i++) p += sprintf(hex + p, "%02X", xenolift_mem[off + i]);
        }
        fprintf(stderr, "[dec] decompress src=0x%08X len=%u first16=%s\n", src, len, hex);
        /* R416 FIELD-DECOMPRESS DIAGNOSIS (c173): both field data files
         * COMPLETED and the field module STARTED EXECUTING — first field-
         * era crash: decompress(src=0x800AFC9D, end=+29048) walked past
         * its input end ([lzss-inpast]), garbage output, downstream draw
         * call dereferenced 0x44602C06 -> HALT. Suspicion: the staging
         * buffer at 0x800AFC98 held byte-identical content to the boot-
         * era stream 1 (same 29048 len) — did file 2's bytes ever get
         * staged there, or is the delivered data itself wrong? Finger-
         * print every large decompress call (boot stream 1 included as
         * baseline) AND verify the delivered file-2 ring 0x801EABD8
         * against the DISC (LBA 108979-108994 payloads, 29048 bytes).
         * Diagnosis before fixes — no control-flow changes this ship. */
        /* R417 (c174): the single c174 [fld-dec] line was ambiguous
         * (boot stream-1 calls and the field call share src+len) — every
         * line now carries call index + elapsed seconds. NEW VERIFIES:
         * (a) staging buffer 0x800AFC98 vs DISC file-2 payloads (LBA
         * 108979-108994, 29048B) — if the field module staged file 2
         * correctly, staging == disc and the decompress PARAMS are the
         * suspect; if staging still holds the boot archive, the stage
         * copy never happened. (b) ctlblk 0x800A49E8 (file#4 data, LBA
         * 108861) vs its disc payload — the field decompress control
         * block; garbage there = runaway walk. Diagnosis only. */
        if (src >= 0x80010000u && src < 0x80200000u && len >= 0x2000u && len <= 0x10000u) {
            static int r416_n;
            if (r416_n < 8) {
                uint32_t off = src - 0x80000000u;
                uint32_t crc_in = 2166136261u;
                for (uint32_t i = 0; i < len; i++)
                    crc_in = (crc_in ^ (uint32_t)xenolift_mem[off + i]) * 16777619u;
                uint32_t ring = 0x801EABD8u - 0x80000000u;
                uint32_t crc_ring = 2166136261u;
                for (uint32_t i = 0; i < 29048u; i++)
                    crc_ring = (crc_ring ^ (uint32_t)xenolift_mem[ring + i]) * 16777619u;
                unsigned char sbuf[2048];
                uint32_t mmatch = 0xFFFFFFFFu, disc_off = 0u;
                for (uint32_t lba = 108979u; lba <= 108994u && disc_off < 29048u; lba++) {
                    if (disc_read_lba(lba, sbuf) != 0) break;
                    for (uint32_t k = 0; k < 2048u && (disc_off + k) < 29048u; k++) {
                        if (mmatch == 0xFFFFFFFFu
                            && xenolift_mem[ring + disc_off + k] != sbuf[k])
                            mmatch = disc_off + k;
                    }
                    disc_off += 2048u;
                }
                uint32_t stg = 0x800AFC98u - 0x80000000u;
                uint32_t fd_stg = 0xFFFFFFFFu;
                disc_off = 0u;
                for (uint32_t lba = 108979u; lba <= 108994u && disc_off < 29048u; lba++) {
                    if (disc_read_lba(lba, sbuf) != 0) break;
                    for (uint32_t k = 0; k < 2048u && (disc_off + k) < 29048u; k++) {
                        if (fd_stg == 0xFFFFFFFFu
                            && xenolift_mem[stg + disc_off + k] != sbuf[k])
                            fd_stg = disc_off + k;
                    }
                    disc_off += 2048u;
                }
                uint32_t ctl = 0x800A49E8u - 0x80000000u;
                uint32_t fd_ctl = 0xFFFFFFFFu;
                if (disc_read_lba(108861u, sbuf) == 0) {
                    for (uint32_t k = 0; k < 16u; k++)
                        if (xenolift_mem[ctl + k] != sbuf[k]) { fd_ctl = k; break; }
                }
                long el = (long)(time(NULL) - g_boot_wall_t0);
                fprintf(stderr, "[fld-dec] #%d t=%lds src=%08X len=%u srccrc=%08X ringcrc=%08X ring-vs-disc=%s@%u staging-vs-disc=%s@%u ctlblk-vs-disc=%s@%u first4w=%08X %08X %08X %08X\n",
                        r416_n, el, src, len, crc_in, crc_ring,
                        (mmatch == 0xFFFFFFFFu) ? "MATCH" : "DIFF",
                        (mmatch == 0xFFFFFFFFu) ? 0u : mmatch,
                        (fd_stg == 0xFFFFFFFFu) ? "MATCH" : "DIFF",
                        (fd_stg == 0xFFFFFFFFu) ? 0u : fd_stg,
                        (fd_ctl == 0xFFFFFFFFu) ? "MATCH" : "DIFF",
                        (fd_ctl == 0xFFFFFFFFu) ? 0u : fd_ctl,
                        (uint32_t)xenolift_mem[off] | ((uint32_t)xenolift_mem[off+1] << 8)
                            | ((uint32_t)xenolift_mem[off+2] << 16) | ((uint32_t)xenolift_mem[off+3] << 24),
                        (uint32_t)xenolift_mem[off+4] | ((uint32_t)xenolift_mem[off+5] << 8)
                            | ((uint32_t)xenolift_mem[off+6] << 16) | ((uint32_t)xenolift_mem[off+7] << 24),
                        (uint32_t)xenolift_mem[off+8] | ((uint32_t)xenolift_mem[off+9] << 8)
                            | ((uint32_t)xenolift_mem[off+10] << 16) | ((uint32_t)xenolift_mem[off+11] << 24),
                        (uint32_t)xenolift_mem[off+12] | ((uint32_t)xenolift_mem[off+13] << 8)
                            | ((uint32_t)xenolift_mem[off+14] << 16) | ((uint32_t)xenolift_mem[off+15] << 24));
                r416_n++;
            }
        }
        /* R172: FULL INPUT CAPTURE. Cycle-7 decode: the free-list walker
         * (0x80031D9C: next = LW(node+0) - 8) chased a poisoned pointer
         * 0xC2C0CBA5 that our decompressor's output planted at verdict-block
         * +4 (0x801F34B8). On real HW the same walk works -> our emulated
         * decompress must be producing different bytes. Capture the raw
         * compressed input (cap 64KB) so a Python reference LZSS decode can
         * diff against the runtime's output dump next cycle. */
        if (src >= 0x80010000u && src < 0x80200000u && len <= 0x10000u) {
            uint32_t off = src - 0x80000000u;
            char ipath[64]; int nn = 0;
            static int dec_in_n;
            if (dec_in_n < 8) {
                nn = dec_in_n++;
                snprintf(ipath, sizeof ipath, "dec_input_%d.bin", nn);
                FILE *df = fopen(ipath, "wb");
                if (df) { fwrite(xenolift_mem + off, 1, len ? len : 16, df); fclose(df);
                    fprintf(stderr, "[dec] input capture -> dec_input_%d.bin (%u bytes)\n", nn, len ? len : 16); }
            }
        }
    }
    /* R114: the decompress VERDICT. fn_800197EC's install path:
     * fn_80032E88(s5,1) returns v0 -> fn_800335F4(v0): v0==0 ->
     * fn_800324B8(0x20) failure report -> the state machine bounces
     * back to the decompress stage and retries forever (the Mac
     * R107-R113 installer loop, ~1000 cycles/watchdog). v0!=0 -> the
     * real install continues (fn_800320A4 -> cells 0x80069360/68 ->
     * fn_8003342C). Log the verdict at the install call and the
     * fn_800324B8 status codes (0x31 pre-read, 0x20 decompress-fail). */
    if (a == 0x800335F4u) {
        fprintf(stderr, "[ins] install call: decompress verdict=0x%08X (%s)\n",
                r[4], r[4] == 0u ? "FAIL -> bounce" : "ok");
        /* R116: OVERLAY CAPTURE. The installer decompresses a runtime
         * code module (the overlay) to a work buffer and the kernel
         * later JUMPS INTO IT — statically-recompiled code can't run
         * runtime-loaded bytes (the 0x80200000 wild-jump class, the
         * Mac R107-R115 ~1000x boot-restart loop: install -> launch
         * state 0x80077C5C -> restart). Capture the module so it can
         * be emitted+recompiled natively: dump the decompressed
         * buffer at every successful install. */
        if (r[4] != 0u)
            xenolift_ovl_dump(r[4], "verdict-dest");
    }
    /* R116: the overlay launch state + boot-main restarts. The state
     * advancer fn_80031C58 receives a0=0x80077C5C (the overlay launch
     * state, called from fn_80019A2C's region at 0x80019A54) each
     * cycle before the boot restarts (early chain caller 0x80019690).
     * Trace both. */
    /* R121: the phase callbacks are OVERLAY CODE, now compiled native
     * (R120 mapped the captured module at 0x80070000). Without these
     * hooks we are blind to whether the overlay actually runs. */
    if (a == 0x800737ECu || a == 0x80077E88u || a == 0x80070CFCu
        || a == 0x80088E90u || a == 0x80077C5Cu)
        fprintf(stderr, "[ovlcb] overlay fn 0x%08X entered: a0=0x%08X a1=0x%08X a2=0x%08X a3=0x%08X caller=0x%08X\n",
                a, r[4], r[5], r[6], r[7], r[31]);
    /* R121: module file reads — the table manifest says files 13-18
     * (0xD-0x12). Watch fn_800295D8(file#) to see if the module files
     * are ever read from disc. */
    if (a == 0x800295D8u && r[4] >= 1u && r[4] < 64u) {
        fprintf(stderr, "[ovlread] module file read: file#=%u a1=0x%08X caller=0x%08X\n",
                r[4], r[5], r[31]);
        if (r[4] < 64u) { /* R490: record file#->dest + file#->disc-LBA */
            s_ovl_dest[r[4]] = r[5];
            uint32_t fb = xenolift_mem_read32(0x8004FDF0u);
            uint32_t fo = xenolift_mem_read32(0x8004FE14u);
            uint32_t fp = (fb + (r[4] + fo - 1u) * 7u) & 0x1FFFFFFFu;
            if (fb >= 0x80000000u && fp + 7u <= XENOLIFT_RAM_SIZE) {
                const uint8_t *fe = xenolift_mem + fp;
                s_ovl_lba[r[4]] = fe[0] | (fe[1] << 8) | (fe[2] << 16);
                s_ovl_size[r[4]] = fe[3] | (fe[4] << 8) | (fe[5] << 16) | ((uint32_t)fe[6] << 24); /* R491: bytes[3..6] = size 32-bit LE */
            }
        }
        /* R479: this a1 IS the file's destination buffer (HAND probes
         * confirm: file2->0x8006FAF8, 3->0x8007EBF0, 4->0x800A49E8,
         * 5->0x800AA6B0). Snapshot it + the seek so the rescue knows
         * where to carry the bytes. New file announced = reset size
         * tracker (max FDF8 for THIS file). */
        r479_dest = r[5]; r479_seek0 = cd_seek_lba;
        r479_max = 0u; r479_valid = 1;
        /* R127: decode the file-table entry the kernel will consult.
         * fn_80028738/fn_800289D0: idx = file# + *(0x8004FE14) - 1;
         * entry = *(0x8004FDF0) + idx*7; bytes[0..2] = LBA (24-bit LE),
         * bytes[3..6] = size (32-bit LE). fn_800295D8 returns -3 without
         * issuing a read when size <= 0. 0x8004FE48 != 0 selects the
         * alloc/wait path (0x8004C318/48) before the table lookup. */
        static int ftab_budget = 24;
        if (ftab_budget-- > 0) {
            uint32_t base = xenolift_mem_read32(0x8004FDF0u);
            uint32_t off  = xenolift_mem_read32(0x8004FE14u);
            uint32_t gate = xenolift_mem_read32(0x8004FE48u);
            uint32_t idx  = r[4] + off - 1u;
            uint32_t ent  = base + idx * 7u;
            uint32_t p    = ent & 0x1FFFFFFFu;
            if (base >= 0x80000000u && p + 7u <= XENOLIFT_RAM_SIZE) {
                const uint8_t *e = xenolift_mem + p;
                uint32_t lba  = e[0] | (e[1] << 8) | (e[2] << 16);
                uint32_t size = e[3] | (e[4] << 8) | (e[5] << 16) | ((uint32_t)e[6] << 24);
                fprintf(stderr, "[ftab] file#=%u base=0x%08X off=%u gate48=0x%08X entry=0x%08X bytes=%02X%02X%02X%02X%02X%02X%02X -> LBA=%u size=%u%s\n",
                        r[4], base, off, gate, ent, e[0], e[1], e[2], e[3], e[4], e[5], e[6],
                        lba, size, (int32_t)size <= 0 ? "  <== SIZE GATE FAILS (-3, read never issued)" : "");
            } else {
                fprintf(stderr, "[ftab] file#=%u base=0x%08X off=%u gate48=0x%08X -> table pointer INVALID\n",
                        r[4], base, off, gate);
            }
        }
    }
    /* R127: the gates after the size check — did the read ever get issued? */
    if (a == 0x800295D8u && r[4] >= 12 && r[4] < 64) {
        /* R128: one-shot FAT neighborhood dump — entries 12..21 with the
         * CURRENT archive offset applied. Negative sizes = DIRECTORY
         * MARKERS (they declare following-record counts, not file sizes);
         * MeasureArchivePayload returns them as-is and
         * ReadArchiveMemberIntoBuffer bails -3 on size <= 0. */
        static int ftab_neigh = 1;
        if (ftab_neigh-- > 0) {
            uint32_t base = xenolift_mem_read32(0x8004FDF0u);
            uint32_t off  = xenolift_mem_read32(0x8004FE14u);
            fprintf(stderr, "[ftab] FAT neighborhood (base=0x%08X off=%u)\n", base, off);
            for (uint32_t fi = 1u; fi <= 18u; fi++) {
                uint32_t idx2 = fi + off - 1u;
                uint32_t p2 = (base + idx2 * 7u) & 0x1FFFFFFFu;
                if (base >= 0x80000000u && p2 + 7u <= XENOLIFT_RAM_SIZE) {
                    const uint8_t *e = xenolift_mem + p2;
                    uint32_t lba2 = e[0] | (e[1] << 8) | (e[2] << 16);
                    int32_t sz2 = (int32_t)(e[3] | (e[4] << 8) | (e[5] << 16) | ((uint32_t)e[6] << 24));
                    fprintf(stderr, "[ftab] file#=%u: LBA=%u size=%d%s\n",
                            fi, lba2, sz2, sz2 < 0 ? "  <== DIRECTORY MARKER" : "");
                }
            }
        }
    }
    if (a == 0x8004111Cu) {
        static int b = 40;
        if (b-- > 0) {
            fprintf(stderr, "[slot] ENQUEUE fn_8004111C(a0=0x%08X a1=0x%08X) caller=0x%08X cell564A8=0x%08X\n",
                    r[4], r[5], r[31], xenolift_mem_read32(0x800564A8u));
            static int b2 = 6;
            if (b2-- > 0) {
                uint32_t base = 0x80056420u;
                fprintf(stderr, "[slot] slot-table dump @0x%08X:", base);
                for (int i = 0; i < 12; i++)
                    fprintf(stderr, " [%d]=0x%08X", i, xenolift_mem_read32(base + 4u * i));
                fprintf(stderr, "\n");
            }
        }
    }
    /* R282: state-machine routing probes — FSMHIST shows states only in {1,2,5,10};
     * the state-11 LADDER DISPATCHER (fn_8002AB28) and states 6/7 never appear =>
     * completions are stolen by the queue dispatcher (fn_800413EC writes FE1C 10->1).
     * These entry probes catch the routing: who dispatches, with which arg, in what order. */
    /* R370 TITLE-ERA FONT PROBES: cycle 126/127 parked inside the font-render
     * family - fn_80036718 = FontVPrintf (printf-style, r5=fmt), fn_800366F0 =
     * EmitFontCharacter (r4=char), and the indirect-dispatch callee 0x800370DC
     * (dispatched via the fn_800366F8 wrapper, r2=target at park). Capture the
     * actual title text + the spin-site args. All HARD-CAPPED (L20/L15/L21):
     * EmitFontCharacter fires per character = thousands per frame. */
    if (a == 0x80036718u) { /* FontVPrintf entry: dump the format string */
        static int fvp = 24;
        if (fvp-- > 0) {
            fprintf(stderr, "[fvp] fmt@%08X caller=%08X: \"", r[5], r[31]);
            for (int w = 0; w < 12; w++) {
                uint32_t v = xenolift_mem_read32(r[5] + (uint32_t)(4 * w));
                int stop = 0;
                for (int b = 0; b < 4 && !stop; b++) {
                    unsigned char c = (unsigned char)(v >> (8 * b));
                    if (c == 0 || (c < 32u) || c > 126u) { stop = 1; break; }
                    fputc(c, stderr);
                }
                if (stop) break;
            }
            fprintf(stderr, "\"\n");
        }
    }
    if (a == 0x800366F0u) { /* EmitFontCharacter: one glyph into the font buffer */
        static int emit = 64;
        if (emit-- > 0)
            fprintf(stderr, "[emit] char=0x%02X '%c' x=%u y=%u (r21=%u r20=%u) caller=%08X\n",
                    r[4], (r[4] >= 32u && r[4] < 127u) ? (int)r[4] : '.',
                    r[21] & 0xFFu, r[20] & 0xFFu, r[21], r[20], r[31]);
    }
    if (a == 0x800370DCu) { /* the parked indirect callee - spin-site args */
        static int d37 = 40;
        if (d37-- > 0)
            fprintf(stderr, "[d37c] entry r2=%08X r4=%08X r5=%08X r6=%08X r7=%08X FE1C=%u FE20=%u caller=%08X\n",
                    r[2], r[4], r[5], r[6], r[7],
                    xenolift_mem_read32(0x8004FE1Cu), xenolift_mem_read32(0x8004FE20u), r[31]);
    }
    if (a == 0x80037FD8u) { /* R487: WDS bank install — diff bank-2 source (file-5 region) vs disc payload */
        static int wds_n;
        if (wds_n++ < 8) {
            uint32_t dst = 0x800AA6B0u, lba = 108873u, len = 21984u;
            { /* R491: LAST-CHANCE HEAL. c57: files 3/4 got NO rescue (timing race
               * moved the boot past them) yet their dests still hold stale heap —
               * bank-2's struct is garbage and the sound allocator then walks off
               * the world. We are AT the installer's door: if the bank source lacks
               * the WDS magic ("wds " = 0x20736477), the file never landed. Find the
               * file by dest in the R490 directory and re-shelve its full content
               * from disc (hdr -> dest-8, payload -> dest) BEFORE the read. */
                static uint32_t r491_heal_n;
                if (r491_heal_n < 4u && r[4] >= 0x80010000u
                    && xenolift_mem_read32(r[4]) != 0x20736477u) {
                    for (uint32_t k = 1u; k < 64u; k++) {
                        if (s_ovl_dest[k] == r[4] && s_ovl_lba[k] > 100000u
                            && s_ovl_size[k] >= 8u && s_ovl_size[k] <= 0x400000u) {
                            uint32_t d = r[4] - 0x80000000u;
                            uint32_t lba = s_ovl_lba[k], sz = s_ovl_size[k], off = 8u;
                            static uint8_t hb[2048];
                            if (d >= 0x10000u && d + (sz - 8u) <= 0x200000u) {
                                /* R492: payload only - dest-8 is a live heap
                                 * record (c58 walker crash); never touch it. */
                                while (off < sz) {
                                    uint32_t in_sec = off % 2048u;
                                    uint32_t chunk = 2048u - in_sec;
                                    if (chunk > sz - off) chunk = sz - off;
                                    if (disc_read_lba(lba + off / 2048u, hb) != 0)
                                        memset(hb, 0, 2048);
                                    memcpy(xenolift_mem + d + (off - 8u), hb + in_sec, chunk);
                                    off += chunk;
                                }
                                fprintf(stderr, "[wdsheal] R492: bank source STALE — file#%u re-shelved %uB -> 0x%08X before install\n",
                                        k, sz, (unsigned)r[4]);
                                r491_heal_n++;
                            }
                            break;
                        }
                    }
                }
            }
            fprintf(stderr, "[wdsdiff] bank install a0=%08X — struct words:\n", (unsigned)r[4]);
            for (int w = 0; w < 12; w++)
                fprintf(stderr, "[wdsdiff]   +0x%02X: %08X\n", w * 4, (unsigned)xenolift_mem_read32(r[4] + 4u * w));
            static uint8_t sec[2048];
            uint32_t off = 0; int mism = 0, sec_ok = 0;
            while (off < len) {
                uint32_t in_sec = off % 2048u;
                if (in_sec == 0) {
                    if (disc_read_lba(lba + off / 2048u, sec) != 0) memset(sec, 0, 2048);
                }
                uint8_t g = xenolift_mem[(dst + off) & 0x1FFFFFFFu];
                if (g != sec[in_sec] && !mism) {
                    mism = 1;
                    fprintf(stderr, "[wdsdiff] FIRST MISMATCH @byte %u (sector %u + %u): ram=%02X disc=%02X\n",
                            (unsigned)off, (unsigned)(off / 2048u), (unsigned)in_sec, g, sec[in_sec]);
                }
                if (in_sec == 2047 && !mism) sec_ok++;
                off++;
            }
            fprintf(stderr, "[wdsdiff] %s (clean sectors: %d)\n",
                    mism ? "DATA DIVERGES — delivery is the fault" :
                    "file-5 region MATCHES disc payload — allocator math is the fault", sec_ok);
        }
    }
    if (a == 0x8002AB6Cu || a == 0x8002AB88u || a == 0x8002AB9Cu) { /* R358: ladder ARM states (FE1C->3/5/6 + issue cmds 2/9). Verdict probe: does the field file-14 read ever reach the ARM stage, and with which FE04? Capped (L15) — these fire once per read, not per access. */
        static int arms = 40;
        if (arms-- > 0)
            fprintf(stderr, "[armst] fn=%08X FE04=%08X FDF8=%08X FE20=%u FE1C=%u reqF10=%08X caller=%08X\n",
                    a, xenolift_mem_read32(0x8004FE04u), xenolift_mem_read32(0x8004FDF8u),
                    xenolift_mem_read32(0x8004FE20u), xenolift_mem_read32(0x8004FE1Cu),
                    xenolift_mem_read32(0x80059F10u), r[31]);
    }
    if (a == 0x8002B2F0u) { /* R580 [streamcb]: c148 — the game DMA'd file-15 sector data into the batch slot SIX times with its own fetch yet its bookkeeping (FE08 advance) never ran; the current-file callback (8002B084, watched since R547) handles per-file copies, but 8002B2F0 is the sibling ARCHIVE-STREAM callback ("receives standard CD sectors into sequenced ring sections"). Watch its entries + the callback-table cells so we learn which slot dispatches it and whether it is armed. */
        static int scn = 24;
        if (scn-- > 0) {
            fprintf(stderr, "[streamcb] cb 8002B2F0 entry ev=%u r5=%08X r6=%08X r31=%08X | cbtab: F08=%08X F0C=%08X F10=%08X F14=%08X F18=%08X | FE08=%08X FE34=%u FDE4=%u FE1C=%u FDF8=%u\n",
                    r[4] & 0xFFu, r[5], r[6], r[31],
                    xenolift_mem_read32(0x80059F08u), xenolift_mem_read32(0x80059F0Cu),
                    xenolift_mem_read32(0x80059F10u), xenolift_mem_read32(0x80059F14u),
                    xenolift_mem_read32(0x80059F18u),
                    xenolift_mem_read32(0x8004FE08u), xenolift_mem_read32(0x8004FE34u),
                    xenolift_mem_read32(0x8004FDE4u), xenolift_mem_read32(0x8004FE1Cu),
                    xenolift_mem_read32(0x8004FDF8u));
        }
    }
    if (a == 0x8002B084u) { /* R547 [dirloop]: the ready-callback (reqF08) the game registers per read — c115: kernel consumed every bell answer (10x [fldbell4], pops OK) yet re-reads LBA 0/1 into a NEW ring slot each pass. Log its arguments + the delivered-data head to see what it parses/compares and whether the pointer advances. */
        static int dln = 30;
        if (dln-- > 0) {
            /* R548 v2: r4=event code (1=data-ready), r5=archive destination struct.
             * c116 lesson: r4 is NOT a pointer — old receipt printed its own fallback.
             * Dump the r5 struct head + batch cells the decoded callback gates on:
             * FE34 (batch remaining) >0 -> copy path; else FDF8 path; r5 struct = destination state. */
            uint32_t s0 = xenolift_mem_read32(r[5]);
            uint32_t s1 = xenolift_mem_read32(r[5] + 4u);
            uint32_t s8 = xenolift_mem_read32(r[5] + 8u);
            uint32_t fe08 = xenolift_mem_read32(0x8004FE08u);
            uint32_t b0 = (fe08 >= 0x80010000u && fe08 < 0x801FFFFCu) ? xenolift_mem_read32(fe08) : 0u;
            fprintf(stderr, "[dirloop] cb 8002B084 entry ev=%u r5=%08X r6=%08X r31=%08X | s[r5]=%08X %08X %08X | FE08=%08X b[FE08]=%08X FE34=%u FE0C=%08X FDE4=%u | FE04=%08X FE1C=%u FDF8=%u\n",
                    r[4] & 0xFFu, r[5], r[6], r[31], s0, s1, s8, fe08, b0,
                    xenolift_mem_read32(0x8004FE34u), xenolift_mem_read32(0x8004FE0Cu),
                    xenolift_mem_read32(0x8004FDE4u),
                    xenolift_mem_read32(0x8004FE04u), xenolift_mem_read32(0x8004FE1Cu),
                    xenolift_mem_read32(0x8004FDF8u));
        }
        /* R551 FE34FIX entry-prime: c119 verdict — the on_alarm heartbeat NEVER saw all gate
         * conditions at once (callback cell cycles armed/cleared between ticks), so the R549
         * tick-prime never fired. THIS hook runs at cb entry — the exact moment the decoded
         * ArchiveCurrentFileReadyCallback checks FE34>0 before its copy path. Prime here. */
        if (0) { /* R564 REMOVED R551 prime: c132 disasm L_8002B084 — FE34>0 means SKIP-copy ->
                 * HandleCdReadyCompletion -> teardown (FDF8=0, PositionArchiveEntry, FDFC=0).
                 * R551 injected the ABORT flag at cb entry; the 12-cycle re-dance was OUR bug. */
            xenolift_mem_write32(0x8004FE34u, 1u);
            { static uint32_t fe34en;
              if (fe34en < 40u) {
                fe34en++;
                fprintf(stderr, "[fe34fix] R551: ENTRY-prime FE34 0->1 (dest FE08=%08X FDF8=%u r31=%08X) - copy gate open at cb doorstep\n",
                        xenolift_mem_read32(0x8004FE08u), xenolift_mem_read32(0x8004FDF8u), r[31]);
              }
            }
        }
        /* R564 FE34-UNLOCK: inverse of dead R551 — if the callback enters with FE34>0
         * while a REAL backlog exists (dest inside file-14 landing zone, remaining>0),
         * that abort flag is stale: clear it so the copy path runs. Cap 8 logs. */
        if ((r[4] & 0xFFu) == 1u
            && xenolift_mem_read32(0x8004FE34u) != 0u
            && xenolift_mem_read32(0x8004FE08u) >= 0x801D9724u
            && xenolift_mem_read32(0x8004FE08u) < (0x801D9724u + 125304u)
            && xenolift_mem_read32(0x8004FDF8u) > 0u) {
            xenolift_mem_write32(0x8004FE34u, 0u);
            { static uint32_t fe34ul;
              if (fe34ul < 8u) { fe34ul++;
                fprintf(stderr, "[fe34unlock] R564: stale abort flag CLEARED at cb entry (dest FE08=%08X FDF8=%u) - copy path open\n",
                        xenolift_mem_read32(0x8004FE08u), xenolift_mem_read32(0x8004FDF8u));
              } }
        }
        /* R554 FDF8-restore DE-NESTED (c122 miss: R553 nested this inside the FE34-prime
         * gate; at the 2nd field-cb entry FE34 was already 1, so it never ran and the game
         * parked at state 6 with a zeroed backlog). The game's pause step zeroes FDF8 before
         * each sector's copy; the callback's continue-branch (r3>0 -> L_8002B2E0 keep reading)
         * needs the TRUE remaining count. Fires on EVERY field-file cb entry (ev==1) with an
         * empty backlog. end = 0x801D9724 + 125304 (file-14 landing zone). */
        if ((r[4] & 0xFFu) == 1u) {
            uint32_t f_dst = xenolift_mem_read32(0x8004FE08u);
            uint32_t f_end = 0x801D9724u + 125304u;
            if (f_dst >= 0x801D9724u && f_dst < f_end
                && xenolift_mem_read32(0x8004FDF8u) == 0u) {
                uint32_t remaining = f_end - f_dst;
                xenolift_mem_write32(0x8004FDF8u, remaining);
                { static uint32_t r554n;
                  if (r554n < 80u) { r554n++;
                    fprintf(stderr, "[fe34fix] R554: fdf8-restored %u (dest %08X offset %u of file-14) - continue-branch sees true backlog\n",
                            remaining, f_dst, f_dst - 0x801D9724u);
                  }
                }
            }
        }
    }
    if (a == 0x8002AAF0u) { /* R544 [sm10]: state-10 handler (arc[10]) — decoded c112: requires r4&0xFF==2 and byte@r5 bit4 CLEAR, then writes FE1C=11. Log entry args to verify the contract live. */
        static int sm10n = 40;
        if (sm10n-- > 0) {
            uint32_t r5v = (r[5] >= 0x80010000u && r[5] < 0x80200000u) ? xenolift_mem[r[5]-0x80000000u] : 0xFFu;
            fprintf(stderr, "[sm10] state-10 HANDLER entry r4=%02X r5=%08X byte@r5=%02X bit4=%u FE1C=%u FE20=%u caller=%08X\n",
                    r[4] & 0xFFu, r[5], r5v, (r5v >> 4) & 1u,
                    xenolift_mem_read32(0x8004FE1Cu), xenolift_mem_read32(0x8004FE20u), r[31]);
        }
    }
    if (a == 0x80041430u) { /* R596 [stepper]: the queue-advancer (fn 80041430) ran
         * at boot for every completed file (F0C 2->...->14, node F10 walked
         * 00NN1424 -> walk -> done 00001524, FE08 advanced to next dest).
         * c164: mount ACCEPTED natively (cur=1 by fn 8004B8BC, req cleared,
         * pending=0 sched=0) yet F0C never advanced 14->15 and the field
         * phase cb never dispatched. The stepper is the missing rung: watch
         * EVERY entry while F0C==14 (post-mount posture) so we learn what
         * gates its boot-era behavior — its caller + node state before/after. */
        static uint32_t stp_n;
        uint32_t f0c_now = xenolift_mem_read32(0x80059F0Cu);
        if (stp_n < 40u || (stp_n % 2000u) == 0u)
            fprintf(stderr, "[stepper] R596 #%u entry F0C=%u F10=%08X FE08=%08X FDF8=%08X FE34=%u FE1C=%u cur=%08X caller=%08X\n",
                    stp_n, f0c_now, xenolift_mem_read32(0x80059F10u),
                    xenolift_mem_read32(0x8004FE08u), xenolift_mem_read32(0x8004FDF8u),
                    xenolift_mem_read32(0x8004FE34u), xenolift_mem_read32(0x8004FE1Cu),
                    xenolift_mem_read32(0x800592C0u), r[31]);
        stp_n++;
    }
    if (a == 0x80077E88u) { /* R571: FIELD phase callback (phase table[1]) — decisive receipt that the main loop dispatches the field module per-frame after the mount-success copy (c139: idx=1 req=0 accepted, writer fn 0x800366F8) */
        static uint32_t fldcb_n;
        if (fldcb_n < 24u || (fldcb_n % 1000u) == 0u)
            fprintf(stderr, "[fldcb] R571 FIELD-PHASE callback entry #%u a0=%08X a1=%08X idx=%08X cur=%08X land=%08X caller=%08X\n",
                    fldcb_n, r[4], r[5], xenolift_mem_read32(0x8005FAECu),
                    xenolift_mem_read32(0x800592C0u), xenolift_mem_read32(0x801D9724u), r[31]);
        fldcb_n++;
    }
    if (a == 0x8002AB28u) { /* state 11 = stream ladder dispatcher (reads FE20, jumps table @0x8001892C) */
        static int sb28 = 40;
        static uint32_t churn;
        /* R324 FALSE-TRIP FIX: R320 measured "depth" with &sb28 — a STATIC
         * (data-segment) address ~4.4GB below the guest stack base on macOS —
         * so (base - sp_now) exceeded 1.25GB on the FIRST check and the guard
         * force-parked every run at t=1s (cycles 69-72 all false trips; the
         * churn trampoline never got a fair test). Measure with a REAL stack
         * local, and bound the check to the 2048MB guest stack region so any
         * cross-thread context is skipped instead of tripping. */
        volatile int sb28_probe_ = 0;
        uintptr_t sp_now = (uintptr_t)&sb28_probe_;
        if (sb28-- > 0)
            fprintf(stderr, "[sm11] state-11 DISPATCHER entry a0=%u FE1C=%u FE20=%u caller=%08X\n",
                    r[4] & 0xFFu, xenolift_mem_read32(0x8004FE1Cu), xenolift_mem_read32(0x8004FE20u), r[31]);
        /* R320: recursion guard — see globals comment. Halt at 1.25GB depth
         * (2048MB stack, wide margin) BEFORE the OOM kill. */
        churn++;
        if (churn == 1u && g_stack_base != 0u)
            fprintf(stderr, "[depth] guard LIVE sp=%llX base=%llX depth=%llX (R324 real-stack fix)\n",
                    (unsigned long long)sp_now, (unsigned long long)g_stack_base,
                    (unsigned long long)(g_stack_base - sp_now));
        if (g_stack_base != 0u && sp_now < g_stack_base
            && sp_now > (g_stack_base - 0x80000000ull) /* R324: same 2048MB stack only */
            && (g_stack_base - sp_now) > 0x50000000ull) {
            if (!g_force_halt) {
                g_force_halt = 1;
                fprintf(stderr, "[depth] C-recursion depth 0x%llX after %u state-11 hops - forcing graceful halt (was OOM-killed cycle-68)\n",
                        (unsigned long long)(g_stack_base - sp_now), churn);
                alarm(1); /* ring the budget-halt path within 1s */
            }
        } else if ((churn & 0xFFFFu) == 0u) {
            fprintf(stderr, "[depth] churn=%u depth=0x%llX\n", churn,
                    (unsigned long long)(g_stack_base ? (g_stack_base - sp_now) : 0));
        }
    }
    if (a == 0x800413ECu) { /* queue dispatcher — FSMHIST shows it writing FE1C 10->1 (the thief) */
        static int sbec = 40;
        if (sbec-- > 0)
            fprintf(stderr, "[smq] fn_800413EC entry a0=%08X a1=%08X FE1C=%u FE20=%u caller=%08X\n",
                    r[4], r[5], xenolift_mem_read32(0x8004FE1Cu), xenolift_mem_read32(0x8004FE20u), r[31]);
    }
    if (a == 0x8002A92Cu) { /* R329: state 7 (seek-issuer). Park FE1C=7
         * with guest happy/fail counters A4A8/A4B4 BOTH ZERO while the
         * R275 probe counts 42 entries = the handler is entered but its
         * body never runs (the state-11 ghost pattern). happy path writes
         * FE1C=6 + A4A8++ then re-seeks; fail path writes FE20=4 + FE1C=10
         * + A4B4++. Log a0 + both counters at entry; if they stay frozen
         * while this probe fires, the dispatch below the entry is dead.
         * R331: 24->48 — cycle-79 cap ran out BEFORE the seek7 assist
         * fired, so post-assist entries (A4A8=1) were invisible. */
        static int sb7 = 48; static uint32_t sb7_total; /* R333: first 48 always, then 1-in-2000 — post-assist entries visible */
        sb7_total++;
        if (sb7-- > 0 || (sb7_total % 2000u) == 0u)
            fprintf(stderr, "[sm7] state-7 entry a0=%u FE1C=%u FE20=%u A4A8=%u A4B4=%u caller=%08X\n",
                    r[4] & 0xFFu, xenolift_mem_read32(0x8004FE1Cu), xenolift_mem_read32(0x8004FE20u),
                    xenolift_mem_read32(0x8006A4A8u), xenolift_mem_read32(0x8006A4B4u), r[31]);
    }
    if (a == 0x8002A894u) { /* state 6 */
        static int sb6 = 48; static uint32_t sb6_total; /* R333: 1-in-2000 sampling like sb7 */
        sb6_total++;
        if (sb6-- > 0 || (sb6_total % 2000u) == 0u)
            fprintf(stderr, "[sm6] state-6 entry a0=%u FE1C=%u FE20=%u happy6=%u/%u retry6=%u caller=%08X\n",
                    r[4] & 0xFFu, xenolift_mem_read32(0x8004FE1Cu), xenolift_mem_read32(0x8004FE20u),
                    xenolift_mem_read32(0x8006A488u), xenolift_mem_read32(0x8006A494u),
                    xenolift_mem_read32(0x8006A498u), r[31]);
    }
    /* R288: deep-ladder probes — cycle-36 ran states 12->8->1->0 via new armer
     * fn_80041820 (writes FE1C=12 and 6); FE20 stuck oscillating 3<->4, never 5.
     * Probe the two new-state handlers + both FE1C/FE20 writers. */
    if (a == 0x80040FCCu) { /* HandleCdReadyCompletion — state-6 happy hands it a waiter chain */
        static int hrc = 16;
        if (hrc-- > 0)
            fprintf(stderr, "[hrc] HandleCdReadyCompletion r4=%08X ready8=%08X ready10=%08X FE1C=%u FE20=%u\n",
                    r[4], xenolift_mem_read32(0x80069F08u), xenolift_mem_read32(0x80069F10u),
                    xenolift_mem_read32(0x8004FE1Cu), xenolift_mem_read32(0x8004FE20u));
    }
    if (zsr_pending && a != 0x80029690u) { /* R293: after StartArchiveRead returns via next fn entry, apply sync-complete once */
        if (zsr_pending == 2) {
            xenolift_mem_write32(0x8004FDF8u, 0);
            xenolift_mem_write32(0x8004FDFCu, 0);
            fprintf(stderr, "[zsr] sync-complete applied: FDF8=0 FDFC=0 (read done, no data event needed)\n");
            zsr_pending = 1;
        }
    }
    if (a == 0x80029690u && g_movie_live) { /* R294: zero-length StartArchiveRead sync-complete — MOVIE-PHASE-ONLY (cycle-42 regression: no gate = fired silently during boot reads, zeroed FDF8/FDFC mid-load = all module data empty = heap/verdict chaos). */
        if ((r[6] & 0xFFFFu) == 0u) {
            static int szsr = 12;
            if (szsr-- > 0)
                fprintf(stderr, "[zsr] zero-size StartArchiveRead member (a0=%08X dest=%08X len=0) -> sync-complete: FDF8=0 FDFC=0 armed at exit\n",
                        r[4], r[5]);
            zsr_pending = 2; /* arm: set cells after fn body completes its setup */
        }
    }
    if (a == 0x8002ABFCu) { /* R291: shared wrong-slot/fail path for states 10/11 (a0!=2 or gate bit) */
        static int sbfc = 40;
        if (sbfc-- > 0)
            fprintf(stderr, "[smfc] fn_8002ABFC entry a0=%u a1=%08X FE1C=%u FE20=%u gate=%02X caller=%08X\n",
                    r[4] & 0xFFu, r[5], xenolift_mem_read32(0x8004FE1Cu), xenolift_mem_read32(0x8004FE20u),
                    (r[5] >= 0x80000000u && r[5] < 0x80200000u) ? xenolift_mem_read8(r[5]) : 0xFFu, r[31]);
    }
    /* R296: THE VIRTUAL PLAYER, entry-hook engine. fn_800769A4 (SkipInput) polls
         * the controller every movie-slice; fn_8003569C (ReadControllerButtons)
         * reads the InitPAD buffers' bytes 2-3 (active-low). After 4096 movie-
         * phase SkipInput polls, hold X: write byte3 = 0xBF (bit 0x40 clear =
         * X reported pressed) on every ReadControllerButtons entry for 200
         * reads, then release once. The poll's own gate (prev+cur bit 0x40,
         * 0x80077028 == 0) then sets 0x80077014 = 5 = movie start. */
        if (a == 0x800769A4u && g_movie_live && g_press_state == 0u) {
            if (++g_skip_polls == 4096u) {
                g_press_state = 1u; g_readbutton_holds = 0u;
                fprintf(stderr, "[padin] VIRTUAL PLAYER pressing X after %u skip-polls\n", g_skip_polls);
            }
        }
        if (a == 0x8003569Cu && g_press_state == 1u) {
            xenolift_mem[0x625FCu + 3] = 0xBF;
            xenolift_mem[0x6261Eu + 3] = 0xBF;
            if (++g_readbutton_holds >= 200u) {
                g_press_state = 2u;
                xenolift_mem[0x625FCu + 3] = 0xFF;
                xenolift_mem[0x6261Eu + 3] = 0xFF;
                fprintf(stderr, "[padin] VIRTUAL PLAYER released X after %u reads (one-shot done)\n", g_readbutton_holds);
            }
        }
        /* R373 MENU-ERA VIRTUAL PLAYER v3 + per-frame call census.
         * Cycle-129/130 verdict: the menu NEVER calls fn_8003569C ([rcb] census:
         * 25+ calls but ALL movie-era via callers 800358CC/80035A68; the R371/372
         * settle trigger on 8003569C entries never fired = no press line). The
         * kernel menu reads input its OWN way. v3: (1) frame-cadence trigger -
         * each menu-header FontVPrintf render (r5==0x800182C0) counts as one menu
         * frame; after 2 frames hold X PERSISTENTLY in the InitPAD pad buffers
         * (byte3=0xBF active-low), rewritten on EVERY dispatch so any per-frame
         * direct pad read (PadRead-style) sees it; release after 8 more frames,
         * one-shot. (2) [mpad] frame census: dedup-record every fn dispatched
         * between header renders and print the set (cap 8 prints) - names the
         * menu's real input reader next digest. */
        { /* R636 PARK CENSUS (c206): the widened read-camera burned its cap in
             * the t=15s commit burst (13x92C0 + 1xFE04) and saw NOTHING during
             * the park - third era-blind-cap hit. The mpad census answered the
             * menu era by listing every dispatched fn; re-arm it for the PARK
             * era: t>=25s, dedup-record all dispatched fns, print the set every
             * 30s (cap 3 prints x 200 fns) - names the park waiter directly. */
            /* R640 (c210) STATE-1 ENTRY CAMERA: the real state table
             * (0x8001808C, from exe bytes) wires state-1 = FIELD to entry
             * 0x80077E88. Transition teardown ran (c210 census) but 80077E88
             * never dispatched - receipt it directly, cap 8. */
            { static int r640n;
              if (a == 0x80077E88u && r640n < 8) {
                  r640n++;
                  fprintf(stderr, "[cd] R640 STATE-1 ENTRY 80077E88 #%d @t=%lds req=%08X cur=%08X idx=%08X 92BC=%08X\n",
                          r640n, (long)(time(NULL) - g_boot_wall_t0),
                          xenolift_mem_read32(0x80018088u),
                          xenolift_mem_read32(0x800592C0u),
                          xenolift_mem_read32(0x8005FAECu),
                          xenolift_mem_read32(0x800592BCu));
              {   /* R685 [coordb3]: coordinator-page BOUNDARY dump - is the data
                   * block at 0x80077E88 an island (legit table inside module-2
                   * code) or a corruption patch (garbage neighbors too)? */
                  static int c3n = 0;
                  if (c3n++ < 2) {
                      const uint32_t spots[3] = {0x80077E68u, 0x80077E88u, 0x80077EC8u};
                      for (int s = 0; s < 3; s++) {
                          uint32_t w[8]; char buf[9*8+1]; int q = 0; buf[0]=0;
                          for (int i = 0; i < 8; i++) {
                              w[i] = xenolift_mem_read32(spots[s] + 4u*(uint32_t)i);
                              q += sprintf(buf+q, "%08X ", w[i]);
                          }
                          fprintf(stderr, "[coordb3] R685 window-0 @%08X: %s\n", spots[s], buf);
                      }
                  } }
                  {   /* R683 [coordb]: c254 proved 0x80077E88 holds DATA
                       * (001D8453 14001440 800B9012 F8C43C01 - the wild jump
                       * target was literally word[3]) - the kernel dispatches
                       * into a descriptor, not code. The REAL field module is
                       * file 14, installed at 0x801D9724 (stage-2 window).
                       * Photograph BOTH rooms at dispatch time: the descriptor
                       * block and the module base, plus the module table. */
                      uint32_t cbp = 0x80077E88u, mbp = 0x801D9724u;
                      fprintf(stderr, "[coordb] R683 descriptor block @0x80077E88:");
                      for (int q = 0; q < 8; q++) fprintf(stderr, " %08X", xenolift_mem_read32(cbp + 4u*q));
                      fprintf(stderr, "\n[coordb] R683 field-module base @0x801D9724:");
                      for (int q = 0; q < 8; q++) fprintf(stderr, " %08X", xenolift_mem_read32(mbp + 4u*q));
                      fprintf(stderr, "\n[coordb] R683 module table @0x8004EAA0:");
                      for (int q = 0; q < 8; q++) fprintf(stderr, " %08X", xenolift_mem_read32(0x8004EAA0u + 4u*q));
                      fprintf(stderr, " | relay cells: 92B8=%08X 92BC=%08X 92C4=%08X 92C8=%08X 18098=%08X\n",
                              xenolift_mem_read32(0x800592B8u), xenolift_mem_read32(0x800592BCu),
                              xenolift_mem_read32(0x800592C4u), xenolift_mem_read32(0x800592C8u),
                              xenolift_mem_read32(0x80018098u));
                {   /* R684 [coordb2]: queue cells 18088..180AC (all four 16B
                 * descriptors), the staged field module's 32-word header (find
                 * the entry table), the candidate relocated-coordinator offset
                 * inside the staged module (module-2 base 8006FAF8 ->
                 * coordinator 80077E88 = offset 0x8390; staged base 801D9724
                 * -> candidate 801E1AB4), and the WORKING movie entry
                 * 800737EC as the healthy-control sample. */
                    int qi;
                    fprintf(stderr, "[coordb2] R684 queue descriptors 18088..180AC:");
                    for (qi = 0; qi < 10; qi++)
                        fprintf(stderr, " %08X", xenolift_mem_read32(0x80018088u + 4u * (uint32_t)qi));
                    fprintf(stderr, "\n");
                    fprintf(stderr, "[coordb2] R684 staged-module header @801D9724 (32w):");
                    for (qi = 0; qi < 32; qi++)
                        fprintf(stderr, " %08X", xenolift_mem_read32(0x801D9724u + 4u * (uint32_t)qi));
                    fprintf(stderr, "\n");
                    fprintf(stderr, "[coordb2] R684 field-coordinator candidate @801E1AB4 (offset 8390, 8w):");
                    for (qi = 0; qi < 8; qi++)
                        fprintf(stderr, " %08X", xenolift_mem_read32(0x801E1AB4u + 4u * (uint32_t)qi));
                    fprintf(stderr, "\n");
                    fprintf(stderr, "[coordb2] R684 healthy-control movie entry @800737EC (8w):");
                    for (qi = 0; qi < 8; qi++)
                        fprintf(stderr, " %08X", xenolift_mem_read32(0x800737ECu + 4u * (uint32_t)qi));
                    fprintf(stderr, "\n");
                }
                  }
              } }
            long r636t = time(NULL) - g_boot_wall_t0;
            if (r636t >= 25) {
                static uint32_t r636set[200]; static int r636n; static long r636last;
                int r636seen = 0;
                for (int r636i = 0; r636i < r636n; r636i++)
                    if (r636set[r636i] == a) { r636seen = 1; break; }
                if (!r636seen && r636n < 200) r636set[r636n++] = a;
                if (r636last == 0) r636last = r636t;
                if (r636t - r636last >= 30 && r636n > 0) {
                    static int r636prints;
                    if (r636prints < 3) { r636prints++;
                        fprintf(stderr, "[census] R636 park window t=%lds..%lds (%d fns):",
                                r636last, r636t, r636n);
                        for (int r636i = 0; r636i < r636n; r636i++)
                            fprintf(stderr, " %06X", r636set[r636i]);
                        fprintf(stderr, "\n");
                    }
                    r636n = 0; r636last = r636t;
                }
            }
        }
        if (g_menu_seen && g_menu_press_state != 3u && a != 0x80036718u) {
            int seen = 0;
            for (int i = 0; i < g_menu_callcount; i++)
                if (g_menu_callset[i] == a) { seen = 1; break; }
            if (!seen && g_menu_callcount < 128)
                g_menu_callset[g_menu_callcount++] = a;
        }
        if (a == 0x80036718u && r[5] == 0x800182C0u) {
            static int sio_prints;
            if (sio_prints < 10) { /* R377: does ANYTHING touch the controller port per menu frame? */
                sio_prints++;
                fprintf(stderr, "[mpad] frame #%u sio-acc=%ld (controller-port accesses since last frame)\n", g_menu_frames, g_sio_acc_menu);
            }
            g_sio_acc_menu = 0;
            static int census_prints;
            if (census_prints < 2) { /* R374: cap 8->2 - cycle 131 burned 8 prints on identical fn sets */
                census_prints++;
                fprintf(stderr, "[mpad] menu frame #%u call census (%u fns):",
                        g_menu_frames, g_menu_callcount);
                for (int i = 0; i < g_menu_callcount && i < 128; i++)
                    fprintf(stderr, " %06X", g_menu_callset[i]);
                fprintf(stderr, "\n");
            }
            g_menu_callcount = 0;
            if (!g_menu_seen) {
                g_menu_seen = 1u;
                g_menu_press_state = 1u;
                fprintf(stderr, "[mpad] kernel menu detected - frame cadence armed\n");
            } else if (g_menu_press_state == 1u) {
                if (++g_menu_frames >= 2u) {
                    g_menu_press_state = 2u;
                    g_menu_frames = 0u;
                    fprintf(stderr, "[mpad] MENU VIRTUAL PLAYER pressing CONFIRM at 0x8006948C (cursor 0 = Field -> CommitGameStateTransition(1))\n");
                }
            } else if (g_menu_press_state == 2u) {
                if (++g_menu_frames >= 12u) { /* R380: 12-frame hold - cycle-137 3-frame confirm STILL not seen; a transient wipe (ClearControllerSnapshots) may eat short windows */
                    g_menu_press_state = 3u;
                    xenolift_mem[0x625FCu + 3] = 0xFF;
                    xenolift_mem[0x6261Eu + 3] = 0xFF;
                    xenolift_mem[0x773ACu + 3] = 0xFF; /* R377 frame-layout release */
                    xenolift_mem[0x773ACu + 4] = 0xFF;
                    xenolift_mem[0x773B4u + 3] = 0xFF;
                    xenolift_mem[0x773B4u + 4] = 0xFF;
                    xenolift_mem[0x6948Cu] = 0x00; /* R379: confirm bit released */
                    fprintf(stderr, "[mpad] MENU VIRTUAL PLAYER released CONFIRM after %u menu frames (one-shot done)\n", g_menu_frames);
                }
            }
        }
        if (g_menu_press_state == 2u) { /* persistent hold: rewrite every dispatch */
            xenolift_mem[0x625FCu + 3] = 0xBF; /* X pressed (active-low bit 0x40 clear) */
            xenolift_mem[0x6261Eu + 3] = 0xBF;
            /* R374: ALSO press at KERNEL level. Cycle-131 verdict: the R373 buffer
             * press fired (8 frames held+released) and the menu ignored it; the frame
             * census shows NO pad reader among the menu's 24 fns; the kernel button
             * cells 0x800773AC/74B4 sit at 0 since the movie era ended. The countdown-
             * era decode (fn_800769A4) proved the kernel polls THIS pair with bit 0x40
             * = X, active-low. Write X-held into the cells themselves. */
            /* R377: cycle-134 re-read of the R295 decode — the kernel cells are
             * 8-BYTE PAD FRAMES, not bare button bytes: [0]=header/[ID], buttons
             * at +2/+3 (InitPAD-buffer layout, byte3 = buttons-hi with X = bit
             * 0x40), possibly +4 (raw-frame layout). R374 wrote +0 = the ID
             * header byte = pressed NOTHING. Hold X at every plausible button
             * slot of both cells (prev 773AC + cur 773B4). */
            xenolift_mem[0x773ACu + 0] = 0xFF;
            xenolift_mem[0x773ACu + 2] = 0xFF;
            xenolift_mem[0x773ACu + 3] = 0xBF;
            xenolift_mem[0x773ACu + 4] = 0xBF;
            xenolift_mem[0x773B4u + 0] = 0xFF;
            xenolift_mem[0x773B4u + 2] = 0xFF;
            xenolift_mem[0x773B4u + 3] = 0xBF;
            xenolift_mem[0x773B4u + 4] = 0xBF;
            /* R379: THE CONFIRM PRESS. Cycle-136 window decoded the full handler:
             * LHU 0x8006948C bit 0x0020 (circle/confirm, ACTIVE-HIGH) -> reads cursor
             * cell 0x8005F2D8 and calls fn_8001996C(cursor + 1) = CommitGameStateTransition
             * (symbol: state 0=Kernel Menu, 1=FIELD, 2=Battle, 3=Worldmap, 4=Battling,
             * 5=Menu, 6=Movie). Park shows cursor=0, so confirm = Commit(1) = FIELD.
             * Held 3 menu frames (cycle-136 X pulse vanished - likely wiped by a kernel
             * restart, so re-assert across several frames; Commit is idempotent).
             * Old X-bit write removed: cursor is already 0 = Field. */
            xenolift_mem[0x6948Cu] = 0x20;
            /* R381 CHANNEL B — DIRECT STATE REQUEST. Cycles 137-138: the confirm
             * bit (0x20 at 6948C) held 3 then 12 menu frames NEVER triggered
             * CommitGameStateTransition. Bypass the input fn entirely: the decoded
             * CommitGameStateTransition (cycle-137 window) writes r4 to 0x80018088
             * (requested-state cell; kernel data, 0x8002<<16 + 0x8088). The confirm
             * press's ENTIRE effect is SW(0x80018088, cursor+1). We write 1 = FIELD
             * directly, every dispatch while holding. Left in place on release —
             * the kernel consumes the request (idempotent; kernel owns the cell). */
            xenolift_mem[0x18088u + 0] = 0x01;
            xenolift_mem[0x18088u + 1] = 0x00;
            xenolift_mem[0x18088u + 2] = 0x00;
            xenolift_mem[0x18088u + 3] = 0x00;
            /* R643 (c213 trail verdict): channel E fires EVERY dispatch in the hold era
             * and re-stamps cur=-1 + latch=0 AFTER the game's own install already wrote
             * cur=1 (stepper #9) - the state-1 entry then sees pending-forever and the
             * kernel loops back to the menu. The boot-era consumer is gone (channel F
             * hands the mount natively). Disarm after CHANNEL F. */
            if (!xenolift_chanf_fired) {
            /* R384 channel E: cycle-141 proved the commit chain dies mid-hop (its blocks
             * prepared r2=-1 but the SW(92C0,-1) link never executed). Replicate Commit's
             * decoded EFFECT directly - the kernel bootmain restart loop demonstrably consumes
             * 92C0==-1 + req(8088) and mounts the requested state (boot: Commit(6) -> mount 6,
             * Commit(0) -> mount menu, both with cur=-1 at the [gtab] mount probe). */
            xenolift_mem_write32(0x800592BCu, 0u);           /* release latch cleared */
            xenolift_mem_write32(0x800592C0u, 0xFFFFFFFFu); /* transition-pending sentinel */
            }
        }
        /* R380 MINPUT EVIDENCE KIT — cycle-137 verdict: the 3-frame confirm hold
         * fired (press+release logged) but NO CommitGameStateTransition happened
         * (no [phase] r4=1 entry, menu still drawing "Field", cursor 0). Either the
         * button cell is wiped between our dispatch-entry write and the input fn's
         * read, or the input fn is not running in the hold window. These probes
         * print the LIVE cell values AT the input fn's dispatch, watch 0x8006948C
         * + cursor 0x8005F2D8 for value changes with attribution, and trace
         * CommitGameStateTransition entries beyond the [phase] 5-entry cap. */
        if (a == 0x8003FBF8u && r[5] == 0x800282B0u) { /* R382 BODY-LIVENESS: unique to the menu handler body (L_8001A414 sprintf path). If absent while 8001A34C dispatches every frame -> the handler body never executes (dead dispatch entry). */
            static int bodylive_n;
            if (bodylive_n < 12) { bodylive_n++;
                fprintf(stderr, "[minput] BODY-LIVE FormatRuntimeString r4=%08X r5=%08X caller=%06X pstate=%u\n",
                        r[4], r[5], r[31], g_menu_press_state);
            }
        }
        /* R383 CHANNEL D — VIRTUAL CONFIRM EXECUTION (dead-block bypass).
         * Cycle-140 verdict: the handler body is a GHOST — fn_8001A34C dispatches
         * every frame, reads 6948C=0020 during our hold, but its downstream blocks
         * (X check @0x8001A384, confirm @0x8001A3C8, commit call) NEVER dispatch
         * (census lacks them; BODY-LIVE FormatRuntimeString w/ fmt 0x800282B0
         * never fires) — the translated chain dies at its first conditional
         * branch. The commit chain ITSELF works (boot mounts prove it). So at the
         * input fn dispatch during the hold, execute the confirm block's action
         * directly: r4 = cursor+1 -> dispatch fn_8001996C -> latch SW(0x800592D0, 0).
         * One-shot per menu era. */
        if (a == 0x8001A34Cu && g_menu_press_state == 2u && g_menu_frames == 2u /* R389: fire early — cycle 146 proved the mount arms the field async loader; it needs MAX runway, the trigger at frame 11 left only ~40s */) {
            /* R388 CHANNEL F — cycle-145 STATEW camera PROVED the native chain:
             * our button -> handler -> confirm -> commit writes req(8088)=1 and
             * pending-sentinel(92C0)=-1 natively (attributed at fn 80036760), and
             * the sentinel then sits unconsumed all run (boot-only consumer). So
             * the ONLY missing step is the mount itself: hand the kernel's own
             * translated MountGameStateModule (fn_800199CC, boot-proven for
             * state 6) the requested state directly, once, at the last held
             * frame. Channel E removed — the game owns the mailbox now. */
            static uint32_t fmount_done;
            if (!fmount_done) {
                fmount_done = 1u;
                xenolift_chanf_fired = 1u; /* R643: era boundary - channel E stops re-stamping cur=-1 */
                fprintf(stderr, "[minput] CHANNEL F: dispatching MountGameStateModule(1) (Field) — game's own mount machinery, one-shot\n");
                { /* R421 (c178): invalidate the stale staging stamp.
                    * c176-178 chain: (1) staging head 0x800AFC98 stamped 0x7178 (=29048)
                    * by the boot module-7 read (fn 80041534), NO field-era writer
                    * (STGW: 3 writes total, all boot); (2) at crash the kernel is
                    * mid-sequence (file 3 queued, seek=108995) — the module jumped
                    * ahead; (3) the crash decompress used the STALE input fence (the
                    * field wrapper enters the LZSS loop mid-body, skipping entry
                    * probes); (4) the stale 0x7178 coincidentally EQUALS the field
                    * module's expected archive size — its data-ready gate was
                    * satisfied by boot leftovers. FIX: zero head words at mount; if
                    * the module gates on word0==size it now WAITS for the real
                    * module-read; if the gate is elsewhere the zero is harmless
                    * (empty stream = lzss guard bails instead of 52KB of garbage). */
                    uint32_t was = xenolift_mem_read32(0x800AFC98u);
                    xenolift_mem_write32(0x800AFC98u, 0);
                    xenolift_mem_write32(0x800AFC9Cu, 0);
                    xenolift_mem_write32(0x800AFCA0u, 0);
                    xenolift_mem_write32(0x800AFCA4u, 0);
                    fprintf(stderr, "[stg-zero] staging head cleared at CHANNEL F (was %08X - stale boot stamp satisfying the module data-ready gate)\n", was);
                }
                r[4] = 1u;            /* requested state = 1 = Field */
                r[31] = 0x8001A34Cu;  /* plausible return addr */
                xenolift_dispatch(0x800199CCu);
                fprintf(stderr, "[minput] CHANNEL F returned: cur-state(92C0)=%08X req(8088)=%u idx(FAEC)=%08X latch(92BC)=%08X\n",
                        xenolift_mem_read32(0x800592C0u), xenolift_mem_read32(0x80018088u),
                        xenolift_mem_read32(0x8005FAECu), xenolift_mem_read32(0x800592BCu));
            }
        }
        /* R383 block-range probe: does ANY handler block past 0x8001A34C ever
         * dispatch (and to which address)? Root-cause evidence for the emit. */
        if (a >= 0x8001A350u && a < 0x8001A4C0u) {
            static int blk_n;
            if (blk_n < 12) { blk_n++;
                fprintf(stderr, "[minput] BLOCK-RANGE dispatch a=%06X frame=%u pstate=%u r2=%08X r4=%08X\n",
                        a, g_menu_frames, g_menu_press_state, r[2], r[4]);
            }
        }
        /* R393 FIELD-SEEK ASSIST v4 — MENU-FRAME DISPATCH CONTEXT (guaranteed live:
         * minput footage proves 8001A344/34C dispatch EVERY frame through the field
         * stall, frames 3-11+). Cycles 148/149/150: v2 (status-poll ctx) and v3
         * (state-1 dispatch ctx) never fired — the status-poll context goes silent
         * in the stall AND state handlers are direct jumps (invisible to dispatch
         * hooks). Same stall signature, same cure: prime the 3-byte SetLoc answer
         * [02,01,01] (movie-era rspop pattern) + record to cd_last_full + arm
         * INT1 (cd_pending=3) so the native handler-pair machinery converts it. */
        {
            static int fsk_budget = 400;
            if (fsk_budget > 0
                && cd_last_cmd == 0x02u && cd_pending == 0u
                && cd_resp_n < 3u && cd_seek_lba != 0u
                && xenolift_mem[0x4FE1Cu] == 1u
                && xenolift_mem_read32(0x8004FE04u) == cd_seek_lba
                && cd_data_pos >= cd_data_n && !cd_read_active) {
                fsk_budget--;
                cd_resp[0] = 0x02u; cd_resp[1] = 0x01u; cd_resp[2] = 0x01u;
                cd_resp_n = 3; cd_resp_pos = 0;
                memcpy(cd_last_full, cd_resp, sizeof cd_resp); cd_last_full_n = 3;
                cd_pending = 3u; /* INT1 chain — the fd-tick/handler-pair machinery owns conversion */
                fprintf(stderr, "[cd] FIELD-SEEK assist v4 (menu-frame ctx): 3-byte SetLoc answer + INT1 armed (LBA %u, FE1C=%u)\n",
                        cd_seek_lba, xenolift_mem[0x4FE1Cu]);
            }
        }
        /* R395 FIELD-READ ASSIST — the SAME handshake family, next sentence.
         * Cycle 152 PROVED the seek assist: field SetLoc (LBA 108933) fired,
         * state 1->2 walked, and the game issued ReadN (last_cmd=06). Park
         * then froze with the ReadN stat answer sitting UNPOPPED (resp_n=1,
         * resp_pos=0, pending=0, arm1=0): command completion at the HLE queues
         * the stat byte but arms NO INT by itself — the boot-era tick
         * machinery covered this; the field era's doesn't. Movie-era rspop
         * pattern: cmd 06 also consumes the 3-byte [02,01,01] (R263 replay).
         * Same cure as the seek: prime the full answer + arm INT1 in the
         * guaranteed-live menu-frame context. Signature: ReadN issued, state 2,
         * answer unpopped, no INT, no data yet, read length armed (FDF8). */
        {
            static int frd_budget = 400; static int frd_logged;
            if (frd_budget > 0
                && cd_last_cmd == 0x06u && cd_pending == 0u
                && cd_resp_n == 1u && cd_resp_pos == 0u
                && cd_seek_lba != 0u
                && xenolift_mem[0x4FE1Cu] == 2u
                && xenolift_mem_read32(0x8004FE04u) == cd_seek_lba
                && xenolift_mem_read32(0x8004FDF8u) != 0u
                && cd_data_pos >= cd_data_n && !cd_read_active) {
                frd_budget--;
                cd_resp[0] = 0x02u; cd_resp[1] = 0x01u; cd_resp[2] = 0x01u;
                cd_resp_n = 3; cd_resp_pos = 0;
                memcpy(cd_last_full, cd_resp, sizeof cd_resp); cd_last_full_n = 3;
                cd_pending = 3u;
                if (frd_logged < 24) { frd_logged++;
                    fprintf(stderr, "[cd] FIELD-READ assist (menu-frame ctx): 3-byte ReadN answer + INT1 armed (LBA %u, FDF8=%u, FE1C=2)\n",
                            cd_seek_lba, xenolift_mem_read32(0x8004FDF8u));
                }
            }
        }
        /* R392 FIELD-SEEK ASSIST v3 — STATE-1 DISPATCH CONTEXT. Cycles 148/149:
         * the R390 assist (status-poll context) never fired — that context
         * goes silent during the field stall (zero re-primes with last_cmd=02
         * while stalled). The state-1 handler fn_8002A6C0 IS dispatched every
         * frame through the h2 churn (slot footage), so this context is
         * guaranteed-live. Signature: SetLoc issued (last_cmd=02), expected
         * LBA armed and matching seek target, state machine parked at state 1,
         * no INT pending, no data flowing, FIFO short of the 3-byte answer
         * the state-2 transition consumes (movie-era rspop pattern 02/01/01,
         * natively a replayed GetTN triple via R263). */
        if (a == 0x8002A6C0u) {
            if (cd_last_cmd == 0x02u && cd_pending == 0u && cd_resp_n < 3u
                && cd_seek_lba != 0u
                && xenolift_mem[0x4FE1Cu] == 1u
                && xenolift_mem_read32(0x8004FE04u) == cd_seek_lba
                && cd_data_pos >= cd_data_n && !cd_read_active) {
                static int fs_budget = 400;
                if (fs_budget > 0) {
                    fs_budget--;
                    cd_resp[0] = 0x02u; cd_resp[1] = 0x01u; cd_resp[2] = 0x01u;
                    cd_resp_n = 3u; cd_resp_pos = 0u;
                    memcpy(cd_last_full, cd_resp, sizeof cd_resp);
                    cd_last_full_n = 3u;
                    cd_pending = 3u; /* INT1s the established converter pair handles */
                    fprintf(stderr, "[cd] FIELD-SEEK assist v3: state-1 dispatch primed 3-byte SetLoc answer + INT1 (LBA %u, resp_n was %u)\n",
                            cd_seek_lba, cd_resp_n);
                }
            }
        }
        if (a == 0x8001A344u || a == 0x8001A34Cu || a == 0x8001996Cu) {
            static int minput_n;
            if (minput_n < 32) { minput_n++;
                uint32_t pre_948c = ((uint32_t)xenolift_mem[0x6948Cu]) | ((uint32_t)xenolift_mem[0x6948Du] << 8);
                uint32_t pre_94a4 = ((uint32_t)xenolift_mem[0x694A4u]) | ((uint32_t)xenolift_mem[0x694A5u] << 8);
                fprintf(stderr, "[minput] fn=%06X frame=%u pstate=%u | 694A4=%04X 6948C=%04X cursor=%08X r2=%08X r4=%08X\n",
                        a, g_menu_frames, g_menu_press_state,
                        pre_94a4, pre_948c,
                        xenolift_mem_read32(0x8005F2D8u), r[2], r[4]);
            }
        }
        { /* R380 wipe watcher: value-change detection on the confirm cell + cursor */
            static int wipe_n; static uint32_t last_948c = 0xDEADBEEFu; static uint32_t last_f2d8 = 0xDEADBEEFu;
            uint32_t cur_948c = ((uint32_t)xenolift_mem[0x6948Cu]) | ((uint32_t)xenolift_mem[0x6948Du] << 8);
            uint32_t cur_f2d8 = xenolift_mem_read32(0x8005F2D8u);
            if (wipe_n < 24 && (cur_948c != last_948c || cur_f2d8 != last_f2d8)) {
                if (last_948c != 0xDEADBEEFu)
                    fprintf(stderr, "[minput] WIPE-WATCH fn=%06X 6948C: %04X -> %04X cursor: %08X -> %08X\n",
                            a, last_948c, cur_948c, last_f2d8, cur_f2d8);
                wipe_n++;
                last_948c = cur_948c; last_f2d8 = cur_f2d8;
            }
        }
        if (a == 0x8003569Cu && xenolift_mem_read32(0x8004FE1Cu) >= 10u) { /* R373: menu-era-only census - movie-era calls burned the cap in cycle 130 (lesson #7) */
            static int rcb_n = 24;
            if (rcb_n-- > 0)
                fprintf(stderr, "[rcb] ReadControllerButtons entry #%d caller=%08X FE1C=%u FE20=%u\n",
                        25 - rcb_n, r[31],
                        xenolift_mem_read32(0x8004FE1Cu), xenolift_mem_read32(0x8004FE20u));
        }
if (a == 0x80019EF8u) { /* R297: AbortOnGameFault — cycle-45 first firing (code 131 after the X-press intro countdown reached state 1, null-trap at 0x80073B94). Log the fault code + caller. */
        static int abrt_n;
        if (abrt_n < 8) { abrt_n++;
            fprintf(stderr, "[abrt] AbortOnGameFault code=%d caller=0x%08X (X-press intro countdown nulled the never-loaded config render path)\n", (int)(r[4] & 0xFFu), r[31]);
            {   /* R496: context at the game's OWN abort - guest stack +
                 * delivery cells so the digest names what was missing */
                static int abrt_n;
                if (abrt_n++ < 4) {
                    fprintf(stderr, "[abrt] ctx: FE04=%08X FDF8=%08X FE1C=%08X FE20=%08X last_cmd=%02X seek=%u pending=%u data_n=%u\n",
                            xenolift_mem_read32(0x8004FE04u), xenolift_mem_read32(0x8004FDF8u),
                            xenolift_mem_read32(0x8004FE1Cu), xenolift_mem_read32(0x8004FE20u),
                            (unsigned)xenolift_mem[0x4FE48], cd_seek_lba, cd_pending, cd_data_n);
                    if (r[29] >= 0x80010000u && r[29] < 0x801FFF00u)
                        fprintf(stderr, "[abrt] stk: %08X %08X %08X %08X\n",
                                *(uint32_t *)(xenolift_mem + (r[29] - 0x80000000u + 0u)),
                                *(uint32_t *)(xenolift_mem + (r[29] - 0x80000000u + 4u)),
                                *(uint32_t *)(xenolift_mem + (r[29] - 0x80000000u + 8u)),
                                *(uint32_t *)(xenolift_mem + (r[29] - 0x80000000u + 12u)));
                }
            }
        }
    }
    if (a == 0x80039144u) { /* R297: FreeSoundHeapBlock — abort-path cleanup; count calls + args to name the park loop. */
        static int sfree_n; static uint32_t last_arg; static uint32_t same_arg;
        if (sfree_n < 12) { sfree_n++;
            if (r[4] == last_arg) same_arg++;
            last_arg = r[4];
            fprintf(stderr, "[sndfree] #%d FreeSoundHeapBlock(0x%08X)%s\n", sfree_n, r[4], (r[4] < 0x80065B10u || r[4] > 0x8006BE10u) ? " OUT-OF-HEAP" : "");
        } else if (r[4] == last_arg && same_arg == 0xFFFFFFFFu) { }
    }
        if (a == 0x8002ABFCu) { /* R306: shared wrong-slot/fail path for states 10/11 — candidate FE20 advancer */
        static int smfc_n = 24;
        if (smfc_n-- > 0)
            fprintf(stderr, "[smfc] fn_8002ABFC a0=%08X a1=%08X a2=%08X FE1C=%u FE20=%u FE38=%08X gate=%02X caller=%08X\n",
                    r[4], r[5], r[6], xenolift_mem_read32(0x8004FE1Cu), xenolift_mem_read32(0x8004FE20u),
                    xenolift_mem_read32(0x8004FE38u),
                    xenolift_mem[(0x8005A210u-0x80000000u)], r[31]);
    }
if (a == 0x8002A99Cu) { /* state 12 (table[12]) */
        static int sb12 = 24;
        if (sb12-- > 0)
            fprintf(stderr, "[sm12] state-12 entry a0=%u FE1C=%u FE20=%u caller=%08X\n",
                    r[4] & 0xFFu, xenolift_mem_read32(0x8004FE1Cu), xenolift_mem_read32(0x8004FE20u), r[31]);
    }
    if (a == 0x8002AA00u) { /* state 8 (table[8]) */
        static int sb8 = 24;
        if (sb8-- > 0)
            fprintf(stderr, "[sm8] state-8 entry a0=%u FE1C=%u FE20=%u caller=%08X\n",
                    r[4] & 0xFFu, xenolift_mem_read32(0x8004FE1Cu), xenolift_mem_read32(0x8004FE20u), r[31]);
    }
    if (a == 0x80041820u) { /* ladder state-ARMER: writes FE1C=12/6 */
        static int sb18 = 24;
        if (sb18-- > 0)
            fprintf(stderr, "[smarm] fn_80041820 entry a0=%08X a1=%08X a2=%08X FE1C=%u FE20=%u caller=%08X\n",
                    r[4], r[5], r[6], xenolift_mem_read32(0x8004FE1Cu), xenolift_mem_read32(0x8004FE20u), r[31]);
    }
    /* R429 UNLOAD-CAMERA: fn_80037494 releases the font ctx block and
     * zeroes cell 0x80059394 when called with a0 != 0 (no static caller —
     * invoked via runtime pointer). Who calls it decides the fix. */
    if (a == 0x80037494u) {
        static int sb_un = 8;
        if (sb_un-- > 0)
            fprintf(stderr, "[fkunld] fn_80037494 entry a0=%08X caller=%08X ctx69394=%08X ext93A0=%08X\n",
                    r[4], r[31], xenolift_mem_read32(0x80059394u), xenolift_mem_read32(0x800693A0u));
    }
    /* R428 FONTBT JOURNEY CAMERA (hoisted to general dispatch level — R427
     * nested it inside the LegacyCdSectorFetch probe case so it never fired,
     * c185 =FONTBT= empty while ADV shows the builder running). Logs every
     * dispatch into the font-builder range or returning into it: the last
     * callee before the missing ctx-install store names the divergence. */
    if ((a >= 0x800374E8u && a < 0x8003783Cu) ||
        (r[31] >= 0x800374E8u && r[31] < 0x8003783Cu)) {
        static int sb_fb = 48; /* R429: 24 exactly exhausted after one journey */
        if (sb_fb-- > 0)
            fprintf(stderr, "[fontbt] target=%08X caller=%08X r4=%08X r5=%08X r6=%08X r16=%08X ctx=%08X n9390=%08X n9398=%08X n93A0=%08X\n",
                    a, r[31], r[4], r[5], r[6], r[16], xenolift_mem_read32(0x80059394u),
                    xenolift_mem_read32(0x80069390u), xenolift_mem_read32(0x80069398u),
                    xenolift_mem_read32(0x800693A0u));
    }
    if (a == 0x80042AA8u) { /* R328: LegacyCdSectorFetch (PsyQ libcd) — the fn
         * that arms the ch3 CD-DMA per sector ("the kernel issues it before
         * EVERY DMA arm", R106). ZERO [cd-dma] lines ever fire in the movie
         * era while a manufactured sector sits loaded+undrained (pos=0) —
         * either this fetch is never invoked (the caller chain is broken)
         * or it runs and fails before the arm. This probe names which. */
        static int sb32 = 32;
        if (sb32-- > 0)
            fprintf(stderr, "[dmaarm] LegacyCdSectorFetch entry a0=%08X a1=%08X a2=%08X FE1C=%u FE20=%u last_cmd=0x%02X fifo=%u/%u caller=%08X\n",
                    r[4], r[5], r[6], xenolift_mem_read32(0x8004FE1Cu),
                    xenolift_mem_read32(0x8004FE20u), cd_last_cmd,
                    cd_data_pos, cd_data_n, r[31]);
    }
    if (a == 0x8002A99Cu || a == 0x8002AA00u) { /* R300: PAIR-LOOP SUB-HANDLERS.
         * Cycle-49 decode: fn_8002A99C = the sub-handler dispatched by state-11
         * (fn_8002AB28 -> subtable[FE20-1]). With arg==2 it issues FE1C=8 +
         * bytes @0x80069F14/15 (member index from FE38) + cmd 0x0D. With arg!=2
         * it writes FE20=5 = THE POST-PAIR STAGE (the batch advance that has
         * NEVER fired). Log every entry: arg, FE20/FE38, the 0x80069F10 node
         * pair, and the 0x80059F10 queue node — one digest names the advance
         * caller or proves arg!=2 never arrives (-> then the wedge: inject it). */
        static int sub_n = 40;
        if (sub_n-- > 0)
            fprintf(stderr, "[sub] %s a0=%08X FE20=%u FE38=%u node69F10=%08X/%08X q59F10=%08X/%08X caller=%08X\n",
                    a == 0x8002A99Cu ? "fn_8002A99C" : "fn_8002AA00",
                    r[4], xenolift_mem_read32(0x8004FE20u), xenolift_mem_read32(0x8004FE38u),
                    xenolift_mem_read32(0x80069F10u), xenolift_mem_read32(0x80069F18u),
                    xenolift_mem_read32(0x80059F10u), xenolift_mem_read32(0x80059F18u), r[31]);
    }
    if (a == 0x800295D8u) { /* R305: NEW-MODULE READ PATH. State-1 module mounts and orders its big
         * archive files via ReadArchiveMemberIntoBuffer (member, dest). Cycles-52/53: stab size-lookups
         * for dir-0 members fire but no sectors deliver — this probe names the read order + args. */
        static int newmod_n = 30;
        if (newmod_n-- > 0)
            fprintf(stderr, "[newmod] fn_800295D8 member=%u dest=%08X a2=%08X r31=%08X | slots[3]=%u slots[6]=%u FE04=%08X gdisp=%u\n",
                    r[4], r[5], r[6], r[31],
                    xenolift_mem_read32(0x8005642Cu) & 0xFFu, xenolift_mem_read32(0x80056438u) & 0xFFu,
                    xenolift_mem_read32(0x8004FE04u), xenolift_mem_read32(0x80018088u));
         fprintf(stderr, "[stress] read-order member=%u: ring=%08X %08X %08X %08X %08X %08X | 77448=%08X 7711C=%08X 7398=%08X 739C=%08X 77014=%08X 76F04=%08X\n",
                r[4],
                xenolift_mem_read32(0x800773B8u), xenolift_mem_read32(0x800773BCu),
                xenolift_mem_read32(0x800773C0u), xenolift_mem_read32(0x800773C4u),
                xenolift_mem_read32(0x800773C8u), xenolift_mem_read32(0x800773CCu),
                xenolift_mem_read32(0x80077448u), xenolift_mem_read32(0x8007711Cu),
                xenolift_mem_read32(0x80077398u), xenolift_mem_read32(0x8007739Cu),
                xenolift_mem_read32(0x80077014u), xenolift_mem_read32(0x80076F04u));
    }
    if (a == 0x80073B28u) { /* R302: CFG-PTR PROBE. fn_80073B28 a0 = the config
         * buffer ptr (module heap block, filled via ReadArchiveMemberIntoBuffer in fn_800738B0).
         * Log entry args + candidate ptr cells. R304: also CAPTURE r20 = the finale cleanup
         * handle, BEFORE the stage-2 call clobbers it (cycle-52: entry 0x801D3000, trap-time 0). */
        static int cfgptr_n = 20;
        fin_r20_saved = r[20];
        if (cfgptr_n-- > 0)
            fprintf(stderr, "[cfgptr] fn_80073B28 entry a0=%08X a1=%08X a2=%08X r31=%08X r20=%08X | 7745C=%08X | 77454=%08X 77458=%08X 77C5C=%08X 77460=%08X 1F34A8=%08X 6FAF8=%08X\n",
                    r[4], r[5], r[6], r[31], r[20], xenolift_mem_read32(0x8007745Cu),
                    xenolift_mem_read32(0x80077454u), xenolift_mem_read32(0x80077458u),
                    xenolift_mem_read32(0x80077C5Cu), xenolift_mem_read32(0x80077460u),
                    xenolift_mem_read32(0x801F34A8u), xenolift_mem_read32(0x8006FAF8u));
        fprintf(stderr, "[finfree] capture: fn_80073B28 entry r20=%08X (cleanup handle)\n", fin_r20_saved);
    }
    if (a == 0x801D4318u) { /* R302: slice-loop finale stage-2 movie call (countdown==1 path) */
        static int mvfin_n = 12;
        if (mvfin_n-- > 0)
            fprintf(stderr, "[mvfin] fn_801D4318 entry a0=%08X a1=%08X a2=%08X a3=%08X r31=%08X 77014=%u\n",
                    r[4], r[5], r[6], r[7], r[31], xenolift_mem_read32(0x80077014u));
    }
    if (a == 0x80040FB4u) {{   /* R298: BATCH-FINISH WEDGE. Cycle-46 verdict chain: X-press -> countdown
        * 5..1 -> final segment -> teardown frees VALID sound block -> config-init
        * fn_80073B28 derefs NULL cfg ptr (R301: 0x800704E0 is static code, NOT the cfg — the REAL cfg ptr passed to fn_80073B28 is null) ->
        * ReleaseHeapBlock(0) NULL-trap -> AbortOnGameFault(131). Root: the
        * movie config pair = member-1 (88604B, read COMPLETES) + member-2
        * (SIZE 0, LBA 108605) — the read-struct +1C cell went 0->1 when the
        * pair built (boot single-member batches left it 0) = the member-2
        * pending marker, and the FE20 stage oscillates 3<->4 at THIS handler
        * re-walking the pair forever. Hardware completes a size-0 member
        * instantly (zero sectors = zero iterations of the read loop).
        * Wedge: after the oscillation is established (movie phase only),
        * mark member-2 complete (+1C -> 0) ONE-SHOT and let the game's own
        * batch logic advance. Watchers on 59EFC/59F0C/59F14 verify semantics;
        * if +1C is NOT the pending marker, next digest shows the true roles. */
        static uint32_t fe20_osc; static uint32_t batfin_done;
        if (g_movie_live && !batfin_done) {
            uint32_t fe20 = xenolift_mem_read32(0x8004FE20u);
            if (fe20 == 3u || fe20 == 4u) {
                if (++fe20_osc > 8u) { /* R299: cycle-47 measured ~18 toggles/run — 40 never reached; 8 fires mid-oscillation */
                    uint32_t m2 = xenolift_mem_read32(0x80059F14u);
                    fprintf(stderr, "[batfin] FE20 pair-oscillation %u passes — read-struct +1C=%08X +14=%08X +4=%08X\n",
                            fe20_osc, m2, xenolift_mem_read32(0x80059F0Cu), xenolift_mem_read32(0x80059EFCu));
                    if (m2 != 0u) {
                        xenolift_mem_write32(0x80059F14u, 0u);
                        fprintf(stderr, "[batfin] size-0 member-2 marked COMPLETE (+1C -> 0) — batch should advance to parse\n");
                    } else {
                        fprintf(stderr, "[batfin] +1C already 0 — semantics differ, watching\n");
                    }
                    batfin_done = 1;
                }
            }
        }
    }
 /* completion helper: the FE20 3<->4 writer */
        static int sbfb = 16;
        if (sbfb-- > 0)
            fprintf(stderr, "[smfb] fn_80040FB4 entry a0=%08X a1=%08X FE1C=%u FE20=%u caller=%08X\n",
                    r[4], r[5], xenolift_mem_read32(0x8004FE1Cu), xenolift_mem_read32(0x8004FE20u), r[31]);
    }
    if (a == 0x8002A68Cu) {
        static int b = 60;
        if (b-- > 0)
            fprintf(stderr, "[slot] h2 STARTER fn_8002A68C(a0=0x%08X) caller=0x%08X FE04(LBA)=0x%08X FE1C(state)=%u FE20(sub)=%u FDF8=%u FDFC=%u gate(r5=%08X)&0x10=%u gdisp=%u\n",
                    r[4], r[31], xenolift_mem_read32(0x8004FE04u),
                    xenolift_mem_read32(0x8004FE1Cu), xenolift_mem_read32(0x8004FE20u), xenolift_mem_read32(0x8004FDF8u),
                    xenolift_mem_read32(0x8004FDFCu), r[5],
                    (r[5] >= 0x80000000u && r[5] < 0x80200000u) ? (xenolift_mem_read32(r[5]) & 0x10u) >> 4 : 0xFFFFu, xenolift_mem_read32(0x80018088u));
            /* R220: live FAT lookup for every formed request — names what
             * the kernel believes member FE1C is at THIS moment (base/off
             * drift after directory selects is the open question). */
            {
                static int st_fab;
                if (st_fab < 400) {
                    uint32_t mid = xenolift_mem_read32(0x8004FE1Cu);
                    uint32_t tb  = xenolift_mem_read32(0x8004FDF0u);
                    uint32_t of2 = xenolift_mem_read32(0x8004FE14u);
                    if (mid != 0u && tb >= 0x80000000u) {
                        uint32_t ep = tb + (mid + of2 - 1u) * 7u;
                        uint32_t pp = ep & 0x1FFFFFFFu;
                        if (pp + 7u < XENOLIFT_RAM_SIZE) {
                            const uint8_t *e2 = xenolift_mem + pp;
                            uint32_t lb = e2[0] | (e2[1] << 8) | (e2[2] << 16);
                            uint32_t sz = e2[3] | (e2[4] << 8) | (e2[5] << 16) | ((uint32_t)e2[6] << 24);
                            st_fab++;
                            fprintf(stderr, "[stab] req member=%u base=0x%08X off=%u entry=0x%08X LBA=%u size=%u gdisp=%u\n",
                                    mid, tb, of2, ep, lb, sz, xenolift_mem_read32(0x80018088u));
                        }
                    }
                }
            }
    }
    if (a == 0x8003A68Cu || a == 0x8003B084u) {
        static int b = 12;
        if (b-- > 0)
            fprintf(stderr, "[slot] CD callback 0x%08X(a0=0x%08X) caller=0x%08X FE1C(file#)=%u\n",
                    a, r[4], r[31], xenolift_mem_read32(0x8004FE1Cu));
    }
    /* R131 success hook (HANDLER_MAP decode): the boot handler jalrs
     * into Module 6 entry 0x800737EC (ra=0x80019C0C) once the CD has
     * populated the overlay. Reaching here = the boot wall is BROKEN. */
    if (a == 0x800737ECu) {
        g_mod6_live = 1; /* R253: movie module actually entered */
        static int b = 10;
        if (b-- > 0) {
            /* R143 (Jos directive 07:41): register sanity at Module-6
             * entry. Module 6 = MOVIE overlay (qa/OVERLAY_SYMBOLS.md:
             * movie.bin, 29,779B decompressed @0x8006FAF0, entry =
             * MovieModuleEntry). Overlays link against KERNEL data
             * via $gp — if gp is not the kernel gp (0x8005xxxx) every
             * data access inside the module reads garbage and the
             * module silently faults back to boot main. Also snapshot
             * the fd drive-state struct: the Movie module runs the
             * CD read STRESS TEST + READBACK VERIFICATION, so any
             * drive-state mirroring drift makes it abort+restart. */
            fprintf(stderr, "[mod6] MODULE 6 ENTRY REACHED 0x800737EC caller=0x%08X — overlay module executing, boot wall BROKEN\n", r[31]);
            fprintf(stderr, "[mod6] REGS gp=%08X%s sp=%08X ra=%08X\n",
                    r[28], ((r[28] >> 16) == 0x8005u) ? "(kernel-gp OK)" : "(*** GP NOT KERNEL 0x8005xxxx! ***)",
                    r[29], r[31]);
            fprintf(stderr, "[mod6] DRIVE-STATE: ptr5677C=%08X slotbits56788=%08X FE04(LBA)=%08X FDF8(size)=%08X FE1C(file#)=%08X\n",
                    xenolift_mem_read32(0x8005677Cu), xenolift_mem_read32(0x80056788u),
                    xenolift_mem_read32(0x8004FE04u), xenolift_mem_read32(0x8004FDF8u),
                    xenolift_mem_read32(0x8004FE1Cu));
        }
    }
    /* R143 (Jos directive 07:41): Module 6 = MOVIE overlay = a CD-ROM
     * diagnostic suite (qa/OVERLAY_SYMBOLS.md). Hook the named Movie
     * functions so the next digest shows WHICH diagnostics run and in
     * what order — the readback verification path is the prime
     * suspect for the boot-main restart loop. */
    {
        static const struct { uint32_t a; const char *n; } mv[] = {
            { 0x800704E8u, "MovieRunCdReadStressTestScreen" },
            { 0x80070DCCu, "MovieUpdateCdReadStressTest" },
            { 0x800712C4u, "MovieAdvanceCdReadVerification" },
            { 0x80071BA0u, "MovieQueueRandomSectorRead" },
            { 0x80071C34u, "MovieStartCdReadTestOperation" },
            { 0x80072428u, "MovieAdvanceCdStressVSyncClock" },
            { 0x80072480u, "MovieRunDiscChangeTest" },
            { 0x8007293Cu, "MovieReinitializeCdAfterDiscChange" },
        };
        int mi;
        for (mi = 0; mi < 8; mi++) {
            if (a == mv[mi].a) {
                static int mlog[8];
                if (mlog[mi] < 6) {
                    mlog[mi]++;
                    fprintf(stderr, "[movie] %s entered (call #%d) caller=0x%08X\n",
                            mv[mi].n, mlog[mi], r[31]);
                }
            }
        }
    }
    { /* R149 (MODULE_PREMAP.md + STR_PIPELINE.md execution): watch the
         * five module phase callbacks + the movie PLAYER chain. The
         * phase table is LIVE-verified (R147 Mac =PHASE=): [1]=Field
         * 0x80077E88, [2]=Battle 0x8001B6C4, [3]=WorldMap 0x80070CFC,
         * [4]=Battling 0x80088E90, [5]=Menu 0x8001C634, [6]=Movie
         * 0x800737EC. NOTE (MODULE_PREMAP): the Menu overlay PAYLOAD
         * loads at 0x801C5000 — OUTSIDE the 0x8006F000-0x8008FFFF
         * capture window; when [menu] fires we need a SECOND capture
         * window at 0x801C0000+. STR_PIPELINE.md: MovieRunPlayback
         * 0x80076488 feeds MDEC slices via DMA ch0/ch1 with
         * MovieDecodeSliceCallback 0x800768D8 advancing frame state. */
        static const struct { uint32_t a; const char *n; } pv[] = {
            { 0x80077E88u, "FIELD RunFieldCoordinator" },
            { 0x8001B6C4u, "BATTLE RunBattleAndDispatchOutcome" },
            { 0x80070CFCu, "WORLDMAP overlay entry" },
            { 0x80088E90u, "BATTLING BattlingMain" },
            { 0x8001C634u, "MENU RunResidentMenu" },
            { 0x800763BCu, "MovieLaunchScriptedMovie" },
            { 0x80076488u, "MovieRunPlayback" },
            { 0x800768D8u, "MovieDecodeSliceCallback" },
            { 0x800769A4u, "MoviePollSkipInput" },
            { 0x8007670Cu, "MOVIE SliceLoopA" },
            { 0x800767DCu, "MOVIE SliceLoopB" },
        };
        int pi;
        for (pi = 0; pi < 11; pi++) {
            if (a == pv[pi].a) {
                static int plog[11]; static uint32_t pcount[11]; /* R254: was [9] for 11 entries = OOB write */
                pcount[pi]++;
                if (pi >= 5 && pi <= 7 && !g_movie_live) { /* Launch/RunPlayback/SliceCb */
                    g_movie_live = 1;
                    fprintf(stderr, "[mvloop] MOVIE PLAYER LIVE via %s caller=0x%08X — stuck detector ARMED\n", pv[pi].n, r[31]);
                }
                if (plog[pi] < 8 || (pcount[pi] % 65536u) == 0u) /* R264: cycle-12 flood — 919k entries x every-500th = 1800 lines/fn in the last 200KB alone */
                    fprintf(stderr, "[phasecb] %s entered (#%u) caller=0x%08X\n",
                            pv[pi].n, pcount[pi], r[31]);
            }
            if (pv[pi].a == 0x800769A4u) {
                /* R231: sp-corruption hunt. Cycle-17 crash regs: sp=0x807FC910
                 * but the true kernel-frame sp should be ~0x801FC910 (kernel
                 * top 0x80200000 minus frames) = off by EXACTLY 0x600000, a
                 * corrupted hi-digit. Log sp/ra/gp at every poll entry to
                 * learn if sp is already bad at entry #1 (module entry bug)
                 * or degrades across polls (mid-loop corruption), plus the
                 * fn's four working cells (0x80076F04/08 counter+limit,
                 * 0x800773AC/B4 call token) and the data cells at r5. */
                static int b = 12;
                if (b-- > 0)
                    fprintf(stderr, "[phasecb] SKIP-POLL sp=0x%08X ra=0x%08X gp=0x%08X r4=%u r5=0x%08X cnt=%u lim=%u tokA=%08X tokB=%08X\n",
                            r[29], r[31], r[28], r[4], r[5],
                            xenolift_mem_read32(0x80076F04u),
                            xenolift_mem_read32(0x80076F08u),
                            xenolift_mem_read32(0x800773ACu),
                            xenolift_mem_read32(0x800773B4u));
            }
            if (pv[pi].a == 0x8007670Cu || pv[pi].a == 0x800767DCu) {
                { /* R325 countdown timeline: the skip countdown 77014 ran 5->4->3->2->1
                     * (FSMHIST) and stalls at 1 - log EVERY transition with its context so
                     * the digest names the missing condition for the final 1->0 tick. */
                    static uint32_t cntdn_prev = 0x41414141u;
                    uint32_t cntdn = xenolift_mem_read32(0x80077014u);
                    if (cntdn != cntdn_prev) {
                        fprintf(stderr, "[cntdn] 77014 %u -> %u @%s | frame(76F04)=%u pass(77448)=%u FE1C=%u FE20=%u FDF8=%u last_cmd=0x%02X\n",
                                cntdn_prev, cntdn, (pv[pi].a == 0x8007670Cu ? "SliceLoopA" : "SliceLoopB"),
                                xenolift_mem_read32(0x80076F04u), xenolift_mem_read32(0x80077448u),
                                xenolift_mem_read32(0x8004FE1Cu), xenolift_mem_read32(0x8004FE20u),
                                xenolift_mem_read32(0x8004FDF8u), cd_last_cmd);
                        cntdn_prev = cntdn;
                    }
                }
                /* R249: movie slice-loop NON-PROGRESS detector. Cycle-1 of
                 * the R248 lab hung to the watchdog in this pair (native
                 * backtrace alternating fn_8007670C/fn_800767DC seven+ deep,
                 * each pass entering WaitForVerticalRetrace with a POISONED
                 * sp stripped by the R244 entry fix, caller 0x80076768). The
                 * pair is the movie render slice chain: on hardware each
                 * pass advances the poll frame counter 0x80076F04; a pass
                 * that does NOT advance it is waiting on a condition that
                 * never fires (prime suspect: MDEC slice delivery,
                 * STR_PIPELINE.md gap 1 - hle_mdec is synchronous). If 96
                 * pair entries pass with the counter frozen, dump the full
                 * loop state and HALT named - a 30-second diagnosis instead
                 * of a 420s hang. */
                static uint32_t mv_n, mv_last, mv_same, mv_seen_active;
                uint32_t rs0 = xenolift_mem_read32(0x80077180u);
                uint32_t lim = xenolift_mem_read32(0x80076F08u);
                mv_n++; mv_pass_now = mv_n; /* R263 */
                if ((mv_n & 0xFFFu) == 0u) vb_topup_60hz(); /* R317: throttled — per-call clock_gettime ate ~30% of the loop */
                /* R258 CONTEXT-INDEPENDENT INT1 DELIVERY (R137 lesson, movie
                 * edition): R257 cycle-6 = player LIVE, 4.89M loop passes in
                 * 46s, but the stage-2 read's 2nd 64KB chunk sat with INT1
                 * pending (seek 108593, FDF8=23068, FIFO drained, arm1=0) —
                 * the movie loop never enters the kernel collector contexts
                 * where fd-tick converts INTs. Hardware IRQs preempt anywhere;
                 * so deliver from here every 256 passes. */
                if (g_movie_live && (mv_n & 0xFFu) == 0u && cd_read_active
                    && cd_arm_int1_pending == 0u
                    && (cd_pending != 0u || (cd_data_loaded && cd_data_pos == 0u
                                             && xenolift_mem_read32(0x8004FDF8u) != 0u)))
                    cd_force_deliver_int1("mvloop"); /* R261: FDF8 gate — cycle-9 fired 23,552x on the leftover sector after the read completed */
                /* R260: SCHEDULED RESPONSE too (cycle-8: stage-2 load DONE, FDF8=0,
                 * kernel issued Pause 0x09 → INT3 scheduled (sched=1, pending=0)
                 * but the virtual-INT3 delivery is gated on kernel contexts
                 * 0x8004B894/0x8004293C the movie loop never visits; it VSync-
                 * spins waiting for the Pause completion. Deliver the same way
                 * (set pending=3 + op flag) then run the collector chain. */
                if (g_movie_live && (mv_n & 0xFFu) == 0x80u && cd_scheduled && cd_pending == 0u) {
                    static uint32_t fs_n;
                    cd_restore_pend(); /* R308: central (was R307 mv inline) */
                    cd_scheduled = 0;
                    cd_pending = 3;
                    if (!cd_flag_suppressed(cd_last_cmd)) {
                        uint16_t one = 1;
                        memcpy(xenolift_mem + (0x800578A6u & 0x1FFFFFFFu), &one, 2);
                    }
                    if (++fs_n <= 16u || (fs_n % 64u) == 0u)
                        fprintf(stderr, "[cdf] force-sched #%u: cmd 0x%02X INT3 delivered from movie loop (pending=3)\n", fs_n, cd_last_cmd);
                    cd_force_deliver_int1("mvloop-sched");
                }
                if (mv_n <= 4u)
                    fprintf(stderr, "[mvloop] slice-pair entry #%u fn=0x%08X ra=0x%08X r4=0x%08X r5=0x%08X r17=0x%08X r18=0x%08X\n",
                            mv_n, pv[pi].a, r[31], r[4], r[5], r[17], r[18]);
                /* R250 MOVIE-ACTIVE GATE (cycle-2 lesson): the kernel polls
                 * the state-6 callback chain (slice pair included) every
                 * display pass for the WHOLE boot, with the module data
                 * legitimately all-zero until a movie actually plays - the
                 * R249 cap misread this healthy pre-movie polling as a stuck
                 * loop and killed a 1-second-old boot. Stuck evaluation ONLY
                 * arms once the render struct head or the poll limit cell is
                 * nonzero = the movie pipeline is configured. */
                if (!g_movie_live || (rs0 == 0u && lim == 0u) || lim > 0x10000u
                    || cd_read_active || xenolift_mem_read32(0x8004FDF8u) != 0u
                    || !((r[31] >= 0x8006F000u && r[31] < 0x80090000u) || (r[31] >= 0x801D3000u && r[31] < 0x801F4000u))) {
                    /* R257: (a) never judge while a CD read is in flight (R256
                     * cycle-5: stage-2 load streaming 32/44 sectors, frame
                     * counter legitimately frozen, r31=0x801D4430 inside the
                     * freshly loaded stage-2 code — the module was LOADING,
                     * not stalled); (b) only count REAL loop passes: the
                     * caller must be module/stage-2 code (65k phantom
                     * entries with ra=0/boot-main polluted the counter). */
                    /* R254: R253 armed on MODULE ENTRY — too early: the render
                     * sheet still held file-2/3 archive data (rs0=0C16EC56,
                     * lim=4007658019) → false STUCK 1s after module 6 entered.
                     * Now anchored to the movie PLAYER chain starting
                     * (Launch/RunPlayback/SliceCb) + a sane poll limit. */
                    /* R253 FALSE-ALARM FIX: R252 cycle-1 halted a HEALTHY boot at
                     * 1s — the file-2/3 CD DMA (LBA 108766+ → 0x80075AF8..)
                     * wrote archive data over 0x80077180/0x80076F04 BEFORE the
                     * movie module existed → "render struct nonzero + frame
                     * counter frozen" = file data, not a movie stall. Stuck
                     * evaluation now ALSO requires MovieModuleEntry seen. */
                    g_mv_poll_n = mv_n;
                    { /* R394 MOVIE-ERA INT CONVERSION — cycle 151: assist v4 FIRED
                     * (unblocked the boot file-7 seek) and the run flew into the
                     * native movie era (movie-poll 800M+ iterations) — but parked
                     * with the primed 3-byte SetLoc answer (resp_n=3) + pending=3
                     * UNCONSUMED: every existing conversion context (fd-tick,
                     * spin-conv leaf-spin) is dead in the movie loop. THIS branch
                     * runs every movie-poll pass (proven live all era) — convert
                     * the pending INT here via the proven handler pair, full
                     * register save/restore (R160 pattern), cadence 4096 polls,
                     * own budget, log head 12. */
                        static uint32_t mv_conv_budget = 2000u;
                        static int mv_conv_logged;
                        if (cd_pending != 0u && cd_arm_int1_pending == 0u
                            && mv_conv_budget > 0u && (mv_n % 4096u) == 0u) {
                            static int mv_conv_busy;
                            if (!mv_conv_busy) {
                                uint32_t sr[32]; uint32_t shi, slo;
                                mv_conv_busy = 1;
                                memcpy(sr, r, sizeof r); shi = hi; slo = lo;
                                r[4] = 0; r[5] = 0;
                                cd_restore_pend();
                                if (mv_conv_logged < 12) {
                                    mv_conv_logged++;
                                    fprintf(stderr, "[cd] mv-conv: converting pending INT (%u) via handler pair (movie-loop ctx, n=%u FE1C=%u)\n",
                                            cd_pending, mv_n, xenolift_mem_read32(0x8004FE1Cu));
                                }
                                xenolift_dispatch(0x800409E4u);
                                xenolift_dispatch(0x80040A4Cu);
                                xenolift_dispatch(0x800415B4u);
                                memcpy(r, sr, sizeof r); hi = shi; lo = slo;
                                mv_conv_busy = 0;
                                mv_conv_budget--;
                            }
                        }
                    }
                    if ((mv_n % 4096u) == 0u && (mv_n < 65536u || (mv_n % 1048576u) == 0u)) /* R313: dense head, then 1M stride */
                        fprintf(stderr, "[mvloop] pre-movie polling n=%u (mod6=%d player=%d rs0=%08X lim=%u - benign, no halt)\n", mv_n, g_mod6_live, g_movie_live, rs0, lim);
                    /* R252 REGRESSION FIX: R250's early `return` here exited
                     * xenolift_trace before the CD event-delivery machinery
                     * further down could run — the slice pair polls 65k+ times
                     * per boot, starving the delivery → boot stalled in the
                     * GetStat treadmill at 16s (R250 cycle-1). Pre-movie
                     * polling now simply skips stuck-evaluation and FLOWS ON. */
                } else {
                    mv_seen_active++;
                    if ((mv_n & 31u) == 0u) {
                        uint32_t c = xenolift_mem_read32(0x80076F04u);
                        if (c == mv_last) mv_same++;
                        else { mv_same = 0; mv_last = c; }
                        /* R263: the CD layer trading commands = the player is WORKING
                         * (cycle-11 died at 1s mid GetTN/GetStat exchange). Hold the
                         * verdict while a command completed within the last 4096 passes. */
                        if (mv_same >= 3u && (mv_n - mv_last_cd_pass) > 4096u) {
                            int di;
                            fprintf(stderr, "[mvloop] STUCK after %u slice-pair entries (active-phase %u) - frame counter 0x80076F04 frozen at %u\n", mv_n, mv_seen_active, c);
                            fprintf(stderr, "[mvloop] cells F04=%08X F08=%08X r17cell(0x800773C0)=%08X r18cell(0x800773C4)=%08X tokA=%08X tokB=%08X\n",
                                    xenolift_mem_read32(0x80076F04u), xenolift_mem_read32(0x80076F08u),
                                    xenolift_mem_read32(0x800773C0u), xenolift_mem_read32(0x800773C4u),
                                    xenolift_mem_read32(0x800773ACu), xenolift_mem_read32(0x800773B4u));
                            fprintf(stderr, "[mvloop] render struct @0x80077180:");
                            for (di = 0; di < 16; di++)
                                fprintf(stderr, " %08X", xenolift_mem_read32(0x80077180u + 4u * (uint32_t)di));
                            fprintf(stderr, "\n");
                            fprintf(stderr, "[mvloop] drv triple 568C4=%08X 568C8=%08X 568CC=%08X\n",
                                    xenolift_mem_read32(0x800568C4u), xenolift_mem_read32(0x800568C8u), xenolift_mem_read32(0x800568CCu));
                            /* R336: HALT RETIRED. This detector (R249-era, when the slice
                             * loop was genuinely dead at 96 entries) killed cycle-84 at 4s:
                             * R335's zrf state-6 serve RELEASED the loop into its skip
                             * phase, where the frame counter freezes BY DESIGN between
                             * re-arms and the drive goes quiet between orders — the
                             * detector read that healthy lull as death and cut the run
                             * before the assist clocks could fire. The 195s budget
                             * watchdog is the single park authority now; it emits the
                             * full park dump with the same cells. One diagnostic note
                             * per run, no halt. */
                            {
                                static int mvstuck_noted;
                                if (!mvstuck_noted) {
                                    mvstuck_noted = 1;
                                    fprintf(stderr, "[mvloop] R336: frame-counter lull noted (skip-phase freeze is expected; run continues to budget)\n");
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    /* R144 (BIOS_THUNK_AUDIT.md #1 at-risk): ChangeClearRCnt
     * C0:0x0A — configures root-counter auto-clear modes. Unhandled in
     * our bios gate (v0=0 default). If the pump park is a root-counter
     * wait, these args name the counter+mode the kernel expects. */
    if (a == 0x8004B730u) {
        static int b = 12;
        if (b-- > 0)
            fprintf(stderr, "[rcnt] ChangeClearRCnt rc=%u mode=%08X arg=%08X caller=0x%08X\n",
                    r[4], r[5], r[6], r[31]);
    }
    if (a == 0x80028470u) {
        static int b = 16;
        if (b-- > 0)
            fprintf(stderr, "[arc] SelectArchiveDirectoryEntry a0=0x%08X a1=0x%08X dirtable=0x%08X off_now=%u caller=0x%08X\n",
                    r[4], r[5], xenolift_mem_read32(0x8004FDF4u),
                    xenolift_mem_read32(0x8004FE14u), r[31]);
    }
    if (a == 0x80029AFCu) {
        static int b = 8;
        if (b-- > 0)
            fprintf(stderr, "[arc] ArchiveStartQueuedReads entered caller=0x%08X FDFC=%u FE10=%u\n",
                    r[31], xenolift_mem_read32(0x8004FDFCu), xenolift_mem_read32(0x8004FE10u));
    }
    if (a == 0x80028738u && r[4] >= 12 && r[4] < 64) {
        static int b = 12;
        if (b-- > 0) fprintf(stderr, "[ftab] size-lookup fn_80028738(file#=%u) caller=0x%08X\n", r[4], r[31]);
    }
    if (a == 0x8002AC24u) { /* R352: ArchiveQueuedReadReadyCallback — consumes ready sectors; with FE34=0/FDF8=0 routes to fn_8002AD4C (queue advance to next destination = file 14). Camera: does it EVER run, and with what arg? */
        static int arc_cb_n;
        if (arc_cb_n < 24) {
            arc_cb_n++;
            fprintf(stderr, "[arccb] fn_8002AC24 entry arg=%02X FE34=%u FE38=%u FE3C=%u FDF8=%u FDE8=%u A4DC=%u caller=%08X\n",
                    r[4] & 0xFFu, xenolift_mem_read32(0x8004FE34u), xenolift_mem_read32(0x8004FE38u),
                    xenolift_mem_read32(0x8004FE3Cu), xenolift_mem_read32(0x8004FDF8u),
                    xenolift_mem_read32(0x8004FDE8u), xenolift_mem_read32(0x8006A4DCu), r[31]);
        }
    }
    if (a == 0x800413ECu) { /* R353: SetCdSectorCallback — what gets REGISTERED as the CD ready callback. fn_8002AC24 (the queue-advance owner) never ran in cycle-101: if nothing ever registers it, the advance has no caller. */
        static int cbr_n;
        if (cbr_n < 40) {
            cbr_n++;
            fprintf(stderr, "[cbreg] SetCdSectorCallback(a0=%08X) caller=%08X FE1C=%u FE04=%08X\n",
                    r[4], r[31], xenolift_mem_read32(0x8004FE1Cu), xenolift_mem_read32(0x8004FE04u));
        }
    }
    if (a == 0x8002AD4Cu) { /* R352: the queue-ADVANCE path (ready callback, no active destination) — this is where file 14 should get handed the disc. */
        static int adv_n;
        if (adv_n < 24) {
            adv_n++;
            fprintf(stderr, "[arcadv] fn_8002AD4C entry r4=%08X r5=%08X FE04=%08X FDF8=%u caller=%08X\n",
                    r[4], r[5], xenolift_mem_read32(0x8004FE04u), xenolift_mem_read32(0x8004FDF8u), r[31]);
        }
    }
    if (a == 0x800288ECu && g_field_era) { /* R348: field-era FE04 seeding — file 14 (LBA 108933) must get stamped here; empty = seed never runs for the field read */
        static int ffs_n;
        if (ffs_n < 16) {
            ffs_n++;
            fprintf(stderr, "[seed] fn_800288EC FIELD entry a0=%08X a1=%08X a2=%08X caller=%08X FE04=%08X FDF8=%08X\n",
                    r[4], r[5], r[6], r[31], xenolift_mem_read32(0x8004FE04u), xenolift_mem_read32(0x8004FDF8u));
        }
    }
    if (a == 0x800288ECu && g_movie_live) { /* R343: fn_800288EC seeds FE04 (cycle-91 FE04W: seeds boot file bases; movie-era seed 0x1A831=108593 = 119 sectors past last STR file end 108474). Log every movie-era seeding with inputs + read struct + queue node. */
        static int fs_n;
        if (fs_n < 12) {
            fs_n++;
            fprintf(stderr, "[feseed] fn_800288EC movie-era entry a0=%08X a1=%08X a2=%08X caller=%08X FE04=%08X | rstruct 59EF8: %08X %08X %08X %08X %08X %08X %08X %08X | node 59F10: %08X %08X %08X %08X\n",
                    r[4], r[5], r[6], r[31], xenolift_mem_read32(0x8004FE04u),
                    xenolift_mem_read32(0x80059EF8u), xenolift_mem_read32(0x80059EF8u + 4), xenolift_mem_read32(0x80059EF8u + 8), xenolift_mem_read32(0x80059EF8u + 12),
                    xenolift_mem_read32(0x80059EF8u + 16), xenolift_mem_read32(0x80059EF8u + 20), xenolift_mem_read32(0x80059EF8u + 24), xenolift_mem_read32(0x80059EF8u + 28),
                    xenolift_mem_read32(0x80059F10u), xenolift_mem_read32(0x80059F10u + 4), xenolift_mem_read32(0x80059F10u + 8), xenolift_mem_read32(0x80059F10u + 12));
        }
    }
    if (a == 0x80029690u && r[4] >= 12 && r[4] < 64) {
        /* R155: snapshot the freshly-issued request before anything
         * can overwrite its register cells. */
        xenolift_kick2_lba = xenolift_mem_read32(0x8004FE04u);
        xenolift_kick2_len = xenolift_mem_read32(0x8004FDF8u);
        xenolift_kick2_armed = 1;
        xenolift_kick2_ticks = 0;
        static int b = 12;
        if (b-- > 0) fprintf(stderr, "[ftab] READ ISSUED fn_80029690(file#=%u dst=0x%08X a2=0x%08X a3=0x%08X) LBA cell FE04=0x%08X size cell FDF8=%u\n",
                r[4], r[5], r[6], r[7], xenolift_mem_read32(0x8004FE04u), xenolift_mem_read32(0x8004FDF8u));
        { /* R137: new-territory read watcher — the R136 Mac staged a
           * read with FE04=0x3A6D5 (LBA 239317, deep game-data) that
           * no digest section caught. Flag every read outside the
           * known boot range. */
            uint32_t lba_cell = xenolift_mem_read32(0x8004FE04u);
            if (lba_cell != 0u && (lba_cell < 108804u || lba_cell > 109165u))
                fprintf(stderr, "[newread] NEW-TERRITORY READ file#=%u LBA=%u size=%u dst=0x%08X\n",
                        r[4], lba_cell, xenolift_mem_read32(0x8004FDF8u), r[5]);
        }
    }
    /* R675: STATE-1 CB RETURN cam - c246 proved 80019C0C is the return site
     * after table[1]=80077E88 runs (ovlcb caller=80019C0C). Shows whether the
     * field cb completes and what state the loop sees right after. */
    if (a == 0x80019C0Cu) {
        static uint32_t r675r;
        if (r675r < 8u) {
            r675r++;
            fprintf(stderr, "[mtrans] R675 STATE-1 CB RETURN #%u @t=%lds: idx=%u cur=%u req=%u F0C=%u FDF8=%u FE1C=%u FE20=%u 92BC=%u r31=%08X\n",
                    r675r, (long)(time(NULL) - g_boot_wall_t0),
                    xenolift_mem_read32(0x8005FAECu), xenolift_mem_read32(0x800592C0u),
                    xenolift_mem_read32(0x80018088u), xenolift_mem_read32(0x80059F0Cu),
                    xenolift_mem_read32(0x8004FDF8u), xenolift_mem_read32(0x8004FE1Cu),
                    xenolift_mem_read32(0x8004FE20u), xenolift_mem_read32(0x800592BCu),
                    (unsigned)r[31]);
        }
    }
    if (a == 0x80031F58u) {
        /* R183: the allocator's common exit (original 0x80031F58 reached via
         * take-success gp+0x1C0 nonzero AND via the carve block at 0x80031E60
         * j). v0 (r2) = the block handed back to the caller -> LZSS dest.
         * Cycle-16: the carve math at 0x80031E00-E64 builds words via
         * (a0<<26)|(v1&0xF)<<21 halfword-assembly and STORES through
         * v0 = LW(node)-s1-8 — the 0xC2C0CBA5 poison class. Log the handoff. */
        static int exit_n;
        if (exit_n < 16) {
            exit_n++;
            fprintf(stderr, "[hand] #%d v0(r2)=0x%08X a0(r4)=0x%08X a1(r5)=0x%08X a2(r6)=0x%08X s0(r16)=0x%08X s1(r17)=%u s5(r21)=0x%08X gp1C0=0x%08X\n",
                    exit_n, r[2], r[4], r[5], r[6], r[16], r[17], r[21],
                    xenolift_mem_read32(0x80059170u + 0x1C0u));
        }
        /* R232: STAGE-2 STACK-TOP HANDOFF FIX. Cycle-18 proof chain:
         * SKIP-POLL shows MoviePollSkipInput enters with a HEALTHY sp
         * (0x801FFFC8) every iteration; the crash sp = 0x807FC8C8/0x807FC910
         * = kernel stack top 0x80200000 MINUS ~0x36F0 of frames PLUS
         * EXACTLY 0x600000 of poison. The poison source = hand #13: the
         * allocator exit hands the stage-2 module (v0=0x801D3000) its
         * config args a1=0x80800000 / a2=0x00800000 = the TRUE stack-top
         * 0x80200000 and span 0x00200000 with bits 21/22 (0x600000)
         * tag-poisoned — the stage-2 slice chain then reloads sp from the
         * stored 0x80800000-class stack-top and every pointer built on it
         * chases garbage (the varying wild derefs). HLE correction: when
         * the handoff's handed-back block is the stage-2 window and the
         * stack-top arg is out of RAM, restore the PROVEN-correct pair
         * (0x80200000 / 0x00200000 — [postres] shows the kernel's own sp
         * at dispatch = 0x80200000, and the span is the full 2MB RAM). */
        if (r[2] >= 0x801D3000u && r[2] < 0x801F4000u
            && r[5] != 0u && (r[5] < 0x80000000u || r[5] >= 0x80200000u)) {
            static int fix_n;
            if (fix_n < 8) {
                fix_n++;
                fprintf(stderr, "[hand-fix] #%d stage-2 handoff stack-top POISONED (a1=0x%08X a2=0x%08X) -> restoring 0x80200000 / 0x00200000\n",
                        fix_n, r[5], r[6]);
            }
            r[5] = 0x80200000u;
            r[6] = 0x00200000u;
        }
    }
    if (a == 0x80031DA8u) {
        /* R182: the TAKE path — cycle-15: chunk 0x800B06FC's header flips
         * 0x84000000 -> 0x84020200 (flags 0x00200000 = the take marker)
         * after the module-read alloc; the walker takes THAT chunk and the
         * carve computes garbage (Coalesce arg 0xC2C0CBA5) -> LZSS writes
         * wild -> 0xFFFF93D4. Log the take inputs + Coalesce args. */
        static int take_n;
        if (take_n < 12) {
            take_n++;
            uint32_t node = r[10];
            uint32_t w0 = (node >= 0x80000000u && node < 0x80200000u) ? xenolift_mem_read32(node) : 0u;
            uint32_t w1 = (node >= 0x80000000u && node < 0x80200000u) ? xenolift_mem_read32(node + 4u) : 0u;
            fprintf(stderr, "[take] #%d node=0x%08X w0=0x%08X w1=0x%08X r2=0x%08X r5=0x%08X r6=0x%08X r16=0x%08X r17(want)=%u r21=0x%08X\n",
                    take_n, node, w0, w1, r[2], r[5], r[6], r[16], r[17], r[21]);
        }
    }
    if (a == 0x80031FF8u) {
        static int coal_n;
        if (coal_n < 12) {
            coal_n++;
            fprintf(stderr, "[coal] #%d r4(a0)=0x%08X r5=0x%08X r6=0x%08X r28(gp)=0x%08X r2=0x%08X\n",
                    coal_n, r[4], r[5], r[6], r[28], r[2]);
        }
    }
    if (a == 0x80031D9Cu) {
        /* R177: free-list walk hop trace. Cycle-12's ring showed the walk
         * stepping through DECOMPRESS DESTS (0x801FC000/0x801FA634/0x801F34B4).
         * At this hop: r10 = current node, next = LW(r10) - 8. Log the hop
         * so the digest names the exact node whose word0 is game data. */
        static int walk_n;
        if (walk_n < 64) {
            walk_n++;
            uint32_t node = r[10];
            uint32_t tag = (node >= 0x80000000u && node < 0x80200000u)
                ? xenolift_mem_read32(node) : 0xDEAD0000u;
            uint32_t w1 = (node >= 0x80000000u && node < 0x80200000u)
                ? xenolift_mem_read32(node + 4u) : 0u;
            uint32_t gp = r[28];
            uint32_t head = (gp >= 0x80000000u && gp < 0x80200000u)
                ? xenolift_mem_read32(gp + 0x1B0u) : 0u;
            fprintf(stderr, "[walk] hop %d: node=0x%08X tag=0x%08X w1=0x%08X flags=0x%02X chunk=0x%08X want=%u gp=0x%08X head=0x%08X\n",
                    walk_n, node, tag, w1, (w1 >> 21) & 0xFu, r[5], r[17], gp, head);
        }
    }
    if (a == 0x800197C4u || a == 0x800197C8u) {
        /* R176: the crashy boot-main step — r4 here = the size-prefixed
         * stream ptr handed to UnpackCompressedHeapBlock (0x80032E88);
         * log its lineage. */
        static int bm_n;
        if (bm_n < 16) {
            bm_n++;
            fprintf(stderr, "[bm] enter 0x%08X r2=0x%08X r4=0x%08X r5=0x%08X r6=0x%08X r21=0x%08X r31=0x%08X\n",
                    a, r[2], r[4], r[5], r[6], r[21], r[31]);
        }
    }
    if (a == 0x80019578u) {
        extern unsigned xenolift_errc_count;
        fprintf(stderr, "[bootmain] boot main entered (restart?) caller=0x%08X", r[31]);
        if (xenolift_errc_count)
            fprintf(stderr, " — prior cycle: %u fn_80019ACC error-dispatcher calls (SPIKE = Module-6 validation failing)", xenolift_errc_count);
        fprintf(stderr, "\n");
        xenolift_errc_count = 0;
        /* R118: THE OVERLAY REGION DUMP. The phase callbacks point
         * into 0x80070000-0x8009FFFF (above kernel text end
         * 0x80059800) — the runtime-loaded module's final resting
         * place, where the driver will dispatch it (0x800737EC,
         * 0x80077C5C etc.). R117's a0-based captures caught leftover
         * register values (zero windows) — dump the region directly
         * at boot-main entry (fires after the install chain ran, on
         * first boot and every restart). */
        static int ovl_region_entry = 0;
        ovl_region_entry++;
        /* R120 TIMING FIX: the FIRST boot-main entry is boot START (before
         * the install chain ran — the R118/R119 captures were pre-install
         * zeros). Dump at entry #2 = after the first full install cycle,
         * when the module is really in RAM at 0x80070000+. */
        if (ovl_region_entry == 2) {
            FILE *f = fopen("overlay_region.bin", "wb");
            if (f) {
                /* R142: modules load at 0x8006FAF0 (xenogears-recomp disc1
                 * overlay inventory: files 13-18 = Battling/Field/World/
                 * Battle/Menu/Movie, bases 0x8006FAF0 / menu 0x801C5000).
                 * The old window started 0x5B10 bytes too high, missing
                 * the module base region. Window now 0x8006F000 (16-byte
                 * aligned below 0x8006FAF0) through 0x8008FFFF. */
                fwrite(xenolift_mem + (0x8006F000u - 0x80000000u), 1, 0x21000u, f);
                fclose(f);
                fprintf(stderr, "[ovl] overlay region 0x8006F000-0x8008FFFF (135KB, base incl. 0x8006FAF0 module load) -> overlay_region.bin\n");
            }
            /* R119: the module callback table (fn_80019A2C dispatches
             * table[idx] from 0x8004EAA0, 7 entries; the staged file at
             * 0x8004EABC sits right past its end). Log the LIVE values
             * at first boot-main entry. */
            fprintf(stderr, "[ovl] module table @0x8004EAA0:");
            for (int i = 0; i < 7; i++)
                fprintf(stderr, " [%d]=0x%08X", i,
                        xenolift_mem_read32(0x8004EAA0u + 4u * (uint32_t)i));
            fprintf(stderr, "\n");
            /* entry==2 gate auto-closes (counter keeps rising) */
        }
    }
    if (a == 0x800324B8u)
        fprintf(stderr, "[ins] fn_800324B8(0x%02X)%s\n", r[4],
                r[4] == 0x20u ? " <- DECOMPRESS FAILURE REPORT" : "");
    /* R215: INSTALL-CHAIN PROBE — decode of fn_80019ACC shows the
     * state-6 entry path: fn_80019C7C -> fn_80032498(a0=install-id,
     * a1=0) runs the MODULE INSTALL (file 10 = the state-6 family)
     * BEFORE MountGameStateModule; the boot loop = the install chain
     * never completing so the state re-enters. Log every fn_80032498
     * entry (id + a1) to name WHICH install re-issues. */
    if (a == 0x80032498u) {
        static int in_n;
        if (in_n < 40) {
            in_n++;
            fprintf(stderr, "[inscall] install chain id=0x%02X a1=0x%08X r31=0x%08X\n",
                    r[4], r[5], r[31]);
        }
    }
    /* R115: the state-machine advancers. fn_80031FF8 and fn_80031C58
     * write the next state fn into the state cell (0x80059340 =
     * gp+464; the state fns are call-site-indexed via fn_80031BDC's
     * ra-8 trick). Log WHO advances to WHAT — the Mac R114 loop =
     * 3 install states cycling (decompress 80032E94 -> 800197EC /
     * 8001B9AC -> back), ~1000x per watchdog; the exit condition of
     * the chain is what we are hunting. a0 = the next-state arg. */
    /* R222: UNPACK POISON GUARD. The sandbox (deeper than the Mac via
     * stream-alive defers) reached the mount chain step 6: UnpackCompressed-
     * Buffer entry FAULTED reading src=0x002A669C — the a0 block argument
     * carries the 0xC2C0CBA5-class tag-math poison from the heap walk (same
     * class [reloc-fix] substitutes for data). The TRUE block lives in the
     * res cell (0x800592BC = AllocateHeapBlock result, filled by the file-18
     * read). Substitute the true block when src is outside RAM. */
    if (a == 0x80032EB4u && (r[4] < 0x80000000u || r[4] >= 0x80200000u)) {
        uint32_t blk = xenolift_mem_read32(0x800592BCu);
        fprintf(stderr, "[unpack-fix] poison src a0=0x%08X -> block 0x%08X (res cell) dst=0x%08X\n",
                r[4], blk, r[5]);
        if (blk >= 0x80000000u && blk < 0x80200000u)
            r[4] = blk;
    }
    if (a == 0x80031FF8u || a == 0x80031C58u) {
        fprintf(stderr, "[adv] %s a0=0x%08X caller=0x%08X\n",
                a == 0x80031FF8u ? "fn_80031FF8" : "fn_80031C58",
                r[4], r[31]);
        /* R117: the decompress state passes its output buffer in a0
         * when fn_80031C58 is called from its tail (0x80032E9C) —
         * Mac R115 showed 0x801FC000 and 0x801FA634. Capture those
         * windows too (work region only). */
        if (a == 0x80031C58u && r[31] == 0x80032E9Cu
            && r[4] >= 0x801A0000u && r[4] < 0x80200000u)
            xenolift_ovl_dump(r[4], "decompress-out");
    }
        /* R440: DOUBLE-BOOK AUDIT. R439 proved (a) [adv] alloc 0x1E978 ->
         * advance at 0x801EF558 = the heap re-offers the LIVE font record
         * [0x801EF558,0x801F34B4) to a second alloc; (b) [frclash] movie
         * sector LBA 108988 -> 0x801EF3D8 (2048B) spans the record page;
         * (c) [rootw] root node is write-once at t=0 = ledger never
         * updates. Photograph the node header + heap descriptor at every
         * take inside the record span so the next ship marks the record's
         * node in-use with the CORRECT field (a blind redirect risks a
         * 125KB staging overflow past the 0x80200000 RAM ceiling). */
        if (a == 0x80031C58u && r[4] >= 0x801EF558u && r[4] < 0x801F34B4u) {
            static uint32_t c2n;
            c2n++;
            if (c2n <= 16u) {
                uint32_t p = r[4];
                fprintf(stderr, "[carve2] #%u take a0=%08X n[-8]=%08X n[-4]=%08X n[0]=%08X n[+4]=%08X n[+8]=%08X n[+C]=%08X r31=%08X rec-installed=%u\n",
                        c2n, p,
                        xenolift_mem_read32(p - 8),
                        xenolift_mem_read32(p - 4), xenolift_mem_read32(p),
                        xenolift_mem_read32(p + 4), xenolift_mem_read32(p + 8),
                        xenolift_mem_read32(p + 12), r[31],
                        xenolift_mem_read32(0x80059394u) == 0x801EF558u);
                fprintf(stderr, "[carve2] heap-desc FAEC=%08X FAF0=%08X FAF4=%08X FAF8=%08X FAFC=%08X FB00=%08X FB04=%08X FBFF8w0=%08X FBFFCw1=%08X\n",
                        xenolift_mem_read32(0x8005FAECu), xenolift_mem_read32(0x8006FAF0u),
                        xenolift_mem_read32(0x8006FAF4u), xenolift_mem_read32(0x8006FAF8u),
                        xenolift_mem_read32(0x8006FAFCu), xenolift_mem_read32(0x8006FB00u),
                        xenolift_mem_read32(0x8006FB04u),
                        xenolift_mem_read32(0x801FBFF8u), xenolift_mem_read32(0x801FBFFCu));
            }
            /* R444: heapfix REMOVED FOR GOOD (Lesson 40, re-proven c201+c203):
             * the redirect pushes the staging carve up INTO the record span
             * (staging [0x801D4B34,0x801F34B4) overlaps record by 0x3F5C).
             * Natural layout (staging [0x801D0BD8,0x801EF558)) is ADJACENT and
             * correct - only the last fill sector(s) overshoot, and [dmashield]
             * (index-space mask, at the executing site) clips exactly that. */
                    }
    if (a == 0x80031BDCu) {
        static uint32_t hp_n;
        hp_n++;
        if (hp_n <= 40u || (hp_n % 500u) == 0u || r[4] > 0x80000u)
            fprintf(stderr, "[heap] #%u alloc size=%u\n", hp_n, r[4]);
    }
    /* R153: restart step — the funnel that resets SP/GP and re-enters boot
     * main. r31 at entry names the site that selected the restart step. */
    if (a == 0x80019BD0u)
        fprintf(stderr, "[restart] RESTART STEP entered r31=0x%08X idx-cell=0x%08X cur=0x%08X res=0x%08X\n",
                r[31],
                xenolift_mem[0x18088] | ((uint32_t)xenolift_mem[0x18089] << 8)
                    | ((uint32_t)xenolift_mem[0x2808A] << 16) | ((uint32_t)xenolift_mem[0x2808B] << 24),
                xenolift_mem[0x592C0] | ((uint32_t)xenolift_mem[0x592C1] << 8)
                    | ((uint32_t)xenolift_mem[0x592C2] << 16) | ((uint32_t)xenolift_mem[0x592C3] << 24),
                xenolift_mem[0x592BC] | ((uint32_t)xenolift_mem[0x592BD] << 8)
                    | ((uint32_t)xenolift_mem[0x592BE] << 16) | ((uint32_t)xenolift_mem[0x592BF] << 24));
    /* R222: MOUNT-CHAIN STEP PROBES. Fresh disasm of fn_800199CC: cur is
     * written at mount ENTRY (0x800199F4), res = the allocated block right
     * after AllocateHeapBlock (0x80019A58). The file-18 read completes but
     * the module unpack (UnpackCompressedBuffer -> 0x8006FAF0) NEVER fires
     * and the entry dispatch @0x80019BFC never runs — the chain dies between
     * the unpack-dest read and the dispatch. These probes name the last
     * live step: MoveHeapAllocation / ClearHeapRuntime / ClearController-
     * Snapshots entries, with callers. */
    if (a == 0x80031B10u || a == 0x80031A30u || a == 0x80035DB0u) {
        static int ch_n;
        if (ch_n < 400) {
            ch_n++;
            const char *nm = (a == 0x80031B10u) ? "MoveHeapAllocation" :
                             (a == 0x80031A30u) ? "ClearHeapRuntime" : "ClearControllerSnapshots";
            fprintf(stderr, "[chain] %s a0=0x%08X a1=0x%08X caller=0x%08X cur=0x%08X res=0x%08X\n",
                    nm, r[4], r[5], r[31],
                    xenolift_mem_read32(0x800592C0u), xenolift_mem_read32(0x800592BCu));
        }
    }
    /* R223: POST-RESTORE PROBE — PC 0x80019BD8 = the first instruction
     * after fn_80019548's jr ra. If this fires, the restore returned
     * here and the dispatch stretch (MoveHeap#2/Clear/Commit/jalr) runs
     * next; if it never fires, the vanish is inside the restore's return
     * path. Logs the live s1 descriptor + SP, budget generous. */
    if (a == 0x80019BD8u) {
        static int pr_n;
        if (pr_n < 100) {
            pr_n++;
            uint32_t d0 = 0, d1 = 0, d8 = 0, d12 = 0;
            if (r[17] >= 0x80000000u && r[17] < 0x80200000u) {
                memcpy(&d0, xenolift_mem + (r[17] - 0x80000000u), 4);
                memcpy(&d1, xenolift_mem + (r[17] - 0x80000000u) + 4, 4);
                memcpy(&d8, xenolift_mem + (r[17] - 0x80000000u) + 8, 4);
                memcpy(&d12, xenolift_mem + (r[17] - 0x80000000u) + 12, 4);
            }
            fprintf(stderr, "[postres] #%u POST-RESTORE reached r31=0x%08X sp=0x%08X s1=0x%08X desc=[0x%08X 0x%08X 0x%08X 0x%08X] cur=0x%08X res=0x%08X\n",
                    pr_n, r[31], r[29], r[17], d0, d1, d8, d12,
                    xenolift_mem_read32(0x800592C0u), xenolift_mem_read32(0x800592BCu));
        }
    }
    /* R223: MODULE-UNPACK PROBE — fn_80032EB4 called with the module block
     * (src >= 0x801E0000) never appears in any digest; dedicated log line,
     * never budget-cut, names whether the dispatcher's unpack (0x80019B90)
     * ever fires. */
    if (a == 0x80032EB4u && r[4] >= 0x801E0000u && r[4] < 0x80200000u) {
        fprintf(stderr, "[unpack] MODULE UNPACK src=0x%08X dst=0x%08X caller=0x%08X (dispatcher unpack expected src=res-block dst=0x8006FAF0)\n",
                r[4], r[5], r[31]);
    }
    /* R153: MountGameStateModule entry — state arg + the four working cells */
    if (a == 0x800199CCu) {
        static int mt_n;
        if (mt_n < 12) {
            mt_n++;
            /* R154: the unpack-dest cell 0x80028084. Cycle-5 live value was
             * the raw disc word 0xAFB100EC - nonsense. The intended value is
             * the module load base per state (R142/MODULE_PREMAP: modules
             * load at 0x8006FAF0; Menu payload at 0x801C5000). Install it
             * here so UnpackCompressedBuffer lands the module correctly. */
            uint32_t st = r[4];
            uint32_t base = (st == 5u) ? 0x801C5000u : 0x8006FAF0u;
            if (st >= 1u && st <= 6u) {
                memcpy(xenolift_mem + 0x28084u, &base, 4);
                fprintf(stderr, "[mount] unpack-dest cell set to 0x%08X for state %u\n", base, st);
            }
            fprintf(stderr, "[mount] MountGameStateModule(state=%u) idx=0x%08X dest=0x%08X cur=0x%08X res=0x%08X\n",
                    r[4],
                    xenolift_mem[0x18088] | ((uint32_t)xenolift_mem[0x18089] << 8)
                        | ((uint32_t)xenolift_mem[0x2808A] << 16) | ((uint32_t)xenolift_mem[0x2808B] << 24),
                    xenolift_mem[0x28084] | ((uint32_t)xenolift_mem[0x28085] << 8)
                        | ((uint32_t)xenolift_mem[0x28086] << 16) | ((uint32_t)xenolift_mem[0x28087] << 24),
                    xenolift_mem[0x592C0] | ((uint32_t)xenolift_mem[0x592C1] << 8)
                        | ((uint32_t)xenolift_mem[0x592C2] << 16) | ((uint32_t)xenolift_mem[0x592C3] << 24),
                    xenolift_mem[0x592BC] | ((uint32_t)xenolift_mem[0x592BD] << 8)
                        | ((uint32_t)xenolift_mem[0x592BE] << 16) | ((uint32_t)xenolift_mem[0x592BF] << 24));
        }
    }
    /* R153: dispatcher watch (kept from R152 - fires only if the chain gets here) */
    if (a == 0x80019AFCu) {
        /* R154: mirror the committed state (0x80018088) into the working idx
         * cell (0x80018088) right before the dispatcher reads it. */
        uint32_t rom_idx = 0, work_idx = 0;
        memcpy(&rom_idx, xenolift_mem + 0x18088u, 4);
        memcpy(&work_idx, xenolift_mem + 0x18088u, 4);
        if (rom_idx != work_idx)
            fprintf(stderr, "[gdisp] idx mirror: 0x%08X -> 0x%08X (working cell had 0x%08X)\n",
                    work_idx, rom_idx, work_idx);
        memcpy(xenolift_mem + 0x18088u, &rom_idx, 4);
        uint32_t gs = rom_idx;
        fprintf(stderr, "[gdisp] dispatcher enter state=%u\n", gs);
    }
    if (a == 0x80019BFCu) {
        static int gtd;
        uint32_t d = r[17];
        uint32_t cb = 0, w1 = 0, w2 = 0, w3 = 0;
        if (d >= 0x80000000u && d < 0x80200000u) {
            memcpy(&cb, xenolift_mem + (d - 0x80000000u), 4);
            memcpy(&w1, xenolift_mem + (d - 0x80000000u) + 4, 4);
            memcpy(&w2, xenolift_mem + (d - 0x80000000u) + 8, 4);
            memcpy(&w3, xenolift_mem + (d - 0x80000000u) + 12, 4);
        }
        fprintf(stderr, "[gdisp] ENTRY-DISPATCH desc=0x%08X cb=0x%08X w1=0x%08X w2=0x%08X w3=0x%08X\n",
                d, cb, w1, w2, w3);

    }
    if (a == 0x80019ACCu) {
        /* R214: VALIDATION-CONDITION PROBE — dump the routing state at
         * EVERY error-dispatcher entry (not just the first 8): a0, the
         * install_required flag cell 0x80018088, the first descriptor
         * pair 0x8001808C, and the mount result cells. With the watchers
         * proving NO WRITER ever touches cur/res (0x800592C0/0x800592BC),
         * the question is what the validator compares each pass. */
        {
            uint32_t f0, d0, d1;
            memcpy(&f0, xenolift_mem + 0x18088u, 4);
            memcpy(&d0, xenolift_mem + 0x2808Cu, 4);
            memcpy(&d1, xenolift_mem + 0x28090u, 4);
            fprintf(stderr, "[vprobe] a0=0x%08X flag=0x%08X desc0=0x%08X desc1=0x%08X cur=0x%08X res=0x%08X\n",
                    r[4], f0, d0, d1,
                    xenolift_mem[0x592C0] | ((uint32_t)xenolift_mem[0x592C1] << 8)
                        | ((uint32_t)xenolift_mem[0x592C2] << 16) | ((uint32_t)xenolift_mem[0x592C3] << 24),
                    xenolift_mem[0x592BC] | ((uint32_t)xenolift_mem[0x592BD] << 8)
                        | ((uint32_t)xenolift_mem[0x592BE] << 16) | ((uint32_t)xenolift_mem[0x592BF] << 24));
        }
        /* R153: live game-table dump at RunResidentGameLoop entry (proven-fire site) */
        static int gt_n;
        if (gt_n < 8) {
            gt_n++;
            uint32_t idx, dst, cur, res;
            memcpy(&idx, xenolift_mem + 0x18088u, 4);
            memcpy(&dst, xenolift_mem + 0x28084u, 4);
            memcpy(&cur, xenolift_mem + 0x592C0u, 4);
            memcpy(&res, xenolift_mem + 0x592BCu, 4);
            fprintf(stderr, "[gtab] idx-cell=0x%08X dest-cell=0x%08X cur=0x%08X res=0x%08X\n", idx, dst, cur, res);
            for (uint32_t e = 0; e < 8u; e++) {
                uint32_t b = 0x2808Cu + e * 16u;
                uint32_t c0, c1, c2, c3;
                memcpy(&c0, xenolift_mem + b, 4); memcpy(&c1, xenolift_mem + b + 4, 4);
                memcpy(&c2, xenolift_mem + b + 8, 4); memcpy(&c3, xenolift_mem + b + 12, 4);
                fprintf(stderr, "[gtab] gdesc[%u] = 0x%08X 0x%08X 0x%08X 0x%08X\n", e, c0, c1, c2, c3);
            }
        }
    }
    /* R661 (c231): death state is now PERFECT (cur=1, mount done posture,
     * FDF8=0, clean cells) yet the boot still unwinds @16s — the cause lives
     * PAST the mount, in the game loop's own exit decision, which no receipt
     * covers. Cameras for the two dark doors: the state-1 callback entry
     * (does the dispatcher ever actually CALL cb 0x80077E88 after the heal?)
     * and the outer game-loop iteration check (fn 0x80031DA8 reads its loop
     * exit pair r16/r2 — watch the decision evolve frame by frame). */
    if (a == 0x80077E88u) {
        static uint32_t r661cb;
        /* R676: cur-restore at the field cb's own door. c246/c247: the cb
         * enters with cur(92C0)=FFFFFFFF (mount machinery's in-flight mark)
         * -> the state walk exits on the invalid state -> main unwinds @11s.
         * State-1 dispatch itself proves Field is the live state; restore the
         * game's own CHANNEL-F committed value so the walk keeps running. */
        if (xenolift_mem_read32(0x800592C0u) == 0xFFFFFFFFu) {
            xenolift_mem_write32(0x800592C0u, 1u);
            fprintf(stderr, "[mtrans] R676 cur-restore at state-1 cb entry: 92C0 -1 -> 1 (field dispatch is proof - keep the state walk alive)\n");
        }
        if (r661cb < 12u) {
            r661cb++;
            fprintf(stderr, "[mtrans] R661 STATE-1 CB ENTER #%u @t=%lds: idx=%u cur=%u req=%u F0C=%u FDF8=%u FE1C=%u FE20=%u r31=%08X\n",
                    r661cb, (long)(time(NULL) - g_boot_wall_t0),
                    xenolift_mem_read32(0x8005FAECu), xenolift_mem_read32(0x800592C0u),
                    xenolift_mem_read32(0x80018088u), xenolift_mem_read32(0x80059F0Cu),
                    xenolift_mem_read32(0x8004FDF8u), xenolift_mem_read32(0x8004FE1Cu),
                    xenolift_mem_read32(0x8004FE20u), (unsigned)r[31]);
        }
    }
    if (a == 0x80031DA8u) {
        static uint32_t r661lp;
        if (r661lp < 16u) {
            r661lp++;
            fprintf(stderr, "[phase] R661 outer-loop check #%u @t=%lds: r16=%08X r2=%08X r6=%08X FE1C=%u cur=%u idx=%u r31=%08X r28=%08X cell1C0=%08X\n",
                    r661lp, (long)(time(NULL) - g_boot_wall_t0),
                    (unsigned)r[16], (unsigned)r[2], (unsigned)r[6],
                    xenolift_mem_read32(0x8004FE1Cu), xenolift_mem_read32(0x800592C0u),
                    xenolift_mem_read32(0x8005FAECu), (unsigned)r[31],
                    (unsigned)r[28], xenolift_mem_read32(r[28] + 0x1C0u));
        }
    }
    /* R670: c240 — R669 req=1 landed + survived (mount dormant, no reset), but the
 * program still clean-returned @14s: the outer walker ran 3x @t=8s and NEVER AGAIN,
 * so the latch-check exit is not the path; the menu-exit unwind happens because the
 * state dispatcher (0x80019AF8) is never re-entered after the menu exits. Cameras:
 * (a) 0x80019AF8 dispatcher entry — what index source it reads (req/FAEC/cur) and
 * what cb it picks; (b) 0x80031F58 walker-exit branch entry — full context if it
 * ever actually runs. Both capped 8. */
    if (a == 0x80019AF8u) {
        static uint32_t r670d;
        /* R674 [reselect] FIELD RE-SELECT AT THE DESK. c244 dispatcher footage:
         * 80019AF8 re-fires every ~2s post-menu with cur(92C0)=1 idx(FAEC)=1 but
         * req(18088)=0 -> dispatches menu cb forever. CHANNEL F (c186+ every cycle)
         * proves the game's own CommitGameStateTransition writes 18088=1 - it is
         * consumed before the desk reads it. Return the game's own commit value at
         * the read site so the dispatcher's own table walk picks table[1] =
         * 80077E88 (field state cb) natively. Gates: field committed by the game
         * (cur==1), mount index reached member 1 (FAEC==1), field era (F0C>=14),
         * and the cell actually empty. Capped 4 (2s cadence = 4 chances). */
        if (xenolift_mem_read32(0x800592C0u) == 1u &&
            xenolift_mem_read32(0x8005FAECu) == 1u &&
            xenolift_mem_read32(0x80059F0Cu) >= 14u &&
            xenolift_mem_read32(0x80018088u) == 0u) {
            static uint32_t r674n;
            if (r674n < 4u) {
                r674n++;
                xenolift_mem_write32(0x80018088u, 1u);
                fprintf(stderr, "[phase] R674 reselect stamp #%u @t=%lds: 18088 0 -> 1 (game's own CHANNEL-F commit value - desk should dispatch table[1]=80077E88 field cb natively)\n",
                        r674n, (long)(time(NULL) - g_boot_wall_t0));
            }
        }
        if (r670d < 8u) {
            r670d++;
            fprintf(stderr, "[phase] R670 DISPATCHER entry #%u @t=%lds: req=%08X idx(FAEC)=%08X cur=%08X F0C=%u FDF8=%08X latch(9330)=%08X r31=%08X\n",
                    r670d, (long)(time(NULL) - g_boot_wall_t0),
                    xenolift_mem_read32(0x80018088u), xenolift_mem_read32(0x8005FAECu),
                    xenolift_mem_read32(0x800592C0u), xenolift_mem_read32(0x80059F0Cu),
                    xenolift_mem_read32(0x8004FDF8u), xenolift_mem_read32(0x80059330u),
                    (unsigned)r[31]);
        }
    }
    if (a == 0x80031F58u) {
        static uint32_t r670x;
        /* R673: suppress boot-era module-check entries (cur==0 && req==0 -
         * c241-c243 proved they are the 5-per-boot routine, not the exit) */
        if (r670x < 8u && (xenolift_mem_read32(0x800592C0u) != 0u ||
                           xenolift_mem_read32(0x80018088u) != 0u)) {
            r670x++;
            fprintf(stderr, "[phase] R670 WALKER-EXIT branch entry #%u @t=%lds: r6=%08X r16=%08X req=%08X idx(FAEC)=%08X cur=%08X latch(9330)=%08X r31=%08X\n",
                    r670x, (long)(time(NULL) - g_boot_wall_t0),
                    (unsigned)r[6], (unsigned)r[16],
                    xenolift_mem_read32(0x80018088u), xenolift_mem_read32(0x8005FAECu),
                    xenolift_mem_read32(0x800592C0u), xenolift_mem_read32(0x80059330u),
                    (unsigned)r[31]);
        }
    }
if (a == 0x8001996Cu || a == 0x80019ACCu || a == 0x80019EF8u) {
        static uint32_t ph_n;
        uint32_t idx = xenolift_mem[0x18088] | ((uint32_t)xenolift_mem[0x18089] << 8)
                     | ((uint32_t)xenolift_mem[0x1808A] << 16) | ((uint32_t)xenolift_mem[0x1808B] << 24);
        uint32_t cb = 0xDEADBEEFu;
        if (idx < 16u) {
            uint32_t b = 0x1808Cu + idx * 16u;
            cb = xenolift_mem[b] | ((uint32_t)xenolift_mem[b + 1] << 8)
               | ((uint32_t)xenolift_mem[b + 2] << 16) | ((uint32_t)xenolift_mem[b + 3] << 24);
        }
        int32_t phase = (int32_t)(xenolift_mem[0x592C0] | ((uint32_t)xenolift_mem[0x592C1] << 8)
                     | ((uint32_t)xenolift_mem[0x592C2] << 16) | ((uint32_t)xenolift_mem[0x592C3] << 24));
        uint32_t flag = xenolift_mem[0x592BC] | ((uint32_t)xenolift_mem[0x592BD] << 8)
                     | ((uint32_t)xenolift_mem[0x592BE] << 16) | ((uint32_t)xenolift_mem[0x592BF] << 24);
        /* R657 (c227) DISPATCH-RACE HEAL: at death the state machine was READY
         * (cur=1, idx=1, field mount in flight - 8 sectors streamed natively)
         * but the dispatcher's mid-teardown re-read caught cur=-1 in the
         * sub-second window between teardown and the maintenance-side
         * re-stamp, read "no state", unwound to main-return @14s. Heal at the
         * READ SITE - main thread, race-free: phase==-1 while the field mount
         * is pending (mount idx cell FAEC==1, request era F0C 14/15) =>
         * restore cur=1 so the dispatch loop re-enters state-1 (cb 0x80077E88)
         * natively once the field module installs. */
        if ((a == 0x80019ACCu || a == 0x8001996Cu || a == 0x80019EF8u) && phase == -1) {
            uint32_t midx = xenolift_mem[0x5FAEC] | ((uint32_t)xenolift_mem[0x5FAED] << 8)
                          | ((uint32_t)xenolift_mem[0x5FAEE] << 16) | ((uint32_t)xenolift_mem[0x5FAEF] << 24);
            uint32_t f0c = xenolift_mem[0x59F0C] | ((uint32_t)xenolift_mem[0x59F0D] << 8)
                         | ((uint32_t)xenolift_mem[0x59F0E] << 16) | ((uint32_t)xenolift_mem[0x59F0F] << 24);
            if (midx == 1u && (f0c == 14u || f0c == 15u)) {
                static uint32_t r657n;
                if (r657n < 40u) {
                    xenolift_mem[0x592C0] = 1u; xenolift_mem[0x592C1] = 0u;
                    xenolift_mem[0x592C2] = 0u; xenolift_mem[0x592C3] = 0u;
                    /* R659 (c229): fold the exit-pair re-arm INTO the main-thread
                     * heal — c228's long trajectory was sustained by the alarm-side
                     * refires (R650 #3/#4/#5); c229 died at 15s in the gap between
                     * refires. Same anti-race doctrine: move the stamp to the read
                     * site. idx==1 guarantees the menu already committed. */
                    xenolift_mem[0x592D0] = 0u; xenolift_mem[0x592D1] = 0u;
                    xenolift_mem[0x592D2] = 0u; xenolift_mem[0x592D3] = 0u;
                    xenolift_mem[0x592C8] = 1u; xenolift_mem[0x592C9] = 0u;
                    xenolift_mem[0x592CA] = 0u; xenolift_mem[0x592CB] = 0u;
                    phase = 1;
                    r657n++;
                    fprintf(stderr, "[phase] R657/R659 race heal #%u (fn=%08X): dispatcher read phase=-1 while field mount in flight (idx=1 F0C=%u) - cur restored to 1 + exit pair re-armed AT THE READ SITE (main-thread, race-free) - loop should re-dispatch state-1 (cb 0x80077E88)\n", r657n, a, f0c);
                }
            }
        }
        if ((a == 0x80019ACCu || a == 0x8001996Cu || a == 0x80019EF8u)) {
            /* R660: field request live => complete the install in this breath */
            uint32_t pidx = xenolift_mem[0x5FAEC] | ((uint32_t)xenolift_mem[0x5FAED] << 8)
                          | ((uint32_t)xenolift_mem[0x5FAEE] << 16) | ((uint32_t)xenolift_mem[0x5FAEF] << 24);
            uint32_t pf0c = xenolift_mem[0x59F0C] | ((uint32_t)xenolift_mem[0x59F0D] << 8)
                          | ((uint32_t)xenolift_mem[0x59F0E] << 16) | ((uint32_t)xenolift_mem[0x59F0F] << 24);
            /* R662: whole field-era family (files 15-18) — the game itself queued file 16 */
            if (pidx == 1u && pf0c >= 15u && pf0c <= 18u) {
                static uint32_t r660n;
                if (r660n < 4u) {
                    if (xenolift_f15_bulk("phase-hook")) {
                        r660n++;
                        /* R664: c234 - the phase-hook bulk completed the file
                         * BEFORE the alarm path could run the R655 done-ack prime
                         * (run died 1s later, done posture sat unconsumed at
                         * FE1C=6, walk finalize never ran, queue never advanced).
                         * Prime the SAME mailbox inline here: main-thread fn-entry
                         * boundary = same write class as the bulk itself. The game's
                         * own poll (fn_8002AC14 chain) pops it and walks its finalize
                         * (cbcall #78-equivalent -> HandleCdSyncCompletion -> queue
                         * node F10 advance + queue idx stamp). */
                        cd_resp[0] = 0x02u; cd_resp[1] = 0x01u; cd_resp[2] = 0x01u;
                        cd_resp_n = 3u; cd_resp_pos = 0u;
                        if (cd_pending == 0u) cd_pending = 1u;
                        fprintf(stderr, "[mtrans] R664 phase-done-ack primed (f0c=%u - mailbox hot, walk finalize can run)\n", pf0c);
                        /* R669: c239 [phase] receipts — the state dispatcher
                         * (0x80019AF8, entered when the menu exits) reads
                         * req(0x80018088) as its QUEUE INDEX: node[0] = menu cb
                         * 0x8001A4B4, node[1] = FIELD cb 0x80077E88. c236 failed
                         * because 1 was written DURING the install (the mount
                         * machine consumed it as "request pending"). HERE —
                         * post-finalize, ack primed, mount loops dormant — the
                         * write feeds only the dispatcher: next dispatch calls
                         * the field handler instead of the menu. One-shot,
                         * kernel field posture (cur=1) required. */
                        if (xenolift_mem_read32(0x800592C0u) == 1u
                            && xenolift_mem_read32(0x80018088u) == 0u) {
                            xenolift_mem_write32(0x80018088u, 1u);
                            fprintf(stderr, "[mtrans] R669 queue answer: req 0 -> 1 (field node for post-menu dispatcher - finalize-era, mount dormant)\n");
                        }
                    }
                }
            }
        }
        ph_n++;
        if (a == 0x80019ACCu) {
            /* R143 (Jos directive 07:41): fn_80019ACC = the error/re-init
             * dispatcher. A call spike = the kernel failing a downstream
             * validation inside Module 6 and falling back to re-init.
             * Count per boot cycle; bootmain logs + resets the count. */
            extern unsigned xenolift_errc_count;
            xenolift_errc_count++;
        }
        if (a == 0x80019EF8u || ph_n <= 60u || (ph_n % 2000u) == 0u)
            fprintf(stderr, "[phase] #%u enter 0x%08X r4=%u idx=%u cb=0x%08X flag=%u phase=%d r31=0x%08X\n",
                    ph_n, a, r[4], idx, cb, flag, phase, r[31]);
        if (a == 0x80019ACCu) { /* once: dump the whole runtime table */
            static int dumped;
            if (!dumped) {
                dumped = 1;
                for (uint32_t e = 0; e < 8u; e++) {
                    uint32_t b = 0x1808Cu + e * 16u;
                    uint32_t w0 = xenolift_mem[b] | ((uint32_t)xenolift_mem[b + 1] << 8)
                                | ((uint32_t)xenolift_mem[b + 2] << 16) | ((uint32_t)xenolift_mem[b + 3] << 24);
                    fprintf(stderr, "[phase] table[%u] cb=0x%08X\n", e, w0);
                }
            }
        }
    }

    /* Virtual clock: on real hardware the kernel clock at 0x80068960 is
     * advanced by the root-counter (timer) interrupt ~60 times per frame.
     * No interrupts in static recomp, so the kernel's "sleep until clock
     * reaches target" (fn 0x8004B694) would spin forever on a frozen clock.
     * Advance it here: this hook fires on every recompiled function entry,
     * so every kernel spin loop that calls functions makes time pass. */
    {
        static uint32_t clock_ticks;
        if (++clock_ticks >= 32u) {
            clock_ticks = 0;
            xenolift_mem[0x68960] += 1; /* little-endian increment of 0x80068960 */
            if (xenolift_mem[0x68960] == 0) xenolift_mem[0x68961]++;
            if (xenolift_mem[0x68961] == 0) xenolift_mem[0x68962]++;
            if (xenolift_mem[0x68962] == 0) xenolift_mem[0x68963]++;
        }
        /* driver-state transition watcher: prints every change of the
         * CD/card driver state cells with the function that was entered */
        {
            static uint8_t snap[9]; /* R475 FIX: was [8] with a 9-cell loop — snap[8] wrote OOB into adjacent statics every trace pass, killing the guest in 1s (c39). -w hides the excess-initializer warning; DECLARED SIZE must match initializer count AND loop bound. */
            uint8_t cdfs_lo = xenolift_mem[0x4FE1C], cdfs_hi = xenolift_mem[0x4FE1D];
            static uint8_t snap9[2];
            if (cdfs_lo != snap9[0] || cdfs_hi != snap9[1]) {
                fprintf(stderr, "[chg] FE1C %04X->%04X at fn 0x%08X\n",
                        (snap9[1] << 8) | snap9[0], (cdfs_hi << 8) | cdfs_lo, a);
                snap9[0] = cdfs_lo; snap9[1] = cdfs_hi;
            }
            /* read-request cells: expected LBA (FE04), rejection
             * counter (FDE4), dest (FE08), remaining (FDF8) */
            static uint32_t snapR[4];
            const uint32_t req_cells[4] = { 0x4FE04u, 0x4FDE4u, 0x4FE08u, 0x4FDF8u };
            for (int i = 0; i < 4; i++) {
                uint32_t v = xenolift_mem_read32(0x80000000u + req_cells[i]);
                if (v != snapR[i]) {
                    fprintf(stderr, "[req] %s %08X->%08X at fn 0x%08X\n",
                            i == 0 ? "FE04" : i == 1 ? "FDE4" : i == 2 ? "FE08" : "FDF8",
                            snapR[i], v, a);
                    snapR[i] = v;
                }
            }
            uint8_t cur[9] = { /* R475: resized with snap[] */
                xenolift_mem[0x56788], xenolift_mem[0x56789],
                xenolift_mem[0x5678A], xenolift_mem[0x564B8],
                xenolift_mem[0x564C9], xenolift_mem[0x5A210],
                (uint8_t)(*(uint16_t *)(xenolift_mem + 0x578A6) & 0xFF),
                xenolift_mem[0x564AC], /* handler cell low byte */
                (uint8_t)(xenolift_mem_read32(0x77448u) & 0xFFu) /* movie pass ctr low */
            };
            for (int i = 0; i < 9; i++) {
                if (cur[i] != snap[i]) {
                    fprintf(stderr, "[chg] cell%d %02X->%02X at fn 0x%08X\n",
                            i, snap[i], cur[i], a);
                    snap[i] = cur[i];
                }
            }
            /* R493: FRONTIER-RECORD WATCH. c58/c59: the heap walker
             * fn_80031C58 (boot file-place steps) walks the free-record
             * chain into the frontier record at dest-8 and follows a
             * poisoned next-pointer into the void (c58: my old hdr write
             * "wds "; c59: pre-existing garbage 0x1132001A — a record the
             * game never wrote properly because the frontier never
             * advanced past file 3). Name the writers of the three
             * frontier cells so the repair can be honest. */
            {
                static uint32_t snapF[4]; static uint32_t fw_n;
                /* R494: FRONTIER BODYGUARD. c60 [frontw] NAMED the poisoner:
                 * the frontier advancer fn_80031F58 writes ALL records
                 * legitimately (chain to next file dest), then fn_800286CC
                 * (movie/display ctl, writes per-frame packed control words)
                 * sprays 0x1132001A onto cell 0x8007EBE8, breaking the chain
                 * the heap walker needs. Once the advancer arms a cell, any
                 * OTHER writer's value is misdelivered cross-talk: revert it
                 * on sight so the walk reads the advancer's chain. The ctl
                 * word is per-frame refresh data (rewritten constantly), so
                 * dropping one write is safe for the movie subsystem. */
                static uint32_t armedF[4]; static uint32_t legitF[4]; static uint32_t fguard_n; /* R496: +0xAFC90 = file-6 dest-8 record -> its arming reveals file 7's dest */
                const uint32_t front_cells[4] = { 0x7EBE8u, 0xA49E0u, 0xAA6A8u, 0xAFC90u };
                for (int i = 0; i < 4; i++) {
                    uint32_t v = xenolift_mem_read32(0x80000000u + front_cells[i]);
                    if (v != snapF[i]) {
                        if (a == 0x80031F58u || a == 0x80031C58u || a == 0x80031B9Cu
                            || a == 0x80031BA8u || a == 0x80031BDCu || a == 0x80031B00u) {
                            armedF[i] = 1u; legitF[i] = v; /* heap-advancer family: legitimate chain value */
                            /* R497: PRE-SHELVE. c63: the advancer armed
                             * file-6's record (cell 0x800AFC90) with
                             * 0x800B0704 = file 7's dest (matches
                             * 0x800AFC98 + 2660 + 8 exactly). File 7
                             * (LBA 108886, 13768B, member 7 @0x800100CF)
                             * was queued but its request never armed
                             * (last_cmd=00) and the phase engine's poll
                             * limit beat the R496 ARM timer -> clean
                             * AbortOnGameFault(130). Deliver the whole
                             * payload to the armed dest NOW, before the
                             * phase asks - the data is on the shelf
                             * when the config check runs. One-shot. */
                            if (i == 3 && v >= 0x80010000u && v < 0x801FC000u
                                && v != 0x801FC000u && !r497_shelved_lba) {
                                const uint8_t *fe7 = xenolift_mem + 0x000100A5u + 7u * 6u; /* member 7 entry */
                                uint32_t lba7 = fe7[0] | (fe7[1] << 8) | (fe7[2] << 16);
                                uint32_t size7 = fe7[3] | (fe7[4] << 8) | (fe7[5] << 16) | ((uint32_t)fe7[6] << 24);
                                if (lba7 > 100000u && size7 >= 8u && size7 <= 0x100000u
                                    && v + (size7 - 8u) <= 0x801FC000u) {
                                    static uint8_t ps7[2048];
                                    uint32_t rem7 = size7 - 8u, off7 = 0u;
                                    while (off7 < rem7) {
                                        uint32_t fo = 8u + off7;
                                        if (disc_read_lba(lba7 + fo / 2048u, ps7) != 0) break;
                                        uint32_t n = 2048u - (fo % 2048u);
                                        if (n > rem7 - off7) n = rem7 - off7;
                                        memcpy(xenolift_mem + (v + off7 - 0x80000000u), ps7 + (fo % 2048u), n);
                                        off7 += n;
                                    }
                                    r497_shelved_lba = lba7;
                                    fprintf(stderr, "[defib7] R497 PRE-SHELVE: file7 lba %u size %u -> 0x%08X (frontier-armed dest, %u bytes shelved BEFORE the phase asks - armed path too slow, abort beat it c63)\n",
                                            lba7, size7, v, off7);
                                    /* R498: c64 - data on the shelf but the phase cb
                                     * STILL aborted(130) with FE04=0x1A954 still
                                     * queued (ctx byte-identical to c63). The game's
                                     * request bookkeeping never saw a completion:
                                     * natively the file layer CLEARS FE04->0 at
                                     * fn_800415B4 when a request finishes
                                     * ([FE04W] 0x1A8F1->0 receipt). Mirror that
                                     * completion write so queue checks pass. */
                                    if (xenolift_mem_read32(0x8004FE04u) == 0x0001A954u) {
                                        xenolift_mem_write32(0x8004FE04u, 0u);
                                        fprintf(stderr, "[defib7] R498 REQ-DONE: file-7 request FE04 cleared (mirror of native fn_800415B4 completion write)\n");
                                    }
                                }
                            }
                        } else if (armedF[i] && v != legitF[i]) {
                            if (fguard_n < 8u) {
                                xenolift_mem_write32(0x80000000u + front_cells[i], legitF[i]);
                                fprintf(stderr, "[frontguard] R494 misdelivered ctl word 0x%08X -> frontier record 0x%08X REVERTED (fn 0x%08X, chain preserved)\n",
                                        v, legitF[i], a);
                                fguard_n++;
                            }
                            v = legitF[i];
                        }
                        if (fw_n++ < 16u)
                            fprintf(stderr, "[frontw] cell 0x%08X %08X->%08X at fn 0x%08X\n",
                                    0x80000000u + front_cells[i], snapF[i], v, a);
                        snapF[i] = v;
                    }
                }
            }
        }
    }
    /* Virtual CD interrupt: the kernel's event-flag check fn. Entering it
     * means the kernel is polling for events — this is where a real
     * controller's INT3 would have fired. Deliver any scheduled response
     * now: set pending, and set the kernel op flag (the collector runs
     * when the flag check returns nonzero). Handler-table commands are
     * delivered silently (no flag) — their slot-3 completions would
     * wedge the event pump forever without a real interrupt dispatcher. */
    if ((a == 0x8004B894u || a == 0x8004293Cu) && cd_scheduled) {
        if (cd_pending != 0u) {
            /* A sector data event is in flight: delivering a command
             * response now would CLOBBER it (the kernel's collector
             * takes one event per pass). Defer — cd_scheduled stays
             * set, so this re-delivers once the data event drains. */
            static int deferred_logs;
            if (deferred_logs++ < 6)
                fprintf(stderr, "[cd] INT3 deferred: sector event in flight (cmd 0x%02X)\n", cd_last_cmd);
        } else {
        /* EXPERIMENT: when the Setmode (0x0E) response arrives while the
         * CDFS async-wait cell 0x8004FE1C is nonzero, the state machine
         * can't advance (its continuation runs in IRQ context on real
         * hardware). Force-complete the wait so the kernel's own code
         * proceeds and we can observe what it expects next. */
        uint32_t cdfs_wait;
        memcpy(&cdfs_wait, xenolift_mem + (0x8004FE1Cu & 0x1FFFFFFFu), 4);
        if (cd_last_cmd == 0x0Eu && cdfs_wait != 0u) {
            uint32_t zero = 0;
            memcpy(xenolift_mem + (0x8004FE1Cu & 0x1FFFFFFFu), &zero, 4);
            fprintf(stderr, "[cd] CDFS wait cell 0x8004FE1C: %08X -> 0 (force-completed after Setmode response)\n", cdfs_wait);
        }
        cd_restore_pend(); /* R308: central (was R307 event-flag inline) */
        cd_scheduled = 0;
        cd_pending = 3; /* INT3: response ready in the FIFO */
        if (!cd_flag_suppressed(cd_last_cmd)) {
            uint16_t one = 1;
            memcpy(xenolift_mem + (0x800578A6u & 0x1FFFFFFFu), &one, 2);
            fprintf(stderr, "[cd] virtual INT3: cmd 0x%02X response delivered, op flag set\n", cd_last_cmd);
        } else {
            fprintf(stderr, "[cd] virtual INT3: cmd 0x%02X delivered silently (handler cmd)\n", cd_last_cmd);
        }
        }
    }
    /* Per-sector data events (INT1): the data handler is dispatched by
     * the event pump on real hardware from INTERRUPT context while the
     * kernel sits in its read-wait loop. The loop ticks fn 0x80041410
     * each iteration — deliver any pending sector event there, exactly
     * the way the pump's slot-4 dispatch would (handler a0=1 data event,
     * a1 = 8-byte event status buffer at 0x8005A218). */
    /* Wait-loop event delivery. The kernel's CDFS read-wait loop
     * (fn 0x800286CC) ticks fn 0x80041410 each iteration but NEVER
     * runs the event pump — on real hardware, pending CD events
     * (INT1 sector data, INT3 command responses) arrive as
     * interrupts and the pump-equivalent runs in IRQ context.
     * Deliver them here exactly the way the pump (fn 0x80041B3C)
     * would: run the kernel's own collector (fn 0x800415B4, no
     * args), then dispatch the slot handlers it armed — slot 4:
     * h4(a0=cell 0x56789, a1=0x8005A218), slot 2: h2(a0=cell
     * 0x56788, a1=0x8005A210) — looping while the collector reports
     * events, then restore the register bank like the pump does. */
    /* gate: only deliver from INSIDE the read-wait loop — fn 0x800286CC
     * is the only caller of the tick from that loop (r31 = its call
     * site 0x80028704). Other fn 0x80041410 callers are main-loop
     * contexts where the kernel's own pump handles events and a
     * second collector here corrupts the in-flight handshake. */
    /* R111: two delivery contexts. (1) The read-wait loop (fn
     * 0x800286CC calls the pump 0x80041410 at r31 0x80028704). (2)
     * The fd module's INT processor calls the collector 0x800415B4
     * DIRECTLY (jal at 0x80041C98, r31 = 0x80041CA0) and spins inside
     * it while an INT1 is pending: the pending flag only becomes a
     * slot event via the registered handler pair, which only ran in
     * context (1) — so the collector starved (Mac R109/R110: FDF8=0,
     * FE1C=5, notify never dispatched). Re-entrancy guard: the tick
     * body itself dispatches the collector, which would re-fire this
     * gate in the same register state. */
    static int cd_tick_busy = 0;
    /* R130: kick-pending = the fd collector spins at drive-idle while
     * an enqueued archive request (FE04 cell) was never Setloc'd. */
    uint32_t fe04_now = xenolift_mem_read32(0x8004FE04u);
    int kick_wanted = (fe04_now != 0u && fe04_now != cd_seek_lba
                       && cd_pending == 0u && cd_scheduled == 0u
                       && cd_arm_int1_pending == 0u);
    /* R213: AT-TARGET SPIN-KICK — cycle-45/46 wedge: the kernel polls
     * GetStat forever (it is WAITING for the next file request to
     * start) with FE04 formed but EQUAL to cd_seek_lba (the drive is
     * already at the target from the previous read) — the R130 kick
     * condition (fe04 != seek) never fires and no slot event re-arms
     * h2 after the Stop. After 32 idle GetStat spins with a formed
     * request + no slot bits armed, step h2 ourselves. */
    int kick3_wanted = (cd_getstat_spins >= 32u && fe04_now != 0u
                        && fe04_now == cd_seek_lba
                        && xenolift_mem[0x56788] == 0u
                        && cd_pending == 0u && cd_scheduled == 0u
                        && cd_arm_int1_pending == 0u);
    /* R155: the register lost the request (walked over by the next
     * read) while the request is still armed and unserved. */
    int kick2_wanted = (xenolift_kick2_armed
                        && xenolift_kick2_lba != 0u
                        && fe04_now != xenolift_kick2_lba
                        && xenolift_mem_read32(0x8004FE1Cu) == 0u
                        && cd_pending <= 1u && cd_scheduled == 0u
                        && cd_arm_int1_pending == 0u
                        && ++xenolift_kick2_ticks > 8);
    /* R137: CONTEXT-INDEPENDENT collector gate. Four contexts have
     * now manifested the same disease (wait-loop 0x80028704, fd
     * 0x80041CA0, legacy 0x80042398, and R136 Mac parked INSIDE the
     * pump fn_80041B3C itself at r31=0x80041BB0). Stop the whack-a-
     * mole: ANY collector call converts an armed-but-undelivered INT
     * (pending!=0, arm1==0) via the proven handler pair. Safety is
     * already guaranteed by the tick body's own conditions + the
     * busy guard + budgets — the r31 list added nothing. */
    /* R204: cycle-37 Mac parked in the LEGACY CD data wait chain
     * (fn_8004293C -> fn_8004299C -> fn_80042A54/58 collector) with a
     * loaded sector (data_loaded=1, FIFO 2060B) that nothing delivered —
     * that spin never hits the pump (0x800415B4) or the fd wait-loop
     * (0x80041410@0x80028704), so the tick never fired. The collector
     * pair 0x80042A54/58 IS a collector context (appears throughout the
     * dispatch ring) — same context-independent conversion applies. */
    if (!cd_tick_busy && (cd_pending != 0u || kick_wanted || kick2_wanted || kick3_wanted)
        && ((a == 0x80041410u && r[31] == 0x80028704u)
            || a == 0x800415B4u
            || a == 0x80042A54u || a == 0x80042A58u)) {
        cd_tick_busy = 1;
        uint8_t saved_bank = cd_index;
        {   /* R403 fld-data camera: fd-tick dispatches during field-data stage */
            static uint32_t fdt_n;
            if (fld_n < 96u && fdt_n < 12u && fld_data_sig()) {
                fprintf(stderr, "[cd] fld-data ctx fd-tick r31=0x%08X pending=%u arm1=%u\n",
                        r[31], cd_pending, cd_arm_int1_pending);
                fdt_n++;
            }
        }
        if (a == 0x800415B4u) {
            static uint32_t ctx_seen[8]; static uint32_t ctx_n;
            int known = 0;
            for (uint32_t i = 0; i < ctx_n && i < 8; i++)
                if (ctx_seen[i] == r[31]) { known = 1; break; }
            if (!known && ctx_n < 8) ctx_seen[ctx_n++] = r[31];
            fprintf(stderr, "[cd] fd-collector tick (r31=0x%08X)%s\n", r[31],
                    known ? "" : " NEW CONTEXT");
            /* R144: in the PUMP context (r31=0x80041BB0) the R143 park
             * sat with nothing armed — show the state the pump waits on. */
            if (r[31] == 0x80041BB0u) {
                static int pb = 24;
                if (pb-- > 0)
                    fprintf(stderr, "[pump] slotbits=%08X t3=%u t6=%u cell564A8=%08X pending=%u arm1=%u cmd=%02X resp_n=%u FE1C=%08X\n",
                            xenolift_mem_read32(0x80056788u),
                            xenolift_mem_read32(0x80056420u + 3u * 4u),
                            xenolift_mem_read32(0x80056420u + 6u * 4u),
                            xenolift_mem_read32(0x800564A8u),
                            cd_pending, cd_arm_int1_pending, cd_last_cmd, cd_resp_n,
                            xenolift_mem_read32(0x8004FE1Cu));
            }
        }
        /* R122: convert a STUCK pending INT1 into a slot event BEFORE
         * the collector scan. The overlay-launch module read (file 18,
         * the manifest's last entry) issues every cycle but never
         * executes: the last early sector's INT1 stays pending
         * (arm1=0) with no consumer in this context, the drive never
         * idles, and the fd pump never services the queued request.
         * The registered handler pair performs the pending->slot
         * conversion — run it here, in the spin context. */
        /* R455 STALL-SIGNATURE CAMERA (c215 verdict: R454 alarm twin placed
         * correctly BEFORE the R122 conversion yet never fired — one of its
         * conditions is false but the digest can't say which. Photograph the
         * full signature every alarm round while a field-region scheduled
         * read exists, so the next digest names the failing bit exactly. */
        if (cd_seek_lba >= 108900u) {
            static uint32_t fld2sig_n;
            if (fld2sig_n < 200u) {
                fprintf(stderr, "[fld2sig] sched=1 seek=%u pend=%u arm1=%u loaded=%u data=%u/%u cmd=%02x FDF8=%u FE04=%08x FDFC=%u FE1C=%u FE20=%u resp_n=%u\n",
                        cd_seek_lba, cd_pending,
                        cd_arm_int1_pending, cd_data_loaded, cd_data_pos,
                        cd_data_n, cd_last_cmd,
                        xenolift_mem_read32(0x8004FDF8u),
                        xenolift_mem_read32(0x8004FE04u),
                        xenolift_mem_read32(0x8004FDFCu),
                        xenolift_mem_read32(0x8004FE1Cu),
                        xenolift_mem_read32(0x8004FE20u), cd_resp_n);
                fprintf(stderr, "[fld2arm] would-arm=%s (need sched=1:%u loaded:%u undrained:%u cmd02:%02x pend0:%u FDF8=0)\n",
                        (cd_scheduled == 1u && cd_pending == 0u && cd_arm_int1_pending == 0
                         && cd_data_loaded && cd_data_pos < cd_data_n
                         && cd_last_cmd == 0x02u && xenolift_mem_read32(0x8004FDF8u) == 0u) ? "YES" : "no",
                        cd_scheduled, cd_data_loaded,
                        (cd_data_pos < cd_data_n) ? 1u : 0u, cd_last_cmd, cd_pending);
                fld2sig_n++;
            }
        }
        /* R454 SCHEDULED-STALL ARM, alarm-context twin (c214 verdict: R453's
         * poll-site arm never fired — the scheduled-wait loop never polls
         * 803-idx1). Signature from c213/c214 parks: sched=1 pending=0
         * arm1=0 loaded+undrained cmd=02 seek>=108900 FDF8=0. The FDF8==0
         * fence keeps every boot/movie scheduled read (nonzero FDF8) out.
         * Pure flag-set, no guest dispatch (R350-safe, same as R122 below). */
        if (cd_scheduled == 1u && cd_pending == 0u && cd_arm_int1_pending == 0
            && cd_data_loaded && cd_data_pos < cd_data_n
            && cd_last_cmd == 0x02u && cd_seek_lba >= 108900u
            && xenolift_mem_read32(0x8004FDF8u) == 0u) {
            cd_pending = 1;
            g_cd_irq_force = 1;
            { static uint32_t fld2a_n;
              if (fld2a_n < 24u) {
                fprintf(stderr, "[fld2-int1] alarm-ctx scheduled batch INT1 armed (seek=%u data=%u/%u sched=1 cmd=02)\n",
                        cd_seek_lba, cd_data_pos, cd_data_n);
                fld2a_n++;
              }
            }
        }
        /* R457 VARIANT-B ARM: c216/c17 camera — halt park of the stall
         * matches every R454 condition except the loaded flag, which was
         * never photographed (and the old arm log line matched NO digest
         * section — could have fired invisibly). Variant B uses the
         * batch-unique signature: seek>=108995 fences tighter than any
         * boot/movie/file-18 read (all earlier eras sit below 108995),
         * no loaded requirement (data_n>0 proves a buffered sector),
         * idempotent flag-set + irq force, R350-safe. Fires with the
         * fld2sig prefix so the widened digest section shows it. */
        if ((cd_scheduled == 1u || cd_read_active == 1u)
            && cd_pending == 0u && cd_arm_int1_pending == 0
            && cd_last_cmd == 0x02u && cd_seek_lba >= 108995u
            && xenolift_mem_read32(0x8004FDF8u) == 0u
            && cd_data_n > 0u) {
            cd_pending = 1;
            g_cd_irq_force = 1;
            { static uint32_t fld2b_n;
              if (fld2b_n < 24u) {
                fprintf(stderr, "[fld2sig] alarm-arm variant-B fired (seek=%u pend set=1 data=%u/%u cmd=02)\n",
                        cd_seek_lba, cd_data_pos, cd_data_n);
                fld2b_n++;
              }
            }
        }
        /* R464: INLINE FREEZE CAMERA — c26/c27: the on_alarm freeze camera is
         * dormant during long native grinds (alarm fires t=30,32,170 ONLY).
         * This inline stepper path runs during the grind — photograph the
         * drive every 15s once sector deliveries stop in the field era. */
        if (cd_seek_lba >= 108900u) {
            static time_t frz2_last_chg; static uint32_t frz2_last_cnt; static uint32_t frz2_n;
            time_t frz2_now = time(NULL);
            if (g_fldsec_total != frz2_last_cnt) {
                frz2_last_cnt = g_fldsec_total; frz2_last_chg = frz2_now;
            } else if (frz2_n < 40u && frz2_now - frz2_last_chg >= 15) {
                fprintf(stderr, "[fldfrz2] t=%lds sectors=%u | seek=%u pend=%u sched=%u act=%u arm1=%u loaded=%u data=%u/%u cmd=%02x resp=%u/%u | FDF8=%u FE04=%08x FE1C=%u FE20=%u FDE4=%08x FDE8=%08x | batch FE08=%08x FE0C=%08x FE10=%08x FE34=%08x | q10=%08x/%08x q18=%08x/%08x | rs+18=%08x rs+1C=%08x FE28=%08x FE2C=%08x\n",
                        (long)(frz2_now - g_boot_wall_t0), g_fldsec_total,
                        cd_seek_lba, cd_pending, cd_scheduled, cd_read_active,
                        cd_arm_int1_pending, cd_data_loaded, cd_data_pos, cd_data_n,
                        cd_last_cmd, cd_resp_n, cd_resp_pos,
                        xenolift_mem_read32(0x8004FDF8u),
                        xenolift_mem_read32(0x8004FE04u),
                        xenolift_mem_read32(0x8004FE1Cu),
                        xenolift_mem_read32(0x8004FE20u),
                        xenolift_mem_read32(0x8004FDE4u),
                        xenolift_mem_read32(0x8004FDE8u),
                        xenolift_mem_read32(0x8004FE08u),
                        xenolift_mem_read32(0x8004FE0Cu),
                        xenolift_mem_read32(0x8004FE10u),
                        xenolift_mem_read32(0x8004FE34u),
                        xenolift_mem_read32(0x80059F10u), xenolift_mem_read32(0x80059F14u),
                        xenolift_mem_read32(0x80059F18u), xenolift_mem_read32(0x80059F1Cu),
                        xenolift_mem_read32(0x80059EF8u + 0x18u), xenolift_mem_read32(0x80059EF8u + 0x1Cu),
                        xenolift_mem_read32(0x8004FE28u), xenolift_mem_read32(0x8004FE2Cu));
                frz2_n++;
            }
        }
        static int conv_budget = 100000;
        if (cd_pending != 0u && cd_arm_int1_pending == 0 && conv_budget > 0) {
            conv_budget--;
            uint32_t sa4 = r[4], sa5 = r[5];
            r[4] = 0; r[5] = 0;
            cd_restore_pend(); /* R308: door 3 */
fprintf(stderr, "[cd] fd-tick: converting stuck INT1 (pending=%u) via handler pair\n", cd_pending);
    {   /* R403 fld-data camera */
        static uint32_t fdc_n;
        if (fdc_n < 12u && fld_data_sig()) {
            fprintf(stderr, "[cd] fld-data ctx conv (pending=%u)\n", cd_pending);
            fdc_n++;
        }
    }
            uint32_t sr[32]; uint32_t shi, slo;
            memcpy(sr, r, sizeof r); shi = hi; slo = lo;
            xenolift_dispatch(0x800409E4u);
            xenolift_dispatch(0x80040A4Cu);
            memcpy(r, sr, sizeof r); hi = shi; lo = slo;
            { /* R471: STACKED-PENDING DRAIN. c34+c35 (both R470, identical
               * photos = real stall, not flake): pending stacked to 3 during
               * the movie-era file-3 kickoff; the guest consumed one answer
               * per conversion pass, leaving its expected event buried behind
               * the queue -> SliceLoopA countdown starved (cntdn 1160620782
               * frozen, FDF8=155120 never drained, boot never drew the menu).
               * c32/c33 won the stack race, c34/c35 lost it — drain ALL
               * stacked events back-to-back like real hardware IRQ delivery:
               * repeat the proven release (restore + handler pair) while the
               * shelf is still loaded, max 3 passes (one per stacked INT). */
                uint32_t r471_n;
                for (r471_n = 0; r471_n < 3u && cd_pending != 0u
                     && cd_arm_int1_pending == 0 && conv_budget > 0; r471_n++) {
                    conv_budget--;
                    cd_restore_pend();
                    fprintf(stderr, "[defib5] R471 stacked-pending drain pass #%u (pending=%u)\n",
                            r471_n + 1u, cd_pending);
                    uint32_t dr[32]; uint32_t dhi, dlo;
                    memcpy(dr, r, sizeof dr); dhi = hi; dlo = lo;
                    xenolift_dispatch(0x800409E4u);
                    xenolift_dispatch(0x80040A4Cu);
                    memcpy(r, dr, sizeof r); hi = dhi; lo = dlo;
                }
            }
        }
        /* R218: STALE-REQUEST RETIREMENT. Cycle-3 R217 digest decoded
         * the archive pre-wait: ReadArchiveMemberIntoBuffer(7) first
         * calls WaitArchiveCdData(0) -> PollArchiveTransfer
         * (fn_800286CC), which returns BUSY while [0x8004FE1C]
         * (file#) != 0 even with the transfer flag FDFC idle. The
         * file batch 10/11 left request markers that can NEVER
         * complete — their FAT entries are empty (size 0 -> FDF8=0,
         * zero bytes to read) — so the pre-wait loops forever and
         * member 7 (REAL: LBA 108886 size 13768) never starts.
         * Real HW semantics: a zero-length request completes
         * instantly. When the marker has sat for 2+ consecutive
         * fd-ticks with zero length, no data, and an idle drive,
         * retire it — same proven release the read-complete path
         * uses (memcpy nudge, kernel re-reads from RAM). */
        {
            static int stale_seen;
            uint32_t fe1c_r = xenolift_mem_read32(0x8004FE1Cu);
            uint32_t fdf8_r = xenolift_mem_read32(0x8004FDF8u);
            if (fe1c_r != 0u && fdf8_r == 0u && !g_movie_live) {
                /* R261: !g_movie_live — cycle-9 retired the movie player's own
                 * FE1C=11 request ("no length"): STR streaming reads (ReadS)
                 * carry NO byte length by design (dir member 10 = 20,893,184B
                 * FMV @LBA 36637, dir member 2 size=0). Retiring it kills the
                 * movie stream before it starts. */
                if (++stale_seen >= 2) {
                    stale_seen = 0;
                    uint32_t zero = 0;
                    memcpy(xenolift_mem + (0x8004FE1Cu & 0x1FFFFFFFu), &zero, 4);
                    memcpy(xenolift_mem + (0x8004FE04u & 0x1FFFFFFFu), &zero, 4);
                    fprintf(stderr, "[cd] fd-retire: stale empty request FE1C=%u -> 0 (no length, drive idle) — releasing the file layer\n",
                            fe1c_r);
                }
            } else {
                stale_seen = 0;
            }
        }
        /* R276: ZERO-LENGTH READ COMPLETION (hardware-faithful).
         * Cycle-24 local decode of fn_8002B084_ArchiveCurrentFileReadyCallback:
         * its advance path does dest += 0x800; remaining -= 0x800; and if the
         * result is <= 0 it calls HandleCdReadyCompletion, zeroes FDF8, and
         * runs PositionArchiveEntry = READ FINALIZED. On hardware the queued
         * ReadN delivers its first sector regardless of the archive layer's
         * byte count, so a zero-length request finalizes on that first
         * advance. Our drive model never loads a sector when FDF8==0 (no
         * demand registered), the callback never runs, and the FSM parks in
         * the 10/11/7 ring forever (counters: state-7 happy branch ran 0x).
         * WEDGE: when the movie is live and the parked signature holds
         * (archive FSM state 7/10/11, FDF8==0, FE04 nonzero), manufacture
         * the hardware first-sector event: cd_data_load() re-anchors on FE04
         * and loads the REAL disc sector + BCD header, then the proven
         * force-deliver runs handler pair + collector + h4 (fallback =
         * fn_8002B084) so the guest's OWN callback does the advance and
         * finalize. One-shot per request LBA (arm on first sight, fire on
         * the second tick = same two-tick pattern as the R219 retirement). */
        {
            static uint32_t zrf_for; static int zrf_armed;
            uint32_t fe1c = xenolift_mem_read32(0x8004FE1Cu);
            uint32_t fdf8 = xenolift_mem_read32(0x8004FDF8u);
            uint32_t fe04 = xenolift_mem_read32(0x8004FE04u);
            /* R335: cycle-83 = the escalation WORKED — the kernel issued a REAL
             * seek (last_cmd=0x09, read_active=1, seek 108606, FE04=0x1A83E) and
             * parked in state 6 (data-wait). The zrf machinery already re-anchors
             * on the CURRENT FE04, but state 6 was not in its trigger set, so
             * the freshly-issued seek starved. State 6 = the legitimate
             * "queued ReadN awaiting first sector" state: hardware delivers
             * that first sector with INT1 -> handler pair -> the guest's own
             * advance->finalize callback. Same service, one more door state. */
            uint32_t zrf_arc_cb = xenolift_mem_read32(0x80059F08u);       /* R552: archive copy callback armed? */
            uint32_t zrf_arc_dst = xenolift_mem_read32(0x8004FE08u);       /* R552: real archive destination? */
            int zrf_real_archive = (zrf_arc_dst >= 0x80010000u && zrf_arc_dst < 0x80200000u); /* R553: c121 — the kernel invokes the archive copier DIRECTLY (cb cell 0x80059F08 read 0 at fire time); judge by DESTINATION alone: a real RAM destination in FE08 means a real file stream is in flight — never manufacture */
            if ((g_movie_live || cd_seek_lba >= 108900u) && fe04 != 0u && fdf8 == 0u && /* R509: same wedge, now era-open — c72-75 field freeze matches this signature exactly (fe04=1A986, fdf8=0, fe1c=10, FE20 3/4) */
                (fe1c == 6u || fe1c == 7u || fe1c == 10u || fe1c == 11u) &&
                !zrf_real_archive) { /* R552: c120 — the dir-loop is DEAD (fe34fix opened the copy gate); when the archive
                                     * callback (0x8002B084) is armed with a real RAM dest (FE08), the read is a REAL file
                                     * stream (file-14 = 125304B) — manufacturing a zero-length sector here lets the
                                     * callback's finalize path stamp the read COMPLETE after 0 real sectors (fe04 -> 0,
                                     * game parks at state 6 mid-stream). Movie-era posture only. */
                /* R536 [zrf-fast]: c104 — flutter needed TWO ticks/sector at 2s cadence =
                 * ~10-20s/sector; 62 sectors can't fit any run budget. In the
                 * file-14 window the posture is terminal (same verdict class as
                 * dirack4 R532): serve the FIRST qualifying tick at each NEW
                 * fe04. Out-of-window keeps the proven arm-then-flutter. */
                int zrf_win_now = (cd_scheduled && fe04 >= 108933u && fe04 < 108995u);
                static uint32_t zrf_win_served;
                if ((zrf_armed && zrf_for == fe04) || (zrf_win_now && zrf_win_served != fe04)) {
                    if (zrf_win_now) zrf_win_served = fe04;
                    zrf_armed = 0;
                    cd_data_load();
                    cd_pending = 1;
                    cd_force_deliver_int1("zrf");
                    { /* R339: Noah sStrSectorHeader — assembler accepts only magic 0x0160 + chunk 0x8001; log what we served */
                        uint8_t *p = cd_data + 12;
                        uint16_t magic = (uint16_t)(p[0] | (p[1] << 8));
                        uint16_t chunk = (uint16_t)(p[2] | (p[3] << 8));
                        uint16_t sn = (uint16_t)(p[4] | (p[5] << 8));
                        uint16_t ns = (uint16_t)(p[6] | (p[7] << 8));
                        uint32_t fr = (uint32_t)p[8] | ((uint32_t)p[9] << 8) | ((uint32_t)p[10] << 16) | ((uint32_t)p[11] << 24);
                        uint16_t w = (uint16_t)(p[16] | (p[17] << 8));
                        uint16_t h = (uint16_t)(p[18] | (p[19] << 8));
                        fprintf(stderr, "[strsec] served LBA %u: magic=%04X chunk=%04X sec=%u/%u frame=%u w=%u h=%u %s\n",
                                fe04, magic, chunk, sn, ns, fr, w, h,
                                (magic == 0x0160u && chunk == 0x8001u) ? "VALID-STR" : "NOT-STR (assembler rejects)");
                    }
                    fprintf(stderr, "[zrf] zero-length read: manufactured first sector @LBA %u (FE1C=%u) — guest callback advance->finalize path armed\n",
                            fe04, fe1c);
                    /* R534 [zrfm]: c102 cmdtl named the loop — the game issues a
                     * REAL ReadN after Setloc, consumes our one manufactured
                     * sector, then gets the SAME sector re-served forever:
                     * cd_data_load() re-anchors to the kernel's expected-LBA
                     * cell (FE04) and the guest callback never advances it in
                     * this era, so the game exhausts, pauses, and re-seeks.
                     * On hardware the drive head auto-advances one sector per
                     * ReadN tick and the kernel's expected-LBA cell follows
                     * (psx-spx: ReadN = continuous read, head advances). Supply
                     * that advance: after each delivered sector, bump FE04 so
                     * the next re-anchor serves the NEXT sector. Window = the
                     * field file-14 span (LBA 108933..108994, end 108995);
                     * beyond the end we stop and the read finalizes. */
                    /* R537 [zrfm-lazy]: c105 exposed DOUBLE-ADVANCE drift — the
                     * game's own consume-handler advances FE04 (fn 800415B4,
                     * FE04T receipts) AND we advanced it at serve time: +2 per
                     * sector. After 5 sectors the game's Setloc target lagged
                     * our FE04 by one, its BCD header compare rejected the
                     * served sector, and it wedged at FE1C=10 (t=61s..park).
                     * FIX: game owns the pointer. Do NOT write at serve time.
                     * Record the served LBA; on the NEXT qualifying tick, only
                     * if the game failed to advance it (FE04 still == served)
                     * do we supply the hardware head-advance (+1). Whichever
                     * mechanism moves first wins — exactly one step per
                     * sector, no drift. */
                    {
                        uint32_t fe04_now = xenolift_mem_read32(0x8004FE04u);
                        static uint32_t zm_served;
                        if (cd_seek_lba >= 108933u && fe04_now >= 108933u && fe04_now < 108995u && cd_scheduled) {
                            if (fe04_now == zm_served && zm_served != 0u) {
                                /* game did NOT advance after consuming our sector
                                 * — supply the head-advance it missed */
                                static int zm_log;
                                xenolift_mem_write32(0x8004FE04u, fe04_now + 1u);
                                if (zm_log < 64) {
                                    zm_log++;
                                    fprintf(stderr, "[zrfm] R537 lazy-advance #%d: game stalled at %u, supplied +1 -> %u (window ends 108995)\n",
                                            zm_log, fe04_now, fe04_now + 1u);
                                }
                            } else if (fe04_now == zm_served + 1u) {
                                static int zg_log;
                                if (zg_log < 64) {
                                    zg_log++;
                                    fprintf(stderr, "[zrfm] R537 game-advanced OK: %u -> %u (no supply needed)\n",
                                            zm_served, fe04_now);
                                }
                            }
                            zm_served = fe04_now;
                        }
                    }
                } else {
                    zrf_armed = 1; zrf_for = fe04;
                }
            } else {
                {
            /* R513: one-shot LBA-0-era dump — the raw file-table entry for member 1
             * (7 bytes @0x800100A5: LBA-3, size-2, flags-2) + the request cells, so the
             * digest shows exactly what the game natively carries for the directory read. */
            static int l0_dumped;
            if (!l0_dumped && cd_seek_lba < 150u) {
                l0_dumped = 1;
                uint32_t e1 = xenolift_mem_read32(0x800100A4u); /* 4 bytes @ entry-1 (align) */
                uint32_t e2 = xenolift_mem_read32(0x800100A8u);
                uint32_t e3 = xenolift_mem_read32(0x800100ACu);
                fprintf(stderr, "[l0tab] R513 member-1 entry bytes: %02X %02X %02X %02X %02X %02X %02X | e2=%08X e3=%08X | rs=%08X %08X %08X | q=%08X %08X\n",
                        e1 & 0xFF, (e1 >> 8) & 0xFF, (e1 >> 16) & 0xFF, (e1 >> 24) & 0xFF,
                        e2 & 0xFF, (e2 >> 8) & 0xFF, e2 & 0xFF000000u ? 0 : ((e2 >> 16) & 0xFF),
                        e2, e3,
                        xenolift_mem_read32(0x80059EF8u + 0x14u), xenolift_mem_read32(0x80059EF8u + 0x18u),
                        xenolift_mem_read32(0x80059EF8u + 0x1Cu),
                        xenolift_mem_read32(0x80059F10u), xenolift_mem_read32(0x80059F14u));
            }
        }
        /* R510: c76 photos — the field FD ring flutters through fe1c=0 between
                 * parked states (6/10/11); the old hard disarm here reset the arm every
                 * other tick, so the wedge never accumulated arm+fire. Keep the arm
                 * alive across the flutter while the target LBA is unchanged. */
                if (fe04 != zrf_for) zrf_armed = 0;
            }

        }
        /* R511: LBA-0 TWIN. c78: the field batch COMPLETED (FDE4 walked home,
         * game closed it and flipped to the disc's directory/system sector at
         * seek 0, MSF 00:02:00) — same parked posture (fdf8==0, fe1c 6/7/10/11,
         * sector sitting in the FIFO, pending INT1 never consumed) but fe04==0
         * there, so the R509/R510 wedge (fe04 != 0) is blind at address zero.
         * Evidence the stall bites: [lzss-inpast] — the game fed the never-
         * delivered buffer to its uncompressor and ran off the input end.
         * Same service as the proven wedge: arm one tick, fire the next,
         * force-deliver INT1 (handler pair + collector + h4 = the guest's own
         * advance->finalize callback). Flutter-tolerant arm (R510 pattern). */
        {
            static int zrf0_armed; static int zrf0_fires;
            uint32_t fe1c0 = xenolift_mem_read32(0x8004FE1Cu);
            uint32_t fdf80 = xenolift_mem_read32(0x8004FDF8u);
            /* R528: c96 — dirack bells ALL fired (R521/526/527 visible in =DIRACK=, game
             * popped GetStat, FDE4 0x13->0x14) but LBA-1 data sat unconsumed
             * 130s: the stall polls FLUTTER FE1C 0<->6 (fld2sig receipts) and
             * fe1c==0 was not in the qualifying set, so the arm never saw two
             * consecutive qualifying polls. Widen the set: with 0 included the
             * 0/6 alternation always pairs -> wedge fires. */
            if (cd_seek_lba < 150u && fdf80 == 0u && cd_data_n >= 2048u && zrf0_fires < 40u &&
                (fe1c0 == 0u || fe1c0 == 6u || fe1c0 == 7u || fe1c0 == 10u || fe1c0 == 11u)) {
                if (zrf0_armed) {
                    zrf0_armed = 0; zrf0_fires++;
                    /* R515: c82 L0TAB verdict — the directory request (member 1)
                     * carries NO length (native entry size -6 -> game registers
                     * FDF8=0) and the 240-line FDF8 write watcher proved NO
                     * guest code ever writes a length in this era. The archive
                     * callback (fn_8002B084) can't copy/finalize without a
                     * countdown. Heal the bookkeeping cell the same way as the
                     * latch/cbheal family: give it ONE sector (2048) only when
                     * zero, so the game's OWN callback does the copy, the
                     * countdown, and the native finalize. If the game wants
                     * more sectors it re-requests and we re-heal. */
                    if (xenolift_mem_read32(0x8004FDF8u) == 0u) {
                        xenolift_mem_write32(0x8004FDF8u, 2048u);
                        fprintf(stderr, "[zrf0] R515: zero-length directory request healed (FDF8 0 -> 2048) fire #%d\n",
                                zrf0_fires);
                    }
                    cd_pending = 1;
                    cd_force_deliver_int1("zrf0");
                    fprintf(stderr, "[zrf0] R511: LBA-0 wedge fire #%d (seek=%u fe1c=%u data_n=%u pend) — guest callback advance->finalize path\n",
                            zrf0_fires, cd_seek_lba, fe1c0, cd_data_n);
                } else {
                    zrf0_armed = 1;
                }
            } else {
                if (cd_seek_lba >= 150u) zrf0_armed = 0;
            }
        }
        /* R130: QUEUED-REQUEST KICK. fn_8004111C points the slot
         * handler cell (0x800564A8) at h2 when StartArchiveRead
         * enqueues a request — "next slot event dispatches h2 to
         * start it". The boot-file reads generate slot events through
         * the native command chain; the LAST queued request (module
         * file 18) starves: the previous read completes, the drive
         * idles, and no event ever wakes h2. Deliver the missing
         * initial event here — dispatch h2 exactly as the wait loop
         * does. h2 is safe to dispatch spuriously (the kernel itself
         * runs idle h2 passes). */
        static int kick_budget = 100000;
        if (kick_wanted && kick_budget > 0) {
            kick_budget--;
            { uint32_t ksr[32]; uint32_t kshi, kslo; /* R199: full ctx */
            memcpy(ksr, r, sizeof r); kshi = hi; kslo = lo;
            if (cd_data_pos < cd_data_n) {
                fprintf(stderr, "[cd] fd-kick: discarding stale FIFO leftover (%u bytes, request done)\n",
                        cd_data_n - cd_data_pos);
                cd_data_pos = cd_data_n = 0;
                cd_data_loaded = 0; /* R167: flag stuck 1 = starved demand */
                cd_arm_int1_pending = 0;
            }
            {   /* R403 fld-data camera */
                static uint32_t fdk_n;
                if (fdk_n < 12u && fld_data_sig()) {
                    fprintf(stderr, "[cd] fld-data ctx kick FE04=0x%08X seek=%u\n",
                            xenolift_mem_read32(0x8004FE04u), cd_seek_lba);
                    fdk_n++;
                }
            }
            fprintf(stderr, "[cd] fd-kick: queued request FE04=0x%08X unserved (seek=%u) — dispatching h2\n",
                    fe04_now, cd_seek_lba);
            xenolift_dispatch(0x800415B4u);
            uint32_t h2k = *(uint32_t *)(xenolift_mem + 0x564A8);
            if (h2k >= 0x80010000u && h2k < 0x80060000u) {
                r[4] = xenolift_mem[0x56788];
                r[5] = 0x8005A210u;
                fprintf(stderr, "[cd] fd-kick: dispatch h2 0x%08X (a0=%u)\n", h2k, r[4]);
                xenolift_dispatch(h2k);
            }
            memcpy(r, ksr, sizeof r); hi = kshi; lo = kslo;
            }
        }
        if (kick3_wanted) {
            cd_getstat_spins = 0;
            { uint32_t ksr[32]; uint32_t kshi, kslo;
            memcpy(ksr, r, sizeof r); kshi = hi; kslo = lo;
            fprintf(stderr, "[cd] spin-kick: kernel polling w/ formed at-target request (FE04=%u) — dispatching h2\n", fe04_now);
            xenolift_dispatch(0x800415B4u);
            uint32_t h2k = *(uint32_t *)(xenolift_mem + 0x564A8);
            if (h2k >= 0x80010000u && h2k < 0x80060000u) {
                r[4] = xenolift_mem[0x56788];
                r[5] = 0x8005A210u;
                fprintf(stderr, "[cd] spin-kick: dispatch h2 0x%08X (a0=%u)\n", h2k, r[4]);
                xenolift_dispatch(h2k);
            }
            memcpy(r, ksr, sizeof r); hi = kshi; lo = kslo;
            }
        }
        /* R155: LOST-REGISTER KICK. The issued request's LBA cell was
         * walked over (FE04 no longer holds it) at drive idle with the
         * request phase cell at 0 — the request was never started.
         * Restore the snapshot and deliver the missing slot event. */
        if (kick2_wanted) {
            xenolift_kick2_armed = 0;
            { uint32_t ksr[32]; uint32_t kshi, kslo; /* R199: full ctx */
            memcpy(ksr, r, sizeof r); kshi = hi; kslo = lo;
            if (cd_data_pos < cd_data_n) {
                fprintf(stderr, "[cd] lost-register kick: discarding stale FIFO leftover (%u bytes)\n",
                        cd_data_n - cd_data_pos);
                cd_data_pos = cd_data_n = 0;
                cd_data_loaded = 0; /* R167: flag stuck 1 = starved demand */
                cd_arm_int1_pending = 0;
            }
            fprintf(stderr, "[cd] lost-register kick: FE04 0x%08X -> 0x%08X (len=%u) — restoring + dispatching h2\n",
                    fe04_now, xenolift_kick2_lba, xenolift_kick2_len);
            xenolift_mem_write32(0x8004FE04u, xenolift_kick2_lba);
            xenolift_mem_write32(0x8004FDF8u, xenolift_kick2_len);
            xenolift_dispatch(0x800415B4u);
            uint32_t h2k2 = xenolift_mem_read32(0x800564A8u);
            if (h2k2 >= 0x80010000u && h2k2 < 0x80060000u) {
                r[4] = xenolift_mem[0x56788];
                r[5] = 0x8005A210u;
                fprintf(stderr, "[cd] lost-register kick: dispatch h2 0x%08X (a0=%u)\n", h2k2, r[4]);
                xenolift_dispatch(h2k2);
            }
            memcpy(r, ksr, sizeof r); hi = kshi; lo = kslo;
            }
        }
        fprintf(stderr, "[cd] wait-loop tick: pending=%u last_cmd=0x%02X arm1=%u\n",
                cd_pending, cd_last_cmd, cd_arm_int1_pending);
        { uint32_t ksr[32]; uint32_t kshi, kslo; /* R199: full ctx */
        memcpy(ksr, r, sizeof r); kshi = hi; kslo = lo;
        for (int i = 0; i < 8; i++) {
            xenolift_dispatch(0x800415B4u);
            uint32_t slots = r[2];
            if (slots == 0u)
                break;
            fprintf(stderr, "[cd] wait-loop event: collector slot=%u\n", slots);
            if (slots & 4u) {
                uint32_t h4 = *(uint32_t *)(xenolift_mem + 0x564AC);
                /* R206: slot-4 handler cell can be EMPTY this round — the
                 * kernel registered the data handler in the READ REQUEST
                 * struct instead (0x80059EF8 +0x10 = 0x8002B084, live in the
                 * =PARK= dump). Cycle-37/39 wedge: slot-4 events flagged,
                 * h4-cell zero -> silent no-dispatch -> sector stuck in the
                 * FIFO mid-read (LBA 108842, FDF8 38384). Fall back to the
                 * read-struct handler; log when the fallback fires. */
                if (!(h4 >= 0x80010000u && h4 < 0x80060000u)) {
                    uint32_t rs_h4 = xenolift_mem_read32(0x80059EF8u + 0x10u);
                    if (rs_h4 >= 0x80010000u && rs_h4 < 0x80060000u) {
                        fprintf(stderr, "[cd] wl: h4 cell empty — falling back to read-struct handler 0x%08X\n", rs_h4);
                        h4 = rs_h4;
                    } else {
                        /* R207: cycle-40 — BOTH mailboxes empty (read
                         * completed + struct reset for the next request,
                         * file#5 chain) while a slot-4 event fires with a
                         * loaded undelivered FIFO. The kernel's data
                         * handler fn_8002B084 is compiled into the image
                         * and stable since R106 (hundreds of proven
                         * dispatches, a0=1) — use it directly. */
                        fprintf(stderr, "[cd] wl: h4 cell + read-struct both empty — known-native h4 0x8002B084\n");
                        h4 = 0x8002B084u;
                    }
                }
                if (h4 >= 0x80010000u && h4 < 0x80060000u && cd_last_cmd == 0x13u) {
                    /* R309: h4 (0x8002B084) = ArchiveCurrentFileReadyCallback — SECTOR-DATA
                     * handler only (manual cycle-57). Dispatching it after a GetTN command
                     * completion is WRONG ROUTING: h4 never reads the response FIFO; it
                     * fetches sectors, compares the read-struct location vs FE04, and on
                     * mismatch bumps its own retry counter (0x8006A4DC) + re-arms FE20=3/4,
                     * FE1C=10 -> AC14 issues GetTN again = the endless 3<->4 verify loop.
                     * On hardware the GetTN INT3 routes to the command-completion event
                     * (slot-2 / state machine), whose continuation READS the 3-byte answer
                     * (still whole in the FIFO, resp_pos=0 at park = nobody ever read it).
                     * Route like R285's ladder-completion sync: set the op-flag cell and
                     * let the slot-2 state machine dispatch consume the answer natively. */
                    uint16_t one = 1;
                    memcpy(xenolift_mem + (0x800578A6u & 0x1FFFFFFFu), &one, 2);
                    fprintf(stderr, "[cd] TOC-ROUTE: GetTN completion -> state machine (slot-2), NOT h4 (sector handler)\n");
                } else if (h4 >= 0x80010000u && h4 < 0x80060000u) {
                    r[4] = xenolift_mem[0x56789];
                    r[5] = 0x8005A218u;
                    fprintf(stderr, "[cd] wait-loop: dispatch h4 0x%08X (a0=%u)\n", h4, r[4]);
                    xenolift_dispatch(h4);
                }
            }
            if (slots & 2u) {
                uint32_t h2 = *(uint32_t *)(xenolift_mem + 0x564A8);
                if (h2 >= 0x80010000u && h2 < 0x80060000u) {
                    r[4] = xenolift_mem[0x56788];
                    r[5] = 0x8005A210u;
                    fprintf(stderr, "[cd] wait-loop: dispatch h2 0x%08X (a0=%u)\n", h2, r[4]);
                    xenolift_dispatch(h2);
                }
            }
            if (slots & 1u) {
                /* R210: cycles 41-43 ALL end on a slot-1 collector event
                 * with NO handler in this block (only 4 and 2 dispatched).
                 * Drive idle post-Stop (last_cmd=0x08, INT2 armed),
                 * file#7 request at FE04 formed but never stepped. Slot
                 * 1 = response/completion class; step the proven request
                 * stepper h2 (safe idle dispatch, =SLOT= proof) on the
                 * second consecutive slot-1 while the drive is idle. */
                /* R211: the slot-1 event fires ONCE, it never streaks —
                 * R210's streak>=2 guard never opened. Park confirms the
                 * event bits (0x80056788 = 0x03 = slots 1+2) stay ARMED
                 * while the kernel waits: observed but never acted on.
                 * Dispatch the slot-1 handler cell 0x564A4 on first sight
                 * while idle; fall back to the proven h2 request stepper
                 * (file#7 request formed at FE04, needs stepping). */
                if (!cd_read_active && !cd_pending) {
                    uint32_t h1 = *(uint32_t *)(xenolift_mem + 0x564A4);
                    uint32_t tgt = h1;
                    if (!(tgt >= 0x80010000u && tgt < 0x80060000u)) {
                        tgt = *(uint32_t *)(xenolift_mem + 0x564A8);
                        fprintf(stderr, "[cd] wl: slot-1 — cell 0x564A4 empty (0x%08X), falling back to h2 stepper\n", h1);
                    }
                    if (tgt >= 0x80010000u && tgt < 0x80060000u) {
                        r[4] = xenolift_mem[0x56788];
                        r[5] = 0x8005A210u;
                        fprintf(stderr, "[cd] wl: slot-1 — dispatching 0x%08X (a0=%u)\n", tgt, r[4]);
                        xenolift_dispatch(tgt);
                    }
                }
            }
        }
        memcpy(r, ksr, sizeof r); hi = kshi; lo = kslo;
        }
        /* R101: the BIOS calls the kernel's registered CD interrupt
         * handler(s) from IRQ context when the drive raises INT1/INT3.
         * We run the command layer through event forces, but the DATA
         * path (sector DMA via the kernel's DMA cells -> ch3 CHCR)
         * only runs inside the registered handler. Dispatch the pair
         * {0x800409E4, 0x80040A4C} (registered at SysEnqIntRP struct
         * 0x8005A200) BIOS-style at the tick when INT1 is armed. */
        if (g_cd_irq_force) {
            g_cd_irq_force = 0;
            uint32_t sa4 = r[4], sa5 = r[5];
            r[4] = 0; r[5] = 0;
            /* R102: the kernel's polling sync already ACKed the flag
             * (cd_pending cleared) before we run the pair — on real HW
             * the IRQ handler reads the flag WHILE SET, then acks. Re-
             * assert it for the handler; its own code acks when done. */
            cd_pending = 1;
            fprintf(stderr, "[cd] CD IRQ handler pair dispatch (INT1 re-asserted, LBA %u)\n", cd_seek_lba);
            uint32_t sr[32]; uint32_t shi, slo;
            memcpy(sr, r, sizeof r); shi = hi; slo = lo;
            xenolift_dispatch(0x800409E4u);
            xenolift_dispatch(0x80040A4Cu);
            memcpy(r, sr, sizeof r); hi = shi; lo = slo;
        }
        cd_index = saved_bank; /* pump restores the bank after collecting */
        /* Request-complete exit: the notify chain (fn 0x8002A394) set the
         * CDFS state cell FE1C=5 ("read finished, result pending for the
         * file layer"). In the synchronous-read path the file layer is
         * blocked in fn 0x80028A60, which only returns when FE1C==0 —
         * on real hardware the kernel's thread switcher (the event walk
         * in fn 0x8003A68C) wakes the waiter. We can't switch stacks, so
         * give it the same nudge the Setmode cycle gets: only when the
         * whole request drained (FDF8==0) and the completion state is
         * pending, release the wait so the file layer picks up its
         * result struct (filled at 0x80059F10 by the notify). */
        if (xenolift_mem_read32(0x8004FE1Cu) == 5u
            && xenolift_mem_read32(0x8004FDF8u) == 0u) {
            uint32_t zero = 0;
            memcpy(xenolift_mem + (0x8004FE1Cu & 0x1FFFFFFFu), &zero, 4);
            fprintf(stderr, "[cd] read complete: FE1C 5 -> 0, releasing the file layer's wait\n");
        }
        cd_tick_busy = 0; /* R111 */
    }
    /* Second async-wait cell: FDFC (0x8004FDFC) = "async command in
     * flight". Setloc and friends complete in interrupt context on real
     * hardware; without IRQs the wait loop (fn 0x800286CC) polls it
     * forever BEFORE any delivery trigger (cdsync etc.) can run, since
     * the FDFC check short-circuits the loop. Force-complete the wait on
     * loop entry when a scheduled response never got a delivery trigger:
     * deliver it now (flag for the next pump pass to consume) and clear
     * FDFC so the kernel's own flow proceeds. */
    if (a == 0x800286CCu && cd_scheduled && cd_pending == 0u
        && !(cd_read_active && xenolift_mem_read32(0x8004FDF8u) != 0u
             && cd_last_cmd != 0x02u)) { /* R97: Setloc acks are safe mid-stream */
        uint32_t fdfc;
        memcpy(&fdfc, xenolift_mem + (0x8004FDFCu & 0x1FFFFFFFu), 4);
        if (fdfc != 0u) {
            cd_scheduled = 0;
            cd_pending = 3;
            uint16_t one = 1;
            memcpy(xenolift_mem + (0x800578A6u & 0x1FFFFFFFu), &one, 2);
            uint32_t zero = 0;
            memcpy(xenolift_mem + (0x8004FDFCu & 0x1FFFFFFFu), &zero, 4);
            fprintf(stderr, "[cd] FDFC=%08X with scheduled cmd 0x%02X: delivered, FDFC forced 0\n",
                    fdfc, cd_last_cmd);
        }
    }
    /* breakpoint-style probes for the CD detect chain (gdb unavailable) */
    if (a == 0x80042088u)
        fprintf(stderr, "[bp] probe(a0=%d a1=%d) slot=%d flag=%d type=%d "
                        "devcnt=%d tbl=%08X\n",
                r[4], r[5], xenolift_mem[0x56788],
                *(uint16_t *)(xenolift_mem + 0x578A6), xenolift_mem[0x564C9],
                (int)(int32_t)xenolift_mem_read32(0x800564B4u),
                xenolift_mem_read32(0x800566F0u + (r[4] & 0xFF) * 4));
    else if (a == 0x80041B3Cu)
        fprintf(stderr, "[bp] pump(a0=%d a1=%d) slot=%d flag=%d h2=%08X h4=%08X\n",
                r[4], r[5], xenolift_mem[0x56788],
                *(uint16_t *)(xenolift_mem + 0x578A6),
                *(uint32_t *)(xenolift_mem + 0x564A8),
                *(uint32_t *)(xenolift_mem + 0x564AC));
    else if (a == 0x80042750u)
        fprintf(stderr, "[bp] detect(a0=%d) slot=%d\n", r[4], xenolift_mem[0x56788]);
    else if (a == 0x8002B084u)
        fprintf(stderr, "[bp] DATA HANDLER enter a0=%08X a1=%08X slot=%d | FE34=%08X FE08=%08X FDF8=%08X FE04=%08X FE38=%08X\n",
                r[4], r[5], xenolift_mem[0x56788],
                *(uint32_t *)(xenolift_mem + 0x4FE34),
                *(uint32_t *)(xenolift_mem + 0x4FE08),
                *(uint32_t *)(xenolift_mem + 0x4FDF8),
                *(uint32_t *)(xenolift_mem + 0x4FE04),
                *(uint32_t *)(xenolift_mem + 0x4FE38));
    if (g_trace_lines >= 400) {
        if (g_trace_lines == 400) {
            fprintf(stderr, "[trace] (trace capped at 400 lines)\n");
            g_trace_lines++;
        }
        return;
    }
    /* at most the first 3 entries per function: a hot wait loop
     * alternates between two addresses and would otherwise eat the
     * entire 400-line budget before anything interesting happens */
    if (a >= 0x80010000u && a < 0x80059800u) {
        static uint8_t per[76000];
        uint32_t i = (a - 0x80010000u) >> 2;
        if (i < sizeof per) {
            if (per[i] >= 3) {
                return;
            }
            per[i]++;
        }
    }
    fprintf(stderr, "[trace] enter 0x%08X\n", a);
    g_trace_lines++;
}

void xenolift_syscall(void)
{
    /* the kernel also reaches BIOS services through the `syscall`
     * INSTRUCTION — same convention as the jump gates: gate in r10 (t2),
     * function number in r9 (t1). The handler does its work and
     * execution continues right after the syscall. */
    /* SYS functions: the number is in r4 (a0) — per the spec. The kernel's
     * BIOS gate calls NEVER come through the syscall instruction: those
     * are real jalr jumps to 0xA0/0xB0/0xC0, handled by xenolift_dispatch.
     * (Reading r9/r10 here once produced "ghost" BIOS log lines — those
     * registers just held leftovers from an earlier gate call.) */
    static uint8_t seen[256];
    uint32_t fn = r[4] & 0xFFu;
    switch (fn) {
    case 0: /* NoFunction */
        r[2] = 0;
        return;
    case 1: /* EnterCriticalSection: 0 = "interrupts were already disabled",
             * permanently true in our no-interrupt model */
        r[2] = 0;
        return;
    case 2: /* ExitCriticalSection */
        r[2] = 0;
        return;
    case 3: /* ChangeThreadSubFunction(addr in r5) — the thread switcher */
        if (!seen[fn]) {
            seen[fn] = 1;
            fprintf(stderr, "[sys] ChangeThreadSubFunction(0x%08X) — stubbed\n", r[5]);
        }
        r[2] = 0;
        return;
    default: /* SYS(04h..FFFFFFFFh): DeliverEvent(F0000010h,4000h) */
        if (!seen[4]) {
            seen[4] = 1;
            fprintf(stderr, "[sys] DeliverEvent-class syscall (0x%08X) — stubbed\n", r[4]);
        }
        r[2] = 0;
        return;
    }
}

void xenolift_break(uint32_t code)
{
    /* R90: break = the kernel's SOFTWARE-INTERRUPT GATE. The 0x8004C3xx
     * farm (svc codes 0x101-0x107) is a break-stub syscall table: each
     * stub shifts args up one slot (BIOS-gate convention: the service
     * receives original (a0,a1,a2) as (a1,a2,a3)), executes `break
     * <code>`, then interprets v0/v1: v0==0 -> return v1, else -1.
     * Service 0x103 (fn_8004C318, called from the CD module fn_800287xx
     * with a descriptor-table handler in a1) = INDIRECT CALL TRAMPOLINE:
     * call the handler with (a2, a3); the handler's v0/v1 flow back. */
    if (code == 0x103u) {
        uint32_t fn = r[5];
        uint32_t a2 = r[6], a3 = r[7];
        fprintf(stderr, "[brk] svc 0x103 trampoline call fn=%08X arg=%08X %08X\n",
                fn, a2, a3);
        r[4] = a2; r[5] = a3;
        xenolift_dispatch(fn);   /* callee sets v0=r2, v1=r3 */
        return;
    }
    fprintf(stderr, "[brk] unhandled break code 0x%X a0=%08X a1=%08X a2=%08X a3=%08X\n",
            code, r[4], r[5], r[6], r[7]);
    halt_report("break instruction", 0);
}

/* R185: shared COP0 register-file mirror (indexing matches COP0 rd
 * numbers: 8=BadVAddr, 12=SR, 13=Cause, 14=EPC, 15=PRID). The kernel's
 * exception handler reads these via MFC0 — with REAL fault context the
 * kernel's own recovery works the way it does on hardware. */
uint32_t xenolift_cop0_regs[32];
void xenolift_cop0_exception(uint32_t bad_vaddr, uint32_t fault_pc_approx)
{
    uint32_t sr_prev = xenolift_cop0_regs[12];
    xenolift_cop0_regs[12] = (sr_prev & ~0x2u) | 0x2u | 0x1000u; /* SR: EXL set, IE off while handling */
    xenolift_cop0_regs[8]  = bad_vaddr;       /* BadVAddr */
    xenolift_cop0_regs[13] = (0x05u << 2);    /* Cause: ExcCode 5 = AdES (computed-store fault) */
    xenolift_cop0_regs[14] = fault_pc_approx; /* EPC (function-granular) */
    fprintf(stderr, "[bxcep] EXCEPTION CONTEXT set: BadVAddr=0x%08X Cause=0x%08X EPC=0x%08X SR=0x%08X\n",
            xenolift_cop0_regs[8], xenolift_cop0_regs[13],
            xenolift_cop0_regs[14], xenolift_cop0_regs[12]);
}

void xenolift_cop_stub(uint32_t word)
{
    uint32_t op = (word >> 26) & 0x3Fu;
    uint32_t rs = (word >> 21) & 0x1Fu;
    uint32_t rt = (word >> 16) & 0x1Fu;
    uint32_t rd = (word >> 11) & 0x1Fu;

    if (op == 0x10) {
        /* COP0 — the CPU's own control registers (status, cause, TLB).
         * R185: register file now lives in the shared mirror array so the
         * exception-context path can write REAL fault state (EPC/Cause/
         * BadVAddr/SR) that the kernel's exception handler reads via MFC0. */
        if (!xenolift_cop0_regs[15]) xenolift_cop0_regs[15] = 0x02u; /* PRID */
        if (rs == 0) { /* MFC0 rt, rd */
            r[rt] = xenolift_cop0_regs[rd];
            return;
        }
        if (rs == 4) { /* MTC0 rt, rd */
            xenolift_cop0_regs[rd] = r[rt];
            return;
        }
        if (word & 0x02000000u) {
            /* CO form: RFE and the TLB ops. Our model has flat memory
             * (no TLB) and interrupts are effectively always disabled,
             * so every one of these is a no-op. */
            return;
        }
        /* BC0 branches (rs == 8): no pending exceptions exist in our
         * model, so "not taken" is the faithful answer; log once. */
        {
            static uint8_t logged[256];
            if (!logged[word & 0xFFu]) {
                logged[word & 0xFFu] = 1;
                fprintf(stderr, "[cop0] branch word 0x%08X treated as not-taken\n", word);
            }
            return;
        }
    }

    if (op == 0x11) {
        /* COP1: the PS1 has NO floating-point coprocessor — this word
         * is junk (data decoded as code). No-op it and keep going. */
        static uint8_t logged[256];
        if (!logged[word & 0xFFu]) {
            logged[word & 0xFFu] = 1;
            fprintf(stderr, "[cop1] junk word 0x%08X no-op'd\n", word);
        }
        return;
    }

    /* ---- COP2: the GTE, the PS1's 3D math chip ----
     * 64 data registers (cop2r) and 32 control registers (cop2c).
     * Register MOVES are implemented now; the math commands (RTPS,
     * MVMVA, NCLIP, ...) still halt, by name, until that milestone. */
    /* R136: the local register file is gone — hle_gte owns GTE state.
     * Moves/transfers route through it so math commands see everything. */

    if (op == 0x12 && (word & 0x02000000u) == 0) {
        /* rs-form: register moves */
        static const char *kind[8] = {
            "MFC2", NULL, "CFC2", NULL, "MTC2", NULL, "CTC2", NULL
        };
        static uint8_t seen[8];
        if (rs < 8 && kind[rs] && !seen[rs]) {
            seen[rs] = 1;
            fprintf(stderr, "[gte] %s register moves online (data+ctrl file)\n", kind[rs]);
        }
        switch (rs) {
        case 0: /* MFC2 rt, rd */
            r[rt] = hle_gte_read_data(rd);
            return;
        case 2: /* CFC2 rt, rd */
            r[rt] = hle_gte_read_ctrl(rd);
            return;
        case 4: /* MTC2 rt, rd */
            hle_gte_write_data(rd, r[rt]);
            return;
        case 6: /* CTC2 rt, rd */
            hle_gte_write_ctrl(rd, r[rt]);
            return;
        default:
            return; /* BC2 branches: no GTE exceptions exist in our model */
        }
    }

    if (op == 0x32 || op == 0x3A) { /* LWC2 / SWC2: GTE <-> RAM */
        uint32_t base = r[(word >> 21) & 0x1Fu];
        int32_t imm = (int16_t)(word & 0xFFFFu);
        uint32_t idx = (word >> 16) & 0x1Fu;
        uint32_t ea = (base + (uint32_t)imm) & 0xFFFFFFFFu;
        static uint8_t logged;
        if (!logged) {
            logged = 1;
            fprintf(stderr, "[gte] %s data transfers online\n",
                    op == 0x32 ? "LWC2" : "SWC2");
        }
        if (op == 0x32) {
            hle_gte_write_data(idx, xenolift_mem_read32(ea));
        } else {
            xenolift_mem_write32(ea, hle_gte_read_data(idx));
        }
        return;
    }

    if (op == 0x12) {
        /* CO form: an actual GTE math command. Name it and halt. */
        static const char *cmds[64] = {
            NULL, "RTPS", NULL, NULL, NULL, NULL, "NCLIP", NULL,
            NULL, NULL, NULL, NULL, "OP", NULL, NULL, NULL,
            "DPCS", "INTPL", "MVMVA", "NCDS", "CDP", NULL, "NCDT", NULL,
            NULL, NULL, "NCCS", "CC", NULL, "NCS", NULL, NULL,
            "NCT", NULL, NULL, NULL, NULL, NULL, NULL, NULL,
            "SQR", "DCPL", "DPCT", NULL, NULL, NULL, NULL, NULL,
            NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
            NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
            NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
        };
        /* index: 0x28 SQR, 0x29 DCPL, 0x2A DPCT, 0x2D AVSZ3, 0x2E AVSZ4,
         * 0x30 RTPT, 0x3D GPF, 0x3E GPL, 0x3F NCCT */
        const char *name = NULL;
        uint32_t fn = word & 0x3Fu;
        if (cmds[fn] != NULL) {
            name = cmds[fn];
        } else {
            switch (fn) {
            case 0x28: name = "SQR"; break;
            case 0x29: name = "DCPL"; break;
            case 0x2A: name = "DPCT"; break;
            case 0x2D: name = "AVSZ3"; break;
            case 0x2E: name = "AVSZ4"; break;
            case 0x30: name = "RTPT"; break;
            case 0x3D: name = "GPF"; break;
            case 0x3E: name = "GPL"; break;
            case 0x3F: name = "NCCT"; break;
            default: name = "?"; break;
            }
        }
        /* R136: GTE math EXECUTES now (hle_gte verified 8/8 — RTPS
         * sf-inversion + disasm table fixed by the GTE agent). The
         * halt-class is retired; the kernel can draw 3D through us. */
        hle_gte_execute(word);
        if (++xl_gte_cmds <= 4u)
            fprintf(stderr, "[gte] MATH command: %s (0x%02X) -> hle_gte #%u\n",
                    name, fn, xl_gte_cmds);
        return;
    }

    halt_report("unhandled coprocessor word", word);
}


/* R70: fn_800320E8(NULL) is the kernel TRAP: records caller (ra-8) into
 * gp+464 (0x80059340), latches error at gp+0x1C0 (0x80059330), then calls
 * fn_80019ACC(0x83) -> SystemError. Called from emitted dispatch. */
static int trap_n = 0;
void xenolift_trap_hook(uint32_t ra, uint32_t gp)
{
    (void)gp;
    uint32_t latch;
    memcpy(&latch, xenolift_mem + (0x80059330u-0x80000000u), 4);
    trap_n++;
    if (trap_n <= 40 || trap_n % 1000 == 0)
        fprintf(stderr, "[err] NULL-trap #%d caller 0x%08X latch 0x%08X\n", trap_n, ra - 8u, latch);
    if (trap_n <= 3) { /* R303: full forensics at the movie-finale release fault —
        * dump ALL registers + the module descriptor neighborhood (0x80077440-70:
        * 77454=flag, 77458=stage2base, 7745C/60 = UNDUMPED candidates for the
        * cfg-buffer handle the finale passes to ReleaseHeapBlock) + block headers
        * (0x80077C40-70). Cycle-51: a0@fn_80073B28 was VALID (0x8004FE44) — only
        * the release handle r20=0 traps. Find which cell lost it. */
        fprintf(stderr, "[trap3] regs: r4=%08X r5=%08X r16=%08X r17=%08X r18=%08X r20=%08X r21=%08X r28=%08X r29=%08X r31=%08X\n",
                r[4], r[5], r[16], r[17], r[18], r[20], r[21], r[28], r[29], r[31]);
        fprintf(stderr, "[trap3] desc 77440-77470: %08X %08X %08X %08X | %08X %08X %08X %08X | %08X %08X %08X %08X\n",
                xenolift_mem_read32(0x80077440u), xenolift_mem_read32(0x80077444u),
                xenolift_mem_read32(0x80077448u), xenolift_mem_read32(0x8007744Cu),
                xenolift_mem_read32(0x80077450u), xenolift_mem_read32(0x80077454u),
                xenolift_mem_read32(0x80077458u), xenolift_mem_read32(0x8007745Cu),
                xenolift_mem_read32(0x80077460u), xenolift_mem_read32(0x80077464u),
                xenolift_mem_read32(0x80077468u), xenolift_mem_read32(0x8007746Cu));
        fprintf(stderr, "[trap3] hdr 77C40-77C70: %08X %08X %08X %08X | %08X %08X %08X %08X | %08X %08X %08X %08X\n",
                xenolift_mem_read32(0x80077C40u), xenolift_mem_read32(0x80077C44u),
                xenolift_mem_read32(0x80077C48u), xenolift_mem_read32(0x80077C4Cu),
                xenolift_mem_read32(0x80077C50u), xenolift_mem_read32(0x80077C54u),
                xenolift_mem_read32(0x80077C58u), xenolift_mem_read32(0x80077C5Cu),
                xenolift_mem_read32(0x80077C60u), xenolift_mem_read32(0x80077C64u),
                xenolift_mem_read32(0x80077C68u), xenolift_mem_read32(0x80077C6Cu));
    }
}

/* R70: boot state machine entry trace: fn_80019ACC(code) — 0x83 = error
 * trap from walker, 0 = process current table entry. */
static int bs_n = 0;
void xenolift_boot_trace(uint32_t code)
{
    uint32_t idx;
    memcpy(&idx, xenolift_mem + (0x80018088u-0x80000000u), 4);
    bs_n++;
    if (bs_n <= 40 || bs_n % 1000 == 0)
        fprintf(stderr, "[boot] fn_80019ACC(%u) idx=%u r31=0x%08X\n", code, idx, r[31]);
    /* R502 LATCH RESCUE (c68 decode): the walker's verdict branch
     * (L_80031DA8, r6!=0 done-path) reads gp+0x1C0 = 0x80059330:
     * nonzero -> fn_80031F58 advance (healthy), zero -> it hands the
     * main loop the hardcoded fault verdict r4=0x82 and the boot
     * ends on the crash screen. Our latch is armed at boot
     * (fn_80019524 writes 1) and pad_fill re-arms it, yet the verdict
     * keeps seeing 0 -> something clears it after the last pad kick.
     * At the verdict moment itself: log the latch, and if unarmed,
     * re-arm it AND clear the fault verdict (r4 -> 0 = the loop's
     * normal-run path: GPU reinit, callbacks, then subsystem 0 =
     * RunKernelMenu). Same only-when-zero discipline as the R89
     * re-arm: never clobber a value the game just set. */
    if (code == 0x82u) {
        uint32_t latch;
        memcpy(&latch, xenolift_mem + 0x59330u, 4);
        fprintf(stderr, "[latchw] R502 verdict moment: latch 0x80059330=%08X idx=%u r31=0x%08X\n",
                latch, idx, r[31]);
        if (latch == 0u) {
            uint32_t one = 1u;
            memcpy(xenolift_mem + 0x59330u, &one, 4);
            r[4] = 0u; /* fault verdict cleared -> loop runs healthy path */
            fprintf(stderr, "[latchfix] R502: latch re-armed (1) + fault verdict 0x82 -> 0 - main loop rerun healthy, menu is next\n");
        }
    }
    /* R347: field-era marker — one-shot, lets the digest slice everything after the movie->field handoff */
    if (idx == 1 && code == 0) {
        static int fld_marked = 0;
        if (!fld_marked) {
            fld_marked = 1;
            g_field_era = 1;
            fprintf(stderr, "[fld] FIELD ERA START (movie finished, state-1 entered) r31=0x%08X FE04=0x%08X FDF8=%u\n",
                    r[31], xenolift_mem_read32(0x8004FE04u), xenolift_mem_read32(0x8004FDF8u));
        }
    }
}


void xenolift_unknown(uint32_t word)
{
    if (bios_hook(word)) {
        return; /* synthetic BIOS hook serviced — continue execution */
    }
    /* R225: STAGE-2 CAPTURE. The movie module (now executing post-R224) reads
     * an 88,604B second-stage payload from the disc into 0x801D3000 (its own
     * allocation, 132,256B) and calls 0x801D3538 inside the FIRST sector while
     * the stream is still mid-flight — legal on real HW, but the region has no
     * compiled code yet. Before halting (by design: tells us what to build
     * next), complete the pending read directly from the disc image and dump
     * the region so the next cycle's emitter can map it. */
    if (word >= 0x801D3000u && word < 0x801F1000u) {
        uint32_t lba = xenolift_mem_read32(0x8004FE04u);
        uint32_t rem = xenolift_mem_read32(0x8004FDF8u);
        uint32_t base = 0x801D3000u, nsec = (rem + 2047u) / 2048u;
        fprintf(stderr, "[stage2] unresolved jump 0x%08X into loading region — completing read LBA=%u rem=%u (%u sectors)\n",
                word, lba, rem, nsec);
        if (lba >= 150u && nsec > 0u && nsec < 256u) {
            for (uint32_t i = 0; i < nsec; i++)
                disc_read_lba(lba + i, xenolift_mem + (base - 0x80000000u) + i * 2048u);
            fprintf(stderr, "[stage2] region 0x801D3000 filled: LBA %u..%u (%u bytes)\n",
                    lba, lba + nsec - 1u, nsec * 2048u);
        }
        { /* release the file layer the same way the read-complete path does */
            uint32_t zero = 0;
            memcpy(xenolift_mem + (0x8004FDF8u & 0x1FFFFFFFu), &zero, 4);
            memcpy(xenolift_mem + (0x8004FE1Cu & 0x1FFFFFFFu), &zero, 4);
            memcpy(xenolift_mem + (0x8004FE04u & 0x1FFFFFFFu), &zero, 4);
        }
        { /* dump 0x801D3000-0x801F4000 for the emitter */
            FILE *sf = fopen("stage2_region.bin", "wb");
            if (sf) {
                fwrite(xenolift_mem + (base - 0x80000000u), 1, 0x21000u, sf);
                fclose(sf);
                fprintf(stderr, "[stage2] capture: 0x801D3000-0x801F4000 (135,168 bytes) -> stage2_region.bin — next cycle the emitter maps this window\n");
            }
        }
        { /* log the first words at the call target so the next decode has context */
            uint32_t t = word & ~3u;
            fprintf(stderr, "[stage2] target 0x%08X first16:", t);
            for (int i = 0; i < 16; i++)
                fprintf(stderr, " %08X", xenolift_mem_read32(t + 4u * (uint32_t)i));
            fprintf(stderr, "\n");
        }
    }
    {   /* R680: WHO computed the wild target? c251: halt-scan named the killer
         * (target 0xF00E1220, NOT in RAM = in-register computed) but printed no
         * site context. Dump the fault site BEFORE the halt machinery: caller
         * (r31), live fn, arg regs, the field-commit cells, and the guest stack
         * top (8 words at sp = the return-address chain). */
        fprintf(stderr, "[wildctx] R680 unresolved jump 0x%08X @t=%lds: cur_fn=0x%08X r31=0x%08X r4=%08X r5=%08X r6=%08X r7=%08X r16=%08X r17=%08X r29sp=%08X | 92C0=%08X FAEC=%08X F0C=%08X FE04=%08X\n",
                word, (long)(time(NULL) - g_boot_wall_t0),
                (unsigned)xenolift_cur_fn, r[31], r[4], r[5], r[6], r[7], r[16], r[17], r[29],
                xenolift_mem_read32(0x800592C0u), xenolift_mem_read32(0x8005FAECu),
                xenolift_mem_read32(0x80059F0Cu), xenolift_mem_read32(0x8004FE04u));
        {   /* guest stack top: return-address chain near sp */
            for (int i = 0; i < 8; i++) {
                uint32_t a = r[29] + 4u * (uint32_t)i;
                if (a >= 0x80000000u && a + 4 <= 0x80000000u + XENOLIFT_RAM_SIZE)
                    fprintf(stderr, "[wildctx] sp+%02d [%08X] = %08X\n", i*4, a, xenolift_mem_read32(a));
            }
        }
        {   /* R681 [ovlfault]: the pre-menu overlay capture has ZEROS where the
             * field coordinator installs (0x8E88 in-window proof) - the emitter
             * compiled a blank page and the dispatch computed garbage. Capture
             * the window AT THE FAULT MOMENT (coordinator installed) so the
             * emitter maps real code over the stale pre-menu snapshot. */
            FILE *of = fopen("overlay_fault.bin", "wb");
            if (of) {
                fwrite(xenolift_mem + (0x8006F000u - 0x80000000u), 1, 0x21000u, of);
                fclose(of);
                fprintf(stderr, "[ovlfault] R681 overlay window 0x8006F000-0x80090000 captured at fault moment -> overlay_fault.bin (next cycle the emitter maps the REAL field coordinator over the pre-menu zeros)\n");
            }
        }
    }
    {   /* R680: RELAUNCH AT THE FAULT SITE. c246-251 converged: the kernel
         * design is pick-state -> unwind -> shell re-enters the program. The
         * program never gets to unwind on our host (the fault exit ends the
         * process before main regains control - c250's proof). So emulate the
         * shell right HERE: if the field is committed, re-enter the boot chain.
         * The boot's own BSS clear resets kernel cells; cap 2 restarts. */
        static uint32_t r680_n;
        if (r680_n < 2u &&
            (xenolift_mem_read32(0x800592C0u) == 1u ||
             xenolift_mem_read32(0x8005FAECu) >= 1u)) {
            r680_n++;
            fprintf(stderr, "[mtrans] R680 shell RESTART #%u at fault site @t=%lds (field committed: 92C0=%08X FAEC=%08X) - re-entering boot like the console shell would\n",
                    r680_n, (long)(time(NULL) - g_boot_wall_t0),
                    xenolift_mem_read32(0x800592C0u), xenolift_mem_read32(0x8005FAECu));
            r[31] = 0; hi = lo = 0;
            xenolift_region();
        }
    }
    halt_report("unknown instruction / unresolved indirect jump", word);
}

/* ---- the "disc": load a PS-X EXE into fake RAM, mirroring the console ---- */

static void load_exe(const char *path)
{
    FILE *f = fopen(path, "rb");
    if (!f) {
        perror(path);
        exit(1);
    }
    fseek(f, 0, SEEK_END);
    long len = ftell(f);
    fseek(f, 0, SEEK_SET);
    uint8_t *buf = malloc((size_t)len);
    if (!buf || fread(buf, 1, (size_t)len, f) != (size_t)len) {
        fprintf(stderr, "error: cannot read %s\n", path);
        exit(1);
    }
    fclose(f);

    if (len < 0x800 || memcmp(buf, "PS-X EXE", 8) != 0) {
        fprintf(stderr, "error: not a PS-X EXE image\n");
        exit(1);
    }

    uint32_t pc0 = *(const uint32_t *)(buf + 0x10);
    uint32_t t_addr = *(const uint32_t *)(buf + 0x18);
    uint32_t t_size = *(const uint32_t *)(buf + 0x1C);

    /* copy the program image into fake RAM at the load address.
     * KSEG0 addresses alias the 2MB RAM (mask 0x1FFFFF). */
    uint32_t dst = xenolift_phys(t_addr);
    uint32_t bytes = t_size;
    if (bytes > XENOLIFT_RAM_SIZE) {
        bytes = XENOLIFT_RAM_SIZE; /* guard against corrupt headers */
    }
    memcpy(xenolift_mem + xenolift_phys(t_addr), buf + 0x800, bytes);
    free(buf);

    printf("[xenolift] loaded %s: entry 0x%08X, text 0x%08X (0x%X bytes)\n",
           path, pc0, t_addr, t_size);
}

/* R227: CRASH CAPTURE — async-signal-safe only. The cycle-12 Mac segfault
 * produced ZERO output: the old handler used backtrace()+fprintf (not
 * signal-safe); the crash landed mid-log-write and the handler died too
 * (crash-in-crash). This one writes with raw write(2), dumps the current
 * function (tracked live at every xenolift_trace entry), key registers,
 * si_addr, and the last 64 entered functions from the trace ring = the call
 * trail at the moment of the crash. */
extern uint32_t xenolift_ring[64];
extern int xenolift_ring_n;
static void crash_putc(char c) { (void)!write(2, &c, 1); }
static uint64_t host_stack_lo, host_stack_hi; /* R247 walker bounds */
static void crash_puts(const char *s) { while (*s) crash_putc(*s++); }
static void crash_puth(uint32_t v)
{
    static const char hx[] = "0123456789ABCDEF";
    for (int i = 7; i >= 0; i--) crash_putc(hx[(v >> (i * 4)) & 0xF]);
}
/* R229: crash memory dumper — the report must be SELF-SUFFICIENT: with the
 * crashing function named (cycle-15: MoviePollSkipInput 0x800769A4, wild
 * deref of 0xB7E7EFF8, module data base r5=0x80077194), the next digest
 * needs the actual MIPS at the crash + the pointer-source cells so the
 * faulting instruction decodes offline. Async-safe: manual byte assembly,
 * bounds-guarded against the RAM window. */
extern uint8_t xenolift_mem[XENOLIFT_RAM_SIZE + XENOLIFT_IO_SIZE];
static void crash_dump_mem(const char *tag, uint32_t addr, int words)
{
    int i;
    crash_puts("[crash] "); crash_puts(tag); crash_puts(" @0x"); crash_puth(addr);
    crash_puts(":");
    if (addr < 0x80000000u || addr >= 0x80000000u + XENOLIFT_RAM_SIZE) {
        crash_puts(" OUT-OF-RAM (no dump)\n");
        return;
    }
    for (i = 0; i < words; i++) {
        uint32_t a = addr + (uint32_t)i * 4u;
        uint32_t v = 0;
        int b;
        if (a + 3u >= 0x80000000u + XENOLIFT_RAM_SIZE) { crash_puts(" CUT"); break; }
        for (b = 0; b < 4; b++)
            v |= (uint32_t)xenolift_mem[(a - 0x80000000u) + (uint32_t)b] << (8 * b);
        crash_puts(i % 4 == 0 ? "\n[crash]   " : " ");
        crash_puth(v);
    }
    crash_puts("\n");
}
static void segv_handler(int sig, siginfo_t *si, void *uc)
{
    /* R233: HOST PC capture. Cycles 15-19 show cur_fn can be STALE for the
     * fault site (crash regs r4=1/r5=0x80077194 match no state
     * MoviePollSkipInput can produce; the trail's newest entry is the VSync
     * pair, not cur_fn) — the fault is inside a function whose hook context
     * we can't trust. The HOST fault PC resolves through atos against the
     * compiled binary -> names the EXACT emitted C line = the exact
     * translated MIPS instruction. Prints host_pc (fault) + host_base
     * (runtime addr of a static symbol) so run.sh computes the ASLR slide
     * via nm and resolves statically. */
    uintptr_t host_pc = 0, host_base = 0;
#if defined(__APPLE__)
    ucontext_t *UC = (ucontext_t *)uc;
# if defined(__x86_64__)
    host_pc = (uintptr_t)UC->uc_mcontext->__ss.__rip;
# elif defined(__arm64__)
    host_pc = (uintptr_t)UC->uc_mcontext->__ss.__pc;
# endif
    host_base = (uintptr_t)&xenolift_ring;
#else
    /* Linux sandbox builds: REG_RIP lives in sys/ucontext.h with glibc-
     * specific layout; the crash class we need is Mac-host-only, so the
     * non-Apple path reports 0 (the resolver in run.sh no-ops on 0). */
    host_pc = 0; host_base = 0;
#endif
    crash_puts("[crash] host_pc=0x"); crash_puth((uint32_t)((uint64_t)host_pc >> 32)); crash_puth((uint32_t)host_pc);
    crash_puts(" host_base=0x"); crash_puth((uint32_t)((uint64_t)host_base >> 32)); crash_puth((uint32_t)host_base);
    crash_puts(" ring_n="); crash_puth((uint32_t)xenolift_ring_n);
    crash_puts("\n");
    /* R245: HOST BACKTRACE = the translated-C call chain that faulted —
     * cycle-30's fault addr lands in libc territory (wild pointer passed to
     * a copy routine), so the faulting PC alone names nothing; the frame
     * list names the exact emitted function. atos resolves offline. */
    { void *bt[16]; int n = backtrace(bt, 16);
      crash_puts("[crash] host backtrace:\n");
      if (n > 0) backtrace_symbols_fd(bt, n, 2);
      else {
        /* R246: backtrace() from the altstack handler returns 0 frames on
         * macOS (cycle-31: empty). Manual x86_64 frame-pointer chain walk
         * from the signal ucontext is async-signal-safe and DOES work. */
#if defined(__APPLE__) && defined(__x86_64__)
        uint64_t fp = (uint64_t)((const ucontext_t *)uc)->uc_mcontext->__ss.__rbp;
        int i;
        crash_puts("[crash] rbp chain (fp=0x"); crash_puth((uint32_t)(fp >> 32)); crash_puth((uint32_t)fp);
        crash_puts(")\n");
        for (i = 0; i < 12 && fp; i++) {
          uint64_t ra, nfp;
          /* R247 HARD CAP: fp must live inside the real host stack (and
           * leave room for the 8-byte ra slot) before we touch it. */
          if (fp & 7 || fp < 0x1000) break;
          if (fp < host_stack_lo || fp + 16 > host_stack_hi) {
            crash_puts("[crash] frame walk stopped: fp outside host stack\n");
            break;
          }
          memcpy(&ra, (const void *)(uintptr_t)(fp + 8), 8);
          memcpy(&nfp, (const void *)(uintptr_t)fp, 8);
          crash_puts("[crash] frame #"); crash_puth(i);
          crash_puts(" ra=0x"); crash_puth((uint32_t)(ra >> 32)); crash_puth((uint32_t)ra); crash_puts("\n");
          if (nfp <= fp) break;
          fp = nfp;
        }
#endif
      } }
    {   /* R227.1: ATOMIC critical line — one prebuilt buffer, ONE write(),
         * so the identity of the crash (sig, fault addr, current function,
         * return addr, sp, args) can never be lost to a partial fault. */
        static char cb[512];
        unsigned p = 0;
        const uint32_t crit[8] = {
            (uint32_t)sig, (uint32_t)(si ? (uintptr_t)si->si_addr : 0),
            xenolift_cur_fn, r[31], r[29], r[4], r[5], r[6]
        };
        static const char *lab[8] = {
            " sig=", " addr=", " cur_fn=", " r31=", " sp=", " r4=", " r5=", " r6="
        };
        static const char hx[] = "0123456789ABCDEF";
        const char *head = "\n[crash] CRITICAL";
        for (unsigned h = 0; head[h]; h++) cb[p++] = head[h];
        for (int k = 0; k < 8; k++) {
            for (unsigned q = 0; lab[k][q]; q++) cb[p++] = lab[k][q];
            cb[p++] = '0'; cb[p++] = 'x';
            for (int d = 0; d < 8; d++) cb[p++] = hx[(crit[k] >> (28 - 4 * d)) & 0xF];
        }
        cb[p++] = '\n';
        (void)!write(2, cb, p);
    }
    crash_dump_mem("code @cur_fn", xenolift_cur_fn, 96);
    /* R246: r4 = the caller's data struct (cycle-31: movie render struct
     * @0x80077180 whose fields feed the GPU dispatch + transfer size) —
     * the kit dumped r5 which was just a size (0x8000). r4 first, 16 words. */
    crash_dump_mem("data @r4", r[4], 16);
    crash_dump_mem("data @r5", r[5], 8);
    crash_dump_mem("stack @r31-16", r[31] >= 16u ? r[31] - 16u : r[31], 8);
    /* R484: full 32-register dump at host crash (async-safe manual write).
     * c47/c48 host segv landed in a system lib called from
     * xenolift_trace+1967 (probe dispatcher) via fn_800286CC; the kit only
     * dumped r4/r5/r6. Full register file at death -> the deref's source
     * register becomes visible next crash. */
    {
        static const char hxx[] = "0123456789ABCDEF";
        char rb[1024]; unsigned q = 0;
        const char *rh = "\n[crash] regs32:";
        for (unsigned u = 0; rh[u]; u++) rb[q++] = rh[u];
        for (int k = 0; k < 32; k++) {
            if ((k % 4) == 0) rb[q++] = '\n';
            rb[q++] = 'r';
            rb[q++] = (k < 10) ? (char)('0' + k) : (char)('A' + k - 10);
            rb[q++] = '=';
            for (int d = 0; d < 8; d++) rb[q++] = hxx[(r[k] >> (28 - 4 * d)) & 0xF];
            rb[q++] = ' ';
        }
        rb[q++] = '\n';
        (void)!write(2, rb, q);
    }
    crash_puts("\n[crash] SEGFAULT sig="); crash_puth((uint32_t)sig);
    crash_puts(" addr="); crash_puth((uint32_t)(si ? (uintptr_t)si->si_addr : 0));
    crash_puts(" cur_fn="); crash_puth(xenolift_cur_fn);
    crash_puts(" r31="); crash_puth(r[31]);
    crash_puts(" sp="); crash_puth(r[29]);
    crash_puts(" r4="); crash_puth(r[4]);
    crash_puts(" r5="); crash_puth(r[5]);
    crash_puts(" r6="); crash_puth(r[6]);
    crash_puts("\n[crash] trail (newest last, 8/line):\n");
    {   /* snapshot the ring safely; ring may be mid-write. R233: compact —
         * the 32 one-per-line form exceeded the =CRASH= digest budget and
         * the NEWEST entries (the crash context!) got truncated away. */
        uint32_t n = (uint32_t)xenolift_ring_n;
        for (int i = 31; i >= 0; i--) {
            uint32_t idx = (n - 1u - (uint32_t)i) & 63u;
            crash_puts("[crash] trail "); crash_puth(xenolift_ring[idx]);
            if ((i & 7) == 0) crash_puts("\n");
        }
    }
    crash_puts("[crash] END OF REPORT\n");
    _exit(99);
}

static int xenolift_real_main(int argc, char **argv);
#define XENOLIFT_GUEST_STACK (2048ull << 20) /* R261: 2GB guest thread stack */
struct xl_main_args { int argc; char **argv; int rc; };
static void *xl_main_thread(void *p)
{
    struct xl_main_args *a = (struct xl_main_args *)p;
    a->rc = xenolift_real_main(a->argc, a->argv);
    return NULL;
}
/* R649 [exitdiag]: c219 — the run DIED at t=15s mid-file-15-install with no
 * crash-kit output ("host_pc/host_base missing"). Any early death must now
 * self-report the mount/install posture so the next digest names the state
 * at exit. Handlers are diag-only: fprintf + _exit, no guest dispatch. */
static void xenolift_exitdiag(const char *why)
{
    long age = (long)(time(NULL) - g_boot_wall_t0);
    fprintf(stderr, "[exitdiag] exit path: %s\n", g_exit_why);
    fprintf(stderr, "[exitdiag] R649 %s @t=%lds: 92C0=%08X idx(FAEC)=%08X req=%08X F0C(59F0C)=%08X F10(59F10)=%08X FE04=%08X FDF8=%08X FE1C=%08X FE20=%08X seek=%u loop28088=%08X\n",
            why, age,
            xenolift_mem_read32(0x800592C0u), xenolift_mem_read32(0x8005FAECu),
            xenolift_mem_read32(0x80018088u), xenolift_mem_read32(0x80059F0Cu),
            xenolift_mem_read32(0x80059F10u), xenolift_mem_read32(0x8004FE04u),
            xenolift_mem_read32(0x8004FDF8u), xenolift_mem_read32(0x8004FE1Cu),
            xenolift_mem_read32(0x8004FE20u), cd_seek_lba, xenolift_mem_read32(0x80028088u));
}
static void xenolift_exitdiag_clean(void) { xenolift_exitdiag("atexit-clean-return"); }
static void xenolift_exitdiag_sig(int sig)
{
    xenolift_exitdiag(sig == 11 ? "SIGSEGV" : sig == 10 ? "SIGBUS" : sig == 6 ? "SIGABRT" : "signal");
    _exit(99);
}
int main(int argc, char **argv)
{
    g_boot_wall_t0 = time(NULL); /* R315: budget clock from PROCESS START —
     * cycle-63 verdict: run_t0 started at FIRST ALARM (t=30s) so the
     * over-budget check quantized to wall 240s = dead heat with the
     * bridge's 240s SIGKILL, bridge won 3 cycles straight. From process
     * start + 195s budget we halt at ~195s with 45s margin. */
    signal(SIGSEGV, xenolift_exitdiag_sig); /* R649 */
    signal(SIGBUS, xenolift_exitdiag_sig);  /* R649 */
    signal(SIGABRT, xenolift_exitdiag_sig); /* R649 */
    atexit(xenolift_exitdiag_clean);        /* R649: clean main-return also reports */
    /* R261 BIG STACK: cycle-9 crash = SIGSEGV inside vfprintf with the fault
     * address 0x398 below the frame pointer = the 8MB main-thread stack
     * exhausted (R228 predicted this class). The movie slice pair
     * fn_8007670C<->fn_800767DC alternates at IDENTICAL call offsets
     * (+1402/+582) = a tail-jump loop emitted as calls = unbounded host
     * recursion once the loop runs unblocked. Run the guest on a 2GB
     * pthread stack; sigaltstack is per-thread so the crash kit installs
     * inside the thread (unchanged code path). */
    pthread_attr_t at; pthread_t th; struct xl_main_args a = { argc, argv, 1 };
    pthread_attr_init(&at);
    if (pthread_attr_setstacksize(&at, (size_t)XENOLIFT_GUEST_STACK) != 0
        || pthread_create(&th, &at, xl_main_thread, &a) != 0) {
        fprintf(stderr, "[xenolift] big-stack thread unavailable — running on the main stack\n");
        return xenolift_real_main(argc, argv);
    }
    fprintf(stderr, "[xenolift] guest running on a %lluMB thread stack (R261)\n", (unsigned long long)(XENOLIFT_GUEST_STACK >> 20));
    pthread_join(th, NULL);
    return a.rc;
}
static int xenolift_real_main(int argc, char **argv)
{
    { /* R323 CHURN ANCHOR: this frame lives for the whole guest run. Family-fn
         entries deeper than 8MB bounce here via longjmp and re-dispatch at a
         *fresh* stack — the eternal state-machine churn can no longer exhaust
         * the 2048MB thread stack (cycles 69-71: guard park / OOM kill). */
        volatile int cb_ = 0;
        xenolift_churn_base = (uintptr_t)&cb_;
        xenolift_churn_armed = 1;
        xenolift_churn_bounces = 0;
        if (setjmp(xenolift_churn_jmp) != 0) {
            uint32_t pend = xenolift_churn_pend;
            xenolift_dispatch(pend);
            /* machine chain returned: keep the anchor live for future churn */
        }
    }
    fprintf(stderr, "[xenolift] runtime build R689 — STREAM MODE PLAYTEST ERA (R598/R599 lineage: ReadS auto-advance; history: WALKER HARD CAP (cycle-1 hang: nested fault inside the crash handler — fp not bounds-checked before memcpy; R247 = host-stack-range gate on every frame hop, 12-frame cap kept; all R246 capture ships unchanged (cycle-31 = THE CRASH IS DECODED AND CORNERED: fault moved to fn_80044EA4 = THE GPU DISPATCH HELPER, entered from the movie render path r31=0x800767F8 with the movie render struct r4=0x80077180 and transfer size r5=0x8000 (32KB = frame material); full disasm in hand — the fn reads drv triple 0x800568C8/C8+0x10 (driver METHOD POINTER) and 0x800568CC (direct GPU fn, worked all run), builds a VRAM coord token 0x05000000+XY from the struct halfword fields, calls driver methods; the wild pointer comes from THIS chain, data-dependent. Backtrace() returned 0 frames (macOS altstack quirk) and the kit dumped the WRONG reg (r5=size). R246: (1) kit dumps r4 struct 16 words FIRST; (2) rbp-chain walk replaces backtrace (12 frames, async-signal-safe, works on altstack); (3) render-struct head cells 0x80077180/88/90/98 join the on-change watchers (40->44). Next cycle: the struct contents + the named frame chain = the wild pointer SOURCE gets named and healed)");
    { /* R228: SIGALTSTACK. Cycle-14 verdict: the R227 handler was correctly
         * installed (clean compile, banner R227) and STILL printed nothing —
         * the remaining failure mode is STACK EXHAUSTION: the movie-player
         * chain appears stuck in a call loop, the native stack blows in ~2s,
         * and a dead stack cannot deliver the signal frame to any handler
         * running on that stack. SA_ONSTACK + a dedicated alternate stack lets
         * the report run anyway — and the 32-fn call trail will show the
         * repeating function = the loop's name. */
        static char crash_stack[64 * 1024];
        stack_t ss;
        /* R247: host stack bounds for the crash walker — fp chain copies
         * are only safe INSIDE the real thread stack. A garbage-but-aligned
         * rbp previously faulted INSIDE the SIGSEGV handler -> nested fault
         * on the altstack -> hang (cycle-1 of the 500 marathon). */
        {
            volatile char probe;
            host_stack_hi = (uint64_t)(uintptr_t)&probe;
            host_stack_lo = host_stack_hi - XENOLIFT_GUEST_STACK; /* R261: matches the guest thread stack */
        }
        struct sigaction sa;
        memset(crash_stack, 0, sizeof crash_stack);
        ss.ss_sp = crash_stack;
        ss.ss_size = sizeof crash_stack;
        ss.ss_flags = 0;
        sigaltstack(&ss, NULL);
        memset(&sa, 0, sizeof(sa));
        sa.sa_sigaction = segv_handler;
        sa.sa_flags = SA_SIGINFO | SA_ONSTACK;
        sigemptyset(&sa.sa_mask);
        sigaction(SIGSEGV, &sa, NULL);
        sigaction(SIGBUS, &sa, NULL);
    }
    if (argc < 2) {
        fprintf(stderr, "usage: ./xenogears_boot <psx-exe> [disc-image]\n");
        return 1;
    }
    load_exe(argv[1]);
    bios_module_setup();
    hle_gte_reset();    /* R136: GTE owns COP2 state */
    gpu_init();         /* R135: GPU HLE interpreter */
    hle_spu_reset();    /* R134: SPU HLE module */
    hle_mdec_reset();   /* R134: MDEC HLE module */
    hle_memcard_reset();/* R134: memcard HLE (SIO routing deferred) */
    pad_fill(); /* R85: connected digital pad before boot */
    /* R87: state-machine latch (gp+448 = 0x80059330). The walker
     * fn_800320F8 (called from the display step's report at
     * 0x80019ED4) traps 0x83 when latch==0; the alloc gatekeeper
     * fn_80031DB0 also NULLs decompression-class allocs when it is 0.
     * On real HW the state-machine install (set_latch at 0x80031BB8)
     * runs BEFORE the display step, so arming at init matches the real
     * ordering. Both readers only test != 0 — a flag value is safe. */
    { uint32_t latch = 1; memcpy(xenolift_mem + 0x59330u, &latch, 4);
      fprintf(stderr, "[latch] state-machine latch armed (0x80059330 = 1)\n"); }
    {
        static int once; if (!once) { once = 1;
            fprintf(stderr, "[pad] connected digital pad armed (0x800625FC pair)\n"); }
    }
    /* kernel DMA cell pointers -> register addresses. The kernel arms
     * ch3 (CDROM) through cells: MADR/BCR/CHCR at 0x800567AC/B0/B4, DPCR/
     * DICR at 0x800567A4/A8, RAM_SIZE cell at 0x80056780. */
    {
        static const struct { uint32_t cell, val; } cd_cells[] = {
            { 0x80056780u, 0x1F801020u },
            { 0x800567A4u, 0x1F8010F0u },
            { 0x800567A8u, 0x1F8010F4u },
            { 0x800567ACu, 0x1F8010B0u },
            { 0x800567B0u, 0x1F8010B4u },
            { 0x800567B4u, 0x1F8010B8u },
        };
        for (unsigned i = 0; i < sizeof(cd_cells) / sizeof(cd_cells[0]); i++)
            *(uint32_t *)(xenolift_mem + (cd_cells[i].cell & 0x1FFFFFFFu)) = cd_cells[i].val;
        fprintf(stderr, "[cells] CD/DMA register cells initialized\n");
        /* R154: THE WORKING GAME TABLE. Live proof (cycle 5): the kernel
         * commits the requested state to the ROM/idx cell 0x80018088, but
         * the resident-loop dispatcher reads state from 0x80018088 and
         * descriptors from 0x8001808C - a working copy that NOTHING ever
         * initializes (raw disc code sits there). Every cycle it computed a
         * wild descriptor pointer and aborted to the restart step before
         * the entry dispatch. Retail hardware must build this copy before
         * boot; our runtime performs the same install here: 7 entries
         * copied from the verified ROM table 0x8001808C, working idx
         * mirrored from 0x80018088. */
        memcpy(xenolift_mem + 0x2808Cu, xenolift_mem + 0x1808Cu, 7u * 16u);
        {
            uint32_t rom_idx = 0;
            memcpy(&rom_idx, xenolift_mem + 0x18088u, 4);
            memcpy(xenolift_mem + 0x18088u, &rom_idx, 4);
            fprintf(stderr, "[gtab-init] working game table installed: 7 descriptors, idx=0x%08X\n", rom_idx);
        }
    }
    if (argc > 2 && xenolift_disc_mount(argv[2]) != 0) {
        fprintf(stderr, "[disc] continuing without a disc (file functions fail)\n");
    }

    /* watchdog: 15 seconds of emulated execution is plenty for a smoke test */
    signal(SIGALRM, on_alarm);
    alarm(30); /* R305: 30s initial window — state-1 mount era */

    /* mirror the console's initial CPU state */
    r[0] = 0; /* hardwired zero (and never written by our generated code) */
    r[31] = 0;
    hi = lo = 0;

    xenolift_region(); /* run the recompiled boot code */

    /* R678: SHELL RESTART — c246-c249 converged structural read: the kernel
     * menu's design is pick-state -> main RETURNS -> the shell re-enters the
     * exe with that state. Our shell just exits, so the field era dies at
     * the first clean return (@10-11s, cur=1 committed, state-1 cb entered).
     * Restart the boot chain like the console shell would. The boot's own
     * BSS clear (fn_80019524) resets the kernel cells natively; receipts from
     * the second boot tell us what the restart needs next. Cap 2. */
    {
        static uint32_t r678_n;
        while (r678_n < 2u &&
               (xenolift_mem_read32(0x800592C0u) == 1u ||
                xenolift_mem_read32(0x8005FAECu) >= 1u)) {
            r678_n++;
            fprintf(stderr, "[mtrans] R678 shell RESTART #%u @t=%lds: main returned with field committed (92C0=%08X FAEC=%08X) - re-entering boot like the console shell would\n",
                    r678_n, (long)(time(NULL) - g_boot_wall_t0),
                    xenolift_mem_read32(0x800592C0u), xenolift_mem_read32(0x8005FAECu));
            r[31] = 0; hi = lo = 0;
            xenolift_region();
        }
    }
    printf("[xenolift] region returned (the boot chain unwound).\n");
    return 0;
}

/* R258: deliver a stuck CD INT1 from ANY execution context. Mirrors the
 * proven R159/R160 spin-conv sequence (handler pair + collector) with full
 * register-file + hi/lo save/restore and a reentrancy guard. */
static void cd_force_deliver_int1(const char *why)
{
    static int busy; static uint32_t n;
    if (busy) return;
    busy = 1;
    {
        uint32_t sr[32]; uint32_t shi = hi, slo = lo;
        memcpy(sr, r, sizeof r);
        n++;
        if (n <= 16u || (n % 64u) == 0u)
            fprintf(stderr, "[cdf] force-deliver #%u (%s): INT1 pending=%u seek=%u FDF8=%u — handler pair + collector\n",
                    n, why, cd_pending, cd_seek_lba, xenolift_mem_read32(0x8004FDF8u));
        r[4] = 0; r[5] = 0;
        xenolift_dispatch(0x800409E4u);
        xenolift_dispatch(0x80040A4Cu);
        xenolift_dispatch(0x800415B4u);
        {
            /* R259: the collector RETURNS the slot bitmask in v0 — the kernel
             * wait-loop then dispatches h4 (data reader) / h2 (starter). R258
             * dropped it: cycle-7 = 8 sectors got through via stray kernel
             * contexts, then the read parked with the sector LOADED, INT
             * consumed, data_pos=0 (nobody read it), FDF8=6684. Mirror the
             * wait-loop's dispatch exactly (same cells, fallbacks, args). */
            uint32_t slots = r[2];
            if (slots & 4u) {
                uint32_t h4 = *(uint32_t *)(xenolift_mem + 0x564AC);
                if (!(h4 >= 0x80010000u && h4 < 0x80060000u)) {
                    uint32_t rs_h4 = xenolift_mem_read32(0x80059EF8u + 0x10u);
                    h4 = (rs_h4 >= 0x80010000u && rs_h4 < 0x80060000u) ? rs_h4 : 0x8002B084u;
                }
                r[4] = xenolift_mem[0x56789]; r[5] = 0x8005A218u;
                xenolift_dispatch(h4);
            }
            if (slots & 2u) {
                uint32_t h2 = *(uint32_t *)(xenolift_mem + 0x564A8);
                if (h2 >= 0x80010000u && h2 < 0x80060000u) {
                    r[4] = xenolift_mem[0x56788]; r[5] = 0x8005A210u;
                    xenolift_dispatch(h2);
                }
            }
            if (n <= 16u || (n % 64u) == 0u)
                fprintf(stderr, "[cdf] #%u post: slots=%u pending=%u seek=%u FDF8=%u fifo=%u/%u loaded=%u\n",
                        n, slots, cd_pending, cd_seek_lba, xenolift_mem_read32(0x8004FDF8u),
                        cd_data_pos, cd_data_n, cd_data_loaded);
        }
        memcpy(r, sr, sizeof r); hi = shi; lo = slo;
    }
    busy = 0;
}

/* R308: central restore — the pending multi-byte answer must reach the handler
 * intact no matter WHICH delivery door the kernel collects it at. Hardware
 * delivers the INT within interrupt latency; our lazy INT lets GetStat polls
 * stomp the FIFO between build and delivery. Restore at every door. */
static void cd_restore_pend(void)
{
    if (cd_pend_ans_n > 0u) {
        memcpy(cd_resp, cd_pend_ans, sizeof cd_resp);
        cd_resp_n = cd_pend_ans_n; cd_resp_pos = 0;
        memcpy(cd_last_full, cd_pend_ans, sizeof cd_resp);
        cd_last_full_n = cd_pend_ans_n;
        fprintf(stderr, "[cd] TOC-RESTORE(conv): full %u-byte answer restored (cmd 0x%02X)\n", cd_pend_ans_n, cd_pend_ans_cmd);
        { extern int g_rspop_win; g_rspop_win = 24; } /* R317 */
    }
}
