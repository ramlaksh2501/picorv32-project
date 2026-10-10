# PicoRV32 Firmware Development Guide & API Reference

This directory contains the source code, driver libraries, build system, and upload scripts for bare-metal firmware targeting the PicoRV32 RISC-V SoC with the Custom Security (AES/CMAC) hardware block.

---

## 1. Directory Layout

```text
firmware/
├── memory_map/
│   └── registers.h        # Base addresses, peripheral offsets & status bits
├── include/               # Public API headers
│   ├── aes.h              # Hardware AES-128 & CMAC driver
│   ├── uart.h             # 115200 baud UART serial driver
│   ├── led.h              # 16-bit onboard LED driver
│   └── delay.h            # Calibrated delay functions (100 MHz clock)
├── src/                   # Source implementations
│   ├── start.s            # RV32I startup assembly (stack pointer init)
│   ├── main.c             # Military Field Node SoC Secure Controller (production app)
│   ├── aes_test_app.c     # Standalone secure node communication application
│   ├── aes.c              # Cryptographic hardware accelerator routines
│   ├── uart.c             # Serial communication & formatted hex output
│   ├── led.c              # LED register control
│   └── delay.c            # Calibrated busy-wait loops
├── sections.ld            # Linker script (8 KB App RAM @ 0x10000000)
├── Makefile               # GNU Make build configuration
└── tools/
    ├── makehex.py         # Utility to generate $readmemh hex files
    └── upload.py          # UART bootloader flashing client
```

---

## 2. Memory Organization & Linker Script

The PicoRV32 bootloader loads the compiled application into **Application RAM**:
* **Origin**: `0x1000_0000`
* **Size**: `8 KB` (`8192` bytes)
* **Stack Pointer**: Initialized to `0x1000_1FFC` in `start.s` (grows downward).

Memory sections defined in `sections.ld`:
* `.text`: Executable code and vectors
* `.rodata`: Read-only constants (strings, lookup tables)
* `.data`: Initialized global/static variables
* `.bss` / `COMMON`: Zero-initialized global/static variables

---

## 3. Peripheral Driver APIs

### 3.1 Security Block: AES-128 & CMAC (`include/aes.h`)

Base Address: `0x4000_0000`

#### Functions:
* `int aes_init_key(const uint32_t key[4])`
  * Loads a 128-bit key into `AES_KEY0..3_REG` and issues `CMD_INIT_KEY`.
  * Returns `0` on success, `-1` on timeout, `-2` if tamper detected.
* `int aes_encrypt_block(const uint32_t plaintext[4], uint32_t ciphertext[4])`
  * Encrypts a 128-bit block in hardware using `CMD_START_ENCRYPT`.
  * Outputs the resulting ciphertext into `ciphertext[0..3]`.
* `int aes_decrypt_block(const uint32_t ciphertext[4], uint32_t plaintext[4])`
  * Decrypts a 128-bit block in hardware using `CMD_START_DECRYPT`.
  * Outputs the recovered plaintext into `plaintext[0..3]`.
* `int aes_cmac_generate(const uint32_t msg[4], uint32_t tag[4])`
  * Generates a 128-bit CMAC authentication tag using `CMD_CMAC_GENERATE`.
  * Stores tag into `tag[0..3]`.
* `int aes_cmac_verify(const uint32_t msg[4], const uint32_t expected_tag[4])`
  * Performs hardware verification using `CMD_CMAC_VERIFY`.
  * Returns `1` if valid and intact, `0` if invalid or tampered.
* `uint32_t aes_get_status(void)` — Reads raw status register.
* `bool aes_is_busy(void)` — Returns `true` if operation in progress.
* `bool aes_tamper_detected(void)` — Returns `true` if tamper flag is asserted.

---

### 3.2 UART Driver (`include/uart.h`)

Base Address: `0x2000_0000` (Data), `0x2000_0004` (Status)  
Baud Rate: `115200 baud` @ 100 MHz clock

#### Functions:
* `void uart_init(void)` — Ready check / initialization.
* `void uart_putc(char c)` — Transmit a single character (blocking until TX buffer ready).
* `char uart_getc(void)` — Receive a single character (blocking until RX valid).
* `int uart_rx_ready(void)` — Non-blocking check for received characters.
* `int uart_tx_busy(void)` — Check if transmitter is busy.
* `void uart_puts(const char *str)` — Transmit string (automatically handles `\r\n`).
* `void uart_print_hex32(uint32_t val)` — Formats and prints a 32-bit hex word (e.g. `0x1234ABCD`).
* `void uart_print_hex8(uint8_t val)` — Formats and prints an 8-bit hex byte.
* `void uart_print_128(const uint32_t words[4])` — Prints four 32-bit words formatted as a 128-bit block.

---

### 3.3 LED Driver (`include/led.h`)

Base Address: `0x3000_0000`

#### Functions:
* `void led_set(uint16_t val)` — Directly write 16-bit LED state (`1` = ON, `0` = OFF).
* `uint16_t led_get(void)` — Read back current 16-bit LED register value.
* `void led_toggle(uint16_t mask)` — Inverts the LEDs indicated by `mask`.
* `void led_on(uint16_t mask)` — Turns ON LEDs indicated by `mask`.
* `void led_off(uint16_t mask)` — Turns OFF LEDs indicated by `mask`.

---

### 3.4 Delay Utilities (`include/delay.h`)

Calibrated for 100 MHz clock frequency:

#### Functions:
* `void delay_ms(uint32_t ms)` — Busy-wait delay in milliseconds (accurate at 100 MHz).
* `void delay_us(uint32_t us)` — Busy-wait delay in microseconds.
* `void delay_loops(uint32_t count)` — Raw cycle loop counter (`addi` + `bnez`).

---

## 4. Build Instructions

Use GNU Make with a bare-metal RISC-V cross compiler (`riscv64-unknown-elf-gcc` or `riscv-none-elf-gcc`).

### Compile:
```bash
make clean
make
```

### Compiler Flags:
* `-march=rv32i`: RV32 base integer instruction set (PicoRV32 standard core).
* `-mabi=ilp32`: 32-bit integer, long, and pointer ABI.
* `-mno-relax`: Disables linker relaxation to avoid unsupported GP-relative relocations.
* `-O2`: Optimized for size and execution speed.
* `-ffreestanding -nostdlib`: Bare-metal execution without OS runtime or standard libraries.

Build outputs are saved to `../binaries/`:
* `app.bin` / `aes_test_app.bin`: Raw binary flashed directly to FPGA App RAM.
* `app.hex` / `aes_test_app.hex`: Memory hex file for simulation or ROM initialization (2048 words, 8 KB).

---

## 5. Uploading & Flashing Firmware

To flash your compiled application into the board:

1. Reset the FPGA board via `btn_rst` (onboard LEDs will show `0x0001` indicating bootloader waiting).
2. Run the upload command:

```bash
# From Makefile:
make upload COM=COM15

# Or using Python directly from Windows:
python tools/upload.py COM15 ../binaries/app.bin
```

When upload succeeds:
* The host script prints: `Upload confirmed -- application should now be running.`
* The board receives the image, responds with `'K'`, flashes LEDs briefly to `0xFFFF`, and begins executing `main()`.
