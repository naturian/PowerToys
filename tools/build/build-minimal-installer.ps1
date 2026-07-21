<#
.SYNOPSIS
Baut einen MINIMIERTEN PowerToys-Installer (MSI), der nur diese 9 Module enthaelt:
  TextExtractor, Always on Top, Zuschneiden und Sperren (CropAndLock), FancyZones,
  Arbeitsbereiche (Workspaces), Bildgroessenaenderung (ImageResizer), File Locksmith,
  PowerRename, Vorschau (Peek).

Alle anderen Module werden NICHT paketiert (nicht installiert).

.DESCRIPTION
Fuehrt die komplette lokale Pipeline aus:
  1. Submodule initialisieren (spdlog, expected-lite)
  2. Solution bauen (nur benoetigte Projekte: Runner, Settings, gewuenschte Module)
  3. Diagnose-Tools bauen (BugReportTool, StylesReportTool)
  4. Build-Output filtern (Binaries nicht gewuenschter Module loeschen)
  5. WiX-MSI bauen

Voraussetzungen: VS 2022 (17.14+) mit C++-Desktop, .NET 9 SDK, WiX ist per NuGet enthalten.

.PARAMETER Platform     x64 (Standard) oder arm64
.PARAMETER Configuration Release (Standard)
.PARAMETER SkipSolutionBuild  Solution/Tools nicht neu bauen (nur Filter + Installer)
#>
param(
    [string]$Platform = 'x64',
    [string]$Configuration = 'Release',
    [switch]$SkipSolutionBuild
)
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$script:RepoRoot = $repoRoot
. "$repoRoot\tools\build\build-common.ps1"
if (-not (Ensure-VsDevEnvironment)) { throw 'Visual-Studio-Dev-Umgebung nicht gefunden.' }
Set-Location $repoRoot
$env:NUGET_PACKAGES = Join-Path $env:USERPROFILE '.nuget\packages'
$relax = '/p:NuGetAudit=false /p:TreatWarningsAsErrors=false /p:MSBuildTreatWarningsAsErrors=false /p:RunAnalyzersDuringBuild=false /p:WarningLevel=0'

# --- 1. Submodule ---
Write-Host '[1/5] Submodule initialisieren...'
git -C $repoRoot submodule update --init --depth 1

if (-not $SkipSolutionBuild) {
    # --- 2. Benoetigte Projekte bauen ---
    Write-Host '[2/5] Kernprojekte + gewuenschte Module bauen...'
    $projects = @(
        'src\runner\runner.vcxproj',
        'src\settings-ui\Settings.UI\PowerToys.Settings.csproj',
        'src\modules\PowerOCR\PowerOCRModuleInterface\PowerOCRModuleInterface.vcxproj',
        'src\modules\alwaysontop\AlwaysOnTopModuleInterface\AlwaysOnTopModuleInterface.vcxproj',
        'src\modules\CropAndLock\CropAndLockModuleInterface\CropAndLockModuleInterface.vcxproj',
        'src\modules\fancyzones\FancyZonesModuleInterface\FancyZonesModuleInterface.vcxproj',
        'src\modules\Workspaces\WorkspacesModuleInterface\WorkspacesModuleInterface.vcxproj',
        'src\modules\imageresizer\dll\ImageResizerExt.vcxproj',
        'src\modules\FileLocksmith\FileLocksmithExt\FileLocksmithExt.vcxproj',
        'src\modules\powerrename\dll\PowerRenameExt.vcxproj',
        'src\modules\peek\Peek.UI\Peek.UI.csproj'
    )
    foreach ($p in $projects) {
        if (Test-Path $p) { RunMSBuild $p "/m $relax" $Platform $Configuration }
        else { Write-Warning "Projekt nicht gefunden (uebersprungen): $p" }
    }

    # --- 3. Diagnose-Tools ---
    Write-Host '[3/5] Diagnose-Tools bauen...'
    foreach ($sln in @('tools\BugReportTool\BugReportTool.sln','tools\StylesReportTool\StylesReportTool.sln')) {
        RunMSBuild $sln "/t:restore /p:RestorePackagesConfig=true $relax" $Platform $Configuration
        RunMSBuild $sln "/m $relax" $Platform $Configuration
    }
}

# --- 4. Filter ---
Write-Host '[4/5] Build-Output filtern (nicht gewuenschte Module entfernen)...'
& "$repoRoot\installer\PowerToysSetupVNext\filter-minimal-modules.ps1" -Platform $Platform -Configuration $Configuration

# --- 5. Installer ---
Write-Host '[5/5] MSI bauen...'
$env:IsPipeline = '1'   # publish.cmd (Vorschau-Handler) ueberspringen
git -C $repoRoot checkout -- installer/PowerToysSetupVNext/*.wxs 2>$null
& powershell.exe -NonInteractive -ExecutionPolicy Unrestricted -File "$repoRoot\installer\PowerToysSetupVNext\generateAllFileComponents.ps1" -platform $Platform
RunMSBuild 'installer\PowerToysSetup.slnx' "/t:restore /p:RestorePackagesConfig=true $relax" $Platform $Configuration
RunMSBuild 'installer\PowerToysSetup.slnx' "/m /t:PowerToysInstallerVNext /p:PerUser=true $relax" $Platform $Configuration
git -C $repoRoot checkout -- installer/PowerToysSetupVNext/*.wxs 2>$null

$msi = Join-Path $repoRoot "installer\PowerToysSetupVNext\$Platform\$Configuration\UserSetup"
Write-Host ""
Write-Host "[FERTIG] MSI unter: $msi"
Get-ChildItem $msi -Filter *.msi -ErrorAction SilentlyContinue | ForEach-Object { Write-Host ("  {0} ({1:N0} MB)" -f $_.Name, ($_.Length/1MB)) }
