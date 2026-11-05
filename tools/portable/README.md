# Portable PowerToys modules

Experimental Windows x64 packages based on **0.102.3001.0**, developed on branch
`codex/portable-first-modules` in `naturian/PowerToys`. The minimal installer has its own
release. [Portable downloads](https://github.com/naturian/PowerToys/releases/tag/portable-v0.102.3001.0)
and [minimal installer](https://github.com/naturian/PowerToys/releases/tag/minimal-main-2026-09-02).

## Usage

Extract the complete ZIP into a writable directory. Include `portable-mode`,
`portable-module.json`, and all bundled runtime files.

| Package | Entry point | Controls |
| --- | --- | --- |
| FancyZones | `PowerToys.Portable.exe` | Tray controls, original Settings page, and layout editor |
| Color Picker | `PowerToys.Portable.exe` | Tray controls, original Settings page, and color editor |
| Text Extractor | `PowerToys.Portable.exe` | Tray controls, original Settings page, and text capture |
| Image Resizer | `PowerToys.Portable.exe` | Tray controls, original size and encoding settings, and file picker |
| Power Display | `PowerToys.PowerDisplay.exe` | Native tray menu with access to its original Settings page |
| Always On Top | `PowerToys.Portable.exe` | Tray controls, original pinning rules, and keyboard shortcut |
| File Locksmith | `PowerToys.Portable.exe` | File and folder pickers, locking-process list, and original Settings page |
| Peek | `PowerToys.Portable.exe` | File and folder pickers, plus a keyboard shortcut for the Explorer selection |
| Crop And Lock | `PowerToys.Portable.exe` | Tray controls and shortcuts for thumbnail, reparent, and screenshot modes |
| Advanced Paste | `PowerToys.Portable.exe` | Tray controls, standard paste formats, and additional actions with AI blocked |

The German Settings interface shows the packaged module. Double-click the tray icon to open
Settings. Its context menu opens the tool and exits the portable host. Closing the Settings
window leaves the tool running in the tray. Power Display uses its native tray, including
brightness controls. Opening Settings from within a tool also opens its local Settings interface.

Always On Top uses **Win+Ctrl+T** by default. Crop And Lock uses **Win+Ctrl+Shift+T/R/S**
for thumbnail, reparent, and screenshot modes. Peek uses **Ctrl+Space** for selected Explorer
files, with file and folder pickers also available through the tray. The original Settings pages
configure these shortcuts locally.

File Locksmith scans explicitly selected files or folders. The user can end a process through
the End task action or explicitly restart the tool as administrator. Advanced Paste registers
its four basic paste shortcuts and visible additional actions that work without AI. AI,
grammar, coaching, custom AI shortcuts, model preparation, and saved AI credential migration
are blocked in portable mode.

Settings are saved automatically. Fresh packages enable their module subject to existing GPO
restrictions. Application data, color history, layouts, and logs are stored under
`Data/Microsoft/PowerToys`. Include that directory in backups. Exit every tool through its
tray before moving or deleting the package. Complete active image processing before exiting.

## Limitations

- Packages run from their extracted directory. Updates are installed by manually extracting
  a new package. Existing GPO restrictions apply.
- Turn off installed FancyZones before starting its portable counterpart. Both instances can
  affect the same windows and shortcuts. Color Picker and Text Extractor can also encounter
  global shortcut conflicts.
- Text Extractor requires an installed Windows OCR language. Power Display requires compatible
  monitors. Brightness and profile changes affect the connected hardware.
- Browser-based Peek previews require an installed Microsoft Edge WebView2 runtime. Additional
  formats depend on installed Windows preview handlers.
- Windows manages its own clipboard, execution history, and other operating-system data.
- The original Settings application is a shared dependency, which increases package size.
- Controlling elevated windows can require elevated privileges. Elevation in File Locksmith
  is an explicit user action.
- Builds are unsigned prereleases. The release notes describe the tests performed. Corporate
  certification, full hardware coverage, and multi-monitor validation require separate checks.

## Build and verification

Run from the repository root in PowerShell.

```powershell
.\tools\portable\build-portable.ps1 -OutputRoot G:\PowerToys\artifacts\portable\my-build
```

Use `-Modules FancyZones,ColorPicker` to build a subset. The builder uses the repository's
standard build scripts, checks dependencies, publishes the .NET and Windows App SDK runtimes,
and generates a `package-manifest.json` containing file sizes and SHA-256 hashes for each package.
Reusing an output directory requires `-Resume`. Build releases in a fresh directory.

The isolated tests are in `tools/portable/tests`. Build them with `tools/build/build.ps1`,
then run them with Visual Studio's `vstest.console.exe`. They cover data paths, write failures,
event names, and fixed package identities, including mutated inputs.
`test-portable-startup.ps1` checks actual Settings windows, second launches, and complete
shutdown, including shutdown immediately after opening the FancyZones editor.
`package-portable.ps1` creates and verifies ZIPs with fresh profiles. Report hardware and
multi-monitor validation separately.

## Implementation

`src/common/Portable/PortableData.cs` and `src/common/utils/portable_mode.h` enable local
data paths when the marker file is present. Write failures stop startup.

`src/settings-ui/Settings.UI/Portable` implements tray controls and connects to the original
Settings pages. `portable-module.json` selects one of ten fixed package identities.
Instance locks and events are scoped to the package directory. The host accepts settings and
actions for its selected module. Telemetry is disabled in portable mode. File Locksmith,
Peek, and the tests compile the same file-path parser source.

Store and WinGet submissions are restricted to Microsoft's repository. Portable releases in
this fork are published separately as prereleases.
