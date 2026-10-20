# BLE Keyboard Tuning - Samsung-compatible BLE keyboard

Configuration and scripts used to reduce latency, disable USB autosuspend,
back up the `input-remapper` mappings, and optionally reject the keyboard's
idle latency request with a small kernel-module patch.

> This is a personal configuration backup, **not firmware**. The keyboard
> firmware is not modified. Read [Safety](#safety) before running scripts.

## License

**GNU General Public License v3.0 or later** (`GPL-3.0-or-later`).
See [LICENSE](LICENSE) and [NOTICE](NOTICE).

The optional kernel patch in [`kernel/`](kernel/) is GPL-2.0-only because it
modifies the Linux kernel; all other original content remains
GPL-3.0-or-later.

## Hardware / software

- Keyboard: BLE, Samsung PnP ID `0x04E8:0x7021`, in-tree HID driver `samsung`.
- Adapter: `hci0`, Qualcomm Atheros AR3012 `0cf3:e003` (USB).
- OS: CachyOS/Arch, BlueZ 5.87, kernel 7.2.9.
- The real MAC addresses are replaced with placeholders in this repo:
  - adapter: `B0:10:41:XX:XX:XX`
  - keyboard: `10:11:89:XX:XX:XX`

Put the real values in `config.env` (gitignored); never commit MAC addresses,
link keys, or `btmon` logs.

## Current state and target

| Item | Current | Target |
|---|---|---|
| `main.conf` LE min/max | `16/16` (20 ms) | keep |
| `main.conf` latency | `0` | keep |
| `main.conf` scan connect/auto | `16/16` (10 ms) | keep |
| `main.conf` supervision timeout | `100` (1 s) | keep |
| Bond `[ConnectionParameters]` | `12/12/0/300` | keep |
| Runtime HCI update | optional `12/12/0/300` | optional |
| Kernel L2CAP idle-latency rejection | not installed; module built | optional |
| USB autosuspend AR3012 | off via udev | keep |
| input-remapper | 19 mappings | keep |

The keyboard bond target was set back to **`Latency=0`**; the bond and the
optional runtime update use `12/12/0/300`. The keyboard may still ask for
`12/12/9/300` when idle, and BlueZ can accept that request for the live
connection. The bond value itself can also be rewritten by BlueZ after such a
request. The optional kernel patch can reject that request, but it is built
only and **not installed**; the live behavior is unchanged until it is
installed and tested. See [Known limitations](#known-limitations) and
[docs/kernel-patch.md](docs/kernel-patch.md).

## Repository contents

```text
.
|-- LICENSE
|-- NOTICE
|-- README.md
|-- config.env.example
|-- configs/
|   |-- bluetooth/
|   |   |-- main.conf
|   |   |-- bond-connection-parameters.current.conf
|   |   `-- bond-connection-parameters.target.conf
|   |-- udev/
|   |   `-- 50-bt-ar3012-no-autosuspend.rules
|   |-- input-remapper/
|   |   `-- Bluetooth Keyboard/
|   |       `-- general.json
|   `-- modprobe.d/
|       `-- ble-latency.conf
|-- kernel/
|   `-- 0001-bluetooth-reject-le-latency.patch
|-- docs/
|   |-- keyboard-notes.md
|   `-- kernel-patch.md
`-- scripts/
    |-- apply-active-le.sh
    |-- build-bluetooth-module.sh
    |-- install-system.sh
    |-- install-user.sh
    |-- le_update.py
    |-- set-bond-conn-params.sh
    `-- set_bond_conn_params.py
```

## Current configuration

### `/etc/bluetooth/main.conf`

Relevant values:

```ini
[General]
FastConnectable = true

[LE]
ScanWindowConnect = 16
ScanIntervalConnect = 16
ScanWindowAutoConnect = 16
ScanIntervalAutoConnect = 16
ConnectionSupervisionTimeout = 100
ConnectionLatency = 0
MaxConnectionInterval = 16
MinConnectionInterval = 16

[Policy]
AutoEnable = true
ReconnectIntervals = 1,2,4,8,16,32,64
ReconnectAttempts = 7
```

- `16` LE units = 10 ms for scan window/interval.
- `16` connection interval units = 20 ms.
- `ConnectionSupervisionTimeout = 100` = 1 s. This is the global fallback and
  is aggressive; the keyboard bond overrides it with `300` = 3 s.
- `FastConnectable = true` makes the adapter respond faster when reconnecting.

### Keyboard bond

Real file:

```text
/var/lib/bluetooth/<ADAPTER_MAC>/<KEYBOARD_MAC>/info
```

The real file also contains `[LinkKey] Key=...` - **never commit it**. This
repo only stores the `[ConnectionParameters]` section.

Current values:

```ini
[ConnectionParameters]
MinInterval=12
MaxInterval=12
Latency=0
Timeout=300
```

The same values are in `configs/bluetooth/bond-connection-parameters.current.conf`
and `configs/bluetooth/bond-connection-parameters.target.conf`.

### udev

`/etc/udev/rules.d/50-bt-ar3012-no-autosuspend.rules`:

```udev
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="0cf3", ATTR{idProduct}=="e003", ATTR{power/control}="on"
```

### input-remapper

The `Bluetooth Keyboard/general.json` preset has 19 mappings, all 1-to-1:

- `F1 <-> Search`, `F6 <-> Previous`, `F7 <-> Play`, `F8 <-> Next`
- `F9 <-> VolumeDown`, `F10 <-> VolumeUp`
- `F11 <-> BrightnessDown`, `F12 <-> BrightnessUp`
- `Homepage -> Esc`, `Power -> Delete`, `Delete -> Sleep`

The preset partly depends on key codes produced by the `samsung` driver
(Search/Homepage). Do not switch to `hid-generic` without re-testing the preset.

## Scripts

| Script | Run as | Purpose |
|---|---|---|
| `scripts/install-system.sh` | root | Back up then install `main.conf` and the udev rule; optionally set the bond target; reload udev; restart Bluetooth |
| `scripts/install-user.sh` | desktop user | Back up then install the input-remapper preset |
| `scripts/build-bluetooth-module.sh` | desktop user | Download source, apply the optional kernel patch, and build `bluetooth.ko`; does not install |
| `scripts/set-bond-conn-params.sh` | root | Update `[ConnectionParameters]` in the bond file; timestamped backup |
| `scripts/apply-active-le.sh` | root | Send an HCI LE Connection Update to the current connection |
| `scripts/le_update.py` | root | Low-level HCI helper used by `apply-active-le.sh` |

## Quick start

```bash
cp config.env.example config.env
$EDITOR config.env          # fill in the real MAC addresses

sudo ./scripts/install-system.sh
./scripts/install-user.sh

# Reconnect the keyboard, then optionally force the runtime parameters:
sudo HANDLE=0x0020 ./scripts/apply-active-le.sh

# Optional: build the patched bluetooth.ko; this does not install it:
./scripts/build-bluetooth-module.sh
```

`apply-active-le.sh` defaults to connection handle `0x0020` (32 decimal). If the
handle changed, read it from `sudo btmon -t` (`LE Connection Complete`) and run:

```bash
sudo HANDLE=0x0021 ./scripts/apply-active-le.sh
```

`hcitool` is not installed on this machine, so the script does not auto-detect
the handle. The raw HCI socket does not always receive the completion event;
`le_update.py` exits 0 with a warning after sending, and the command may still
have been applied. Verify the result with `sudo btmon -t`. If the handle is
stale, `btmon` shows the command error.

## Optional kernel module patch

The firmware's idle request `12/12/9/300` can be rejected in the kernel instead
of fighting it with a userspace watchdog. The patch is opt-in, defaults to off,
and can be restricted to the keyboard MAC.

- Patch: `kernel/0001-bluetooth-reject-le-latency.patch`
- Modprobe example: `configs/modprobe.d/ble-latency.conf`
- Build script: `scripts/build-bluetooth-module.sh`
- Full build/install/test/rollback: [docs/kernel-patch.md](docs/kernel-patch.md)

A module-only build was verified against kernel `7.2.9-2-cachyos`
(`CONFIG_BT=m`): matching `vermagic` and dependencies (this kernel has
`CONFIG_MODVERSIONS` disabled), with the new `reject_le_latency` and
`reject_le_latency_mac` parameters. It is **not installed**; the stock module is
still active. The live keyboard can therefore still request `12/12/9/300`
until the patched module is installed and tested.

## Known limitations

- The keyboard does not expose GATT battery, backlight, or DFU services. The OS
  cannot read the battery percentage or control the backlight.
- A slow 1/2 Hz LED blink is likely low battery (<10%) according to the Trio 500
  manual.
- The keyboard disconnects when idle; HCI logs show `Remote User Terminated`,
  not a host timeout. This is firmware behavior and cannot be fixed from the OS.
- `apply-active-le.sh` only applies runtime parameters to the current connection.
  If the keyboard requests `12/12/9/300` again when idle, BlueZ may accept it
  and rewrite the bond. The optional kernel patch can reject that request, but
  it is **not installed**; see [docs/kernel-patch.md](docs/kernel-patch.md).
- The kernel module is built locally and is unsigned. Secure Boot, kernel
  lockdown, `CONFIG_MODULE_SIG_FORCE`, or a kernel update can prevent it from
  loading. Keep the stock module backup and re-test after every kernel update.
- The patched policy is global unless `reject_le_latency_mac` is set. A MAC
  filter limits it to the keyboard; an empty filter applies it to every LE
  device on the adapter.
- `main.conf` is global and can affect other Bluetooth devices.

## Safety

- `install-system.sh` restarts Bluetooth and can temporarily disconnect the
  keyboard. It creates a backup in `/var/backups/ble-keyboard-tuning/`.
- Never commit `config.env`, the real bond file, link keys, MAC addresses, or
  `btmon` logs.
- The optional kernel patch replaces only the `bluetooth.ko` module, not the
  kernel image. Back up the stock module, keep the `modprobe.d` file removable,
  and test with `btmon`; see [docs/kernel-patch.md](docs/kernel-patch.md). An
  unsigned module can taint the kernel; do not load it under lockdown/Secure
  Boot unless it is signed.
- No firmware is modified. Changes are limited to BlueZ, udev, HID, the
  optional Bluetooth kernel module, and input-remapper.
- No warranty; see GPLv3.

## Technical notes

See [docs/keyboard-notes.md](docs/keyboard-notes.md) for the GATT/HID report
map, `samsung` driver, Device Info, and the battery/backlight/sleep limitations.

See [docs/kernel-patch.md](docs/kernel-patch.md) for the optional module-only
patch, build checks, installation, and rollback.
