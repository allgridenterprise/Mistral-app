@echo off
SET SCRIPT_PATH=%~dp0fix-bitwarden-sso-integration.ps1
echo Running Bitwarden SSO Integration Fix Script with elevated privileges...
echo.

powershell -Command "Start-Process powershell -ArgumentList '-NoExit','-ExecutionPolicy Bypass','-File \"%SCRIPT_PATH%\"' -Verb RunAs"

echo.
echo If a UAC prompt appears, please accept it to run the script with admin rights.
echo Script logs will be saved to %~dp0logs directory.
echo.
pause
