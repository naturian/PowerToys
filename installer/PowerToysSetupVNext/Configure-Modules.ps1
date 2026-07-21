<#
.SYNOPSIS
Konfiguriert den minimierten Installer aus selected-modules.txt: stempelt die GENERATED-Marker
in main.cpp (Runner), DashboardViewModel.cs (Settings) und Product.wxs (WiX).

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
if ($notBuildable) { throw "Nicht baubar in dieser Umgebung (VS 2026 noetig): $($notBuildable -join ', '). Bitte aus $ConfigFile entfernen." }

Write-Host "[CONFIG] Ausgewaehlte Module ($($selected.Count)): $($selected -join ', ')"

# --- Ableitungen ---
$runnerDlls = [System.Collections.Generic.List[string]]::new()
$moduleTypes = [System.Collections.Generic.List[string]]::new()
$wixGroups = [System.Collections.Generic.List[string]]::new()
$needMonaco = $false
foreach ($k in $selected) {
    $m = $ModuleDatabase[$k]
    $m.RunnerDlls   | ForEach-Object { if ($runnerDlls -notcontains $_) { $runnerDlls.Add($_) } }
    $m.ModuleTypes  | ForEach-Object { if ($moduleTypes -notcontains $_) { $moduleTypes.Add($_) } }
    $m.WixGroups    | ForEach-Object { if ($wixGroups -notcontains $_) { $wixGroups.Add($_) } }
    if ($m.NeedsMonaco) { $needMonaco = $true }
}
if ($needMonaco) {
    # Monaco-Assets liegen in FileExplorerPreview.wxs + MonacoSRC.wxs
    foreach ($g in @('MonacoSRCHeatGenerated', 'FileExplorerPreviewComponentGroup')) {
        if ($wixGroups -notcontains $g) { $wixGroups.Insert(0, $g) }
    }
}

# --- Marker-Ersetzung ---
function Set-GeneratedRegion([string]$Path, [string]$Indent, [string[]]$Lines) {
    $content = Get-Content $Path -Raw
    $begin = [regex]::Escape('BEGIN_GENERATED_MODULES')
    $end = [regex]::Escape('END_GENERATED_MODULES')
    $pattern = "(?s)(.*?$begin[^\r\n]*\r?\n).*?(\s*[^\r\n]*$end)"
    if ($content -notmatch $pattern) { throw "GENERATED-Marker nicht gefunden in $Path" }
    $body = ($Lines | ForEach-Object { "$Indent$_" }) -join "`r`n"
    $new = [regex]::Replace($content, $pattern, { param($mm) $mm.Groups[1].Value + $body + "`r`n" + $mm.Groups[2].Value.TrimStart("`r","`n") }, [Text.RegularExpressions.RegexOptions]::Singleline)
    Set-Content -Path $Path -Value $new -NoNewline
    Write-Host "  [OK] $([IO.Path]::GetFileName($Path)) aktualisiert."
}

# 1) Runner (main.cpp)
$runnerLines = $runnerDlls | ForEach-Object { "L`"$_`"," }
Set-GeneratedRegion (Join-Path $RepoRoot 'src\runner\main.cpp') '            ' $runnerLines

# 2) Dashboard (DashboardViewModel.cs)
$dashLines = $moduleTypes | Sort-Object | ForEach-Object { "ModuleType.$_," }
Set-GeneratedRegion (Join-Path $RepoRoot 'src\settings-ui\Settings.UI\ViewModels\DashboardViewModel.cs') '            ' $dashLines

# 3) WiX (Product.wxs)
$wixLines = $wixGroups | ForEach-Object { "<ComponentGroupRef Id=`"$_`" />" }
Set-GeneratedRegion (Join-Path $RepoRoot 'installer\PowerToysSetupVNext\Product.wxs') '      ' $wixLines

Write-Host "[CONFIG] Fertig. Jetzt Runner + Settings neu bauen und Installer erzeugen (build-minimal-installer.ps1)."
