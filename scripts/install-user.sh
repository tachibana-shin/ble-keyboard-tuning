#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Tachibana Shin
#
# Install the input-remapper preset for the Bluetooth Keyboard. Run as the
# desktop user, not root. Makes a timestamped backup of the existing preset.

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)

if [[ ${EUID} -eq 0 ]]; then
    echo "install-user.sh: run as your desktop user, not root" >&2
    exit 1
fi

PRESET_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/input-remapper-2/presets/Bluetooth Keyboard"
install -d -m 0755 "$PRESET_DIR"

if [[ -f "$PRESET_DIR/general.json" ]]; then
    cp -a "$PRESET_DIR/general.json" \
        "$PRESET_DIR/general.json.bak.$(date +%Y%m%d-%H%M%S)"
fi

install -m 0644 \
    "$REPO_DIR/configs/input-remapper/Bluetooth Keyboard/general.json" \
    "$PRESET_DIR/general.json"

echo "Installed preset: $PRESET_DIR/general.json"
echo "Restart input-remapper from its GUI or: systemctl --user restart input-remapper-daemon"
