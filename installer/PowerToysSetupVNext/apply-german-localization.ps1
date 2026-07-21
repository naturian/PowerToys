<#
.SYNOPSIS
Ueberlagert den (englischen) lokalen Build-Output mit den deutschen (multilingualen)
Lokalisierungsdateien aus einem offiziellen PowerToys-v0.99.1-Release.

Hintergrund: Die uebersetzten Ressourcen liegen NICHT im oeffentlichen Repo (nur en-us);
sie stammen aus Microsofts interner Loc-Pipeline. Wir entnehmen sie dem offiziellen Release:
 - WinUI3-Module (Settings, Peek, FileLocksmith, PowerRename, ImageResizer): multilinguale .pri
 - WPF-Modul-Editoren (FancyZones, TextExtractor/PowerOCR, Workspaces): de-DE-Satelliten-DLLs

.PARAMETER OfficialRoot
Pfad zum extrahierten offiziellen PowerToys-Verzeichnis (enthaelt WinUI3Apps\ und de-DE\).
Extraktion z.B.:
  wix burn extract PowerToysSetup-0.99.1-x64.exe -o out -oba ba
  msiexec /a out\WixAttachedContainer\PowerToysSetup-0.99.1-x64.msi /qn TARGETDIR=<dir>
  -> OfficialRoot = <dir>\PFiles64\PowerToys

.PARAMETER Platform / Configuration
Zielplattform/Konfiguration des lokalen Builds (Standard x64/Release).
#>
param(
    [Parameter(Mandatory = $true)][string]$OfficialRoot,
    [string]$Platform = 'x64',
    [string]$Configuration = 'Release',
    [string]$RepoRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
)
$ErrorActionPreference = 'Stop'
$my = Join-Path $RepoRoot "$Platform\$Configuration"
if (-not (Test-Path $my)) { throw "Build-Output nicht gefunden: $my" }
if (-not (Test-Path $OfficialRoot)) { throw "Offizielles Verzeichnis nicht gefunden: $OfficialRoot" }

# 1. Multilinguale .pri ueberlagern (WinUI3Apps + Wurzel)
$priCount = 0
foreach ($sub in @('WinUI3Apps', '')) {
    $offDir = if ($sub) { Join-Path $OfficialRoot $sub } else { $OfficialRoot }
    $myDir  = if ($sub) { Join-Path $my $sub } else { $my }
    if (-not (Test-Path $offDir)) { continue }
    Get-ChildItem -Path $offDir -Filter *.pri -File | ForEach-Object {
        $dest = Join-Path $myDir $_.Name
        if (Test-Path $dest) { Copy-Item $_.FullName $dest -Force; $priCount++ }
    }
}
Write-Host "[GERMAN] $priCount multilinguale .pri ueberlagert."

# 2. de-DE-Satelliten der gewuenschten WPF-Module
$deTarget = Join-Path $my 'de-DE'
New-Item -ItemType Directory -Path $deTarget -Force | Out-Null
$wanted = @(
    'PowerToys.FancyZonesEditor.resources.dll',
    'PowerToys.PowerOCR.resources.dll',
    'PowerToys.WorkspacesEditor.resources.dll'
)
$offDe = Join-Path $OfficialRoot 'de-DE'
$copied = 0
foreach ($f in $wanted) {
    $src = Join-Path $offDe $f
    if (Test-Path $src) { Copy-Item $src $deTarget -Force; $copied++ }
    else { Write-Warning "de-DE-Satellit fehlt im offiziellen Release: $f" }
}
Write-Host "[GERMAN] $copied de-DE-Modul-Satelliten kopiert (ModernWpf-Satelliten baut der lokale Build selbst)."
