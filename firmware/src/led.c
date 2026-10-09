#include "led.h"
#include "../memory_map/registers.h"

void led_set(uint16_t val)
{
    LED_REG = (uint32_t)val;
}

uint16_t led_get(void)
{
    return (uint16_t)(LED_REG & 0xFFFF);
}

void led_toggle(uint16_t mask)
{
    uint16_t current = led_get();
    led_set(current ^ mask);
}

void led_on(uint16_t mask)
{
    uint16_t current = led_get();
    led_set(current | mask);
}

void led_off(uint16_t mask)
{
    uint16_t current = led_get();
    led_set(current & ~mask);
}
