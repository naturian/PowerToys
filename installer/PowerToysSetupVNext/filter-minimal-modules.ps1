<#
.SYNOPSIS
Entfernt die Binaries NICHT ausgewaehlter PowerToys-Module aus dem Build-Output, BEVOR der
WiX-Installer den Ausgabeordner "harvestet" (BaseApplicationsFiles / WinUI3ApplicationsFiles
sammeln alles in Release\ bzw. Release\WinUI3Apps\ ein).

Konfigurationsgetrieben: die zu loeschenden Muster ergeben sich aus den NICHT in
selected-modules.txt gewaehlten Modulen (Modules-Database.ps1).
Es werden NUR .dll/.exe/.pdb in den beiden (nicht-rekursiven) Catch-all-Wurzeln geloescht.
#>
param(
    [string]$Platform = 'x64',
    [string]$Configuration = 'Release',
    [string]$RepoRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [string]$ConfigFile
)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
. (Join-Path $here 'Modules-Database.ps1')
if (-not $ConfigFile) { $ConfigFile = Join-Path $here 'selected-modules.txt' }

$releaseRoot = Join-Path $RepoRoot "$Platform\$Configuration"
if (-not (Test-Path $releaseRoot)) { throw "Build-Output nicht gefunden: $releaseRoot" }
$winui = Join-Path $releaseRoot 'WinUI3Apps'
$scopeDirs = @($releaseRoot, $winui) | Where-Object { Test-Path $_ }

# Ausgewaehlte Module
$selected = Get-Content $ConfigFile | ForEach-Object { ($_ -replace '#.*$', '').Trim() } | Where-Object { $_ -ne '' }

# Loeschmuster = FilterPatterns aller NICHT ausgewaehlten Module
$deny = [System.Collections.Generic.List[string]]::new()
foreach ($k in $ModuleDatabase.Keys) {
    if ($selected -contains $k) { continue }
    foreach ($p in $ModuleDatabase[$k].FilterPatterns) { if ($deny -notcontains $p) { $deny.Add($p) } }
}

# Diese Dateien nie loeschen (Settings-UI laedt sie zur Laufzeit).
$keep = $FilterKeepAlways | ForEach-Object { $_.ToLowerInvariant() }

$exts = @('.dll', '.exe', '.pdb')
$deleted = 0
$keptExceptions = @()
foreach ($dir in $scopeDirs) {
    Get-ChildItem -Path $dir -File | ForEach-Object {
        $file = $_
        if ($exts -notcontains $file.Extension.ToLowerInvariant()) { return }
        $matched = $false
        foreach ($pat in $deny) { if ($file.Name -like $pat) { $matched = $true; break } }
        if (-not $matched) { return }
        if ($keep -contains $file.Name.ToLowerInvariant()) { $keptExceptions += $file.Name; return }
        Remove-Item $file.FullName -Force
        $deleted++
    }
}

# Unterordner nicht ausgewaehlter Module (werden ohnehin nicht paketiert - Aufraeumen).
if ($selected -notcontains 'Run') {
    $rp = Join-Path $releaseRoot 'RunPlugins'; if (Test-Path $rp) { Remove-Item $rp -Recurse -Force }
}
if ($selected -notcontains 'CmdPal') {
    $cp = Join-Path $winui 'CmdPal'; if (Test-Path $cp) { Remove-Item $cp -Recurse -Force }
}

Write-Host "[FILTER] $deleted Datei(en) nicht ausgewaehlter Module entfernt."
if ($keptExceptions.Count) { Write-Host "[FILTER] Als Settings-Abhaengigkeit behalten: $(($keptExceptions | Sort-Object -Unique) -join ', ')" }
