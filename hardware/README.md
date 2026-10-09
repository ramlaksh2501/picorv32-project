# Hardware Design & FPGA Implementation Guide

This directory is designated for the **FPGA Hardware / RTL Design** of the PicoRV32 SoC with the Custom Security (AES/CMAC) hardware block.

---

## 1. Directory Structure for Hardware Team

Place all Verilog, constraint files, and Vivado automation scripts here:

```text
hardware/
├── rtl/                   # Verilog / SystemVerilog source files (.v, .sv)
│   ├── top.v              # Top-level SoC wrapper (CPU + BRAM + Peripherals)
│   ├── picorv32.v         # PicoRV32 RISC-V core (from YosysHQ)
│   └── custom_security/   # Custom AES-128 & CMAC hardware accelerator module
│       ├── aes_top.v
│       ├── aes_core.v
│       └── cmac_core.v
├── constraints/           # FPGA pin & timing constraints
│   └── boolean.xdc        # Board constraints (Clk, Reset, UART TX/RX, LEDs)
├── tb/                    # Testbenches for simulation (Icarus / ModelSim / Vivado)
│   └── tb_top.v
├── scripts/               # Vivado automation scripts
│   └── build.tcl          # Synthesis, implementation & bitstream generation
└── bootloader.hex         # Resident bootloader ROM image (preloaded into Boot ROM)
```

---

## 2. Hardware-Firmware Interface Contract

The firmware drivers in `../firmware/` strictly adhere to this memory map. Any hardware changes must preserve these address decodes:

| Base Address | Region | Size | Target & Behavior |
| :--- | :--- | :--- | :--- |
| `0x0000_0000` | **Boot ROM** | 2 KB | Preloaded with `bootloader.hex` via `$readmemh`. Runs immediately on reset. |
| `0x1000_0000` | **App RAM** | 8 KB | Volatile block RAM written by the bootloader over UART at runtime. |
| `0x2000_0000` | **UART DATA** | 32-bit | Read: RX byte (bits [7:0]) / Write: TX byte (bits [7:0]). |
| `0x2000_0004` | **UART STATUS**| 32-bit | Bit 0: `TX_BUSY` (1 = transmitting), Bit 1: `RX_VALID` (1 = received byte available). |
| `0x3000_0000` | **LED Register**| 32-bit | Bits [15:0] drive physical board LEDs `led[15:0]`. |
| `0x4000_0000` | **Custom AES/CMAC**| 32-bit | Hardware cryptographic accelerator (register map below). |

### Custom Block Register Specifications (`0x4000_0000` Base)

```text
Offset    Register Name      Access   Description / Bitfields
------------------------------------------------------------------------------------------
+0x00     AES_CONTROL_REG    W        Bit 0: CMD_START_ENCRYPT  (Trigger 128-bit encryption)
                                      Bit 1: CMD_START_DECRYPT  (Trigger 128-bit decryption)
                                      Bit 2: CMD_INIT_KEY       (Load & expand 128-bit key)
                                      Bit 3: CMD_CMAC_GENERATE  (Generate CMAC authentication tag)
                                      Bit 4: CMD_CMAC_VERIFY    (Verify message against expected tag)

+0x04     AES_STATUS_REG     R        Bit 0: STATUS_KEY_READY       (1 = Key expanded and ready)
                                      Bit 1: STATUS_CIPHER_READY    (1 = Encryption/decryption complete)
                                      Bit 2: STATUS_BUSY            (1 = Hardware engine active)
                                      Bit 3: STATUS_CMAC_DONE       (1 = CMAC generation/verify done)
                                      Bit 4: STATUS_CMAC_VALID      (1 = Verification matched)
                                      Bit 5: STATUS_TAMPER_DETECTED (1 = Hardware tamper/mismatch alert)

+0x10     AES_DATA0_REG      R/W      Message / Plaintext Word 0 [31:0]
+0x14     AES_DATA1_REG      R/W      Message / Plaintext Word 1 [63:32]
+0x18     AES_DATA2_REG      R/W      Message / Plaintext Word 2 [95:64]
+0x1C     AES_DATA3_REG      R/W      Message / Plaintext Word 3 [127:96]

+0x20     AES_KEY0_REG       W        Key Word 0 [31:0]
+0x24     AES_KEY1_REG       W        Key Word 1 [63:32]
+0x28     AES_KEY2_REG       W        Key Word 2 [95:64]
+0x2C     AES_KEY3_REG       W        Key Word 3 [127:96]

+0x30     AES_RES0_REG       R        Ciphertext / Recovered Plaintext Word 0 [31:0]
+0x34     AES_RES1_REG       R        Ciphertext / Recovered Plaintext Word 1 [63:32]
+0x38     AES_RES2_REG       R        Ciphertext / Recovered Plaintext Word 2 [95:64]
+0x3C     AES_RES3_REG       R        Ciphertext / Recovered Plaintext Word 3 [127:96]

+0x40     CMAC_TAG0_REG      R        Generated CMAC Tag Word 0 [31:0]
+0x44     CMAC_TAG1_REG      R        Generated CMAC Tag Word 1 [63:32]
+0x48     CMAC_TAG2_REG      R        Generated CMAC Tag Word 2 [95:64]
+0x4C     CMAC_TAG3_REG      R        Generated CMAC Tag Word 3 [127:96]

+0x50     CMAC_EXP0_REG      W        Expected CMAC Tag Word 0 [31:0] (for verification)
+0x54     CMAC_EXP1_REG      W        Expected CMAC Tag Word 1 [63:32]
+0x58     CMAC_EXP2_REG      W        Expected CMAC Tag Word 2 [95:64]
+0x5C     CMAC_EXP3_REG      W        Expected CMAC Tag Word 3 [127:96]
```

---

## 3. Clocking and Baud Rate Timing

* **System Clock**: **100 MHz** (from onboard oscillator, pin `F14`).
* **UART Timing**: **115200 baud**.
  $$\text{CLKS\_PER\_BIT} = \frac{100{,}000{,}000\,\text{Hz}}{115200\,\text{baud}} = 868\,\text{cycles}$$
* **Reset**: Push button reset on pin `J2` (`btn_rst`, active-high, synchronized to active-low `resetn` internally).

---

## 4. Hardware Build Workflow (Vivado)

1. Put all module files in `hardware/rtl/`.
2. Ensure `bootloader.hex` is in the synthesis folder (needed for `$readmemh("bootloader.hex", bootrom)`).
3. Run synthesis and generate bitstream in Vivado:
   ```tcl
   source scripts/build.tcl
   ```
4. Program the FPGA via Hardware Manager.
5. On success, LEDs will show `0x0001` (binary `0000000000000001`), indicating the bootloader is awaiting firmware upload over serial.
