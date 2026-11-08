@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Disable-TabletKeyboard.ps1" -Undo
if errorlevel 1 pause
