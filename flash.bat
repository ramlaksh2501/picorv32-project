@echo off
setlocal

set PORT=%1
if "%PORT%"=="" set PORT=COM15

echo ========================================================
echo Flashing PicoRV32 Application Firmware
echo Target Port: %PORT%
echo Binary: binaries\app.bin
echo ========================================================

if not exist binaries\app.bin (
    echo Error: binaries\app.bin does not exist. Please build the firmware first.
    exit /b 1
)

python firmware\tools\upload.py %PORT% binaries\app.bin
pause
