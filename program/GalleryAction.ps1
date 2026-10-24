# GalleryAction - handles the gallery buttons "Open in Bambu Studio" and "Delete".
# Called by the browser with:
#   gallery3mf:open?f=<full path of a .3mf file>
#   gallery3mf:delete?f=<full path of a .3mf file>&g=<gallery folder>
# Registered by program\Install-Buttons.ps1 ("Install Buttons.bat").
#
# Safety: works only on existing .3mf files, and deleting always asks for
# confirmation in a Windows dialog. Files are never erased - they are moved to
# the "Trash" folder inside the gallery folder.

param(
    [string]$Url,
    [switch]$NoPrompt     # for command-line testing only
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms

function Show-Msg([string]$text, [string]$icon = 'Information', [string]$buttons = 'OK') {
    # always on top (otherwise the dialog hides behind the browser)
    $owner = New-Object System.Windows.Forms.Form -Property @{ TopMost = $true; ShowInTaskbar = $false }
    try { return [System.Windows.Forms.MessageBox]::Show($owner, $text, '3MF Gallery', $buttons, $icon) }
    finally { $owner.Dispose() }
}

function Find-Bambu {
    $c = @()
    foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                   'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                   'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*') {
        Get-ItemProperty $k -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like 'Bambu Studio*' } | ForEach-Object {
            if ($_.InstallLocation) { $c += Join-Path $_.InstallLocation 'bambu-studio.exe' }
            if ($_.DisplayIcon)     { $c += (($_.DisplayIcon -replace '"', '') -replace ',\d+$', '') }
        }
    }
    $c += Join-Path $env:ProgramFiles 'Bambu Studio\bambu-studio.exe'
    # Start menu shortcut (e.g. when installed somewhere else)
    foreach ($lnk in "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Bambu Studio\Bambu Studio.lnk",
                     "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Bambu Studio\Bambu Studio.lnk") {
        if (Test-Path -LiteralPath $lnk) {
            try { $c += (New-Object -ComObject WScript.Shell).CreateShortcut($lnk).TargetPath } catch {}
        }
    }
    $c | Where-Object { $_ -and $_ -like '*bambu-studio.exe' -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
}

try {
    $m = [regex]::Match($Url, '^gallery3mf:/*(open|delete)/?\?(.*)$', 'IgnoreCase')
    if (-not $m.Success) { throw "Unknown command:`n$Url" }
    $action = $m.Groups[1].Value.ToLowerInvariant()
    $q = @{}
    foreach ($kv in ($m.Groups[2].Value -split '&')) {
        $p = $kv -split '=', 2
        if ($p.Count -eq 2) { $q[$p[0]] = [Uri]::UnescapeDataString($p[1]) }
    }

    $file = [string]$q['f']
    if (-not $file -or $file -notmatch '\.3mf$') { throw 'This is not a .3mf file.' }
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        throw "File not found:`n$file`n`nIt may have been deleted or moved already. Refresh the gallery (Refresh Gallery.bat)."
    }
    $item = Get-Item -LiteralPath $file

    if ($action -eq 'open') {
        $exe = Find-Bambu
        if ($exe) { Start-Process -FilePath $exe -ArgumentList ('"{0}"' -f $item.FullName) }
        else      { Invoke-Item -LiteralPath $item.FullName }   # no Bambu Studio - default app for .3mf
        return
    }

    # --- delete (move to the gallery Trash) ---
    $gal = [string]$q['g']
    if (-not $gal -or -not (Test-Path -LiteralPath (Join-Path $gal 'gallery.html'))) {
        throw "Gallery folder not found:`n$gal"
    }
    $trash = Join-Path $gal 'Trash'
    if (-not $NoPrompt) {
        $r = Show-Msg ("Move this file to the gallery Trash?`n`n{0}`n`nfrom folder:`n{1}`n`nThe file will be moved to:`n{2}`nso you can restore it later if needed." -f $item.Name, $item.DirectoryName, $trash) 'Warning' 'YesNo'
        if ($r -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    }
    New-Item -ItemType Directory -Force -Path $trash | Out-Null
    $dest = Join-Path $trash $item.Name
    if (Test-Path -LiteralPath $dest) {
        $base = $item.Name -replace '(\.gcode)?\.3mf$', ''
        $ext  = $item.Name.Substring($base.Length)
        $dest = Join-Path $trash ('{0} ({1:yyyy-MM-dd HHmmss}){2}' -f $base, (Get-Date), $ext)
    }
    Move-Item -LiteralPath $item.FullName -Destination $dest

    # tell the open gallery to hide the card without a refresh
    $line = 'window.DELETED_FILES=(window.DELETED_FILES||[]).concat([' + (ConvertTo-Json -InputObject $file -Compress) + ']);' + "`r`n"
    [IO.File]::AppendAllText((Join-Path $gal 'deleted.js'), $line, (New-Object Text.UTF8Encoding $false))
}
catch {
    if ($NoPrompt) { throw }
    Show-Msg $_.Exception.Message 'Error' | Out-Null
}
