#!/usr/bin/env python3
"""
upload_program.py <BIN_FILE>

Scans serial ports, lets you pick one, uploads a binary via the bootloader
W command, verifies CRC32 via the 'C' command, sends 'D' to release the CPU,
then hands the terminal over as a raw pass-through.
"""

import sys
import os
import struct
import binascii
import select
import threading

try:
    import serial
    import serial.tools.list_ports
except ImportError:
    sys.exit("pyserial is required:  pip install pyserial")


BAUD = 115_200


# ---------------------------------------------------------------------------
# Port selection
# ---------------------------------------------------------------------------
def choose_port() -> str:
    ports = sorted(serial.tools.list_ports.comports(), key=lambda p: p.device)
    if not ports:
        sys.exit("No serial ports found.")

    print("\nAvailable serial ports:")
    for i, p in enumerate(ports):
        desc = p.description or ""
        print(f"  [{i}] {p.device}  {desc}")

    while True:
        try:
            choice = input(f"\nSelect port [0-{len(ports)-1}]: ").strip()
            idx = int(choice)
            if 0 <= idx < len(ports):
                return ports[idx].device
        except (ValueError, EOFError):
            pass
        print("Invalid selection, try again.")


# ---------------------------------------------------------------------------
# Upload
# ---------------------------------------------------------------------------
def upload(ser: serial.Serial, path: str) -> None:
    data = open(path, "rb").read()
    size = len(data)
    print(f"\nUploading '{os.path.basename(path)}' ({size} bytes) ...")

    # W  <size_hi>  <size_lo>  <bytes...>
    header = b"W" + struct.pack(">H", size)
    ser.write(header + data)
    ser.flush()
    print("Upload complete.")


# ---------------------------------------------------------------------------
# CRC32 verification
# ---------------------------------------------------------------------------
def verify_crc(ser: serial.Serial, data: bytes) -> None:
    expected = binascii.crc32(data) & 0xFFFF_FFFF

    ser.write(b"C")
    ser.flush()

    raw = ser.read(4)
    if len(raw) != 4:
        sys.exit(f"CRC32 check failed: expected 4 bytes, got {len(raw)}")

    got = int.from_bytes(raw, "little")
    if got != expected:
        sys.exit(f"CRC32 MISMATCH: expected 0x{expected:08X}, got 0x{got:08X}")
    print(f"CRC32 OK: 0x{expected:08X}")


# ---------------------------------------------------------------------------
# Raw terminal pass-through
# ---------------------------------------------------------------------------
def raw_terminal(ser: serial.Serial) -> None:
    """
    Bidirectional pass-through.  Ctrl-] exits (like telnet).
    Works on Windows (uses threads) and POSIX (uses select).
    """
    EXIT_KEY = b"\x1d"  # Ctrl-]
    print("\n--- Raw terminal  (Ctrl-] to exit) ---\n")

    stop = threading.Event()

    def reader():
        while not stop.is_set():
            try:
                chunk = ser.read(ser.in_waiting or 1)
                if chunk:
                    sys.stdout.buffer.write(chunk)
                    sys.stdout.buffer.flush()
            except serial.SerialException:
                break

    t = threading.Thread(target=reader, daemon=True)
    t.start()

    if os.name == "nt":
        _raw_terminal_windows(ser, stop, EXIT_KEY)
    else:
        _raw_terminal_posix(ser, stop, EXIT_KEY)

    stop.set()
    t.join(timeout=1)
    print("\n--- Session ended ---")


def _raw_terminal_windows(ser, stop, exit_key):
    import msvcrt
    while not stop.is_set():
        if msvcrt.kbhit():
            ch = msvcrt.getwch()
            if isinstance(ch, str):
                ch = ch.encode()
            if ch == exit_key:
                return
            ser.write(ch)


def _raw_terminal_posix(ser, stop, exit_key):
    import tty
    import termios
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    try:
        tty.setraw(fd)
        while not stop.is_set():
            r, _, _ = select.select([sys.stdin], [], [], 0.1)
            if r:
                ch = os.read(fd, 1)
                if ch == exit_key:
                    return
                ser.write(ch)
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    if len(sys.argv) != 2:
        sys.exit(f"Usage: {sys.argv[0]} <BIN_FILE>")

    bin_file = sys.argv[1]
    if not os.path.isfile(bin_file):
        sys.exit(f"File not found: {bin_file}")

    port = choose_port()
    print(f"\nOpening {port} at {BAUD} baud ...")

    with serial.Serial(port, BAUD, timeout=1) as ser:
        with open(bin_file, "rb") as f:
            data = f.read()

        print("Checking bootloader presence and empty CRC...")
        verify_crc(ser, b"")

        upload(ser, bin_file)
        verify_crc(ser, data)

        print("Sending 'D' to release CPU ...")
        ser.write(b"D")
        ser.flush()

        raw_terminal(ser)


if __name__ == "__main__":
    main()
