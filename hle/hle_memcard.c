/* xenolift HLE Memory Card & SIO module — Implementation
 *
 * Spec references & Citations:
 * - psx-spx "Controller and Memory Card I/O Ports": http://problemkaputt.de/psxspx-controller-and-memory-card-i-o-ports.htm
 * - psx-spx "Memory Card Read/Write Commands": http://problemkaputt.de/psxspx-memory-card-read-write-commands.htm
 * - psx-spx "Memory Card Data Format": http://problemkaputt.de/psxspx-memory-card-data-format.htm
 */

#include "hle_memcard.h"
#include "receipt_xprintf.h" /* R985 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* R982 (b8-c92, WARDEN - HLE PRINT-DOOR SWEEP, kills the fprintf crash
 * class at its real source): c89/90/92 died identically - __stack_chk_fail
 * via __xvprintf <- vfprintf_l <- fprintf, PC attributed to real_main
 * (offset moved 2146139->2146123 as runtime.c edits shifted statics; the
 * call sites are THIS module's static fns placed after real_main with no
 * symbol - disassembly of rt.o proved runtime.c itself has ZERO fprintf/
 * printf calls). The HLE modules' raw fprintf(stderr)/hle_out() calls fire
 * on every recovery/reset (census receipts in every EXITTAIL) and a signal
 * landing mid-vfprintf smashes the canary - the class R977 killed at
 * r861_out's door, R981 killed at printf's door; these are the remaining
 * doors. Mechanical conversion: single-flight guarded printer (vsnprintf
 * into a local buffer + ONE raw write(2) - async-signal-safe, no FILE
 * machinery, nested calls drop like R977). Output moves to stderr for the
 * former hle_out() sites: cosmetic only, all receipts read stderr. */
#include <stdarg.h>
#include <unistd.h>
static void hle_out(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
static void hle_out(const char *fmt, ...)
{
    static int r982_in;
    char b[1024];
    va_list ap;
    int n;
    if (r982_in) return;
    r982_in = 1;
    va_start(ap, fmt);
    n = xl_format(b, (int)sizeof b, fmt, ap); /* R985: vprintf-free */
    va_end(ap);
    r982_in = 0;
    if (n > 0) {
        if (n > (int)sizeof b - 1) n = (int)sizeof b - 1;
        (void)!write(2, b, (size_t)n);
    }
}


#define CARD_TOTAL_SIZE (128 * 1024) /* 128 KB = 1024 sectors * 128 bytes */
#define SECTOR_SIZE 128
#define TOTAL_SECTORS 1024

/* SIO State enum */
typedef enum {
    SIO_STATE_IDLE,

    /* Memory Card Read States */
    MC_STATE_WAIT_CMD,
    MC_STATE_READ_ID1,
    MC_STATE_READ_ID2,
    MC_STATE_READ_ADDR_MSB,
    MC_STATE_READ_ADDR_LSB,
    MC_STATE_READ_ACK1,
    MC_STATE_READ_ACK2,
    MC_STATE_READ_CONFIRM_MSB,
    MC_STATE_READ_CONFIRM_LSB,
    MC_STATE_READ_DATA,
    MC_STATE_READ_CHECKSUM,
    MC_STATE_READ_END,

    /* Memory Card Write States */
    MC_STATE_WRITE_ID1,
    MC_STATE_WRITE_ID2,
    MC_STATE_WRITE_ADDR_MSB,
    MC_STATE_WRITE_ADDR_LSB,
    MC_STATE_WRITE_DATA,
    MC_STATE_WRITE_CHECKSUM,
    MC_STATE_WRITE_ACK1,
    MC_STATE_WRITE_ACK2,
    MC_STATE_WRITE_END,

    /* Memory Card Get ID States */
    MC_STATE_GETID_ID1,
    MC_STATE_GETID_ID2,
    MC_STATE_GETID_ACK1,
    MC_STATE_GETID_ACK2,
    MC_STATE_GETID_B0,
    MC_STATE_GETID_B1,
    MC_STATE_GETID_B2,
    MC_STATE_GETID_B3,

    /* Pad Poll States */
    PAD_STATE_POLL,
    PAD_STATE_BYTE1,
    PAD_STATE_SW_LO,
    PAD_STATE_SW_HI
} SioState;

/* Internal SIO / Memcard State */
typedef struct {
    uint8_t card_data[CARD_TOTAL_SIZE];
    uint8_t flag_byte;

    /* SIO hardware registers */
    uint16_t joy_stat;  /* 0x1F801044 / 0x1F801084 */
    uint16_t joy_mode;  /* 0x1F801048 / 0x1F801088 */
    uint16_t joy_ctrl;  /* 0x1F80104A / 0x1F80108A */
    uint16_t joy_baud;  /* 0x1F80104E / 0x1F80108E */

    /* RX FIFO (8 bytes max) */
    uint8_t rx_fifo[8];
    size_t rx_head;
    size_t rx_tail;
    size_t rx_count;

    /* Protocol execution state */
    SioState state;
    uint16_t cur_sector;
    uint8_t sector_msb;
    uint8_t sector_lsb;
    size_t byte_index;

    /* Write buffer */
    uint8_t tmp_write[SECTOR_SIZE];
    bool chk_match;

    /* Pad input */
    uint16_t pad_buttons; /* Active low: 0xFFFF = no buttons pressed */
} MemcardSioState;

static MemcardSioState g_sio;

static void rx_push(uint8_t b) {
    if (g_sio.rx_count < 8) {
        g_sio.rx_fifo[g_sio.rx_head] = b;
        g_sio.rx_head = (g_sio.rx_head + 1) % 8;
        g_sio.rx_count++;
        g_sio.joy_stat |= (1u << 1); /* RX FIFO Not Empty */
    }
}

static uint8_t rx_pop(void) {
    if (g_sio.rx_count > 0) {
        uint8_t b = g_sio.rx_fifo[g_sio.rx_tail];
        g_sio.rx_tail = (g_sio.rx_tail + 1) % 8;
        g_sio.rx_count--;
        if (g_sio.rx_count == 0) {
            g_sio.joy_stat &= ~(1u << 1); /* RX FIFO Empty */
        }
        return b;
    }
    return 0xFF;
}

uint8_t hle_memcard_calc_sector_checksum(uint16_t sector_num, const uint8_t *data) {
    uint8_t chk = (uint8_t)(sector_num >> 8) ^ (uint8_t)(sector_num & 0xFF);
    for (int i = 0; i < SECTOR_SIZE; i++) {
        chk ^= data[i];
    }
    return chk;
}

void hle_memcard_format(void) {
    memset(g_sio.card_data, 0, CARD_TOTAL_SIZE);

    /* Sector 0: Header Frame */
    g_sio.card_data[0] = 'M';
    g_sio.card_data[1] = 'C';
    /* bytes 2..126 are 0 */
    g_sio.card_data[127] = 'M' ^ 'C'; /* 0x0E */

    /* Sectors 1..15: Directory Frames */
    for (int i = 1; i <= 15; i++) {
        uint8_t *dir = &g_sio.card_data[i * SECTOR_SIZE];
        /* Allocation state 0x000000A0 = Free */
        dir[0] = 0xA0;
        dir[1] = 0x00;
        dir[2] = 0x00;
        dir[3] = 0x00;
        /* Size = 0, Next block = 0xFFFF */
        dir[8] = 0xFF;
        dir[9] = 0xFF;
        /* Calculate checksum */
        uint8_t chk = 0;
        for (int b = 0; b < 127; b++) chk ^= dir[b];
        dir[127] = chk;
    }

    g_sio.flag_byte = 0x08; /* Initial unread directory flag */
    hle_out("[memcard] formatted fresh 128KB image\n");
}

void hle_memcard_reset(void) {
    memset(&g_sio, 0, sizeof(g_sio));
    hle_memcard_format();

    g_sio.joy_stat = 0x0005; /* TX Ready 1, TX Ready 2 */
    g_sio.joy_mode = 0x000D; /* 8-bit, no parity */
    g_sio.joy_ctrl = 0x0000;
    g_sio.joy_baud = 0x0088;
    g_sio.state = SIO_STATE_IDLE;
    g_sio.pad_buttons = 0xFFFFu; /* active low: all unpressed */

    hle_out("[memcard] reset complete\n");
}

void hle_pad_set_buttons(uint16_t buttons_active_low) {
    g_sio.pad_buttons = buttons_active_low;
}

uint8_t *hle_memcard_get_sector(uint32_t sector_num) {
    if (sector_num >= TOTAL_SECTORS) return NULL;
    return &g_sio.card_data[sector_num * SECTOR_SIZE];
}

int hle_memcard_load(const char *filepath) {
    FILE *f = fopen(filepath, "rb");
    if (!f) return -1;
    size_t n = fread(g_sio.card_data, 1, CARD_TOTAL_SIZE, f);
    fclose(f);
    if (n < CARD_TOTAL_SIZE) {
        hle_out("[memcard] warning: short read from %s (%zu / %d bytes)\n",
                filepath, n, CARD_TOTAL_SIZE);
    } else {
        hle_out("[memcard] loaded card image from %s\n", filepath);
    }
    return 0;
}

int hle_memcard_save(const char *filepath) {
    FILE *f = fopen(filepath, "wb");
    if (!f) return -1;
    size_t n = fwrite(g_sio.card_data, 1, CARD_TOTAL_SIZE, f);
    fclose(f);
    if (n == CARD_TOTAL_SIZE) {
        hle_out("[memcard] saved card image to %s\n", filepath);
        return 0;
    }
    return -1;
}

int hle_memcard_write_file(const char *filename, const uint8_t *data, size_t size) {
    if (!filename || !data || size == 0) return -1;

    uint32_t blocks_needed = (uint32_t)((size + 8191) / 8192);
    if (blocks_needed > 15) return -1; /* Max 15 blocks */

    /* Find contiguous or free directory slots */
    int free_blocks[15];
    int free_count = 0;

    for (int b = 1; b <= 15; b++) {
        uint8_t *dir = &g_sio.card_data[b * SECTOR_SIZE];
        uint32_t state = dir[0] | (dir[1] << 8) | (dir[2] << 16) | (dir[3] << 24);
        if (state == 0xA0 || state == 0xA1 || state == 0xA2 || state == 0xA3) {
            free_blocks[free_count++] = b;
        }
    }

    if ((uint32_t)free_count < blocks_needed) {
        hle_out("[memcard] not enough free blocks (%d < %u)\n", free_count, blocks_needed);
        return -1;
    }

    /* Write directory and data blocks */
    for (uint32_t i = 0; i < blocks_needed; i++) {
        int blk = free_blocks[i];
        uint8_t *dir = &g_sio.card_data[blk * SECTOR_SIZE];
        memset(dir, 0, SECTOR_SIZE);

        if (blocks_needed == 1) {
            dir[0] = 0x51; /* First and only block */
        } else if (i == 0) {
            dir[0] = 0x51; /* First block */
        } else if (i == blocks_needed - 1) {
            dir[0] = 0x53; /* Last block */
        } else {
            dir[0] = 0x52; /* Middle block */
        }

        /* File size */
        uint32_t fsize = (uint32_t)size;
        dir[4] = (uint8_t)(fsize & 0xFF);
        dir[5] = (uint8_t)((fsize >> 8) & 0xFF);
        dir[6] = (uint8_t)((fsize >> 16) & 0xFF);
        dir[7] = (uint8_t)((fsize >> 24) & 0xFF);

        /* Next block pointer (0..14 or 0xFFFF) */
        if (i + 1 < blocks_needed) {
            uint16_t next_ptr = (uint16_t)(free_blocks[i + 1] - 1);
            dir[8] = (uint8_t)(next_ptr & 0xFF);
            dir[9] = (uint8_t)(next_ptr >> 8);
        } else {
            dir[8] = 0xFF;
            dir[9] = 0xFF;
        }

        /* Filename (only in first block) */
        if (i == 0) {
            strncpy((char *)&dir[0x0A], filename, 20);
        }

        /* Directory frame checksum */
        uint8_t chk = 0;
        for (int c = 0; c < 127; c++) chk ^= dir[c];
        dir[127] = chk;

        /* Write payload data into block */
        size_t block_offset = blk * 8192;
        size_t bytes_to_copy = (size - i * 8192) > 8192 ? 8192 : (size - i * 8192);
        memcpy(&g_sio.card_data[block_offset], data + i * 8192, bytes_to_copy);
    }

    hle_out("[memcard] wrote file '%s' (%zu bytes, %u blocks)\n",
            filename, size, blocks_needed);

    hle_memcard_save("memcard.mcd");
    return 0;
}

/* Process one byte transaction on SIO bus */
static void sio_process_byte(uint8_t tx_byte) {
    switch (g_sio.state) {
        case SIO_STATE_IDLE:
            if (tx_byte == 0x81) {
                /* Memory Card select */
                rx_push(0xFF); /* dummy response */
                g_sio.state = MC_STATE_WAIT_CMD;
                g_sio.joy_stat |= (1u << 7); /* Set ACK active */
            } else if (tx_byte == 0x01) {
                /* Controller select */
                rx_push(0xFF);
                g_sio.state = PAD_STATE_POLL;
                g_sio.joy_stat |= (1u << 7);
            } else {
                rx_push(0xFF);
            }
            break;

        case MC_STATE_WAIT_CMD:
            if (tx_byte == 0x52) {
                /* Read sector command 'R' */
                rx_push(g_sio.flag_byte);
                g_sio.state = MC_STATE_READ_ID1;
            } else if (tx_byte == 0x57) {
                /* Write sector command 'W' */
                rx_push(g_sio.flag_byte);
                g_sio.state = MC_STATE_WRITE_ID1;
            } else if (tx_byte == 0x53) {
                /* Get ID command 'S' */
                rx_push(g_sio.flag_byte);
                g_sio.state = MC_STATE_GETID_ID1;
            } else {
                rx_push(0xFF);
                g_sio.state = SIO_STATE_IDLE;
            }
            break;

        /* READ SECTOR SEQUENCE */
        case MC_STATE_READ_ID1:
            rx_push(0x5A);
            g_sio.state = MC_STATE_READ_ID2;
            break;
        case MC_STATE_READ_ID2:
            rx_push(0x5D);
            g_sio.state = MC_STATE_READ_ADDR_MSB;
            break;
        case MC_STATE_READ_ADDR_MSB:
            g_sio.sector_msb = tx_byte;
            rx_push(0x00);
            g_sio.state = MC_STATE_READ_ADDR_LSB;
            break;
        case MC_STATE_READ_ADDR_LSB:
            g_sio.sector_lsb = tx_byte;
            g_sio.cur_sector = ((uint16_t)g_sio.sector_msb << 8) | g_sio.sector_lsb;
            rx_push(0x5C); /* ACK1 */
            g_sio.state = MC_STATE_READ_ACK2;
            break;
        case MC_STATE_READ_ACK2:
            rx_push(0x5D); /* ACK2 */
            g_sio.state = MC_STATE_READ_CONFIRM_MSB;
            break;
        case MC_STATE_READ_CONFIRM_MSB:
            rx_push(g_sio.sector_msb);
            g_sio.state = MC_STATE_READ_CONFIRM_LSB;
            break;
        case MC_STATE_READ_CONFIRM_LSB:
            rx_push(g_sio.sector_lsb);
            g_sio.byte_index = 0;
            g_sio.state = MC_STATE_READ_DATA;
            break;
        case MC_STATE_READ_DATA:
            if (g_sio.cur_sector < TOTAL_SECTORS) {
                rx_push(g_sio.card_data[g_sio.cur_sector * SECTOR_SIZE + g_sio.byte_index]);
            } else {
                rx_push(0x00);
            }
            g_sio.byte_index++;
            if (g_sio.byte_index >= SECTOR_SIZE) {
                g_sio.state = MC_STATE_READ_CHECKSUM;
            }
            break;
        case MC_STATE_READ_CHECKSUM: {
            uint8_t *sec_data = &g_sio.card_data[g_sio.cur_sector * SECTOR_SIZE];
            uint8_t chk = hle_memcard_calc_sector_checksum(g_sio.cur_sector, sec_data);
            rx_push(chk);
            g_sio.state = MC_STATE_READ_END;
            break;
        }
        case MC_STATE_READ_END:
            rx_push(0x47); /* 'G' = Good */
            g_sio.state = SIO_STATE_IDLE;
            g_sio.joy_stat &= ~(1u << 7);
            break;

        /* WRITE SECTOR SEQUENCE */
        case MC_STATE_WRITE_ID1:
            rx_push(0x5A);
            g_sio.state = MC_STATE_WRITE_ID2;
            break;
        case MC_STATE_WRITE_ID2:
            rx_push(0x5D);
            g_sio.state = MC_STATE_WRITE_ADDR_MSB;
            break;
        case MC_STATE_WRITE_ADDR_MSB:
            g_sio.sector_msb = tx_byte;
            rx_push(0x00);
            g_sio.state = MC_STATE_WRITE_ADDR_LSB;
            break;
        case MC_STATE_WRITE_ADDR_LSB:
            g_sio.sector_lsb = tx_byte;
            g_sio.cur_sector = ((uint16_t)g_sio.sector_msb << 8) | g_sio.sector_lsb;
            g_sio.byte_index = 0;
            rx_push(0x00);
            g_sio.state = MC_STATE_WRITE_DATA;
            break;
        case MC_STATE_WRITE_DATA:
            if (g_sio.byte_index < SECTOR_SIZE) {
                g_sio.tmp_write[g_sio.byte_index++] = tx_byte;
            }
            rx_push(0x00);
            if (g_sio.byte_index >= SECTOR_SIZE) {
                g_sio.state = MC_STATE_WRITE_CHECKSUM;
            }
            break;
        case MC_STATE_WRITE_CHECKSUM: {
            uint8_t expected_chk = hle_memcard_calc_sector_checksum(g_sio.cur_sector, g_sio.tmp_write);
            g_sio.chk_match = (tx_byte == expected_chk);
            rx_push(0x5C); /* ACK1 */
            g_sio.state = MC_STATE_WRITE_ACK2;
            break;
        }
        case MC_STATE_WRITE_ACK2:
            rx_push(0x5D); /* ACK2 */
            g_sio.state = MC_STATE_WRITE_END;
            break;
        case MC_STATE_WRITE_END:
            if (g_sio.chk_match) {
                if (g_sio.cur_sector < TOTAL_SECTORS) {
                    memcpy(&g_sio.card_data[g_sio.cur_sector * SECTOR_SIZE], g_sio.tmp_write, SECTOR_SIZE);
                    hle_memcard_save("memcard.mcd");
                }
                rx_push(0x47); /* 'G' = Good */
            } else {
                rx_push(0x4E); /* 'N' = Bad Checksum */
            }
            /* Writing resets unread dir flag */
            g_sio.flag_byte = 0x00;
            g_sio.state = SIO_STATE_IDLE;
            g_sio.joy_stat &= ~(1u << 7);
            break;

        /* GET ID SEQUENCE */
        case MC_STATE_GETID_ID1: rx_push(0x5A); g_sio.state = MC_STATE_GETID_ID2; break;
        case MC_STATE_GETID_ID2: rx_push(0x5D); g_sio.state = MC_STATE_GETID_ACK1; break;
        case MC_STATE_GETID_ACK1: rx_push(0x5C); g_sio.state = MC_STATE_GETID_ACK2; break;
        case MC_STATE_GETID_ACK2: rx_push(0x5D); g_sio.state = MC_STATE_GETID_B0; break;
        case MC_STATE_GETID_B0: rx_push(0x04); g_sio.state = MC_STATE_GETID_B1; break;
        case MC_STATE_GETID_B1: rx_push(0x00); g_sio.state = MC_STATE_GETID_B2; break;
        case MC_STATE_GETID_B2: rx_push(0x00); g_sio.state = MC_STATE_GETID_B3; break;
        case MC_STATE_GETID_B3:
            rx_push(0x80);
            g_sio.state = SIO_STATE_IDLE;
            g_sio.joy_stat &= ~(1u << 7);
            break;

        /* PAD POLL SEQUENCE */
        case PAD_STATE_POLL:
            if (tx_byte == 0x42) {
                rx_push(0x41); /* Digital Pad ID */
                g_sio.state = PAD_STATE_BYTE1;
            } else {
                rx_push(0xFF);
                g_sio.state = SIO_STATE_IDLE;
            }
            break;
        case PAD_STATE_BYTE1:
            rx_push(0x5A);
            g_sio.state = PAD_STATE_SW_LO;
            break;
        case PAD_STATE_SW_LO:
            rx_push((uint8_t)(g_sio.pad_buttons & 0xFF));
            g_sio.state = PAD_STATE_SW_HI;
            break;
        case PAD_STATE_SW_HI:
            rx_push((uint8_t)((g_sio.pad_buttons >> 8) & 0xFF));
            g_sio.state = SIO_STATE_IDLE;
            g_sio.joy_stat &= ~(1u << 7);
            break;
    }

    /* Trigger ACK IRQ if enabled */
    if ((g_sio.joy_ctrl & (1u << 12)) && (g_sio.joy_stat & (1u << 7))) {
        g_sio.joy_stat |= (1u << 9); /* Set IRQ7 */
    }
}

void hle_sio_port_write(uint32_t addr, uint8_t v) {
    uint32_t reg = addr & 0x0Fu;

    if (reg == 0x00) {
        /* JOY_TX_DATA */
        sio_process_byte(v);
    }
}

uint8_t hle_sio_port_read(uint32_t addr) {
    uint32_t reg = addr & 0x0Fu;

    if (reg == 0x00) {
        /* JOY_RX_DATA */
        return rx_pop();
    }
    return 0xFF;
}

uint32_t hle_sio_reg_read32(uint32_t addr) {
    uint32_t reg = addr & 0x0Fu;

    if (reg == 0x00) {
        return (uint32_t)hle_sio_port_read(addr);
    } else if (reg == 0x04) {
        return (uint32_t)g_sio.joy_stat;
    } else if (reg == 0x08) {
        return (uint32_t)g_sio.joy_mode;
    } else if (reg == 0x0A) {
        return (uint32_t)g_sio.joy_ctrl;
    } else if (reg == 0x0E) {
        return (uint32_t)g_sio.joy_baud;
    }
    return 0;
}

void hle_sio_reg_write32(uint32_t addr, uint32_t v) {
    uint32_t reg = addr & 0x0Fu;

    if (reg == 0x00) {
        hle_sio_port_write(addr, (uint8_t)(v & 0xFF));
    } else if (reg == 0x08) {
        g_sio.joy_mode = (uint16_t)(v & 0xFFFF);
    } else if (reg == 0x0A) {
        g_sio.joy_ctrl = (uint16_t)(v & 0xFFFF);
        if (v & (1u << 4)) {
            /* Reset ACK/IRQ bits in JOY_STAT */
            g_sio.joy_stat &= ~(1u << 9);
        }
        if (v & (1u << 6)) {
            /* Reset SIO */
            g_sio.state = SIO_STATE_IDLE;
            g_sio.rx_head = 0;
            g_sio.rx_tail = 0;
            g_sio.rx_count = 0;
            g_sio.joy_stat = 0x0005;
        }
    } else if (reg == 0x0E) {
        g_sio.joy_baud = (uint16_t)(v & 0xFFFF);
    }
}
