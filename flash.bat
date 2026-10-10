@echo off
setlocal

set PORT=%1
if "%PORT%"=="" set PORT=COM15

set BIN_FILE=%2
if "%BIN_FILE%"=="" (
    if exist binaries\aes_test_app.bin (
        set BIN_FILE=binaries\aes_test_app.bin
    ) else (
        set BIN_FILE=binaries\app.bin
    )
)

echo ========================================================
echo Flashing PicoRV32 Application Firmware
echo Target Port: %PORT%
echo Binary: %BIN_FILE%
echo ========================================================

if not exist "%BIN_FILE%" (
    echo Error: %BIN_FILE% does not exist. Please build the firmware first.
    exit /b 1
)

python firmware\tools\upload.py %PORT% %BIN_FILE%
pause
