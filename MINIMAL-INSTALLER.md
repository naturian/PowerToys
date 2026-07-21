# PowerToys – Minimierter Installer

Fork von PowerToys **v0.99.1**, der einen MSI-Installer mit **nur diesen 9 Modulen** erzeugt:

| Modul (deutsch) | intern |
|---|---|
| Textextraktor | PowerOCR |
| Always on Top | AlwaysOnTop |
| Zuschneiden und Sperren | CropAndLock |
| FancyZones | FancyZones |
| Arbeitsbereiche | Workspaces |
| Bildgrößenänderung | ImageResizer |
| File Locksmith | FileLocksmith |
| PowerRename | PowerRename |
| Vorschau (Peek) | Peek |

Alle übrigen Module (Command Palette, PowerToys Run, Color Picker, Awake, Hosts,
Keyboard Manager, Mouse-Utilities, Mouse Without Borders, Advanced Paste, Quick Accent,
Screen Ruler, Registry Preview, Shortcut Guide, New+, ZoomIt, Environment Variables,
LightSwitch, PowerDisplay, Datei-Explorer-Vorschauhandler, …) werden **nicht paketiert
und nicht installiert** – ihre Binaries sind nicht im MSI enthalten.

## Warum v0.99.1?
Ab v0.100 zielt PowerToys auf **.NET 10 / MSBuild 18 (Visual Studio 2026)**. v0.99.1 ist die
letzte stabile Version auf **.NET 9**, die sich mit **Visual Studio 2022** bauen lässt.

## Wie der Ausschluss funktioniert
Der VNext-Installer „harvestet" den gesamten Build-Ausgabeordner: `BaseApplicationsFiles`
und `WinUI3ApplicationsFiles` sammeln **alle** Binaries aus `x64\Release\` bzw.
`x64\Release\WinUI3Apps\` ein. Das Entfernen von `ComponentGroupRef` allein genügt daher
nicht. Der Ausschluss erfolgt über zwei Hebel:

1. **`installer/PowerToysSetupVNext/filter-minimal-modules.ps1`** löscht die Binaries nicht
   gewünschter Module aus dem Ausgabeordner, **bevor** der Harvest läuft. Drei von der
   Settings-UI zur Laufzeit benötigte DLLs bleiben erhalten (`PowerToys.MouseJump.Common.dll`,
   `PowerToys.ZoomItSettingsInterop.dll`, `PowerDisplay.Models.dll`).
2. **`Product.wxs`** referenziert nur noch die Komponentengruppen der gewünschten Module +
   Infrastruktur; nicht gewünschte Modul-`.wxs` sind aus der Compile-Liste des `.wixproj`
   entfernt. `FileExplorerPreview.wxs` bleibt erhalten – es enthält **nur** die Monaco-Editor-
   Assets (`index.html` etc.), die **Peek** für die Quellcode-Vorschau braucht.

## Bauen
```powershell
# Aus dem Repo-Wurzelverzeichnis, in einer Developer-PowerShell für VS 2022:
tools\build\build-minimal-installer.ps1
```
Das Skript initialisiert die Submodule, baut die benötigten Projekte + Diagnose-Tools,
filtert den Ausgabeordner und baut den MSI. Ergebnis:
`installer\PowerToysSetupVNext\x64\Release\UserSetup\PowerToysUserSetup-0.0.1-x64.msi`

> Referenz-Build: Solution-Build der benötigten Projekte + `runner` + `PowerToys.Settings`,
> danach Filter + WiX. CmdPal (AOT-Fehler) und ZoomIt (Toolset v145) werden nicht gebaut –
> beide sind nicht gewünscht.

## Voraussetzungen
- Visual Studio 2022 (17.14+) mit „Desktopentwicklung mit C++" (inkl. Spectre-Libs, ATL)
- Windows SDK 10.0.19041.0
- .NET 9 SDK
- WiX 5 (kommt per NuGet über das `.wixproj`)
- `nuget.config`: nuget.org (primär) + CommunityToolkit-Labs-Feed. Der ursprüngliche
  shine-oss-Feed lieferte diverse Runtime-/AOT-Pakete nicht zuverlässig (HTTP 503/401).

## Bekannte Einschränkungen
- **Nur Englisch.** Die übersetzten Satelliten-DLLs (`*.resources.dll`) werden ausschließlich
  von Microsofts interner Lokalisierungs-Pipeline erzeugt und liegen **nicht** im öffentlichen
  Repo. Ein lokaler/Community-Build ist daher zwangsläufig englischsprachig
  (`Resources.wxs` wurde deshalb aus dem Paket entfernt).
- **Geister-Seiten in den Einstellungen.** Die Settings-UI ist monolithisch und zeigt auch
  Seiten für nicht installierte Module. Da deren Binaries fehlen, lädt der Runner sie nicht –
  die Seiten sind ohne Funktion. Die eigentliche Anforderung („Module nicht installiert") ist
  erfüllt (keine Modul-Binaries auf dem System).
- **Per-User-Installer.** Für maschinenweite Installation (Unternehmens-Deployment)
  `/p:PerUser=false` verwenden – erzeugt `MachineSetup\PowerToysMachineSetup-*.msi`.

## Geänderte Dateien
- `installer/PowerToysSetupVNext/Product.wxs` – Feature-Komponentengruppen minimiert
- `installer/PowerToysSetupVNext/PowerToysInstallerVNext.wixproj` – Compile-Liste minimiert
- `installer/PowerToysSetupVNext/generateAllFileComponents.ps1` – Run-Harvest übersprungen
- `installer/PowerToysSetupVNext/filter-minimal-modules.ps1` – **neu**, Output-Filter
- `tools/build/build-minimal-installer.ps1` – **neu**, Gesamt-Pipeline
- `nuget.config` – zuverlässige Paketquellen
