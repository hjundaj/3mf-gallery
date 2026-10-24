# Installs (or removes) the handler for the gallery buttons "Open in Bambu Studio" and "Delete".
# Run once on every computer you view the gallery on.
# No administrator rights needed - it only writes to the current user's registry
# (HKCU\Software\Classes\gallery3mf) and copies the handler to %LOCALAPPDATA%\3MFGallery.
#
#   Install-Buttons.ps1             -> install / update
#   Install-Buttons.ps1 -Uninstall  -> remove

param([switch]$Uninstall)

$ErrorActionPreference = 'Stop'
$dir = Join-Path $env:LOCALAPPDATA '3MFGallery'
$key = 'HKCU:\Software\Classes\gallery3mf'

if ($Uninstall) {
    if (Test-Path $key) { Remove-Item $key -Recurse -Force }
    if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
    Write-Host 'The gallery button handler has been removed.' -ForegroundColor Green
    return
}

New-Item -ItemType Directory -Force -Path $dir | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'GalleryAction.ps1') -Destination $dir -Force

$ps  = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$cmd = '"{0}" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File "{1}" "%1"' -f $ps, (Join-Path $dir 'GalleryAction.ps1')

New-Item -Path "$key\shell\open\command" -Force | Out-Null
Set-Item -Path $key -Value 'URL:3MF Gallery'
New-ItemProperty -Path $key -Name 'URL Protocol' -Value '' -PropertyType String -Force | Out-Null
Set-Item -Path "$key\shell\open\command" -Value $cmd

Write-Host 'Done. The "Open in Bambu Studio" and "Delete" buttons in the gallery now work.' -ForegroundColor Green
Write-Host 'The first time you click one, the browser asks whether to open "3MF Gallery" - tick "Always allow" and click Open.'
