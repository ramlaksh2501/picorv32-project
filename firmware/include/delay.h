#ifndef DELAY_H
#define DELAY_H

#include <stdint.h>

/**
 * @brief Core clock frequency definition (100 MHz)
 */
#define F_CPU 100000000UL

/**
 * @brief Busy-wait delay in milliseconds (calibrated for 100 MHz PicoRV32)
 * @param ms Milliseconds to delay
 */
void delay_ms(uint32_t ms);

/**
 * @brief Busy-wait delay in microseconds (calibrated for 100 MHz PicoRV32)
 * @param us Microseconds to delay
 */
void delay_us(uint32_t us);

/**
 * @brief Raw loop-iteration delay
 * @param count Loop iterations
 */
void delay_loops(uint32_t count);

#endif // DELAY_H
