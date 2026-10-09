#ifndef SOC_SECURITY_H
#define SOC_SECURITY_H

#include <stdint.h>

// UART Registers
#define UART_DATA_REG         (*(volatile uint32_t *)0x20000000)
#define UART_STATUS_REG       (*(volatile uint32_t *)0x20000004)
#define UART_TX_BUSY          (1 << 0)
#define UART_RX_VALID         (1 << 1)

// LED Register
#define LED_REG               (*(volatile uint32_t *)0x30000000)

// Security Peripheral Base
#define AES_BASE              0x40000000

#define AES_CONTROL_REG       (*(volatile uint32_t *)(AES_BASE + 0x00))
#define AES_STATUS_REG        (*(volatile uint32_t *)(AES_BASE + 0x04))

// Data / Message Registers (128-bit)
#define AES_DATA0_REG         (*(volatile uint32_t *)(AES_BASE + 0x10))
#define AES_DATA1_REG         (*(volatile uint32_t *)(AES_BASE + 0x14))
#define AES_DATA2_REG         (*(volatile uint32_t *)(AES_BASE + 0x18))
#define AES_DATA3_REG         (*(volatile uint32_t *)(AES_BASE + 0x1C))

// Key Registers (128-bit)
#define AES_KEY0_REG          (*(volatile uint32_t *)(AES_BASE + 0x20))
#define AES_KEY1_REG          (*(volatile uint32_t *)(AES_BASE + 0x24))
#define AES_KEY2_REG          (*(volatile uint32_t *)(AES_BASE + 0x28))
#define AES_KEY3_REG          (*(volatile uint32_t *)(AES_BASE + 0x2C))

// Direct AES Result Registers
#define AES_RES0_REG          (*(volatile uint32_t *)(AES_BASE + 0x30))
#define AES_RES1_REG          (*(volatile uint32_t *)(AES_BASE + 0x34))
#define AES_RES2_REG          (*(volatile uint32_t *)(AES_BASE + 0x38))
#define AES_RES3_REG          (*(volatile uint32_t *)(AES_BASE + 0x3C))

// CMAC Output Tag Registers
#define CMAC_TAG0_REG         (*(volatile uint32_t *)(AES_BASE + 0x40))
#define CMAC_TAG1_REG         (*(volatile uint32_t *)(AES_BASE + 0x44))
#define CMAC_TAG2_REG         (*(volatile uint32_t *)(AES_BASE + 0x48))
#define CMAC_TAG3_REG         (*(volatile uint32_t *)(AES_BASE + 0x4C))

// CMAC Expected Tag Registers (for Verification)
#define CMAC_EXP0_REG         (*(volatile uint32_t *)(AES_BASE + 0x50))
#define CMAC_EXP1_REG         (*(volatile uint32_t *)(AES_BASE + 0x54))
#define CMAC_EXP2_REG         (*(volatile uint32_t *)(AES_BASE + 0x58))
#define CMAC_EXP3_REG         (*(volatile uint32_t *)(AES_BASE + 0x5C))

// Command Control Bits
#define CMD_START_ENCRYPT     (1 << 0)
#define CMD_START_DECRYPT     (1 << 1)
#define CMD_INIT_KEY          (1 << 2)
#define CMD_CMAC_GENERATE     (1 << 3)
#define CMD_CMAC_VERIFY       (1 << 4)

// Status Flags
#define STATUS_KEY_READY      (1 << 0)
#define STATUS_CIPHER_READY   (1 << 1)
#define STATUS_BUSY           (1 << 2)
#define STATUS_CMAC_DONE      (1 << 3)
#define STATUS_CMAC_VALID     (1 << 4)
#define STATUS_TAMPER_DETECTED (1 << 5)

#endif // SOC_SECURITY_H