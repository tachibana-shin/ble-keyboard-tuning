#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Tachibana Shin
#
# Update the keyboard bond's [ConnectionParameters] section. The default target
# is 12/12/0/300. The real bond file also contains a link key; this script never
# reads or prints it, and makes a timestamped backup first.

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)

if [[ -f "$REPO_DIR/config.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "$REPO_DIR/config.env"
    set +a
fi

if [[ ${EUID} -ne 0 ]]; then
    echo "set-bond-conn-params.sh: run with sudo" >&2
    exit 1
fi

: "${ADAPTER_MAC:?set ADAPTER_MAC in config.env or the environment}"
: "${KEYBOARD_MAC:?set KEYBOARD_MAC in config.env or the environment}"

ADAPTER_MAC="${ADAPTER_MAC^^}"
KEYBOARD_MAC="${KEYBOARD_MAC^^}"
INFO="/var/lib/bluetooth/${ADAPTER_MAC}/${KEYBOARD_MAC}/info"

if [[ ! -f "$INFO" ]]; then
    echo "set-bond-conn-params.sh: bond info not found: $INFO" >&2
    exit 1
fi

MIN="${MIN_INTERVAL:-12}"
MAX="${MAX_INTERVAL:-12}"
LATENCY="${LATENCY:-0}"
TIMEOUT="${SUPERVISION_TIMEOUT:-300}"
BACKUP="${INFO}.bak.$(date +%Y%m%d-%H%M%S)"

cp -a "$INFO" "$BACKUP"
python3 "$SCRIPT_DIR/set_bond_conn_params.py" "$INFO" "$MIN" "$MAX" "$LATENCY" "$TIMEOUT"

echo "backup: $BACKUP"
echo "restart Bluetooth or reconnect the keyboard to apply"
