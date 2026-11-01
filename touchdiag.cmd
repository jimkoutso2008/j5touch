@echo off
rem J5 touchscreen diagnostics - runs from startnet.cmd, needs no input.
rem Touch the screen while it runs; the counters should move.
set N=0
:loop
set /a N+=1
cls
echo ===== J5 touch diag - pass %N%, refreshes every ~3s =====
echo.
echo [1] ACPI touch device J5TS0001:
reg query "HKLM\SYSTEM\CurrentControlSet\Enum\ACPI\J5TS0001" /s /v Service 2>nul | find "Service" || echo     NOT ENUMERATED - is the new firmware with the TSC0 ACPI device flashed?
echo.
call :count j5touch "[2] j5touch driver started on"
call :count mouhid  "[3] mouhid HID mouse started on"
echo.
echo [4] j5touch status:
reg query "HKLM\SYSTEM\CurrentControlSet\Services\j5touch" 2>nul | find "REG_DWORD" || echo     no status yet - driver never ran
echo.
echo [5] HID devices:
reg query "HKLM\SYSTEM\CurrentControlSet\Enum\HID" 2>nul | find "\HID\" || echo     none
echo.
echo ChipId 0x38c = touch chip found, 0xffffffff = no answer. Ctrl+C stops.
ping -n 4 127.0.0.1 >nul 2>&1
goto loop

:count
set C=
for /f "tokens=3" %%v in ('reg query "HKLM\SYSTEM\CurrentControlSet\Services\%~1\Enum" /v Count 2^>nul ^| find "Count"') do set C=%%v
if not defined C goto count_none
echo %~2: %C% device
exit /b
:count_none
echo %~2: none
exit /b
