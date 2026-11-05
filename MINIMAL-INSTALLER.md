# PowerToys minimal installer

This branch is based on Microsoft's official stable tag `v0.102.3001`
(`a00b2bce7403f0a48efe5cbb6671074e01f27824`), released on October 27, 2026.
It uses product version `0.102.3001.0` and the internal `private` update channel.
The custom build is unsigned and provides a German (`de-DE`) interface.

The current x64 per-user MSI is available under the retained release tag
`minimal-main-2026-09-02`. [Release notes](https://github.com/naturian/PowerToys/releases/tag/minimal-main-2026-09-02)
and [MSI download](https://github.com/naturian/PowerToys/releases/download/minimal-main-2026-09-02/PowerToysUserSetup-0.102.3001.0-x64.msi).

The generated MSI includes these 20 module groups.

| Module | Internal key |
| --- | --- |
| FancyZones | `FancyZones` |
| Always On Top | `AlwaysOnTop` |
| Crop And Lock | `CropAndLock` |
| Text Extractor | `TextExtractor` / `PowerOCR` |
| Workspaces | `Workspaces` |
| Image Resizer | `ImageResizer` |
| File Locksmith | `FileLocksmith` |
| PowerRename | `PowerRename` |
| Peek | `Peek` |
| Color Picker | `ColorPicker` |
| Screen Ruler | `ScreenRuler` / `MeasureTool` |
| Power Display | `PowerDisplay` |
| Light Switch | `LightSwitch` |
| Mouse Utilities | `MouseUtils` |
| Window Hopper | `WindowHopper` / `AltWindowCycle` |
| Advanced Paste | `AdvancedPaste` |
| New+ | `NewPlus` |
| ZoomIt | `ZoomIt` |
| Grab And Move | `GrabAndMove` |
| Shortcut Guide | `ShortcutGuide` |

`MouseUtils` includes Cursor Wrap, Find My Mouse, Mouse Highlighter, Mouse Jump, and
Mouse Pointer Crosshairs. The output filter removes unselected modules before WiX harvesting.

Advanced Paste blocks Paste with AI, including attempts to enable it through existing or
manually edited settings. The shared Advanced Paste engine blocks all AI providers,
including local models. The Advanced Paste CLI and PATH shims are excluded from the installer.
CursorHide and Mouse Button Lock are also excluded. ZoomIt's offline dictation follows the
upstream default of disabled. Users can enable it, which gives it access to the microphone.

## Module selection

The selection is defined in `installer/PowerToysSetupVNext/selected-modules.txt`.
The central module mapping is in `installer/PowerToysSetupVNext/Modules-Database.ps1`.

```text
selected-modules.txt --> Configure-Modules.ps1 --> Runner module list
                                              +-> Settings dashboard
                                              +-> WiX component groups
                                              +-> WiX source files
Modules-Database.ps1 --> filter-minimal-modules.ps1 --> filtered build output
```

Rebuild after editing `selected-modules.txt`. The database marks `CmdPal`, `CmdNotFound`,
and `Run` as unavailable for this pipeline because their packaging requires further integration.

## Build

Run from the repository root.

```powershell
tools\build\build-minimal-installer.ps1
```

The script uses the version from the Microsoft release above, restores dependencies, builds
the solution with test projects excluded, builds the diagnostic tools, filters unselected
modules, and produces a German per-user MSI.

To repeat the filtering and installer stages after a successful solution build, run

```powershell
tools\build\build-minimal-installer.ps1 -SkipSolutionBuild
```

The output is `installer/PowerToysSetupVNext/<Platform>/<Configuration>/UserSetup/*.msi`.

The pipeline uses the ignored package cache `.build-cache/nuget` and forces dependency
restoration so that restore and compilation use the same packages.

Prerequisites follow the upstream repository, including Visual Studio 2022 17.4+ or Visual
Studio 2026 with the C++ desktop workload, the required Windows and .NET SDKs, and initialized
submodules. The selected upstream version determines the required toolchain.

## Module filtering

The VNext installer harvests the shared Release output directory. Filtering therefore covers
the output files as well as the installer definitions.

1. `filter-minimal-modules.ps1` removes files and directories for unselected utilities.
2. `Product.wxs` references infrastructure and selected module groups.
3. `PowerToysInstallerVNext.wixproj` compiles the required `.wxs` files.
4. `src/runner/main.cpp` loads the packaged module DLLs.
5. The Settings dashboard and navigation expose the installed areas.

Shared Settings dependencies are included. Selecting Peek also enables the Monaco and
File Explorer Preview component groups.

## Localization

The public source tree provides English PowerToys resources by default. This fork includes
complete `de-DE` RESW/RESX sources. `import-german-localization.ps1` extracts them from the
signed Microsoft `v0.102.3001` build and maps them to the resource keys of the corresponding
source version. It imports resource source text, preserving consistent XAML and assembly versions.

Color Picker and Text Extractor use WinUI RESW/PRI resources. When updating the Microsoft
baseline, import German sources from a closely matching official package and verify the result.

```powershell
installer\PowerToysSetupVNext\import-german-localization.ps1 -OfficialRoot <extracted-PowerToys-directory>
tools\build\test-minimal-release.ps1
```

The build stops if a German resource key is missing. After compilation, the pipeline also
checks the generated PRI files and WPF satellite assemblies.

## Relevant files

- `installer/PowerToysSetupVNext/selected-modules.txt` defines the active selection.
- `installer/PowerToysSetupVNext/Modules-Database.ps1` contains the module metadata.
- `installer/PowerToysSetupVNext/Configure-Modules.ps1` generates the selection-dependent files.
- `installer/PowerToysSetupVNext/filter-minimal-modules.ps1` filters the build output.
- `installer/PowerToysSetupVNext/import-german-localization.ps1` updates German resource sources.
- `tools/build/build-minimal-installer.ps1` runs the complete pipeline.
- `tools/build/test-minimal-release.ps1` checks release and localization regressions.
