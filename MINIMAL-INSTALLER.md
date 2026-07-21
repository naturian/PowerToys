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
3. **`src/runner/main.cpp`** – die fest codierte Modulliste (`knownModules`) MUSS auf die 9
   gewünschten Module reduziert werden. Sonst versucht der Runner beim Start die (nicht
   paketierten) DLLs der entfernten Module zu laden und wirft „DLL fehlt"-Fehler.

## Bauen
```powershell
# Aus dem Repo-Wurzelverzeichnis, in einer Developer-PowerShell für VS 2022:
tools\build\build-minimal-installer.ps1                 # englischer Per-User-MSI
```
Das Skript initialisiert die Submodule, baut die benötigten Projekte + Diagnose-Tools,
filtert den Ausgabeordner und baut den MSI.

Für **Deutsch** + **maschinenweit** zusätzlich (siehe unten):
```powershell
# 1. Deutsche Lokalisierung aus offiziellem Release überlagern (einmalig extrahieren, s.u.)
installer\PowerToysSetupVNext\apply-german-localization.ps1 -OfficialRoot <extrahiertes-PowerToys>
# 2. Filter + Harvest + Machine-MSI (PerUser=false)  -> siehe "Deutsch" unten
```
Ergebnis (maschinenweit): `installer\PowerToysSetupVNext\x64\Release\MachineSetup\PowerToysSetup-0.0.1-x64.msi`

> Referenz-Build: Solution-Build der benötigten Projekte + `runner` + `PowerToys.Settings`,
> danach Filter + WiX. CmdPal (AOT-Fehler) und ZoomIt (Toolset v145) werden nicht gebaut –
> beide sind nicht gewünscht.

## Deutsch, Geister-Seiten, maschinenweit

**Deutsche Oberfläche.** Die übersetzten Ressourcen liegen nicht im öffentlichen Repo, werden
aber aus einem **offiziellen PowerToys-v0.99.1-Release** entnommen:
- WinUI3-Module (Settings, Peek, FileLocksmith, PowerRename, ImageResizer): multilinguale
  `.pri`-Dateien (enthalten alle Sprachen inkl. Deutsch) – per Overlay. **→ Deutsch.**
- WPF-Modul-Editoren (FancyZones-Editor, TextExtractor, Workspaces-Editor): **bleiben Englisch.**
  Die de-DE-Satelliten des offiziellen Release sind Version 0.99.1.0, die lokal gebauten
  WPF-Module aber 0.0.1.0 → .NET-Versions-Mismatch würde diese Editoren abstürzen lassen.
  Für vollständiges Deutsch auch dort müsste die Build-Version auf 0.99.1 gesetzt und die
  WPF-Module neu gebaut werden (siehe `src/Version.props`; berührt zusätzlich die DSC-Pfade).

Extraktion des offiziellen Release:
```powershell
wix burn extract PowerToysSetup-0.99.1-x64.exe -o out -oba ba
msiexec /a out\WixAttachedContainer\PowerToysSetup-0.99.1-x64.msi /qn TARGETDIR=<dir>
# -> OfficialRoot = <dir>\PFiles64\PowerToys
```
Danach `apply-german-localization.ps1 -OfficialRoot <dir>\PFiles64\PowerToys`.

**Geister-Seiten ausgeblendet.** Die Settings-Navigation blendet die Einträge nicht
installierter Module aus. Umgesetzt im **Code-Behind** (`ShellPage.xaml.cs` →
`HideUninstalledModules()`), NICHT in der XAML – denn die kompilierte XAML (`ShellPage.xbf`)
ist als `EmbeddedData` in der `.pri` gespeichert; würde man die XAML ändern, ginge die
Änderung beim Überlagern der deutschen `.pri` verloren. Der Code-Behind-Weg ist mit dem
`.pri`-Overlay kompatibel.

**Maschinenweit.** `/p:PerUser=false` erzeugt `MachineSetup\PowerToysSetup-*.msi`
(Scope per-machine, ALLUSERS=1) – für Unternehmens-Deployment (SCCM/Intune/GPO-Softwareverteilung).

## Voraussetzungen
- Visual Studio 2022 (17.14+) mit „Desktopentwicklung mit C++" (inkl. Spectre-Libs, ATL)
- Windows SDK 10.0.19041.0
- .NET 9 SDK
- WiX 5 (kommt per NuGet über das `.wixproj`)
- `nuget.config`: nuget.org (primär) + CommunityToolkit-Labs-Feed. Der ursprüngliche
  shine-oss-Feed lieferte diverse Runtime-/AOT-Pakete nicht zuverlässig (HTTP 503/401).

## Bekannte Einschränkungen / Hinweise
- **Deutsch stammt aus dem offiziellen Release.** Ohne den Overlay-Schritt ist ein reiner
  Quellcode-Build englischsprachig (Übersetzungen liegen nicht im öffentlichen Repo). Der
  Overlay entnimmt sie dem offiziellen v0.99.1-Release derselben Version (Ressourcennamen
  identisch → kompatibel).
- **Standard-`build-minimal-installer.ps1` erzeugt Englisch/Per-User.** Deutsch + maschinenweit
  erfordern die zwei zusätzlichen Schritte oben.
- **Nur Deutsch + Englisch relevant.** Die überlagerten `.pri` sind zwar multilingual (alle
  Sprachen), die WPF-Satelliten wurden bewusst auf `de-DE` beschränkt.

## Geänderte / neue Dateien
- `installer/PowerToysSetupVNext/Product.wxs` – Feature-Komponentengruppen minimiert + GermanSatellites
- `installer/PowerToysSetupVNext/PowerToysInstallerVNext.wixproj` – Compile-Liste minimiert + German.wxs
- `installer/PowerToysSetupVNext/generateAllFileComponents.ps1` – Run-Harvest übersprungen
- `installer/PowerToysSetupVNext/filter-minimal-modules.ps1` – **neu**, Output-Filter
- `installer/PowerToysSetupVNext/German.wxs` – **neu**, de-DE-Satelliten der WPF-Module
- `installer/PowerToysSetupVNext/apply-german-localization.ps1` – **neu**, PRI/Satelliten-Overlay
- `src/settings-ui/Settings.UI/SettingsXAML/Views/ShellPage.xaml.cs` – Geister-Seiten ausblenden
- `tools/build/build-minimal-installer.ps1` – **neu**, Gesamt-Pipeline
- `nuget.config` – zuverlässige Paketquellen
