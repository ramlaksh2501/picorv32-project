#ifndef UART_H
#define UART_H

#include <stdint.h>

/**
 * @brief Initialize UART (if any peripheral config needed)
 */
void uart_init(void);

/**
 * @brief Check if UART transmitter is busy
 * @return 1 if busy, 0 if ready to transmit
 */
int uart_tx_busy(void);

/**
 * @brief Check if UART receiver has data available
 * @return 1 if data is available, 0 otherwise
 */
int uart_rx_ready(void);

/**
 * @brief Transmit a single character over UART (blocking)
 * @param c Character to transmit
 */
void uart_putc(char c);

/**
 * @brief Receive a single character over UART (blocking)
 * @return Received character
 */
char uart_getc(void);

/**
 * @brief Transmit a null-terminated string over UART
 * @param str Pointer to string
 */
void uart_puts(const char *str);

/**
 * @brief Transmit a 32-bit value in hexadecimal format (e.g. 0x1234ABCD)
 * @param val 32-bit integer
 */
void uart_print_hex32(uint32_t val);

/**
 * @brief Transmit an 8-bit value in hexadecimal format
 * @param val 8-bit integer
 */
void uart_print_hex8(uint8_t val);

/**
 * @brief Transmit a 128-bit block (4x 32-bit words) in hexadecimal format
 * @param words Pointer to array of 4 uint32_t words
 */
void uart_print_128(const uint32_t words[4]);

#endif // UART_H
