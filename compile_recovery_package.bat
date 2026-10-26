@echo off
setlocal
cd /d "%~dp0"

echo ================================================================================
echo    Motorola Camera 4 Recovery Package Compiler for Moto G Stylus 5G 2023
echo                      Device: genevn / genevn_g (LineageOS)
echo ================================================================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0compile_recovery_package.ps1" %*
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
