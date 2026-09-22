/* xenolift HLE Memory Card & SIO module — SIO / Joypad / Memcard (0x1F801080 / 0x1F801040)
 *
 * Spec references & Citations:
 * - psx-spx "Controller and Memory Card I/O Ports": http://problemkaputt.de/psxspx-controller-and-memory-card-i-o-ports.htm
 * - psx-spx "Memory Card Read/Write Commands": http://problemkaputt.de/psxspx-memory-card-read-write-commands.htm
 * - psx-spx "Memory Card Data Format": http://problemkaputt.de/psxspx-memory-card-data-format.htm
 */

#ifndef HLE_MEMCARD_H
#define HLE_MEMCARD_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Standard API required by xenolift briefing */
void hle_memcard_reset(void);
void hle_sio_port_write(uint32_t addr, uint8_t v);
uint8_t hle_sio_port_read(uint32_t addr);

/* Standard 16-bit and 32-bit register accessor wrappers */
uint32_t hle_sio_reg_read32(uint32_t addr);
void hle_sio_reg_write32(uint32_t addr, uint32_t v);

/* Memory Card image management */
void hle_memcard_format(void);
int hle_memcard_load(const char *filepath);
int hle_memcard_save(const char *filepath);
int hle_memcard_write_file(const char *filename, const uint8_t *data, size_t size);

/* Direct Sector Access (for unit testing) */
uint8_t *hle_memcard_get_sector(uint32_t sector_num);
uint8_t hle_memcard_calc_sector_checksum(uint16_t sector_num, const uint8_t *data);

/* Joypad button setter (for controller simulation) */
void hle_pad_set_buttons(uint16_t buttons_active_low);

#ifdef __cplusplus
}
#endif

#endif /* HLE_MEMCARD_H */
