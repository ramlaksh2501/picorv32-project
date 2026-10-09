#!/usr/bin/env python3
# ============================================================================
# monitor.py -- Direct Live Serial Monitor for PicoRV32 Military Field Node
#
# Usage:
#   py host\monitor.py COM18
# ============================================================================

import sys
import time
import threading
import serial

try:
    import msvcrt
    HAS_MSVCRT = True
except ImportError:
    HAS_MSVCRT = False

def main():
    if len(sys.argv) < 2:
        print("Usage: py host\\monitor.py <COM_PORT>")
        sys.exit(1)

    port = sys.argv[1]
    print(f"\n[INFO] Opening live serial monitor on {port} (115200 baud)...")
    try:
        s = serial.Serial(port, 115200, timeout=0.1, rtscts=False, dsrdtr=False)
    except Exception as e:
        print(f"\n[ERROR] Could not open port '{port}': {e}")
        print("--> Make sure other terminal windows using this port are closed first!\n")
        sys.exit(1)

    s.dtr = False
    s.rts = False
    time.sleep(0.1)
    s.reset_input_buffer()

    print("===================================================================")
    print("  LIVE SERIAL MONITOR ACTIVE (Streaming directly from Spartan-7 FPGA)")
    print("  Press '1' to re-run Authentic Exchange | '2' to re-run Tamper Attack")
    print("  Press Ctrl+C anytime to Exit")
    print("===================================================================\n", flush=True)

    stop_flag = False

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
