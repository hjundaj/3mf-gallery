# Build-Gallery - builds a browsable HTML gallery of your .3mf files
# (Bambu Studio / MakerWorld / Orca Slicer / PrusaSlicer).
#
# Usage:
#   Build-Gallery.bat                   -> folder picker
#   Build-Gallery.bat "D:\3D Models"    -> specific folder (or drag a folder onto the .bat)
#   Build-Gallery.ps1 -Folder "D:\3D Models" [-Output "D:\Gallery"] [-NoOpen]
#
# Output: <Output>\gallery.html plus extracted pictures in <Output>\images
# (default Output = <Folder>\_3mf_gallery). Your .3mf files are only read, never modified.

param(
    [string]$Folder,    # folder with .3mf files (empty = folder picker)
    [string]$Output,    # where to write the gallery (empty = <Folder>\_3mf_gallery)
    [switch]$NoOpen     # do not open the gallery in the browser when done
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$lastFile  = Join-Path $scriptDir 'last_folder.txt'

# --- pick the folder ---------------------------------------------------------
if (-not $Folder) {
    Add-Type -AssemblyName System.Windows.Forms
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Choose the folder with your .3mf files'
    if (Test-Path -LiteralPath $lastFile) {
        $prev = (Get-Content -LiteralPath $lastFile -Raw -Encoding UTF8).Trim()
        if ($prev -and (Test-Path -LiteralPath $prev)) { $dlg.SelectedPath = $prev }
    }
    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
    $Folder = $dlg.SelectedPath
}
$Folder = (Resolve-Path -LiteralPath $Folder).Path.TrimEnd('\')
Set-Content -LiteralPath $lastFile -Value $Folder -Encoding UTF8

if ($Output) {
    New-Item -ItemType Directory -Force -Path $Output | Out-Null
    $outDir = (Resolve-Path -LiteralPath $Output).Path.TrimEnd('\')
} else {
    $outDir = Join-Path $Folder '_3mf_gallery'
}
$imgDir = Join-Path $outDir 'images'
New-Item -ItemType Directory -Force -Path $imgDir | Out-Null

Write-Host "Folder: $Folder"
$files = @(Get-ChildItem -LiteralPath $Folder -Recurse -File -Filter '*.3mf' -ErrorAction SilentlyContinue |
           Where-Object { -not $_.FullName.StartsWith($outDir + '\', [StringComparison]::OrdinalIgnoreCase) } |
           Sort-Object FullName)
Write-Host "Found .3mf files: $($files.Count)"

# --- read metadata (title, designer, description) from 3D/3dmodel.model -----
function Read-Meta($entry) {
    $meta = @{}
    $s = $entry.Open()
    try {
        # metadata sits at the top of the file - read only 256 KB, the mesh can be hundreds of MB
        $buf = New-Object byte[] 262144
        $total = 0
        while ($total -lt $buf.Length) {
            $n = $s.Read($buf, $total, $buf.Length - $total)
            if ($n -le 0) { break }
            $total += $n
        }
    } finally { $s.Dispose() }
    $text = [Text.Encoding]::UTF8.GetString($buf, 0, $total)
    foreach ($m in [regex]::Matches($text, '<metadata\s+name="([^"]+)"\s*>(.*?)</metadata>', 'Singleline')) {
        $meta[$m.Groups[1].Value] = [Net.WebUtility]::HtmlDecode($m.Groups[2].Value).Trim()
    }
    return $meta
}

function Clean-Html([string]$s, [int]$max) {
    if (-not $s) { return '' }
    # MakerWorld descriptions are sometimes encoded several times (&amp;lt;p&amp;gt;)
    for ($n = 0; $n -lt 4; $n++) { $d = [Net.WebUtility]::HtmlDecode($s); if ($d -eq $s) { break }; $s = $d }
    $s = $s -replace '<br\s*/?>|</p>|</li>|</h\d>', ' '
    $s = [Net.WebUtility]::HtmlDecode(($s -replace '<[^>]+>', ' '))
    $s = ($s -replace '\s+', ' ').Trim()
    if ($s.Length -gt $max) { $s = $s.Substring(0, $max).TrimEnd() + '...' }
    return $s
}

# --- process files -------------------------------------------------------------
$items = New-Object System.Collections.Generic.List[object]
$used  = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$md5   = [Security.Cryptography.MD5]::Create()
$i = 0

foreach ($f in $files) {
    $i++
    Write-Progress -Activity 'Building 3MF gallery' -Status "$i / $($files.Count): $($f.Name)" -PercentComplete ($i * 100 / [Math]::Max(1, $files.Count))

    $rel  = $f.FullName.Substring($Folder.Length).TrimStart('\')
    $hash = -join ($md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($rel.ToLowerInvariant())) | Select-Object -First 4 | ForEach-Object { $_.ToString('x2') })
    $base = $f.Name -replace '(\.gcode)?\.3mf$', ''
    $safe = ($base -replace '[^\w\-]+', '_').Trim('_')
    if ($safe.Length -gt 50) { $safe = $safe.Substring(0, 50) }
    if (-not $safe) { $safe = 'model' }
    $prefix = "${safe}_$hash"

    $item = [ordered]@{
        title    = $base
        profile  = ''
        designer = ''
        desc     = ''
        file     = $rel
        name     = $f.Name
        dir      = [string](Split-Path $rel -Parent)
        sliced   = ($f.Name -match '\.gcode\.3mf$')
        size     = [Math]::Round($f.Length / 1MB, 1)
        date     = $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
        img      = ''
        imgs     = @()
        plates   = 0
        err      = ''
    }

    $zip = $null
    try {
        $zip = [IO.Compression.ZipFile]::OpenRead($f.FullName)
        $entries = @($zip.Entries)

        $model = $entries | Where-Object { $_.FullName -ieq '3D/3dmodel.model' } | Select-Object -First 1
        if ($model) {
            $meta = Read-Meta $model
            if ($meta['Title'])        { $item.title    = $meta['Title'] }
            if ($meta['ProfileTitle']) { $item.profile  = $meta['ProfileTitle'] }
            if ($meta['Designer'])     { $item.designer = $meta['Designer'] }
            if ($meta['Description'])  { $item.desc     = Clean-Html $meta['Description'] 600 }
        }

        # pictures: cover, MakerWorld photos, plate thumbnails
        $cover  = @($entries | Where-Object { $_.FullName -match '^Auxiliaries/\.thumbnails/thumbnail_3mf\.png$' })
        $photos = @($entries | Where-Object { $_.FullName -match '^Auxiliaries/Model Pictures/[^/]+\.(jpe?g|png|webp|gif)$' -and $_.Length -gt 0 } |
                   Sort-Object FullName | Select-Object -First 3)
        $plates = @($entries | Where-Object { $_.FullName -match '^Metadata/plate_\d+\.png$' } |
                   Sort-Object { [int]([regex]::Match($_.Name, '\d+').Value) })
        $item.plates = $plates.Count

        $sel = New-Object System.Collections.Generic.List[object]
        foreach ($e in $cover)  { $sel.Add(@($e, 'Cover')) }
        foreach ($e in $photos) { $sel.Add(@($e, 'Photo')) }
        foreach ($e in $plates) { $sel.Add(@($e, ('Plate ' + [regex]::Match($e.Name, '\d+').Value))) }
        if ($sel.Count -eq 0) {
            # other slicers (Orca, Prusa) - first sensible thumbnail
            $fb = $entries | Where-Object { $_.FullName -match '^(Metadata|Auxiliaries)/.*\.(png|jpe?g)$' -and $_.FullName -notmatch '(_small|no_light|pick_|top_)' } |
                  Sort-Object Length -Descending | Select-Object -First 1
            if ($fb) { $sel.Add(@($fb, 'Preview')) }
        }

        $imgs = @()
        $k = 0
        foreach ($pair in $sel) {
            $e = $pair[0]
            $ext = [IO.Path]::GetExtension($e.Name).ToLowerInvariant()
            $n = "${prefix}_$k$ext"
            $k++
            $dest = Join-Path $imgDir $n
            $fresh = (Test-Path -LiteralPath $dest) -and ((Get-Item -LiteralPath $dest).LastWriteTime -ge $f.LastWriteTime)
            if (-not $fresh) {
                [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $dest, $true)
                (Get-Item -LiteralPath $dest).LastWriteTime = Get-Date
            }
            [void]$used.Add($n)
            $imgs += [ordered]@{ src = "images/$n"; label = $pair[1] }
        }
        $item.imgs = $imgs
        if ($imgs.Count -gt 0) { $item.img = $imgs[0].src }
    }
    catch {
        $item.err = $_.Exception.Message
        Write-Warning "Problem with $rel : $($_.Exception.Message)"
    }
    finally {
        if ($zip) { $zip.Dispose() }
    }
    $items.Add($item)
}
Write-Progress -Activity 'Building 3MF gallery' -Completed

# remove pictures of files that no longer exist (only files named by this program)
Get-ChildItem -LiteralPath $imgDir -File |
    Where-Object { $_.Name -match '_[0-9a-f]{8}_\d+\.(png|jpe?g|webp|gif)$' -and -not $used.Contains($_.Name) } |
    Remove-Item -Force

# --- links from the gallery back to the .3mf files ----------------------------
if ($outDir.StartsWith($Folder + '\', [StringComparison]::OrdinalIgnoreCase)) {
    $depth = ($outDir.Substring($Folder.Length).Trim('\') -split '\\').Count
    $relPrefix = '../' * $depth
} elseif ($Folder.StartsWith('\\')) {
    $relPrefix = 'file:' + ($Folder -replace '\\', '/') + '/'
} else {
    $relPrefix = 'file:///' + ($Folder -replace '\\', '/') + '/'
}

# --- write gallery.html -------------------------------------------------------
if ($items.Count -eq 0) { $json = '[]' }
else { $json = ConvertTo-Json -InputObject @($items.ToArray()) -Depth 6 -Compress }
$json = $json.Replace('</', '<\/')

$html = [IO.File]::ReadAllText((Join-Path $scriptDir 'gallery_template.html'), [Text.Encoding]::UTF8)
$html = $html.Replace('__DATA__', $json)
$html = $html.Replace('__FOLDER__', [Net.WebUtility]::HtmlEncode($Folder))
$html = $html.Replace('__ROOT_JSON__', (ConvertTo-Json -InputObject $Folder -Compress))
$html = $html.Replace('__PREFIX_JSON__', (ConvertTo-Json -InputObject $relPrefix -Compress))
$html = $html.Replace('__OUTDIR_JSON__', (ConvertTo-Json -InputObject $outDir -Compress))
$html = $html.Replace('__GEN__', (Get-Date).ToString('yyyy-MM-dd HH:mm'))

# list of files removed with the "Delete" button - obsolete after a fresh scan
$delList = Join-Path $outDir 'deleted.js'
if (Test-Path -LiteralPath $delList) { Remove-Item -LiteralPath $delList -Force }

$htmlPath = Join-Path $outDir 'gallery.html'
[IO.File]::WriteAllText($htmlPath, $html, (New-Object Text.UTF8Encoding $false))

Write-Host "Done: $htmlPath" -ForegroundColor Green
if (-not $NoOpen) { Start-Process $htmlPath }
