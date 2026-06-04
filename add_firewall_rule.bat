@echo off
echo ======================================================
echo  LUFS Monitor Firewall Registry (Requires Admin)
echo ======================================================
echo.

:: Check for administrator privileges
net session >nul 2>&1
if %errorLevel% == 0 (
    echo [INFO] Administrative privileges confirmed.
) else (
    echo [ERROR] Please right-click this file and select "Run as Administrator".
    echo.
    pause
    exit /b
)

echo.
echo [1/1] Registering Windows Defender Firewall inbound rule for UDP 49153...
netsh advfirewall firewall add rule name="LUFS Monitor Reset" dir=in action=allow protocol=UDP localport=49153 description="Allow remote reset command from app"

if %errorLevel% == 0 (
    echo.
    echo [SUCCESS] Firewall rule registered successfully!
    echo           Now you can test the reset button on your phone.
) else (
    echo.
    echo [FAIL] Failed to register firewall rule. (Error code: %errorLevel%)
)
echo.
pause
