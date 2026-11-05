[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BuildRoot,
    [Parameter(Mandatory)][string]$ReceiptPath
)

$ErrorActionPreference = 'Stop'
$BuildRoot = [IO.Path]::GetFullPath($BuildRoot)
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$fixtureRoot = Join-Path $repoRoot 'diagnostics\portable-first-modules\file-fixture'
[void][IO.Directory]::CreateDirectory($fixtureRoot)
$fixture = Join-Path $fixtureRoot 'Prüfung mit Leerzeichen.txt'
[IO.File]::WriteAllText($fixture, 'Portable test fixture. No user files.', [Text.UTF8Encoding]::new($false))
$receipts = [Collections.Generic.List[object]]::new()

function Start-PortableWorker([string]$Executable, [string[]]$Inputs) {
    $start = [Diagnostics.ProcessStartInfo]::new($Executable)
    $start.UseShellExecute = $false
    $start.WorkingDirectory = $fixtureRoot
    foreach ($inputPath in $Inputs) { $start.ArgumentList.Add($inputPath) }
    [Diagnostics.Process]::Start($start)
}

foreach ($definition in @(
    @{module='FileLocksmith';exe='PowerToys.FileLocksmithUI.exe'},
    @{module='Peek';exe='PowerToys.Peek.UI.exe'}
)) {
    $module = $definition.module
    $directory = Join-Path $BuildRoot $module
    $executable = Join-Path $directory $definition.exe
    $invalid = Start-PortableWorker $executable @('--runner-pid')
    if (-not $invalid.WaitForExit(15000) -or $invalid.ExitCode -ne 2) { throw "Invalid file arguments not rejected: $module" }

    $dataRoot = Join-Path $directory 'Data\Microsoft\PowerToys'
    $scope = [IO.Path]::GetFullPath($dataRoot).ToUpperInvariant() + [char]0 + 'StopModule'
    $eventName = 'Local\PowerToys_Portable_' + [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($scope)))
    $stop = [Threading.EventWaitHandle]::new($false, [Threading.EventResetMode]::ManualReset, $eventName)
    try {
        $stop.Reset() | Out-Null
        # Relative input exercises the actual worker's original-directory handling too.
        $process = Start-PortableWorker $executable @([IO.Path]::GetFileName($fixture))
        for ($attempt=0; $attempt -lt 80; $attempt++) {
            Start-Sleep -Milliseconds 250
            $process.Refresh()
            if ($process.HasExited) { throw "Worker exited on a valid selection: $module ($($process.ExitCode))" }
            if ($process.MainWindowHandle -ne 0 -and $process.MainWindowTitle) { break }
        }
        if ($process.MainWindowHandle -eq 0) { throw "Selected-file window did not open: $module" }
        $title = $process.MainWindowTitle
    }
    finally {
        $stop.Set() | Out-Null
        if ($process -and -not $process.WaitForExit(10000)) { throw "Selected-file window did not close: $module" }
        $stop.Dispose()
    }
    if ($process.ExitCode -ne 0) { throw "Selected-file window failed: $module ($($process.ExitCode))" }
    $receipts.Add([pscustomobject][ordered]@{module=$module;invalidFlagsExitCode=$invalid.ExitCode;selection='relative path, spaces and Unicode';windowTitle=$title;cleanExit=$true})
    Write-Host "PASS $module - explicit file input and clean exit"
}

[IO.File]::WriteAllText($ReceiptPath, (ConvertTo-Json -InputObject @($receipts.ToArray()) -Depth 5), [Text.UTF8Encoding]::new($false))
