#include "uart.h"
#include "../memory_map/registers.h"

void uart_init(void)
{
    // Hardware UART is already configured by FPGA bitstream (115200 baud @ 100MHz)
}

int uart_tx_busy(void)
{
    return (UART_STATUS_REG & UART_TX_BUSY) ? 1 : 0;
}

int uart_rx_ready(void)
{
    return (UART_STATUS_REG & UART_RX_VALID) ? 1 : 0;
}

void uart_putc(char c)
{
    while (UART_STATUS_REG & UART_TX_BUSY)
        ;
    UART_DATA_REG = (uint32_t)(uint8_t)c;
}

char uart_getc(void)
{
    while (!(UART_STATUS_REG & UART_RX_VALID))
        ;
    return (char)(uint8_t)UART_DATA_REG;
}

void uart_puts(const char *str)
{
    if (!str) return;
    while (*str) {
        if (*str == '\n') {
            uart_putc('\r');
        }
        uart_putc(*str);
        str++;
    }
}

static char nibble_to_hex(uint8_t n)
{
    n &= 0x0F;
    return (n < 10) ? ('0' + n) : ('A' + (n - 10));
}

void uart_print_hex8(uint8_t val)
{
    uart_putc(nibble_to_hex(val >> 4));
    uart_putc(nibble_to_hex(val));
}

void uart_print_hex32(uint32_t val)
{
    uart_puts("0x");
    for (int i = 7; i >= 0; i--) {
        uart_putc(nibble_to_hex((uint8_t)(val >> (i * 4))));
    }
}

void uart_print_128(const uint32_t words[4])
{
    // Print 128-bit word in standard big-endian hex (word0 is MSB or LSB)
    for (int i = 0; i < 4; i++) {
        for (int b = 7; b >= 0; b--) {
            uart_putc(nibble_to_hex((uint8_t)(words[i] >> (b * 4))));
        }
        if (i < 3) uart_putc(' ');
    }
}
