@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
start "" wscript.exe "%SCRIPT_DIR%App\Start-DriverVault.vbs"
endlocal
