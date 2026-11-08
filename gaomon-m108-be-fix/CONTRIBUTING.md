# Contributing

Thanks for helping improve this fix.

## Reporting an issue

Please include:

- Tablet model and internal model (e.g. GAOMON M108 / `GM001_T208`);
- USB `VID` / `PID`;
- Windows version and build;
- GAOMON driver version;
- Output of:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Get-TabletKeyboardState.ps1
```

- The relevant `logs\fix-*.log` (remove personal paths if needed);
- What happens with the driver open vs. closed.

## Pull requests

- Keep PowerShell compatible with Windows PowerShell 5.1.
- Keep script output in ASCII where possible (avoids code-page issues).
- Do not hardcode personal paths or machine-specific instance IDs; use
  `-Match` patterns.
- Test the disable and `-Undo` paths on real hardware before submitting.
- Update `README.md`, `README.en.md` and `CHANGELOG.md` when behavior changes.

## Scope

This project intentionally uses the device-level `ConfigFlags` approach. It
does not install a kernel driver or a background process. Proposals that add a
driver should be discussed in an issue first.
