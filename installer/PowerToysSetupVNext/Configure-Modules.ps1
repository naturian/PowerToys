<#
.SYNOPSIS
Konfiguriert den minimierten Installer aus selected-modules.txt: stempelt die GENERATED-Marker
in main.cpp (Runner), DashboardViewModel.cs (Settings), Product.wxs und dem WiX-Projekt.

.DESCRIPTION
Einzige Wahrheitsquelle ist selected-modules.txt + Modules-Database.ps1. Nach dem Ausfuehren
muessen Runner + Settings neu gebaut und der Filter/Installer neu erzeugt werden
(erledigt build-minimal-installer.ps1).
#>
param(
    [string]$RepoRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [string]$ConfigFile
)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
. (Join-Path $here 'Modules-Database.ps1')
if (-not $ConfigFile) { $ConfigFile = Join-Path $here 'selected-modules.txt' }

# --- Auswahl einlesen ---
$selected = Get-Content $ConfigFile | ForEach-Object { ($_ -replace '#.*$', '').Trim() } | Where-Object { $_ -ne '' }
if (-not $selected) { throw "Keine Module in $ConfigFile ausgewaehlt." }

$unknown = $selected | Where-Object { -not $ModuleDatabase.Contains($_) }
if ($unknown) { throw "Unbekannte Modul-Schluessel: $($unknown -join ', ')`nGueltige: $($ModuleDatabase.Keys -join ', ')" }

$notBuildable = $selected | Where-Object { -not $ModuleDatabase[$_].Buildable }
if ($notBuildable) { throw "Nicht in der Minimal-Pipeline baubar: $($notBuildable -join ', '). Bitte aus $ConfigFile entfernen." }

Write-Host "[CONFIG] Ausgewaehlte Module ($($selected.Count)): $($selected -join ', ')"

# --- Ableitungen ---
$runnerDlls = [System.Collections.Generic.List[string]]::new()
$moduleTypes = [System.Collections.Generic.List[string]]::new()
$wixGroups = [System.Collections.Generic.List[string]]::new()
$wixSources = [System.Collections.Generic.List[string]]::new()
$needMonaco = $false
foreach ($k in $selected) {
    $m = $ModuleDatabase[$k]
    $m.RunnerDlls   | ForEach-Object { if ($runnerDlls -notcontains $_) { $runnerDlls.Add($_) } }
    $m.ModuleTypes  | ForEach-Object { if ($moduleTypes -notcontains $_) { $moduleTypes.Add($_) } }
    $m.WixGroups    | ForEach-Object { if ($wixGroups -notcontains $_) { $wixGroups.Add($_) } }
    if ($m.WixGroups.Count -gt 0) {
        $wixSource = "$k.wxs"
        if (-not (Test-Path -LiteralPath (Join-Path $here $wixSource))) {
            throw "WiX-Quelle fuer $k nicht gefunden: $wixSource"
        }
        if ($wixSources -notcontains $wixSource) { $wixSources.Add($wixSource) }
    }
    if ($m.NeedsMonaco) { $needMonaco = $true }
}
if ($needMonaco) {
    # Monaco-Assets liegen in FileExplorerPreview.wxs + MonacoSRC.wxs
    foreach ($g in @('MonacoSRCHeatGenerated', 'FileExplorerPreviewComponentGroup')) {
        if ($wixGroups -notcontains $g) { $wixGroups.Insert(0, $g) }
    }
    foreach ($source in @('MonacoSRC.wxs', 'FileExplorerPreview.wxs')) {
        if ($wixSources -notcontains $source) { $wixSources.Insert(0, $source) }
    }
}

# --- Marker-Ersetzung ---
function Set-GeneratedRegion([string]$Path, [string]$Indent, [string[]]$Lines) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    $hasUtf8Bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $offset = if ($hasUtf8Bom) { 3 } else { 0 }
    $content = [Text.Encoding]::UTF8.GetString($bytes, $offset, $bytes.Length - $offset)
    $newLine = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
    $begin = [regex]::Escape('BEGIN_GENERATED_MODULES')
    $end = [regex]::Escape('END_GENERATED_MODULES')
    $pattern = "(?s)(.*?$begin[^\r\n]*\r?\n).*?(\s*[^\r\n]*$end)"
    $match = [regex]::Match($content, $pattern, [Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $match.Success) { throw "GENERATED-Marker nicht gefunden in $Path" }
    $body = ($Lines | ForEach-Object { if ($_ -eq '') { '' } else { "$Indent$_" } }) -join $newLine
    $existingBodyStart = $match.Groups[1].Index + $match.Groups[1].Length
    $existingBody = $content.Substring($existingBodyStart, $match.Groups[2].Index - $existingBodyStart)
    if (($existingBody -replace "`r`n", "`n") -ceq ($body -replace "`r`n", "`n")) {
        Write-Host "  [OK] $([IO.Path]::GetFileName($Path)) unveraendert."
        return
    }
    $new = [regex]::Replace($content, $pattern, { param($mm) $mm.Groups[1].Value + $body + $newLine + $mm.Groups[2].Value.TrimStart("`r","`n") }, [Text.RegularExpressions.RegexOptions]::Singleline)
    $encoding = [Text.UTF8Encoding]::new($hasUtf8Bom)
    [IO.File]::WriteAllText($Path, $new, $encoding)
    Write-Host "  [OK] $([IO.Path]::GetFileName($Path)) aktualisiert."
}

# 1) Runner (main.cpp)
$runnerLines = $runnerDlls | ForEach-Object { "L`"$_`"," }
Set-GeneratedRegion (Join-Path $RepoRoot 'src\runner\main.cpp') '            ' $runnerLines

# 2) Dashboard (DashboardViewModel.cs)
$dashLines = @($moduleTypes | Sort-Object | ForEach-Object { "ModuleType.$_," }) + ''
Set-GeneratedRegion (Join-Path $RepoRoot 'src\settings-ui\Settings.UI\ViewModels\DashboardViewModel.cs') '            ' $dashLines

# Tray quick access must honor the same package selection, including old user settings.
Set-GeneratedRegion (Join-Path $RepoRoot 'src\settings-ui\Settings.UI.Controls\QuickAccess\QuickAccessViewModel.cs') '            ' $dashLines

# 3) WiX (Product.wxs)
$wixLines = $wixGroups | ForEach-Object { "<ComponentGroupRef Id=`"$_`" />" }
Set-GeneratedRegion (Join-Path $RepoRoot 'installer\PowerToysSetupVNext\Product.wxs') '      ' $wixLines

# 4) Nur die fuer die Auswahl benoetigten WiX-Quelldateien kompilieren.
$wixSourceLines = $wixSources | ForEach-Object { "<Compile Include=`"$_`" />" }
Set-GeneratedRegion (Join-Path $RepoRoot 'installer\PowerToysSetupVNext\PowerToysInstallerVNext.wixproj') '    ' $wixSourceLines

# CmdPal ist in der Minimal-Pipeline nicht waehlbar. Upstream legt seine WinMD
# trotzdem in BaseApplications ab; ohne Bereinigung wuerde sie mitpaketiert.
$baseApplicationsPath = Join-Path $RepoRoot 'installer\PowerToysSetupVNext\BaseApplications.wxs'
$baseBytes = [IO.File]::ReadAllBytes($baseApplicationsPath)
$baseHasBom = $baseBytes.Length -ge 3 -and $baseBytes[0] -eq 0xEF -and $baseBytes[1] -eq 0xBB -and $baseBytes[2] -eq 0xBF
$baseOffset = if ($baseHasBom) { 3 } else { 0 }
$baseContent = [Text.Encoding]::UTF8.GetString($baseBytes, $baseOffset, $baseBytes.Length - $baseOffset)
$baseContent = [regex]::Replace(
    $baseContent,
    '(?s)\s*<!-- winmd must be in WinUI3Apps.*?<DirectoryRef Id="WinUI3AppsInstallFolder">.*?</DirectoryRef>',
    '')
$baseContent = [regex]::Replace(
    $baseContent,
    '\s*<ComponentRef Id="Microsoft_CommandPalette_Extensions_winmd"\s*/>',
    '')
[IO.File]::WriteAllText($baseApplicationsPath, $baseContent, [Text.UTF8Encoding]::new($baseHasBom))
Write-Host '  [OK] BaseApplications.wxs von CmdPal-WinMD bereinigt.'

Write-Host "[CONFIG] Fertig. Jetzt Runner + Settings neu bauen und Installer erzeugen (build-minimal-installer.ps1)."
