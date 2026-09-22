/*
 * xenolift HLE - PS1 Geometry Transformation Engine (GTE) Coprocessor 2
 *
 * Spec reference: psx-spx "COP2 Geometry Transformation Engine (GTE)"
 */

#ifndef HLE_GTE_H
#define HLE_GTE_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Reset GTE state and zero registers */
void hle_gte_reset(void);

/* Register access: Data registers 0..31 (cop2r0..31) */
uint32_t hle_gte_read_data(int reg);
void hle_gte_write_data(int reg, uint32_t v);

/* Register access: Control registers 0..31 (cop2r32..63 / cnt0..31) */
uint32_t hle_gte_read_ctrl(int reg);
void hle_gte_write_ctrl(int reg, uint32_t v);

/* Execute COP2 command (opcode = full 25-bit imm25 command word or CO-function 0..0x3F) */
void hle_gte_execute(uint32_t opcode);

/* Disassemble command opcode name for logging */
const char *hle_gte_disasm(uint32_t opcode);

#ifdef __cplusplus
}
#endif

#endif /* HLE_GTE_H */
