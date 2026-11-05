# Standalone PowerToys module assessment

As of November 5, 2026, ten experimental portable packages are available on branch
`codex/portable-first-modules`. They include FancyZones, Color Picker, Text Extractor,
Image Resizer, Power Display, Always On Top, File Locksmith, Peek, Crop And Lock, and
Advanced Paste with AI blocked. Each has German graphical settings and tray controls.
The minimal installer is maintained on branch `minimal-installer-main`.
[Portable release](https://github.com/naturian/PowerToys/releases/tag/portable-v0.102.3001.0)
and [minimal installer release](https://github.com/naturian/PowerToys/releases/tag/minimal-main-2026-09-02).

Each package contains an executable and its runtime files. Application settings and logs
are stored under `Data/Microsoft/PowerToys` in its directory. Usage, build instructions,
and limitations are documented in the portable branch.
[Portable documentation](https://github.com/naturian/PowerToys/blob/codex/portable-first-modules/tools/portable/README.md).

The assessment below records the upstream starting conditions and the work required for
standalone modules. Its stable comparison baseline is tag `v0.102.3001`, commit
`a00b2bce7403f0a48efe5cbb6671074e01f27824`, released on October 27, 2026. The entry points
examined in the earlier `0.102.2883.0` checkout were compared with that tag and had matching
startup requirements. The assessment is based on source inspection. Package execution tests
for the ten implemented modules are reported separately in the portable release notes.
[Microsoft release](https://github.com/microsoft/PowerToys/releases/tag/v0.102.3001).

## Portability definitions

**Installation-free** means extracting a complete application directory and running it
from there. Application settings and logs may still use the Windows user profile.

**Portable application data** additionally keeps settings, history, and logs in a movable
data directory. This requires a shared configurable data path. Windows manages its own
execution history and operating-system data.

The four examined WinUI applications import `Common.SelfContained.props` and enable
`WindowsAppSDKSelfContained=true`. Their runtime files, native libraries, and resources
belong in the package. [ColorPicker-Project], [ImageResizer-Project]

## Assessment of the 20 selected module groups

Effort describes a standalone application directory with the existing functionality.
A portable data path and a shared launcher can require further work. The ratings describe
architecture and expected scope. Actual delivery and functionality require validation.

| Module group | Assessment | Entry points and constraints |
| --- | --- | --- |
| ZoomIt | Low, official standalone version available | Starts independently of the Runner. The Sysinternals version is available separately and stores settings in the registry. [ZoomIt-Entry], [ZoomIt-Registry] |
| Image Resizer | Low | Starts independently, accepts file paths, or opens a file picker. The Explorer menu requires additional integration. [ImageResizer-Entry] |
| File Locksmith | Low for CLI, medium for GUI | The CLI processes its own arguments. The upstream GUI reads its selection from a file in the PowerToys user profile. An independent GUI needs its own file input. [FileLocksmith-CLI], [FileLocksmith-Selection] |
| Color Picker | Low | Detects standalone startup and enables its own keyboard hook. Settings and color history initially use the user profile. [ColorPicker-Entry], [ColorPicker-Hook] |
| Text Extractor | Low | Starts its own KeyboardMonitor when the Runner PID is absent. Recognition depends on Windows OCR language support. [OCR-Entry], [OCR-Backend] |
| FancyZones | Medium | The Runner PID is optional. FancyZones installs its own keyboard and window hooks. Packaging must include the editor and layout data. [FancyZones-Entry], [FancyZones-Hook] |
| Always On Top | Low to medium | The Runner PID is optional and independent hotkey registration exists. A standalone package needs start and stop controls and a portable settings path. [AlwaysOnTop-Entry], [AlwaysOnTop-Hotkeys] |
| Crop And Lock | Medium | Upstream startup requires the Runner. Named events activate its actions. A standalone launcher must take over that control. [CropAndLock-Entry] |
| Grab And Move | Medium | Requires a Runner PID and uses the Runner lifecycle and named Settings and exit events. [GrabAndMove-Entry] |
| Screen Ruler | Low to medium | Runner PID monitoring is optional and the interface is created independently. Packaging must include the native MeasureToolCore library. [ScreenRuler-Entry] |
| Power Display | Low to medium | Provides a standalone mode with its own window and tray. Hardware access and the associated libraries are required. [PowerDisplay-Entry] |
| Light Switch | Medium | Its helper process can run independently of the Windows service manager. The CLI communicates with it over IPC. Changing the Windows theme writes registry values. [LightSwitch-Entry], [LightSwitch-CLI], [LightSwitch-Theme] |
| Mouse Utilities | Medium to high for the complete group | Several tools are Runner DLL modules. Mouse Jump also requires a Runner PID and activation events. The five selected tools need a shared host or standalone startup logic. [MouseUtils-Host], [MouseJump-Entry] |
| Window Hopper | Medium | Implements the PowerToys module interface as a DLL. Its host provides hotkey descriptions and activation callbacks. [WindowHopper-Host] |
| Advanced Paste | Low for CLI, medium for GUI | The CLI has its own entry point and a shared engine. GUI display and action commands arrive through a pipe. Every package must preserve this fork's AI restriction. [AdvancedPaste-CLI], [AdvancedPaste-GUI] |
| New+ | High with standalone file selection | Its primary interface is an Explorer extension. Module startup registers COM context menus or a sparse package. A standalone package needs an equivalent interface or system registration. [NewPlus-Host], [NewPlus-Registration] |
| PowerRename | Low to medium with standalone file selection | Its interface accepts explicit paths and also supports pipe or standard input. Direct file launch is plausible. The original Explorer menu requires registration. [PowerRename-Entry], [PowerRename-Registration] |
| Peek | Low to medium with file paths | Distinguishes Runner invocation from direct CLI invocation with paths. Explorer hotkey behavior and preview dependencies require additional work. [Peek-Entry] |
| Workspaces | Medium | The editor starts with an optional Runner PID. A complete package also includes capture, launcher, and arrangement processes and workspace data. [Workspaces-Entry] |
| Shortcut Guide | Medium | The PID is optional. Its initially hidden interface waits for activation events. A standalone tool needs activation controls or its own hotkey handling. [ShortcutGuide-Entry], [ShortcutGuide-Events] |

## Shared work

A **launcher** can start and stop application directories and handle Runner hotkeys and
activation events. DLL modules also require an implementation of their module interface.
Data-path handling is a separate responsibility. [WindowHopper-Host], [CropAndLock-Entry]

A **shared data path** requires changes to native and managed code. The native SettingsAPI
uses `SHGetKnownFolderPath(FOLDERID_LocalAppData)` and creates `Microsoft\PowerToys`.
Managed settings and logging use the same user area. Image Resizer also has a dedicated
settings path. Changing `LOCALAPPDATA` alone leaves native Known Folder calls using the
Windows user profile. [Native-DataRoot], [Managed-DataRoot], [Managed-Logs], [ImageResizer-Data]

**Explorer integration** requires COM, registry, or sparse-package registration for New+,
PowerRename, Image Resizer, and File Locksmith. Registration at startup and cleanup at exit
must handle crashes and moved application directories. File pickers and explicit paths provide
independent file input. New+ would need an alternative to its Explorer-based interface.
[NewPlus-Registration], [PowerRename-Registration], [Explorer-Manifest]

ZoomIt's standalone distribution demonstrates the distinction between installation-free
execution and portable application data. Microsoft provides a separate download and
Sysinternals Live entry point. Its source stores settings under
`HKCU\Software\Sysinternals\ZoomIt`. [ZoomIt-Registry]
and [official standalone distribution](https://learn.microsoft.com/en-us/sysinternals/downloads/zoomit).

The original source assessment identified ZoomIt, Image Resizer, Color Picker, Text Extractor,
and the File Locksmith CLI as a small initial scope. FancyZones and PowerRename also have
entry points suitable for standalone adaptation. Current implementation and test coverage
are described in the portable release and documentation linked above.

## Source references

These permalinks refer to immutable upstream files from the stable baseline. Local paths
match the linked repository paths. This fork adds its AI restriction in
`src/modules/AdvancedPaste/AdvancedPaste.Engine/AdvancedPastePolicy.cs`.

[ColorPicker-Project]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/colorPicker/ColorPickerUI/ColorPickerUI.csproj#L4-L19
[ImageResizer-Project]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/imageresizer/ui/ImageResizerUI.csproj#L4-L20
[ZoomIt-Entry]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/ZoomIt/ZoomIt/Zoomit.cpp#L13064-L13099
[ZoomIt-Registry]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/ZoomIt/ZoomIt/Zoomit.cpp#L280
[ImageResizer-Entry]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/imageresizer/ui/ImageResizerXAML/App.xaml.cs#L102-L129
[FileLocksmith-CLI]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/FileLocksmith/FileLocksmithCLI/main.cpp#L52-L67
[FileLocksmith-Selection]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/FileLocksmith/FileLocksmithLibInterop/NativeMethods.cpp#L14-L21
[ColorPicker-Entry]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/colorPicker/ColorPickerUI/ColorPickerXAML/App.xaml.cs#L84-L99
[ColorPicker-Hook]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/colorPicker/ColorPickerUI/ViewModels/MainViewModel.cs#L84-L88
[OCR-Entry]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/PowerOCR/PowerOCR/PowerOCRXAML/App.xaml.cs#L127-L143
[OCR-Backend]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/PowerOCR/PowerOCR.Core/Ocr/WindowsOcrRecognizer.cs#L19-L29
[FancyZones-Entry]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/fancyzones/FancyZones/main.cpp#L67-L88
[FancyZones-Hook]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/fancyzones/FancyZones/FancyZonesApp.cpp#L76-L103
[AlwaysOnTop-Entry]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/alwaysontop/AlwaysOnTop/main.cpp#L48-L68
[AlwaysOnTop-Hotkeys]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/alwaysontop/AlwaysOnTop/AlwaysOnTop.cpp#L364-L383
[CropAndLock-Entry]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/CropAndLock/CropAndLock/main.cpp#L96-L105
[GrabAndMove-Entry]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/GrabAndMove/GrabAndMove/main.cpp#L3326-L3353
[ScreenRuler-Entry]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/MeasureTool/MeasureToolUI/MeasureToolXAML/App.xaml.cs#L50-L76
[PowerDisplay-Entry]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/powerdisplay/PowerDisplay/PowerDisplayXAML/App.xaml.cs#L153-L195
[LightSwitch-Entry]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/LightSwitch/LightSwitchService/LightSwitchService.cpp#L36-L73
[LightSwitch-CLI]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/LightSwitch/LightSwitch.Cli/Program.cs#L117-L123
[LightSwitch-Theme]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/LightSwitch/LightSwitchLib/ThemeHelper.cpp#L93-L106
[MouseUtils-Host]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/MouseUtils/FindMyMouse/dllmain.cpp#L62-L81
[MouseJump-Entry]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/MouseUtils/MouseJump.WinUI3/Program.cs#L47-L78
[WindowHopper-Host]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/AltWindowCycle/dllmain.cpp#L180-L230
[AdvancedPaste-CLI]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/AdvancedPaste/AdvancedPaste.CLI/Program.cs#L96-L104
[AdvancedPaste-GUI]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/AdvancedPaste/AdvancedPaste/AdvancedPasteXAML/App.xaml.cs#L104-L126
[NewPlus-Host]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/NewPlus/NewShellExtensionContextMenu/powertoys_module.cpp#L123-L140
[NewPlus-Registration]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/NewPlus/NewShellExtensionContextMenu/RuntimeRegistration.h#L14-L31
[PowerRename-Entry]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/powerrename/PowerRenameUILib/PowerRenameXAML/App.xaml.cpp#L130-L149
[PowerRename-Registration]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/powerrename/dll/RuntimeRegistration.h#L14-L33
[Peek-Entry]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/peek/Peek.UI/PeekXAML/App.xaml.cs#L112-L136
[Workspaces-Entry]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/Workspaces/WorkspacesEditor/App.xaml.cs#L79-L109
[ShortcutGuide-Entry]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/ShortcutGuide/ShortcutGuide.Ui/Program.cs#L52-L55
[ShortcutGuide-Events]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/ShortcutGuide/ShortcutGuide.Ui/ShortcutGuideXAML/App.xaml.cs#L93-L113
[Native-DataRoot]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/common/SettingsAPI/settings_helpers.cpp#L14-L25
[Managed-DataRoot]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/settings-ui/Settings.UI.Library/SettingPath.cs#L34-L64
[Managed-Logs]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/common/ManagedCommon/Logger.cs#L75-L87
[ImageResizer-Data]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/imageresizer/ui/Properties/Settings.cs#L65
[Explorer-Manifest]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/imageresizer/ImageResizerContextMenu/AppxManifest.xml#L38-L48
