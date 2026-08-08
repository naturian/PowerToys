<#
.SYNOPSIS
Baut einen MINIMIERTEN PowerToys-Installer (MSI), der nur die Module aus
installer\PowerToysSetupVNext\selected-modules.txt enthaelt.

Alle nicht ausgewaehlten Module werden NICHT paketiert (nicht installiert).

.DESCRIPTION
Fuehrt die komplette lokale Pipeline aus:
  1. NuGet- und vcpkg-Abhaengigkeiten fuer die Solution wiederherstellen
  2. Solution ohne Tests bauen (vollstaendiger gemeinsamer Build-Output)
  3. Diagnose-Tools bauen (BugReportTool, StylesReportTool)
  4. Build-Output filtern (Binaries nicht gewuenschter Module loeschen)
  5. WiX-MSI bauen

Voraussetzungen: VS 2026 (empfohlen) oder VS 2022 17.4+ mit C++-Desktop und vcpkg,
.NET 10 SDK.
WiX ist per NuGet enthalten.

.PARAMETER Platform     x64 (Standard) oder arm64
.PARAMETER Configuration Release (Standard)
.PARAMETER Version      PowerToys-Version (Standard: 0.100.2)
.PARAMETER SkipSolutionBuild  Solution/Tools nicht neu bauen (nur Filter + Installer)
#>
param(
    [string]$Platform = 'x64',
    [string]$Configuration = 'Release',
    [string]$Version = '0.100.2',
    [switch]$SkipSolutionBuild
)
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$script:RepoRoot = $repoRoot
. "$repoRoot\tools\build\build-common.ps1"
if (-not (Ensure-VsDevEnvironment)) { throw 'Visual-Studio-Dev-Umgebung nicht gefunden.' }
Set-Location $repoRoot
$env:NUGET_PACKAGES = Join-Path $env:USERPROFILE '.nuget\packages'
$versionScript = Join-Path $repoRoot '.pipelines\versionSetting.ps1'
if (-not (Test-Path $versionScript)) { throw "Versionsskript nicht gefunden: $versionScript" }
$excludedVersionFiles = @(
    (Join-Path $repoRoot 'src\CmdPalVersion.props'),
    (Join-Path $repoRoot 'src\modules\NewPlus\NewShellExtensionContextMenu\AppxManifest.xml')
)
$preservedVersionBytes = @{}
foreach ($path in $excludedVersionFiles) { $preservedVersionBytes[$path] = [IO.File]::ReadAllBytes($path) }
try {
    & $versionScript -versionNumber $Version -DevEnvironment 'Local'
    if (-not $?) { throw "PowerToys-Version konnte nicht auf $Version gesetzt werden." }
}
finally {
    # Das offizielle Skript schreibt auch CmdPal/NewPlus um; beide sind hier
    # nicht waehlbar. Vorhandenen Inhalt daher bytegenau bewahren.
    foreach ($path in $excludedVersionFiles) { [IO.File]::WriteAllBytes($path, $preservedVersionBytes[$path]) }
}

$relax = '/p:NuGetAudit=false /p:TreatWarningsAsErrors=false /p:MSBuildTreatWarningsAsErrors=false /p:RunAnalyzersDuringBuild=false /p:WarningLevel=0'
$buildParallel = '/m:2 /p:CL_MPCount=2'

# --- 0. Modulauswahl anwenden (selected-modules.txt -> main.cpp / DashboardViewModel.cs / Product.wxs) ---
Write-Host '[0/5] Modulauswahl aus selected-modules.txt anwenden...'
& "$repoRoot\installer\PowerToysSetupVNext\Configure-Modules.ps1" -RepoRoot $repoRoot

# --- 1. Abhaengigkeiten wiederherstellen ---
Write-Host '[1/5] NuGet- und vcpkg-Abhaengigkeiten wiederherstellen...'
RestoreThenBuild 'PowerToys.slnx' $relax $Platform $Configuration $true

if (-not $SkipSolutionBuild) {
    # --- 2. Solution bauen ---
    # Viele Projekte verwenden $(SolutionDir) fuer den gemeinsamen Ausgabeordner.
    # Ein isolierter Projekt-Build legt Artefakte sonst unter src\...\x64 ab und
    # laesst vom Installer benoetigte Begleitprogramme sowie Assets aus.
    Write-Host '[2/5] Solution ohne Tests bauen...'
    RunMSBuild 'PowerToys.slnx' "$buildParallel /p:BuildTests=false $relax" $Platform $Configuration

    # --- 3. Diagnose-Tools ---
    Write-Host '[3/5] Diagnose-Tools bauen...'
    foreach ($sln in @('tools\BugReportTool\BugReportTool.sln','tools\StylesReportTool\StylesReportTool.sln')) {
        RunMSBuild $sln "/t:restore /p:RestorePackagesConfig=true $relax" $Platform $Configuration
        RunMSBuild $sln "$buildParallel $relax" $Platform $Configuration
    }
}

# --- 4. Filter ---
Write-Host '[4/5] Build-Output filtern (nicht gewuenschte Module entfernen)...'
& "$repoRoot\installer\PowerToysSetupVNext\filter-minimal-modules.ps1" -Platform $Platform -Configuration $Configuration

# --- 5. Installer ---
Write-Host '[5/5] MSI bauen...'
$env:IsPipeline = '1'   # publish.cmd (Vorschau-Handler) ueberspringen
git -C $repoRoot checkout -- installer/PowerToysSetupVNext/*.wxs 2>$null
# Product.wxs ist ebenfalls von der Auswahl abgeleitet und wurde durch checkout
# auf den Git-Stand zurueckgesetzt. Vor Harvest/MSI daher erneut konfigurieren.
& "$repoRoot\installer\PowerToysSetupVNext\Configure-Modules.ps1" -RepoRoot $repoRoot
& powershell.exe -NonInteractive -ExecutionPolicy Unrestricted -File "$repoRoot\installer\PowerToysSetupVNext\generateAllFileComponents.ps1" -platform $Platform
RunMSBuild 'installer\PowerToysSetup.slnx' "/t:restore /p:RestorePackagesConfig=true $relax" $Platform $Configuration
RunMSBuild 'installer\PowerToysSetup.slnx' "$buildParallel /t:PowerToysInstallerVNext /p:PerUser=true $relax" $Platform $Configuration
git -C $repoRoot checkout -- installer/PowerToysSetupVNext/*.wxs 2>$null
# Den Arbeitsbaum wieder passend zu selected-modules.txt hinterlassen.
& "$repoRoot\installer\PowerToysSetupVNext\Configure-Modules.ps1" -RepoRoot $repoRoot

$msi = Join-Path $repoRoot "installer\PowerToysSetupVNext\$Platform\$Configuration\UserSetup"
Write-Host ""
Write-Host "[FERTIG] MSI unter: $msi"
Get-ChildItem $msi -Filter *.msi -ErrorAction SilentlyContinue | ForEach-Object { Write-Host ("  {0} ({1:N0} MB)" -f $_.Name, ($_.Length/1MB)) }
