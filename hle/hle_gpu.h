/*
 * hle_gpu.h - High-Level Emulation (HLE) module for PSX GPU
 * xenolift project - pure C17, cleanly separable GP0/GP1 interpreter
 *
 * References:
 * - psx-spx (Martin Korth): GPU command table, texture pages, blending
 * - Nocash PSX Hardware Specification (GPU section)
 */

#ifndef HLE_GPU_H
#define HLE_GPU_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* VRAM dimensions: 1024x512, 15bpp BGR555 + mask bit */
#define GPU_VRAM_WIDTH  1024
#define GPU_VRAM_HEIGHT 512
#define GPU_VRAM_SIZE   (GPU_VRAM_WIDTH * GPU_VRAM_HEIGHT)

/* Debug log macro hook: override before including if custom logging is needed */
#ifndef GPU_LOG
#define GPU_LOG(...) ((void)0)
#endif

/* Core API */
void gpu_init(void);
void gpu_gp0_write(uint32_t word);
void gpu_cls_report(void); /* R939: executed/dropped GP0 command-class census (pixels-door camera) */
extern uint16_t g_vram[GPU_VRAM_HEIGHT][GPU_VRAM_WIDTH]; /* R694: single-canvas alias */
void gpu_gp1_write(uint32_t word);
void gpu_vram_snapshot(uint16_t *out_vram, size_t max_halfwords);
void gpu_display_area(uint16_t *x, uint16_t *y, uint16_t *w, uint16_t *h);

/* Status & Inspection API */
uint32_t gpu_get_status(void);
uint32_t gpu_get_read_latch(void);
uint16_t gpu_vram_peek(uint32_t x, uint32_t y);
void gpu_vram_poke(uint32_t x, uint32_t y, uint16_t val);

#ifdef __cplusplus
}
#endif

#endif /* HLE_GPU_H */
