@echo off
set "SCRIPT_DIR=%~dp0"
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File "%SCRIPT_DIR%DriverVault.ps1"
