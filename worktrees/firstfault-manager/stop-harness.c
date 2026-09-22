#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <pthread.h>
#include <execinfo.h>
#define XENOLIFT_RAM_SIZE 0x200000u
uint8_t xenolift_mem[XENOLIFT_RAM_SIZE];
uint32_t r[32], xenolift_cur_fn=0x80010000u;
int g_firstfault_stop;
void xenolift_receipt(const char *fmt, ...) { va_list ap; va_start(ap,fmt); vfprintf(stderr,fmt,ap); va_end(ap); }
/* R1172: stop-only path. No guest helper, dispatch, recovery or RAM store.
 * Raw bounded RAM reads avoid recursively invoking diagnostic memory hooks.
 * Flags off: this path is never entered. */
static void r1172_raw_window(const char *label, uint32_t a, unsigned words)
{
    if (a < 0x80000000u || a > 0x80200000u - 4u) {
        xenolift_receipt("[firstfault-raw] %s @%08X unavailable\n", label, a);
        return;
    }
    uint32_t off = a - 0x80000000u;
    for (unsigned i = 0; i < words && off <= XENOLIFT_RAM_SIZE - 4u; ++i, off += 4u) {
        uint32_t v = (uint32_t)xenolift_mem[off] | ((uint32_t)xenolift_mem[off+1] << 8)
                   | ((uint32_t)xenolift_mem[off+2] << 16) | ((uint32_t)xenolift_mem[off+3] << 24);
        xenolift_receipt("[firstfault-raw] %s %08X=%08X\n", label, 0x80000000u + off, v);
    }
}
static void r1172_guest_stop(uint32_t a)
{
    /* Suppress asynchronous timer callbacks on this thread during capture.
     * Synchronous host faults remain visible to the existing host handler. */
    sigset_t blocked;
    sigemptyset(&blocked); sigaddset(&blocked, SIGALRM);
    sigaddset(&blocked, SIGVTALRM); sigaddset(&blocked, SIGPROF);
    pthread_sigmask(SIG_BLOCK, &blocked, NULL);
    xenolift_receipt("[firstfault] R1172 BEGIN guest-fault target=%08X cur_fn=%08X; before legacy fault handling\n", a, (unsigned)xenolift_cur_fn);
    for (unsigned i = 0; i < 32; ++i)
        xenolift_receipt("[firstfault-reg] r%u=%08X\n", i, r[i]);
    /* Preserve full raw RAM before any potentially allocating symbolication. */
    const char *path = getenv("XENOLIFT_FIRSTFAULT_RAM");
    if (path && *path) {
        int fd = open(path, O_WRONLY | O_CREAT | O_EXCL, 0600);
        size_t done = 0;
        if (fd >= 0) {
            while (done < XENOLIFT_RAM_SIZE) {
                ssize_t n = write(fd, xenolift_mem + done, XENOLIFT_RAM_SIZE - done);
                if (n <= 0) break;
                done += (size_t)n;
            }
            close(fd);
        }
        xenolift_receipt("[firstfault-ram] bytes=%u expected=%u complete=%u\n", (unsigned)done, (unsigned)XENOLIFT_RAM_SIZE, done == XENOLIFT_RAM_SIZE);
    }
    r1172_raw_window("stack", r[29], 64);
    r1172_raw_window("code-curfn", xenolift_cur_fn, 32);
    r1172_raw_window("code-ra", r[31], 32);
    r1172_raw_window("data-a0", r[4], 32);
    r1172_raw_window("request-4F", 0x8004FDF8u, 20);
    r1172_raw_window("request-5F", 0x8005FDF8u, 20);
    r1172_raw_window("walk-5F", 0x8005FAECu, 2);
    r1172_raw_window("file", 0x80059F0Cu, 2);
    void *frames[32]; int count = backtrace(frames, 32);
    xenolift_receipt("[firstfault-backtrace] frames=%d; return PCs may follow the offending call\n", count);
    backtrace_symbols_fd(frames, count, 2);
    xenolift_receipt("[firstfault] R1172 GUEST-FAULT STOP complete; exit=99; no legacy recovery entered\n");
    _exit(99);
}


void xenolift_io_fault(uint32_t a) {
    if (g_firstfault_stop) r1172_guest_stop(a);
    xenolift_mem[0] = 99; /* sentinel for legacy execution */
}
int main(int argc, char **argv) {
 for(unsigned i=0;i<XENOLIFT_RAM_SIZE;++i) xenolift_mem[i]=(uint8_t)i;
 for(unsigned i=0;i<32;++i) r[i]=i;
 r[29]=0x801FFFF0u; r[31]=0x80010000u;
 g_firstfault_stop=argc>1;
 xenolift_io_fault(0x0059FAECu);
 return xenolift_mem[0]==99 ? 0 : 2;
}
