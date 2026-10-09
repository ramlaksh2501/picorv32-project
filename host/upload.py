#!/usr/bin/env python3
# ============================================================================
# upload.py -- All-in-One Firmware Uploader & Live Interactive Serial Monitor
#
# Usage:
#   py host\upload.py COM14 app\aes_test_app.bin
#
# Features:
#   1. Uploads the firmware to the resident bootloader over UART.
#   2. As soon as upload is confirmed, automatically opens the LIVE SERIAL MONITOR
#      directly in this terminal window -- no PuTTY or TeraTerm needed!
#   3. You can press '1' (Pass) or '2' (Tamper) right on your keyboard to trigger
#      tests interactively on the FPGA board!
#   4. Press Ctrl+C anytime to exit.
# ============================================================================

import sys
import os
import struct
import time
import threading
import serial

try:
    import msvcrt  # Windows non-blocking keyboard input
    HAS_MSVCRT = True
except ImportError:
    HAS_MSVCRT = False

def main():
    if len(sys.argv) < 2:
        print("Usage: py host\\upload.py <COM_PORT> [path_to_app.bin or app.hex]")
        sys.exit(1)

    port = sys.argv[1]
    input_file = sys.argv[2] if len(sys.argv) > 2 else "app/aes_test_app.bin"

    # Check if user asked directly for monitor mode
    if len(sys.argv) > 2 and sys.argv[2] in ["--monitor", "-m", "monitor"]:
        print(f"\n[INFO] Connecting directly to live serial monitor on {port}...")
        try:
            s = serial.Serial(port, 115200, timeout=1, rtscts=False, dsrdtr=False)
        except Exception as e:
            print(f"\n[ERROR] Could not open port '{port}': {e}")
            print("--> Make sure PuTTY, TeraTerm, or other serial monitors are CLOSED first!\n")
            sys.exit(1)
        # Jump directly to monitor
        start_monitor(s)
        return

    # Support both .bin and .hex files seamlessly
    try:
        bin_candidate = None
        if input_file.endswith(".hex"):
            # Check if there is an exact matching .bin file
            candidates = [
                input_file[:-4] + ".bin",
                os.path.join(os.path.dirname(input_file), "app", os.path.basename(input_file)[:-4] + ".bin"),
                os.path.join("app", os.path.basename(input_file)[:-4] + ".bin")
            ]
            for c in candidates:
                if os.path.exists(c):
                    bin_candidate = c
                    break

        if bin_candidate:
            print(f"[1/3] Found compiled binary: {bin_candidate}")
            with open(bin_candidate, "rb") as f:
                data = f.read()
        elif input_file.endswith(".hex"):
            print(f"[1/3] Parsing Verilog hex file: {input_file}")
            data = bytearray()
            with open(input_file, "r") as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith("//") or line.startswith("@"):
                        continue
                    word = int(line, 16)
                    data.extend(struct.pack("<I", word))
            while len(data) > 0 and data[-4:] == b"\x00\x00\x00\x00":
                data = data[:-4]
            data = bytes(data)
        else:
            print(f"[1/3] Reading binary file: {input_file}")
            with open(input_file, "rb") as f:
                data = f.read()
    except Exception as e:
        print(f"Error reading file '{input_file}': {e}")
        sys.exit(1)

    print(f"      Image payload size: {len(data)} bytes")

    try:
        s = serial.Serial(port, 115200, timeout=2, rtscts=False, dsrdtr=False)
    except Exception as e:
        print(f"\n[ERROR] Could not open port '{port}': {e}")
        print("--> Make sure PuTTY, TeraTerm, or other serial monitors are CLOSED first!\n")
        sys.exit(1)

    s.dtr = False
    s.rts = False
    time.sleep(0.05)
    s.reset_input_buffer()

    print("-------------------------------------------------------------------")
    print("  Ready to upload firmware to Spartan-7 FPGA:")
    print("  1. Press and hold pushbutton BTN0 (pin J2) on the FPGA board.")
    print("  2. Hit ENTER to begin transmission, then release BTN0.")
    print("-------------------------------------------------------------------")
    try:
        input("Press ENTER to upload > ")
    except Exception:
        pass

    header = struct.pack("<I", len(data))
    print("[2/3] Uploading firmware to FPGA...")
    s.reset_input_buffer()
    s.write(header)
    s.flush()
    s.write(data)
    s.flush()

    print("[3/3] Waiting for confirmation from bootloader...")
    ack = s.read(1)
    if ack != b"K":
        time.sleep(0.1)
        s.reset_input_buffer()
        print(f"\n[NOTE] Bootloader window elapsed (received: {ack!r}).")
        print(">> Falling back to live interactive monitor...\n")
        start_monitor(s)
        return

    print("\n===================================================================")
    print("  [SUCCESS] Firmware uploaded and running!")
    print("===================================================================\n")
    start_monitor(s)

def start_monitor(s):
    print("\n===================================================================")
    print("  LIVE SERIAL MONITOR STARTED (Direct terminal connection)")
    print("  Type '1' -> Run Authentic Exchange  (All 16 LEDs ON)")
    print("  Type '2' -> Run Tamper Attack Test  (LD12..LD15 Blink Alone)")
    print("  Press Ctrl+C to Exit")
    print("===================================================================\n", flush=True)

    stop_flag = False

    # Keyboard listening thread (Windows)
    def keyboard_listener():
        while not stop_flag:
            if HAS_MSVCRT and msvcrt.kbhit():
                try:
                    ch = msvcrt.getch()
                    s.write(ch)
                    s.flush()
                except Exception:
                    break
            time.sleep(0.02)

    kb_thread = threading.Thread(target=keyboard_listener, daemon=True)
    kb_thread.start()

    # Stream FPGA UART output live to the console
    try:
        while True:
            waiting = s.in_waiting
            if waiting:
                chunk = s.read(waiting)
                sys.stdout.write(chunk.decode("latin1", errors="replace"))
                sys.stdout.flush()
            else:
                time.sleep(0.01)
    except KeyboardInterrupt:
        print("\n\n[Serial Monitor Closed]")
    finally:
        stop_flag = True
        s.close()

if __name__ == "__main__":
    main()
