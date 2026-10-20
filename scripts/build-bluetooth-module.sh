#!/usr/bin/env bash
# Build an opt-in patched bluetooth.ko for the running kernel.
# This script does NOT install anything. Review docs/kernel-patch.md first.

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PATCH="${REPO_ROOT}/kernel/0001-bluetooth-reject-le-latency.patch"
WORKDIR="${WORKDIR:-/tmp/ble-keyboard-kernel}"
KERNEL_BUILD="${KERNEL_BUILD:-/lib/modules/$(uname -r)/build}"

if [[ ! -d "$KERNEL_BUILD" ]]; then
  echo "error: kernel build tree not found: $KERNEL_BUILD" >&2
  exit 1
fi

KERNEL_RELEASE="$(cat "$KERNEL_BUILD/include/config/kernel.release")"
KERNEL_BASE="${KERNEL_RELEASE%%-*}"
SRC_DIR="${WORKDIR}/linux-${KERNEL_BASE}"
BT_DIR="${SRC_DIR}/net/bluetooth"
MODULE="${BT_DIR}/bluetooth.ko"
KBUILD_CONFIG="${KERNEL_BUILD}/.config"

echo "kernel release: $KERNEL_RELEASE"
echo "kernel source:  $SRC_DIR"
echo "work dir:       $WORKDIR"

if ! grep -q '^CONFIG_BT=m$' "$KBUILD_CONFIG"; then
  echo "error: CONFIG_BT is not 'm'; this approach only replaces the bluetooth module." >&2
  exit 1
fi

# The module is unsigned. Check whether the kernel would reject it.
if [[ -r /sys/kernel/security/lockdown ]]; then
  lockdown="$(awk '{print $1}' /sys/kernel/security/lockdown | tr -d '[]')"
  if [[ "$lockdown" != "none" ]]; then
    echo "warning: kernel lockdown is '$lockdown'; an unsigned module may be rejected." >&2
  fi
fi
if grep -q '^CONFIG_MODULE_SIG_FORCE=y$' "$KBUILD_CONFIG"; then
  echo "warning: CONFIG_MODULE_SIG_FORCE=y; an unsigned module will be rejected." >&2
fi

for tool in clang ld.lld llvm-ar llvm-nm llvm-objcopy llvm-strip pahole; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "error: required tool not found: $tool" >&2
    exit 1
  fi
done

if [[ ! -d "$BT_DIR" ]]; then
  mkdir -p "$WORKDIR"
  echo "downloading Linux ${KERNEL_BASE} net/bluetooth sources..."
  curl -fL --retry 3 --connect-timeout 20 --max-time 600 \
    "https://cdn.kernel.org/pub/linux/kernel/v${KERNEL_BASE%%.*}.x/linux-${KERNEL_BASE}.tar.xz" \
    | tar -xJ -C "$WORKDIR" "linux-${KERNEL_BASE}/net/bluetooth"
fi

if ! grep -q 'reject_le_latency_for' "$BT_DIR/l2cap_core.c"; then
  echo "applying kernel patch..."
  patch -d "$SRC_DIR" -p1 < "$PATCH"
else
  echo "kernel patch already present; skipping"
fi

echo "building bluetooth.ko (LLVM=1)..."
make -C "$KERNEL_BUILD" M="$BT_DIR" LLVM=1 modules -j"$(nproc)"

if [[ ! -f "$MODULE" ]]; then
  echo "error: build did not produce $MODULE" >&2
  exit 1
fi

echo
echo "built module:"
modinfo "$MODULE" | grep -E '^(filename|version|vermagic|srcversion|depends|parm):'
sha256sum "$MODULE"

built_vermagic="$(modinfo -F vermagic "$MODULE")"
installed_module="$(modinfo -n bluetooth)"
installed_vermagic="$(modinfo -F vermagic "$installed_module")"
if [[ "$built_vermagic" != "$installed_vermagic" ]]; then
  echo "error: vermagic mismatch" >&2
  echo "  built:     $built_vermagic" >&2
  echo "  installed: $installed_vermagic" >&2
  exit 1
fi
echo "vermagic matches installed module: $built_vermagic"

# Compare symbol CRCs when the kernel uses CONFIG_MODVERSIONS. If versioning is
# disabled, neither the stock nor the built module has a __versions section;
# the vermagic and modpost checks still apply.
if grep -q '^CONFIG_MODVERSIONS=y$' "$KBUILD_CONFIG"; then
  modprobe --dump-modversions "$MODULE" > "${WORKDIR}/modversions.built"
  modprobe --dump-modversions "$installed_module" > "${WORKDIR}/modversions.installed"
  if ! diff -q "${WORKDIR}/modversions.installed" "${WORKDIR}/modversions.built" >/dev/null; then
    echo "error: module symbol versions differ from the installed module" >&2
    diff -u "${WORKDIR}/modversions.installed" "${WORKDIR}/modversions.built" >&2 || true
    exit 1
  fi
  echo "module symbol versions match installed module"
else
  echo "CONFIG_MODVERSIONS is disabled; symbol CRC comparison not applicable"
fi

cat <<EOF

Build complete. Nothing was installed.

Next steps (review docs/kernel-patch.md first):
  1. Back up $(modinfo -n bluetooth)
  2. Install and compress the module, then run depmod.
  3. Add configs/modprobe.d/ble-latency.conf to /etc/modprobe.d/
     with the real keyboard MAC.
  4. Reboot or reload the bluetooth stack, then verify the L2CAP response
     and connection latency with: sudo btmon -t

Keep a copy of the original module for rollback.
EOF
