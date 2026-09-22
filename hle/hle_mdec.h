/* xenolift HLE MDEC module — Motion Decoder (0x1F801820 - 0x1F801828)
 *
 * Spec reference: psx-spx "Macroblock Decoder (MDEC)"
 * http://problemkaputt.de/psxspx-mdec-i-o-ports.htm
 * http://problemkaputt.de/psxspx-mdec-commands.htm
 * http://problemkaputt.de/psxspx-mdec-data-format.htm
 * http://problemkaputt.de/psxspx-mdec-decompression.htm
 *
 * PS1 MDEC features implemented:
 * - Registers 0x1F801820 (MDEC0 Cmd/Param write, Data read),
 *   0x1F801824 (MDEC1 Status read, Reset/Control write)
 * - Commands 0 (Reset/NOP), 1 (Decode Macroblocks 15bpp/24bpp),
 *   2 (Set Quant Tables), 3 (Set Scale Table)
 * - Decompression pipeline: RLE bitstream decoding, inverse quantization,
 *   zigzag reordering, 8x8 integer IDCT, YCbCr -> RGB color conversion matrix
 * - Output depth modes: 15bpp (depth 3) and 24bpp (depth 2)
 * - DMA Ch0 (MDEC In: RAM -> MDEC) and Ch1 (MDEC Out: MDEC -> RAM)
 */

#ifndef HLE_MDEC_H
#define HLE_MDEC_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Standard API required by xenolift briefing */
void hle_mdec_reset(void);
void hle_mdec_port_write(uint32_t addr, uint32_t v);
uint32_t hle_mdec_port_read(uint32_t addr);
void hle_mdec_set_ram(uint8_t *shared_ram);

/* DMA handoff API */
void hle_mdec_dma0_in(uint32_t madr, uint32_t bcr);
void hle_mdec_dma1_out(uint32_t madr, uint32_t bcr);

/* Extended status & debug helpers */
uint32_t hle_mdec_get_status(void);
bool hle_mdec_is_busy(void);

#ifdef __cplusplus
}
#endif

#endif /* HLE_MDEC_H */
