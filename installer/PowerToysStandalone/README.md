# Standalone module MSI packages

Each of the ten standalone modules has its own Windows x64, per-machine MSI package.
The binaries install under `%ProgramFiles%\Naturian\PowerToys Modules\<ModuleId>`.
Each package adds an entry under **Start > PowerToys Modules** and a Windows Installed apps
entry. Multiple different modules can be installed together.

Application settings, layouts, history, caches, and logs are created at first user launch
under `%LOCALAPPDATA%\Naturian\PowerToysModules\<ModuleId>\Microsoft\PowerToys`.
The installed `standalone-mode` marker selects this storage. Fresh profiles use German
and enable their selected module subject to GPO restrictions. Advanced Paste AI is blocked.
User settings are retained through repair, upgrade, and uninstall.

The ZIP packages use their `portable-mode` marker and executable-adjacent `Data` directory.
The two package formats have separate settings locations. Turn off other copies of the same
tool before starting one, or configure distinct shortcuts.

## Configuration Manager deployment

Create an application using **Windows Installer (*.msi file)** and select the desired MSI.
Configure its user experience to **Install for system**, **Whether or not a user is logged on**,
and **Hidden**. Windows x64 and Windows 10 version 2004 or newer are required.
Use the product code imported from the MSI as its Windows Installer detection method.
The release's `sccm-deployment.json` and `sccm-deployment.csv` list each product code,
upgrade code, version, SHA-256, and installation and removal command.
[Microsoft application deployment documentation](https://learn.microsoft.com/en-us/intune/configmgr/apps/deploy-use/create-applications).

For example, install FancyZones silently with logging.

```cmd
msiexec.exe /i "PowerToys-FancyZones-Standalone-0.102.3001.0-x64.msi" /qn /norestart /L*v "%WINDIR%\Temp\PowerToys-FancyZones-install.log"
```

Remove it using the product code from the deployment metadata.

```cmd
msiexec.exe /x {PRODUCT-CODE-FROM-DEPLOYMENT-METADATA} /qn /norestart /L*v "%WINDIR%\Temp\PowerToys-FancyZones-uninstall.log"
```

Standard Windows Installer return codes apply, including `0` for success, `3010` for success
with a reboot required, `1618` for another installation in progress, and `1603` for failure.
Configure return-code handling in Configuration Manager accordingly. A running module can
hold application files open. Close it before maintenance, or allow Configuration Manager
to handle the required reboot. The package suppresses automatic restarts and uses
`MSIRESTARTMANAGERCONTROL=DisableShutdown`.

MSI product and upgrade identities are distinct for each module. Upgrade codes and file
component GUIDs remain stable across versions. A newer product version performs a transactional
major upgrade and rejects a downgrade. The binary version is `0.102.3001.0`, and the MSI
product version is `0.102.3001`. Windows Installer compares three version fields.
[Microsoft versioning rules](https://learn.microsoft.com/en-us/windows/win32/msi/productversion).

The `HKLM\SOFTWARE\Naturian\PowerToysModules\<ModuleId>` registry key also records the
binary version, product code, and installation location in the 64-bit registry view.

Install and uninstall execute Windows Installer file, shortcut, and registry operations.
Users launch the tool from their own session after installation. Dependencies for Windows OCR,
WebView2 previews, preview handlers, and monitor hardware follow the module documentation.
These custom builds are unsigned prereleases.

## Build and verify

Run the build scripts in PowerShell 7. Build the complete module payload first, then package
its successful output.

```powershell
.\tools\portable\build-portable.ps1 -OutputRoot G:\PowerToys\artifacts\portable\standalone-payload
.\tools\portable\build-standalone-msi.ps1 `
    -BuildRoot G:\PowerToys\artifacts\portable\standalone-payload `
    -OutputRoot G:\PowerToys\deliverables\standalone-msi
```

Use `-Modules FancyZones,Peek` to select a subset. `-Resume` explicitly allows reusing an
MSI output directory. Every invocation creates fresh staging directories. The builder uses
the existing WiX 5.0.2 SDK and repository build wrapper, validates each actual MSI database,
and generates deployment metadata and hashes after successful packaging.

The packager uses neutral MSI file-language metadata for MUI resources and oversized
multilingual values. Application resource selection uses the locale directories and German
profile defaults. After normalization, the complete set of ICE checks runs on the final MSI.

`tools/portable/test-standalone-msi.ps1` verifies the x64 per-machine scope, German language,
file and component graph, registry ownership, Start menu target, upgrade detection, and
custom-action types. Runtime data tests cover isolated profiles, concurrent first starts,
seed retries, and malformed module identities. Lifecycle testing on a clean target remains
part of deployment validation.
