<#
.SYNOPSIS
Entfernt die Binaries NICHT ausgewaehlter PowerToys-Module aus dem Build-Output, BEVOR der
WiX-Installer den Ausgabeordner "harvestet" (BaseApplicationsFiles / WinUI3ApplicationsFiles
sammeln alles in Release\ bzw. Release\WinUI3Apps\ ein).

Konfigurationsgetrieben: die zu loeschenden Muster ergeben sich aus den NICHT in
selected-modules.txt gewaehlten Modulen (Modules-Database.ps1).
Es werden passende Dateien und modulbezogene Ausgabeordner rekursiv geloescht.
#>
param(
    [ValidateSet('x64', 'arm64')]
    [string]$Platform = 'x64',
    [ValidateSet('Release', 'Debug')]
    [string]$Configuration = 'Release',
    [string]$RepoRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [string]$ConfigFile
)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
. (Join-Path $here 'Modules-Database.ps1')
if (-not $ConfigFile) { $ConfigFile = Join-Path $here 'selected-modules.txt' }

$resolvedRepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path.TrimEnd('\', '/')
$releaseRoot = [IO.Path]::GetFullPath((Join-Path $resolvedRepoRoot "$Platform\$Configuration"))
$repoPrefix = $resolvedRepoRoot + [IO.Path]::DirectorySeparatorChar
if (-not $releaseRoot.StartsWith($repoPrefix, [StringComparison]::OrdinalIgnoreCase) -or
    -not (Test-Path -LiteralPath (Join-Path $resolvedRepoRoot 'PowerToys.slnx') -PathType Leaf)) {
    throw "Unsicherer Build-Output-Pfad: $releaseRoot"
}
if (-not (Test-Path -LiteralPath $releaseRoot -PathType Container)) { throw "Build-Output nicht gefunden: $releaseRoot" }
$releasePrefix = $releaseRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar

# Keine rekursive Bereinigung durch Verzeichnisverknuepfungen ausserhalb des Outputs.
$outputDirectories = @((Get-Item -LiteralPath (Split-Path -Parent $releaseRoot)),
    (Get-Item -LiteralPath $releaseRoot)) + @(Get-ChildItem -LiteralPath $releaseRoot -Directory -Recurse -Force)
if ($outputDirectories | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }) {
    throw 'Build-Output enthaelt Verzeichnisverknuepfungen; Bereinigung abgebrochen.'
}

function Assert-OutputPath([string]$Path) {
    $fullPath = [IO.Path]::GetFullPath($Path)
    if (-not $fullPath.StartsWith($releasePrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Loeschziel liegt ausserhalb des Build-Outputs: $fullPath"
    }
}

# Ausgewaehlte Module
$selected = Get-Content $ConfigFile | ForEach-Object { ($_ -replace '#.*$', '').Trim() } | Where-Object { $_ -ne '' }
if (-not $selected) { throw "Keine Module in $ConfigFile ausgewaehlt." }
$unknown = @($selected | Where-Object { -not $ModuleDatabase.Contains($_) })
if ($unknown.Count -gt 0) { throw "Unbekannte Modul-Schluessel: $($unknown -join ', ')" }
$notBuildable = @($selected | Where-Object { -not $ModuleDatabase[$_].Buildable })
if ($notBuildable.Count -gt 0) { throw "Nicht in der Minimal-Pipeline freigegeben: $($notBuildable -join ', ')" }

# Loeschmuster = FilterPatterns aller NICHT ausgewaehlten Module
$deny = [System.Collections.Generic.List[string]]::new()
foreach ($pattern in $FilterAlwaysDenyPatterns) { $deny.Add($pattern) }
foreach ($k in $ModuleDatabase.Keys) {
    if ($selected -contains $k) { continue }
    foreach ($p in $ModuleDatabase[$k].FilterPatterns) { if ($deny -notcontains $p) { $deny.Add($p) } }
    foreach ($type in $ModuleDatabase[$k].ModuleTypes) {
        $dscPattern = "microsoft.powertoys.$type.settings.dsc.resource.json"
        if ($deny -notcontains $dscPattern) { $deny.Add($dscPattern) }
    }
}

# Diese Dateien nie loeschen (Settings-UI laedt sie zur Laufzeit).
$keep = $FilterKeepAlways | ForEach-Object { $_.ToLowerInvariant() }

$deleted = 0
$keptExceptions = @()
Get-ChildItem -LiteralPath $releaseRoot -File -Recurse | ForEach-Object {
    $file = $_
    $matched = $false
    foreach ($pat in $deny) { if ($file.Name -like $pat) { $matched = $true; break } }
    if (-not $matched -and $file.DirectoryName.Equals($releaseRoot, [StringComparison]::OrdinalIgnoreCase)) {
        foreach ($pat in $FilterLegacyRootPatterns) { if ($file.Name -like $pat) { $matched = $true; break } }
    }
    if (-not $matched) { return }
    if ($keep -contains $file.Name.ToLowerInvariant()) { $keptExceptions += $file.Name; return }
    Assert-OutputPath $file.FullName
    Remove-Item -LiteralPath $file.FullName -Force
    $deleted++
}

# Modulbezogene Ordner tiefste zuerst entfernen.
$denyDirNames = [System.Collections.Generic.List[string]]::new()
foreach ($k in $ModuleDatabase.Keys) {
    if ($selected -contains $k) { continue }
    foreach ($name in $ModuleFilterDirectories[$k]) {
        if ($denyDirNames -notcontains $name) { $denyDirNames.Add($name) }
    }
}
$deletedDirs = 0
Get-ChildItem -LiteralPath $releaseRoot -Directory -Recurse |
    Sort-Object { $_.FullName.Length } -Descending |
    Where-Object { $denyDirNames -contains $_.Name } |
    ForEach-Object {
        Assert-OutputPath $_.FullName
        Remove-Item -LiteralPath $_.FullName -Recurse -Force
        $deletedDirs++
    }

foreach ($name in $denyDirNames) {
    $candidate = Join-Path $releaseRoot $name
    if (Test-Path -LiteralPath $candidate) {
        Assert-OutputPath $candidate
        Remove-Item -LiteralPath $candidate -Recurse -Force
        $deletedDirs++
    }
}

Write-Host "[FILTER] $deleted Datei(en), $deletedDirs Ordner nicht ausgewaehlter Module entfernt."
if ($keptExceptions.Count) { Write-Host "[FILTER] Als Settings-Abhaengigkeit behalten: $(($keptExceptions | Sort-Object -Unique) -join ', ')" }
