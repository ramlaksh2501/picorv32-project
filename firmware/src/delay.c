#include "delay.h"

void delay_loops(uint32_t count)
{
    if (count == 0) return;
    __asm__ volatile (
        "1:\n"
        "   addi %0, %0, -1\n"
        "   bnez %0, 1b\n"
        : "+r" (count)
        :
        : "memory"
    );
}

void delay_ms(uint32_t ms)
{
    // At 100 MHz, the 2-instruction loop (addi + bnez) executes at ~13 cycles/iter.
    // 1 ms = 100,000 cycles -> ~7692 iterations per ms.
    for (uint32_t i = 0; i < ms; i++) {
        delay_loops(7692);
    }
}

void delay_us(uint32_t us)
{
    // ~8 iterations per microsecond at 100 MHz
    delay_loops(us * 8);
}
