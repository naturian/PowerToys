[CmdletBinding()]
param(
    [ValidateSet('FancyZones', 'ColorPicker', 'TextExtractor', 'ImageResizer', 'PowerDisplay', 'AlwaysOnTop', 'FileLocksmith', 'Peek', 'CropAndLock', 'AdvancedPaste')]
    [string[]]$Modules = @('FancyZones', 'ColorPicker', 'TextExtractor', 'ImageResizer', 'PowerDisplay', 'AlwaysOnTop', 'FileLocksmith', 'Peek', 'CropAndLock', 'AdvancedPaste'),
    [string]$OutputRoot,
    [switch]$Resume
)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
if (-not $OutputRoot) { $OutputRoot = Join-Path $repoRoot ('artifacts\portable\' + (Get-Date -Format 'yyyyMMdd-HHmmss')) }
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
if ((Test-Path -LiteralPath $OutputRoot) -and -not $Resume) { throw "Use a new output directory: $OutputRoot" }
[void][IO.Directory]::CreateDirectory($OutputRoot)
$env:NUGET_PACKAGES = Join-Path $repoRoot '.build-cache\nuget'
$env:Path = (($env:Path -split ';' | ForEach-Object { $_.Trim('"') }) -join ';')
$projects = @{
    FancyZones = @{ Directory = 'src\modules\fancyzones\editor\FancyZonesEditor'; Assembly = 'PowerToys.FancyZonesEditor'; Name = 'FancyZones'; Icon = 'src\modules\fancyzones\FancyZonesLib\icon.ico' }
    ColorPicker = @{ Directory = 'src\modules\colorPicker\ColorPickerUI'; Assembly = 'PowerToys.ColorPickerUI'; Name = 'Farbwähler'; Icon = 'src\modules\colorPicker\ColorPickerUI\Assets\ColorPicker\icon.ico' }
    TextExtractor = @{ Directory = 'src\modules\PowerOCR\PowerOCR'; Assembly = 'PowerToys.PowerOCR'; Name = 'Textextraktor'; Icon = 'src\modules\PowerOCR\PowerOCR\Assets\PowerOCR\PowerOCR.ico' }
    ImageResizer = @{ Directory = 'src\modules\imageresizer\ui'; Assembly = 'PowerToys.ImageResizer'; Name = 'Bildgrößenänderung'; Icon = 'src\modules\imageresizer\ui\Assets\ImageResizer\ImageResizer.ico' }
    PowerDisplay = @{ Directory = 'src\modules\powerdisplay\PowerDisplay'; Assembly = 'PowerToys.PowerDisplay'; Name = 'Power Display'; Icon = 'src\modules\powerdisplay\PowerDisplay\Assets\PowerDisplay\PowerDisplay.ico' }
    AlwaysOnTop = @{ Directory = 'src\modules\alwaysontop\AlwaysOnTop'; Assembly = 'PowerToys.AlwaysOnTop'; Name = 'Immer im Vordergrund'; Icon = 'src\modules\alwaysontop\Assets\AlwaysOnTop.ico'; Native = $true }
    FileLocksmith = @{ Directory = 'src\modules\FileLocksmith\FileLocksmithUI'; Assembly = 'PowerToys.FileLocksmithUI'; Name = 'Dateischlosser'; Icon = 'src\modules\FileLocksmith\FileLocksmithUI\Assets\FileLocksmith\Icon.ico' }
    Peek = @{ Directory = 'src\modules\peek\Peek.UI'; Assembly = 'PowerToys.Peek.UI'; Name = 'Peek'; Icon = 'src\modules\peek\Peek.UI\Assets\Peek\Icon.ico' }
    CropAndLock = @{ Directory = 'src\modules\CropAndLock\CropAndLock'; Assembly = 'PowerToys.CropAndLock'; Name = 'Zuschneiden und Sperren'; Icon = 'src\modules\CropAndLock\CropAndLock\icon1.ico'; Native = $true }
    AdvancedPaste = @{ Directory = 'src\modules\AdvancedPaste\AdvancedPaste'; Assembly = 'PowerToys.AdvancedPaste'; Name = 'Erweitertes Einfügen'; Icon = 'src\modules\AdvancedPaste\AdvancedPaste\Assets\AdvancedPaste\AdvancedPaste.ico' }
}
$settingsDestination = Join-Path $OutputRoot '_settings'
$settingsDirectory = Join-Path $repoRoot 'src\settings-ui\Settings.UI'
Push-Location -LiteralPath $settingsDirectory
try
{
    & (Join-Path $repoRoot 'tools\build\build.ps1') -Platform x64 -Configuration Release -Path $settingsDirectory -ExtraArgs @(
        '/restore', '/t:Publish', '/p:BuildTests=false', "/p:SolutionDir=$repoRoot\", '/p:RuntimeIdentifier=win-x64',
        '/p:SelfContained=true', '/p:WindowsPackageType=None', '/p:PublishSingleFile=false', '/p:PublishTrimmed=false',
        '/p:PublishAot=false', '/p:RunAnalyzersDuringBuild=false', '/p:GenerateSettingsSearchIndex=false', '/p:NuGetAudit=false', '/m:2', '/p:CL_MPCount=2', "/p:PublishDir=$settingsDestination\")
    if ($LASTEXITCODE -ne 0) { throw "Portable settings publish failed (exit $LASTEXITCODE)" }
}
finally { Pop-Location }
$settingsApps = @(Get-ChildItem -LiteralPath $settingsDestination -Filter '*.exe' | Where-Object Name -notin @('PowerToys.Settings.exe', 'createdump.exe', 'RestartAgent.exe'))
if ($settingsApps.Count) { throw "Unexpected application in settings payload: $($settingsApps.Name -join ', ')" }
$results = [Collections.Generic.List[object]]::new()
if ($Resume -and (Test-Path -LiteralPath (Join-Path $OutputRoot 'build-results.json')))
{
    foreach ($previous in @(Get-Content -LiteralPath (Join-Path $OutputRoot 'build-results.json') -Raw | ConvertFrom-Json))
    {
        if ($previous.module -notin $Modules -and $previous.buildExitCode -eq 0)
        {
            $results.Add($previous)
        }
    }
}
foreach ($module in $Modules)
{
    $project = $projects[$module]
    $destination = Join-Path $OutputRoot $module
    [void][IO.Directory]::CreateDirectory($destination)
    [IO.File]::WriteAllText((Join-Path $OutputRoot 'progress.txt'), "Building $module")
    $arguments = @('/restore', '/t:Publish', '/p:BuildTests=false', "/p:SolutionDir=$repoRoot\",
        '/p:RuntimeIdentifier=win-x64', '/p:SelfContained=true',
        '/p:WindowsPackageType=None', '/p:PublishSingleFile=false', '/p:PublishTrimmed=false',
        '/p:PublishAot=false', '/p:RunAnalyzersDuringBuild=false', '/p:NuGetAudit=false',
        '/m:2', '/p:CL_MPCount=2', "/p:PublishDir=$destination\")
    $directory = Join-Path $repoRoot $project.Directory
    if ($module -eq 'FancyZones')
    {
        $engineDirectory = Join-Path $repoRoot 'src\modules\fancyzones\FancyZones'
        Push-Location -LiteralPath $engineDirectory
        try
        {
            & (Join-Path $repoRoot 'tools\build\build.ps1') -Platform x64 -Configuration Release -Path $engineDirectory -ExtraArgs @('/restore', '/p:BuildTests=false', "/p:SolutionDir=$repoRoot\", '/m:2', '/p:CL_MPCount=2', '/p:NuGetAudit=false')
            if ($LASTEXITCODE -ne 0) { throw "FancyZones engine build failed (exit $LASTEXITCODE)" }
        }
        finally { Pop-Location }
    }
    Push-Location -LiteralPath $directory
    try
    {
        if ($project.Native)
        {
            $arguments = @('/restore', '/p:BuildTests=false', "/p:SolutionDir=$repoRoot\", '/m:2', '/p:CL_MPCount=2', '/p:NuGetAudit=false')
        }

        & (Join-Path $repoRoot 'tools\build\build.ps1') -Platform x64 -Configuration Release -Path $directory -ExtraArgs $arguments
        if ($LASTEXITCODE -ne 0) { throw "Publish failed for $module (exit $LASTEXITCODE)" }
        if ($project.Native)
        {
            Copy-Item -LiteralPath (Join-Path $repoRoot ("x64\Release\" + $project.Assembly + '.exe')) -Destination $destination -Force
        }
    }
    finally { Pop-Location }

    $requiredFiles = @($project.Assembly + '.exe')
    if (-not $project.Native)
    {
        $requiredFiles += @('.dll', '.runtimeconfig.json') | ForEach-Object { $project.Assembly + $_ }
        $requiredFiles += @('PowerToys.ManagedCommon.dll', 'PowerToys.Interop.dll', 'hostfxr.dll', 'coreclr.dll')
    }
    if ($module -ne 'FancyZones' -and -not $project.Native)
    {
        $requiredFiles += @($project.Assembly + '.pri')
        $requiredFiles += @('PowerToys.GPOWrapper.dll', 'Microsoft.UI.Xaml.dll')
    }
    foreach ($file in $requiredFiles)
    {
        if (-not (Test-Path -LiteralPath (Join-Path $destination $file) -PathType Leaf)) { throw "Missing $module dependency: $file" }
    }
    $allowedApps = @($project.Assembly + '.exe') + @('PowerToys.Settings.exe', 'PowerToys.Portable.exe')
    if ($module -eq 'FancyZones') { $allowedApps += 'PowerToys.FancyZones.exe' }
    $otherApps = @(Get-ChildItem -LiteralPath $destination -Filter 'PowerToys*.exe' | Where-Object Name -notin $allowedApps)
    if ($otherApps.Count) { throw "Unexpected other PowerToys executable in $module package: $($otherApps.Name -join ', ')" }
    if ($module -eq 'FancyZones')
    {
        Copy-Item -LiteralPath (Join-Path $repoRoot 'x64\Release\PowerToys.FancyZones.exe') -Destination $destination
        if (-not (Test-Path -LiteralPath (Join-Path $destination 'de-DE\PowerToys.FancyZonesEditor.resources.dll'))) { throw 'FancyZones German satellite missing' }
    }
    $dataRoot = Join-Path $destination 'Data\Microsoft\PowerToys'
    [void][IO.Directory]::CreateDirectory($dataRoot)
    [IO.File]::WriteAllText((Join-Path $destination 'portable-mode'), '', [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $dataRoot 'language.json'), '{"language":"de-DE"}', [Text.UTF8Encoding]::new($false))
    $settingsModuleName = if ($module -eq 'ImageResizer') { 'Image Resizer' } elseif ($module -eq 'FileLocksmith') { 'File Locksmith' } else { $module }
    $generalProfile = @{ enabled = @{ $settingsModuleName = $true }; theme = 'system'; startup = $false; download_updates_automatically = $false; enable_experimentation = $false }
    $generalProfilePath = Join-Path $dataRoot 'settings.json'
    if (-not (Test-Path -LiteralPath $generalProfilePath)) {
        [IO.File]::WriteAllText($generalProfilePath, ($generalProfile | ConvertTo-Json -Depth 4 -Compress), [Text.UTF8Encoding]::new($false))
    }
    Get-ChildItem -LiteralPath $settingsDestination | Copy-Item -Destination $destination -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $settingsDestination 'PowerToys.Settings.exe') -Destination (Join-Path $destination 'PowerToys.Portable.exe')
    # WinUI resolves page resources by the process name, including a renamed apphost.
    Copy-Item -LiteralPath (Join-Path $settingsDestination 'PowerToys.Settings.pri') -Destination (Join-Path $destination 'PowerToys.Portable.pri')
    Copy-Item -LiteralPath (Join-Path $repoRoot $project.Icon) -Destination (Join-Path $destination 'portable.ico')
    [IO.File]::WriteAllText((Join-Path $destination 'portable-module.json'), (@{module=$module} | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
    $entryPoint = if ($module -eq 'PowerDisplay') { 'PowerToys.PowerDisplay.exe' } else { 'PowerToys.Portable.exe' }
    if ($module -ne 'PowerDisplay')
    {
        [IO.File]::WriteAllText((Join-Path $destination 'Beenden.cmd'), '@"%~dp0PowerToys.Portable.exe" --stop' + [Environment]::NewLine, [Text.Encoding]::ASCII)
    }
    $readme = @"
$($project.Name) — experimentelles Portable-Paket (Windows x64)

Gesamten Ordner entpacken. $entryPoint starten.
Keine PowerToys-Installation und kein PowerToys-Runner erforderlich.
Alle mitgelieferten Dateien gehören zum Programm; nicht nur die EXE kopieren.
Der Ordner muss beschreibbar sein. Die Datei portable-mode aktiviert die
getrennten Daten unter Data\Microsoft\PowerToys. Diese Datei nicht entfernen.
Sprache: Data\Microsoft\PowerToys\language.json (de-DE).
Das Tray-Symbol bietet Öffnen, Einstellungen und Beenden. Die grafischen
Einstellungen verwenden die originale PowerToys-Seite dieses Moduls.
Schließen des Einstellungsfensters lässt das Werkzeug im Tray weiterlaufen.
Power Display verwendet sein eigenes Tray-Menü; PowerToys.Portable.exe öffnet
dort die Einstellungen. Einstellungen werden automatisch lokal gespeichert.
Zum Mitnehmen oder Verschieben zuerst das Programm vollständig beenden.
Zum Entfernen den beendeten Programmordner löschen.

Farbwähler/Textextraktor: erneutes Starten aktiviert dieselbe portable Instanz.
Vorhandene globale PowerToys-Tastenkürzel können mit installierten Werkzeugen
kollidieren. Für einen ersten Test installierten Farbwähler/Textextraktor beenden.
Textextraktor benötigt eine vorhandene Windows-OCR-Sprache. Windows verwaltet
Zwischenablage und Ausführungsspuren selbst; diese sind nicht im Datenordner.
Bildgrößenänderung: Dateien auf die EXE ziehen oder im Auswahldialog auswählen.
Originalbilder nur ersetzen, wenn dies ausdrücklich im Werkzeug ausgewählt wird.
Power Display: Änderungen an Helligkeit/Farbe wirken auf die angeschlossene
Hardware. Erst prüfen, bevor Einstellungen verändert werden.
FancyZones: PowerToys.Portable.exe startet Engine, Tray und Einstellungen.
Den Layout-Editor über das Tray-Menü oder die Einstellungen öffnen.
Zum Beenden das Tray-Menü oder Beenden.cmd verwenden.
Installiertes FancyZones
muss währenddessen ausgeschaltet sein; dieselben Fenster können sonst von
beiden Instanzen angeordnet werden. Zuerst mit eigenen Testfenstern prüfen.

Eigener unsignierter Versuchsbuild auf Basis 0.102.3001.0. Keine Firmenfreigabe.
Quellcode und Lizenzen: https://github.com/naturian/PowerToys
"@
    [IO.File]::WriteAllText((Join-Path $destination 'README.txt'), $readme, [Text.UTF8Encoding]::new($false))
    foreach ($notice in @('LICENSE', 'NOTICE.md'))
    {
        Copy-Item -LiteralPath (Join-Path $repoRoot $notice) -Destination $destination
    }
    $files = @(Get-ChildItem -LiteralPath $destination -Recurse -File | Where-Object { $_.Name -ne 'package-manifest.json' } | ForEach-Object {
        [pscustomobject][ordered]@{ path = $_.FullName.Substring($destination.TrimEnd('\').Length + 1); bytes = $_.Length; sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
    })
    $manifest = [ordered]@{ module = $module; version = '0.102.3001.0'; experimental = $true; entryPoint = $entryPoint; files = $files }
    [IO.File]::WriteAllText((Join-Path $destination 'package-manifest.json'), ($manifest | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
    $results.Add([ordered]@{ module = $module; path = $destination; files = $files.Count; bytes = ($files | Measure-Object -Property bytes -Sum).Sum; buildExitCode = 0 })
    [IO.File]::WriteAllText((Join-Path $OutputRoot 'build-results.json'), (ConvertTo-Json -InputObject @($results.ToArray()) -Depth 5), [Text.UTF8Encoding]::new($false))
}
[IO.File]::WriteAllText((Join-Path $OutputRoot 'progress.txt'), 'PUBLISH_COMPLETE')
Write-Host "PORTABLE_PUBLISH_COMPLETE=$OutputRoot"
