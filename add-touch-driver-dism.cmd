@echo off
setlocal
rem ---------------------------------------------------------------------------
rem Add j5touch to a WinPE boot.wim with DISM (injects a driver without a
rem signed catalog). Run from an *elevated* Command Prompt:
rem   add-touch-driver-dism.cmd "E:\sd card\sources\boot.wim"
rem Build first (out\j5touch.sys); install-bootwim.sh does the same from WSL.
rem ---------------------------------------------------------------------------

net session >nul 2>&1
if errorlevel 1 (
  echo This needs an elevated command prompt ^(Run as administrator^).
  exit /b 1
)

set WIM=%~f1
set MNT=%TEMP%\j5touch-mount
set PKG=%TEMP%\j5touch-pkg

if "%WIM%"=="" (echo usage: %~nx0 path\to\boot.wim & exit /b 1)
if not exist "%WIM%" (echo Missing %WIM% & exit /b 1)
if not exist "%~dp0out\j5touch.sys" (echo Missing %~dp0out\j5touch.sys - run build.sh first & exit /b 1)

if exist "%PKG%" rmdir /s /q "%PKG%"
mkdir "%PKG%"
copy /y "%~dp0j5touch.inf" "%PKG%" >nul
copy /y "%~dp0out\j5touch.sys" "%PKG%" >nul

if exist "%MNT%" rmdir /s /q "%MNT%"
mkdir "%MNT%"

dism /Mount-Image /ImageFile:"%WIM%" /Index:1 /MountDir:"%MNT%" || goto fail
dism /Image:"%MNT%" /Add-Driver /Driver:"%PKG%\j5touch.inf" /ForceUnsigned
if errorlevel 1 (
  dism /Unmount-Image /MountDir:"%MNT%" /Discard
  goto fail
)
dism /Unmount-Image /MountDir:"%MNT%" /Commit || goto fail

echo.
echo Done. Copy boot.wim to the SD card again.
exit /b 0

:fail
echo DISM failed, see the messages above.
exit /b 1
