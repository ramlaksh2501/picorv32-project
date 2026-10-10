#!/usr/bin/env python3
# ============================================================================
# run_dynamic_tb.py
#
# Interactive CLI Runner for Dynamic Runtime Data & CSPRNG Key Hardware Testbench
# Compiles and executes dynamic_csprng_tb.v using Icarus Verilog (iverilog/vvp).
#
# Usage:
#   python hardware/tb/run_dynamic_tb.py
#   python hardware/tb/run_dynamic_tb.py --text "MY_SECRET_MSG!!"
#   python hardware/tb/run_dynamic_tb.py --hex 434d445f524541445f53454e534f5253
# ============================================================================

import sys
import os
import secrets
import subprocess
import argparse

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
SRC_DIR = os.path.join(PROJECT_DIR, "hardware", "src")
TB_FILE = os.path.join(SCRIPT_DIR, "dynamic_csprng_tb.v")
OUT_VVP = os.path.join(SCRIPT_DIR, "dynamic_sim.vvp")

VERILOG_SRCS = [
    os.path.join(SRC_DIR, "sub_bytes_lut.v"),
    os.path.join(SRC_DIR, "mix_col_lut.v"),
    os.path.join(SRC_DIR, "inv_mix_col_lut.v"),
    os.path.join(SRC_DIR, "rcon_lut.v"),
    os.path.join(SRC_DIR, "round.v"),
    os.path.join(SRC_DIR, "key_schedule.v"),
    os.path.join(SRC_DIR, "aes128.v"),
    os.path.join(SRC_DIR, "aes128_wrapper.v"),
    os.path.join(SRC_DIR, "cmac_controller.v"),
    os.path.join(SRC_DIR, "aes_peripheral.v"),
    TB_FILE
]

def find_tool(name):
    # Check default path and C:\Users\akash\iverilog\bin
    custom_bin = os.path.join(r"C:\Users\akash\iverilog\bin", f"{name}.exe")
    if os.path.exists(custom_bin):
        return custom_bin
    return name

def compile_testbench():
    iverilog = find_tool("iverilog")
    cmd = [iverilog, "-o", OUT_VVP, f"-I{SRC_DIR}"] + VERILOG_SRCS
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if res.returncode != 0:
        print("[ERROR] iverilog compilation failed:\n", res.stderr)
        sys.exit(1)

def text_to_hex128(text: str) -> str:
    b = text.encode("utf-8")
    if len(b) > 16:
        b = b[:16]
    else:
        b = b.ljust(16, b"\x00")
    return b.hex()

def main():
    parser = argparse.ArgumentParser(description="Dynamic CSPRNG Key & Runtime Data Testbench Runner")
    parser.add_argument("--text", type=str, help="16-character ASCII text string for runtime payload")
    parser.add_argument("--hex", type=str, help="32-character hex string for runtime payload")
    parser.add_argument("--key", type=str, help="Optional 32-character hex key (if omitted, CSPRNG generates one)")
    parser.add_argument("--auto", action="store_true", help="Run automated 3-round stimulus loop")
    args = parser.parse_args()

    print("=" * 79)
    print("   PicoRV32 SoC: DYNAMIC RUNTIME DATA & CSPRNG KEY SIMULATION DRIVER")
    print("=" * 79)

    print("\n[STEP 1/3] Compiling hardware RTL and testbench with Icarus Verilog...")
    compile_testbench()
    print("  >> Compilation successful: output generated to dynamic_sim.vvp")

    # Determine Key
    if args.key:
        csprng_key_hex = args.key
        print(f"\n[STEP 2/3] Using Specified Key : 0x{csprng_key_hex}")
    else:
        # Generate true CSPRNG 128-bit key using Python's OS-entropy secrets module
        csprng_key_bytes = secrets.token_bytes(16)
        csprng_key_hex = csprng_key_bytes.hex()
        print(f"\n[STEP 2/3] Generated Dynamic CSPRNG Key (128-bit):")
        print(f"  Key (Hex): 0x{csprng_key_hex}")

    # Determine Payload Data
    if args.hex:
        data_hex = args.hex
        print(f"  Payload Data (Hex) : 0x{data_hex}")
    elif args.text:
        data_hex = text_to_hex128(args.text)
        print(f"  Payload Text : '{args.text}' -> Hex: 0x{data_hex}")
    elif args.auto:
        data_hex = None
        print("  Payload Mode: Multi-round autonomous random stream")
    else:
        # Prompt interactively if run without flags
        print("\n  Enter runtime payload (or press ENTER to use random payload):")
        user_in = input("  Text Payload (<=16 chars) > ").strip()
        if user_in:
            data_hex = text_to_hex128(user_in)
            print(f"  Using Text: '{user_in}' (0x{data_hex})")
        else:
            data_hex = secrets.token_bytes(16).hex()
            print(f"  Generated CSPRNG Payload: 0x{data_hex}")

    print("\n[STEP 3/3] Launching cycle-accurate hardware simulation...")
    vvp = find_tool("vvp")
    cmd = [vvp, OUT_VVP]
    if data_hex and not args.auto:
        cmd.append(f"+KEY={csprng_key_hex}")
        cmd.append(f"+DATA={data_hex}")

    subprocess.run(cmd)

if __name__ == "__main__":
    main()
