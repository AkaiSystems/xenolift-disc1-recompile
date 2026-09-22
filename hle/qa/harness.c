/* xenolift HLE Conformance Skeleton (hle/qa/harness.c)
 *
 * This conformance harness links every hle_*.c module that exists at build time
 * using weak symbol attributes. Missing modules will not break the build.
 *
 * Compilation & Execution Instructions:
 *   From workspace root:
 *     cc -std=c17 -w -I. -Ihle hle/qa/harness.c $(ls hle/hle_*.c 2>/dev/null) -o hle/qa/harness && ./hle/qa/harness
 *   Or from hle/ directory:
 *     cc -std=c17 -w -I. -I.. qa/harness.c $(ls hle_*.c 2>/dev/null) -o qa/harness && ./qa/harness
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>

#if defined(__has_include)
  #if __has_include("../hle_gte.h")
    #include "../hle_gte.h"
  #endif
  #if __has_include("../hle_gpu.h")
    #include "../hle_gpu.h"
  #endif
  #if __has_include("../hle_spu.h")
    #include "../hle_spu.h"
  #endif
  #if __has_include("../hle_mdec.h")
    #include "../hle_mdec.h"
  #endif
  #if __has_include("../hle_memcard.h")
    #include "../hle_memcard.h"
  #endif
#endif

/* Weak declarations for module reset and test entry points.
 * If a module .c file is compiled and linked, its non-weak definitions override
 * these weak declarations. If absent, the function pointers evaluate to NULL. */

__attribute__((weak)) void hle_gte_reset(void);
__attribute__((weak)) int  hle_gte_test(void);

__attribute__((weak)) void hle_gpu_reset(void);
__attribute__((weak)) int  hle_gpu_test(void);

__attribute__((weak)) void hle_spu_reset(void);
__attribute__((weak)) int  hle_spu_test(void);

__attribute__((weak)) void hle_mdec_reset(void);
__attribute__((weak)) int  hle_mdec_test(void);

__attribute__((weak)) void hle_memcard_reset(void);
__attribute__((weak)) int  hle_memcard_test(void);

typedef struct {
    const char *name;
    void (*reset)(void);
    int (*test)(void);
} ModuleHook;

int main(int argc, char **argv)
{
    (void)argc; (void)argv;

    printf("====================================================================\n");
    printf("              xenolift HLE Conformance Skeleton Harness             \n");
    printf("====================================================================\n\n");

    ModuleHook modules[] = {
        { "GTE (hle_gte)",         hle_gte_reset,     hle_gte_test },
        { "GPU (hle_gpu)",         hle_gpu_reset,     hle_gpu_test },
        { "SPU (hle_spu)",         hle_spu_reset,     hle_spu_test },
        { "MDEC (hle_mdec)",       hle_mdec_reset,    hle_mdec_test },
        { "Memcard (hle_memcard)", hle_memcard_reset, hle_memcard_test },
    };

    size_t total_modules = sizeof(modules) / sizeof(modules[0]);
    size_t present_count = 0;
    size_t passed_count = 0;
    size_t failed_count = 0;

    printf("+----------------------+---------+--------------+------------------+\n");
    printf("| Module Name          | Present | Reset Status | Self-Test Status |\n");
    printf("+----------------------+---------+--------------+------------------+\n");

    for (size_t i = 0; i < total_modules; i++) {
        ModuleHook *m = &modules[i];
        bool is_present = (m->reset != NULL || m->test != NULL);
        const char *present_str = is_present ? "  YES  " : "   NO  ";
        const char *reset_str   = "   N/A  ";
        const char *test_str    = "   N/A  ";

        if (is_present) {
            present_count++;

            /* Perform Reset */
            if (m->reset != NULL) {
                m->reset();
                reset_str = "   OK   ";
            } else {
                reset_str = " NO_RST ";
            }

            /* Perform Self-Test */
            if (m->test != NULL) {
                int res = m->test();
                if (res == 0) {
                    test_str = "  PASS  ";
                    passed_count++;
                } else {
                    test_str = "  FAIL  ";
                    failed_count++;
                }
            } else {
                test_str = " NO_TST ";
            }
        }

        printf("| %-20s | %s | %-12s | %-16s |\n",
               m->name, present_str, reset_str, test_str);
    }

    printf("+----------------------+---------+--------------+------------------+\n\n");
    printf("Summary: Total=%zu, Present=%zu, Passed=%zu, Failed=%zu\n",
           total_modules, present_count, passed_count, failed_count);

    if (failed_count > 0) {
        printf("RESULT: CONFORMANCE SUITE FAILED (%zu test failures)\n", failed_count);
        return 1;
    }

    if (present_count == 0) {
        printf("RESULT: CONFORMANCE SUITE PASSED (Skeleton only — 0 modules linked)\n");
    } else {
        printf("RESULT: CONFORMANCE SUITE PASSED (%zu/%zu present modules passed tests)\n",
               passed_count, present_count);
    }

    return 0;
}
