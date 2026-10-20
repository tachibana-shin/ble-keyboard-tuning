#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Tachibana Shin
#
# Install the system-side backup: BlueZ main.conf, AR3012 autosuspend rule and
# (optionally) the keyboard bond connection parameters. Requires root.
# Creates a timestamped backup before overwriting anything.

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
    echo "install-system.sh: run with sudo" >&2
    exit 1
fi

BACKUP_DIR="/var/backups/ble-keyboard-tuning/$(date +%Y%m%d-%H%M%S)"
install -d -m 0755 "$BACKUP_DIR"

for f in \
    /etc/bluetooth/main.conf \
    /etc/udev/rules.d/50-bt-ar3012-no-autosuspend.rules
do
    if [[ -f "$f" ]]; then
        cp -a "$f" "$BACKUP_DIR/$(basename "$f")"
    fi
done

install -m 0644 "$REPO_DIR/configs/bluetooth/main.conf" /etc/bluetooth/main.conf
install -m 0644 \
    "$REPO_DIR/configs/udev/50-bt-ar3012-no-autosuspend.rules" \
    /etc/udev/rules.d/50-bt-ar3012-no-autosuspend.rules

if [[ -n "${ADAPTER_MAC:-}" && -n "${KEYBOARD_MAC:-}" ]]; then
    ADAPTER_U="${ADAPTER_MAC^^}"
    KEYBOARD_U="${KEYBOARD_MAC^^}"
    if [[ -f "/var/lib/bluetooth/${ADAPTER_U}/${KEYBOARD_U}/info" ]]; then
        "$SCRIPT_DIR/set-bond-conn-params.sh"
    else
        echo "WARN: bond info not found for ${ADAPTER_U}/${KEYBOARD_U}; skipping bond params" >&2
    fi
else
    echo "WARN: ADAPTER_MAC/KEYBOARD_MAC not set; skipping bond params" >&2
fi

udevadm control --reload-rules
udevadm trigger --subsystem-match=usb --attr-match=idVendor=0cf3 --attr-match=idProduct=e003 || true
systemctl restart bluetooth

echo "Installed. Backup: $BACKUP_DIR"
echo "Reconnect the keyboard. Optional runtime update: sudo ./scripts/apply-active-le.sh"
