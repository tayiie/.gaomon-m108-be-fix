# GAOMON M108 pen side-button B/E fix

> When the GAOMON driver is not running, the pen side buttons emit `B` and `E`
> in addition to their normal mouse function. This repository removes those
> stray keystrokes by **disabling the tablet's HID keyboard collections at the
> device level**, while keeping the pen tip, pressure, mouse buttons and volume
> keys working.

[![Platform](https://img.shields.io/badge/Windows-10%20%2F%2011-0078D6?logo=windows)](https://www.microsoft.com/windows)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell)](https://learn.microsoft.com/powershell/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## Problem

Device: **GAOMON M108** (internal model `GM001_T208`, USB `VID_256C / PID_0064`).

- With the official driver UI closed, holding a pen side button while the pen
  hovers emits `B` or `E` on top of the normal left/right click.
- The characters land in whatever window has focus (editor, chat, browser).
- While the tip is touching the tablet, the characters usually do not appear.

## Root cause

The tablet exposes a separate **HID keyboard collection**:

```
HID\VID_256C&PID_0064&MI_02&Col04      HID Keyboard Device   (physical)
HID\bigmax_hid_drv&Col07               HID Keyboard Device   (GAOMON virtual)
```

The GAOMON background driver reads `B`/`E` from that collection and injects
them into the focused window with **`PostMessage` / `SendMessage`**.

Because this is window-message injection instead of normal keyboard input:

- a low-level keyboard hook (`WH_KEYBOARD_LL`) never sees the keys;
- a user-mode filter cannot block them;
- Raw Input can observe the HID report, but cannot stop the injection.

The reliable fix is to disable the keyboard collection at the device level.

## Fix

The script sets the target HID keyboard collections to:

```
ConfigFlags = 0x1   (CONFIGFLAG_DISABLED)
```

and restarts the device with `pnputil /restart-device`.

`pnputil /disable-device` is not used because Windows treats keyboard-class
devices as *critical system devices* and refuses. Writing `ConfigFlags`
directly and restarting is the same operation Device Manager performs when you
choose “Disable device”.

Only `kbdhid` / Keyboard collections are touched. The pen digitizer, mouse
collection and Consumer Control (volume keys) are left alone.

## Quick start

```powershell
git clone https://github.com/<your-name>/gaomon-m108-be-fix.git
cd gaomon-m108-be-fix
```

Right-click **`scripts\disable-tablet-keyboard.cmd`** → **Run as administrator**
→ approve UAC.

The script:

1. enumerates matching keyboard collections under
   `HKLM\SYSTEM\CurrentControlSet\Enum\HID`;
2. sets `ConfigFlags = 1`;
3. restarts the device with `pnputil`;
4. writes every step to `logs\fix-*.log`.

Test: hold a pen side button while hovering — no `B`/`E` should appear. The pen
tip, pressure, left/right click and volume keys keep working.

## Check state

Read-only, no admin required:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Get-TabletKeyboardState.ps1
```

## Restore

Right-click **`scripts\enable-tablet-keyboard.cmd`** → **Run as administrator**.

This sets `ConfigFlags = 0` and restarts the device. If a device does not come
back, unplug/replug the tablet or reboot.

## What is kept / what stops

| Feature | After the fix |
|---|---|
| Pen tip, pressure, hover | ✅ kept |
| Pen side-button left/right click | ✅ kept |
| Pen sliding to scroll pages | ✅ kept |
| Volume keys | ✅ kept |
| 8 express keys | ❌ disabled (same keyboard interface) |
| Lock screen / screenshot shortcuts | ❌ disabled (same keyboard interface) |
| Stray `B`/`E` | ✅ gone |

The express keys and `B`/`E` share the same HID keyboard collection, so they
stop together. Switch back with `enable-tablet-keyboard.cmd` if you need them.

## Other models

Default match patterns:

```text
VID_256C&PID_0064      # GAOMON M108 / HUION devices with the same IDs
bigmax_hid_drv         # GAOMON virtual keyboard created by the kernel driver
```

For another model, find its `VID_xxxx&PID_xxxx` in Device Manager → the
tablet's **HID Keyboard Device** → Properties → Details → **Device instance
path**, then run:

```powershell
.\scripts\Disable-TabletKeyboard.ps1 -Match "VID_1234&PID_5678","bigmax_hid_drv"
```

See [docs/compatibility.md](docs/compatibility.md).

## FAQ

**`Cannot disable critical system device`?**  
That is `pnputil /disable-device`. This script writes `ConfigFlags` directly and
restarts the device instead.

**Does it need a background process?**  
No. The setting lives in the registry device key and survives reboots.

**B/E came back after a driver update?**  
Re-run `disable-tablet-keyboard.cmd`. Driver updates and USB port changes can
re-enumerate the device.

**Express keys stopped working?**  
Expected. Run `enable-tablet-keyboard.cmd` or open the official driver.

**Antivirus warning?**  
The script only edits `ConfigFlags` under the target HID device key and calls
the built-in `pnputil.exe`. No network access, no background process. Read the
source before running.

## Technical details

- [docs/technical.md](docs/technical.md)
- [docs/compatibility.md](docs/compatibility.md)
- [CHANGELOG.md](CHANGELOG.md)

## Disclaimer

This changes Windows device registry keys. It is reversible, but test it in a
controlled environment first. Use at your own risk.

## License

[MIT](LICENSE)
