[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$BuildRoot,
    [switch]$GeneratedWix
)

$ErrorActionPreference = 'Stop'
if (-not $RepoRoot)
{
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure([string]$Message)
{
    $failures.Add($Message)
}

function Read-XmlDocument([string]$Path)
{
    $document = [Xml.XmlDocument]::new()
    $document.PreserveWhitespace = $false
    $document.Load($Path)
    return ,$document
}

function Get-ResourceKeys([string]$Path)
{
    $document = Read-XmlDocument $Path
    return @($document.root.data | ForEach-Object { [string]$_.name })
}

function Convert-ReswKeyToPriPath([string]$Key)
{
    $insideQualifier = $false
    $builder = [Text.StringBuilder]::new()
    foreach ($character in $Key.ToCharArray())
    {
        if ($character -eq '[') { $insideQualifier = $true }
        if ($character -eq ']') { $insideQualifier = $false }
        if ($character -eq '.' -and -not $insideQualifier)
        {
            [void]$builder.Append('/')
        }
        else
        {
            [void]$builder.Append($character)
        }
    }

    return $builder.ToString()
}

function Resolve-MakePriPath
{
    $kitsRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    return Get-ChildItem -LiteralPath $kitsRoot -Filter 'makepri.exe' -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Directory.Name -eq 'x64' } |
        Sort-Object { try { [version]$_.Directory.Parent.Name } catch { [version]'0.0' } } -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}

function Test-LocalizedPair([string]$EnglishPath, [string]$GermanPath)
{
    $englishFullPath = Join-Path $RepoRoot $EnglishPath
    $germanFullPath = Join-Path $RepoRoot $GermanPath

    if (-not (Test-Path -LiteralPath $germanFullPath))
    {
        Add-Failure "Deutsche Ressource fehlt: $GermanPath"
        return
    }

    $englishKeys = Get-ResourceKeys $englishFullPath
    $germanKeys = Get-ResourceKeys $germanFullPath
    $missingKeys = @($englishKeys | Where-Object { $_ -notin $germanKeys })
    $extraKeys = @($germanKeys | Where-Object { $_ -notin $englishKeys })

    if ($missingKeys.Count -gt 0)
    {
        Add-Failure "$GermanPath fehlen $($missingKeys.Count) Schluessel: $($missingKeys -join ', ')"
    }

    if ($extraKeys.Count -gt 0)
    {
        Add-Failure "$GermanPath enthaelt $($extraKeys.Count) veraltete Schluessel: $($extraKeys -join ', ')"
    }
}

$resourcePairs = @(
    @('src\settings-ui\Settings.UI\Strings\en-us\Resources.resw', 'src\settings-ui\Settings.UI\Strings\de-DE\Resources.resw'),
    @('src\settings-ui\Settings.UI.Controls\Strings\en-us\Resources.resw', 'src\settings-ui\Settings.UI.Controls\Strings\de-DE\Resources.resw'),
    @('src\modules\AdvancedPaste\AdvancedPaste\Strings\en-us\Resources.resw', 'src\modules\AdvancedPaste\AdvancedPaste\Strings\de-DE\Resources.resw'),
    @('src\modules\FileLocksmith\FileLocksmithUI\Strings\en-us\Resources.resw', 'src\modules\FileLocksmith\FileLocksmithUI\Strings\de-DE\Resources.resw'),
    @('src\modules\imageresizer\ui\Strings\en-us\Resources.resw', 'src\modules\imageresizer\ui\Strings\de-DE\Resources.resw'),
    @('src\modules\MeasureTool\MeasureToolUI\Strings\en-us\Resources.resw', 'src\modules\MeasureTool\MeasureToolUI\Strings\de-DE\Resources.resw'),
    @('src\modules\peek\Peek.UI\Strings\en-us\Resources.resw', 'src\modules\peek\Peek.UI\Strings\de-DE\Resources.resw'),
    @('src\modules\powerdisplay\PowerDisplay\Strings\en-us\Resources.resw', 'src\modules\powerdisplay\PowerDisplay\Strings\de-DE\Resources.resw'),
    @('src\modules\powerrename\PowerRenameUILib\Strings\en-us\Resources.resw', 'src\modules\powerrename\PowerRenameUILib\Strings\de-DE\Resources.resw'),
    @('src\modules\ShortcutGuide\ShortcutGuide.Ui\Strings\en-us\Resources.resw', 'src\modules\ShortcutGuide\ShortcutGuide.Ui\Strings\de-DE\Resources.resw'),
    @('src\modules\colorPicker\ColorPickerUI\Properties\Resources.resx', 'src\modules\colorPicker\ColorPickerUI\Properties\Resources.de-DE.resx'),
    @('src\modules\FancyZones\editor\FancyZonesEditor\Properties\Resources.resx', 'src\modules\FancyZones\editor\FancyZonesEditor\Properties\Resources.de-DE.resx'),
    @('src\modules\PowerOCR\PowerOCR\Properties\Resources.resx', 'src\modules\PowerOCR\PowerOCR\Properties\Resources.de-DE.resx'),
    @('src\modules\Workspaces\WorkspacesEditor\Properties\Resources.resx', 'src\modules\Workspaces\WorkspacesEditor\Properties\Resources.de-DE.resx')
)
$expectedWpfSatellites = @(
    'PowerToys.ColorPickerUI.resources.dll',
    'PowerToys.FancyZonesEditor.resources.dll',
    'PowerToys.PowerOCR.resources.dll',
    'PowerToys.WorkspacesEditor.resources.dll')
$expectedWinUiMuiFiles = @(
    'Microsoft.ui.xaml.dll.mui',
    'Microsoft.UI.Xaml.Phone.dll.mui')

foreach ($pair in $resourcePairs)
{
    Test-LocalizedPair $pair[0] $pair[1]

    $germanPath = Join-Path $RepoRoot $pair[1]
    if (Test-Path -LiteralPath $germanPath)
    {
        $germanDocument = Read-XmlDocument $germanPath
        $mojibakeNodes = @($germanDocument.root.data | Where-Object {
            [string]$_.value -match '\u00C3|\u00C2|\u00E2\u20AC|\u00F0\u0178|\u00C4[\u0080-\u009F]|\u00E1\u00BB|\u00C6\u00B0'
        })
        if ($mojibakeNodes.Count -gt 0)
        {
            $examples = @($mojibakeNodes | Select-Object -First 5 | ForEach-Object { [string]$_.name })
            Add-Failure "$($pair[1]) enthaelt $($mojibakeNodes.Count) fehlcodierte Texte: $($examples -join ', ')"
        }
    }
}

$germanSettingsPath = Join-Path $RepoRoot 'src\settings-ui\Settings.UI\Strings\de-DE\Resources.resw'
if (Test-Path -LiteralPath $germanSettingsPath)
{
    $germanSettings = Read-XmlDocument $germanSettingsPath
    $expectedSettingsValues = @{
        'SettingsWindow_Title' = 'PowerToys-Einstellungen'
        'Shell_General.Content' = 'Allgemein'
        'Shell_Welcome.Content' = 'Erste Schritte'
        'Shell_AdvancedPaste.Content' = ('Erweitertes Einf' + [char]0x00FC + 'gen')
        'Shell_ImageResizer.Content' = ('Bildgr' + [char]0x00F6 + [char]0x00DF + 'en' + [char]0x00E4 + 'nderung')
    }

    foreach ($expected in $expectedSettingsValues.GetEnumerator())
    {
        $actualNode = $germanSettings.root.data | Where-Object { $_.name -eq $expected.Key }
        if (-not $actualNode -or [string]$actualNode.value -ne $expected.Value)
        {
            Add-Failure "Deutscher UI-Marker '$($expected.Key)' ist nicht '$($expected.Value)'."
        }
    }
}

$germanLocalizationWxsPath = Join-Path $RepoRoot 'installer\PowerToysSetupVNext\GermanLocalization.wxs'
if (Test-Path -LiteralPath $germanLocalizationWxsPath)
{
    $germanLocalizationWxs = Read-XmlDocument $germanLocalizationWxsPath
    $wixNamespace = [Xml.XmlNamespaceManager]::new($germanLocalizationWxs.NameTable)
    $wixNamespace.AddNamespace('wix', 'http://wixtoolset.org/schemas/v4/wxs')
    $removeFolder = $germanLocalizationWxs.SelectSingleNode(
        "//wix:Component[@Id='RemoveGermanLocalizationFolder']/wix:RemoveFolder[@Directory='GermanLocalizationInstallFolder' and @On='uninstall']",
        $wixNamespace)
    if (-not $removeFolder)
    {
        Add-Failure 'Der deutsche Installationsordner hat keinen WiX-Cleanup fuer die Deinstallation.'
    }

    if ($GeneratedWix)
    {
        $generatedComponent = $germanLocalizationWxs.SelectSingleNode(
            "//wix:Component[@Id='GermanLocalizationFiles_Component']",
            $wixNamespace)
        $generatedComponentRef = $germanLocalizationWxs.SelectSingleNode(
            "//wix:ComponentGroup[@Id='GermanLocalizationComponentGroup']/wix:ComponentRef[@Id='GermanLocalizationFiles_Component']",
            $wixNamespace)
        if (-not $generatedComponent -or -not $generatedComponentRef)
        {
            Add-Failure 'Der WiX-Harvester hat keine deutsche Satelliten-Komponente erzeugt.'
        }
        else
        {
            foreach ($satellite in $expectedWpfSatellites)
            {
                $file = $generatedComponent.SelectSingleNode("wix:File[substring(@Source, string-length(@Source) - string-length('$satellite') + 1) = '$satellite']", $wixNamespace)
                if (-not $file)
                {
                    Add-Failure "WiX-Satellit fehlt in GermanLocalizationFiles_Component: $satellite"
                }
            }
        }
    }
}
else
{
    Add-Failure 'GermanLocalization.wxs fehlt.'
}

$versionPropsPath = Join-Path $RepoRoot 'src\Version.props'
$expectedVersion = $null
if (-not (Test-Path -LiteralPath $versionPropsPath))
{
    Add-Failure "Version.props fehlt: $versionPropsPath"
}
else
{
    $versionDocument = Read-XmlDocument $versionPropsPath
    $expectedVersion = [string]$versionDocument.Project.PropertyGroup.Version
    if ($expectedVersion -notmatch '^\d+\.\d+\.\d+(?:\.\d+)?$')
    {
        Add-Failure "Ungueltige PowerToys-Version in Version.props: $expectedVersion"
    }

    $contextMenuManifests = @(
        'src\modules\FileLocksmith\FileLocksmithContextMenu\AppxManifest.xml',
        'src\modules\NewPlus\NewShellExtensionContextMenu\AppxManifest.xml',
        'src\modules\imageresizer\ImageResizerContextMenu\AppxManifest.xml',
        'src\modules\powerrename\PowerRenameContextMenu\AppxManifest.xml'
    )
    foreach ($relativeManifestPath in $contextMenuManifests)
    {
        $manifestPath = Join-Path $RepoRoot $relativeManifestPath
        $manifestDocument = Read-XmlDocument $manifestPath
        $manifestVersion = [string]$manifestDocument.Package.Identity.Version
        if ($manifestVersion -ne $expectedVersion)
        {
            Add-Failure "Kontextmenue-Version weicht von Version.props ab: $relativeManifestPath ($manifestVersion statt $expectedVersion)"
        }
    }
}

if ($BuildRoot)
{
    $resolvedBuildRoot = (Resolve-Path -LiteralPath $BuildRoot).Path
    if ($expectedVersion)
    {
        foreach ($relativeExecutablePath in @('PowerToys.exe', 'WinUI3Apps\PowerToys.Settings.exe'))
        {
            $executablePath = Join-Path $resolvedBuildRoot $relativeExecutablePath
            if (-not (Test-Path -LiteralPath $executablePath))
            {
                Add-Failure "Versioniertes Kernprogramm fehlt: $executablePath"
                continue
            }

            $actualVersion = (Get-Item -LiteralPath $executablePath).VersionInfo.FileVersion
            if ($actualVersion -ne $expectedVersion)
            {
                Add-Failure "Binaerversion weicht von Version.props ab: $relativeExecutablePath ($actualVersion statt $expectedVersion)"
            }
        }
    }

    $manifestPath = Join-Path $resolvedBuildRoot 'WinUI3Apps\hardlinks.txt'
    if (-not (Test-Path -LiteralPath $manifestPath))
    {
        Add-Failure "Hardlink-Manifest fehlt: $manifestPath"
    }
    else
    {
        $forbiddenXamlEntry = Get-Content -LiteralPath $manifestPath |
            Where-Object { $_.Trim().Equals('Microsoft.UI.Xaml.dll', [StringComparison]::OrdinalIgnoreCase) }
        if ($forbiddenXamlEntry)
        {
            Add-Failure 'hardlinks.txt darf Microsoft.UI.Xaml.dll nicht aus dem Root nach WinUI3Apps kopieren.'
        }

        $duplicates = @(Get-Content -LiteralPath $manifestPath | Group-Object | Where-Object { $_.Count -gt 1 })
        if ($duplicates.Count -gt 0)
        {
            Add-Failure "hardlinks.txt enthaelt doppelte Eintraege: $($duplicates.Name -join ', ')"
        }
    }

    $rootXamlPath = Join-Path $resolvedBuildRoot 'Microsoft.UI.Xaml.dll'
    $winUiXamlPath = Join-Path $resolvedBuildRoot 'WinUI3Apps\Microsoft.UI.Xaml.dll'
    if ((Test-Path -LiteralPath $rootXamlPath) -and (Test-Path -LiteralPath $winUiXamlPath))
    {
        $rootVersion = (Get-Item -LiteralPath $rootXamlPath).VersionInfo.FileVersion
        $winUiVersion = (Get-Item -LiteralPath $winUiXamlPath).VersionInfo.FileVersion
        if (-not $winUiVersion.StartsWith('3.'))
        {
            Add-Failure "WinUI3Apps enthaelt nicht WinUI 3: Root=$rootVersion, WinUI3Apps=$winUiVersion"
        }
    }
    else
    {
        Add-Failure 'Microsoft.UI.Xaml.dll fehlt im Root oder in WinUI3Apps.'
    }

    foreach ($satellite in $expectedWpfSatellites)
    {
        if (-not (Test-Path -LiteralPath (Join-Path $resolvedBuildRoot "de-DE\$satellite")))
        {
            Add-Failure "Gebautes deutsches WPF-Satellit fehlt: $satellite"
        }
    }

    foreach ($muiFile in $expectedWinUiMuiFiles)
    {
        if (-not (Test-Path -LiteralPath (Join-Path $resolvedBuildRoot "WinUI3Apps\de-DE\$muiFile")))
        {
            Add-Failure "Gebautes deutsches WinUI-Sprachmodul fehlt: $muiFile"
        }
    }

    $makePriPath = Resolve-MakePriPath
    if (-not $makePriPath)
    {
        Add-Failure 'makepri.exe fuer die Pruefung der gebauten PRI-Dateien nicht gefunden.'
    }
    else
    {
        $priChecks = @(
            @{ Map = 'PowerToys.Settings'; Pri = 'PowerToys.Settings.pri'; German = 'src\settings-ui\Settings.UI\Strings\de-DE\Resources.resw' },
            @{ Map = 'PowerToys.QuickAccess'; Pri = 'PowerToys.QuickAccess.pri'; German = 'src\settings-ui\Settings.UI\Strings\de-DE\Resources.resw' },
            @{ Map = 'PowerToys.Settings.UI.Controls'; Pri = 'PowerToys.Settings.UI.Controls.pri'; German = 'src\settings-ui\Settings.UI.Controls\Strings\de-DE\Resources.resw' },
            @{ Map = 'PowerToys.AdvancedPaste'; Pri = 'PowerToys.AdvancedPaste.pri'; German = 'src\modules\AdvancedPaste\AdvancedPaste\Strings\de-DE\Resources.resw' },
            @{ Map = 'PowerToys.FileLocksmithUI'; Pri = 'PowerToys.FileLocksmithUI.pri'; German = 'src\modules\FileLocksmith\FileLocksmithUI\Strings\de-DE\Resources.resw' },
            @{ Map = 'PowerToys.ImageResizer'; Pri = 'PowerToys.ImageResizer.pri'; German = 'src\modules\imageresizer\ui\Strings\de-DE\Resources.resw' },
            @{ Map = 'PowerToys.ImageResizerCLI'; Pri = 'PowerToys.ImageResizerCLI.pri'; German = 'src\modules\imageresizer\ui\Strings\de-DE\Resources.resw' },
            @{ Map = 'PowerToys.MeasureToolUI'; Pri = 'PowerToys.MeasureToolUI.pri'; German = 'src\modules\MeasureTool\MeasureToolUI\Strings\de-DE\Resources.resw' },
            @{ Map = 'PowerToys.Peek.UI'; Pri = 'PowerToys.Peek.UI.pri'; German = 'src\modules\peek\Peek.UI\Strings\de-DE\Resources.resw' },
            @{ Map = 'Peek.FilePreviewer'; Pri = 'Peek.FilePreviewer.pri'; German = 'src\modules\peek\Peek.UI\Strings\de-DE\Resources.resw' },
            @{ Map = 'PowerToys.PowerDisplay'; Pri = 'PowerToys.PowerDisplay.pri'; German = 'src\modules\powerdisplay\PowerDisplay\Strings\de-DE\Resources.resw' },
            @{ Map = 'PowerToys.PowerRename'; Pri = 'PowerToys.PowerRename.pri'; German = 'src\modules\powerrename\PowerRenameUILib\Strings\de-DE\Resources.resw' },
            @{ Map = 'PowerToys.ShortcutGuide'; Pri = 'PowerToys.ShortcutGuide.pri'; German = 'src\modules\ShortcutGuide\ShortcutGuide.Ui\Strings\de-DE\Resources.resw' },
            @{ Map = 'PowerToys.ShortcutGuide.IndexYmlGenerator'; Pri = 'PowerToys.ShortcutGuide.IndexYmlGenerator.pri'; German = 'src\modules\ShortcutGuide\ShortcutGuide.Ui\Strings\de-DE\Resources.resw' }
        )

        $tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
        $tempDirectory = [IO.Path]::GetFullPath((Join-Path $tempBase ('powertoys-pri-test-' + [guid]::NewGuid().ToString('N'))))
        if (-not $tempDirectory.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase) -or
            -not (Split-Path -Leaf $tempDirectory).StartsWith('powertoys-pri-test-'))
        {
            throw 'Unsicherer temporaerer PRI-Pruefpfad.'
        }

        New-Item -Path $tempDirectory -ItemType Directory | Out-Null
        try
        {
            foreach ($check in $priChecks)
            {
                $priPath = Join-Path $resolvedBuildRoot "WinUI3Apps\$($check.Pri)"
                if (-not (Test-Path -LiteralPath $priPath))
                {
                    Add-Failure "Gebautes PRI fehlt: $($check.Pri)"
                    continue
                }

                $dumpPath = Join-Path $tempDirectory ($check.Map + '.xml')
                & $makePriPath dump /if $priPath /of $dumpPath /dt detailed | Out-Null
                if ($LASTEXITCODE -ne 0)
                {
                    Add-Failure "makepri dump fehlgeschlagen: $($check.Pri)"
                    continue
                }

                $priDocument = Read-XmlDocument $dumpPath
                $resourceMap = $priDocument.SelectSingleNode("//ResourceMap[@name='$($check.Map)']")
                if (-not $resourceMap)
                {
                    Add-Failure "ResourceMap fehlt in $($check.Pri): $($check.Map)"
                    continue
                }

                $germanPriValues = @{}
                foreach ($resource in $resourceMap.SelectNodes('.//NamedResource'))
                {
                    $candidate = $resource.SelectSingleNode("./Candidate[QualifierSet/Qualifier[@name='Language' and translate(@value,'abcdefghijklmnopqrstuvwxyz','ABCDEFGHIJKLMNOPQRSTUVWXYZ')='DE-DE']]")
                    if (-not $candidate) { continue }
                    $marker = '/Resources/'
                    $markerIndex = $resource.uri.IndexOf($marker, [StringComparison]::OrdinalIgnoreCase)
                    if ($markerIndex -ge 0)
                    {
                        $germanPriValues[$resource.uri.Substring($markerIndex + $marker.Length)] = [string]$candidate.Value
                    }
                }

                $expectedKeys = Get-ResourceKeys (Join-Path $RepoRoot $check.German) |
                    ForEach-Object { Convert-ReswKeyToPriPath $_ }
                $missingCompiledKeys = @($expectedKeys | Where-Object { -not $germanPriValues.ContainsKey($_) })
                if ($missingCompiledKeys.Count -gt 0)
                {
                    Add-Failure "$($check.Pri) fehlen $($missingCompiledKeys.Count) kompilierte de-DE-Schluessel."
                }

                if ($check.Map -eq 'PowerToys.Settings')
                {
                    $expectedCompiledSettings = @{
                        'SettingsWindow_Title' = 'PowerToys-Einstellungen'
                        'Shell_AdvancedPaste/Content' = ('Erweitertes Einf' + [char]0x00FC + 'gen')
                        'Shell_ImageResizer/Content' = ('Bildgr' + [char]0x00F6 + [char]0x00DF + 'en' + [char]0x00E4 + 'nderung')
                    }
                    foreach ($expectedCompiledValue in $expectedCompiledSettings.GetEnumerator())
                    {
                        if ($germanPriValues[$expectedCompiledValue.Key] -cne $expectedCompiledValue.Value)
                        {
                            Add-Failure "PowerToys.Settings.pri enthaelt fuer $($expectedCompiledValue.Key) keinen korrekt codierten deutschen Text."
                        }
                    }
                }
            }
        }
        finally
        {
            if (Test-Path -LiteralPath $tempDirectory)
            {
                Remove-Item -LiteralPath $tempDirectory -Recurse -Force
            }
        }
    }
}

if ($failures.Count -gt 0)
{
    Write-Host "[RED] Minimal-Release-Pruefung fehlgeschlagen ($($failures.Count))." -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "  - $_" }
    exit 1
}

Write-Host "[GREEN] Deutsche Ressourcen und Minimal-Release-Invarianten sind vollstaendig." -ForegroundColor Green
