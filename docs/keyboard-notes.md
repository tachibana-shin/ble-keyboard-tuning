# Keyboard notes - GATT/HID, driver, battery/backlight/sleep

These notes were collected from the Samsung-compatible BLE keyboard
(PnP `0x04E8:0x7021`) through BlueZ/GATT, the kernel HID descriptor, and the
`hid-samsung` source. MAC addresses are omitted.

## GATT

| Service | UUID | Components |
|---|---|---|
| GAP | `0x1800` | Device Name, Appearance, Preferred Connection Parameters (`0x2A04`) |
| GATT | `0x1801` | Service Changed, Client Supported Features, Database Hash |
| Device Info | `0x180A` | Manufacturer, Serial, Hardware, Firmware, PnP ID |
| HID | `0x1812` | HID Info, HID Control Point, Report Map, 4 Report characteristics |

- No Battery service (`0x180F`) and no Battery Level (`0x2A19`).
- No vendor `0xFFxx`/`0xFDxx` service and no DFU/OTA service.
- Reports:
  - input report ID 1 - keyboard
  - output report ID 1 - LEDs
  - input report ID 2 - consumer control
  - input report ID 3 - system control
- Report Reference values: `01 01`, `01 02`, `02 01`, `03 01`.
- The `0x2A4B` Report Map is 177 bytes and matches the kernel descriptor.

## HID report map

| Report | Type | Size | Contents |
|---|---|---|---|
| 1 | Input | 8 bytes | 8 modifier bits + 1 reserved byte + 6 keycodes -> 6KRO |
| 1 | Output | 1 byte | Num/Caps/Scroll/Compose/Kana + 3 padding bits |
| 2 | Input | 3 bytes | 24 consumer usages (media, brightness, mail, web, search, ...) |
| 3 | Input | 1 byte | Power/Sleep/Wake + padding |

There is no feature report, no battery usage page `0x06`, no vendor usage page
`0xFFxx`, and no backlight report. The output report only controls the five
standard LED bits, not a backlight.

## Device Info

| Field | Value |
|---|---|
| Manufacturer | `BLE5x` |
| Serial | `11.0.2-LE` |
| Hardware | `1.0.0` |
| Firmware | `11.0.2` |
| PnP ID | source `0x02` (USB-IF), vendor `0x04E8` Samsung, product `0x7021`, version `0x0300` |
| HID Info | HID 1.11, country 0, flags `0x03` (remote wake + normally connectable) |

`BLE5x` plus firmware `11.0.2` identifies a BLE 5.x module/clone; the PnP ID and
HID descriptor are Samsung-compatible. This is not enough to prove it uses the
same chip/firmware as a Trio 500, but it is the same protocol family.

## `samsung` driver

- In-tree driver `hid-samsung`; alias `hid:b0005g*v000004E8p00007021`.
- Product `0x7021` = `USB_DEVICE_ID_SAMSUNG_WIRELESS_KBD`.
- Applied mapping table: `samsung_kbd_input_mapping`.
- Usages present in this descriptor:
  - Keyboard: `0x32` -> `KEY_BACKSLASH`, `0x64` -> `KEY_102ND`,
    `0x87` -> `KEY_RO`
  - Consumer: `0x18A` -> Mail, `0x196` -> WWW, `0x221` -> Search,
    `0x223` -> Homepage, `0x306` -> `BTN_TRIGGER_HAPPY5` (QPanel),
    `0x307` -> `BTN_TRIGGER_HAPPY3` (SIP)
- The driver has many cases for other Samsung models (Menu, Screenlock, Smart
  Voice, Recent Apps, Language, Brightness `0x30A/0x30B`, ...); this descriptor
  does not contain those usages, so they do not apply.
- Brightness `0x06F/0x070` is present in the descriptor but is not in this
  driver's mapping table; generic HID handles it, usually as display brightness.
- `samsung_probe` only special-cases IR remotes; `samsung_report_fixup` also
  only handles IR remotes. There is no battery/backlight/DFU support.

The current input-remapper preset partly depends on key codes produced by this
driver (Search/Homepage). Do not replace it with `hid-generic` without testing
the preset.

## Battery, backlight, and sleep

- No battery GATT/HID data; `/sys/class/power_supply` only has `AC` and `BAT0`.
- No keyboard backlight; `/sys/class/backlight` only has `intel_backlight`;
  there is no keyboard entry in `/sys/class/leds`.
- A slow 1/2 Hz LED blink is likely low battery (<10%) according to the Trio 500
  manual. The OS cannot read the battery percentage.
- The keyboard disconnects when idle; HCI logs show `Remote User Terminated`,
  not a host timeout. This is firmware behavior; there is no GATT command to
  disable sleep.
- Latency can only be tuned from the host side (BlueZ/HCI). The bond target is
  `12/12/0/300`; however, `btmon` showed the keyboard requesting
  `12/12/9/300` when idle and BlueZ accepting it for the live connection. The
  bond can be rewritten to 9 after that request. Fully blocking it would require
  a BlueZ/kernel policy change; no such patch is included in this repository.
- The `0x2A04` Preferred Connection Parameters characteristic is read-only
  (20 ms / latency 0 / 3240 ms); it is not a sleep control.

## Sources

- BlueZ D-Bus GATT reads (`ReadValue`) and `bluetoothctl`.
- HID report descriptor from
  `/sys/class/hidraw/hidraw0/device/report_descriptor`.
- Linux `drivers/hid/hid-samsung.c` and `drivers/hid/hid-ids.h`.
- `btmon` for connection and termination events.
