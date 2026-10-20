# Optional kernel patch: reject non-zero LE latency

Status: patch prepared and `bluetooth.ko` built on 2026-10-20. **Not installed**
and not loaded. The running system still uses the stock CachyOS module.

## Problem

The keyboard asks for `12/12/9/300` (`min 12`, `max 12`, latency `9`,
supervision timeout `300`) when it goes idle. The kernel's L2CAP connection
parameter update handler validates that request, accepts it, and sends HCI LE
Connection Update. BlueZ can then persist the same values in the bond.

A runtime HCI update to `12/12/0/300` works, but the next idle request replaces
it. `MGMT_OP_LOAD_CONN_PARAM` was tested and did not stop the keyboard's
request. A userspace watchdog would have to poll or fight the keyboard
repeatedly; rejecting the request in the kernel is cheaper and does not wake
the keyboard.

## What the patch changes

The patch modifies `net/bluetooth/l2cap_core.c` in
`l2cap_conn_param_update_req()`. It adds an opt-in filter:

- `reject_le_latency=0` (default): unchanged kernel behavior.
- `reject_le_latency=1`: reject any L2CAP connection parameter update whose
  requested slave latency is non-zero (`L2CAP_CONN_PARAM_REJECTED`).
- `reject_le_latency_mac=`: optional MAC filter. An empty value applies the
  policy to all LE devices. A parseable MAC restricts it to that device.

For the keyboard:

- `12/12/0/300` has latency 0, so it is accepted normally.
- `12/12/9/300` has latency 9, so it is rejected.
- The current connection parameters stay at latency 0; no HCI update is sent,
  and there is no new value for BlueZ to persist.

The filter does not change the HCI connection itself, the HID driver, the bond
file, or the input-remapper mappings.

## Build

The build is module-only; it does not rebuild the kernel image. It requires the
running kernel's build tree, the matching Linux source, and the same toolchain
class used for the kernel (LLVM/Clang for CachyOS).

The installed `/usr/src/linux-cachyos` is a headers/build tree, not a full
source tree. The script downloads only `net/bluetooth` from the matching
upstream source and builds against the installed build tree.

```bash
./scripts/build-bluetooth-module.sh
```

The script:

1. Reads the kernel release and checks `CONFIG_BT=m`.
2. Downloads `net/bluetooth` from `linux-<base>.tar.xz` into
   `${WORKDIR:-/tmp/ble-keyboard-kernel}`.
3. Applies `kernel/0001-bluetooth-reject-le-latency.patch`.
4. Builds with `make ... LLVM=1 modules`.
5. Verifies the built module's `vermagic`; compares symbol CRCs when the
   kernel has `CONFIG_MODVERSIONS` enabled.
6. Prints the module path and the manual install steps; it does **not** install
   anything.

Manual equivalent:

```bash
make -C /lib/modules/"$(uname -r)"/build \
  M=/tmp/ble-keyboard-kernel/linux-7.2.9/net/bluetooth \
  LLVM=1 modules -j"$(nproc)"
```

Build result on the test machine:

- kernel: `7.2.9-2-cachyos`, `CONFIG_BT=m`, lockdown `none`
- module: `/tmp/bt-src/linux-7.2.9/net/bluetooth/bluetooth.ko`
- `vermagic`: `7.2.9-2-cachyos SMP preempt mod_unload`
- `depends`: `rfkill` (same as the stock module)
- symbol versions: `CONFIG_MODVERSIONS` is disabled in this kernel, so there
  is no `__versions` section to compare; CRC comparison is not applicable
- new parameters: `reject_le_latency`, `reject_le_latency_mac`
- compiler: Clang 23.1.3 (kernel was built with Clang 23.1.1; this is a local
  build, and the module was **not loaded** during the build-only step)

The kernel and the module have the same `vermagic`; a mismatch must be treated
as a failed build and the module must not be installed.

## Install (not performed)

Do this only after reviewing the build result and keeping the original module.

### 1. Back up the stock module

```bash
sudo mkdir -p /var/backups/ble-keyboard-tuning
sudo cp -a /lib/modules/"$(uname -r)"/kernel/net/bluetooth/bluetooth.ko.zst \
  /var/backups/ble-keyboard-tuning/bluetooth.ko.zst.stock
sudo sha256sum /var/backups/ble-keyboard-tuning/bluetooth.ko.zst.stock
```

### 2. Install the built module

```bash
sudo zstd -19 -T0 -f /tmp/bt-src/linux-7.2.9/net/bluetooth/bluetooth.ko \
  -o /tmp/bluetooth.ko.zst
sudo install -m 0644 /tmp/bluetooth.ko.zst \
  /lib/modules/"$(uname -r)"/kernel/net/bluetooth/bluetooth.ko.zst
sudo depmod -a
```

### 3. Enable the filter

```bash
sudo install -m 0644 configs/modprobe.d/ble-latency.conf \
  /etc/modprobe.d/ble-latency.conf
sudoedit /etc/modprobe.d/ble-latency.conf
```

Replace `10:11:89:XX:XX:XX` with the real keyboard MAC from local
`config.env`. Do not commit that file.

### 4. Reboot

A reboot is simpler and safer than unloading the whole Bluetooth stack while
the keyboard is connected. After reboot:

```bash
cat /sys/module/bluetooth/parameters/reject_le_latency
cat /sys/module/bluetooth/parameters/reject_le_latency_mac
modinfo bluetooth | grep -E '^(vermagic|parm):'
```

The values should be `Y` and the real keyboard MAC.

### 5. Verify with btmon

```bash
sudo btmon -t
```

Connect the keyboard, leave it idle, and watch for:

- the keyboard's L2CAP Connection Parameter Update Request for
  `12/12/9/300`;
- a `Connection Parameter Update Response` with result **Rejected**;
- `Connection latency: 0` remaining on the live connection;
- no rewrite of the bond to `Latency=9`.

Check the bond after idle:

```bash
sudo grep -A4 '^\[ConnectionParameters\]' \
  /var/lib/bluetooth/<ADAPTER_MAC>/<KEYBOARD_MAC>/info
```

Expected:

```ini
[ConnectionParameters]
MinInterval=12
MaxInterval=12
Latency=0
Timeout=300
```

## Rollback

```bash
sudo rm -f /etc/modprobe.d/ble-latency.conf
sudo install -m 0644 \
  /var/backups/ble-keyboard-tuning/bluetooth.ko.zst.stock \
  /lib/modules/"$(uname -r)"/kernel/net/bluetooth/bluetooth.ko.zst
sudo depmod -a
sudo reboot
```

The keyboard should return to the stock behavior: the OS-side latency-0 policy
can still be overridden when the keyboard requests 9.

## Risks and caveats

- **Unsigned module.** The stock module is signed; this build is not. The
  current kernel has `lockdown` set to `none` and does not set
  `CONFIG_MODULE_SIG_FORCE`, so an unsigned module can load with a kernel
  taint. Secure Boot, lockdown, or a future policy change can reject it. If
  that happens, restore the backup and do not force it.
- **Kernel updates replace the module.** After a kernel update, rebuild with
  `scripts/build-bluetooth-module.sh`; do not copy a module across releases.
  The script's `vermagic` check is mandatory; the symbol CRC check is applied
  only when `CONFIG_MODVERSIONS` is enabled.
- **Source mismatch.** The build uses upstream Linux 7.2.9 `net/bluetooth`,
  while CachyOS may carry Bluetooth patches. On this machine the built module
  matches the installed `vermagic` and depends only on `rfkill`, but
  `CONFIG_MODVERSIONS` is disabled, so no CRC check is available. Re-test after
  any CachyOS update. If the build or the Bluetooth stack fails, restore the
  stock module.
- **Global by default.** `reject_le_latency=1` with an empty
  `reject_le_latency_mac` affects every LE device handled by this adapter.
  Use the MAC filter unless the policy is intentional for all devices.
- **Only latency is filtered.** The patch does not reject other parameter
  changes, does not change the HCI connection, and does not fix the keyboard's
  firmware sleep/self-disconnect behavior. The LED/battery observations in
  [keyboard-notes.md](keyboard-notes.md) still apply.
- **The keyboard may retry.** Rejected requests can appear repeatedly in
  `btmon`; that is expected. The host stays at latency 0 unless another
  component changes it.
- **License.** The kernel patch is GPL-2.0-only (matching the Linux kernel);
  the rest of this repository is GPL-3.0-or-later. See [NOTICE](../NOTICE).

## Post-install checklist

- [ ] `uname -r` matches the module's `vermagic`.
- [ ] `reject_le_latency` is `Y` and the MAC filter contains the keyboard MAC.
- [ ] The keyboard still types and the input-remapper mappings work.
- [ ] The idle `12/12/9/300` request is rejected in `btmon`.
- [ ] Live connection latency stays 0 after idle.
- [ ] The bond still shows `Latency=0` after idle.
- [ ] A reboot restores Bluetooth and the keyboard without manual steps.
- [ ] The stock module backup exists and is readable.
