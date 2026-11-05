[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Install', 'Repair', 'RemoveFirst', 'RemoveRemaining')][string]$Phase,
    [Parameter(Mandatory)][string]$Nonce
)

$ErrorActionPreference = 'Stop'
if ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-18' -or
    $PSScriptRoot -cne 'C:\Tests' -or
    (Get-Content -LiteralPath 'C:\Results\sandbox-test-authorized.txt' -Raw).Trim() -cne $Nonce) {
    throw 'This lifecycle test requires the authorized Windows Sandbox SYSTEM task.'
}
$packages = @(Get-Content -LiteralPath 'C:\Packages\sccm-deployment.json' -Raw | ConvertFrom-Json)
$results = [Collections.Generic.List[object]]::new()
$receiptPath = 'C:\Results\system-' + $Phase + '.json'

function Write-Receipt($Receipt) {
    $Receipt | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath ($receiptPath + '.tmp') -Encoding utf8
    Move-Item -LiteralPath ($receiptPath + '.tmp') -Destination $receiptPath
}

try {
    foreach ($package in $packages) {
        if ($package.productCode -notmatch '^\{[0-9A-Fa-f-]{36}\}$' -or
            $package.file -notmatch '^PowerToys-[A-Za-z]+-Standalone-[0-9.]+-x64\.msi$') {
            throw 'Invalid package metadata.'
        }
        if (($Phase -eq 'RemoveFirst' -and $package.module -ne 'FancyZones') -or
            ($Phase -eq 'RemoveRemaining' -and $package.module -eq 'FancyZones')) {
            continue
        }
        $log = 'C:\Results\' + $package.module + '-' + $Phase + '.log'
        $arguments = switch ($Phase) {
            'Install' { @('/i', ('"C:\Packages\' + $package.file + '"')) }
            'Repair' { @('/famus', $package.productCode) }
            default { @('/x', $package.productCode) }
        }
        $arguments += @('/qn', '/norestart', '/L*v', ('"' + $log + '"'))
        $process = Start-Process -FilePath "$env:SystemRoot\System32\msiexec.exe" -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
        if ($process.ExitCode -notin @(0, 3010)) {
            throw "Windows Installer failed for $($package.module) during $Phase, exit $($process.ExitCode)."
        }
        $results.Add([pscustomobject]@{module=$package.module;exitCode=$process.ExitCode})
    }
    Write-Receipt ([pscustomobject]@{phase=$Phase;success=$true;identity='S-1-5-18';results=@($results.ToArray())})
}
catch {
    Write-Receipt ([pscustomobject]@{phase=$Phase;success=$false;error=$_.Exception.Message;results=@($results.ToArray())})
    exit 1
}
