#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Tachibana Shin
"""Update only [ConnectionParameters] in a BlueZ bond info file.

The real bond file contains [LinkKey] Key=...; this script never prints or
modifies other sections. Run it through set-bond-conn-params.sh, which makes a
backup first.
"""

from __future__ import annotations

import os
import sys
import tempfile
from pathlib import Path

FIELD_NAMES = {
    "mininterval": "MinInterval",
    "maxinterval": "MaxInterval",
    "latency": "Latency",
    "timeout": "Timeout",
}


def update(path: str, values: dict[str, str]) -> None:
    p = Path(path)
    lines = p.read_text().splitlines()

    out: list[str] = []
    in_section = False
    found = False
    seen: set[str] = set()

    def add_missing() -> None:
        for key, val in values.items():
            if key.lower() not in seen:
                out.append(f"{key}={val}")
                seen.add(key.lower())

    for line in lines:
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            if in_section:
                add_missing()
            in_section = stripped.lower() == "[connectionparameters]"
            if in_section:
                found = True
            out.append(line)
            continue

        if in_section and "=" in stripped:
            key = stripped.split("=", 1)[0].strip().lower()
            if key in FIELD_NAMES:
                canonical = FIELD_NAMES[key]
                out.append(f"{canonical}={values[canonical]}")
                seen.add(key)
                continue

        out.append(line)

    if in_section:
        add_missing()

    if not found:
        if out and out[-1].strip():
            out.append("")
        out.append("[ConnectionParameters]")
        for key, val in values.items():
            out.append(f"{key}={val}")

    new_text = "\n".join(out) + "\n"
    st = p.stat()
    fd, tmp_name = tempfile.mkstemp(prefix=".info.", dir=str(p.parent))
    try:
        with os.fdopen(fd, "w") as f:
            f.write(new_text)
        os.chmod(tmp_name, st.st_mode)
        try:
            os.chown(tmp_name, st.st_uid, st.st_gid)
        except PermissionError:
            pass
        os.replace(tmp_name, p)
    finally:
        if os.path.exists(tmp_name):
            os.unlink(tmp_name)


def main() -> int:
    if len(sys.argv) != 6:
        print(
            "usage: set_bond_conn_params.py <info> <min> <max> <latency> <timeout>",
            file=sys.stderr,
        )
        return 2

    path, minv, maxv, lat, timeout = sys.argv[1:]
    values = {
        "MinInterval": str(int(minv, 0)),
        "MaxInterval": str(int(maxv, 0)),
        "Latency": str(int(lat, 0)),
        "Timeout": str(int(timeout, 0)),
    }
    update(path, values)
    print(f"updated {path}: [ConnectionParameters] {values}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
