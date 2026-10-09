#ifndef LED_H
#define LED_H

#include <stdint.h>

/**
 * @brief Set the 16-bit LED register value
 * @param val 16-bit LED bitmask (1 = ON, 0 = OFF)
 */
void led_set(uint16_t val);

/**
 * @brief Get the current 16-bit LED register value
 * @return Current 16-bit LED value
 */
uint16_t led_get(void);

/**
 * @brief Toggle LEDs specified by mask
 * @param mask 16-bit mask of LEDs to invert
 */
void led_toggle(uint16_t mask);

/**
 * @brief Turn ON LEDs specified by mask
 * @param mask 16-bit mask of LEDs to turn on
 */
void led_on(uint16_t mask);

/**
 * @brief Turn OFF LEDs specified by mask
 * @param mask 16-bit mask of LEDs to turn off
 */
void led_off(uint16_t mask);

#endif // LED_H
