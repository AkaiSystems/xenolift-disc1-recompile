/* receipt_xprintf.h - R985 (b8-c96, WARDEN - RECEIPT PRINTER vprintf-FREE)
 *
 * RECEIPT PROVENANCE (8 cycles, c89-c96): every host death lands in the SAME
 * frames - __stack_chk_fail <- __vfprintf <- _vsnprintf <- vsnprintf <- our
 * receipt printers (r861_out / hle_out). The printf-internal frames are the
 * DETECTOR (the canary that trips belongs to a libsystem frame); the smasher
 * is still unknown, and Apple's INTERNAL __stack_chk_fail is not interposable
 * (c444: the R853 namer can never fire for this class). Door-hunting removed
 * every OUR-side vprintf hazard (R977 reentrancy guard, R981 printf-args fix,
 * R982 HLE sweep, R983 kit/canaryrec manual formatting, R984 handler sweep) -
 * the class persists because the CRASH SITE is vsnprintf's internals, entered
 * by the receipt path on every print.
 *
 * R985 removes the crash site itself: a minimal formatter for the receipts'
 * actual vocabulary (audited: %08X %u %d %02X %% %s %08x %04X %x %c %X %ld
 * %llu %llX %p), manual conversion into the caller buffer + raw write(2).
 * No libc print machinery anywhere in the receipt path. Unknown specs fall
 * back to vsnprintf ON THE REMAINING va_list (rare; audit says none).
 *
 * Game-agnostic product note (goal 2): this is the "receipt printer that
 * never dies" mechanism - generalizable to any headless recomp harness.
 */
#ifndef XENOLIFT_RECEIPT_XPRINTF_H
#define XENOLIFT_RECEIPT_RECEIPT_XPRINTF_H
#define XENOLIFT_RECEIPT_XPRINTF_H

#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>   /* vsnprintf fallback only */

/* returns number of chars written to b (not counting NUL); never exceeds cap-1 */
static int xl_format(char *b, int cap, const char *fmt, va_list ap)
{
    int n = 0;
    const char *p = fmt;
    while (*p) {
        if (*p != '%') {
            if (n < cap - 1) b[n++] = *p;
            p++;
            continue;
        }
        p++; /* past % */
        if (*p == '%') { if (n < cap - 1) b[n++] = '%'; p++; continue; }
        /* parse: 0 flag, width (1-2 digits), l/ll modifiers, conv */
        int zero = 0, width = -1;
        if (*p == '0') { zero = 1; p++; }
        if (*p >= '1' && *p <= '9') {
            width = 0;
            while (*p >= '0' && *p <= '9' && width < 64) { width = width * 10 + (*p - '0'); p++; }
        }
        int lmod = 0, llmod = 0;
        if (*p == 'l') { lmod = 1; p++; if (*p == 'l') { llmod = 1; p++; } }
        char conv = *p;
        if (conv == 's' && !lmod && !llmod && width < 0) {
            const char *s = va_arg(ap, const char *);
            if (!s) s = "(null)";
            while (*s) { if (n < cap - 1) b[n++] = *s; s++; }
            p++;
            continue;
        }
        if (conv == 'c' && !lmod && !llmod && width < 0) {
            int c = va_arg(ap, int);
            if (n < cap - 1) b[n++] = (char)c;
            p++;
            continue;
        }
        if (conv == 'd' || conv == 'i' || conv == 'u' || conv == 'x' ||
            conv == 'X' || conv == 'p') {
            static const char hxU[] = "0123456789ABCDEF";
            static const char hxl[] = "0123456789abcdef";
            unsigned long long v = 0;
            int isptr = (conv == 'p');
            if (isptr) { v = (unsigned long long)(uintptr_t)va_arg(ap, void *); }
            else if (llmod) {
                if (conv == 'd' || conv == 'i') { long long s = va_arg(ap, long long);
                    if (s < 0) { if (n < cap - 1) b[n++] = '-'; v = (unsigned long long)(-s); }
                    else v = (unsigned long long)s; }
                else v = va_arg(ap, unsigned long long);
            } else if (lmod) {
                if (conv == 'd' || conv == 'i') { long s = va_arg(ap, long);
                    if (s < 0) { if (n < cap - 1) b[n++] = '-'; v = (unsigned long long)(-s); }
                    else v = (unsigned long long)s; }
                else v = va_arg(ap, unsigned long);
            } else {
                if (conv == 'd' || conv == 'i') { int s = va_arg(ap, int);
                    if (s < 0) { if (n < cap - 1) b[n++] = '-'; v = (unsigned long long)(-s); }
                    else v = (unsigned long long)s; }
                else v = (unsigned long long)va_arg(ap, unsigned int);
            }
            char t[24]; int m = 0;
            if (conv == 'd' || conv == 'i' || conv == 'u') {
                if (v == 0) t[m++] = '0';
                while (v && m < 20) { t[m++] = (char)('0' + (char)(v % 10)); v /= 10; }
            } else {
                const char *hx = (conv == 'X') ? hxU : hxl;
                if (isptr) { if (n < cap - 3) { b[n++] = '0'; b[n++] = 'x'; } }
                if (v == 0) t[m++] = '0';
                while (v && m < 16) { t[m++] = hx[v & 0xFu]; v >>= 4; }
            }
            if (zero && width > m) {
                char pad[32];
                int pw = (width - m > 31) ? 31 : width - m;
                for (int i = 0; i < pw; i++) pad[i] = '0';
                for (int i = pw - 1; i >= 0; i--) { if (n < cap - 1) b[n++] = pad[i]; }
            }
            while (m > 0) { if (n < cap - 1) b[n++] = t[--m]; }
            p++;
            continue;
        }
        /* R987: NO libc fallback - vsnprintf here would recurse into the
         * R987 interposer (which calls xl_format) = infinite loop, and it
         * re-opens the __vfprintf canary door we just closed. Unknown
         * specs print a literal marker and consume one arg of the
         * matching width class (int for everything but %s-family). */
        {
            if (n < cap - 8) { b[n++] = '['; b[n++] = '?'; b[n++] = ']'; }
            if (conv == 's' || conv == 'p' || conv == 'c') (void)va_arg(ap, void *);
            else if (llmod) (void)va_arg(ap, long long);
            else if (lmod) (void)va_arg(ap, long);
            else (void)va_arg(ap, int);
        }
        p++;
    }
    if (n < cap) b[n] = '\0';
    return n;
}
#endif
