@echo off
rem Run once on every computer: enables the "Open in Bambu Studio" and "Delete" buttons in the gallery.
rem To uninstall: "Install Buttons.bat" -Uninstall
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0program\Install-Buttons.ps1" %*
pause
