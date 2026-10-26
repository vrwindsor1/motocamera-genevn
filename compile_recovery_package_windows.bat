@echo off
setlocal
cd /d "%~dp0"

echo ================================================================================
echo    Motorola Camera 4 Recovery Package Compiler for Moto G Stylus 5G 2023
echo                      Device: genevn / genevn_g (LineageOS)
echo ================================================================================
echo.

set PS_SCRIPT=%~dp0compile_recovery_package_windows.ps1
set GITHUB_RAW=https://raw.githubusercontent.com/vrwindsor1/motocamera-genevn/main/compile_recovery_package_windows.ps1

if not exist "%PS_SCRIPT%" (
    echo [INFO] compile_recovery_package_windows.ps1 not found locally.
    echo [INFO] Downloading PowerShell builder script from GitHub...
    powershell.exe -NoProfile -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; (New-Object Net.WebClient).DownloadFile('%GITHUB_RAW%', '%PS_SCRIPT%')"
    if not exist "%PS_SCRIPT%" (
        echo [ERROR] Failed to download compile_recovery_package_windows.ps1.
        pause
        exit /b 1
    )
    echo [OK] PowerShell builder downloaded successfully.
    echo.
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" %*
set SCRIPT_EXIT_CODE=%ERRORLEVEL%

echo.
if %SCRIPT_EXIT_CODE% equ 0 (
    echo [OK] Execution finished successfully.
) else (
    echo [ERROR] Script exited with error code %SCRIPT_EXIT_CODE%.
)

echo.
echo Press any key to exit...
pause >nul
exit /b %SCRIPT_EXIT_CODE%
