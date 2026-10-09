# PicoRV32 SoC Firmware Workspace with Custom Security Peripheral

This workspace contains the complete firmware development environment, peripheral hardware drivers, and upload utilities for the **PicoRV32 RISC-V SoC** running on the Real Digital Boolean FPGA board (or compatible).

---

## Architecture & Memory Map

| Base Address | Region | Description |
| :--- | :--- | :--- |
| `0x0000_0000` | Boot ROM (2 KB) | Resident UART bootloader baked into bitstream |
| `0x1000_0000` | Application RAM (8 KB) | User firmware loaded over UART at runtime |
| `0x2000_0000` | UART DATA | Read: RX byte / Write: TX byte (115200 baud) |
| `0x2000_0004` | UART STATUS | bit0: `TX_BUSY`, bit1: `RX_VALID` |
| `0x3000_0000` | LED Register | 16-bit register connected to `led[15:0]` |
| `0x4000_0000` | **Custom AES / CMAC Block** | Hardware cryptographic accelerator |

### Custom Block (`0x4000_0000`) Registers
- `+0x00`: **Control Register** (`CMD_START_ENCRYPT`, `CMD_START_DECRYPT`, `CMD_INIT_KEY`, `CMD_CMAC_GENERATE`, `CMD_CMAC_VERIFY`)
- `+0x04`: **Status Register** (`KEY_READY`, `CIPHER_READY`, `BUSY`, `CMAC_DONE`, `CMAC_VALID`, `TAMPER_DETECTED`)
- `+0x10..+0x1C`: **Data Registers** (128-bit input block: DATA0..DATA3)
- `+0x20..+0x2C`: **Key Registers** (128-bit key: KEY0..KEY3)
- `+0x30..+0x3C`: **AES Result Registers** (128-bit output block: RES0..RES3)
- `+0x40..+0x4C`: **CMAC Output Tag Registers** (128-bit generated tag: TAG0..TAG3)
- `+0x50..+0x5C`: **CMAC Expected Tag Registers** (128-bit expected tag: EXP0..EXP3)

---

## Directory Structure

```text
picorv32-project/
├── binaries/                  # Output binaries ready for flashing
│   ├── app.bin                # Raw binary image (uploaded to App RAM)
│   └── app.hex                # Memory hex representation
├── firmware/
│   ├── memory_map/
│   │   └── registers.h        # Hardware register offsets & bitfield definitions
│   ├── include/               # Modular driver headers
│   │   ├── uart.h             # UART driver API
│   │   ├── led.h              # LED driver API
│   │   ├── delay.h            # Calibrated delay routines
│   │   └── aes.h              # Custom AES/CMAC block driver API
│   ├── src/                   # Driver implementations & app code
│   │   ├── start.s            # RV32I startup assembly (stack initialization)
│   │   ├── uart.c             # UART transmission, reception, and hex printing
│   │   ├── led.c              # LED manipulation functions
│   │   ├── delay.c            # Accurate busy-wait delays for 100 MHz clock
│   │   ├── aes.c              # Complete hardware AES-128 & CMAC driver
│   │   └── main.c             # Demo application testing all peripherals
│   ├── sections.ld            # Linker script targeting 8 KB App RAM @ 0x10000000
│   ├── Makefile               # Automated build script (rv32i bare-metal)
│   └── tools/
│       ├── makehex.py         # Binary to hex converter
│       └── upload.py          # UART flasher script matching bootloader
├── flash.bat                  # One-click Windows flasher script
└── README.md
```

---

## Building the Firmware

Build using `make` (inside WSL or a bash environment with `riscv64-unknown-elf-gcc` or `riscv-none-elf-gcc`):

```bash
cd firmware
make clean
make
```

This compiles all drivers, links with `sections.ld`, and outputs `app.bin` and `app.hex` into the `binaries/` directory.

---

## Flashing the Board

1. Ensure the FPGA is programmed with the PicoRV32 bitstream.
2. The onboard LEDs will show pattern `0x0001` (waiting for upload).
3. Run the flash command:

### From Windows (PowerShell or Command Prompt):
```powershell
# Using the python script:
python firmware\tools\upload.py COM15 binaries\app.bin

# Or using the one-click script:
.\flash.bat COM15
```

### From Makefile:
```bash
make upload COM=COM15
```

When upload completes, the board acknowledges with `'K'`, all LEDs jump briefly to `0xFFFF`, and the application starts running immediately.
