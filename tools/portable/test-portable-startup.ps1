[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BuildRoot,
    [Parameter(Mandatory)][string]$ReceiptPath,
    [switch]$Background,
    [ValidateSet('FancyZones','ColorPicker','TextExtractor','ImageResizer','PowerDisplay','AlwaysOnTop','FileLocksmith','Peek','CropAndLock','AdvancedPaste')]
    [string[]]$Modules = @('FancyZones','ColorPicker','TextExtractor','ImageResizer','PowerDisplay','AlwaysOnTop','FileLocksmith','Peek','CropAndLock','AdvancedPaste')
)

$ErrorActionPreference = 'Stop'
$BuildRoot = [IO.Path]::GetFullPath($BuildRoot)
$names = @{ FancyZones='FancyZones'; ColorPicker='Farbwähler'; TextExtractor='Textextraktor'; ImageResizer='Bildgrößenänderung'; PowerDisplay='Power Display'; AlwaysOnTop='Immer im Vordergrund'; FileLocksmith='Dateischlosser'; Peek='Peek'; CropAndLock='Zuschneiden und Sperren'; AdvancedPaste='Erweitertes Einfügen' }
$children = @{ FancyZones='PowerToys.FancyZones'; ColorPicker='PowerToys.ColorPickerUI'; TextExtractor='PowerToys.PowerOCR'; AlwaysOnTop='PowerToys.AlwaysOnTop'; CropAndLock='PowerToys.CropAndLock'; AdvancedPaste='PowerToys.AdvancedPaste' }
$receipts = [Collections.Generic.List[object]]::new()
$backgroundProcesses = @{}

function Get-PackageProcesses([string]$Directory, [string]$Name) {
    @(Get-Process -Name $Name -ErrorAction SilentlyContinue | Where-Object {
        try { [string]::Equals($_.Path, (Join-Path $Directory ($Name + '.exe')), [StringComparison]::OrdinalIgnoreCase) } catch { $false }
    })
}

if ($Background) {
    foreach ($module in $Modules) {
        $directory = Join-Path $BuildRoot $module
        $entry = if ($module -eq 'PowerDisplay') { 'PowerToys.PowerDisplay.exe' } else { 'PowerToys.Portable.exe' }
        if ((Get-PackageProcesses $directory ([IO.Path]::GetFileNameWithoutExtension($entry))).Count) { throw "Close the existing test instance first: $module" }
        $backgroundProcesses[$module] = Start-Process -FilePath (Join-Path $directory $entry) -ArgumentList '--background' -WorkingDirectory $env:SystemRoot -WindowStyle Normal -PassThru
    }
    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        Start-Sleep -Milliseconds 250
        foreach ($process in $backgroundProcesses.Values) {
            $process.Refresh()
            if ($process.HasExited -or $process.MainWindowHandle -ne 0) { throw 'Concurrent logon startup exited or opened a window.' }
        }
    }
    Write-Host "PASS simultaneous tray-only startup of $($Modules.Count) modules"
}

foreach ($module in $Modules) {
    $directory = Join-Path $BuildRoot $module
    $executable = Join-Path $directory 'PowerToys.Portable.exe'
    $expectedTitle = $names[$module] + ' Portable – Einstellungen'
    if (-not $Background -and (Get-PackageProcesses $directory 'PowerToys.Portable').Count) { throw "Close the existing portable test instance first: $module" }
    if ($Background) {
        $backgroundExecutable = if ($module -eq 'PowerDisplay') { Join-Path $directory 'PowerToys.PowerDisplay.exe' } else { $executable }
        $backgroundHost = $backgroundProcesses[$module]
        $settingsHost = $null
        try {
            for ($attempt = 0; $attempt -lt 20; $attempt++) {
                Start-Sleep -Milliseconds 250
                $backgroundHost.Refresh()
                if ($backgroundHost.HasExited -or $backgroundHost.MainWindowHandle -ne 0) { throw "Background startup exited or opened a window: $module" }
            }
            if ($children.ContainsKey($module)) {
                for ($attempt = 0; $attempt -lt 40 -and -not (Get-PackageProcesses $directory $children[$module]).Count; $attempt++) { Start-Sleep -Milliseconds 250 }
                if (-not (Get-PackageProcesses $directory $children[$module]).Count) { throw "Background engine did not start silently: $module" }
            }
            $duplicate = Start-Process -FilePath $backgroundExecutable -ArgumentList '--background' -WorkingDirectory $directory -WindowStyle Normal -PassThru
            if (-not $duplicate.WaitForExit(10000) -or $duplicate.ExitCode -ne 0) { throw "Duplicate background launch did not exit: $module" }
            $backgroundHost.Refresh()
            if ($backgroundHost.MainWindowHandle -ne 0) { throw "Duplicate background launch opened Settings: $module" }
            $settingsLaunch = Start-Process -FilePath $executable -ArgumentList '--settings' -WorkingDirectory $directory -WindowStyle Normal -PassThru
            $settingsHost = if ($module -eq 'PowerDisplay') { $settingsLaunch } else { $backgroundHost }
            for ($attempt = 0; $attempt -lt 60; $attempt++) {
                Start-Sleep -Milliseconds 250
                $settingsHost.Refresh()
                if ($settingsHost.MainWindowTitle -eq $expectedTitle) { break }
            }
            if ($settingsHost.MainWindowTitle -ne $expectedTitle) { throw "Settings did not open after tray-only startup: $module" }
        }
        finally {
            $stop = Start-Process -FilePath $executable -ArgumentList '--stop' -WorkingDirectory $directory -WindowStyle Hidden -PassThru
            if (-not $stop.WaitForExit(10000)) { throw "Background stop did not redirect: $module" }
        }
        if (-not $backgroundHost.WaitForExit(10000) -or $backgroundHost.ExitCode -ne 0) { throw "Background host did not exit cleanly: $module" }
        if ($settingsHost -and -not $settingsHost.WaitForExit(10000)) { throw "Background Settings host remains: $module" }
        Write-Host "PASS $module - tray-only startup, silent duplicate, manual Settings"
    }
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
    $receipts.Add([pscustomobject][ordered]@{ module=$module; settingsTitle=$title; backgroundStartupVerified=$Background.IsPresent; secondLaunchRedirected=$true; cleanExit=$true; exitCode=$primary.ExitCode })
    Write-Host "PASS $module - settings, single instance, clean exit"
    [IO.File]::WriteAllText($ReceiptPath, (ConvertTo-Json -InputObject @($receipts.ToArray()) -Depth 5), [Text.UTF8Encoding]::new($false))
}
