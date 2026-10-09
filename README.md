# Secure Military Field Node SoC: Hardware-Accelerated Authenticated Cryptography on RISC-V FPGA

[![Target FPGA](https://img.shields.io/badge/Target-Real%20Digital%20Boolean%20(XC7S50)-blue.svg)](#hardware-architecture)
[![CPU Core](https://img.shields.io/badge/CPU-PicoRV32%20(RV32I)-orange.svg)](#system-architecture)
[![Crypto Accelerator](https://img.shields.io/badge/Accelerator-AES--128%20%2F%20AES--CMAC-green.svg)](#hardware-vs-software-performance)
[![Frequency](https://img.shields.io/badge/Clock-50%20MHz-brightgreen.svg)](#timing-closure--power)
[![Timing Slack](https://img.shields.io/badge/WNS-%2B1.415%20ns%20(0%20Violations)-success.svg)](#timing-closure--power)

An autonomous, secure edge controller SoC designed for energy-constrained military tactical field nodes. Built on a **Xilinx Spartan-7 FPGA**, the SoC integrates a 32-bit **PicoRV32 RISC-V** processor core with a dedicated **Hardware AES-128 & AES-CMAC Cryptographic Coprocessor** to achieve low-latency message authentication and tamper detection.

---

## 1. System Architecture

```text
┌────────────────────────────────────────────────────────────────────────┐
│                        SPARTAN-7 FPGA SoC (50 MHz)                     │
│                                                                        │
│   ┌────────────────────┐            Memory-Mapped I/O Bus (MMIO)       │
│   │   PicoRV32 CPU     │◄─────────────────┬───────────────────┐        │
│   │ (32-bit RISC-V)    │                  │                   │        │
│   │   [1,112 LUTs]     │                  ▼                   ▼        │
│   └─────────┬──────────┘          ┌───────────────┐   ┌──────────────┐ │
│             │                     │ UART & GPIO   │   │  On-Chip RAM │ │
│             ▼                     │ (LEDs / COM)  │   │   (BRAM)     │ │
│   ┌───────────────────────────┐   └───────────────┘   └──────────────┘ │
│   │ Dedicated AES Accelerator │                                        │
│   │  & CMAC Coprocessor       │ ◄── Key: 128-bit Pre-Shared Key (PSK)  │
│   │       [3,706 LUTs]        │     (Isolated in Hardware Registers)   │
│   └───────────────────────────┘                                        │
└────────────────────────────────────────────────────────────────────────┘
```

### Memory Map (MMIO Base: `0x4000_0000`)

| Address Range | Region / Register | Description |
| :--- | :--- | :--- |
| `0x0000_0000 - 0x0000_07FF` | **Boot ROM** | 2 KB resident UART bootloader (allows in-system reflash) |
| `0x1000_0000 - 0x1000_1FFF` | **App RAM** | 8 KB Block RAM preloaded with authenticated firmware |
| `0x2000_0000` | **UART DATA** | TX/RX serial character buffer @ 115200 baud |
| `0x2000_0004` | **UART STATUS** | Bit 0: `TX_BUSY`, Bit 1: `RX_VALID` |
| `0x3000_0000` | **LED Register** | 16-bit physical board actuation (`LD0..LD15`) |
| `0x4000_0000` | **AES CONTROL** | Trigger bits: Encrypt, Decrypt, Key Init, CMAC Gen, CMAC Verify |
| `0x4000_0004` | **AES STATUS** | Flags: `key_ready`, `cipher_ready`, `busy`, `cmac_done`, `cmac_valid`, `tamper_detected` |
| `0x4000_0010 - 0x4000_001C` | **DATA 0..3** | 128-bit plaintext / ciphertext / message buffer |
| `0x4000_0020 - 0x4000_002C` | **KEY 0..3** | 128-bit isolated cipher key registers |
| `0x4000_0030 - 0x4000_003C` | **RESULT 0..3** | 128-bit direct AES encryption/decryption output |
| `0x4000_0040 - 0x4000_004C` | **CMAC TAG 0..3** | Calculated 128-bit NIST SP 800-38B CMAC tag |
| `0x4000_0050 - 0x4000_005C` | **CMAC EXP 0..3** | Expected 128-bit tag loaded for hardware tamper verification |

---

## 2. Hardware vs. Software Performance

Direct benchmark comparing pure software AES executed on the 32-bit PicoRV32 (RV32I) core against the dedicated FPGA hardware coprocessor @ 50 MHz:

| Operation | Software AES (PicoRV32 CPU) | Hardware Coprocessor (FPGA) | Speedup Advantage |
| :--- | :---: | :---: | :---: |
| **Key Expansion** | 820 cycles (16.4 $\mu$s) | **10 cycles (0.20 $\mu$s)** | **82.0×** |
| **128-bit Encryption** | 2,712 cycles (54.2 $\mu$s) | **11 cycles (0.22 $\mu$s)** | **246.5×** |
| **128-bit Decryption** | 2,940 cycles (58.8 $\mu$s) | **11 cycles (0.22 $\mu$s)** | **267.3×** |
| **CMAC Tamper Verify** | 3,450 cycles (69.0 $\mu$s) | **14 cycles (0.28 $\mu$s)** | **246.4×** |
| **CPU Core Load** | **100% Core Lock** | **0% Core Load** | **Autonomous Offload** |
| **Max Throughput** | ~2.36 Mbps | **~581.8 Mbps** | **>240× Faster** |

---

## 3. Vivado Physical Implementation Metrics

Synthesized and fully implemented on the **Xilinx Spartan-7 XC7S50CSGA324-1** using Vivado:

* **Timing Closure:** **WNS = +1.415 ns**, **WHS = +0.019 ns**, **0 Failing Endpoints** out of 22,487 critical paths.
* **FPGA Logic Footprint:**
  * Slice LUTs: **6,125 / 32,600 (18.79%)**
  * Slice Registers: **3,875 / 65,200 (5.94%)**
  * Distributed RAM: **1,324 / 9,600 (13.79%)**
  * *Over 80% of chip area remains free for future edge expansions.*
* **Hierarchical Logic Allocation:**
  * Dedicated AES/CMAC Engine (`aes_inst`): **3,706 LUTs** (Hardware coprocessor)
  * PicoRV32 CPU (`cpu`): **1,112 LUTs** (Minimalist microcontroller core)
* **Total On-Chip Power:** **144 mW (0.144 W)** total power (72 mW dynamic, 72 mW static) — compliant with low-SWaP (Size, Weight, and Power) field requirements.

---

## 4. Repository Layout

```text
picorv32-project/
├── hardware/
│   ├── src/                  # All 12 Synthesizable Verilog RTL Modules
│   │   ├── top.v             # Top-level SoC interconnect & bus address decoder
│   │   ├── picorv32.v        # 32-bit RISC-V RV32I Processor Core
│   │   ├── aes_peripheral.v  # Memory-mapped security controller
│   │   ├── cmac_controller.v # Hardware AES-CMAC authenticator FSM
│   │   ├── aes128_wrapper.v  # AES-128 core wrapper bridge
│   │   ├── aes128.v          # 10-round AES execution engine
│   │   ├── key_schedule.v    # Round key generation unit
│   │   ├── round.v           # SubBytes, ShiftRows, MixColumns, AddRoundKey
│   │   ├── sub_bytes_lut.v   # S-Box & Inv S-Box lookup tables
│   │   ├── mix_col_lut.v     # GF(2^8) multiplier LUT for encryption
│   │   ├── inv_mix_col_lut.v # GF(2^8) multiplier LUT for decryption
│   │   └── rcon_lut.v        # Round constants LUT
│   ├── tb/                   # Verification Testbenches
│   │   ├── aes_peripheral_tb.v # Full peripheral register & command TB
│   │   ├── cmac_tb.v         # NIST SP 800-38B verification TB
│   │   ├── phase5_perf_tb.v  # Cycle-accurate latency measurement TB
│   │   └── soc_aes_tb.v      # Complete SoC simulation TB
│   ├── constraints/          # Pin assignments & clock definitions
│   │   └── boolean_bootloader.xdc
│   ├── hex/                  # Memory initialization hex files
│   │   ├── bootloader.hex    # Resident bootloader ROM image
│   │   └── aes_test_app.hex  # Authenticated application image
│   └── scripts/              # Vivado automation scripts
│       ├── build.tcl         # One-click project generation & bitstream build
│       └── program_fpga.tcl  # JTAG hardware programmer script
│
├── host/                     # Python Host Controller & Verification Tools
│   ├── monitor.py            # Live serial terminal interface
│   ├── upload.py             # Dual-mode UART firmware uploader & monitor
│   ├── benchmark_proof.py    # Hardware vs. Software performance verification
│   └── session_key_test.py   # NIST SP 800-108 Session Key generation test suite
│
├── firmware/                 # C Firmware Source & Drivers
│   ├── src/                  # Bare-metal C routines
│   ├── include/              # API headers
│   └── memory_map/           # Hardware register offsets
│
└── binaries/                 # Precompiled application binaries
    └── aes_test_app.bin      # Production firmware binary for UART flashing
```

---

## 5. Quick Start & Execution

### 1. Build and Flash Bitstream
Open Vivado Tcl Console in the repository root:
```tcl
source hardware/scripts/build.tcl
source hardware/scripts/program_fpga.tcl
```

### 2. Run Live Hardware Demonstration
Connect your Real Digital Boolean FPGA board over USB:
```powershell
python host/monitor.py
```
* **Press `1`:** Sends authentic encrypted command $\rightarrow$ CMAC verified in 14 cycles $\rightarrow$ Decrypted in 11 cycles $\rightarrow$ **All 16 LEDs turn ON (`0xFFFF`)**.
* **Press `2`:** Injects transmission tamper attack $\rightarrow$ CMAC mismatch detected $\rightarrow$ Payload rejected $\rightarrow$ **Alarm LEDs blink (`LD12..LD15`)**.

### 3. Run Benchmark Verification
```powershell
python host/benchmark_proof.py
python host/session_key_test.py
```
