@echo off
setlocal
cd /d "%~dp0"
where powershell.exe >nul 2>&1 || (
  echo PowerShell is required on Windows 10/11.
  pause
  exit /b 1
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\installer.ps1"
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" pause
exit /b %RC%
