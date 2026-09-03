<#
.SYNOPSIS
Imports German strings from a matching official PowerToys build into source-level RESW/RESX files.

.DESCRIPTION
The public PowerToys source tree contains only en-US application resources. Official builds add
translations in Microsoft's localization pipeline. This script extracts only the de-DE string
values from an official build and merges them into the current source resource files. It never
copies PRI or satellite binaries, so current XAML/code and assembly versions stay consistent.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OfficialRoot,

    [string]$RepoRoot,

    [string]$MakePriPath
)

$ErrorActionPreference = 'Stop'
if (-not $RepoRoot)
{
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}
$OfficialRoot = (Resolve-Path -LiteralPath $OfficialRoot).Path

function Resolve-MakePriPath
{
    if ($MakePriPath)
    {
        return (Resolve-Path -LiteralPath $MakePriPath).Path
    }

    $kitsRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    $candidate = Get-ChildItem -LiteralPath $kitsRoot -Filter 'makepri.exe' -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Directory.Name -eq 'x64' } |
        Sort-Object { try { [version]$_.Directory.Parent.Name } catch { [version]'0.0' } } -Descending |
        Select-Object -First 1
    if (-not $candidate)
    {
        throw 'makepri.exe wurde im Windows SDK nicht gefunden.'
    }

    return $candidate.FullName
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

function Read-XmlDocument([string]$Path)
{
    # XmlDocument.Load honors the XML declaration even in Windows PowerShell 5.1.
    # Get-Content -Raw decodes BOM-less UTF-8 as the active ANSI code page there and
    # silently turns German umlauts from makepri dumps into mojibake.
    $document = [Xml.XmlDocument]::new()
    $document.PreserveWhitespace = $false
    $document.Load($Path)
    return ,$document
}

function Save-Xml([xml]$Document, [string]$Path)
{
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory))
    {
        New-Item -Path $directory -ItemType Directory | Out-Null
    }

    $settings = [Xml.XmlWriterSettings]::new()
    $settings.Encoding = [Text.UTF8Encoding]::new($false)
    $settings.Indent = $true
    $settings.IndentChars = '  '
    $settings.NewLineChars = "`r`n"
    $settings.NewLineHandling = [Xml.NewLineHandling]::Replace
    $writer = [Xml.XmlWriter]::Create($Path, $settings)
    try
    {
        $Document.Save($writer)
    }
    finally
    {
        $writer.Dispose()
    }

    # The upstream RESW/RESX schema comments contain trailing spaces. Keep the
    # generated sources clean so git diff --check remains useful.
    $utf8NoBom = [Text.UTF8Encoding]::new($false)
    $content = [IO.File]::ReadAllText($Path, $utf8NoBom)
    $content = [Text.RegularExpressions.Regex]::Replace(
        $content,
        '[ \t]+(?=\r?$)',
        '',
        [Text.RegularExpressions.RegexOptions]::Multiline)
    [IO.File]::WriteAllText($Path, $content, $utf8NoBom)
}

$fallbackGerman = @{
    'PowerToys.Settings|MeasureTool_UnitsOfMeasure.Description' = ('Ger' + [char]0x00E4 + 'teunabh' + [char]0x00E4 + 'ngige Pixel ber' + [char]0x00FC + 'cksichtigen die Windows-Anzeigeskalierung.')
    'PowerToys.Settings|MeasureTool_UnitsOfMeasure_DIP.Content' = ('Ger' + [char]0x00E4 + 'teunabh' + [char]0x00E4 + 'ngige Pixel (DIP)')
    'PowerToys.Settings|Shell_Awake.Content' = 'Awake'
    'PowerToys.Settings|Shell_FancyZones.Content' = 'FancyZones'
    'PowerToys.Settings|FileExplorerPreview_ToggleSwitch_Preview_MD.Description' = '.md, .markdown, .mdown, .mkdn, .mkd, .mdwn, .mdtxt, .mdtext'
    'PowerToys.Settings|FileExplorerPreview_ToggleSwitch_Preview_Monaco.Description' = '.txt, .cpp, .py, .json, .xml, .csproj, ...'
    'PowerToys.Settings|FileExplorerPreview_ToggleSwitch_Preview_SVG.Description' = '.svg'
    'PowerToys.Settings|FileExplorerPreview_ToggleSwitch_Preview_PDF.Header' = 'Portable-Dokumentformat'
    'PowerToys.Settings|FileExplorerPreview_ToggleSwitch_Preview_PDF.Description' = '.pdf'
    'PowerToys.Settings|FileExplorerPreview_ToggleSwitch_Thumbnail_SVG.Header' = 'Skalierbare Vektorgrafiken'
    'PowerToys.Settings|FileExplorerPreview_ToggleSwitch_Thumbnail_SVG.Description' = '.svg'
    'PowerToys.Settings|FileExplorerPreview_ToggleSwitch_Thumbnail_STL.Description' = '.stl'
    'PowerToys.Settings|FileExplorerPreview_ToggleSwitch_Preview_QOI.Header' = 'Quite OK Image'
    'PowerToys.Settings|FileExplorerPreview_ToggleSwitch_Preview_QOI.Description' = '.qoi'
    'PowerToys.Settings|FileExplorerPreview_ToggleSwitch_Thumbnail_QOI.Header' = 'Quite OK Image'
    'PowerToys.Settings|FileExplorerPreview_ToggleSwitch_Thumbnail_QOI.Description' = '.qoi'
    'PowerToys.Settings|FileExplorerPreview_ToggleSwitch_Thumbnail_PDF.Header' = 'Portable-Dokumentformat'
    'PowerToys.Settings|FileExplorerPreview_ToggleSwitch_Thumbnail_PDF.Description' = '.pdf'
    'PowerToys.Settings|ImageResizer_ENCODER_TIFF_CCITT3.Content' = 'CCITT3'
    'PowerToys.Settings|ImageResizer_ENCODER_TIFF_CCITT4.Content' = 'CCITT4'
    'PowerToys.Settings|ImageResizer_ENCODER_TIFF_LZW.Content' = 'LZW'
    'PowerToys.Settings|ImageResizer_ENCODER_TIFF_RLE.Content' = 'RLE'
    'PowerToys.Settings|ImageResizer_ENCODER_TIFF_Zip.Content' = 'Zip'
    'PowerToys.Settings|FancyZones.ModuleTitle' = 'FancyZones'
    'PowerToys.Settings|Shell_AlwaysOnTop.Content' = 'Immer im Vordergrund'
    'PowerToys.Settings|Oobe_AlwaysOnTop.Title' = 'Immer im Vordergrund'
    'PowerToys.Settings|LightSwitch_PowerDisplayDisabledWarningBar.Message' = ''
    'PowerToys.MeasureToolUI|MeasurementUnitAbbrDip' = 'DIP'
    'PowerToys.Peek.UI|UnsupportedFile_FolderContains' = ('Enth' + [char]0x00E4 + 'lt: {0}')
    'PowerToys.Peek.UI|UnsupportedFile_FolderFileCount_Single' = '1 Datei'
    'PowerToys.Peek.UI|UnsupportedFile_FolderFileCount_Plural' = '{0:N0} Dateien'
    'PowerToys.Peek.UI|UnsupportedFile_FolderDirectoryCount_Single' = '1 Ordner'
    'PowerToys.Peek.UI|UnsupportedFile_FolderDirectoryCount_Plural' = '{0:N0} Ordner'
    'PowerToys.Peek.UI|UnsupportedFile_FolderContains_Scanning' = ('Wird gescannt' + [char]0x00A0 + [char]0x2026)
    'PowerToys.Peek.UI|UnsupportedFile_FolderContains_Incomplete' = ('unvollst' + [char]0x00E4 + 'ndig')
    'PowerToys.Peek.UI|Sqlite_Table_Count' = '{0} Tabellen'
    'PowerToys.Peek.UI|Sqlite_Row_Count' = ('Datens' + [char]0x00E4 + 'tze: {0}')
    'PowerToys.Peek.UI|Sqlite_Row_Count_Truncated' = ('Datens' + [char]0x00E4 + 'tze: {0} von {1}')
    'PowerToys.Peek.UI|Sqlite_Blob_Value' = '[BLOB, {0} Byte]'
}

$reswSets = @(
    @{ Map = 'PowerToys.Settings'; Pri = 'PowerToys.Settings.pri'; Source = 'src\settings-ui\Settings.UI\Strings\en-us\Resources.resw'; Destination = 'src\settings-ui\Settings.UI\Strings\de-DE\Resources.resw' },
    @{ Map = 'PowerToys.Settings.UI.Controls'; Pri = 'PowerToys.Settings.UI.Controls.pri'; Source = 'src\settings-ui\Settings.UI.Controls\Strings\en-us\Resources.resw'; Destination = 'src\settings-ui\Settings.UI.Controls\Strings\de-DE\Resources.resw' },
    @{ Map = 'PowerToys.AdvancedPaste'; Pri = 'PowerToys.AdvancedPaste.pri'; Source = 'src\modules\AdvancedPaste\AdvancedPaste\Strings\en-us\Resources.resw'; Destination = 'src\modules\AdvancedPaste\AdvancedPaste\Strings\de-DE\Resources.resw' },
    @{ Map = 'PowerToys.FileLocksmithUI'; Pri = 'PowerToys.FileLocksmithUI.pri'; Source = 'src\modules\FileLocksmith\FileLocksmithUI\Strings\en-us\Resources.resw'; Destination = 'src\modules\FileLocksmith\FileLocksmithUI\Strings\de-DE\Resources.resw' },
    @{ Map = 'PowerToys.ImageResizer'; Pri = 'PowerToys.ImageResizer.pri'; Source = 'src\modules\imageresizer\ui\Strings\en-us\Resources.resw'; Destination = 'src\modules\imageresizer\ui\Strings\de-DE\Resources.resw' },
    @{ Map = 'PowerToys.MeasureToolUI'; Pri = 'PowerToys.MeasureToolUI.pri'; Source = 'src\modules\MeasureTool\MeasureToolUI\Strings\en-us\Resources.resw'; Destination = 'src\modules\MeasureTool\MeasureToolUI\Strings\de-DE\Resources.resw' },
    @{ Map = 'PowerToys.Peek.UI'; Pri = 'PowerToys.Peek.UI.pri'; Source = 'src\modules\peek\Peek.UI\Strings\en-us\Resources.resw'; Destination = 'src\modules\peek\Peek.UI\Strings\de-DE\Resources.resw' },
    @{ Map = 'PowerToys.PowerDisplay'; Pri = 'PowerToys.PowerDisplay.pri'; Source = 'src\modules\powerdisplay\PowerDisplay\Strings\en-us\Resources.resw'; Destination = 'src\modules\powerdisplay\PowerDisplay\Strings\de-DE\Resources.resw' },
    @{ Map = 'PowerToys.PowerRename'; Pri = 'PowerToys.PowerRename.pri'; Source = 'src\modules\powerrename\PowerRenameUILib\Strings\en-us\Resources.resw'; Destination = 'src\modules\powerrename\PowerRenameUILib\Strings\de-DE\Resources.resw' },
    @{ Map = 'PowerToys.ShortcutGuide'; Pri = 'PowerToys.ShortcutGuide.pri'; Source = 'src\modules\ShortcutGuide\ShortcutGuide.Ui\Strings\en-us\Resources.resw'; Destination = 'src\modules\ShortcutGuide\ShortcutGuide.Ui\Strings\de-DE\Resources.resw' }
)

$resxSets = @(
    @{ Satellite = 'PowerToys.ColorPickerUI.resources.dll'; Source = 'src\modules\colorPicker\ColorPickerUI\Properties\Resources.resx'; Destination = 'src\modules\colorPicker\ColorPickerUI\Properties\Resources.de-DE.resx' },
    @{ Satellite = 'PowerToys.FancyZonesEditor.resources.dll'; Source = 'src\modules\FancyZones\editor\FancyZonesEditor\Properties\Resources.resx'; Destination = 'src\modules\FancyZones\editor\FancyZonesEditor\Properties\Resources.de-DE.resx' },
    @{ Satellite = 'PowerToys.PowerOCR.resources.dll'; Source = 'src\modules\PowerOCR\PowerOCR\Properties\Resources.resx'; Destination = 'src\modules\PowerOCR\PowerOCR\Properties\Resources.de-DE.resx' },
    @{ Satellite = 'PowerToys.WorkspacesEditor.resources.dll'; Source = 'src\modules\Workspaces\WorkspacesEditor\Properties\Resources.resx'; Destination = 'src\modules\Workspaces\WorkspacesEditor\Properties\Resources.de-DE.resx' }
)

$resolvedMakePri = Resolve-MakePriPath
$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
$tempDirectory = [IO.Path]::GetFullPath((Join-Path $tempBase ('powertoys-german-' + [guid]::NewGuid().ToString('N'))))
if (-not $tempDirectory.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase) -or
    -not (Split-Path -Leaf $tempDirectory).StartsWith('powertoys-german-'))
{
    throw 'Unsicherer temporaerer Verzeichnispfad.'
}

New-Item -Path $tempDirectory -ItemType Directory | Out-Null
try
{
    foreach ($set in $reswSets)
    {
        $priPath = Join-Path (Join-Path $OfficialRoot 'WinUI3Apps') $set.Pri
        if (-not (Test-Path -LiteralPath $priPath))
        {
            throw "Offizielle PRI fehlt: $priPath"
        }

        $dumpPath = Join-Path $tempDirectory ($set.Map + '.xml')
        & $resolvedMakePri dump /if $priPath /of $dumpPath /dt detailed | Out-Null
        if ($LASTEXITCODE -ne 0)
        {
            throw "makepri dump fehlgeschlagen fuer $($set.Pri)."
        }

        $priDocument = Read-XmlDocument $dumpPath
        $resourceMap = $priDocument.SelectSingleNode("//ResourceMap[@name='$($set.Map)']")
        if (-not $resourceMap)
        {
            throw "ResourceMap '$($set.Map)' fehlt in $($set.Pri)."
        }

        $germanValues = @{}
        foreach ($resource in $resourceMap.SelectNodes('.//NamedResource'))
        {
            $candidate = $resource.SelectSingleNode("./Candidate[QualifierSet/Qualifier[@name='Language' and translate(@value,'abcdefghijklmnopqrstuvwxyz','ABCDEFGHIJKLMNOPQRSTUVWXYZ')='DE-DE']]")
            if (-not $candidate) { continue }

            $marker = '/Resources/'
            $markerIndex = $resource.uri.IndexOf($marker, [StringComparison]::OrdinalIgnoreCase)
            if ($markerIndex -lt 0) { continue }
            $resourcePath = $resource.uri.Substring($markerIndex + $marker.Length)
            $germanValues[$resourcePath] = [string]$candidate.Value
        }

        $sourcePath = Join-Path $RepoRoot $set.Source
        $destinationPath = Join-Path $RepoRoot $set.Destination
        $localizedDocument = Read-XmlDocument $sourcePath
        $missing = [System.Collections.Generic.List[string]]::new()
        foreach ($dataNode in @($localizedDocument.root.data))
        {
            $key = [string]$dataNode.name
            $resourcePath = Convert-ReswKeyToPriPath $key
            $fallbackKey = "$($set.Map)|$key"
            if ($germanValues.ContainsKey($resourcePath))
            {
                $value = $germanValues[$resourcePath]
            }
            elseif ($fallbackGerman.ContainsKey($fallbackKey))
            {
                $value = $fallbackGerman[$fallbackKey]
            }
            else
            {
                $missing.Add($key)
                continue
            }

            $dataNode.SelectSingleNode('value').InnerText = $value
        }

        if ($missing.Count -gt 0)
        {
            throw "$($set.Map): keine deutsche Uebersetzung fuer $($missing -join ', ')"
        }

        Save-Xml $localizedDocument $destinationPath
        Write-Host "[GERMAN] $($set.Map): $(@($localizedDocument.root.data).Count) RESW-Texte importiert."
    }

    $officialGermanDirectory = Join-Path $OfficialRoot 'de-DE'
    foreach ($set in $resxSets)
    {
        $satellitePath = Join-Path $officialGermanDirectory $set.Satellite
        if (-not (Test-Path -LiteralPath $satellitePath))
        {
            throw "Offizielles Satellitenassembly fehlt: $satellitePath"
        }

        $assembly = [Reflection.Assembly]::LoadFile($satellitePath)
        $manifestResource = @($assembly.GetManifestResourceNames() | Where-Object { $_.EndsWith('.resources', [StringComparison]::OrdinalIgnoreCase) })
        if ($manifestResource.Count -ne 1)
        {
            throw "$($set.Satellite): genau eine eingebettete .resources-Datei erwartet."
        }

        $stream = $assembly.GetManifestResourceStream($manifestResource[0])
        $reader = [Resources.ResourceReader]::new($stream)
        $germanValues = @{}
        try
        {
            $enumerator = $reader.GetEnumerator()
            while ($enumerator.MoveNext())
            {
                $germanValues[[string]$enumerator.Key] = [string]$enumerator.Value
            }
        }
        finally
        {
            $reader.Dispose()
            $stream.Dispose()
        }

        $sourcePath = Join-Path $RepoRoot $set.Source
        $destinationPath = Join-Path $RepoRoot $set.Destination
        $localizedDocument = Read-XmlDocument $sourcePath
        $missing = [System.Collections.Generic.List[string]]::new()
        foreach ($dataNode in @($localizedDocument.root.data))
        {
            $key = [string]$dataNode.name
            if (-not $germanValues.ContainsKey($key))
            {
                $missing.Add($key)
                continue
            }

            $dataNode.SelectSingleNode('value').InnerText = $germanValues[$key]
        }

        if ($missing.Count -gt 0)
        {
            throw "$($set.Satellite): keine deutsche Uebersetzung fuer $($missing -join ', ')"
        }

        Save-Xml $localizedDocument $destinationPath
        Write-Host "[GERMAN] $($set.Satellite): $(@($localizedDocument.root.data).Count) RESX-Texte importiert."
    }
}
finally
{
    if (Test-Path -LiteralPath $tempDirectory)
    {
        Remove-Item -LiteralPath $tempDirectory -Recurse -Force
    }
}

Write-Host '[GERMAN] Deutsche Quellressourcen vollstaendig aktualisiert.'
