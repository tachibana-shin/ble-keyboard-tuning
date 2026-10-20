#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Tachibana Shin
#
# Send a runtime HCI LE Connection Update for the connected keyboard.
# Requires root. The handle is dynamic; default 0x0020 matches the current
# setup, override HANDLE=... if it changed (see `sudo btmon -t`).

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
    echo "apply-active-le.sh: run with sudo" >&2
    exit 1
fi

HCI_INDEX="${HCI_INDEX:-0}"
HANDLE="${HANDLE:-0x0020}"
KEYBOARD_MAC="${KEYBOARD_MAC:-}"

if [[ -n "$KEYBOARD_MAC" ]] && command -v btmgmt >/dev/null 2>&1; then
    if ! btmgmt -i "hci${HCI_INDEX}" con 2>/dev/null | grep -qi -- "$KEYBOARD_MAC"; then
        echo "apply-active-le.sh: keyboard ${KEYBOARD_MAC} is not connected on hci${HCI_INDEX}" >&2
        exit 1
    fi
fi

echo "Using HCI_INDEX=${HCI_INDEX} HANDLE=${HANDLE}; override HANDLE=... if needed"
exec python3 "$SCRIPT_DIR/le_update.py" \
    --hci "$HCI_INDEX" \
    --handle "$HANDLE" \
    --min "${MIN_INTERVAL:-12}" \
    --max "${MAX_INTERVAL:-12}" \
    --latency "${LATENCY:-0}" \
    --timeout "${SUPERVISION_TIMEOUT:-300}"
