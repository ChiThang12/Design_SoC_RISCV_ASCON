/* ============================================================================
 * spi.h — SoC SPI Master Driver
 *
 * Base address : 0x5002_0000  (SPI_BASE_HI = "0x50020")
 *
 * ── Register Map ─────────────────────────────────────────────────────────────
 *   0x00  TX_DATA    WO [7:0]   ghi byte vào TX FIFO
 *   0x04  RX_DATA    RO [7:0]   đọc byte từ RX FIFO (auto-pop)
 *   0x08  STATUS     RO [5:0]   {rx_overrun,rx_full,rx_empty,tx_full,tx_empty,busy}
 *   0x0C  CTRL       RW [7:0]   {spi_en,cs_auto,cpol,cpha,--,--,rx_irq_en,tx_irq_en}
 *   0x10  DIVIDER    RW [15:0]  SCK = clk/(2*(DIVIDER+1))
 *   0x14  IRQ_STATUS RW1C [1:0] {rx_valid_irq, tx_empty_irq}
 *   0x18  CS_CTRL    RW [3:0]   manual CS, active-low (khi CTRL[cs_auto]=0)
 *
 * ── CTRL bit layout (0x0C) ───────────────────────────────────────────────────
 *   [7] SPI_EN   : enable SPI core (0=off, 1=on)
 *   [6] CS_AUTO  : 1=auto-assert CS khi có data, 0=manual via CS_CTRL
 *   [5] CPOL     : clock polarity (0=idle-LOW, 1=idle-HIGH)
 *   [4] CPHA     : clock phase    (0=sample 1st edge, 1=sample 2nd edge)
 *   [1] RX_IRQ_EN: bật IRQ khi RX FIFO có data
 *   [0] TX_IRQ_EN: bật IRQ khi TX FIFO empty
 *
 * ── DIVIDER ──────────────────────────────────────────────────────────────────
 *   SCK freq = clk_freq / (2*(DIVIDER+1))
 *   @ 100 MHz: DIVIDER=4  → SCK=10 MHz
 *              DIVIDER=9  → SCK= 5 MHz
 *              DIVIDER=49 → SCK= 1 MHz
 *   #define SPI_DIV_10MHZ_100MHZ   4u
 *   #define SPI_DIV_1MHZ_100MHZ    49u
 *
 * ── DMA Channel Assignment ───────────────────────────────────────────────────
 *   DMA CH2 (mode 01 periph-to-mem): SPI RX → DMEM  (req = !rx_empty)
 *   DMA CH3 (mode 10 mem-to-periph): DMEM → SPI TX  (req = !tx_full)
 * ============================================================================ */

#ifndef _SPI_H_
#define _SPI_H_

#include <stdint.h>

/* ── Base Address ─────────────────────────────────────────────────────────── */
#define SPI_BASE_HI  "0x50020"   /* lui rx, 0x50020 → rx = 0x50020000 */

/* ── Register Offsets ────────────────────────────────────────────────────── */
#define SPI_OFS_TX_DATA     0x00
#define SPI_OFS_RX_DATA     0x04
#define SPI_OFS_STATUS      0x08
#define SPI_OFS_CTRL        0x0C
#define SPI_OFS_DIVIDER     0x10
#define SPI_OFS_IRQ_STATUS  0x14
#define SPI_OFS_CS_CTRL     0x18

/* ── STATUS bits (0x08) ──────────────────────────────────────────────────── */
#define SPI_ST_BUSY         (1u << 0)
#define SPI_ST_TX_EMPTY     (1u << 1)
#define SPI_ST_TX_FULL      (1u << 2)
#define SPI_ST_RX_EMPTY     (1u << 3)
#define SPI_ST_RX_FULL      (1u << 4)
#define SPI_ST_RX_OVERRUN   (1u << 5)

/* ── CTRL bits (0x0C) ────────────────────────────────────────────────────── */
#define SPI_CTRL_TX_IRQ_EN  (1u << 0)
#define SPI_CTRL_RX_IRQ_EN  (1u << 1)
#define SPI_CTRL_CPHA       (1u << 4)
#define SPI_CTRL_CPOL       (1u << 5)
#define SPI_CTRL_CS_AUTO    (1u << 6)
#define SPI_CTRL_EN         (1u << 7)

/* Preset SPI modes */
#define SPI_CTRL_MODE0  (SPI_CTRL_EN | SPI_CTRL_CS_AUTO)              /* CPOL=0,CPHA=0 */
#define SPI_CTRL_MODE1  (SPI_CTRL_EN | SPI_CTRL_CS_AUTO | SPI_CTRL_CPHA)
#define SPI_CTRL_MODE2  (SPI_CTRL_EN | SPI_CTRL_CS_AUTO | SPI_CTRL_CPOL)
#define SPI_CTRL_MODE3  (SPI_CTRL_EN | SPI_CTRL_CS_AUTO | SPI_CTRL_CPOL | SPI_CTRL_CPHA)

/* ── DIVIDER presets ─────────────────────────────────────────────────────── */
#define SPI_DIV_10MHZ_100MHZ    4u
#define SPI_DIV_5MHZ_100MHZ     9u
#define SPI_DIV_1MHZ_100MHZ    49u

/* ── Inline Assembly Macros ──────────────────────────────────────────────── */
#define SPI_WRITE(offset, val) do {                              \
    __asm__ volatile (                                            \
        "lui  t0, " SPI_BASE_HI "\n"                            \
        "sw   %0, %1(t0)\n"                                      \
        "fence w, w\n"                                           \
        :: "r" ((uint32_t)(val)), "i" (offset)                   \
        : "t0", "memory"                                         \
    );                                                            \
} while(0)

#define SPI_READ(offset, val) do {                               \
    __asm__ volatile (                                            \
        "lui  t0, " SPI_BASE_HI "\n"                            \
        "lw   %0, %1(t0)\n"                                      \
        : "=r" (val)                                              \
        : "i" (offset)                                            \
        : "t0", "memory"                                         \
    );                                                            \
} while(0)

/* ── API ─────────────────────────────────────────────────────────────────── */

/* Khởi tạo: mode = SPI_CTRL_MODE0..3, divider = SPI_DIV_* */
static inline void spi_init(uint32_t mode, uint32_t divider) {
    SPI_WRITE(SPI_OFS_CTRL,    0u);          /* disable trước */
    SPI_WRITE(SPI_OFS_DIVIDER, divider);
    SPI_WRITE(SPI_OFS_CTRL,    mode);
}

/* Ghi 1 byte vào TX FIFO — không blocking */
static inline void spi_write_byte(uint8_t data) {
    uint32_t st;
    do { SPI_READ(SPI_OFS_STATUS, st); } while (st & SPI_ST_TX_FULL);
    SPI_WRITE(SPI_OFS_TX_DATA, (uint32_t)data);
}

/* Đọc 1 byte từ RX FIFO — blocking wait */
static inline uint8_t spi_read_byte(void) {
    uint32_t st, val;
    do { SPI_READ(SPI_OFS_STATUS, st); } while (st & SPI_ST_RX_EMPTY);
    SPI_READ(SPI_OFS_RX_DATA, val);
    return (uint8_t)(val & 0xFFu);
}

/* Full-duplex transfer: ghi tx, đọc rx */
static inline uint8_t spi_transfer(uint8_t tx) {
    spi_write_byte(tx);
    return spi_read_byte();
}

/* Chờ SPI core rảnh (TX FIFO empty và core không busy) */
static inline void spi_wait_idle(void) {
    uint32_t st;
    do {
        SPI_READ(SPI_OFS_STATUS, st);
    } while ((st & SPI_ST_BUSY) || !(st & SPI_ST_TX_EMPTY));
}

/* Manual CS control (khi CTRL[cs_auto]=0) */
static inline void spi_cs_assert(uint8_t cs_mask) {
    /* cs_mask: bit=1 muốn assert → active-low → ghi 0 vào đó */
    SPI_WRITE(SPI_OFS_CS_CTRL, (uint32_t)(~cs_mask & 0xFu));
}

static inline void spi_cs_deassert(void) {
    SPI_WRITE(SPI_OFS_CS_CTRL, 0xFu);  /* tất cả high = deassert */
}

/* Disable SPI */
static inline void spi_disable(void) {
    SPI_WRITE(SPI_OFS_CTRL, 0u);
}

/* ── Multi-byte blocking transfer ────────────────────────────────────────── */

/* Ghi N bytes từ buf, bỏ RX */
static inline void spi_write_buf(const uint8_t *buf, uint32_t len) {
    uint32_t i;
    for (i = 0u; i < len; i++) {
        spi_write_byte(buf[i]);
    }
    spi_wait_idle();
}

/* Full-duplex N bytes: tx_buf → SPI, SPI → rx_buf */
static inline void spi_transfer_buf(const uint8_t *tx_buf, uint8_t *rx_buf,
                                     uint32_t len) {
    uint32_t i;
    for (i = 0u; i < len; i++) {
        rx_buf[i] = spi_transfer(tx_buf[i]);
    }
}

/* ── IRQ helpers ─────────────────────────────────────────────────────────── */
static inline uint32_t spi_read_irq_status(void) {
    uint32_t v;
    SPI_READ(SPI_OFS_IRQ_STATUS, v);
    return v;
}

static inline void spi_clear_irq(void) {
    SPI_WRITE(SPI_OFS_IRQ_STATUS, 0x3u);  /* clear cả TX và RX IRQ */
}

#endif /* _SPI_H_ */
