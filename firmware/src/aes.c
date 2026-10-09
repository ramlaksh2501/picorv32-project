#include "aes.h"
#include "../memory_map/registers.h"

#define TIMEOUT_CYCLES 2000000

uint32_t aes_get_status(void)
{
    return AES_STATUS_REG;
}

bool aes_is_busy(void)
{
    return (AES_STATUS_REG & STATUS_BUSY) != 0;
}

bool aes_tamper_detected(void)
{
    return (AES_STATUS_REG & STATUS_TAMPER_DETECTED) != 0;
}

static int wait_condition(uint32_t ready_mask)
{
    uint32_t timeout = TIMEOUT_CYCLES;
    while (timeout--) {
        uint32_t status = AES_STATUS_REG;
        if (status & STATUS_TAMPER_DETECTED) {
            return -2; // Tamper detected
        }
        if (!(status & STATUS_BUSY) && (status & ready_mask)) {
            return 0; // Success
        }
    }
    return -1; // Timeout
}

int aes_init_key(const uint32_t key[4])
{
    if (!key) return -3;

    AES_KEY0_REG = key[0];
    AES_KEY1_REG = key[1];
    AES_KEY2_REG = key[2];
    AES_KEY3_REG = key[3];

    AES_CONTROL_REG = CMD_INIT_KEY;

    return wait_condition(STATUS_KEY_READY);
}

int aes_encrypt_block(const uint32_t plaintext[4], uint32_t ciphertext[4])
{
    if (!plaintext || !ciphertext) return -3;

    AES_DATA0_REG = plaintext[0];
    AES_DATA1_REG = plaintext[1];
    AES_DATA2_REG = plaintext[2];
    AES_DATA3_REG = plaintext[3];

    AES_CONTROL_REG = CMD_START_ENCRYPT;

    int ret = wait_condition(STATUS_CIPHER_READY);
    if (ret == 0) {
        ciphertext[0] = AES_RES0_REG;
        ciphertext[1] = AES_RES1_REG;
        ciphertext[2] = AES_RES2_REG;
        ciphertext[3] = AES_RES3_REG;
    }
    return ret;
}

int aes_decrypt_block(const uint32_t ciphertext[4], uint32_t plaintext[4])
{
    if (!ciphertext || !plaintext) return -3;

    AES_DATA0_REG = ciphertext[0];
    AES_DATA1_REG = ciphertext[1];
    AES_DATA2_REG = ciphertext[2];
    AES_DATA3_REG = ciphertext[3];

    AES_CONTROL_REG = CMD_START_DECRYPT;

    int ret = wait_condition(STATUS_CIPHER_READY);
    if (ret == 0) {
        plaintext[0] = AES_RES0_REG;
        plaintext[1] = AES_RES1_REG;
        plaintext[2] = AES_RES2_REG;
        plaintext[3] = AES_RES3_REG;
    }
    return ret;
}

int aes_cmac_generate(const uint32_t msg[4], uint32_t tag[4])
{
    if (!msg || !tag) return -3;

    AES_DATA0_REG = msg[0];
    AES_DATA1_REG = msg[1];
    AES_DATA2_REG = msg[2];
    AES_DATA3_REG = msg[3];

    AES_CONTROL_REG = CMD_CMAC_GENERATE;

    int ret = wait_condition(STATUS_CMAC_DONE);
    if (ret == 0) {
        tag[0] = CMAC_TAG0_REG;
        tag[1] = CMAC_TAG1_REG;
        tag[2] = CMAC_TAG2_REG;
        tag[3] = CMAC_TAG3_REG;
    }
    return ret;
}

int aes_cmac_verify(const uint32_t msg[4], const uint32_t expected_tag[4])
{
    if (!msg || !expected_tag) return -3;

    AES_DATA0_REG = msg[0];
    AES_DATA1_REG = msg[1];
    AES_DATA2_REG = msg[2];
    AES_DATA3_REG = msg[3];

    CMAC_EXP0_REG = expected_tag[0];
    CMAC_EXP1_REG = expected_tag[1];
    CMAC_EXP2_REG = expected_tag[2];
    CMAC_EXP3_REG = expected_tag[3];

    AES_CONTROL_REG = CMD_CMAC_VERIFY;

    int ret = wait_condition(STATUS_CMAC_DONE);
    if (ret == 0) {
        uint32_t status = AES_STATUS_REG;
        if ((status & STATUS_CMAC_VALID) && !(status & STATUS_TAMPER_DETECTED)) {
            return 1; // Valid
        }
        return 0; // Invalid / Tamper
    }
    return ret;
}
