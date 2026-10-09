#include <stdint.h>
#include <stdbool.h>
#include "uart.h"
#include "led.h"
#include "delay.h"
#include "aes.h"

// NIST AES-128 Test Vector
// Key: 2b7e1516 28aed2a6 abf71588 09cf4f3c
static const uint32_t test_key[4] = {
    0x2b7e1516, 0x28aed2a6, 0xabf71588, 0x09cf4f3c
};

// Plaintext: 6bc1bee2 2e409f96 e93d7e11 7393172a
static const uint32_t test_plain[4] = {
    0x6bc1bee2, 0x2e409f96, 0xe93d7e11, 0x7393172a
};

// Expected Ciphertext: 3ad77bb4 0d7a3660 a89ecaf3 2466ef97
static const uint32_t expected_cipher[4] = {
    0x3ad77bb4, 0x0d7a3660, 0xa89ecaf3, 0x2466ef97
};

int main(void)
{
    led_set(0x0001); // Signal start of execution
    uart_init();

    delay_ms(50); // Settle UART

    uart_puts("\n\n========================================\n");
    uart_puts("   PicoRV32 Security SoC Firmware Demo  \n");
    uart_puts("   Clock: 100 MHz | Memory: 8 KB SRAM   \n");
    uart_puts("   Custom Block: AES/CMAC @ 0x40000000 \n");
    uart_puts("========================================\n\n");

    led_set(0x0003);

    // 1. Initialize Key
    uart_puts("[1] Loading 128-bit AES Key... ");
    int res = aes_init_key(test_key);
    if (res == 0) {
        uart_puts("OK\n    Key: ");
        uart_print_128(test_key);
        uart_puts("\n");
    } else {
        uart_puts("FAILED (code ");
        uart_print_hex32((uint32_t)res);
        uart_puts(")\n");
    }

    // 2. Test Encryption
    uint32_t cipher[4] = {0};
    uart_puts("[2] Testing AES-128 Encryption...\n");
    uart_puts("    Plaintext : ");
    uart_print_128(test_plain);
    uart_puts("\n");

    res = aes_encrypt_block(test_plain, cipher);
    if (res == 0) {
        uart_puts("    Ciphertext: ");
        uart_print_128(cipher);
        uart_puts("\n");

        bool match = true;
        for (int i = 0; i < 4; i++) {
            if (cipher[i] != expected_cipher[i]) match = false;
        }
        if (match) {
            uart_puts("    Match NIST Vector: SUCCESS\n");
        } else {
            uart_puts("    Note: Output differs from standard vector\n");
        }
    } else {
        uart_puts("    Encryption FAILED (code ");
        uart_print_hex32((uint32_t)res);
        uart_puts(")\n");
    }

    // 3. Test Decryption
    uint32_t decrypted[4] = {0};
    uart_puts("[3] Testing AES-128 Decryption...\n");
    res = aes_decrypt_block(cipher, decrypted);
    if (res == 0) {
        uart_puts("    Decrypted : ");
        uart_print_128(decrypted);
        uart_puts("\n");

        bool plain_match = true;
        for (int i = 0; i < 4; i++) {
            if (decrypted[i] != test_plain[i]) plain_match = false;
        }
        if (plain_match) {
            uart_puts("    Plaintext recovery: SUCCESS\n");
        } else {
            uart_puts("    Plaintext recovery: MISMATCH\n");
        }
    } else {
        uart_puts("    Decryption FAILED\n");
    }

    // 4. Test CMAC Generation
    uint32_t cmac_tag[4] = {0};
    uart_puts("[4] Testing CMAC Tag Generation...\n");
    res = aes_cmac_generate(test_plain, cmac_tag);
    if (res == 0) {
        uart_puts("    CMAC Tag  : ");
        uart_print_128(cmac_tag);
        uart_puts("\n");

        // 5. Test CMAC Verification
        uart_puts("[5] Verifying CMAC in Hardware... ");
        int vres = aes_cmac_verify(test_plain, cmac_tag);
        if (vres == 1) {
            uart_puts("VALID (PASSED)\n");
        } else {
            uart_puts("INVALID (FAILED)\n");
        }
    } else {
        uart_puts("    CMAC Generation FAILED\n");
    }

    uart_puts("\nFirmware running. Entering heartbeat loop (toggling LEDs)...\n");

    // Main Heartbeat / Echo loop
    uint16_t led_val = 0x00FF;
    while (1) {
        led_set(led_val);
        led_val ^= 0xFFFF; // Alternate 8-bit banks

        // Check if user sent a byte over UART, echo back with acknowledge
        if (uart_rx_ready()) {
            char ch = uart_getc();
            uart_puts("Echo: ");
            uart_putc(ch);
            uart_puts("\n");
        }

        delay_ms(500); // 0.5 sec toggle
    }

    return 0;
}
