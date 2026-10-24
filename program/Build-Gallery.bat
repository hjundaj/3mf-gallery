@echo off
rem Builds a gallery for ANY folder: double-click for a folder picker, or drag a folder onto this file.
rem The gallery is written to <folder>\_3mf_gallery\gallery.html
powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0Build-Gallery.ps1" %*
if errorlevel 1 pause
