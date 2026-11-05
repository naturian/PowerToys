[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
if ($env:USERNAME -cne 'WDAGUtilityAccount' -or $PSScriptRoot -cne 'C:\Tests' -or
    -not (Test-Path -LiteralPath 'C:\Packages\sccm-deployment.json')) {
    throw 'Run this lifecycle test only through its Windows Sandbox configuration.'
}
$nonce = [Guid]::NewGuid().ToString('N')
$nonce | Set-Content -LiteralPath 'C:\Results\sandbox-test-authorized.txt' -Encoding ascii
$packages = Get-Content -LiteralPath 'C:\Packages\sccm-deployment.json' -Raw | ConvertFrom-Json
$installRoot = Join-Path $env:ProgramFiles 'Naturian\PowerToys Modules'
$profileRoot = Join-Path $env:LOCALAPPDATA 'Naturian\PowerToysModules'
$taskName = 'PowerToysStandalone-Test-' + $nonce
$progressPath = 'C:\Results\progress.txt'
$suiteProfile = Join-Path $env:LOCALAPPDATA 'Microsoft\PowerToys'
if (Test-Path -LiteralPath $suiteProfile) { throw 'The test requires a fresh PowerToys user profile.' }

Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class MsiDetection
{
    [DllImport("msi.dll", CharSet = CharSet.Unicode)]
    public static extern uint MsiGetProductInfoEx(string product, string sid, uint context, string property, StringBuilder value, ref uint size);
    [DllImport("msi.dll", CharSet = CharSet.Unicode)]
    public static extern uint MsiGetShortcutTarget(string shortcut, StringBuilder product, StringBuilder feature, StringBuilder component);
    [DllImport("msi.dll", CharSet = CharSet.Unicode)]
    public static extern int MsiGetComponentPathEx(string product, string component, string sid, uint context, StringBuilder value, ref uint size);
}
'@

function Test-MachineProduct($Package, [bool]$ExpectedInstalled) {
    $value = [Text.StringBuilder]::new(128)
    [uint32]$length = 128
    $code = [MsiDetection]::MsiGetProductInfoEx($Package.productCode, $null, 4, 'VersionString', $value, [ref]$length)
    if ($ExpectedInstalled) {
        if ($code -ne 0 -or $value.ToString() -ne $Package.productVersion) {
            throw "Machine-context MSI detection failed for $($Package.module), code $code."
        }
    }
    elseif ($code -ne 1605) {
        throw "The removed product remains registered: $($Package.module), code $code."
    }
}

function Invoke-SystemPhase([string]$Phase) {
    $Phase | Set-Content -LiteralPath $progressPath -Encoding ascii
    $arguments = '-NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File C:\Tests\test-standalone-system.ps1 -Phase ' + $Phase + ' -Nonce ' + $nonce
    $action = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument $arguments
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    [void](Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Force)
    try {
        Start-ScheduledTask -TaskName $taskName
        $receiptPath = 'C:\Results\system-' + $Phase + '.json'
        $deadline = (Get-Date).AddMinutes(15)
        while (-not (Test-Path -LiteralPath $receiptPath)) {
            if ((Get-Date) -gt $deadline) { throw "SYSTEM phase timed out: $Phase" }
            Start-Sleep -Seconds 1
        }
        $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
        if (-not $receipt.success) { throw $receipt.error }
    }
    finally { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue }
}

function Get-ProfileHashes {
    $hashes = @{}
    foreach ($file in (Get-ChildItem -LiteralPath $profileRoot -Filter '*.json' -Recurse -File)) {
        $hashes[$file.FullName] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    }
    return $hashes
}

function Assert-ProfileHashes($Before) {
    $after = Get-ProfileHashes
    if ($Before.Count -ne $after.Count) { throw 'User profile file count changed during MSI maintenance.' }
    foreach ($file in $Before.Keys) {
        if ($after[$file] -ne $Before[$file]) { throw "User data changed during MSI maintenance: $file" }
    }
}

try {
    'Cache' | Set-Content -LiteralPath $progressPath -Encoding ascii
    [void][IO.Directory]::CreateDirectory('C:\SccmContent')
    foreach ($package in $packages) {
        $cached = Join-Path 'C:\SccmContent' $package.file
        Copy-Item -LiteralPath (Join-Path 'C:\Packages' $package.file) -Destination $cached
        if ((Get-FileHash -LiteralPath $cached -Algorithm SHA256).Hash -ne $package.sha256) {
            throw 'The copied deployment content differs from its manifest.'
        }
    }
    Invoke-SystemPhase 'Install'
    foreach ($package in $packages) { Test-MachineProduct $package $true }
    if (Test-Path -LiteralPath 'C:\Windows\System32\config\systemprofile\AppData\Local\Naturian\PowerToysModules') {
        throw 'Installation started module profile initialization as SYSTEM.'
    }
    'Runtime' | Set-Content -LiteralPath $progressPath -Encoding ascii
    $displayExecutable = Join-Path $installRoot 'PowerDisplay\PowerToys.PowerDisplay.exe'
    $display = Start-Process -FilePath $displayExecutable -WorkingDirectory ([IO.Path]::GetDirectoryName($displayExecutable)) -WindowStyle Hidden -PassThru
    & 'C:\Tests\test-portable-startup.ps1' -BuildRoot $installRoot -ReceiptPath 'C:\Results\startup.json'
    if (-not $display.WaitForExit(10000)) { throw 'Power Display did not exit through its portable host.' }
    if ($display.ExitCode -ne 0) { throw "Power Display failed with exit $($display.ExitCode)." }

    foreach ($package in $packages) {
        $directory = Join-Path $installRoot $package.module
        if (Test-Path -LiteralPath (Join-Path $directory 'Data')) { throw 'Application data was written beside installed binaries.' }
        $data = Join-Path $profileRoot ($package.module + '\Microsoft\PowerToys')
        $language = Get-Content -LiteralPath (Join-Path $data 'language.json') -Raw | ConvertFrom-Json
        if ($language.language -ne 'de-DE') { throw 'First-user language is incorrect.' }
        $registration = Get-ItemProperty -LiteralPath ('HKLM:\SOFTWARE\Naturian\PowerToysModules\' + $package.module)
        if ($registration.ProductCode -ne $package.productCode) { throw 'Incorrect module registry identity.' }
    }
    $shortcuts = @(Get-ChildItem -LiteralPath 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\PowerToys Modules' -Filter '*.lnk' -File)
    if ($shortcuts.Count -ne $packages.Count) { throw 'Incorrect number of Start menu shortcuts.' }
    foreach ($shortcut in $shortcuts) {
        $product = [Text.StringBuilder]::new(39)
        $feature = [Text.StringBuilder]::new(256)
        $component = [Text.StringBuilder]::new(39)
        $code = [MsiDetection]::MsiGetShortcutTarget($shortcut.FullName, $product, $feature, $component)
        if ($code -ne 0 -or $product.ToString() -notin $packages.productCode) { throw 'Incorrect advertised shortcut product.' }
        $target = [Text.StringBuilder]::new(32768)
        [uint32]$length = 32768
        $state = [MsiDetection]::MsiGetComponentPathEx($product.ToString(), $component.ToString(), $null, 4, $target, [ref]$length)
        if ($state -ne 3 -or -not (Test-Path -LiteralPath $target.ToString()) -or
            -not $target.ToString().StartsWith($installRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Start menu shortcut targets the wrong application.'
        }
    }
    $profileHashes = Get-ProfileHashes
    Invoke-SystemPhase 'Repair'
    Assert-ProfileHashes $profileHashes
    if (Test-Path -LiteralPath $suiteProfile) { throw 'Standalone modules created a full-suite user profile.' }
    foreach ($package in $packages) { Test-MachineProduct $package $true }
    Invoke-SystemPhase 'RemoveFirst'
    foreach ($package in $packages) { Test-MachineProduct $package ($package.module -ne 'FancyZones') }
    & 'C:\Tests\test-portable-startup.ps1' -BuildRoot $installRoot -Modules Peek -ReceiptPath 'C:\Results\coexistence.json'
    $profileHashes = Get-ProfileHashes
    Invoke-SystemPhase 'RemoveRemaining'
    foreach ($package in $packages) {
        Test-MachineProduct $package $false
        if (Test-Path -LiteralPath (Join-Path $installRoot ($package.module + '\PowerToys.Portable.exe'))) {
            throw 'An uninstalled application executable remains.'
        }
    }
    Assert-ProfileHashes $profileHashes
    if (Test-Path -LiteralPath 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\PowerToys Modules') {
        if (@(Get-ChildItem -LiteralPath 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\PowerToys Modules' -Filter '*.lnk' -File).Count) {
            throw 'Uninstalled Start menu shortcuts remain.'
        }
    }
    [pscustomobject]@{
        success=$true;modules=$packages.Count;systemInstall=$true;machineDetection=$true
        userStartup=$true;systemRepair=$true;systemUninstall=$true;coexistence=$true
        profileJsonFiles=$profileHashes.Count;profileDataPreserved=$true
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath 'C:\Results\result.json' -Encoding utf8
    'COMPLETE' | Set-Content -LiteralPath $progressPath -Encoding ascii
}
catch {
    [pscustomobject]@{success=$false;error=$_.Exception.Message;position=$_.InvocationInfo.PositionMessage} |
        ConvertTo-Json -Depth 4 | Set-Content -LiteralPath 'C:\Results\result.json' -Encoding utf8
    'FAILED' | Set-Content -LiteralPath $progressPath -Encoding ascii
    exit 1
}
