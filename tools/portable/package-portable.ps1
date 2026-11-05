[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BuildRoot,
    [Parameter(Mandatory)][string]$OutputRoot
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$BuildRoot = [IO.Path]::GetFullPath($BuildRoot).TrimEnd('\')
if ((Get-Content -LiteralPath (Join-Path $BuildRoot 'progress.txt') -Raw).Trim() -ne 'PUBLISH_COMPLETE') { throw 'The portable build is not complete.' }
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
[void][IO.Directory]::CreateDirectory($OutputRoot)
$results = @(Get-Content -LiteralPath (Join-Path $BuildRoot 'build-results.json') -Raw | ConvertFrom-Json)
if (-not $results.Count -or @($results | Where-Object buildExitCode -ne 0).Count) { throw 'Successful build results are required.' }
$sourceCommit = (& git -C $repoRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Cannot identify the source commit.' }
$receipts = [Collections.Generic.List[object]]::new()
$utf8 = [Text.UTF8Encoding]::new($false)
$languageBytes = $utf8.GetBytes('{"language":"de-DE"}')

function Get-BytesHash([byte[]]$Bytes) {
    $hash = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($hash.ComputeHash($Bytes))).Replace('-', '') }
    finally { $hash.Dispose() }
}

foreach ($result in $results) {
    $module = [string]$result.module
    if ($module -notin @('FancyZones', 'ColorPicker', 'TextExtractor', 'ImageResizer', 'PowerDisplay', 'AlwaysOnTop', 'FileLocksmith', 'Peek', 'CropAndLock', 'AdvancedPaste')) { throw "Unknown module: $module" }
    $source = Join-Path $BuildRoot $module
    foreach ($required in @('PowerToys.Portable.exe', 'PowerToys.Portable.pri', 'PowerToys.Settings.dll', 'portable-mode', 'portable-module.json', 'portable.ico')) {
        if (-not (Test-Path -LiteralPath (Join-Path $source $required) -PathType Leaf)) { throw "Missing portable dependency: $module/$required" }
    }
    if ((Get-FileHash -LiteralPath (Join-Path $source 'PowerToys.Portable.pri')).Hash -ne (Get-FileHash -LiteralPath (Join-Path $source 'PowerToys.Settings.pri')).Hash) { throw "Portable resource alias differs from settings resources: $module" }
    $buildManifest = Get-Content -LiteralPath (Join-Path $source 'package-manifest.json') -Raw | ConvertFrom-Json
    $version = [string]$buildManifest.version
    if ($version -notmatch '^\d+\.\d+\.\d+\.\d+$') { throw 'Invalid package version.' }
    $zipName = "PowerToys-$module-Portable-$version-x64.zip"
    $zipPath = Join-Path $OutputRoot $zipName
    if (Test-Path -LiteralPath $zipPath) { throw "Refusing to replace an existing archive: $zipPath" }
    $manifestFiles = [Collections.Generic.List[object]]::new()
    $stream = [IO.File]::Open($zipPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    $archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create, $false)
    try {
        foreach ($file in (Get-ChildItem -LiteralPath $source -Recurse -File | Sort-Object FullName)) {
            $relative = $file.FullName.Substring($source.Length + 1).Replace('\', '/')
            if ($relative -eq 'package-manifest.json' -or $relative.StartsWith('Data/', [StringComparison]::OrdinalIgnoreCase)) { continue }
            if ($file.Extension -eq '.pdb') { continue }
            if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Reparse point in package: $relative" }
            [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $file.FullName, $relative, [IO.Compression.CompressionLevel]::Optimal)
            $manifestFiles.Add([pscustomobject][ordered]@{ path=$relative; bytes=$file.Length; sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash })
        }

        # Seed a fresh German profile; never distribute smoke-test data, logs or user settings.
        $settingsModuleName = if ($module -eq 'ImageResizer') { 'Image Resizer' } elseif ($module -eq 'FileLocksmith') { 'File Locksmith' } else { $module }
        $generalProfile = @{ enabled = @{ $settingsModuleName = $true }; theme = 'system'; startup = $false; download_updates_automatically = $false; enable_experimentation = $false }
        $generalBytes = $utf8.GetBytes(($generalProfile | ConvertTo-Json -Depth 4 -Compress))
        foreach ($seed in @(@{path='Data/Microsoft/PowerToys/language.json'; bytes=$languageBytes}, @{path='Data/Microsoft/PowerToys/settings.json'; bytes=$generalBytes})) {
            $entry = $archive.CreateEntry($seed.path)
            $entryStream = $entry.Open()
            try { $entryStream.Write($seed.bytes, 0, $seed.bytes.Length) } finally { $entryStream.Dispose() }
            $manifestFiles.Add([pscustomobject][ordered]@{ path=$seed.path; bytes=$seed.bytes.Length; sha256=(Get-BytesHash $seed.bytes) })
        }
        $manifest = [ordered]@{
            module=$module; version=$version; experimental=$true; sourceCommit=$sourceCommit
            entryPoint=$buildManifest.entryPoint; files=@($manifestFiles.ToArray())
        }
        $entry = $archive.CreateEntry('package-manifest.json')
        $writer = [IO.StreamWriter]::new($entry.Open(), $utf8)
        try { $writer.Write(($manifest | ConvertTo-Json -Depth 6)) } finally { $writer.Dispose() }
    }
    finally { $archive.Dispose(); $stream.Dispose() }

    # Verify the archive itself, not only the source directory.
    $archive = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        if ($archive.Entries.Count -ne $manifestFiles.Count + 1) { throw "Unexpected ZIP entry count: $module" }
        foreach ($file in $manifestFiles) {
            $entry = $archive.GetEntry($file.path)
            if (-not $entry -or $entry.Length -ne $file.bytes) { throw "ZIP size mismatch: $($file.path)" }
            $entryStream = $entry.Open()
            $hash = [Security.Cryptography.SHA256]::Create()
            try { $actual = ([BitConverter]::ToString($hash.ComputeHash($entryStream))).Replace('-', '') }
            finally { $hash.Dispose(); $entryStream.Dispose() }
            if ($actual -ne $file.sha256) { throw "ZIP hash mismatch: $($file.path)" }
        }
    }
    finally { $archive.Dispose() }
    $receipts.Add([pscustomobject][ordered]@{ module=$module; file=$zipName; bytes=(Get-Item -LiteralPath $zipPath).Length; sha256=(Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash; verifiedFiles=$manifestFiles.Count; sourceCommit=$sourceCommit })
    Write-Host "Verified $module ($($manifestFiles.Count) files)"
}

[IO.File]::WriteAllText((Join-Path $OutputRoot 'package-verification.json'), (ConvertTo-Json -InputObject @($receipts.ToArray()) -Depth 5), $utf8)
[IO.File]::WriteAllLines((Join-Path $OutputRoot 'SHA256SUMS.txt'), @($receipts | ForEach-Object { "$($_.sha256)  $($_.file)" }), $utf8)
