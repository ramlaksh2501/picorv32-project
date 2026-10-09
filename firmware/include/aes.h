#ifndef AES_H
#define AES_H

#include <stdint.h>
#include <stdbool.h>

/**
 * @brief Initialize AES hardware key (128-bit)
 * @param key Array of 4 uint32_t words (128-bit key)
 * @return 0 on success, negative error code on timeout
 */
int aes_init_key(const uint32_t key[4]);

/**
 * @brief Encrypt a 128-bit block using custom AES hardware
 * @param plaintext Array of 4 uint32_t words (128-bit input)
 * @param ciphertext Array of 4 uint32_t words (128-bit output)
 * @return 0 on success, negative error code on timeout/tamper
 */
int aes_encrypt_block(const uint32_t plaintext[4], uint32_t ciphertext[4]);

/**
 * @brief Decrypt a 128-bit block using custom AES hardware
 * @param ciphertext Array of 4 uint32_t words (128-bit input)
 * @param plaintext Array of 4 uint32_t words (128-bit output)
 * @return 0 on success, negative error code on timeout/tamper
 */
int aes_decrypt_block(const uint32_t ciphertext[4], uint32_t plaintext[4]);

/**
 * @brief Generate a CMAC tag for a 128-bit block
 * @param msg Array of 4 uint32_t words (128-bit message)
 * @param tag Array of 4 uint32_t words (128-bit generated tag output)
 * @return 0 on success, negative error code on timeout
 */
int aes_cmac_generate(const uint32_t msg[4], uint32_t tag[4]);

/**
 * @brief Verify a CMAC tag for a 128-bit block in hardware
 * @param msg Array of 4 uint32_t words (128-bit message)
 * @param expected_tag Array of 4 uint32_t words (128-bit expected tag)
 * @return 1 if CMAC is valid, 0 if invalid/tampered, negative on timeout
 */
int aes_cmac_verify(const uint32_t msg[4], const uint32_t expected_tag[4]);

/**
 * @brief Read raw AES peripheral status register
 * @return 32-bit status register value
 */
uint32_t aes_get_status(void);

/**
 * @brief Check if AES peripheral is busy
 * @return true if busy, false otherwise
 */
bool aes_is_busy(void);

/**
 * @brief Check if tamper was detected by the security hardware
 * @return true if tamper flag set, false otherwise
 */
bool aes_tamper_detected(void);

#endif // AES_H
