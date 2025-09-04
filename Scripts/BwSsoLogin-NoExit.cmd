@echo off
powershell -NoExit -ExecutionPolicy Bypass -Command "& { $Host.UI.RawUI.WindowTitle = 'Bitwarden SSO Login'; . '%~dp0BwSsoLogin.ps1' -AutoUnlock -UpdateSession; $host.enternestedprompt() }"