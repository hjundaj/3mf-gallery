@echo off
rem Rebuilds the gallery for the PARENT folder (all .3mf files in it and its subfolders).
rem The gallery (gallery.html + images) is written to this folder.
powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0program\Build-Gallery.ps1" -Folder "%~dp0.." -Output "%~dp0."
if errorlevel 1 pause
