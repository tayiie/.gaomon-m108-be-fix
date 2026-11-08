# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.0.0] - 2026-11-08

### Added

- `scripts/Disable-TabletKeyboard.ps1` — disables the tablet's HID keyboard
  collections by writing `ConfigFlags = 1` and restarting the device;
  `-Undo` restores them.
- `scripts/disable-tablet-keyboard.cmd` / `scripts/enable-tablet-keyboard.cmd`
  — one-click wrappers with UAC self-elevation.
- `scripts/Get-TabletKeyboardState.ps1` — read-only state viewer.
- `docs/technical.md` — HID topology, report formats, injection analysis,
  `ConfigFlags` details, rejected alternatives.
- `docs/compatibility.md` — tested devices, custom `-Match`, troubleshooting.
- Chinese and English README, MIT license, changelog.

### Tested

- GAOMON M108 (`GM001_T208`, `VID_256C / PID_0064`), Windows 11,
  GAOMON driver 16.0.0.218.

### Notes

- Express keys, lock-screen and screenshot shortcuts share the disabled
  keyboard collection and stop working. Use `enable-tablet-keyboard.cmd` to
  restore them.
