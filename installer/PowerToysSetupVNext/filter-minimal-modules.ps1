<#
.SYNOPSIS
Entfernt die Binaries nicht gewuenschter PowerToys-Module aus dem Build-Output, BEVOR der
WiX-Installer den Ausgabeordner "harvestet" (BaseApplicationsFiles / WinUI3ApplicationsFiles
sammeln alles in Release\ bzw. Release\WinUI3Apps\ ein).

Gewuenschte Module (bleiben): TextExtractor(PowerOCR), AlwaysOnTop, CropAndLock, FancyZones,
Workspaces, ImageResizer, FileLocksmith, PowerRename, Peek.

Es werden NUR .dll/.exe/.pdb in den beiden Catch-all-Wurzeln geloescht. Gemeinsame Bibliotheken
und drei von der Settings-UI zur Laufzeit benoetigte Modul-DLLs bleiben erhalten (KeepList).
#>
param(
    [string]$Platform = 'x64',
    [string]$Configuration = 'Release',
    [string]$RepoRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
)

$ErrorActionPreference = 'Stop'
$releaseRoot = Join-Path $RepoRoot "$Platform\$Configuration"
if (-not (Test-Path $releaseRoot)) { throw "Build-Output nicht gefunden: $releaseRoot" }
$winui = Join-Path $releaseRoot 'WinUI3Apps'

# Nur diese beiden (nicht-rekursiven) Ordner werden vom Installer-Catch-all erfasst:
$scopeDirs = @($releaseRoot, $winui) | Where-Object { Test-Path $_ }

# Glob-Muster der Binaries NICHT gewuenschter Module (case-insensitive).
$deny = @(
    'PowerToys.AdvancedPaste*',
    'PowerToys.Awake*',
    'PowerToys.Bgcode*',
    'PowerToys.CmdNotFound*',
    'PowerToys.CmdPal*',
    'Microsoft.CmdPal*',
    'Microsoft.CommandPalette*',       # nur .dll/.exe; .winmd bleibt (explizit paketiert)
    'PowerToys.ColorPicker*',
    'PowerToys.CursorWrap*',
    'PowerToys.EnvironmentVariables*',
    'PowerToys.FindMyMouse*',
    'PowerToys.Gcode*',
    'PowerToys.GrabAndMove*',
    'PowerToys.Hosts*',
    'PowerToys.KeyboardManager*',
    'PowerToys.Launcher*',             # PowerToys Run
    'PowerToys.LightSwitch*',
    'PowerToys.Markdown*',
    'PowerToys.MeasureTool*',          # Screen Ruler
    'PowerToys.MonacoPreviewHandler*', # Explorer-Vorschau-Handler (Peek nutzt FilePreviewCommon)
    'PowerToys.MouseHighlighter*',
    'PowerToys.MouseJump.dll',
    'PowerToys.MouseJumpUI*',
    'PowerToys.MousePointerCrosshairs*',
    'PowerToys.MouseWithoutBorders*',
    'PowerToys.NewPlus*',
    'PowerToys.Pdf*',
    'PowerToys.PowerAccent*',          # Quick Accent
    'PowerToys.PowerDisplay.dll',
    'PowerToys.PowerDisplay.exe',
    'PowerToys.PowerDisplayModuleInterface*',
    'PowerToys.PowerLauncher*',        # PowerToys Run
    'PowerToys.powerpreview*',         # Datei-Explorer-Add-ons (Vorschaufenster)
    'PowerToys.Qoi*',
    'PowerToys.RegistryPreview*',
    'PowerToys.ShortcutGuide*',
    'PowerToys.Stl*',
    'PowerToys.Svg*',
    'PowerToys.ZoomItModuleInterface*',
    'Wox.*'                            # PowerToys Run Framework
)

# Diese Dateien NIE loeschen — die Settings-UI laedt sie zur Laufzeit, obwohl das jeweilige
# Modul selbst nicht installiert wird (ProjectReferences von PowerToys.Settings.csproj).
$keep = @(
    'PowerToys.MouseJump.Common.dll',
    'PowerToys.ZoomItSettingsInterop.dll',
    'PowerDisplay.Models.dll'
) | ForEach-Object { $_.ToLowerInvariant() }

$exts = @('.dll', '.exe', '.pdb')
$deleted = 0
$keptExceptions = @()

foreach ($dir in $scopeDirs) {
    Get-ChildItem -Path $dir -File | ForEach-Object {
        $file = $_
        if ($exts -notcontains $file.Extension.ToLowerInvariant()) { return }
        $nameLower = $file.Name.ToLowerInvariant()
        $matched = $false
        foreach ($pat in $deny) { if ($file.Name -like $pat) { $matched = $true; break } }
        if (-not $matched) { return }
        if ($keep -contains $nameLower) { $keptExceptions += $file.Name; return }
        Remove-Item $file.FullName -Force
        Write-Host "  [-] $($file.FullName.Substring($releaseRoot.Length + 1))"
        $deleted++
    }
}

# Ganze Unterordner nicht gewuenschter Module (werden ohnehin nicht paketiert, aber wir raeumen auf).
$folders = @(
    (Join-Path $releaseRoot 'RunPlugins'),      # PowerToys Run Plugins
    (Join-Path $winui 'CmdPal')                 # Command Palette
)
foreach ($f in $folders) {
    if (Test-Path $f) { Remove-Item $f -Recurse -Force; Write-Host "  [-] Ordner: $($f.Substring($releaseRoot.Length + 1))" }
}

Write-Host ""
Write-Host "[FILTER] $deleted Datei(en) entfernt."
if ($keptExceptions.Count) { Write-Host "[FILTER] Als Settings-Abhaengigkeit behalten: $($keptExceptions -join ', ')" }
