#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Tachibana Shin
"""Send an HCI LE Connection Update command.

Usage:
  sudo ./le_update.py --handle 0x0020 --min 12 --max 12 --latency 0 --timeout 300

Intervals are in 1.25 ms units; the supervision timeout is in 10 ms units.
The handle is the HCI connection handle (not the Bluetooth address). Get it
from `sudo btmon -t` at the "LE Connection Complete" event if it changed.
"""

from __future__ import annotations

import argparse
import os
import socket
import struct
import sys

HCI_COMMAND_PKT = 0x01
HCI_EVENT_PKT = 0x04
HCI_OP_LE_CONN_UPDATE = 0x2013
LE_CONN_UPDATE_COMPLETE = 0x03

HCI_EVENT_LE_META = 0x3E


def parse_int(value: str) -> int:
    return int(value, 0)


def build_command(
    handle: int,
    min_interval: int,
    max_interval: int,
    latency: int,
    timeout: int,
) -> bytes:
    params = struct.pack(
        "<HHHHHHH",
        handle,
        min_interval,
        max_interval,
        latency,
        timeout,
        0,
        0,
    )
    return (
        struct.pack("<BHB", HCI_COMMAND_PKT, HCI_OP_LE_CONN_UPDATE, len(params))
        + params
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--hci", type=int, default=0, help="HCI device index, default 0 (hci0)")
    parser.add_argument("--handle", type=parse_int, required=True, help="connection handle (decimal or 0x...)")
    parser.add_argument("--min", dest="min_interval", type=int, default=12, help="min interval in 1.25 ms units")
    parser.add_argument("--max", dest="max_interval", type=int, default=12, help="max interval in 1.25 ms units")
    parser.add_argument("--latency", type=int, default=0, help="slave latency")
    parser.add_argument("--timeout", type=int, default=300, help="supervision timeout in 10 ms units")
    args = parser.parse_args()

    if os.geteuid() != 0:
        print("le_update.py: must be run as root", file=sys.stderr)
        return 2

    if not 0x0000 <= args.handle <= 0x0EFF:
        print("le_update.py: invalid connection handle", file=sys.stderr)
        return 2
    if not 0x0006 <= args.min_interval <= 0x0C80:
        print("le_update.py: min interval out of range 0x0006..0x0C80", file=sys.stderr)
        return 2
    if not 0x0006 <= args.max_interval <= 0x0C80:
        print("le_update.py: max interval out of range 0x0006..0x0C80", file=sys.stderr)
        return 2
    if args.min_interval > args.max_interval:
        print("le_update.py: min interval must be <= max interval", file=sys.stderr)
        return 2
    if not 0x0000 <= args.latency <= 0x01F3:
        print("le_update.py: latency out of range 0x0000..0x01F3", file=sys.stderr)
        return 2
    if not 0x000A <= args.timeout <= 0x0C80:
        print("le_update.py: timeout out of range 0x000A..0x0C80", file=sys.stderr)
        return 2

    packet = build_command(
        args.handle,
        args.min_interval,
        args.max_interval,
        args.latency,
        args.timeout,
    )

    sock = socket.socket(socket.AF_BLUETOOTH, socket.SOCK_RAW, socket.BTPROTO_HCI)
    try:
        sock.bind((args.hci,))
        sock.send(packet)
        print(
            f"sent hci{args.hci} handle={args.handle:#06x} "
            f"interval={args.min_interval}-{args.max_interval} "
            f"latency={args.latency} timeout={args.timeout}: {packet.hex()}"
        )

        sock.settimeout(5.0)
        while True:
            data = sock.recv(255)
            if not data:
                break
            print(f"evt {data.hex()}")
            if (
                len(data) >= 5
                and data[0] == HCI_EVENT_PKT
                and data[1] == HCI_EVENT_LE_META
                and data[3] == LE_CONN_UPDATE_COMPLETE
            ):
                status = data[4]
                print(f"LE Connection Update Complete: status=0x{status:02x}")
                return 0 if status == 0 else 1
    except socket.timeout:
        print(
            "le_update.py: no completion event observed; the command may still "
            "have been applied. Verify with `sudo btmon -t`.",
            file=sys.stderr,
        )
        return 0
    except OSError as exc:
        print(f"le_update.py: HCI error: {exc}", file=sys.stderr)
        return 1
    finally:
        sock.close()

    return 1


if __name__ == "__main__":
    raise SystemExit(main())
