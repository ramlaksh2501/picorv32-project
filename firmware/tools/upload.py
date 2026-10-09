#!/usr/bin/env python3
"""
Uploads a compiled PicoRV32 application (app.bin) to the resident
bootloader over a serial port -- the PicoRV32 equivalent of clicking
"Upload" in the Arduino IDE.

Usage:
  python upload.py COM15 ../binaries/app.bin
  python upload.py ../binaries/app.bin  (auto-detects COM port)
"""

import sys
import struct
import time
import os

try:
    import serial
    import serial.tools.list_ports
except ImportError:
    print("Error: pyserial is not installed. Run: pip install pyserial")
    sys.exit(1)

def find_default_port():
    ports = serial.tools.list_ports.comports()
    if not ports:
        return None
    # If COM15 is found, prefer it
    for p in ports:
        if p.device.upper() == "COM15":
            return p.device
    # Otherwise return first port
    return ports[0].device

def main():
    port = None
    bin_path = None

    if len(sys.argv) == 2:
        bin_path = sys.argv[1]
        port = find_default_port()
        if not port:
            print("Error: No COM port detected. Please specify COM port explicitly.")
            sys.exit(1)
        print(f"Auto-selected serial port: {port}")
    elif len(sys.argv) == 3:
        port = sys.argv[1]
        bin_path = sys.argv[2]
    else:
        print("Usage: python upload.py [COM_PORT] <path_to_app.bin>")
        sys.exit(1)

    if not os.path.isfile(bin_path):
        print(f"Error: Application binary not found: {bin_path}")
        sys.exit(1)

    with open(bin_path, "rb") as f:
        data = f.read()

    print(f"App image: {bin_path} ({len(data)} bytes)")
    print(f"Target port: {port} @ 115200 baud")

    try:
        s = serial.Serial(port, 115200, timeout=3, rtscts=False, dsrdtr=False)
    except Exception as e:
        print(f"Failed to open {port}: {e}")
        sys.exit(1)

    s.dtr = False
    s.rts = False
    time.sleep(0.2)  # settle time

    header = struct.pack("<I", len(data))
    print("Sending length header...")
    s.write(header)
    s.flush()

    print("Sending application bytes...")
    s.write(data)
    s.flush()

    print("Waiting for acknowledgement from bootloader...")
    ack = s.read(1)
    if ack == b"K":
        print("\n=======================================================")
        print("SUCCESS: Upload confirmed -- Application is now running!")
        print("=======================================================\n")
    else:
        print(f"\nNo/unexpected ack received: {ack!r}")
        print("Tip: If the board is running previous code, press btn_rst")
        print("on the FPGA board to return to the bootloader (LEDs = 0x0001)")
        print("and re-run this upload script.")

    s.close()

if __name__ == "__main__":
    main()
