# PicoRV32 SoC with Custom Security Accelerator (Hardware & Firmware)

This repository is the central home for the complete **PicoRV32 RISC-V SoC Project**, integrating both the FPGA Hardware (RTL, Vivado synthesis, constraints) and the Software/Firmware (bare-metal drivers, test applications, and bootloader upload tools).

---

## 1. Repository Structure

```text
picorv32-project/
├── hardware/                  # FPGA Hardware & RTL Design (Verilog, constraints, Vivado)
│   ├── rtl/                   # SoC RTL modules (top.v, picorv32.v, custom security core)
│   ├── constraints/           # Board pin constraints (.xdc)
│   ├── scripts/               # Vivado build & bitstream automation (.tcl)
│   ├── tb/                    # Hardware simulation testbenches
│   └── README.md              # Hardware team guidelines & register contract
│
├── firmware/                  # Bare-metal RISC-V C Firmware & Driver Libraries
│   ├── memory_map/            # Hardware register definitions (registers.h)
│   ├── include/               # Public API headers (aes.h, uart.h, led.h, delay.h)
│   ├── src/                   # Driver implementations & main application
│   ├── sections.ld            # Linker script (8 KB App RAM @ 0x10000000)
│   ├── Makefile               # RV32I bare-metal compilation script
│   ├── tools/                 # Upload and binary conversion tools
│   └── README.md              # Firmware API reference & build guide
│
├── binaries/                  # Compiled firmware outputs
│   ├── app.bin                # Raw application image sent over UART
│   └── app.hex                # Memory hex image
│
├── flash.bat                  # One-click Windows flasher script
└── README.md                  # Project overview (this file)
```

---

## 2. System Architecture & Memory Map

The SoC pairs the PicoRV32 CPU with memory and peripherals using memory-mapped I/O:

| Address Range | Region | Size | Description |
| :--- | :--- | :--- | :--- |
| `0x0000_0000 - 0x0000_07FF` | **Boot ROM** | 2 KB | Permanent resident UART bootloader (baked into bitstream) |
| `0x1000_0000 - 0x1000_1FFF` | **Application RAM** | 8 KB | Volatile FPGA block RAM written by the bootloader over UART |
| `0x2000_0000` | **UART DATA** | 32-bit | Serial RX byte (read) / TX byte (write) @ 115200 baud |
| `0x2000_0004` | **UART STATUS** | 32-bit | Bit 0: `TX_BUSY`, Bit 1: `RX_VALID` |
| `0x3000_0000` | **LED Register** | 32-bit | 16-bit register driving board LEDs `led[15:0]` |
| `0x4000_0000 - 0x4000_005C` | **Custom AES/CMAC** | 32-bit | Cryptographic hardware accelerator (see `hardware/README.md`) |

---

## 3. Team Collaboration Workflow

### For Hardware Engineers (`hardware/`):
* Place all Verilog RTL modules in `hardware/rtl/`.
* Put Xilinx constraint files in `hardware/constraints/` (target: Real Digital Boolean board XC7S50-CSGA324-1, 100 MHz clock on pin `F14`).
* Ensure address decoding strictly matches the table above and the register contract detailed in [`hardware/README.md`](hardware/README.md).
* Preload the Boot ROM with `bootloader.hex` so the board can receive runtime firmware updates without repeated bitstream generation.

### For Firmware Engineers (`firmware/`):
* Develop drivers and user applications in `firmware/src/` and `firmware/include/`.
* Compile using the RV32 bare-metal cross compiler:
  ```bash
  cd firmware
  make clean && make
  ```
* Flashing firmware takes only seconds over serial—no Vivado synthesis required!

---

## 4. How to Flash and Run

### Step 1: Program the FPGA (Hardware)
1. Open Vivado Hardware Manager and connect to your FPGA board.
2. Program the device using the generated `.bit` bitstream file.
3. Upon programming, the onboard LEDs show pattern `0x0001` (binary `0000000000000001`). This indicates the bootloader is running and ready for firmware.

### Step 2: Upload Firmware (Software)
With the board plugged in via USB-UART:

* **From Windows (Command Prompt / PowerShell):**
  ```cmd
  flash.bat COM15
  ```
  *(Or: `python firmware\tools\upload.py COM15 binaries\app.bin`)*

* **From Makefile (WSL / Linux):**
  ```bash
  cd firmware
  make upload COM=COM15
  ```

Upon completion, the board acknowledges with `'K'`, all LEDs flash `0xFFFF` briefly, and your application immediately begins execution. To re-flash a new firmware build at any time, simply press `btn_rst` on the board to return to `0x0001` and run the flash command again.
