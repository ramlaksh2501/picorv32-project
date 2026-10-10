#!/usr/bin/env python3
# ============================================================================
# flash_app.py -- One-step Firmware Flasher & Live Interactive Terminal
# ============================================================================

import sys
import os
import time
import struct
import serial
import threading

try:
    import msvcrt
    HAS_MSVCRT = True
except ImportError:
    HAS_MSVCRT = False

def main():
    port = sys.argv[1] if len(sys.argv) > 1 else "COM18"
    bin_file = sys.argv[2] if len(sys.argv) > 2 else "binaries/app.bin"

    if not os.path.exists(bin_file):
        print(f"Error: Binary not found at {bin_file}")
        sys.exit(1)

    with open(bin_file, "rb") as f:
        data = f.read()

    print("=" * 68)
    print("   SPARTAN-7 FPGA ONE-CLICK FIRMWARE FLASHER & LIVE MONITOR")
    print("=" * 68)
    print(f"  Target Port : {port} @ 115200 baud")
    print(f"  Firmware    : {bin_file} ({len(data)} bytes)")
    print("-------------------------------------------------------------------")
    print("  INSTRUCTIONS:")
    print("  1. Press and HOLD the 'BTN0' button on the FPGA board.")
    print("  2. Hit ENTER in this window, then immediately RELEASE BTN0.")
    print("-------------------------------------------------------------------")
    input("Ready? Hold BTN0 and hit ENTER > ")

    try:
        s = serial.Serial(port, 115200, timeout=3, rtscts=False, dsrdtr=False)
    except Exception as e:
        print(f"\n[ERROR] Could not open port '{port}': {e}")
        print("--> Make sure any other serial monitors or PuTTY windows are CLOSED!\n")
        sys.exit(1)

    s.dtr = False
    s.rts = False
    time.sleep(0.05)
    s.reset_input_buffer()

    print("\n[1/2] Streaming updated firmware image into App RAM...")
    header = struct.pack("<I", len(data))
    s.write(header)
    s.flush()
    s.write(data)
    s.flush()

    print("[2/2] Awaiting acknowledgment from Boot ROM...")
    ack = s.read(1)
    if ack == b"K":
        print("\n=======================================================")
        print("  SUCCESS: Firmware Uploaded! Board is now running.")
        print("  Opening Live Interactive Monitor directly below:")
        print("=======================================================\n")
        
        stop_flag = False
        def kb_listener():
            while not stop_flag:
                if HAS_MSVCRT and msvcrt.kbhit():
                    try:
                        c = msvcrt.getch()
                        s.write(c)
                        s.flush()
                    except Exception:
                        break
                time.sleep(0.01)

        kb_t = threading.Thread(target=kb_listener, daemon=True)
        kb_t.start()

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
            print("\n[Session Closed]")
        finally:
            stop_flag = True
            s.close()
    else:
        print(f"\n[ERROR] Bootloader did not respond (received {ack!r}).")
        print("Tip: Make sure to hold BTN0 when hitting Enter, then release BTN0.")
        s.close()

if __name__ == "__main__":
    main()
