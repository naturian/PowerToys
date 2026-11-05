[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BuildRoot,
    [Parameter(Mandatory)][string]$ReceiptPath,
    [ValidateSet('FancyZones','ColorPicker','TextExtractor','ImageResizer','PowerDisplay','AlwaysOnTop','FileLocksmith','Peek','CropAndLock','AdvancedPaste')]
    [string[]]$Modules = @('FancyZones','ColorPicker','TextExtractor','ImageResizer','PowerDisplay','AlwaysOnTop','FileLocksmith','Peek','CropAndLock','AdvancedPaste')
)

$ErrorActionPreference = 'Stop'
$BuildRoot = [IO.Path]::GetFullPath($BuildRoot)
$names = @{ FancyZones='FancyZones'; ColorPicker='Farbwähler'; TextExtractor='Textextraktor'; ImageResizer='Bildgrößenänderung'; PowerDisplay='Power Display'; AlwaysOnTop='Immer im Vordergrund'; FileLocksmith='Dateischlosser'; Peek='Peek'; CropAndLock='Zuschneiden und Sperren'; AdvancedPaste='Erweitertes Einfügen' }
$children = @{ FancyZones='PowerToys.FancyZones'; ColorPicker='PowerToys.ColorPickerUI'; TextExtractor='PowerToys.PowerOCR'; AlwaysOnTop='PowerToys.AlwaysOnTop'; CropAndLock='PowerToys.CropAndLock'; AdvancedPaste='PowerToys.AdvancedPaste' }
$receipts = [Collections.Generic.List[object]]::new()

function Get-PackageProcesses([string]$Directory, [string]$Name) {
    @(Get-Process -Name $Name -ErrorAction SilentlyContinue | Where-Object {
        try { [string]::Equals($_.Path, (Join-Path $Directory ($Name + '.exe')), [StringComparison]::OrdinalIgnoreCase) } catch { $false }
    })
}

foreach ($module in $Modules) {
    $directory = Join-Path $BuildRoot $module
    $executable = Join-Path $directory 'PowerToys.Portable.exe'
    $expectedTitle = $names[$module] + ' Portable – Einstellungen'
    if ((Get-PackageProcesses $directory 'PowerToys.Portable').Count) { throw "Close the existing portable test instance first: $module" }
    $primary = Start-Process -FilePath $executable -WorkingDirectory $directory -WindowStyle Hidden -PassThru
    try {
        for ($attempt=0; $attempt -lt 60; $attempt++) {
            Start-Sleep -Milliseconds 250
            $primary.Refresh()
            if ($primary.HasExited) { throw "Portable host exited on startup: $module" }
            if ($primary.MainWindowTitle -eq $expectedTitle) { break }
        }
        if ($primary.MainWindowTitle -ne $expectedTitle) { throw "Settings page did not open for $module. Actual title: $($primary.MainWindowTitle)" }
        if ($children.ContainsKey($module)) {
            for ($attempt=0; $attempt -lt 40 -and -not (Get-PackageProcesses $directory $children[$module]).Count; $attempt++) { Start-Sleep -Milliseconds 250 }
            if (-not (Get-PackageProcesses $directory $children[$module]).Count) { throw "Background module did not start: $module" }
        }

        $secondary = Start-Process -FilePath $executable -ArgumentList '--settings' -WorkingDirectory $directory -WindowStyle Hidden -PassThru
        if (-not $secondary.WaitForExit(10000) -or $secondary.ExitCode -ne 0) { throw "Second settings launch did not redirect: $module" }
        if ((Get-PackageProcesses $directory 'PowerToys.Portable').Count -ne 1) { throw "Duplicate portable host: $module" }

        if ($module -eq 'FancyZones') {
            $open = Start-Process -FilePath $executable -ArgumentList '--open' -WorkingDirectory $directory -WindowStyle Hidden -PassThru
            if (-not $open.WaitForExit(10000)) { throw 'Editor request did not redirect.' }
            for ($attempt=0; $attempt -lt 60 -and -not (Get-PackageProcesses $directory 'PowerToys.FancyZonesEditor').Count; $attempt++) { Start-Sleep -Milliseconds 250 }
            if (-not (Get-PackageProcesses $directory 'PowerToys.FancyZonesEditor').Count) { throw 'FancyZones editor did not start from the portable package.' }
        }
        $title = $primary.MainWindowTitle
    }
    finally {
        $stop = Start-Process -FilePath $executable -ArgumentList '--stop' -WorkingDirectory $directory -WindowStyle Hidden -PassThru
        if (-not $stop.WaitForExit(10000)) { throw "Stop request did not redirect: $module" }
    }

    if (-not $primary.WaitForExit(10000)) { throw "Portable host did not shut down: $module" }
    if ($primary.ExitCode -ne 0) { throw "Portable host failed: $module (exit $($primary.ExitCode))" }
    if ($children.ContainsKey($module) -and (Get-PackageProcesses $directory $children[$module]).Count) { throw "Background module remains running: $module" }
    if ($module -eq 'FancyZones' -and (Get-PackageProcesses $directory 'PowerToys.FancyZonesEditor').Count) { throw 'FancyZones editor remains running.' }
    $receipts.Add([pscustomobject][ordered]@{ module=$module; settingsTitle=$title; secondLaunchRedirected=$true; cleanExit=$true; exitCode=$primary.ExitCode })
    Write-Host "PASS $module - settings, single instance, clean exit"
    [IO.File]::WriteAllText($ReceiptPath, (ConvertTo-Json -InputObject @($receipts.ToArray()) -Depth 5), [Text.UTF8Encoding]::new($false))
}
