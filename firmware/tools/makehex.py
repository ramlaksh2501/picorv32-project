#!/usr/bin/env python3
import sys

def main():
    if len(sys.argv) < 3:
        print("Usage: makehex.py <input.bin> <output.hex> [word_count]")
        sys.exit(1)

    bin_path = sys.argv[1]
    hex_path = sys.argv[2]
    words = int(sys.argv[3]) if len(sys.argv) > 3 else None

    with open(bin_path, "rb") as f:
        data = f.read()

    if words is None:
        words = (len(data) + 3) // 4

    lines = []
    for i in range(words):
        off = i * 4
        chunk = data[off:off + 4] if off < len(data) else b""
        chunk = chunk + b"\x00" * (4 - len(chunk))
        val = chunk[0] | (chunk[1] << 8) | (chunk[2] << 16) | (chunk[3] << 24)
        lines.append("%08x\n" % val)

    with open(hex_path, "w") as f:
        f.writelines(lines)

if __name__ == "__main__":
    main()
