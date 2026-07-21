<#
Zentrale Modul-Datenbank fuer den konfigurierbaren minimierten Installer.
EINZIGE Wahrheitsquelle: Filter, Runner-Liste, Dashboard-Filter und WiX leiten sich hieraus ab.

Pro Modul:
  ModuleTypes   : ManagedCommon.ModuleType-Namen (fuer das Settings-Dashboard). Meist 1; MouseUtils = 4.
  RunnerDlls    : Eintraege fuer die knownModules-Liste des Runners (Pfad wie im Original).
  FilterPatterns: Datei-Globs, die AUSSCHLIESSLICH zu diesem Modul gehoeren (Release-/WinUI3Apps-Wurzel).
  WixGroups     : WiX-ComponentGroup-IDs, die bei Auswahl in Product.wxs referenziert werden.
  NeedsMonaco   : $true, wenn das Modul die Monaco-Editor-Assets braucht (Peek, RegistryPreview, FEP).
  Buildable     : $false = laesst sich in dieser Umgebung nicht bauen (nicht waehlbar).
  Note          : Hinweis.
#>

$ModuleDatabase = [ordered]@{
    # ---- Ohne eigene WiX-Gruppe (Binaries kommen aus dem Catch-all) ----
    'FancyZones'          = @{ ModuleTypes=@('FancyZones');       RunnerDlls=@('PowerToys.FancyZonesModuleInterface.dll'); FilterPatterns=@('PowerToys.FancyZones*'); WixGroups=@(); NeedsMonaco=$false; Buildable=$true }
    'AlwaysOnTop'         = @{ ModuleTypes=@('AlwaysOnTop');      RunnerDlls=@('PowerToys.AlwaysOnTopModuleInterface.dll'); FilterPatterns=@('PowerToys.AlwaysOnTop*'); WixGroups=@(); NeedsMonaco=$false; Buildable=$true }
    'CropAndLock'         = @{ ModuleTypes=@('CropAndLock');      RunnerDlls=@('PowerToys.CropAndLockModuleInterface.dll'); FilterPatterns=@('PowerToys.CropAndLock*'); WixGroups=@(); NeedsMonaco=$false; Buildable=$true }
    'TextExtractor'       = @{ ModuleTypes=@('PowerOCR');         RunnerDlls=@('PowerToys.PowerOCRModuleInterface.dll'); FilterPatterns=@('PowerToys.PowerOCR*'); WixGroups=@(); NeedsMonaco=$false; Buildable=$true }
    'QuickAccent'         = @{ ModuleTypes=@('PowerAccent');      RunnerDlls=@('PowerToys.PowerAccentModuleInterface.dll'); FilterPatterns=@('PowerToys.PowerAccent*'); WixGroups=@(); NeedsMonaco=$false; Buildable=$true }
    'ScreenRuler'         = @{ ModuleTypes=@('MeasureTool');      RunnerDlls=@('WinUI3Apps/PowerToys.MeasureToolModuleInterface.dll'); FilterPatterns=@('PowerToys.MeasureTool*'); WixGroups=@(); NeedsMonaco=$false; Buildable=$true }
    'GrabAndMove'         = @{ ModuleTypes=@('GrabAndMove');      RunnerDlls=@('PowerToys.CursorWrap.dll'); FilterPatterns=@('PowerToys.GrabAndMove*','PowerToys.CursorWrap*'); WixGroups=@(); NeedsMonaco=$false; Buildable=$true }
    'MouseUtils'          = @{ ModuleTypes=@('FindMyMouse','MouseHighlighter','MouseJump','MousePointerCrosshairs'); RunnerDlls=@('PowerToys.FindMyMouse.dll','PowerToys.MouseHighlighter.dll','PowerToys.MouseJump.dll','PowerToys.MousePointerCrosshairs.dll'); FilterPatterns=@('PowerToys.FindMyMouse*','PowerToys.MouseHighlighter*','PowerToys.MouseJump.dll','PowerToys.MouseJump.pdb','PowerToys.MouseJumpUI*','PowerToys.MousePointerCrosshairs*'); WixGroups=@(); NeedsMonaco=$false; Buildable=$true; Note='Mausdienstprogramme (4 Werkzeuge in einer Gruppe). MouseJump.Common.dll bleibt immer (Settings-Abhaengigkeit).' }

    # ---- Mit eigener WiX-Gruppe ----
    'Workspaces'          = @{ ModuleTypes=@('Workspaces');       RunnerDlls=@('PowerToys.WorkspacesModuleInterface.dll'); FilterPatterns=@('PowerToys.Workspaces*'); WixGroups=@('WorkspacesComponentGroup'); NeedsMonaco=$false; Buildable=$true }
    'ImageResizer'        = @{ ModuleTypes=@('ImageResizer');     RunnerDlls=@('WinUI3Apps/PowerToys.ImageResizerExt.dll'); FilterPatterns=@('PowerToys.ImageResizer*'); WixGroups=@('ImageResizerComponentGroup'); NeedsMonaco=$false; Buildable=$true }
    'FileLocksmith'       = @{ ModuleTypes=@('FileLocksmith');    RunnerDlls=@('WinUI3Apps/PowerToys.FileLocksmithExt.dll'); FilterPatterns=@('PowerToys.FileLocksmith*'); WixGroups=@('FileLocksmithComponentGroup'); NeedsMonaco=$false; Buildable=$true }
    'PowerRename'         = @{ ModuleTypes=@('PowerRename');      RunnerDlls=@('WinUI3Apps/PowerToys.PowerRenameExt.dll'); FilterPatterns=@('PowerToys.PowerRename*'); WixGroups=@('PowerRenameComponentGroup'); NeedsMonaco=$false; Buildable=$true }
    'Peek'                = @{ ModuleTypes=@('Peek');             RunnerDlls=@('WinUI3Apps/PowerToys.Peek.dll'); FilterPatterns=@('PowerToys.Peek.*','PowerToys.Peek.UI*'); WixGroups=@('PeekComponentGroup'); NeedsMonaco=$true; Buildable=$true }
    'ColorPicker'         = @{ ModuleTypes=@('ColorPicker');      RunnerDlls=@('PowerToys.ColorPicker.dll'); FilterPatterns=@('PowerToys.ColorPicker*'); WixGroups=@('ColorPickerComponentGroup'); NeedsMonaco=$false; Buildable=$true }
    'Awake'               = @{ ModuleTypes=@('Awake');            RunnerDlls=@('PowerToys.AwakeModuleInterface.dll'); FilterPatterns=@('PowerToys.Awake*'); WixGroups=@('AwakeComponentGroup'); NeedsMonaco=$false; Buildable=$true }
    'Hosts'               = @{ ModuleTypes=@('Hosts');            RunnerDlls=@('WinUI3Apps/PowerToys.HostsModuleInterface.dll'); FilterPatterns=@('PowerToys.Hosts*'); WixGroups=@('HostsComponentGroup'); NeedsMonaco=$false; Buildable=$true }
    'KeyboardManager'     = @{ ModuleTypes=@('KeyboardManager');  RunnerDlls=@('PowerToys.KeyboardManager.dll'); FilterPatterns=@('PowerToys.KeyboardManager*'); WixGroups=@('KeyboardManagerComponentGroup'); NeedsMonaco=$false; Buildable=$true }
    'EnvironmentVariables'= @{ ModuleTypes=@('EnvironmentVariables'); RunnerDlls=@('WinUI3Apps/PowerToys.EnvironmentVariablesModuleInterface.dll'); FilterPatterns=@('PowerToys.EnvironmentVariables*'); WixGroups=@('EnvironmentVariablesComponentGroup'); NeedsMonaco=$false; Buildable=$true }
    'RegistryPreview'     = @{ ModuleTypes=@('RegistryPreview');  RunnerDlls=@('WinUI3Apps/PowerToys.RegistryPreviewExt.dll'); FilterPatterns=@('PowerToys.RegistryPreview*'); WixGroups=@('RegistryPreviewComponentGroup'); NeedsMonaco=$true; Buildable=$true }
    'ShortcutGuide'       = @{ ModuleTypes=@('ShortcutGuide');    RunnerDlls=@('PowerToys.ShortcutGuideModuleInterface.dll'); FilterPatterns=@('PowerToys.ShortcutGuide*'); WixGroups=@('ShortcutGuideComponentGroup'); NeedsMonaco=$false; Buildable=$true }
    'MouseWithoutBorders' = @{ ModuleTypes=@('MouseWithoutBorders'); RunnerDlls=@('PowerToys.MouseWithoutBordersModuleInterface.dll'); FilterPatterns=@('PowerToys.MouseWithoutBorders*'); WixGroups=@('MouseWithoutBordersComponentGroup'); NeedsMonaco=$false; Buildable=$true }
    'AdvancedPaste'       = @{ ModuleTypes=@('AdvancedPaste');    RunnerDlls=@('PowerToys.AdvancedPasteModuleInterface.dll'); FilterPatterns=@('PowerToys.AdvancedPaste*'); WixGroups=@('AdvancedPasteComponentGroup'); NeedsMonaco=$false; Buildable=$true }
    'NewPlus'             = @{ ModuleTypes=@('NewPlus');          RunnerDlls=@('WinUI3Apps/PowerToys.NewPlus.ShellExtension.dll'); FilterPatterns=@('PowerToys.NewPlus*'); WixGroups=@('NewPlusComponentGroup','NewPlusTemplatesComponentGroup'); NeedsMonaco=$false; Buildable=$true }
    'PowerDisplay'        = @{ ModuleTypes=@('PowerDisplay');     RunnerDlls=@('PowerToys.PowerDisplayModuleInterface.dll'); FilterPatterns=@('PowerToys.PowerDisplay.dll','PowerToys.PowerDisplay.exe','PowerToys.PowerDisplay.pdb','PowerToys.PowerDisplayModuleInterface*'); WixGroups=@('PowerDisplayComponentGroup'); NeedsMonaco=$false; Buildable=$true; Note='PowerDisplay.Models.dll bleibt immer (Settings-Abhaengigkeit).' }
    'LightSwitch'         = @{ ModuleTypes=@('LightSwitch');      RunnerDlls=@('PowerToys.LightSwitchModuleInterface.dll'); FilterPatterns=@('PowerToys.LightSwitch*'); WixGroups=@('LightSwitchComponentGroup'); NeedsMonaco=$false; Buildable=$true }
    'FileExplorerPreview' = @{ ModuleTypes=@();                   RunnerDlls=@('PowerToys.powerpreview.dll'); FilterPatterns=@('PowerToys.powerpreview*','PowerToys.Markdown*','PowerToys.Svg*','PowerToys.Pdf*','PowerToys.Gcode*','PowerToys.Bgcode*','PowerToys.Qoi*','PowerToys.Stl*','PowerToys.MonacoPreviewHandler*'); WixGroups=@('FileExplorerPreviewComponentGroup'); NeedsMonaco=$true; Buildable=$true; Note='Datei-Explorer-Vorschauhandler. Achtung: liefert auch die Monaco-Assets, die Peek braucht.' }

    # ---- Nicht in dieser Umgebung baubar / nicht unterstuetzt ----
    'CmdPal'              = @{ ModuleTypes=@('CmdPal');           RunnerDlls=@('PowerToys.CmdPalModuleInterface.dll'); FilterPatterns=@('PowerToys.CmdPal*','Microsoft.CmdPal*','Microsoft.CommandPalette*'); WixGroups=@('CmdPalComponentGroup'); NeedsMonaco=$false; Buildable=$false; Note='Command Palette: AOT-Build scheitert mit VS 2022 (braucht VS 2026).' }
    'ZoomIt'              = @{ ModuleTypes=@('ZoomIt');           RunnerDlls=@('PowerToys.ZoomItModuleInterface.dll'); FilterPatterns=@('PowerToys.ZoomItModuleInterface*'); WixGroups=@(); NeedsMonaco=$false; Buildable=$false; Note='ZoomIt: Plattform-Toolset v145 noetig (VS 2026). ZoomItSettingsInterop.dll bleibt immer (Settings-Abhaengigkeit).' }
    'Run'                 = @{ ModuleTypes=@('PowerLauncher');    RunnerDlls=@('PowerToys.Launcher.dll'); FilterPatterns=@('PowerToys.PowerLauncher*','PowerToys.Launcher*','Wox.*'); WixGroups=@('RunComponentGroup'); NeedsMonaco=$false; Buildable=$false; Note='PowerToys Run: tiefe Kopplung an Resources.wxs/RunPlugins; im minimierten Setup derzeit nicht unterstuetzt.' }
}

# Dateien, die NIE geloescht werden, obwohl sie zu einem (evtl. abgewaehlten) Modul passen -
# die Settings-UI laedt sie zur Laufzeit.
$FilterKeepAlways = @(
    'PowerToys.MouseJump.Common.dll',
    'PowerToys.ZoomItSettingsInterop.dll',
    'PowerDisplay.Models.dll'
)
