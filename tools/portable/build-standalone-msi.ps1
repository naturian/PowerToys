[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BuildRoot,
    [Parameter(Mandatory)][string]$OutputRoot,
    [ValidateNotNull()][version]$PackageVersion = '0.102.3002',
    [ValidateSet('FancyZones', 'ColorPicker', 'TextExtractor', 'ImageResizer', 'PowerDisplay', 'AlwaysOnTop', 'FileLocksmith', 'Peek', 'CropAndLock', 'AdvancedPaste')]
    [string[]]$Modules = @('FancyZones', 'ColorPicker', 'TextExtractor', 'ImageResizer', 'PowerDisplay', 'AlwaysOnTop', 'FileLocksmith', 'Peek', 'CropAndLock', 'AdvancedPaste'),
    [switch]$Resume
)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$BuildRoot = [IO.Path]::GetFullPath($BuildRoot).TrimEnd('\')
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
if ((Get-Content -LiteralPath (Join-Path $BuildRoot 'progress.txt') -Raw).Trim() -ne 'PUBLISH_COMPLETE') {
    throw 'The module payload build must complete before packaging.'
}
if ((Test-Path -LiteralPath $OutputRoot) -and -not $Resume) {
    throw 'Use a fresh output directory, or explicitly select -Resume.'
}
[void][IO.Directory]::CreateDirectory($OutputRoot)
$buildResults = @(Get-Content -LiteralPath (Join-Path $BuildRoot 'build-results.json') -Raw | ConvertFrom-Json)
$sourceCommit = (& git -C $repoRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Cannot determine the source commit.' }
$workRoot = Join-Path $repoRoot ('artifacts\standalone-msi\' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N'))
$projectDirectory = Join-Path $repoRoot 'installer\PowerToysStandalone'
$env:NUGET_PACKAGES = Join-Path $repoRoot '.build-cache\nuget'
$env:Path = (($env:Path -split ';' | ForEach-Object { $_.Trim('"') }) -join ';')
$utf8 = [Text.UTF8Encoding]::new($false)
$wixNamespace = 'http://wixtoolset.org/schemas/v4/wxs'
$moduleNames = @{
    FancyZones = 'FancyZones'; ColorPicker = 'Color Picker'; TextExtractor = 'Text Extractor'
    ImageResizer = 'Image Resizer'; PowerDisplay = 'Power Display'; AlwaysOnTop = 'Always On Top'
    FileLocksmith = 'File Locksmith'; Peek = 'Peek'; CropAndLock = 'Crop And Lock'; AdvancedPaste = 'Advanced Paste'
}
$receipts = [Collections.Generic.List[object]]::new()

function Get-StableHash([string]$Value) {
    $bytes = [Text.Encoding]::UTF8.GetBytes('Naturian/PowerToysStandalone/v1/' + $Value.ToLowerInvariant())
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
}

function Get-StableGuid([string]$Value) {
    $bytes = [Convert]::FromHexString((Get-StableHash $Value).Substring(0, 32))
    return ([Guid]::new($bytes)).ToString('B').ToUpperInvariant()
}

function Write-PayloadDirectory([Xml.XmlWriter]$Writer, [string]$Directory, [string]$Relative) {
    foreach ($file in (Get-ChildItem -LiteralPath $Directory -File | Sort-Object Name)) {
        $relativeFile = ($Relative + '/' + $file.Name).TrimStart('/')
        $identifier = (Get-StableHash ($module + '/' + $relativeFile)).Substring(0, 32)
        $componentId = 'cmp_' + $identifier
        $componentIds.Add($componentId)
        $Writer.WriteStartElement('Component', $wixNamespace)
        $Writer.WriteAttributeString('Id', $componentId)
        $Writer.WriteAttributeString('Guid', (Get-StableGuid ('component/' + $module + '/' + $relativeFile)))
        $Writer.WriteAttributeString('Bitness', 'always64')
        $Writer.WriteStartElement('File', $wixNamespace)
        $Writer.WriteAttributeString('Id', ('file_' + $identifier))
        $Writer.WriteAttributeString('Source', $file.FullName)
        $Writer.WriteAttributeString('Name', $file.Name)
        $Writer.WriteAttributeString('KeyPath', 'yes')
        if ($relativeFile -ceq $manifest.entryPoint) {
            $Writer.WriteStartElement('Shortcut', $wixNamespace)
            $Writer.WriteAttributeString('Id', 'ModuleShortcut')
            $Writer.WriteAttributeString('Directory', 'ModuleShortcutsFolder')
            $Writer.WriteAttributeString('Name', ('PowerToys ' + $moduleNames[$module]))
            $Writer.WriteAttributeString('Advertise', 'yes')
            $Writer.WriteAttributeString('WorkingDirectory', 'INSTALLFOLDER')
            $Writer.WriteAttributeString('Icon', 'ModuleIcon.exe')
            $Writer.WriteEndElement()
        }
        $Writer.WriteEndElement()
        if ($relativeFile -ceq $manifest.entryPoint) {
            $Writer.WriteStartElement('RemoveFolder', $wixNamespace)
            $Writer.WriteAttributeString('Id', 'RemoveModuleShortcutsFolder')
            $Writer.WriteAttributeString('Directory', 'ModuleShortcutsFolder')
            $Writer.WriteAttributeString('On', 'uninstall')
            $Writer.WriteEndElement()
        }
        $Writer.WriteEndElement()
    }
    foreach ($child in (Get-ChildItem -LiteralPath $Directory -Directory | Sort-Object Name)) {
        $relativeChild = ($Relative + '/' + $child.Name).TrimStart('/')
        $Writer.WriteStartElement('Directory', $wixNamespace)
        $Writer.WriteAttributeString('Id', ('dir_' + (Get-StableHash ($module + '/' + $relativeChild)).Substring(0, 32)))
        $Writer.WriteAttributeString('Name', $child.Name)
        Write-PayloadDirectory $Writer $child.FullName $relativeChild
        $Writer.WriteEndElement()
    }
}

foreach ($module in $Modules) {
    $result = @($buildResults | Where-Object module -eq $module)
    if ($result.Count -ne 1 -or $result[0].buildExitCode -ne 0) {
        throw "A successful payload build is required for $module."
    }
    $source = Join-Path $BuildRoot $module
    $manifest = Get-Content -LiteralPath (Join-Path $source 'package-manifest.json') -Raw | ConvertFrom-Json
    $version = [version]$manifest.version
    if ($version.Major -gt 255 -or $version.Minor -gt 255 -or $version.Build -gt 65535 -or $version.Revision -ne 0) {
        throw 'The upstream version must fit the three MSI version fields with a zero fourth field.'
    }
    $binaryVersion = $version.ToString(4)
    $msiVersion = $version.ToString(3)
    if ($PackageVersion) {
        if ($PackageVersion.Major -gt 255 -or $PackageVersion.Minor -gt 255 -or
            $PackageVersion.Build -lt 0 -or $PackageVersion.Build -gt 65535 -or $PackageVersion.Revision -gt 0 -or
            $PackageVersion -lt [version]$msiVersion) {
            throw 'The package version must fit MSI version fields and cover the binary version.'
        }
        $msiVersion = $PackageVersion.ToString(3)
    }
    $moduleWork = Join-Path $workRoot $module
    $payload = Join-Path $moduleWork 'Payload'
    [void][IO.Directory]::CreateDirectory($payload)
    foreach ($file in (Get-ChildItem -LiteralPath $source -Recurse -File)) {
        $relative = $file.FullName.Substring($source.Length + 1)
        if ($relative.StartsWith('Data\', [StringComparison]::OrdinalIgnoreCase) -or
            $relative -in @('portable-mode', 'package-manifest.json', 'README.txt') -or $file.Extension -eq '.pdb') {
            continue
        }
        if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Reparse point in module payload: $relative"
        }
        $destination = Join-Path $payload $relative
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
        Copy-Item -LiteralPath $file.FullName -Destination $destination
    }
    foreach ($required in @('PowerToys.Portable.exe', 'PowerToys.Portable.pri', 'PowerToys.Settings.dll', 'portable-module.json', 'portable.ico', $manifest.entryPoint)) {
        if (-not (Test-Path -LiteralPath (Join-Path $payload $required) -PathType Leaf)) {
            throw "Required module file missing: $module/$required"
        }
    }
    [IO.File]::WriteAllText((Join-Path $payload 'standalone-mode'), $module, $utf8)
    $defaults = Join-Path $payload 'Defaults'
    [void][IO.Directory]::CreateDirectory($defaults)
    [IO.File]::WriteAllText((Join-Path $defaults 'language.json'), '{"language":"de-DE"}', $utf8)
    $settingsName = if ($module -eq 'ImageResizer') { 'Image Resizer' } elseif ($module -eq 'FileLocksmith') { 'File Locksmith' } else { $module }
    $settings = @{ enabled = @{ $settingsName = $true }; theme = 'system'; startup = $false; download_updates_automatically = $false; enable_experimentation = $false }
    [IO.File]::WriteAllText((Join-Path $defaults 'settings.json'), ($settings | ConvertTo-Json -Depth 4 -Compress), $utf8)
    $readme = @"
PowerToys $($moduleNames[$module]) Standalone $binaryVersion

Launch this module from Start > PowerToys Modules.
MSI package version $msiVersion.
At user sign-in, this module starts in the tray using --background.
The German Settings interface and tray menu configure the selected module.
User data is stored under %LOCALAPPDATA%\Naturian\PowerToysModules\$module\Microsoft\PowerToys.
The standalone-mode marker selects per-user storage for this machine-wide installation.
Exit using the tray before an upgrade. Windows Installer manages application files.
Uninstall through Windows Installed apps or your Configuration Manager deployment.
User settings are retained for later installation or upgrade.
Source, licenses, and deployment instructions are available at https://github.com/naturian/PowerToys.
"@
    [IO.File]::WriteAllText((Join-Path $payload 'README.txt'), $readme, $utf8)

    $componentIds = [Collections.Generic.List[string]]::new()
    $harvestPath = Join-Path $moduleWork 'Payload.wxs'
    $xmlSettings = [Xml.XmlWriterSettings]::new()
    $xmlSettings.Indent = $true
    $xmlSettings.Encoding = $utf8
    $writer = [Xml.XmlWriter]::Create($harvestPath, $xmlSettings)
    try {
        $writer.WriteStartElement('Wix', $wixNamespace)
        $writer.WriteStartElement('Fragment', $wixNamespace)
        $writer.WriteStartElement('DirectoryRef', $wixNamespace)
        $writer.WriteAttributeString('Id', 'INSTALLFOLDER')
        Write-PayloadDirectory $writer $payload ''
        $writer.WriteEndElement()
        $writer.WriteStartElement('ComponentGroup', $wixNamespace)
        $writer.WriteAttributeString('Id', 'PayloadComponents')
        foreach ($componentId in $componentIds) {
            $writer.WriteStartElement('ComponentRef', $wixNamespace)
            $writer.WriteAttributeString('Id', $componentId)
            $writer.WriteEndElement()
        }
        $writer.WriteEndElement()
        $writer.WriteEndElement()
        $writer.WriteEndElement()
    }
    finally { $writer.Dispose() }

    $includePath = Join-Path $moduleWork 'PackageData.wxi'
    $values = [ordered]@{
        ModuleId = $module; ModuleName = $moduleNames[$module]; MsiVersion = $msiVersion
        BinaryVersion = $binaryVersion; PayloadRoot = $payload; EntryPoint = $manifest.entryPoint
        UpgradeCode = (Get-StableGuid ('upgrade/' + $module))
        ProductCode = (Get-StableGuid ('product/' + $module + '/' + $msiVersion))
        RegistrationGuid = (Get-StableGuid ('registration/' + $module))
        StartupGuid = (Get-StableGuid ('startup/' + $module))
    }
    $definitions = @($values.Keys | ForEach-Object { '<?define ' + $_ + '="' + $values[$_] + '" ?>' })
    [IO.File]::WriteAllText($includePath, ('<Include xmlns="' + $wixNamespace + '">' + [Environment]::NewLine + ($definitions -join [Environment]::NewLine) + [Environment]::NewLine + '</Include>'), $utf8)
    Push-Location -LiteralPath $projectDirectory
    try {
        & (Join-Path $repoRoot 'tools\build\build.ps1') -Platform x64 -Configuration Release -Path $projectDirectory -ExtraArgs @(
            '/p:NuGetAudit=false', "/p:ModuleId=$module", "/p:BinaryVersion=$binaryVersion", "/p:PackageVersion=$msiVersion",
            "/p:PackageInclude=$includePath", "/p:HarvestFile=$harvestPath", "/p:MsiOutputRoot=$OutputRoot",
            "/p:IntermediateOutputPath=$moduleWork\obj\")
        if ($LASTEXITCODE -ne 0) { throw "MSI build failed for $module (exit $LASTEXITCODE)." }
    }
    finally { Pop-Location }
    $msiPath = Join-Path $OutputRoot "PowerToys-$module-Standalone-$msiVersion-x64.msi"
    $receipt = & (Join-Path $PSScriptRoot 'test-standalone-msi.ps1') -MsiPath $msiPath -PayloadRoot $payload -ExpectedModule $module -NormalizeAndValidate
    $receipt | Add-Member -NotePropertyName sourceCommit -NotePropertyValue $sourceCommit
    $receipt | Add-Member -NotePropertyName payloadRoot -NotePropertyValue $payload
    $receipts.Add($receipt)
    [IO.File]::WriteAllText((Join-Path $workRoot 'build-results.json'), (ConvertTo-Json -InputObject @($receipts.ToArray()) -Depth 6), $utf8)
}

$allComponents = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($receipt in $receipts) {
    foreach ($guid in $receipt.componentGuids) {
        if (-not $allComponents.Add($guid)) { throw 'Component GUIDs must be unique across standalone modules.' }
    }
}
if (@($receipts.productCode | Select-Object -Unique).Count -ne $receipts.Count -or
    @($receipts.upgradeCode | Select-Object -Unique).Count -ne $receipts.Count) {
    throw 'Standalone products must have distinct product and upgrade codes.'
}
$deployment = @($receipts | Select-Object module,file,productCode,upgradeCode,productVersion,binaryVersion,installCommand,uninstallCommand,sha256,sourceCommit)
[IO.File]::WriteAllText((Join-Path $OutputRoot 'sccm-deployment.json'), (ConvertTo-Json -InputObject $deployment -Depth 4), $utf8)
$deployment | Export-Csv -LiteralPath (Join-Path $OutputRoot 'sccm-deployment.csv') -NoTypeInformation -Encoding utf8
[IO.File]::WriteAllLines((Join-Path $OutputRoot 'SHA256SUMS-MSI.txt'), @($receipts | ForEach-Object { "$($_.sha256)  $($_.file)" }), $utf8)
Write-Host "STANDALONE_MSI_COMPLETE=$OutputRoot"
Write-Host "STANDALONE_BUILD_RECEIPT=$workRoot\build-results.json"
