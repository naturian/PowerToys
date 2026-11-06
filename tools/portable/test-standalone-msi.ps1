[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$MsiPath,
    [Parameter(Mandatory)][string]$PayloadRoot,
    [Parameter(Mandatory)][string]$ExpectedModule,
    [switch]$NormalizeAndValidate
)

$ErrorActionPreference = 'Stop'
$MsiPath = [IO.Path]::GetFullPath($MsiPath)
$PayloadRoot = [IO.Path]::GetFullPath($PayloadRoot).TrimEnd('\')

function Read-MsiRows($Database, [string]$Query, [string[]]$Columns) {
    $view = $Database.GetType().InvokeMember('OpenView', 'InvokeMethod', $null, $Database, @($Query))
    try {
        [void]$view.GetType().InvokeMember('Execute', 'InvokeMethod', $null, $view, $null)
        while ($record = $view.GetType().InvokeMember('Fetch', 'InvokeMethod', $null, $view, $null)) {
            try {
                $row = [ordered]@{}
                for ($index = 0; $index -lt $Columns.Count; $index++) {
                    $row[$Columns[$index]] = $record.GetType().InvokeMember('StringData', 'GetProperty', $null, $record, @($index + 1))
                }
                [pscustomobject]$row
            }
            finally { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($record) }
        }
    }
    finally {
        [void]$view.GetType().InvokeMember('Close', 'InvokeMethod', $null, $view, $null)
        [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($view)
    }
}

$installer = New-Object -ComObject WindowsInstaller.Installer
$database = $null
try {
    $database = $installer.GetType().InvokeMember('OpenDatabase', 'InvokeMethod', $null, $installer, @($MsiPath, [int]$NormalizeAndValidate.IsPresent))
    if ($NormalizeAndValidate) {
        # Locale-specific directories select MUI resources. Neutral installer metadata fits MSI's legacy language field.
        $languageRows = @(Read-MsiRows $database 'SELECT `File`, `FileName`, `Language`, `Version` FROM `File`' @('Id', 'Name', 'Language', 'Version'))
        foreach ($row in $languageRows) {
            if (($row.Name -split '\|')[-1] -notlike '*.mui' -and $row.Language.Length -le 20 -and
                ($row.Language -or -not $row.Version)) { continue }
            $query = 'UPDATE `File` SET `Language` = ''0'' WHERE `File` = ?'
            $view = $database.GetType().InvokeMember('OpenView', 'InvokeMethod', $null, $database, @($query))
            $record = $installer.GetType().InvokeMember('CreateRecord', 'InvokeMethod', $null, $installer, @(1))
            try {
                [void]$record.GetType().InvokeMember('StringData', 'SetProperty', $null, $record, @(1, $row.Id))
                [void]$view.GetType().InvokeMember('Execute', 'InvokeMethod', $null, $view, @($record))
            }
            finally {
                [void]$view.GetType().InvokeMember('Close', 'InvokeMethod', $null, $view, $null)
                [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($record)
                [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($view)
            }
        }
        [void]$database.GetType().InvokeMember('Commit', 'InvokeMethod', $null, $database, $null)
        [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($database)
        $database = $null
        $wixTool = Join-Path $env:NUGET_PACKAGES 'wixtoolset.sdk\5.0.2\tools\net472\x64\wix.exe'
        & $wixTool msi validate $MsiPath | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "Full MSI validation failed (exit $LASTEXITCODE)." }
        $database = $installer.GetType().InvokeMember('OpenDatabase', 'InvokeMethod', $null, $installer, @($MsiPath, 0))
    }
    $properties = @{}
    foreach ($row in (Read-MsiRows $database 'SELECT `Property`, `Value` FROM `Property`' @('Property', 'Value'))) {
        $properties[$row.Property] = $row.Value
    }
    if ($properties.ALLUSERS -ne '1' -or $properties.ProductLanguage -ne '1031' -or
        $properties.REBOOT -ne 'ReallySuppress' -or $properties.MSIRESTARTMANAGERCONTROL -ne 'DisableShutdown') {
        throw 'Incorrect installation scope, language, or unattended power/process handling.'
    }
    if ($properties.Manufacturer -ne 'naturian' -or $properties.ProductName -notlike 'PowerToys * Standalone') {
        throw 'Incorrect standalone product identity.'
    }
    foreach ($property in @('ProductCode', 'UpgradeCode')) {
        if ($properties[$property] -notmatch '^\{[0-9A-Fa-f-]{36}\}$') { throw "Invalid $property." }
    }
    $summary = $database.GetType().InvokeMember('SummaryInformation', 'GetProperty', $null, $database, @(0))
    try {
        $template = $summary.GetType().InvokeMember('Property', 'GetProperty', $null, $summary, @(7))
        if ($template -notmatch '^x64;') { throw 'The MSI must be an x64 package.' }
    }
    finally { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($summary) }

    $components = @(Read-MsiRows $database 'SELECT `Component`, `ComponentId`, `Directory_`, `Attributes`, `KeyPath` FROM `Component`' @('Id', 'Guid', 'Directory', 'Attributes', 'KeyPath'))
    if (@($components | Where-Object { ([int]$_.Attributes -band 256) -eq 0 }).Count) {
        throw 'All components must use 64-bit installation locations.'
    }
    $files = @(Read-MsiRows $database 'SELECT `File`, `Component_`, `FileName`, `FileSize` FROM `File`' @('Id', 'Component', 'Name', 'Bytes'))
    $directories = @{}
    foreach ($row in (Read-MsiRows $database 'SELECT `Directory`, `Directory_Parent`, `DefaultDir` FROM `Directory`' @('Id', 'Parent', 'Name'))) {
        $directories[$row.Id] = $row
    }
    if ($directories.INSTALLFOLDER.Parent -ne 'ModulesFolder' -or ($directories.INSTALLFOLDER.Name -split '\|')[-1] -cne $ExpectedModule -or
        $directories.ModulesFolder.Parent -ne 'PublisherFolder' -or $directories.PublisherFolder.Parent -ne 'ProgramFiles64Folder') {
        throw 'Incorrect per-machine application directory.'
    }
    $componentMap = @{}
    foreach ($component in $components) { $componentMap[$component.Id] = $component }
    $installedFiles = @{}
    foreach ($file in $files) {
        $component = $componentMap[$file.Component]
        if ($component.KeyPath -ne $file.Id) { throw 'Each payload file must be its own component key path.' }
        $parts = [Collections.Generic.List[string]]::new()
        $parts.Add(($file.Name -split '\|')[-1])
        $directoryId = $component.Directory
        $visited = [Collections.Generic.HashSet[string]]::new()
        while ($directoryId -ne 'INSTALLFOLDER') {
            if (-not $directories.ContainsKey($directoryId) -or -not $visited.Add($directoryId)) {
                throw 'Invalid payload directory graph.'
            }
            $directory = $directories[$directoryId]
            $parts.Insert(0, (($directory.Name -split ':')[0] -split '\|')[-1])
            $directoryId = $directory.Parent
        }
        $relative = $parts -join '\'
        if ($installedFiles.ContainsKey($relative)) { throw "Duplicate installed file: $relative" }
        $installedFiles[$relative] = [long]$file.Bytes
    }
    $expectedFiles = @(Get-ChildItem -LiteralPath $PayloadRoot -Recurse -File)
    if ($files.Count -ne $expectedFiles.Count -or $components.Count -ne $files.Count + 2) {
        throw 'MSI payload or component count differs from the staged payload.'
    }
    foreach ($file in $expectedFiles) {
        $relative = $file.FullName.Substring($PayloadRoot.Length + 1)
        if (-not $installedFiles.ContainsKey($relative) -or $installedFiles[$relative] -ne $file.Length) {
            throw "MSI file mismatch: $relative"
        }
    }
    if (-not $installedFiles.ContainsKey('standalone-mode') -or $installedFiles.ContainsKey('portable-mode') -or
        @($installedFiles.Keys | Where-Object { $_ -like 'Data\*' -or $_ -like '*.pdb' }).Count) {
        throw 'The MSI must contain standalone storage metadata and a clean payload.'
    }
    if ((Get-Content -LiteralPath (Join-Path $PayloadRoot 'standalone-mode') -Raw).Trim() -cne $ExpectedModule) {
        throw 'Standalone marker differs from its package identity.'
    }
    $identity = Get-Content -LiteralPath (Join-Path $PayloadRoot 'portable-module.json') -Raw | ConvertFrom-Json
    $language = Get-Content -LiteralPath (Join-Path $PayloadRoot 'Defaults\language.json') -Raw | ConvertFrom-Json
    $settings = Get-Content -LiteralPath (Join-Path $PayloadRoot 'Defaults\settings.json') -Raw | ConvertFrom-Json
    $settingsName = if ($ExpectedModule -eq 'ImageResizer') { 'Image Resizer' } elseif ($ExpectedModule -eq 'FileLocksmith') { 'File Locksmith' } else { $ExpectedModule }
    if ($identity.module -cne $ExpectedModule -or $language.language -cne 'de-DE' -or
        $settings.enabled.$settingsName -ne $true -or $settings.startup -ne $false -or
        $settings.download_updates_automatically -ne $false -or $settings.enable_experimentation -ne $false) {
        throw 'Incorrect module identity or fresh profile defaults.'
    }
    $registrations = @(Read-MsiRows $database 'SELECT `Root`, `Key`, `Name`, `Value` FROM `Registry`' @('Root', 'Key', 'Name', 'Value'))
    $key = 'SOFTWARE\Naturian\PowerToysModules\' + $ExpectedModule
    $runKey = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
    if (@($registrations | Where-Object { $_.Root -ne '2' -or $_.Key -cnotin @($key, $runKey) }).Count) {
        throw 'Registry writes must belong to this module or its machine-wide startup entry.'
    }
    $binaryVersion = @($registrations | Where-Object Name -eq 'Version')[0].Value
    if ([version]$properties.ProductVersion -lt [version](([version]$binaryVersion).ToString(3))) { throw 'MSI package version predates its binaries.' }
    $shortcuts = @(Read-MsiRows $database 'SELECT `Directory_`, `Target`, `WkDir`, `Component_` FROM `Shortcut`' @('Directory', 'Target', 'WorkingDirectory', 'Component'))
    $entryPoint = if ($ExpectedModule -eq 'PowerDisplay') { 'PowerToys.PowerDisplay.exe' } else { 'PowerToys.Portable.exe' }
    $startup = @($registrations | Where-Object { $_.Key -ceq $runKey })
    if ($registrations.Count -ne 5 -or $startup.Count -ne 1 -or
        $startup[0].Name -cne ('Naturian.PowerToys.' + $ExpectedModule) -or
        $startup[0].Value -cne ('"[INSTALLFOLDER]' + $entryPoint + '" --background')) {
        throw 'The module must register exactly one quoted, background-only user-logon command.'
    }
    if ($shortcuts.Count -ne 1 -or $shortcuts[0].Directory -ne 'ModuleShortcutsFolder' -or
        $shortcuts[0].Target -cne 'StandaloneModule' -or $shortcuts[0].WorkingDirectory -ne 'INSTALLFOLDER') {
        throw 'Incorrect Start menu shortcut.'
    }
    $shortcutFileId = $componentMap[$shortcuts[0].Component].KeyPath
    if (@($files | Where-Object { $_.Id -eq $shortcutFileId -and ($_.Name -split '\|')[-1] -ceq $entryPoint }).Count -ne 1) {
        throw 'Advertised shortcut must point to this module entry point.'
    }
    $actions = @(Read-MsiRows $database 'SELECT `Type` FROM `CustomAction`' @('Type'))
    if (@($actions | Where-Object { ([int]$_.Type -band 63) -ne 51 }).Count) {
        throw 'Executable or script custom actions are forbidden in standalone MSIs.'
    }
    $upgradeRows = @(Read-MsiRows $database 'SELECT `UpgradeCode`, `Attributes` FROM `Upgrade`' @('Code', 'Attributes'))
    if ($upgradeRows.Count -lt 2 -or @($upgradeRows | Where-Object Code -ne $properties.UpgradeCode).Count) {
        throw 'Missing upgrade or downgrade detection.'
    }
    $fileName = [IO.Path]::GetFileName($MsiPath)
    [pscustomobject][ordered]@{
        module = $ExpectedModule
        file = $fileName
        productCode = $properties.ProductCode
        upgradeCode = $properties.UpgradeCode
        productVersion = $properties.ProductVersion
        binaryVersion = $binaryVersion
        installCommand = 'msiexec.exe /i "' + $fileName + '" /qn /norestart /L*v "%WINDIR%\Temp\PowerToys-' + $ExpectedModule + '-install.log"'
        uninstallCommand = 'msiexec.exe /x ' + $properties.ProductCode + ' /qn /norestart /L*v "%WINDIR%\Temp\PowerToys-' + $ExpectedModule + '-uninstall.log"'
        bytes = (Get-Item -LiteralPath $MsiPath).Length
        sha256 = (Get-FileHash -LiteralPath $MsiPath -Algorithm SHA256).Hash
        verifiedFiles = $files.Count
        componentGuids = @($components.Guid)
    }
}
finally {
    if ($database) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($database) }
    [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($installer)
}
